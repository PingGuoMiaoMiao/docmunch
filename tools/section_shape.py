#!/usr/bin/env python3
"""How often can a 512-char chunk NOT cover a whole section?

The hard question set (docs/e2e-hard.md) showed section-aligned retrieval wins
when an answer needs two facts far apart inside one section. The obvious
follow-up question is: how often does that shape arise?

We cannot measure the distribution of real user questions - nobody has that log
for this project. What we CAN measure, honestly, is the structural half:

  * how long are the sections?
  * what fraction of sections is too long for one 512-char chunk?
  * for the labelled questions we do have, how many chunks would be needed to
    cover the gold section?

That gives the denominator: if most sections fit in one chunk, the hard-set
failure mode rarely arises and the win there is a corner case. If most sections
span several chunks, the failure mode is structural.

Usage: python tools/section_shape.py [--json out.json]
"""

import json
import pathlib
import subprocess
import sys

import tiktoken
from langchain_text_splitters import RecursiveCharacterTextSplitter

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from retrieval_compare import GOLD  # noqa: E402

DOCS = pathlib.Path("docs")
REPO = "shape"
ROOT = pathlib.Path(".doc-index-shape")
CHUNK = 512
ENCODER = tiktoken.get_encoding("cl100k_base")


def read_doc(path):
    """Byte-exact read: read_text would normalise CRLF and shift every offset."""
    return pathlib.Path(path).read_bytes().decode("utf-8")


def resolve_exe():
    base = pathlib.Path("_build/native/debug/build/cmd/main")
    for name in ("main.exe", "main"):
        if (base / name).exists():
            return base / name
    return base / "main.exe"


def pct(count, total):
    return f"{100.0 * count / total:.0f}%" if total else "n/a"


def main():
    exe = resolve_exe()
    if not exe.exists():
        print(f"missing {exe}")
        return 2
    if ROOT.exists():
        import shutil
        shutil.rmtree(ROOT)
    subprocess.run([str(exe), "index-dir", str(DOCS), "--repo", REPO, "--root", str(ROOT)],
                   check=True, capture_output=True, text=True, encoding="utf-8",
                   errors="replace")
    index = json.loads((ROOT / REPO / "index.json").read_text(encoding="utf-8"))

    docs = {}
    for p in sorted(DOCS.glob("*.md")):
        docs[f"docs/{p.name}"] = read_doc(p)

    lengths, token_lengths, per_doc = [], [], {}
    by_key = {}
    for sec in index["sections"]:
        src = docs.get(sec["doc_path"])
        if src is None:
            continue
        raw = src.encode("utf-8")
        body = raw[sec["byte_start"]:sec["byte_end"]].decode("utf-8", "replace")
        lengths.append(len(body))
        token_lengths.append(len(ENCODER.encode(body)))
        by_key[(sec["doc_path"], sec["title"])] = body
        per_doc[sec["doc_path"]] = per_doc.get(sec["doc_path"], 0) + 1

    import shutil
    shutil.rmtree(ROOT, ignore_errors=True)

    n = len(lengths)
    if n == 0:
        print("no sections")
        return 1
    longer = sum(1 for value in lengths if value > CHUNK)
    much_longer = sum(1 for value in lengths if value > 2 * CHUNK)
    lengths_sorted = sorted(lengths)

    def percentile(p):
        idx = min(len(lengths_sorted) - 1, int(len(lengths_sorted) * p))
        return lengths_sorted[idx]

    print(f"\ncorpus: {len(docs)} docs, {n} sections\n")
    print(f"{'section length (chars)':28} {percentile(0.5):>8} median / "
          f"{percentile(0.9):>8} p90 / {max(lengths):>8} max")
    print(f"{'section length (tokens)':28} {sorted(token_lengths)[n // 2]:>8} median / "
          f"{max(token_lengths):>8} max")
    print()
    print(f"sections longer than one {CHUNK}-char chunk : {longer}/{n}  ({pct(longer, n)})")
    print(f"sections longer than two chunks            : {much_longer}/{n}  ({pct(much_longer, n)})")
    print(f"mean chunks needed to cover a section      : "
          f"{sum(max(1, -(-value // CHUNK)) for value in lengths) / n:.2f}")

    # For the labelled questions: how many chunks would their gold section need?
    splitter = RecursiveCharacterTextSplitter(chunk_size=CHUNK, chunk_overlap=80)
    multi = 0
    checked = 0
    rows = []
    for question, gold_doc, gold_title, phrase in GOLD:
        body = by_key.get((gold_doc, gold_title))
        if body is None:
            continue
        checked += 1
        pieces = splitter.split_text(body)
        needs = len(pieces)
        if needs > 1:
            multi += 1
        rows.append({"question": question, "section_chars": len(body),
                     "chunks_needed": needs, "single_chunk": needs <= 1})

    print(f"\nlabelled questions whose gold section needs >1 chunk: "
          f"{multi}/{checked}  ({pct(multi, checked)})")
    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
        pathlib.Path(out).write_text(json.dumps({
            "sections": n,
            "docs": len(docs),
            "longer_than_chunk": longer,
            "longer_than_two_chunks": much_longer,
            "median_chars": percentile(0.5),
            "p90_chars": percentile(0.9),
            "labelled_multi_chunk": multi,
            "labelled_checked": checked,
            "rows": rows,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"detail -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
