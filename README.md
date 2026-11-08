# docmunch (MoonBit)

Structured documentation retrieval for AI agents: index a doc site or repo by its
heading hierarchy, then hand an agent **one section at a time** instead of the
whole file.

This is a from-scratch MoonBit reimplementation. It is **not** a port of an
existing codebase — see [docs/pre-research.md](docs/pre-research.md) for why
(the named reference repo is empty, and the most complete reference is
non-commercial-licensed, so only its *design* was studied).

## Status

| Phase | Scope | State |
| --- | --- | --- |
| P0 | module skeleton, section model, id/byte-offset contract | ✅ done |
| P1 | fetch: HTTPS/streaming/redirects, SSRF guard, raw cache, platform detect | ✅ done |
| P2 | DOM helpers + Readability-compatible extraction + metadata | ✅ done (3/3 fixtures, avg Jaccard 0.92) |
| P3 | HTML → CommonMark, link absolutization, golden files | ✅ done |
| P4 | section split: ATX + setext, fence-aware, hashes, stable slugs | ✅ done |
| P5 | index store, search, byte-range retrieval | ✅ done |
| P6 | MCP server (stdio) | ⏳ next |

## Quick start

```sh
moon build --target native
moon test

# fetch one URL: prints status/bytes/platform, writes .doc-index/raw/<sha256>.bin
moon run cmd/main --target native -- fetch https://docs.moonbitlang.cn/language/ffi.html

# platform fingerprint only (no network)
moon run cmd/main --target native -- detect https://github.com/mozilla/readability

# extract main content + metadata (URL or local file)
moon run cmd/main --target native -- extract fixtures/html/readability-readme.html --out-html out.html

# HTML -> CommonMark (+ absolutized links when the input is a URL)
moon run cmd/main --target native -- markdown fixtures/html/readability-readme.html --out out.md
python tools/markdown_golden.py

# section tree with byte offsets + hashes, then verify the byte contract
moon run cmd/main --target native -- toc fixtures/markdown/readability-readme.md --verify
python tools/toc_check.py

# index -> search -> retrieve (O(1) byte-range read, hash-verified)
moon run cmd/main --target native -- index fixtures/markdown/readability-readme.md --repo local
moon run cmd/main --target native -- search local readability
moon run cmd/main --target native -- section local "<id from search>" --verify

# compare extraction against the Node Readability oracle
python tools/compare.py

# 10-site smoke run (see docs/p1-smoke.md)
moon run cmd/main --target native -- smoke fixtures/smoke-urls.txt
```

`fetch` flags: `--out PATH`, `--allow-private`, `--no-cache`, `--max-bytes N`, `--timeout MS`.

Security default: loopback/RFC1918/link-local targets are refused unless
`--allow-private` is passed (the MCP server runs on the user's machine).

## Layout

```
core/      shared model: Section, DocIndex, slug + id rules, UTF-8 byte length
section/   heading-based splitting, byte offsets, hierarchy
http/      fetch stage (SSRF guard lands first, transport in P1)
extract/   mutable DOM arena + Readability-compatible scorer (P2)
md/        HTML -> CommonMark normalization (P3)
index/     JSON index + raw cache, atomic writes, version gating (P5)
mcp/       MCP tool surface and response envelope (P6)
cmd/main/  CLI entry point
fixtures/  golden documents for differential tests
tools/     test oracles (Node-based Readability reference)
docs/      pre-research, decision records, competition notes
```

## Design contracts (short version)

- Section id: `{repo}::{doc_path}::{hierarchical_slug}#{level}`.
- Byte offsets are **UTF-8 bytes**, not code units, so retrieval is
  `seek(byte_start)` + `read(byte_end - byte_start)`.
- Index holds metadata only; bodies live in the raw cache.
- Retrieval is O(1); re-index is gated by per-file `sha256` and an index version.

Full rationale and rejected alternatives: [docs/decisions.md](docs/decisions.md).

## Docs

- [docs/pre-research.md](docs/pre-research.md) — ecosystem survey, reference-implementation
  teardown, algorithm notes, and every source link used.
- [docs/decisions.md](docs/decisions.md) — ADR-style decision records (D1–D19).
- [docs/p1-smoke.md](docs/p1-smoke.md) — P1 smoke run against 10 real documentation sites.
- [docs/p2-extraction.md](docs/p2-extraction.md) — P2 extraction method, metrics and known gaps.
- [docs/p3-markdown.md](docs/p3-markdown.md) — P3 HTML→CommonMark rules, validation and known gaps.
- [docs/p4-sectioning.md](docs/p4-sectioning.md) — P4 section contract, byte-level checks and gaps.
- [docs/p5-index.md](docs/p5-index.md) — P5 storage layout, search scoring and retrieval.
- [docs/competition-brief.md](docs/competition-brief.md) — background: the MoonBit
  hackathon this project is being built for.

## License

Apache-2.0.
