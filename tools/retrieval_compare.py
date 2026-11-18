#!/usr/bin/env python3
"""Retrieval comparison against real third-party components.

Earlier evidence used a hand-rolled chunker and a hand-rolled BM25. That is not
a fair baseline: LangChain ships both a fixed-size splitter and a
heading-aware splitter, and BM25 has a standard library implementation. This
script replaces the home-made baselines with the real ones.

Systems (same corpus, same questions, same tokenizer for scoring):
  full_doc    the whole corpus, no retrieval
  recursive   langchain RecursiveCharacterTextSplitter(512, 80) + rank_bm25
  md_header   langchain MarkdownHeaderTextSplitter + rank_bm25
  docmunch    heading-aligned sections + BM25 over the same terms

Metrics per question:
  hit@1 / hit@5   retrieved context contains the gold phrase from the gold doc
  complete        the whole gold section is inside the retrieved context
  ctx_tokens      tiktoken count of the context handed to the model

Usage: python tools/retrieval_compare.py [--k 5] [--json rows.json]
Exit code 0 always - it reports, it does not judge.
"""

import json
import math
import pathlib
import re
import subprocess
import sys

import tiktoken
from langchain_text_splitters import (
    MarkdownHeaderTextSplitter,
    RecursiveCharacterTextSplitter,
)
from rank_bm25 import BM25Okapi

CORPUS = pathlib.Path("docs")
REPO = "cmp"
ROOT = pathlib.Path(".doc-index-compare")
ENCODER = tiktoken.get_encoding("cl100k_base")

# question -> (gold doc, exact heading, phrase that must appear in context)
GOLD = [
    ("为什么索引里只放元数据",
     "docs/decisions.md", "D8 — 索引只存元数据 + 原文缓存", "原子替换"),
    ("取回一节时会不会加载整篇文档",
     "docs/p5-index.md", "3. 取回", "read_at"),
    ("参考实现的分节算法是怎么写的",
     "docs/reference-comparison.md", "3.2 分节算法", "frontmatter"),
    ("索引版本不一致时怎么处理",
     "docs/decisions.md", "D31 — 索引版本不匹配即视为未索引", "未索引"),
    ("为什么偏移量按 UTF-8 字节算",
     "docs/p4-sectioning.md", "1. 契约", "UTF-8"),
    ("BM25 的 k1 和 b 取多少",
     "docs/p12-bm25.md", "2. 实现", "k1 = 1.2"),
    ("中文查询怎么切词",
     "docs/decisions.md", "D54 — 中文用 bigram 切词，且标点必须当分隔符", "bigram"),
    ("并发写索引为什么要互斥",
     "docs/decisions.md", "D44 — MCP 索引写入用共享 Mutex 串行化", "Mutex"),
    ("MCP 用哪个协议版本",
     "docs/p6-mcp.md", "1. 协议版本：2026-07-28（无 `initialize`）", "2026-07-28"),
    ("怎么防止访问内网地址",
     "docs/decisions.md", "D13 — 默认拒绝私网地址", "私网"),
    ("缓存多久过期、怎么重试",
     "docs/decisions.md", "D40 — fetch 缓存 TTL + 可读缓存 + 有限重试", "TTL"),
    ("黄金文件为什么要逐字节一致",
     "docs/devlog.md", "P3 Markdown：一个\"不确定\"的产物毁掉所有黄金文件", "黄金文件"),
    ("怎么跳过没有变化的文件",
     "docs/decisions.md", "D9 — 增量：文件级 sha256，Section 哈希只做校验", "sha256"),
    ("MCP 的 HTTP 鉴权怎么开",
     "docs/decisions.md", "D52 — MCP HTTP 用 Bearer Token 保护，stdio 不动", "Bearer"),
    ("RST 和 Jupyter 怎么处理",
     "docs/decisions.md", "D53 — RST 与 Jupyter 用\"降级转换\"而不是拒绝", "index-dir"),
    ("自举演示怎么复跑",
     "docs/demo-selfindex.md", "复跑", "selfindex"),
    ("抽取质量用什么指标",
     "docs/p2-extraction.md", "1. 指标", "Jaccard"),
    ("可维护性里最长的函数是哪个",
     "docs/maintainability.md", "1. 量化指标（实测）", "build_server"),
]


def tokenize(text):
    """ASCII words + CJK bigrams; identical rules on every system's scored text."""
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
        if 0x4E00 <= code <= 0x9FFF or 0x3400 <= code <= 0x4DBF or 0x3040 <= code <= 0x30FF:
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


def count_tokens(text):
    return len(ENCODER.encode(text))


def normalize(text):
    """Collapse whitespace so a re-rendered section compares equal to the source."""
    return re.sub(r"\s+", " ", text).strip()


def covers(gold_text, unit_text):
    """Does `unit_text` contain the whole gold section, allowing re-rendering?

    Exact substring match is too strict for splitters that re-emit their own
    text: the LangChain MarkdownHeaderTextSplitter rebuilds each chunk from
    parsed lines, so the bytes differ even when the content is complete. We
    therefore require every non-empty line of the gold section to be present.
    """
    gold_norm = normalize(gold_text)
    unit_norm = normalize(unit_text)
    if gold_norm and gold_norm in unit_norm:
        return True
    lines = [normalize(line) for line in gold_text.splitlines()]
    lines = [line for line in lines if line]
    if not lines:
        return False
    return all(line in unit_norm for line in lines)


def resolve_exe():
    base = pathlib.Path("_build/native/debug/build/cmd/main")
    for name in ("main.exe", "main"):
        if (base / name).exists():
            return base / name
    return base / "main.exe"


