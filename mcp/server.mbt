// MCP server: exposes the index/retrieval surface over stdio.
//
// Transport and JSON-RPC framing come from colmugx/mcp (D10). This package only
// owns the tool contracts and the response shape.

///|
fn arg_str(args : Json, key : String) -> String {
  match args.as_object() {
    Some(obj) =>
      match obj.get(key) {
        Some(Json::String(v)) => v
        _ => ""
      }
    None => ""
  }
}

///|
fn arg_opt_str(args : Json, key : String) -> String? {
  match args.as_object() {
    Some(obj) =>
      match obj.get(key) {
        Some(Json::String(v)) => Some(v)
        _ => None
      }
    None => None
  }
}

///|
fn arg_int(args : Json, key : String, fallback : Int32) -> Int32 {
  match args.as_object() {
    Some(obj) =>
      match obj.get(key) {
        Some(Json::Number(v, ..)) => v.to_int()
        _ => fallback
      }
    None => fallback
  }
}

///|
fn arg_bool(args : Json, key : String) -> Bool {
  match args.as_object() {
    Some(obj) =>
      match obj.get(key) {
        Some(Json::True) => true
        _ => false
      }
    None => false
  }
}

///|
fn prop_str(name : String, desc : String) -> String {
  "\"\{name}\":{\"type\":\"string\",\"description\":\"\{desc}\"}"
}

///|
fn prop_int(name : String, desc : String) -> String {
  "\"\{name}\":{\"type\":\"integer\",\"description\":\"\{desc}\"}"
}

///|
fn prop_bool(name : String, desc : String) -> String {
  "\"\{name}\":{\"type\":\"boolean\",\"description\":\"\{desc}\"}"
}

///|
fn schema(props : String, required : String) -> Json raise @mcp.MCPError {
  let body = "{\"type\":\"object\",\"properties\":{\{props}},\"required\":[\{required}],\"additionalProperties\":false}"
  @json.parse(body) catch {
    e => raise @mcp.MCPError::InternalError("bad schema: \{e.to_string()}")
  }
}

///|
fn text_result(s : String) -> @mcp.ToolResult {
  @mcp.ToolResult::text(s)
}

///|
fn failure(msg : String) -> Result[@mcp.ToolResult, @mcp.MCPError] {
  Ok(@mcp.ToolResult::error(msg))
}

