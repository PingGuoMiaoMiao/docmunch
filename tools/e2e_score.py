#!/usr/bin/env python3
"""Score the blinded verdicts and report accuracy against context cost.

correct = 1.0, partial = 0.5, wrong = 0.0. Reports per-strategy accuracy, the
strict (correct-only) rate, and the average context tokens that bought it.

Usage: python tools/e2e_score.py [--json out.json]
"""

import json
import pathlib
import sys

WORK = pathlib.Path("_e2e")


def main():
    key = json.loads((WORK / "blind" / "answer_key.json").read_text(encoding="utf-8"))
    verdicts = json.loads((WORK / "blind" / "verdicts.json").read_text(encoding="utf-8"))
    stats = json.loads((WORK / "context_stats.json").read_text(encoding="utf-8"))

    questions = json.loads((WORK / "questions.json").read_text(encoding="utf-8"))
    n = len(questions)

    per_strategy = {s: {"correct": 0, "partial": 0, "wrong": 0} for s in key.values()}
    detail = []
    for row in verdicts:
        for letter, strategy in key.items():
            verdict = str(row.get(letter, "wrong")).strip().lower()
            if verdict not in ("correct", "partial", "wrong"):
                verdict = "wrong"
            per_strategy[strategy][verdict] += 1
            detail.append({"id": row.get("id"), "strategy": strategy, "verdict": verdict})

    order = ["none", "full", "recursive", "docmunch"]
    header = f"{'strategy':11} {'correct':>9} {'partial':>9} {'wrong':>7} {'score':>8} {'ctx tokens':>12}"
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
        results[strategy] = {
            "correct": c, "partial": p, "wrong": w,
            "score": round(score, 4), "ctx_tokens": ctx,
        }
        print(f"{strategy:11} {c:>9} {p:>9} {w:>7} {score:>8.3f} {ctx:>12}")

    best = max(order, key=lambda s: results[s]["score"])
    print(f"\nhighest score: {best} ({results[best]['score']:.3f})")

    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
        pathlib.Path(out).write_text(
            json.dumps({"per_strategy": results, "detail": detail}, ensure_ascii=False, indent=2),
            encoding="utf-8")
        print(f"detail -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
