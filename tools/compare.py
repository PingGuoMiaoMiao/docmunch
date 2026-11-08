#!/usr/bin/env python3
"""Compare docmunch extraction against the Mozilla Readability oracle.

Usage: python tools/compare.py [oracle_dir] [mine_dir]

Metrics per fixture:
  title   exact (normalized) match, or containment (Readability sometimes adds a
          "Site - " prefix to the same title, so containment is the honest rule)
  len     our text length / oracle text length
  jac     word-set Jaccard similarity over the first 40k chars

Exit code is 1 when a fixture is missing or the title does not match.
"""

import json
import pathlib
import re
import sys

ORACLE = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "tools/oracle/out")
MINE = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "tools/oracle/out-moonbit")

WORD = re.compile(r"\w+", re.UNICODE)


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s or "").strip().lower()


def words(s: str) -> set[str]:
    return set(WORD.findall((s or "").lower()[:40000]))


def title_ok(expected: str, got: str) -> bool:
    a, b = norm(expected), norm(got)
    if a == b:
        return True
    if len(a) >= 10 and len(b) >= 10 and (a in b or b in a):
        return True
    return False


def main() -> int:
    rows = []
    for path in sorted(ORACLE.glob("*.json")):
        name = path.stem
        mine_path = MINE / f"{name}.json"
        if not mine_path.exists():
            rows.append((name, "MISSING", "-", "-", ""))
            continue
        exp = json.loads(path.read_text(encoding="utf-8"))
        got = json.loads(mine_path.read_text(encoding="utf-8"))
        ok = title_ok(exp.get("title") or "", got.get("title") or "")
        exp_len = max(1, len(exp.get("textContent") or ""))
        len_ratio = len(got.get("text") or "") / exp_len
        a, b = words(exp.get("textContent") or ""), words(got.get("text") or "")
        jac = len(a & b) / max(1, len(a | b))
        rows.append((name, "ok" if ok else "diff", f"{len_ratio:.2f}", f"{jac:.2f}", norm(got.get("title"))))

    print(f"{'fixture':32} {'title':6} {'len':>5} {'jac':>5}  title(mine)")
    for r in rows:
        print(f"{r[0]:32} {r[1]:6} {r[2]:>5} {r[3]:>5}  {r[4][:56]}")

    ok = sum(1 for r in rows if r[1] == "ok")
    nums = [r for r in rows if r[1] != "MISSING"]
    if nums:
        avg_jac = sum(float(r[3]) for r in nums) / len(nums)
        avg_len = sum(float(r[2]) for r in nums) / len(nums)
        print(f"\ntitle match: {ok}/{len(rows)}   avg len ratio: {avg_len:.2f}   avg jaccard: {avg_jac:.2f}")
    return 0 if ok == len(rows) and len(rows) > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