///|
fn sections_json(repo : String, sections : Array[@core.Section]) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_string("{\"repo\":\{@http.json_escape(repo)},\"sections\":[")
  for i = 0; i < sections.length(); i = i + 1 {
    if i > 0 {
      sb.write_char(',')
    }
    let s = sections[i]
    sb.write_string(
      "{\"id\":\{@http.json_escape(s.id)},\"level\":\{s.level},\"title\":\{@http.json_escape(s.title)},\"path\":\{@http.json_escape(s.doc_path)},\"bytes\":[\{s.byte_start},\{s.byte_end}],\"parent\":\{@http.json_escape(s.parent_id)}}",
    )
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
async fn index_inputs(
  root : String,
  input : String,
  repo : String,
  doc_path : String,
) -> Result[@mcp.ToolResult, @mcp.MCPError] {
  let opts = @http.default_fetch_options()
  let is_url = input.has_prefix("http://") || input.has_prefix("https://")
  if !is_url && (input.has_suffix(".md") || input.has_suffix(".markdown")) {
    let text = @fs.read_file(input).text() catch {
      e => return failure("read failed: \{e.to_string()}")
    }
    let index = @index.build_index(root, repo, doc_path, text) catch {
      e => return failure("index failed: \{e.to_string()}")
    }
    return Ok(
      text_result(
        "{\"repo\":\{@http.json_escape(repo)},\"doc\":\{@http.json_escape(doc_path)},\"sections\":\{index.sections.length()}}",
      ),
    )
  }
  let html = if is_url {
    let result = @http.fetch(input, options=opts) catch {
      e => return failure("fetch failed: \{e.message()}")
    }
    result.body
  } else {
    @fs.read_file(input).text() catch {
      e => return failure("read failed: \{e.to_string()}")
    }
  }
  let ex = @extract.extract(html, input)
  let base = if is_url { input } else { "" }
  let markdown = @md.html_to_markdown(ex.html, base_url=base)
  let index = @index.build_index(root, repo, doc_path, markdown) catch {
    e => return failure("index failed: \{e.to_string()}")
  }
  Ok(
    text_result(
      "{\"repo\":\{@http.json_escape(repo)},\"doc\":\{@http.json_escape(doc_path)},\"title\":\{@http.json_escape(ex.title)},\"sections\":\{index.sections.length()}}",
    ),
  )
}

///|
/// Build the docmunch MCP server rooted at `root`.
pub fn build_server(root : String) -> @mcp.MCPServer raise @mcp.MCPError {
  let mut server = @mcp.MCPServer::MCPServer("docmunch", "0.1.0")

  server = server.tool(
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
        sb.write_string(@http.json_escape(repos[i]))
      }
      sb.write_string("]}")
      Ok(text_result(sb.to_string()))
    },
  )

  server = server.tool(
    "index_url",
    "Fetch a URL, extract the article, and index it. Returns repo/doc/section count.",
    schema(
      prop_str("url", "Absolute http(s) URL of the page to index.") +
      "," +
      prop_str("repo", "Optional repo name; defaults to the URL host."),
      "\"url\"",
    ),
    async fn(_ctx, args) {
      let url = arg_str(args, "url")
      if url == "" {
        return failure("missing required argument: url")
      }
      let parsed = @http.Target::parse(url) catch {
        e => return failure("bad url: \{e.message()}")
      }
      let repo = match arg_opt_str(args, "repo") {
        Some(r) => r
        None => parsed.host()
      }
      index_inputs(root, url, repo, "index.md")
    },
  )

  server = server.tool(
    "index_local",
    "Index a local Markdown or HTML file.",
    schema(
      prop_str("path", "Path to a .md/.markdown/.html file.") +
      "," +
      prop_str("repo", "Optional repo name; defaults to 'local'."),
      "\"path\"",
    ),
    async fn(_ctx, args) {
      let path = arg_str(args, "path")
      if path == "" {
        return failure("missing required argument: path")
      }
      let repo = match arg_opt_str(args, "repo") {
        Some(r) => r
        None => "local"
      }
      let doc_path = path.replace_all(old="\\", new="/")
      index_inputs(root, path, repo, doc_path)
    },
  )

  server = server.tool(
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

  server = server.tool(
    "get_section",
    "Return one section's Markdown by id (byte-range read; optional hash verify).",
    schema(
      prop_str("repo", "Repo name.") +
      "," +
      prop_str("id", "Section id from get_toc/search_sections.") +
      "," +
      prop_bool("verify", "Re-hash the retrieved bytes."),
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
      Ok(
        text_result(
          "{\"verified\":\{ok},\"markdown\":\{@http.json_escape(text)}}",
        ),
      )
    },
  )

  server = server.tool(
    "get_section_context",
    "Return a section with its ancestor chain and child summaries.",
    schema(
      prop_str("repo", "Repo name.") + "," + prop_str("id", "Section id."),
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
          "{\"id\":\{@http.json_escape(a.id)},\"level\":\{a.level},\"title\":\{@http.json_escape(a.title)}}",
        )
      }
      sb.write_string("],\"children\":[")
      for i = 0; i < children.length(); i = i + 1 {
        if i > 0 {
          sb.write_char(',')
        }
        let c = children[i]
        sb.write_string(
          "{\"id\":\{@http.json_escape(c.id)},\"level\":\{c.level},\"title\":\{@http.json_escape(c.title)}}",
        )
      }
      sb.write_string(
        "],\"section\":{\"id\":\{@http.json_escape(section.id)},\"title\":\{@http.json_escape(section.title)},\"verified\":\{ok},\"markdown\":\{@http.json_escape(text)}}}",
      )
      Ok(text_result(sb.to_string()))
    },
  )

  server = server.tool(
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
          "{\"id\":\{@http.json_escape(h.id)},\"level\":\{h.level},\"title\":\{@http.json_escape(h.title)},\"score\":\{h.score}}",
        )
      }
      sb.write_string("]}")
      Ok(text_result(sb.to_string()))
    },
  )

  server = server.tool(
    "delete_index",
    "Delete a repo's index and raw cache.",
    schema(prop_str("repo", "Repo name."), "\"repo\""),
    async fn(_ctx, args) {
      let repo = arg_str(args, "repo")
      let dir = @index.repo_dir(root, repo.replace_all(old="/", new="_"))
      @fs.rmdir(dir, recursive=true) catch {
        e => return failure("delete failed: \{e.to_string()}")
      }
      Ok(text_result("{\"deleted\":\{@http.json_escape(repo)}}"))
    },
  )

  server
}
