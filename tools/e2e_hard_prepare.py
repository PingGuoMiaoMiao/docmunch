#!/usr/bin/env python3
"""Prepare the HARD end-to-end question set: answers that span one section.

Motivation: the first e2e run (docs/e2e-agent-eval.md) saturated - every
retrieval strategy answered all 12 single-fact questions correctly. The natural
follow-up is a set built to probe the one failure mode section-aligned splitting
is designed to prevent: an answer that needs two facts from the same section,
far enough apart that a 512-char chunk cannot hold both.

This script is deliberately honest about being a stress test:

* every question is mechanically validated - both gold phrases must exist
  verbatim inside their section and sit >= 400 chars apart;
* besides building the context packs it reports "both-fact coverage": whether
  each strategy's retrieved context actually contains both phrases. That is an
  LLM-free measurement of exactly what the question set probes.

Strategies: none / full / recursive / docmunch (same definitions as e2e_prepare).

Usage: python tools/e2e_hard_prepare.py
"""

import json
import pathlib
import shutil
import subprocess
import sys

import tiktoken
from langchain_text_splitters import RecursiveCharacterTextSplitter

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from e2e_prepare import tokenize, top_k, resolve_exe  # noqa: E402

def read_doc(path):
    """Read a document exactly as its bytes are on disk.

    read_text() would translate CRLF to LF, which silently shifts every byte
    offset the index records. Never use read_text for files we slice by offset.
    """
    return pathlib.Path(path).read_bytes().decode("utf-8")

WORK = pathlib.Path("_e2e")
QUESTIONS = WORK / "hard_questions.json"
DOCS_DIR = pathlib.Path("docs")
REPO = "hard"
ROOT = WORK / "hard_index"
CTX_DIR = WORK / "hard_contexts"
K = 5
MIN_DISTANCE = 400
ENCODER = tiktoken.get_encoding("cl100k_base")
EXE = resolve_exe()


def tokens(text):
    return len(ENCODER.encode(text))


def validate(questions, sections_by_title):
    problems = []
    for q in questions:
        key = (q["doc"], q["section_title"])
        text = sections_by_title.get(key)
        if text is None:
            problems.append(f"q{q['id']}: section not found: {key}")
            continue
        early, late = q.get("early_phrase", ""), q.get("late_phrase", "")
        ei, li = text.find(early), text.find(late)
        if ei < 0:
            problems.append(f"q{q['id']}: early_phrase not in section")
        if li < 0:
            problems.append(f"q{q['id']}: late_phrase not in section")
        if ei >= 0 and li >= 0 and abs(li - ei) < MIN_DISTANCE:
            problems.append(
                f"q{q['id']}: phrases only {abs(li - ei)} chars apart (< {MIN_DISTANCE})")
    return problems


def main():
    if not EXE.exists():
        print(f"missing {EXE}; run `moon build --target native`")
        return 2
    if not QUESTIONS.exists():
        print(f"missing {QUESTIONS}; run the question generator first")
        return 2
    questions = json.loads(QUESTIONS.read_text(encoding="utf-8"))

    docs = {f"docs/{p.name}": read_doc(p)
            for p in sorted(DOCS_DIR.glob("*.md"))}

    # index the whole docs/ tree with docmunch itself
    if ROOT.exists():
        shutil.rmtree(ROOT)
    subprocess.run([str(EXE), "index-dir", str(DOCS_DIR), "--repo", REPO,
                    "--root", str(ROOT)], check=True, capture_output=True,
                   text=True, encoding="utf-8", errors="replace")
    index = json.loads((ROOT / REPO / "index.json").read_text(encoding="utf-8"))

    sec_units = []
    sections_by_title = {}
    for sec in index["sections"]:
        source = docs.get(sec["doc_path"])
        if source is None:
            continue
        raw = source.encode("utf-8")
        body = raw[sec["byte_start"]:sec["byte_end"]].decode("utf-8", "replace")
        sec_units.append((sec["doc_path"], body))
        sections_by_title[(sec["doc_path"], sec["title"])] = body

    problems = validate(questions, sections_by_title)
    if problems:
        print("question set FAILED validation:")
        for p in problems:
            print("  " + p)
        return 1
    print(f"validated {len(questions)} questions: both phrases present, "
          f">= {MIN_DISTANCE} chars apart")

    # recursive chunks over the same corpus
    splitter = RecursiveCharacterTextSplitter(chunk_size=512, chunk_overlap=80)
    rec_units = []
    for doc, text in docs.items():
        for chunk in splitter.split_text(text):
            rec_units.append((doc, chunk))

    whole = "\n\n".join(f"<!-- {name} -->\n{text}" for name, text in docs.items())

    question_list = "\n".join(f"{q['id']}. {q['question']}" for q in questions)
    CTX_DIR.mkdir(parents=True, exist_ok=True)
    stats = {}

    def write_pack(name, text):
        (CTX_DIR / f"{name}.md").write_text(text, encoding="utf-8")
        stats[name] = tokens(text)

    write_pack("none", f"""# 任务

回答下面 {len(questions)} 个问题。**没有任何参考材料**，凭你自己的知识回答。
不确定就在 `answer` 里写"无法确定"。

## 问题

{question_list}
""")

    write_pack("full", f"""# 任务

回答下面 {len(questions)} 个问题。参考材料是完整文档语料（附在最后）。
只根据材料回答；材料里没有的写"无法确定"。

## 问题

{question_list}

## 参考材料（全文）

{whole}
""")

    coverage = {}
    for strategy, units in (("recursive", rec_units), ("docmunch", sec_units)):
        parts = ["# 任务", "",
                 f"回答下面 {len(questions)} 个问题。每题下方给出检索到的参考片段。",
                 "只根据该题下方的片段回答；片段里没有的写\"无法确定\"，不要用记忆补。",
                 "", "## 问题与参考片段", ""]
        covered = 0
        for q in questions:
            parts.append(f"### 问题 {q['id']}：{q['question']}")
            picked = top_k(units, q["question"], K)
            ctx = "\n\n".join(t for _, t in picked)
            both = q["early_phrase"] in ctx and q["late_phrase"] in ctx
            covered += both
            coverage.setdefault(strategy, {})[q["id"]] = both
            if not picked:
                parts.append("（没有检索到任何片段）")
            for i, (doc, text) in enumerate(picked, start=1):
                parts.append(f"\n片段 {i}（来自 {pathlib.Path(doc).name}）：\n")
                parts.append("~~~")
                parts.append(text.strip())
                parts.append("~~~")
            parts.append("")
        write_pack(strategy, "\n".join(parts))

    # mechanical both-fact coverage (LLM-free)
    for q in questions:
        coverage.setdefault("full", {})[q["id"]] = True
    print(f"\nboth-fact coverage (retrieved context contains early AND late phrase):")
    for strategy in ("docmunch", "recursive", "full"):
        hits = sum(1 for v in coverage[strategy].values() if v)
        print(f"  {strategy:10} {hits}/{len(questions)}")

    (WORK / "hard_context_stats.json").write_text(
        json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")
    (WORK / "hard_coverage.json").write_text(
        json.dumps(coverage, ensure_ascii=False, indent=2), encoding="utf-8")

    print("\ncontext packs (tokens):")
    for name, value in stats.items():
        print(f"  {name:10} {value:>7}")
    print(f"\ncorpus: {len(docs)} docs, {len(sec_units)} sections, {len(rec_units)} chunks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
