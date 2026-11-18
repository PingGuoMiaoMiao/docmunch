#!/usr/bin/env python3
"""Build the four context packs for the end-to-end agent evaluation.

The evaluation answers the same 12 questions four ways:

  none        no context at all (detects memorisation / lucky guesses)
  full        the whole 5-document corpus in the prompt
  recursive   LangChain RecursiveCharacterTextSplitter(512, 80) + rank_bm25
  docmunch    heading-aligned sections + BM25 (this project)

Each pack is written as a markdown file that an answerer agent reads, so the
answering prompt stays small and identical across strategies.

Usage: python tools/e2e_prepare.py
"""

import json
import pathlib
import subprocess

import tiktoken
from langchain_text_splitters import RecursiveCharacterTextSplitter
from rank_bm25 import BM25Okapi

WORK = pathlib.Path("_e2e")
CORPUS_FILES = [
    "docs/decisions.md",
    "docs/p5-index.md",
    "docs/p12-bm25.md",
    "docs/demo-selfindex.md",
    "docs/p6-mcp.md",
]
REPO = "e2e"
ROOT = WORK / "index"
K = 5
ENCODER = tiktoken.get_encoding("cl100k_base")


def tokenize(text):
    out, ascii_run, cjk_run = [], [], []

    def flush_ascii():
        if ascii_run:
            word = "".join(ascii_run).lower()
            if len(word) >= 2:
                out.append(word)
            ascii_run.clear()

    def flush_cjk():
        if len(cjk_run) == 1:
            out.append(cjk_run[0])
        else:
            for a, b in zip(cjk_run, cjk_run[1:]):
                out.append(a + b)
        cjk_run.clear()

    for ch in text:
        code = ord(ch)
        if 0x4E00 <= code <= 0x9FFF or 0x3400 <= code <= 0x4DBF:
            flush_ascii()
            cjk_run.append(ch)
        elif ch.isalnum() or ch == "_":
            flush_cjk()
            ascii_run.append(ch)
        else:
            flush_ascii()
            flush_cjk()
    flush_ascii()
    flush_cjk()
    return out


def resolve_exe():
    base = pathlib.Path("_build/native/debug/build/cmd/main")
    for name in ("main.exe", "main"):
        if (base / name).exists():
            return base / name
    return base / "main.exe"


EXE = resolve_exe()


def tokens(text):
    return len(ENCODER.encode(text))


def top_k(units, query, k):
    bm25 = BM25Okapi([tokenize(text) for _, text in units])
    scores = bm25.get_scores(tokenize(query))
    order = sorted(range(len(units)), key=lambda i: (-scores[i], i))
    return [(units[i][0], units[i][1]) for i in order[:k] if scores[i] > 0]


def main():
    questions = json.loads((WORK / "questions.json").read_text(encoding="utf-8"))
    docs = {name: pathlib.Path(name).read_text(encoding="utf-8") for name in CORPUS_FILES}

    # --- docmunch sections
    if ROOT.exists():
        import shutil
        shutil.rmtree(ROOT)
    corpus_dir = WORK / "corpus"
    if corpus_dir.exists():
        import shutil
        shutil.rmtree(corpus_dir)
    corpus_dir.mkdir(parents=True)
    for name, text in docs.items():
        (corpus_dir / pathlib.Path(name).name).write_text(text, encoding="utf-8")
    subprocess.run(
        [str(EXE), "index-dir", str(corpus_dir), "--repo", REPO, "--root", str(ROOT)],
        check=True, capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    index = json.loads((ROOT / REPO / "index.json").read_text(encoding="utf-8"))
    # the index records the temporary corpus path, so map back by file name
    by_name = {pathlib.Path(name).name: text for name, text in docs.items()}
    sec_units = []
    for sec in index["sections"]:
        source = by_name.get(pathlib.Path(sec["doc_path"]).name)
        if source is None:
            continue
        raw = source.encode("utf-8")
        if not raw:
            continue
        sec_units.append(
            (sec["doc_path"], raw[sec["byte_start"]:sec["byte_end"]].decode("utf-8", "replace"))
        )

    # --- langchain recursive chunks
    splitter = RecursiveCharacterTextSplitter(chunk_size=512, chunk_overlap=80)
    rec_units = []
    for name, text in docs.items():
        for chunk in splitter.split_text(text):
            rec_units.append((name, chunk))

    whole = "\n\n".join(f"<!-- {name} -->\n{text}" for name, text in docs.items())
    stats = {}

    def write_pack(name, blocks):
        path = WORK / "contexts" / f"{name}.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(blocks, encoding="utf-8")
        stats[name] = tokens(blocks)

    question_list = "\n".join(
        f"{q['id']}. {q['question']}" for q in questions
    )

    write_pack("none", f"""# 任务

回答下面 12 个问题。**没有任何参考材料**，凭你自己的知识回答。
如果不确定，就在 `answer` 里写"无法确定"。

## 问题

{question_list}
""")

    write_pack("full", f"""# 任务

回答下面 12 个问题。参考材料是**完整的文档语料**（5 个文件全文，附在最后）。
只根据材料回答；材料里没有的，在 `answer` 里写"无法确定"。

## 问题

{question_list}

## 参考材料（全文）

{whole}
""")

    # A realistic window budget: the whole corpus truncated to 8k tokens, which
    # models the case where the corpus no longer fits and "paste everything"
    # silently loses the answer.
    ids = ENCODER.encode(whole)[:8000]
    truncated = ENCODER.decode(ids)
    write_pack("full_trunc", f"""# 任务

回答下面 12 个问题。参考材料是语料的**前 8000 token**（受上下文窗口限制，之后被截断）。
只根据材料回答；材料里没有的，在 `answer` 里写"无法确定"。

## 问题

{question_list}

## 参考材料（截断后）

{truncated}
""")

    for strategy, units in (("recursive", rec_units), ("docmunch", sec_units)):
        parts = ["# 任务", "",
                 "回答下面 12 个问题。每个问题后面给出检索到的参考片段。",
                 "只根据该问题下方的片段回答；片段里没有的，在 `answer` 里写\"无法确定\"。",
                 "", "## 问题与参考片段", ""]
        for q in questions:
            parts.append(f"### 问题 {q['id']}：{q['question']}")
            picked = top_k(units, q["question"], K)
            if not picked:
                parts.append("（没有检索到任何片段）")
            for i, (doc, text) in enumerate(picked, start=1):
                parts.append(f"\n片段 {i}（来自 {pathlib.Path(doc).name}）：\n")
                parts.append("~~~")
                parts.append(text.strip())
                parts.append("~~~")
            parts.append("")
        write_pack(strategy, "\n".join(parts))

    (WORK / "context_stats.json").write_text(
        json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")

    print("context packs (tokens):")
    for name, value in stats.items():
        print(f"  {name:10} {value:>7}")
    print(f"\nquestions: {len(questions)}; sections {len(sec_units)}; chunks {len(rec_units)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
