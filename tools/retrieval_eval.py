#!/usr/bin/env python3
"""Retrieval evaluation: does section-level retrieval actually beat the alternatives?

Three systems, same corpus (this project's docs/), same questions:

  full-doc   no retrieval at all: the whole corpus, truncated to a budget
  chunk-bm25 fixed 512-char chunks with 80-char overlap, BM25 over chunks
  section    docmunch: heading-aligned sections, BM25 over sections

Metrics per question:
  hit@1 / hit@5   does the retrieved context contain the gold phrase
  ctx_tokens      size of the context handed to the model (estimated)
  complete        is the gold section included whole (not cut by a boundary)

Usage: python tools/retrieval_eval.py [--k 5] [--json out.json]
Exit code 0 always (it reports, it does not judge).
"""

import json
import math
import pathlib
import re
import subprocess
import sys

def read_doc(path):
    """Read a document exactly as its bytes are on disk.

    read_text() would translate CRLF to LF, which silently shifts every byte
    offset the index records. Never use read_text for files we slice by offset.
    """
    return pathlib.Path(path).read_bytes().decode("utf-8")

CORPUS = pathlib.Path("docs")
REPO = "eval"
ROOT = pathlib.Path(".doc-index-eval")

# question -> (doc_path, exact heading title, phrase that must appear in context)
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
    """ASCII words lowercased + CJK bigrams; same idea as core/text/tokens.mbt."""
    out = []
    ascii_run = []
    cjk_run = []

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


def est_tokens(text):
    """Rough token estimate: ASCII ~4 chars/token, CJK ~1 char/token."""
    ascii_chars = sum(1 for c in text if ord(c) < 0x2E80)
    cjk_chars = len(text) - ascii_chars
    return int(math.ceil(ascii_chars / 4.0 + cjk_chars))


class BM25:
    def __init__(self, docs, k1=1.2, b=0.75):
        self.k1, self.b = k1, b
        self.docs = docs
        self.tokens = [tokenize(d) for d in docs]
        self.lens = [len(t) for t in self.tokens]
        self.avg = sum(self.lens) / max(1, len(self.lens))
        self.df = {}
        self.tf = []
        for toks in self.tokens:
            counts = {}
            for t in toks:
                counts[t] = counts.get(t, 0) + 1
            self.tf.append(counts)
            for t in counts:
                self.df[t] = self.df.get(t, 0) + 1

    def search(self, query, k):
        q = tokenize(query)
        n = len(self.docs)
        scores = []
        for i in range(n):
            score = 0.0
            for term in q:
                df = self.df.get(term, 0)
                if df == 0:
                    continue
                idf = math.log(1.0 + (n - df + 0.5) / (df + 0.5))
                tf = self.tf[i].get(term, 0)
                if tf == 0:
                    continue
                norm = 1.0 - self.b + self.b * self.lens[i] / self.avg
                score += idf * tf * (self.k1 + 1.0) / (tf + self.k1 * norm)
            if score > 0:
                scores.append((score, i))
        scores.sort(key=lambda p: (-p[0], p[1]))
        return [i for _, i in scores[:k]]


def split_chunks(text, size=512, overlap=80):
    chunks, start = [], 0
    while start < len(text):
        chunks.append(text[start:start + size])
        if start + size >= len(text):
            break
        start += size - overlap
    return chunks


