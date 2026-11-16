#!/usr/bin/env python3
"""Dogfood smoke test: index this project's own docs and query them.

Uses only the CLI, so it exercises the same path a user takes:
index-dir -> search -> search again (incremental).

Exit code 0 = every assertion passed.
"""

import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile


def resolve_exe():
    """moon names the binary main.exe on every platform we build on."""
    base = pathlib.Path("_build/native/debug/build/cmd/main")
    for name in ("main.exe", "main"):
        candidate = base / name
        if candidate.exists():
            return candidate
    return base / "main.exe"


EXE = resolve_exe()
REPO = "selfindex"
FAILURES = []


def run(args):
    proc = subprocess.run(
        [str(EXE), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return proc.returncode, proc.stdout + proc.stderr


def check(name, cond, detail=""):
    if cond:
        print(f"ok   {name}")
    else:
        FAILURES.append(name)
        print(f"FAIL {name} {detail}")


def parse_counts(output):
    counts = {}
    for key in ("files", "changed", "skipped", "failed", "docs", "sections"):
        match = re.search(rf"{key}=(\d+)", output)
        if match:
            counts[key] = int(match.group(1))
    return counts


def main():
    if not EXE.exists():
        print(f"missing {EXE}; run `moon build --target native`")
        return 2
    if not pathlib.Path("docs").is_dir():
        print("no docs/ directory to index")
        return 2

    root = pathlib.Path(tempfile.mkdtemp(prefix="docmunch-selfindex-"))
    try:
        code, out = run(["index-dir", "docs", "--repo", REPO, "--root", str(root)])
        counts = parse_counts(out)
        check("index-dir exits 0", code == 0, out[-300:])
        check(
            "every doc is indexed",
            counts.get("files", 0) >= 15 and counts.get("failed", 1) == 0,
            str(counts),
        )
        check(
            "sections are produced",
            counts.get("sections", 0) >= 100,
            str(counts),
        )

        code, out = run(["search", REPO, "byte offset", "--root", str(root)])
        check("english query hits", code == 0 and "hits=0" not in out, out[-200:])

        code, out = run(["search", REPO, "索引", "--root", str(root)])
        check("chinese query hits", code == 0 and "hits=0" not in out, out[-200:])

        code, out = run(["index-dir", "docs", "--repo", REPO, "--root", str(root)])
        counts = parse_counts(out)
        check(
            "second pass is incremental",
            counts.get("changed", 1) == 0
            and counts.get("skipped", 0) == counts.get("files", -1),
            str(counts),
        )
    finally:
        shutil.rmtree(root, ignore_errors=True)

    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s)")
        return 1
    print("\nself-index smoke passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
