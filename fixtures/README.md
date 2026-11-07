# fixtures

Golden inputs for differential and regression tests.

## html/

Real pages saved on 2026-11-07, used to compare the MoonBit extractor against
the Mozilla Readability oracle (`tools/oracle/`).

| File | Source | Notes |
| --- | --- | --- |
| `moonbit-update-2026-11-05.html` | <https://www.moonbitlang.cn/updates/2026/11/05/index> | long-form release notes, Chinese, heavy headings |
| `readability-readme.html` | <https://github.com/mozilla/readability> | GitHub UI page — good noise/nav stress case |
| `arxiv-hichunk.html` | <https://arxiv.org/abs/2509.11552> | academic abstract page |

These files are third-party page snapshots kept **only** for offline testing.
They are not part of the distributed work and their own licenses still apply;
do not reuse them as project content.

## Regenerating the oracle output

```sh
cd tools/oracle
npm install
npm run oracle
```

Output lands in `tools/oracle/out/*.json` and is committed so MoonBit tests can
run without Node.
