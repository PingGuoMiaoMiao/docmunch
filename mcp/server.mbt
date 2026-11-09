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
fn schema(props : String, required : String) -> Json raise @mcpsdk.MCPError {
  let body = "{\"type\":\"object\",\"properties\":{\{props}},\"required\":[\{required}],\"additionalProperties\":false}"
  @json.parse(body) catch {
    e => raise @mcpsdk.MCPError::InternalError("bad schema: \{e.to_string()}")
  }
}

///|
fn text_result(s : String) -> @mcpsdk.ToolResult {
  @mcpsdk.ToolResult::text(s)
}

///|
fn failure(msg : String) -> Result[@mcpsdk.ToolResult, @mcpsdk.MCPError] {
  Ok(@mcpsdk.ToolResult::error(msg))
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
) -> Result[@mcpsdk.ToolResult, @mcpsdk.MCPError] {
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
pub fn build_server(root : String) -> @mcpsdk.MCPServer raise @mcpsdk.MCPError {
  let mut server = @mcpsdk.MCPServer::MCPServer("docmunch", "0.1.0")
  // Serialize index mutations: the HTTP transport handles requests concurrently
  // and index writes are read-modify-write (D44). The array keeps one shared
  // mutex across the closures that capture it.
  let index_gate : Array[@async.Mutex] = [@async.Mutex::Mutex()]

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
      index_gate[0].acquire()
      defer index_gate[0].release()
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
      index_inputs(root, url, repo, @http.doc_path_for_url(url))
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
      index_gate[0].acquire()
      defer index_gate[0].release()
      let path = arg_str(args, "path")
      if path == "" {
        return failure("missing required argument: path")
      }
      let repo = match arg_opt_str(args, "repo") {
        Some(r) => r
        None => "local"
      }
      index_inputs(root, path, repo, @http.normalize_local_path(path))
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
      let markdown = @http.truncate_utf8(text, max_bytes)
      let truncated = max_bytes > 0 && total_bytes > max_bytes
      Ok(
        text_result(
          "{\"verified\":\{ok},\"truncated\":\{truncated},\"total_bytes\":\{total_bytes},\"markdown\":\{@http.json_escape(markdown)}}",
        ),
      )
    },
  )

  server = server.tool(
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
      let markdown = @http.truncate_utf8(text, max_bytes)
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
        "],\"section\":{\"id\":\{@http.json_escape(section.id)},\"title\":\{@http.json_escape(section.title)},\"verified\":\{ok},\"truncated\":\{truncated},\"total_bytes\":\{total_bytes},\"markdown\":\{@http.json_escape(markdown)}}}",
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
      index_gate[0].acquire()
      defer index_gate[0].release()
      let repo = arg_str(args, "repo")
      @index.delete_repo(root, repo)
      Ok(text_result("{\"deleted\":\{@http.json_escape(repo)}}"))
    },
  )

  server
}
