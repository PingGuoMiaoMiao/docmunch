#!/usr/bin/env python3
"""Blind the answer sets and build the judge pack.

The judge must not know which strategy produced which answer, otherwise it can
favour the one it expects to be better. This script maps the strategies to
letters A-D with a seeded shuffle, writes the judge pack (questions + gold
answers + the four anonymised answers), and keeps the mapping on disk so the
scorer can undo it.

--tag hard switches to the hard question set (answers spanning one section):
hard_questions.json / answers/hard_<strategy>.json / blind/hard_*.

Usage: python tools/e2e_blind.py [--seed 20261118] [--tag hard]
"""

import json
import pathlib
import random
import sys

WORK = pathlib.Path("_e2e")


def main():
    seed = 20261118
    tag = ""
    argv = sys.argv[1:]
    if "--seed" in argv:
        seed = int(argv[argv.index("--seed") + 1])
    if "--tag" in argv:
        tag = argv[argv.index("--tag") + 1]
    suffix = f"_{tag}" if tag else ""

    strategies = ["none", "full", "recursive", "docmunch"]
    questions = json.loads(
        (WORK / f"{tag + '_' if tag else ''}questions.json").read_text(encoding="utf-8"))
    answers = {}
    for strategy in strategies:
        path = WORK / "answers" / f"{tag + '_' if tag else ''}{strategy}.json"
        if not path.exists():
            print(f"missing {path}; run the {strategy} answerer first")
            return 2
        data = json.loads(path.read_text(encoding="utf-8"))
        answers[strategy] = {int(item["id"]): str(item["answer"]).strip() for item in data}

    letters = ["A", "B", "C", "D"]
    rng = random.Random(seed)
    shuffled = strategies[:]
    rng.shuffle(shuffled)
    mapping = dict(zip(letters, shuffled))

    lines = [
        "# 判分任务",
        "",
        "下面每组包含：问题、标准答案、以及四种上下文策略（A/B/C/D，已匿名打乱）给出的回答。",
        "请逐题判断每个字母的回答是否**包含标准答案里的关键事实**。",
        "",
        "判定标准：",
        "",
        "- `correct`：关键事实全部正确（表述可以不同，数字/参数/机制必须对）；",
        "- `partial`：部分正确（例如两个关键事实只答对一个），或说对方向但缺少关键事实；",
        "- `wrong`：事实错误，或回答\"无法确定\"、空、答非所问。",
        "",
        "只判断事实是否正确，**不要**因为回答更详细或更简洁而加减分。",
        "",
    ]

    for q in questions:
        qid = int(q["id"])
        lines.append(f"## 问题 {qid}：{q['question']}")
        lines.append("")
        lines.append(f"**标准答案**：{q['gold_answer']}")
        lines.append("")
        for letter in letters:
            strategy = mapping[letter]
            answer = answers[strategy].get(qid, "(缺失)")
            lines.append(f"- **{letter}**：{answer}")
        lines.append("")

    pack = WORK / "blind" / f"{tag + '_' if tag else ''}judge_pack.md"
    pack.parent.mkdir(parents=True, exist_ok=True)
    pack.write_text("\n".join(lines), encoding="utf-8")
    (WORK / "blind" / f"{tag + '_' if tag else ''}answer_key.json").write_text(
        json.dumps(mapping, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"judge pack -> {pack} ({len(questions)} questions)")
    print("mapping (keep private from the judge):", mapping)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
