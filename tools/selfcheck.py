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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-build", action="store_true", help="do not run moon build/test")
    ap.add_argument("--with-consumer", action="store_true",
                    help="also resolve and run the PUBLISHED package from the registry")
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
