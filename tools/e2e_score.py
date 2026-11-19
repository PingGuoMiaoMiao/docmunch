#!/usr/bin/env python3
"""Score the blinded verdicts and report accuracy against context cost.

correct = 1.0, partial = 0.5, wrong = 0.0. Reports per-strategy accuracy, the
strict (correct-only) rate, and the average context tokens that bought it.

The main judge covers columns A-D. A strategy added later (the truncated
full-document control) is judged in its own column E and merged here, so the
existing verdicts stay valid.

--tag hard scores the hard question set (answers spanning one section) and also
prints the LLM-free both-fact coverage from e2e_hard_prepare.py.

Usage: python tools/e2e_score.py [--json out.json] [--tag hard]
"""

import json
import pathlib
import sys

WORK = pathlib.Path("_e2e")


def load_verdicts(prefix):
    """Rows keyed by question id, each mapping letter -> verdict."""
    rows = {}
    base = WORK / "blind" / f"{prefix}verdicts.json"
    for row in json.loads(base.read_text(encoding="utf-8")):
        rows[int(row["id"])] = {k: v for k, v in row.items() if k != "id"}
    extra = WORK / "blind" / f"{prefix}verdicts_E.json"
    if extra.exists():
        for row in json.loads(extra.read_text(encoding="utf-8")):
            rows.setdefault(int(row["id"]), {})["E"] = row.get("E", "wrong")
    return rows


def main():
    tag = ""
    argv = sys.argv[1:]
    if "--tag" in argv:
        tag = argv[argv.index("--tag") + 1]
    prefix = f"{tag}_" if tag else ""

    key = json.loads((WORK / "blind" / f"{prefix}answer_key.json").read_text(encoding="utf-8"))
    if (WORK / "blind" / f"{prefix}verdicts_E.json").exists():
        key = {**key, "E": "full_trunc"}

    verdicts = load_verdicts(prefix)
    stats = json.loads((WORK / f"{prefix}context_stats.json").read_text(encoding="utf-8"))
    questions = json.loads((WORK / f"{prefix}questions.json").read_text(encoding="utf-8"))
    n = len(questions)

    per_strategy = {s: {"correct": 0, "partial": 0, "wrong": 0} for s in key.values()}
    detail = []
    for qid, row in verdicts.items():
        for letter, strategy in key.items():
            verdict = str(row.get(letter, "wrong")).strip().lower()
            if verdict not in ("correct", "partial", "wrong"):
                verdict = "wrong"
            per_strategy[strategy][verdict] += 1
            detail.append({"id": qid, "strategy": strategy, "verdict": verdict})

    order = ["none", "full_trunc", "full", "recursive", "docmunch"]
    order = [s for s in order if s in per_strategy]
    header = (f"{'strategy':11} {'correct':>9} {'partial':>9} {'wrong':>7} "
              f"{'score':>8} {'ctx tokens':>12} {'per-question':>13}")
    print(f"\nquestions: {n}\n")
    print(header)
    print("-" * len(header))
    results = {}
    for strategy in order:
        c = per_strategy[strategy]["correct"]
        p = per_strategy[strategy]["partial"]
        w = per_strategy[strategy]["wrong"]
        score = (c + 0.5 * p) / n
        ctx = stats.get(strategy, 0)
        results[strategy] = {"correct": c, "partial": p, "wrong": w,
                             "score": round(score, 4), "ctx_tokens": ctx,
                             "tokens_per_question": round(ctx / n)}
        print(f"{strategy:11} {c:>9} {p:>9} {w:>7} {score:>8.3f} {ctx:>12} "
              f"{round(ctx / n):>13}")

    cov_path = WORK / "hard_coverage.json" if tag == "hard" else None
    if cov_path and cov_path.exists():
        coverage = json.loads(cov_path.read_text(encoding="utf-8"))
        print("\nboth-fact coverage (context contains early AND late phrase):")
        for strategy in ("docmunch", "recursive", "full"):
            if strategy in coverage:
                hits = sum(1 for v in coverage[strategy].values() if v)
                print(f"  {strategy:10} {hits}/{n}")

    if "--json" in argv:
        out = argv[argv.index("--json") + 1]
        pathlib.Path(out).write_text(
            json.dumps({"per_strategy": results, "detail": detail},
                       ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"detail -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
