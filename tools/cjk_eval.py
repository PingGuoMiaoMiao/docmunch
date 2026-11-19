#!/usr/bin/env python3
"""Chinese tokenisation comparison: does the dictionary-free bigram hold up?

docmunch tokenises CJK with overlapping bigrams and ships no dictionary. The
obvious alternative is a word segmenter (jieba). This measures whether that
choice costs retrieval quality, on the same corpus, sections and questions.

  char    every CJK character is a token (smallest possible vocabulary)
  bigram  overlapping bigrams, what docmunch ships
  jieba   dictionary-based word segmentation (external dependency)

All three feed the same BM25 (rank_bm25) over the same sections, so the only
variable is the tokeniser.

Usage: python tools/cjk_eval.py [--json out.json]
Exit code 0 always - it reports, it does not judge.
"""

import json
import pathlib
import subprocess
import sys

import jieba
from rank_bm25 import BM25Okapi

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from retrieval_compare import GOLD  # same 18 labelled questions

CORPUS = pathlib.Path("docs")
REPO = "cjk"
ROOT = pathlib.Path(".doc-index-cjk")
K = 5

CJK_RANGES = ((0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0x3040, 0x30FF))


def is_cjk(ch):
    code = ord(ch)
    return any(lo <= code <= hi for lo, hi in CJK_RANGES)


def split_runs(text):
    """Yield ('cjk', run) and ('ascii', word) pieces in order."""
    cjk, ascii_run = [], []

    def flush_ascii():
        if ascii_run:
            yield ("ascii", "".join(ascii_run).lower())
            ascii_run.clear()

    def flush_cjk():
        if cjk:
            yield ("cjk", "".join(cjk))
            cjk.clear()

    pending = []
    for ch in text:
        if is_cjk(ch):
            pending.extend(flush_ascii())
            cjk.append(ch)
        elif ch.isalnum() or ch == "_":
            pending.extend(flush_cjk())
            ascii_run.append(ch)
        else:
            pending.extend(flush_ascii())
            pending.extend(flush_cjk())
    pending.extend(flush_ascii())
    pending.extend(flush_cjk())
    return pending


def tokens_char(text):
    out = []
    for kind, value in split_runs(text):
        if kind == "ascii":
            if len(value) >= 2:
                out.append(value)
        else:
            out.extend(value)
    return out


def tokens_bigram(text):
    out = []
    for kind, value in split_runs(text):
        if kind == "ascii":
            if len(value) >= 2:
                out.append(value)
        elif len(value) == 1:
            out.append(value)
        else:
            out.extend(value[i:i + 2] for i in range(len(value) - 1))
    return out


def tokens_jieba(text):
    out = []
    for kind, value in split_runs(text):
        if kind == "ascii":
            if len(value) >= 2:
                out.append(value)
        else:
            out.extend(w for w in jieba.cut(value) if w.strip())
    return out


def resolve_exe():
    base = pathlib.Path("_build/native/debug/build/cmd/main")
    for name in ("main.exe", "main"):
        if (base / name).exists():
            return base / name
    return base / "main.exe"


EXE = resolve_exe()


def main():
    if not EXE.exists():
        print(f"missing {EXE}; run `moon build --target native`")
        return 2
    if ROOT.exists():
        import shutil
        shutil.rmtree(ROOT)
    subprocess.run(
        [str(EXE), "index-dir", str(CORPUS), "--repo", REPO, "--root", str(ROOT)],
        check=True, capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    index = json.loads((ROOT / REPO / "index.json").read_text(encoding="utf-8"))
    docs = {f"docs/{p.name}": p.read_text(encoding="utf-8") for p in sorted(CORPUS.glob("*.md"))}
    by_name = {pathlib.Path(name).name: text for name, text in docs.items()}

    units = []
    for sec in index["sections"]:
        source = by_name.get(pathlib.Path(sec["doc_path"]).name)
        if source is None:
            continue
        raw = source.encode("utf-8")
        body = raw[sec["byte_start"]:sec["byte_end"]].decode("utf-8", "replace")
        units.append((sec["doc_path"], sec["title"], body))

    results = {}
    for name, fn in (("char", tokens_char), ("bigram", tokens_bigram), ("jieba", tokens_jieba)):
        corpus_tokens = [fn(body) for _, _, body in units]
        vocab = set()
        for toks in corpus_tokens:
            vocab.update(toks)
        bm25 = BM25Okapi(corpus_tokens)
        h1 = h5 = 0
        misses = []
        for question, gold_doc, gold_title, phrase in GOLD:
            scores = bm25.get_scores(fn(question))
            order = sorted(range(len(units)), key=lambda i: (-scores[i], i))
            picked = [i for i in order[:K] if scores[i] > 0]
            hit5 = any(units[i][0] == gold_doc and phrase in units[i][2] for i in picked)
            hit1 = bool(picked) and units[picked[0]][0] == gold_doc and phrase in units[picked[0]][2]
            h1 += hit1
            h5 += hit5
            if not hit5:
                misses.append(gold_title)
        results[name] = {"hit1": h1, "hit5": h5, "vocab": len(vocab), "misses": misses}

    n = len(GOLD)
    header = f"{'tokenizer':10} {'hit@1':>10} {'hit@5':>10} {'vocab':>9}  note"
    print(f"\ncorpus: {len(docs)} docs, {len(units)} sections, {n} questions, k={K}\n")
    print(header)
    print("-" * (len(header) + 20))
    notes = {
        "char": "no dictionary, largest vocab",
        "bigram": "no dictionary, what docmunch ships",
        "jieba": "dictionary segmentation, extra dependency",
    }
    for name in ("char", "bigram", "jieba"):
        r = results[name]
        print(f"{name:10} {r['hit1']:>5}/{n:<4} {r['hit5']:>5}/{n:<4} {r['vocab']:>9}  {notes[name]}")

    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
        pathlib.Path(out).write_text(
            json.dumps({"per_tokenizer": results, "questions": n, "sections": len(units)},
                       ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"detail -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
