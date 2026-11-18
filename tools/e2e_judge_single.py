#!/usr/bin/env python3
"""Build a one-column judge pack (used to add a strategy without re-judging).

Adding a fifth strategy would mean re-judging everything to keep the blinding
consistent, which is wasteful: the existing A-D verdicts are still valid, and a
fresh column is blind on its own as long as it is labelled with a letter the
judge has not seen mapped to a strategy.

Usage:
  python tools/e2e_judge_single.py --strategy full_trunc --letter E
"""

import argparse
import json
import pathlib

WORK = pathlib.Path("_e2e")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--strategy", required=True)
    parser.add_argument("--letter", required=True)
    args = parser.parse_args()

    questions = json.loads((WORK / "questions.json").read_text(encoding="utf-8"))
    answers_raw = json.loads(
        (WORK / "answers" / f"{args.strategy}.json").read_text(encoding="utf-8"))
    answers = {int(item["id"]): str(item["answer"]).strip() for item in answers_raw}

    lines = [
        "# 判分任务（单列）",
        "",
        f"下面每题给出：问题、标准答案、以及 **{args.letter} 组**的回答。",
        "请逐题判断该回答是否包含标准答案里的关键事实。",
        "",
        "- `correct`：关键事实全部正确（表述可不同，数字/参数/机制必须对）；",
        "- `partial`：部分正确，或方向对但缺关键事实；",
        "- `wrong`：事实错误、答非所问、或回答\"无法确定\"。",
        "",
        "只看事实正确性，不比较详略。只看这一组，不要猜测其他组。",
        "",
    ]
    for q in questions:
        qid = int(q["id"])
        lines.append(f"## 问题 {qid}：{q['question']}")
        lines.append("")
        lines.append(f"**标准答案**：{q['gold_answer']}")
        lines.append("")
        lines.append(f"- **{args.letter}**：{answers.get(qid, '(缺失)')}")
        lines.append("")

    pack = WORK / "blind" / f"judge_pack_{args.letter}.md"
    pack.write_text("\n".join(lines), encoding="utf-8")
    print(f"pack -> {pack} ({len(questions)} questions, strategy={args.strategy})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
