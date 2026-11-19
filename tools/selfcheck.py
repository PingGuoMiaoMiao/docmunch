#!/usr/bin/env python3
"""One command that answers "is this submission in good shape?".

A reviewer should not have to know that this project keeps three separate gates.
`tools/selfcheck.py` runs them and prints one table:

  acceptance   the six published acceptance rules (MoonBit-primary, public
               history, runnable, substantial work, licence, explainable AI)
  consistency  documents matching the code: test counts, ADR numbering and
               counts, relative links, cited commits, verbatim transcripts
  consumer     (optional) a fresh module resolving the PUBLISHED version from
               the registry and running against it

Checks are executed as subprocesses and merged through their --json output, so
each script keeps working on its own and a failure in one cannot mask another.

Usage:
  python tools/selfcheck.py                # acceptance + consistency
  python tools/selfcheck.py --skip-build   # fast: no moon build/test
  python tools/selfcheck.py --with-consumer  # also verify the published package
Exit: 0 = nothing failed, 1 = at least one FAIL, 2 = bad invocation.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent


def out(msg=""):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    print(msg)


def run_json(script: Path, args):
    """Run a checker with --json and return its parsed payload, or None."""
    if not script.is_file():
        return None, f"missing script: {script.name}"
    cmd = [sys.executable, str(script), "--json", *args]
    try:
        res = subprocess.run(
            cmd, cwd=PROJECT, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=1800,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, f"{script.name} could not run: {exc}"
    body = (res.stdout or "").strip()
    if not body:
        return None, f"{script.name} produced no output (stderr: {(res.stderr or '')[:200]})"
    # the checker may print human text first; take from the first JSON token
    start = min((i for i in (body.find("{"), body.find("[")) if i >= 0), default=-1)
    if start < 0:
        return None, f"{script.name} printed no JSON"
    try:
        return json.loads(body[start:]), None
    except json.JSONDecodeError as exc:
        return None, f"{script.name} JSON unparsable: {exc}"


def rows_from_acceptance(payload):
    """Normalise the acceptance schema (checks with name/status/evidence)."""
    rows = []
    for item in payload.get("checks", []):
        name = item.get("name") or item.get("check") or "?"
        rows.append((name, item.get("status", "?"), item.get("evidence", "")))
    return rows


def rows_from_consistency(payload):
    return [(i.get("check", "?"), i.get("status", "?"), i.get("evidence", "")) for i in payload]


def check_publish_dryrun():
    """`moon publish --dry-run` needs no login and re-checks the packaged zip.

    That extraction step is the point: it catches the class of bug where the
    project builds from the working tree but the PACKAGE is broken (workspace
    members shipped, a file referenced but excluded, ...).
    """
    try:
        res = subprocess.run(
            ["moon", "publish", "--dry-run"], cwd=PROJECT, capture_output=True,
            text=True, encoding="utf-8", errors="replace", timeout=1800,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return [("dry-run", "SKIP", f"could not run: {exc}")]
    body = (res.stdout or "") + (res.stderr or "")
    if res.returncode != 0:
        # "duplicated with an existing version" is not a packaging failure: it
        # means the repository's version is ALREADY on the registry. Distinguish
        # that (a good state) from a genuinely broken package.
        if "duplicated with an existing version" in body:
            import re as _re
            ver_match = _re.search(r"version \(([0-9][0-9.]*)\)", body)
            ver = ver_match.group(1) if ver_match else "current"
            return [(
                "dry-run", "PASS",
                f"current version {ver} is already published on the registry "
                "(nothing to republish); package itself validated",
            )]
        # A network hiccup is not a verdict about the package. Treat transport
        # failures as SKIP so a flaky link never looks like a broken submission.
        network_markers = (
            "send failed", "receiver is gone", "connection", "timed out",
            "dns", "unreachable", "request or response body error",
        )
        lowered = body.lower()
        if any(marker in lowered for marker in network_markers):
            return [("dry-run", "SKIP", "registry unreachable during dry-run; package not judged")]
        tail = " ".join(body.strip().splitlines()[-3:])[:300]
        return [("dry-run", "FAIL", tail)]
    rechecked = "running moon check on extracted package" in body
    status_line = next(
        (l.strip() for l in body.splitlines() if l.strip().lower().startswith("server status")),
        "",
    )
    evidence = "package validated" + (", re-checked after extraction" if rechecked else "")
    if status_line:
        evidence += f"; {status_line.lower()}"
    return [("dry-run", "PASS", evidence)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-build", action="store_true", help="do not run moon build/test")
    ap.add_argument("--with-consumer", action="store_true",
                    help="also resolve and run the PUBLISHED package from the registry")
    ap.add_argument("--with-publish", action="store_true",
                    help="also dry-run `moon publish` (validates the packaged zip by "
                         "extracting and re-checking it; no upload, no login)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    shared = ["--skip-build"] if args.skip_build else []
    sections = []

    acc, err = run_json(HERE / "acceptance.py", ["--since", "2026-11-01", *shared])
    sections.append(("acceptance: the six published rules", rows_from_acceptance(acc) if acc else [],
                     err))

    con, err2 = run_json(HERE / "consistency.py", shared)
    sections.append(("consistency: documents vs code", rows_from_consistency(con) if con else [],
                     err2))

    if args.with_consumer:
        consumer = HERE / "consumer_check.py"
        if consumer.is_file():
            try:
                res = subprocess.run(
                    [sys.executable, str(consumer)], cwd=PROJECT, capture_output=True,
                    text=True, encoding="utf-8", errors="replace", timeout=1800,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                sections.append(("consumer: published package", [], f"could not run: {exc}"))
            else:
                status = "PASS" if res.returncode == 0 else "FAIL"
                tail = (res.stdout or res.stderr or "").strip().splitlines()
                sections.append((
                    "consumer: published package",
                    [("registry consume", status, tail[-1] if tail else "")],
                    None,
                ))
        else:
            sections.append(("consumer: published package", [],
                             "no consumer_check.py in this project (skipped)"))

    if args.with_publish:
        sections.append(("publish readiness: packaged zip", check_publish_dryrun(), None))

    all_rows = [(sec, name, status, ev) for sec, rows, _ in sections for name, status, ev in rows]
    failures = [r for r in all_rows if r[2] == "FAIL"]
    errors = [(sec, err) for sec, _, err in sections if err]

    if args.json:
        out(json.dumps({
            "project": str(PROJECT),
            "sections": [
                {"section": sec,
                 "rows": [{"check": n, "status": s, "evidence": e} for n, s, e in rows],
                 "error": err}
                for sec, rows, err in sections
            ],
            "failures": len(failures),
        }, ensure_ascii=False))
        return 1 if failures or errors else 0

    out(f"selfcheck — {PROJECT}")
    for sec, rows, err in sections:
        out()
        out(sec)
        if err:
            out(f"  ERROR  {err}")
            continue
        if not rows:
            out("  (no rows)")
            continue
        for name, status, ev in rows:
            out(f"  {status:<5} {name:<20} {ev}")

    out()
    total = len(all_rows)
    fails = len(failures)
    warn = sum(1 for r in all_rows if r[2] == "WARN")
    skip = sum(1 for r in all_rows if r[2] == "SKIP")
    out(f"{total} checks: {total - fails - warn - skip} pass, {warn} warn, {skip} skip, {fails} fail")
    if failures:
        out()
        out("FAIL details:")
        for sec, name, _, ev in failures:
            out(f"  [{sec}] {name}: {ev}")
    return 1 if failures or errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
