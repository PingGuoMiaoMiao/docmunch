#!/usr/bin/env python3
"""Score the blinded verdicts and report accuracy against context cost.

correct = 1.0, partial = 0.5, wrong = 0.0. Reports per-strategy accuracy, the
strict (correct-only) rate, and the average context tokens that bought it.

The main judge covers columns A-D. A strategy added later (the truncated
full-document control) is judged in its own column E and merged here, so the
existing verdicts stay valid.

Usage: python tools/e2e_score.py [--json out.json]
"""

import json
import pathlib
import sys

WORK = pathlib.Path("_e2e")


def load_verdicts():
    """Rows keyed by question id, each mapping letter -> verdict."""
    rows = {}
    for row in json.loads((WORK / "blind" / "verdicts.json").read_text(encoding="utf-8")):
        rows[int(row["id"])] = {k: v for k, v in row.items() if k != "id"}
    extra = WORK / "blind" / "verdicts_E.json"
    if extra.exists():
        for row in json.loads(extra.read_text(encoding="utf-8")):
            rows.setdefault(int(row["id"]), {})["E"] = row.get("E", "wrong")
    return rows


def main():
    key = json.loads((WORK / "blind" / "answer_key.json").read_text(encoding="utf-8"))
    if (WORK / "blind" / "verdicts_E.json").exists():
        key = {**key, "E": "full_trunc"}

    verdicts = load_verdicts()
    stats = json.loads((WORK / "context_stats.json").read_text(encoding="utf-8"))
    questions = json.loads((WORK / "questions.json").read_text(encoding="utf-8"))
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

    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
        pathlib.Path(out).write_text(
            json.dumps({"per_strategy": results, "detail": detail},
                       ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"detail -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
