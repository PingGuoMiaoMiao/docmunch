// docmunch — structured documentation retrieval for AI agents, in MoonBit.
// Module layout: one package per pipeline stage, see docs/pre-research.md.

name = "PingGuoMiaoMiao/docmunch"

version = "0.2.1"

readme = "README.md"

repository = "https://github.com/PingGuoMiaoMiao/docmunch"

license = "Apache-2.0"

keywords = [ "mcp", "rag", "markdown", "documentation", "chunking" ]

preferred_target = "native"

description = "Index docs by heading hierarchy with byte offsets; serve sections over MCP."

import {
  "moonbitlang/async@0.22.7",
  "tonyfettes/url@0.3.5",
  "gmlewis/sha256@0.18.2",
  "moonbit-community/html@0.2.3",
  "moonbit-community/cmark@0.4.12",
  "colmugx/mcp@0.18.2",
  "LL728/moon_encoding@0.2.0",
}
