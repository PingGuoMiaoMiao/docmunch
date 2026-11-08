// docmunch — structured documentation retrieval for AI agents, in MoonBit.
// Module layout: one package per pipeline stage, see docs/pre-research.md.

name = "pingguomiaomiao/docmunch"

version = "0.1.0"

readme = "README.md"

license = "Apache-2.0"

keywords = [ "mcp", "rag", "markdown", "documentation", "chunking" ]

preferred_target = "native"

description = "Index docs by heading hierarchy with byte offsets; serve sections over MCP."

import {
  "moonbitlang/async@0.22.7",
  "tonyfettes/url@0.3.5",
  "gmlewis/sha256@0.18.2",
}
