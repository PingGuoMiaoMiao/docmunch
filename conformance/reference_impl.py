#!/usr/bin/env python3
"""A second implementation of the section contract, in ~70 lines of Python.

The point is not to be a good document tool - it is to show that the contract in
SPEC.md is implementable *outside* docmunch, and that conformance/check.py judges
it by the rules rather than by whose code produced it.

It splits a Markdown file at ATX headings, records the byte range of each
section and the sha256 of those exact bytes, and writes the same index shape.

Usage:
  python conformance/reference_impl.py --src docs/p5-index.md --out /tmp/ref
  python conformance/check.py --index /tmp/ref/index.json --raw /tmp/ref/raw
Exit code 0 = the index was written.
"""

import argparse
import hashlib
import json
import pathlib
import re

HEADING = re.compile(r"^(#{1,6})\s+(.*)$")


def split_sections(text):
    """Yield (title, level, byte_start, byte_end) for ATX headings."""
    data = text.encode("utf-8")
    lines = text.splitlines(keepends=True)
    starts = []
    offset = 0
    for line in lines:
        match = HEADING.match(line.rstrip("\n"))
        if match:
            starts.append((offset, len(match.group(1)), match.group(2).strip()))
        offset += len(line.encode("utf-8"))

    out = []
    if not starts:
        out.append(("", 0, 0, len(data)))
        return out
    if starts[0][0] > 0:
        out.append(("", 0, 0, starts[0][0]))
    for i, (start, level, title) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(data)
        out.append((title, level, start, end))
    return out


def slug(text, index):
    cleaned = re.sub(r"[^a-z0-9\u4e00-\u9fff]+", "-", text.lower()).strip("-")
    return cleaned or f"sec{index}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", required=True, help="Markdown file to section")
    parser.add_argument("--out", required=True, help="output directory")
    parser.add_argument("--repo", default="ref")
    args = parser.parse_args()

    src = pathlib.Path(args.src)
    text = src.read_text(encoding="utf-8")
    data = text.encode("utf-8")
    out_dir = pathlib.Path(args.out)
    raw_dir = out_dir / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)

    doc_path = src.name
    # SPEC 只要求 raw 文件能被找到；这里用 sha256(doc_path) 命名，与 docmunch 一致
    raw_name = hashlib.sha256(doc_path.encode("utf-8")).hexdigest() + ".bin"
    (raw_dir / raw_name).write_bytes(data)

    sections = []
    seen = {}
    for index, (title, level, start, end) in enumerate(split_sections(text)):
        base = slug(title, index)
        count = seen.get(base, 0)
        seen[base] = count + 1
        unique = base if count == 0 else f"{base}-{count + 1}"
        sections.append({
            "id": f"{args.repo}::{doc_path}::{unique}#{level}",
            "repo": args.repo,
            "doc_path": doc_path,
            "title": title,
            "level": level,
            "byte_start": start,
            "byte_end": end,
            "parent_id": "",
            "content_hash": hashlib.sha256(data[start:end]).hexdigest(),
            "terms": [],
            "tokens": 0,
        })

    index = {
        "repo": args.repo,
        "doc_paths": [doc_path],
        "sections": sections,
        "index_version": 4,
    }
    (out_dir / "index.json").write_text(
        json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote {len(sections)} sections -> {out_dir / 'index.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
