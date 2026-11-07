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
| P1 | fetch + platform detect | ⏳ next |
| P2 | DOM + Readability-compatible extraction | ⏳ |
| P3 | HTML → CommonMark | ⏳ |
| P4 | section split (ATX only today) | 🟡 partial |
| P5 | index store, search, byte-range retrieval | ⏳ |
| P6 | MCP server (stdio) | ⏳ |

## Quick start

```sh
moon build --target native
moon test
moon run cmd/main --target native
```

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
- [docs/decisions.md](docs/decisions.md) — ADR-style decision records (D1–D14).
- [docs/competition-brief.md](docs/competition-brief.md) — background: the MoonBit
  hackathon this project is being built for.

## License

Apache-2.0.
