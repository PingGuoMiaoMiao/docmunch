#!/usr/bin/env python3
"""Regenerate / verify the Markdown goldens.

Usage:
  python tools/markdown_golden.py           # verify (exit 1 on drift)
  python tools/markdown_golden.py --update  # rewrite fixtures/markdown/*.md

Goldens are produced by the real binary, so they guard the whole
extract -> markdown pipeline, not just the converter unit tests.
"""

import os
import pathlib
import subprocess
import sys

def _resolve_exe():
    """moon names the binary main.exe on every platform we build on."""
    base = pathlib.Path("_build/native/debug/build/cmd/main")
    for name in ("main.exe", "main"):
        candidate = base / name
        if candidate.exists():
            return candidate
    return base / "main.exe"


EXE = _resolve_exe()
HTML_DIR = pathlib.Path("fixtures/html")
MD_DIR = pathlib.Path("fixtures/markdown")


def main() -> int:
    update = "--update" in sys.argv[1:]
    if not EXE.exists():
        print(f"missing {EXE}; run `moon build --target native` first")
        return 2
    MD_DIR.mkdir(parents=True, exist_ok=True)

    failures = 0
    for html in sorted(HTML_DIR.glob("*.html")):
        name = html.stem
        target = MD_DIR / f"{name}.md"
        out = subprocess.run(
            [str(EXE), "markdown", str(html)],
            capture_output=True,
            check=False,
        )
        if out.returncode != 0:
            print(f"FAIL {name}: exit {out.returncode}: {out.stderr.decode('utf-8', 'replace')[:200]}")
            failures += 1
            continue
        produced = out.stdout.decode("utf-8").replace("\r\n", "\n")
        if update:
            target.write_bytes(produced.encode("utf-8"))
            print(f"updated {target} ({len(produced)} chars)")
            continue
        if not target.exists():
            print(f"MISSING {target}; run with --update")
            failures += 1
            continue
        expected = target.read_bytes().decode("utf-8")
        if produced != expected:
            print(f"DRIFT {target}")
            failures += 1
        else:
            print(f"ok    {target} ({len(produced)} chars)")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
