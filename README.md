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
| P2 | DOM helpers + Readability-compatible extraction + metadata | ✅ done (4/4 fixtures, avg Jaccard 0.91) |
| P3 | HTML → CommonMark, link absolutization, golden files | ✅ done |
| P4 | section split: ATX + setext, fence-aware, hashes, stable slugs | ✅ done |
| P5 | index store, search, byte-range retrieval | ✅ done |
| P6 | MCP server (stdio, 8 tools) | ✅ done |
| P7 | link-density pruning, CI, benchmark, delivery docs | ✅ done |
| P8 | body-aware search (section keywords), MCP HTTP transport | ✅ done |
| P9 | audit fixes: repo identity/delete, doc_path rules, MCP response cap, frontmatter/fence, cache TTL/retry, stderr, DNS double-resolve + index mutex | ✅ done |
| P10 | charset-aware decoding, cache final_url, explicit JSON extends, acceptance self-check | ✅ done |
| P11 | maintainability pass: core/text package, one registration per MCP tool, split the two 500+ line files | ✅ done |

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
moon run cmd/main --target native -- repos
moon run cmd/main --target native -- delete local

# MCP server: stdio (default) or Streamable HTTP
python tools/mcp_e2e.py
moon run cmd/main --target native -- mcp --http --port 4240 --root .doc-index
python tools/mcp_http_e2e.py

# compare extraction against the Node Readability oracle
python tools/compare.py

# 10-site smoke run (see docs/p1-smoke.md)
moon run cmd/main --target native -- smoke fixtures/smoke-urls.txt
```

`fetch` flags: `--out PATH`, `--allow-private`, `--no-cache`, `--max-bytes N`,
`--timeout MS`, `--cache-ttl MS` (default 24h), `--retries N` (default 2).
`get_section` / `get_section_context` accept `max_bytes` (default 8000; `0` or
`-1` means no cap) and report `truncated` + `total_bytes`, so a client can ask
for more when a section was cut.

Security default: loopback/RFC1918/link-local targets are refused unless
`--allow-private` is passed (the MCP server runs on the user's machine).

## Pre-submission acceptance check

`tools/acceptance.py` is the script behind the `moonbit-hackathon-acceptance`
skill: it checks MoonBit-primary code, commit history, build/tests, README,
licences, AI explainability, demo entry and test density.

```sh
python tools/acceptance.py --since 2026-11-01   # round start date
```

Exit code 0 means no FAIL. WARN rows are "a human should look", FAIL rows must
be fixed before submitting.

## Layout

```
core/      shared model: Section, DocIndex, slug + id rules, UTF-8 byte length
section/   heading-based splitting, byte offsets, hierarchy
http/      fetch stage: SSRF guard, raw cache (TTL/retry), doc_path rules
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
- `doc_path` is the URL pathname (plus a short hash when the URL has a query or
  fragment) or a `\`-normalized local path; CLI and MCP share the same rules.
- Byte offsets are **UTF-8 bytes**, not code units, so retrieval is
  `seek(byte_start)` + `read(byte_end - byte_start)`.
- Index holds metadata only; bodies live in the raw cache.
- Retrieval is O(1); re-index is gated by per-file `sha256` and an index version.

Full rationale and rejected alternatives: [docs/decisions.md](docs/decisions.md).

## Docs

- [docs/pre-research.md](docs/pre-research.md) — ecosystem survey, reference-implementation
  teardown, algorithm notes, and every source link used.
- [docs/decisions.md](docs/decisions.md) — ADR-style decision records (D1–D41).
- [docs/p1-smoke.md](docs/p1-smoke.md) — P1 smoke run against 10 real documentation sites.
- [docs/p2-extraction.md](docs/p2-extraction.md) — P2 extraction method, metrics and known gaps.
- [docs/p3-markdown.md](docs/p3-markdown.md) — P3 HTML→CommonMark rules, validation and known gaps.
- [docs/p4-sectioning.md](docs/p4-sectioning.md) — P4 section contract, byte-level checks and gaps.
- [docs/p5-index.md](docs/p5-index.md) — P5 storage layout, search scoring and retrieval.
- [docs/p6-mcp.md](docs/p6-mcp.md) — P6 MCP tool surface, protocol notes and e2e evidence.
- [docs/p7-delivery.md](docs/p7-delivery.md) — P7 delivery metrics, audit fixes and known gaps.
- [docs/p8-enhancements.md](docs/p8-enhancements.md) — P8 body-aware search and MCP HTTP transport.
- [docs/competition-brief.md](docs/competition-brief.md) — background: the MoonBit
  hackathon this project is being built for.

## License

Apache-2.0.
