#!/usr/bin/env python3
"""Consistency guard: keep documents from drifting away from the code.

Docs rot quietly. A README that says "31/31 tests" when the suite has 39, or a
decision index claiming "D1-D41" when there are 62 entries, costs credibility
exactly where a reviewer looks first. Humans cannot catch this reliably, so it
is automated.

Checks (all read-only):
  1. test-count claims   "39/39" style claims in current docs must match the
                         real `moon test` total
  2. ADR numbering       docs/decisions.md headings must be D1..DN with no gaps
                         and no duplicates
  3. relative links      `](something.md)` targets must exist

Snapshot files (devlog, sent letters, dated reports) are EXEMPT from check 1:
they record a moment and rewriting them would falsify the record. They are
listed in SNAPSHOT_FILES below, and the script prints which files it skipped so
the exemption is visible rather than silent.

Usage: python tools/consistency.py [--project DIR] [--json]
Exit: 0 = no findings, 1 = at least one FAIL, 2 = bad invocation.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

# Records of a point in time. Their numbers were true when written; editing them
# would be rewriting history rather than fixing drift.
SNAPSHOT_FILES = {
    "docs/devlog.md",
    "docs/reply-to-committee.md",
    "docs/reports/independent-verification.md",
}

# A document can declare itself a dated record by putting this marker anywhere
# in it, optionally with a reason:  <!-- consistency:snapshot: why -->
# Its numbers were true when written; rewriting them would falsify the record.
SNAPSHOT_MARKER = "consistency:snapshot"

# A single line can opt out with this marker, for prose that QUOTES a stale
# number on purpose ("the README still said 31/31 tests ..."). Without it, the
# tool would forbid ever writing about the bug it exists to catch.
LINE_IGNORE = "consistency:ignore"

TEXT_SUFFIXES = {".md"}


def out(msg=""):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    print(msg)


def tracked_markdown(root: Path):
    """Tracked markdown files, or a tree walk when git is unavailable."""
    try:
        res = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"],
            capture_output=True,
            check=True,
        )
        names = [p for p in res.stdout.decode("utf-8", "replace").split("\0") if p]
        return sorted(root / n for n in names if Path(n).suffix in TEXT_SUFFIXES)
    except (OSError, subprocess.CalledProcessError):
        return sorted(root.rglob("*.md"))


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def actual_test_total(root: Path):
    """Total tests reported by `moon test`, or None when unavailable."""
    moon = None
    for candidate in ("moon", str(Path.home() / ".moon" / "bin" / "moon.exe")):
        try:
            res = subprocess.run(
                [candidate, "test", "--target", "native"],
                cwd=root,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=900,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        moon = res
        break
    if moon is None:
        return None
    total = None
    for line in (moon.stdout or "").splitlines() + (moon.stderr or "").splitlines():
        m = re.search(r"Total tests:\s*(\d+),\s*passed:\s*(\d+)", line)
        if m:
            total = int(m.group(1))
    return total


def check_test_counts(root: Path, total):
    """Claims like `39/39` must equal the real total."""
    if total is None:
        return ("SKIP", "could not run `moon test`; test-count claims unchecked")
    findings = []
    scanned = 0
    skipped = []
    # A bare N/N is ambiguous (acceptance rows, seed sweeps, fixture counts).
    # Only a number sitting RIGHT NEXT TO a test word counts as a claim: a
    # word appearing elsewhere on the line is not enough, or the check produces
    # noise and then gets switched off - worse than not having it.
    # Two separate patterns: backreferences are numbered globally, so a single
    # alternation cannot reuse \1 for its second branch (that silently made this
    # check scan zero claims - caught by printing the scanned count).
    claim_res = [
        re.compile(r"(?:moon\s*test|测试|用例|tests?)\s*[:：]?\s*[^\d\n]{0,8}(\d{1,5})/\1", re.I),
        re.compile(r"(\d{1,5})/\1\s*(?:个|项)?\s*(?:test|测试|用例)", re.I),
        # Plain "N 个测试" / "N tests" claims. Added after a registration
        # document claimed "115 个测试" while the suite had 116: that form is
        # just as much a claim as "115/115" and was slipping through.
        # "N 个测试文件" counts FILES, not tests - a false positive that only
        # showed up in practice, hence the negative lookahead.
        re.compile(r"(\d{1,5})\s*(?:个|项)\s*(?:单元法?)?测试(?!\s*(?:文件|点|例|处))", re.I),
        re.compile(r"\b(\d{1,5})\s+(?:unit\s+)?tests?\b", re.I),
    ]
    for doc in tracked_markdown(root):
        rel = doc.relative_to(root).as_posix()
        body = read(doc)
        # The marker must be a standalone HTML-comment line. Matching it as a
        # substring exempted any document that merely DESCRIBED the mechanism
        # (an ADR in this very project did that, silencing the whole file).
        declares_snapshot = any(
            line.strip().startswith("<!-- consistency:snapshot")
            for line in body.splitlines()
        )
        if rel in SNAPSHOT_FILES or declares_snapshot:
            skipped.append(rel)
            continue
        for lineno, line in enumerate(body.splitlines(), 1):
            if LINE_IGNORE in line:
                continue
            hits = [int(m.group(1)) for pattern in claim_res for m in pattern.finditer(line)]
            for value in hits:
                # ignore obviously unrelated ratios (dates, ports, byte sizes)
                if value < 2 or value > 100_000:
                    continue
                scanned += 1
                if value != total:
                    findings.append(f"{rel}:{lineno}: claims {value}/{value}, suite has {total}")
    if findings:
        return ("FAIL", "; ".join(findings[:6]))
    note = f"{scanned} claim(s) match {total}"
    if skipped:
        note += f"; snapshots exempt: {', '.join(skipped)}"
    return ("PASS", note)


def check_adr_numbering(root: Path):
    """docs/decisions.md headings must be D1..DN, no gaps, no duplicates."""
    path = root / "docs" / "decisions.md"
    if not path.is_file():
        return ("SKIP", "no docs/decisions.md")
    numbers = []
    for line in read(path).splitlines():
        m = re.match(r"^##\s+D(\d+)\b", line)
        if m:
            numbers.append(int(m.group(1)))
    if not numbers:
        return ("SKIP", "no `## D<N>` headings found")
    seen = {}
    problems = []
    for n in numbers:
        seen[n] = seen.get(n, 0) + 1
    for n, count in sorted(seen.items()):
        if count > 1:
            problems.append(f"D{n} appears {count} times")
    expected = set(range(1, max(numbers) + 1))
    missing = sorted(expected - set(seen))
    if missing:
        problems.append(f"missing {missing}")
    if problems:
        return ("FAIL", "; ".join(problems) + f" (max D{max(numbers)}, {len(numbers)} headings)")
    return ("PASS", f"D1..D{max(numbers)}, {len(numbers)} headings, no gaps or duplicates")


def check_links(root: Path):
    """Relative markdown links must resolve."""
    broken = []
    checked = 0
    link_re = re.compile(r"\]\(([^)\s#]+\.md)(?:#[^)]*)?\)")
    for doc in tracked_markdown(root):
        rel = doc.relative_to(root).as_posix()
        for lineno, line in enumerate(read(doc).splitlines(), 1):
            for m in link_re.finditer(line):
                target = m.group(1)
                if target.startswith(("http://", "https://", "mailto:")):
                    continue
                checked += 1
                if not (doc.parent / target).exists():
                    broken.append(f"{rel}:{lineno}: -> {target}")
    if broken:
        return ("FAIL", "; ".join(broken[:6]))
    return ("PASS", f"{checked} relative links resolve")


def check_documented_transcript(root: Path):
    """Lines quoted from a tool's output must actually appear in that output.

    README shows a real transcript; hand-edited examples rot the moment the
    program changes a label (this already happened once: the block said
    `reconciled=true` while the program prints `matches=true`). Annotation
    suffixes are stripped at `<-` so the sample can carry explanations.
    """
    readme = root / "README.md"
    cmd = ["moon", "run", "adapters/mqtt/bin", "--target", "native"]
    if not readme.is_file() or not (root / "adapters" / "mqtt").is_dir():
        return ("SKIP", "no README quickstart transcript to verify")
    body = read(readme)
    marker = "你会拿到什么"
    if marker not in body:
        return ("SKIP", "README has no \"what you get\" transcript block")
    after = body.split(marker, 1)[1]
    blocks = re.findall(r"```[a-z]*\n(.*?)```", after, re.S)
    if not blocks:
        return ("SKIP", "no fenced block after the transcript heading")
    quoted = []
    for raw in blocks[0].splitlines():
        line = raw.split("<-")[0].strip()
        # skip the command echo and pure prose lines
        if line and not line.startswith("moon "):
            quoted.append(line)
    try:
        res = subprocess.run(
            cmd, cwd=root, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=600,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return ("SKIP", f"could not run the transcript command: {exc}")
    actual = res.stdout + res.stderr
    missing = [q for q in quoted if q not in actual]
    if missing:
        return ("FAIL", "quoted lines absent from real output: " + "; ".join(missing[:4]))
    return ("PASS", f"{len(quoted)} quoted lines found in the real transcript")


def check_adr_count_claims(root: Path, actual):
    """Claims like "49 条 ADR" must match the real number of D-headings.

    Same failure mode as test counts: the number is easy to state and easy to
    forget. Only applied to files that are not snapshots.
    """
    path = root / "docs" / "decisions.md"
    if not path.is_file():
        return ("SKIP", "no docs/decisions.md")
    findings = []
    scanned = 0
    # "N 条 ADR" is an exact claim; "N+ 条 ADR" is a floor. Floors exist because
    # an exact count in prose breaks on every single new ADR: adding one entry
    # invalidated four sites in practice. A floor stays true for a long stretch
    # and can still be verified (claimed <= actual).
    pattern = re.compile(r"(\d{1,4})(\+?)\s*(?:条|个)\s*ADR", re.I)
    for doc in tracked_markdown(root):
        rel = doc.relative_to(root).as_posix()
        body = read(doc)
        if rel in SNAPSHOT_FILES or any(
            line.strip().startswith("<!-- consistency:snapshot") for line in body.splitlines()
        ):
            continue
        for lineno, line in enumerate(body.splitlines(), 1):
            if LINE_IGNORE in line:
                continue
            for m in pattern.finditer(line):
                scanned += 1
                claimed = int(m.group(1))
                is_floor = m.group(2) == "+"
                if is_floor and claimed > actual:
                    findings.append(
                        f"{rel}:{lineno}: claims {claimed}+ ADRs, index only has {actual}"
                    )
                elif not is_floor and claimed != actual:
                    findings.append(f"{rel}:{lineno}: claims {claimed} ADRs, index has {actual}")
    if findings:
        return ("FAIL", "; ".join(findings[:5]))
    if scanned == 0:
        return ("SKIP", "no ADR-count claims in current docs")
    return ("PASS", f"{scanned} ADR-count claim(s) consistent with {actual} entries")


def check_registry_facts(root: Path):
    """Compare claims about the PUBLISHED package against the registry itself.

    Written after a false claim survived in six documents: they said 0.3.1 was
    unpublished while the registry had carried it for days, and quoted 35
    downloads when it was 44. The root cause was trusting an internal document
    to describe the outside world. This asks the outside world.

    Network-dependent by nature: any transport problem is SKIP, never FAIL.
    """
    moon_mod = root / "moon.mod"
    adoption = root / "docs" / "adoption.md"
    if not moon_mod.is_file() or not adoption.is_file():
        return ("SKIP", "no moon.mod / docs/adoption.md to cross-check")
    m = re.search(r'^name\s*=\s*"([^"]+)"', read(moon_mod), re.M)
    if not m:
        return ("SKIP", "moon.mod has no name field")
    module = m.group(1)
    try:
        import urllib.request
        req = urllib.request.Request(
            "https://mooncakes.io/api/v0/manifest/" + module,
            headers={"User-Agent": "consistency-check"},
        )
        with urllib.request.urlopen(req, timeout=25) as resp:
            raw = resp.read().decode("utf-8", "replace")
    except Exception as exc:  # any transport problem means SKIP
        return ("SKIP", f"registry unreachable ({type(exc).__name__}); claims not judged")
    versions = sorted(set(re.findall(r'"version"\s*:\s*"([0-9][^"]*)"', raw)))
    downloads = re.findall(r'"downloads"\s*:\s*(\d+)', raw)
    if not versions:
        return ("SKIP", "registry reply had no versions")
    latest = versions[-1]
    body = read(adoption)
    problems = []
    published_claim = re.search(r"已发布版本\s*\|([^|]+)\|", body)
    if published_claim and latest not in published_claim.group(1):
        problems.append(
            "adoption.md lists published versions without the actual latest (" + latest + ")"
        )
    dl_claim = re.search(r"下载\s*\|\s*\*\*(\d+)\*\*", body)
    if dl_claim and downloads:
        claimed, actual = int(dl_claim.group(1)), int(downloads[0])
        if claimed > actual:
            problems.append(
                f"adoption.md claims {claimed} downloads, registry says {actual}"
            )
    if problems:
        return ("FAIL", "; ".join(problems[:4]))
    return (
        "PASS",
        f"registry: latest={latest}, versions={len(versions)}, "
        f"downloads={downloads[0] if downloads else '?'}"
        + ("; claims agree" if (published_claim or dl_claim) else "; no claims to compare"),
    )


def check_version_literals(root: Path):
    """The version the code advertises must equal moon.mod, in exactly one place.

    Found by running the CLI: it printed "docmunch 0.1.0" while the manifest said
    0.3.1, and the MCP server advertised that same stale string to every client.
    A version is a fact about the release, so it gets one source in code plus a
    check that nothing else hard-codes one.
    """
    manifest = root / "moon.mod"
    if not manifest.is_file():
        return ("SKIP", "no moon.mod")
    m = re.search(r'^version\s*=\s*"([^"]+)"', read(manifest), re.M)
    if not m:
        return ("SKIP", "moon.mod has no version field")
    declared = m.group(1)
    allowed = root / "core" / "version.mbt"
    problems = []
    checked = 0
    # Only a literal that IS a version counts; a looser pattern matched the
    # "127.0.0" inside URLs and produced pure noise.
    semver = re.compile(r'"(\d+\.\d+\.\d+)"')
    for mbt in root.rglob("*.mbt"):
        if "_build" in mbt.parts or ".mooncakes" in mbt.parts:
            continue
        rel = mbt.relative_to(root).as_posix()
        for lineno, line in enumerate(read(mbt).splitlines(), 1):
            for found in semver.finditer(line):
                checked += 1
                if mbt != allowed:
                    problems.append(
                        f"{rel}:{lineno}: hard-codes a version ({found.group(0)}); "
                        "use @core.version instead"
                    )
                elif declared not in found.group(0):
                    problems.append(
                        f"{rel}:{lineno}: says {found.group(0)} but moon.mod says {declared}"
                    )
    if problems:
        return ("FAIL", "; ".join(problems[:4]))
    if checked == 0:
        return ("SKIP", "no version literals in .mbt sources")
    return ("PASS", f"{checked} version literal(s) agree with moon.mod ({declared})")


def check_cited_commits(root: Path):
    """Every commit hash quoted in the docs must exist in this repository.

    A changelog that cites a hash which does not exist is worse than one that
    cites nothing: it looks verifiable and is not. Cheap to check, so check it.
    """
    # A shallow clone holds only recent commits, so "this hash does not exist"
    # would be false - the history simply is not there. Say that instead of
    # accusing the docs of citing invented commits.
    try:
        shallow = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--is-shallow-repository"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
    except OSError as exc:
        return ("SKIP", f"cannot inspect repository: {exc}")
    if "true" in (shallow.stdout or "").lower():
        return ("SKIP", "shallow clone: cited commits cannot be verified (use fetch-depth: 0)")
    try:
        res = subprocess.run(
            ["git", "-C", str(root), "rev-list", "--abbrev-commit", "--all"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
    except OSError as exc:
        return ("SKIP", f"cannot list commits: {exc}")
    known = set(res.stdout.split())
    if not known:
        return ("SKIP", "no commits visible (not a git repo?)")
    cited = {}
    for doc in tracked_markdown(root):
        rel = doc.relative_to(root).as_posix()
        for m in re.finditer(r"`([0-9a-f]{7,40})`", read(doc)):
            cited.setdefault(m.group(1), []).append(rel)
    if not cited:
        return ("SKIP", "no commit hashes cited in the docs")
    missing = sorted(h for h in cited if h not in known)
    if missing:
        detail = "; ".join(f"{h} (in {cited[h][0]})" for h in missing[:5])
        return ("FAIL", f"cited commits do not exist: {detail}")
    return ("PASS", f"{len(cited)} cited commit(s) all exist")


def adr_total(root: Path):
    path = root / "docs" / "decisions.md"
    if not path.is_file():
        return 0
    return len([1 for line in read(path).splitlines() if re.match(r"^##\s+D\d+", line)])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default=".")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--skip-build", action="store_true", help="do not run moon test")
    ap.add_argument("--with-registry", action="store_true",
                    help="also cross-check claims about the published package "
                         "against mooncakes.io (network; SKIP when unreachable)")
    args = ap.parse_args()
    root = Path(args.project).resolve()
    if not root.is_dir():
        out(f"not a directory: {root}")
        return 2

    total = None if args.skip_build else actual_test_total(root)
    results = [
        ("Test counts", check_test_counts(root, total)),
        ("ADR numbering", check_adr_numbering(root)),
        ("Links", check_links(root)),
        ("Transcript", check_documented_transcript(root)),
        ("Cited commits", check_cited_commits(root)),
        ("Version", check_version_literals(root)),
        ("ADR counts", check_adr_count_claims(root, adr_total(root))),
    ]
    if args.with_registry:
        results.append(("Registry", check_registry_facts(root)))
    if args.json:
        out(json.dumps([{"check": n, "status": s, "evidence": e} for n, (s, e) in results], ensure_ascii=False))
    else:
        out(f"consistency guard — {root}")
        out()
        for name, (status, evidence) in results:
            out(f"{status:<5} {name:<15} {evidence}")
        out()
        fails = sum(1 for _, (s, _) in results if s == "FAIL")
        out(f"{len(results) - fails} ok, {fails} fail")
    return 1 if any(s == "FAIL" for _, (s, _) in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
