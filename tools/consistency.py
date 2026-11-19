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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default=".")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--skip-build", action="store_true", help="do not run moon test")
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
    ]
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