def run_cli(args):
    exe = pathlib.Path("_build/native/debug/build/cmd/main/main.exe")
    if not exe.exists():
        exe = pathlib.Path("_build/native/debug/build/cmd/main/main")
    proc = subprocess.run([str(exe), *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    return proc.returncode, proc.stdout + proc.stderr


def build_docmunch_index():
    code, out = run_cli(["index-dir", str(CORPUS), "--repo", REPO, "--root", str(ROOT)])
    if code != 0:
        print(out)
        raise SystemExit("index-dir failed")


def docmunch_search(query, k):
    code, out = run_cli(["search", REPO, query, "--limit", str(k), "--root", str(ROOT)])
    ids = re.findall(r"id=(\S+)", out)
    return ids


def load_index():
    path = ROOT / REPO / "index.json"
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    k = 5
    if "--k" in sys.argv:
        k = int(sys.argv[sys.argv.index("--k") + 1])
    build_docmunch_index()
    index = load_index()
    sections = index["sections"]

    # docmunch: sections grouped by document so we can fetch exact text
    doc_text = {}
    for path in sorted(CORPUS.glob("*.md")):
        doc_text["docs/" + path.name] = read_doc(path)

    # baseline 2: fixed chunks over the same corpus
    chunk_texts, chunk_doc = [], []
    for doc, text in doc_text.items():
        for chunk in split_chunks(text):
            chunk_texts.append(chunk)
            chunk_doc.append(doc)
    chunk_bm25 = BM25(chunk_texts)

    # baseline 1: the whole corpus, truncated to the same budget we allow section
    whole = "\n\n".join(doc_text.values())

    rows = []
    for question, gold_doc, gold_title, phrase in GOLD:
        # --- section retrieval (docmunch)
        ids = docmunch_search(question, k)
        sec_texts, sec_hit1, sec_hit5, complete = [], False, False, False
        for rank, sid in enumerate(ids, start=1):
            sec = next((s for s in sections if s["id"] == sid), None)
            if sec is None:
                continue
            # read the section text out of the cached document
            raw = doc_text.get(sec["doc_path"], "")
            raw_bytes = raw.encode("utf-8")
            body = raw_bytes[sec["byte_start"]:sec["byte_end"]].decode(
                "utf-8", errors="replace")
            sec_texts.append(body)
            if phrase in body and sec["doc_path"] == gold_doc:
                if rank == 1:
                    sec_hit1 = True
                sec_hit5 = True
            if sec["doc_path"] == gold_doc and sec["title"] == gold_title:
                complete = True
        sec_ctx = "\n\n".join(sec_texts)

        # --- chunk retrieval
        idxs = chunk_bm25.search(question, k)
        ch_texts = [chunk_texts[i] for i in idxs]
        ch_ctx = "\n\n".join(ch_texts)
        ch_hit1 = any(
            phrase in chunk_texts[i] and chunk_doc[i] == gold_doc
            for i in idxs[:1]
        )
        ch_hit5 = any(phrase in chunk_texts[i] and chunk_doc[i] == gold_doc for i in idxs)
        # a chunk system is "complete" only when every chunk of the gold section
        # is present; approximate by requiring the heading and the phrase in the
        # same retrieved chunk.
        ch_complete = any(
            phrase in chunk_texts[i] and gold_title in chunk_texts[i] for i in idxs
        )

        # --- full corpus
        full_ctx = whole
        full_hit = phrase in full_ctx

        rows.append({
            "q": question,
            "gold": gold_doc,
            "sec": {"hit1": sec_hit1, "hit5": sec_hit5, "complete": complete,
                    "tokens": est_tokens(sec_ctx)},
            "chunk": {"hit1": ch_hit1, "hit5": ch_hit5, "complete": ch_complete,
                      "tokens": est_tokens(ch_ctx)},
            "full": {"hit1": full_hit, "hit5": full_hit, "complete": full_hit,
                     "tokens": est_tokens(full_ctx)},
        })

    def agg(system, key):
        hits = sum(1 for r in rows if r[system][key])
        return hits, len(rows)

    print(f"\ncorpus: {len(doc_text)} docs, {len(sections)} sections, "
          f"{len(chunk_texts)} chunks; k={k}\n")
    header = f"{'system':10} {'hit@1':>10} {'hit@5':>10} {'complete':>10} {'avg ctx tokens':>15}"
    print(header)
    print("-" * len(header))
    for system in ("sec", "chunk", "full"):
        h1, n = agg(system, "hit1")
        h5, _ = agg(system, "hit5")
        cp, _ = agg(system, "complete")
        avg = sum(r[system]["tokens"] for r in rows) / len(rows)
        print(f"{system:10} {h1}/{n:<8} {h5}/{n:<8} {cp}/{n:<8} {avg:15.0f}")

    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
        pathlib.Path(out).write_text(json.dumps(rows, ensure_ascii=False, indent=2),
                                     encoding="utf-8")
        print(f"\nper-question rows -> {out}")


if __name__ == "__main__":
    main()
