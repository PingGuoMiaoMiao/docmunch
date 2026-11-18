#!/usr/bin/env python3
"""Conformance checker for the section contract described in SPEC.md.

This does NOT import docmunch or any MoonBit code. It reads an index file plus
the raw cache and verifies the five structural rules (C1-C5); with --rerun it
also checks determinism (C6).

Exit code 0 = every rule passed, 1 = violations found, 2 = bad invocation.
"""

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

CONTINUATION = 0b10000000
MASK = 0b11000000


def sha256_hex(data):
    return hashlib.sha256(data).hexdigest()


def raw_path_for(raw_dir, pattern, doc_path):
    name = pattern.format(sha256=sha256_hex(doc_path.encode("utf-8")),
                          doc_path=doc_path.replace("/", "_"))
    return raw_dir / name


def is_boundary(data, offset):
    """True when `offset` does not point at a UTF-8 continuation byte."""
    if offset <= 0 or offset >= len(data):
        return True
    return (data[offset] & MASK) != CONTINUATION


def check(index_path, raw_dir, pattern):
    problems = []
    index = json.loads(index_path.read_text(encoding="utf-8"))
    sections = index.get("sections", [])
    doc_paths = index.get("doc_paths", [])

    if not sections:
        problems.append(("C0", "-", "index contains no sections"))
        return problems, 0

    # C1 unique ids
    seen = {}
    for sec in sections:
        sid = sec.get("id")
        if sid is None:
            problems.append(("C1", "-", "section without id"))
            continue
        if sid in seen:
            problems.append(("C1", sid, "duplicate id"))
        seen[sid] = True

    by_doc = {}
    for sec in sections:
        by_doc.setdefault(sec.get("doc_path"), []).append(sec)

    for doc_path in sorted(by_doc):
        rows = sorted(by_doc[doc_path], key=lambda s: s.get("byte_start", 0))
        raw_file = raw_path_for(raw_dir, pattern, doc_path)
        if not raw_file.exists():
            problems.append(("C2", doc_path, f"raw cache missing: {raw_file.name}"))
            continue
        data = raw_file.read_bytes()

        # C2 contiguity and full coverage
        if rows[0].get("byte_start") != 0:
            problems.append(("C2", doc_path, f"first section starts at {rows[0].get('byte_start')}, not 0"))
        for prev, nxt in zip(rows, rows[1:]):
            if prev.get("byte_end") != nxt.get("byte_start"):
                problems.append(
                    ("C2", doc_path,
                     f"gap/overlap at byte {prev.get('byte_end')} -> {nxt.get('byte_start')}"))
        if rows[-1].get("byte_end") != len(data):
            problems.append(
                ("C2", doc_path,
                 f"last section ends at {rows[-1].get('byte_end')}, file is {len(data)} bytes"))

        for sec in rows:
            start, end = sec.get("byte_start"), sec.get("byte_end")

            # C5 non-empty
            if start is None or end is None or end <= start:
                problems.append(("C5", sec.get("id", doc_path), f"empty or inverted range {start}..{end}"))
                continue

            # C3 character boundaries
            if not is_boundary(data, start):
                problems.append(("C3", sec.get("id", doc_path), f"byte_start {start} splits a character"))
            if not is_boundary(data, end):
                problems.append(("C3", sec.get("id", doc_path), f"byte_end {end} splits a character"))

            # C4 hash matches the bytes
            expected = sec.get("content_hash")
            if expected is None:
                problems.append(("C4", sec.get("id", doc_path), "missing content_hash"))
            else:
                actual = sha256_hex(data[start:end])
                if actual != expected:
                    problems.append(
                        ("C4", sec.get("id", doc_path),
                         f"hash mismatch: index={expected[:12]}… actual={actual[:12]}…"))

    return problems, len(sections)


def check_determinism(index_path, rerun_cmd):
    problems = []
    first = index_path.read_bytes()
    with tempfile.TemporaryDirectory(prefix="conformance-rerun-") as tmp:
        cmd = rerun_cmd.format(out=tmp)
        proc = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                              encoding="utf-8", errors="replace")
        if proc.returncode != 0:
            problems.append(("C6", "-", f"rerun command failed: {proc.stderr[-300:]}"))
            return problems
        candidates = sorted(pathlib.Path(tmp).rglob("index.json"))
        if not candidates:
            problems.append(("C6", "-", "rerun produced no index.json"))
            return problems
        again = candidates[0].read_bytes()
    if again != first:
        problems.append(
            ("C6", "-",
             f"index not byte-identical across runs ({len(first)} vs {len(again)} bytes)"))
    return problems


def main():
    parser = argparse.ArgumentParser(description="Check the section contract (SPEC.md)")
    parser.add_argument("--index", required=True, help="path to index.json")
    parser.add_argument("--raw", required=True, help="directory holding cached source files")
    parser.add_argument("--raw-pattern", default="{sha256}.bin",
                        help="raw file naming; {sha256} or {doc_path} (default: {sha256}.bin)")
    parser.add_argument("--rerun", default=None,
                        help="command that regenerates the index, with {out} for the output dir")
    args = parser.parse_args()

    index_path = pathlib.Path(args.index)
    raw_dir = pathlib.Path(args.raw)
    if not index_path.exists():
        print(f"no such index: {index_path}")
        return 2
    if not raw_dir.is_dir():
        print(f"no such raw directory: {raw_dir}")
        return 2

    problems, checked = check(index_path, raw_dir, args.raw_pattern)
    if args.rerun:
        problems += check_determinism(index_path, args.rerun)

    total_rules = "C1-C6" if args.rerun else "C1-C5"
    print(f"checked {checked} sections against {total_rules}")

    if problems:
        print(f"\n{len(problems)} violation(s):")
        for rule, where, detail in problems[:40]:
            print(f"  {rule}  {where}  {detail}")
        if len(problems) > 40:
            print(f"  … and {len(problems) - 40} more")
        return 1

    print("all rules passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
