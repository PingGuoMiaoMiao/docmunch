// MCP tools that only read the index.
//
// Split out of server.mbt so build_server stays a short assembly list (D49).

///|
fn register_list_repos(
  server : @mcpsdk.MCPServer,
  root : String,
) -> @mcpsdk.MCPServer raise @mcpsdk.MCPError {
  server.tool(
    "list_repos",
    "List documentation repositories that have an index.",
    schema("", ""),
    async fn(_ctx, _args) {
      let repos = @index.list_repos(root) catch {
        e => return failure("list failed: \{e.to_string()}")
      }
      let sb = StringBuilder::StringBuilder()
      sb.write_string("{\"repos\":[")
      for i = 0; i < repos.length(); i = i + 1 {
        if i > 0 {
          sb.write_char(',')
        }
        sb.write_string(@text.json_escape(repos[i]))
      }
      sb.write_string("]}")
      Ok(text_result(sb.to_string()))
    },
  )
}

///|
fn register_get_toc(
  server : @mcpsdk.MCPServer,
  root : String,
) -> @mcpsdk.MCPServer raise @mcpsdk.MCPError {
  server.tool(
    "get_toc",
    "Return every section of a repo in document order (no bodies).",
    schema(prop_str("repo", "Repo name."), "\"repo\""),
    async fn(_ctx, args) {
      let repo = arg_str(args, "repo")
      let index = match @index.load_index(root, repo) {
        Some(i) => i
        None => return failure("repo not indexed: \{repo}")
      }
      Ok(text_result(sections_json(repo, index.sections)))
    },
  )
}

///|
fn register_get_section(
  server : @mcpsdk.MCPServer,
  root : String,
) -> @mcpsdk.MCPServer raise @mcpsdk.MCPError {
  server.tool(
    "get_section",
    "Return one section's Markdown by id (byte-range read; optional hash verify and byte cap).",
    schema(
      prop_str("repo", "Repo name.") +
      "," +
      prop_str("id", "Section id from get_toc/search_sections.") +
      "," +
      prop_bool("verify", "Re-hash the retrieved bytes.") +
      "," +
      prop_int(
        "max_bytes", "Max Markdown bytes to return, default 8000; 0 = no limit.",
      ),
      "\"repo\",\"id\"",
    ),
    async fn(_ctx, args) {
      let repo = arg_str(args, "repo")
      let id = arg_str(args, "id")
      let index = match @index.load_index(root, repo) {
        Some(i) => i
        None => return failure("repo not indexed: \{repo}")
      }
      let (text, ok) = @index.get_section_text(
        root,
        repo,
        index,
        id,
        verify=arg_bool(args, "verify"),
      ) catch {
        e => return failure("read failed: \{e.to_string()}")
      }
      if text == "" && !ok {
        return failure("section not found: \{id}")
      }
      // Verify the full bytes first, then cap the payload: truncation must not
      // make a matching section look corrupt.
      let max_bytes = arg_int(args, "max_bytes", 8000)
      let total_bytes : Int32 = @utf8.encode(text).length()
      let markdown = @text.truncate_utf8(text, max_bytes)
      let truncated = max_bytes > 0 && total_bytes > max_bytes
      Ok(
        text_result(
          "{\"verified\":\{ok},\"truncated\":\{truncated},\"total_bytes\":\{total_bytes},\"markdown\":\{@text.json_escape(markdown)}}",
        ),
      )
    },
  )
}

///|
fn register_get_section_context(
  server : @mcpsdk.MCPServer,
  root : String,
) -> @mcpsdk.MCPServer raise @mcpsdk.MCPError {
  server.tool(
    "get_section_context",
    "Return a section with its ancestor chain and child summaries.",
    schema(
      prop_str("repo", "Repo name.") +
      "," +
      prop_str("id", "Section id.") +
      "," +
      prop_int(
        "max_bytes", "Max Markdown bytes for the section body, default 8000; 0 = no limit.",
      ),
      "\"repo\",\"id\"",
    ),
    async fn(_ctx, args) {
      let repo = arg_str(args, "repo")
      let id = arg_str(args, "id")
      let index = match @index.load_index(root, repo) {
        Some(i) => i
        None => return failure("repo not indexed: \{repo}")
      }
      let section = match @index.section_by_id(index, id) {
        Some(s) => s
        None => return failure("section not found: \{id}")
      }
      let (text, ok) = @index.get_section_text(
        root,
        repo,
        index,
        id,
        verify=false,
      ) catch {
        e => return failure("read failed: \{e.to_string()}")
      }
      let max_bytes = arg_int(args, "max_bytes", 8000)
      let total_bytes : Int32 = @utf8.encode(text).length()
      let markdown = @text.truncate_utf8(text, max_bytes)
      let truncated = max_bytes > 0 && total_bytes > max_bytes
      let ancestors = @index.ancestors_of(index, section)
      let children = @index.children_of(index, section)
      let sb = StringBuilder::StringBuilder()
      sb.write_string("{\"ancestors\":[")
      for i = 0; i < ancestors.length(); i = i + 1 {
        if i > 0 {
          sb.write_char(',')
        }
        let a = ancestors[i]
        sb.write_string(
          "{\"id\":\{@text.json_escape(a.id)},\"level\":\{a.level},\"title\":\{@text.json_escape(a.title)}}",
        )
      }
      sb.write_string("],\"children\":[")
      for i = 0; i < children.length(); i = i + 1 {
        if i > 0 {
          sb.write_char(',')
        }
        let c = children[i]
        sb.write_string(
          "{\"id\":\{@text.json_escape(c.id)},\"level\":\{c.level},\"title\":\{@text.json_escape(c.title)}}",
        )
      }
      sb.write_string(
        "],\"section\":{\"id\":\{@text.json_escape(section.id)},\"title\":\{@text.json_escape(section.title)},\"verified\":\{ok},\"truncated\":\{truncated},\"total_bytes\":\{total_bytes},\"markdown\":\{@text.json_escape(markdown)}}}",
      )
      Ok(text_result(sb.to_string()))
    },
  )
}

///|
fn register_search_sections(
  server : @mcpsdk.MCPServer,
  root : String,
) -> @mcpsdk.MCPServer raise @mcpsdk.MCPError {
  server.tool(
    "search_sections",
    "Weighted search over section titles and paths. Returns summaries only.",
    schema(
      prop_str("repo", "Repo name.") +
      "," +
      prop_str("query", "Search text.") +
      "," +
      prop_int("limit", "Max hits, default 10."),
      "\"repo\",\"query\"",
    ),
    async fn(_ctx, args) {
      let repo = arg_str(args, "repo")
      let query = arg_str(args, "query")
      let index = match @index.load_index(root, repo) {
        Some(i) => i
        None => return failure("repo not indexed: \{repo}")
      }
      let hits = @index.search(
        index,
        query,
        max_results=arg_int(args, "limit", 10),
      )
      let sb = StringBuilder::StringBuilder()
      sb.write_string("{\"hits\":[")
      for i = 0; i < hits.length(); i = i + 1 {
        if i > 0 {
          sb.write_char(',')
        }
        let h = hits[i]
        sb.write_string(
          "{\"id\":\{@text.json_escape(h.id)},\"level\":\{h.level},\"title\":\{@text.json_escape(h.title)},\"score\":\{h.score}}",
        )
      }
      sb.write_string("]}")
      Ok(text_result(sb.to_string()))
    },
  )
}
