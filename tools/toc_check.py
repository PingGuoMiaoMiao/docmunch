#!/usr/bin/env python3
"""Validate the section contract on a Markdown file.

Checks, against the raw bytes on disk (not the in-process string):
  1. sections are contiguous from byte 0 to EOF
  2. every slice is valid UTF-8
  3. sha256(slice) matches the hash printed by `docmunch toc`
  4. ids are unique and parent ids (when present) exist
  5. levels are 0..6 and non-root sections have a title

Usage: python tools/toc_check.py <file.md> [...]
"""

import hashlib
import os
import pathlib
import re
import subprocess
import sys

EXE = pathlib.Path("_build/native/debug/build/cmd/main") / ("main.exe" if os.name == "nt" else "main")
LINE = re.compile(
    r"^(?P<id>.+?)\tlevel=(?P<level>\d+)\tbytes=(?P<start>\d+)-(?P<end>\d+)\thash=(?P<hash>[0-9a-f]{64})\ttitle=(?P<title>.*)$"
)


def check(path: pathlib.Path) -> list[str]:
    errors: list[str] = []
    raw = path.read_bytes()
    out = subprocess.run([str(EXE), "toc", str(path)], capture_output=True, check=False)
    if out.returncode != 0:
        return [f"toc failed: {out.stderr.decode('utf-8', 'replace')[:200]}"]

    rows = []
    for line in out.stdout.decode("utf-8").splitlines():
        m = LINE.match(line)
        if not m:
            errors.append(f"unparsable toc line: {line[:80]}")
            continue
        rows.append(
            (
                m.group("id"),
                int(m.group("level")),
                int(m.group("start")),
                int(m.group("end")),
                m.group("hash"),
                m.group("title"),
            )
        )

    if not rows:
        return [f"{path}: no sections"]

    cursor = 0
    ids = {r[0] for r in rows}
    if len(ids) != len(rows):
        errors.append("duplicate section ids")

    for sid, level, start, end, digest, title in rows:
        if start != cursor:
            errors.append(f"{sid}: gap/overlap at {start} (expected {cursor})")
        cursor = end
        if level < 0 or level > 6:
            errors.append(f"{sid}: bad level {level}")
        if level > 0 and not title:
            errors.append(f"{sid}: missing title")
        chunk = raw[start:end]
        try:
            chunk.decode("utf-8")
        except UnicodeDecodeError as exc:
            errors.append(f"{sid}: slice is not UTF-8 ({exc})")
        actual = hashlib.sha256(chunk).hexdigest()
        if actual != digest:
            errors.append(f"{sid}: hash mismatch")

    if cursor != len(raw):
        errors.append(f"coverage ends at {cursor}, file has {len(raw)} bytes")

    return errors


def main() -> int:
    if not EXE.exists():
        print(f"missing {EXE}; run `moon build --target native`")
        return 2
    targets = [pathlib.Path(p) for p in sys.argv[1:]] or sorted(pathlib.Path("fixtures/markdown").glob("*.md"))
    failed = 0
    for path in targets:
        errors = check(path)
        if errors:
            failed += 1
            print(f"FAIL {path}")
            for e in errors[:10]:
                print(f"  - {e}")
        else:
            print(f"ok   {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
