#!/usr/bin/env python3
"""Prove the conformance checker has teeth.

A checker that passes everything is worthless, so this builds a real index and
then breaks it in four ways, asserting that each mutation is reported against
the rule it violates.

Usage: python conformance/selftest.py
Exit code 0 = the checker detected every injected violation.
"""

import json
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import check as conformance  # noqa: E402


def resolve_exe():
    base = pathlib.Path("_build/native/debug/build/cmd/main")
    for name in ("main.exe", "main"):
        if (base / name).exists():
            return base / name
    return base / "main.exe"


def build_index(exe, work):
    corpus = work / "src"
    corpus.mkdir()
    (corpus / "a.md").write_text("# One\n\nalpha 中文\n\n## Two\n\nbeta gamma\n",
                               encoding="utf-8", newline="\n")
    root = work / "idx"
    subprocess.run([str(exe), "index-dir", str(corpus), "--repo", "t", "--root", str(root)],
                   check=True, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return root / "t" / "index.json", root / "t" / "raw"


def rules_hit(index_path, raw_dir):
    problems, _ = conformance.check(index_path, raw_dir, "{sha256}.bin")
    return {rule for rule, _, _ in problems}


def main():
    exe = resolve_exe()
    if not exe.exists():
        print(f"missing {exe}; run `moon build --target native`")
        return 2

    work = pathlib.Path(tempfile.mkdtemp(prefix="conformance-selftest-"))
    failures = []
    try:
        index_path, raw_dir = build_index(exe, work)
        baseline = rules_hit(index_path, raw_dir)
        if baseline:
            print(f"FAIL clean index already reports {baseline}")
            return 1
        print("ok   clean index reports nothing")

        original = json.loads(index_path.read_text(encoding="utf-8"))

        def mutate(name, fn, expected_rule):
            data = json.loads(json.dumps(original))
            fn(data)
            path = work / f"{name}.json"
            path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
            hit = rules_hit(path, raw_dir)
            if expected_rule in hit:
                print(f"ok   {name} -> {expected_rule}")
            else:
                print(f"FAIL {name} expected {expected_rule}, got {sorted(hit)}")
                failures.append(name)

        def break_hash(data):
            data["sections"][0]["content_hash"] = "0" * 64

        def shift_start(data):
            # pretend the second section starts one byte later: leaves a gap
            data["sections"][1]["byte_start"] += 1

        def duplicate_id(data):
            data["sections"][1]["id"] = data["sections"][0]["id"]

        def empty_section(data):
            data["sections"][0]["byte_end"] = data["sections"][0]["byte_start"]

        def split_character(data):
            # point a boundary inside the 3-byte 中 character, located in the
            # actual raw file (line-ending normalisation would shift a re-derived string)
            raw_file = next(iter(raw_dir.glob("*.bin")))
            raw = raw_file.read_bytes()
            target = raw.index("中".encode("utf-8")) + 1
            data["sections"][0]["byte_end"] = target
            data["sections"][1]["byte_start"] = target

        mutate("broken_hash", break_hash, "C4")
        mutate("gap_between_sections", shift_start, "C2")
        mutate("duplicate_id", duplicate_id, "C1")
        mutate("empty_section", empty_section, "C5")
        mutate("split_character", split_character, "C3")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    if failures:
        print(f"\n{len(failures)} failure(s): {failures}")
        return 1
    print("\nconformance selftest passed (checker detects every injected violation)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
