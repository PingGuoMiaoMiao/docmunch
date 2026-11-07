// MCP serving stage (P6).
//
// The transport and JSON-RPC framing come from colmugx/mcp (stdio first, HTTP
// optional). This package owns the tool surface and the response envelope only.

///|
/// Tool surface for v1. Kept deliberately small: every tool is a contract that
/// has to stay compatible (docs/decisions.md D10).
pub fn tool_names() -> Array[String] {
  [
    "index_url", "index_local", "list_repos", "get_toc", "get_section", "get_section_context",
    "search_sections", "delete_index",
  ]
}
