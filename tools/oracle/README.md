# tools/oracle

Test-time only. Runs Mozilla Readability (via jsdom) over `fixtures/html/` and
writes expected JSON snapshots that the MoonBit extractor tests diff against.

Node is **not** a runtime dependency of docmunch (D5 in `docs/decisions.md`).

```sh
npm install
npm run oracle        # reads ../../fixtures/html, writes ./out
```

Add `out/` and `node_modules/` are git-ignored except the generated `out/*.json`,
which is committed so `moon test` stays Node-free.