EXE = resolve_exe()


def run_cli(args):
    proc = subprocess.run([str(EXE), *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    return proc.returncode, proc.stdout + proc.stderr


class System:
    """A retrieval system: returns (context_texts, hit_title) for a query."""

    def __init__(self, name, units):
        self.name = name
        self.units = units  # list of (doc_path, text)
        self.bm25 = BM25Okapi([tokenize(t) for _, t in units])

    def retrieve(self, query, k):
        scores = self.bm25.get_scores(tokenize(query))
        order = sorted(range(len(self.units)), key=lambda i: (-scores[i], i))
        picked = [i for i in order[:k] if scores[i] > 0]
        return [(self.units[i][0], self.units[i][1]) for i in picked]


def load_docs():
    return {f"docs/{p.name}": p.read_text(encoding="utf-8")
            for p in sorted(CORPUS.glob("*.md"))}


def golden_section_bytes(index, doc_path, title):
    """Byte range of the gold section as docmunch indexed it."""
    for sec in index["sections"]:
        if sec["doc_path"] == doc_path and sec["title"] == title:
            return sec["byte_start"], sec["byte_end"]
    return None


def main():
    k = 5
    if "--k" in sys.argv:
        k = int(sys.argv[sys.argv.index("--k") + 1])
    if not EXE.exists():
        print(f"missing {EXE}; run `moon build --target native`")
        return 2

    code, out = run_cli(["index-dir", str(CORPUS), "--repo", REPO, "--root", str(ROOT)])
    if code != 0:
        print(out)
        raise SystemExit("index-dir failed")
    index = json.loads((ROOT / REPO / "index.json").read_text(encoding="utf-8"))

    docs = load_docs()

    # docmunch sections, text recovered from the byte ranges
    sec_units = []
    for sec in index["sections"]:
        raw = docs.get(sec["doc_path"], "").encode("utf-8")
        body = raw[sec["byte_start"]:sec["byte_end"]].decode("utf-8", errors="replace")
        sec_units.append((sec["doc_path"], body))

    # third-party fixed-size splitter
    rec_splitter = RecursiveCharacterTextSplitter(chunk_size=512, chunk_overlap=80)
    rec_units = []
    for doc, text in docs.items():
        for chunk in rec_splitter.split_text(text):
            rec_units.append((doc, chunk))

    # third-party heading-aware splitter
    hdr_splitter = MarkdownHeaderTextSplitter(
        headers_to_split_on=[("#", "h1"), ("##", "h2"), ("###", "h3")],
        strip_headers=False,
    )
    hdr_units = []
    for doc, text in docs.items():
        for chunk in hdr_splitter.split_text(text):
            hdr_units.append((doc, chunk.page_content))

    systems = {
        "recursive": System("recursive", rec_units),
        "md_header": System("md_header", hdr_units),
        "docmunch": System("docmunch", sec_units),
    }
    whole = "\n\n".join(docs.values())

    rows = []
    for question, gold_doc, gold_title, phrase in GOLD:
        gold_range = golden_section_bytes(index, gold_doc, gold_title)
        if gold_range is None:
            print(f"WARN gold section missing: {gold_doc} :: {gold_title}")
            continue
        raw = docs[gold_doc].encode("utf-8")
        gold_text = raw[gold_range[0]:gold_range[1]].decode("utf-8", errors="replace")
        if phrase not in gold_text:
            print(f"WARN phrase not inside gold section: {gold_title} :: {phrase}")
        row = {"q": question, "gold": gold_doc, "title": gold_title,
               "gold_tokens": count_tokens(gold_text)}
        for name, system in systems.items():
            picked = system.retrieve(question, k)
            ctx = "\n\n".join(text for _, text in picked)
            # "complete" = some retrieved unit covers the gold section verbatim
            complete = any(covers(gold_text, text) for _, text in picked)
            row[name] = {
                "hit1": bool(picked) and picked[0][0] == gold_doc and phrase in picked[0][1],
                "hit5": any(doc == gold_doc and phrase in text for doc, text in picked),
                "complete": complete,
                "tokens": count_tokens(ctx),
            }
        row["full_doc"] = {
            "hit1": phrase in whole,
            "hit5": phrase in whole,
            "complete": True,
            "tokens": count_tokens(whole),
        }
        rows.append(row)

    order = ["recursive", "md_header", "docmunch", "full_doc"]
    print(f"\ncorpus: {len(docs)} docs, {len(sec_units)} docmunch sections, "
          f"{len(rec_units)} recursive chunks, {len(hdr_units)} header splits; k={k}\n")
    header = f"{'system':11} {'hit@1':>9} {'hit@5':>9} {'complete':>10} {'ctx tokens':>12}"
    print(header)
    print("-" * len(header))
    for name in order:
        h1 = sum(1 for r in rows if r[name]["hit1"])
        h5 = sum(1 for r in rows if r[name]["hit5"])
        cp = sum(1 for r in rows if r[name]["complete"])
        avg = sum(r[name]["tokens"] for r in rows) / max(1, len(rows))
        print(f"{name:11} {h1:>4}/{len(rows):<4} {h5:>4}/{len(rows):<4} "
              f"{cp:>5}/{len(rows):<4} {avg:>12.0f}")
    avg_gold = sum(r["gold_tokens"] for r in rows) / max(1, len(rows))
    print(f"\naverage gold-section size: {avg_gold:.0f} tokens")

    if "--json" in sys.argv:
        out_path = sys.argv[sys.argv.index("--json") + 1]
        pathlib.Path(out_path).write_text(
            json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"per-question rows -> {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
