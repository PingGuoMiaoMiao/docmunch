// MCP server: exposes the index/retrieval surface over stdio.
//
// Transport and JSON-RPC framing come from colmugx/mcp (D10). This package only
// owns the tool contracts and the response shape.

///|
fn arg_str(args : Json, key : String) -> String {
  match args {
    Json::Object(obj) =>
      match obj.get(key) {
        Some(Json::String(v)) => v
        _ => ""
      }
    _ => ""
  }
}

///|
fn arg_opt_str(args : Json, key : String) -> String? {
  match args {
    Json::Object(obj) =>
      match obj.get(key) {
        Some(Json::String(v)) => Some(v)
        _ => None
      }
    _ => None
  }
}

///|
fn arg_int(args : Json, key : String, fallback : Int32) -> Int32 {
  match args {
    Json::Object(obj) =>
      match obj.get(key) {
        Some(Json::Number(v, ..)) => v.to_int()
        _ => fallback
      }
    _ => fallback
  }
}

///|
fn arg_bool(args : Json, key : String) -> Bool {
  match args {
    Json::Object(obj) =>
      match obj.get(key) {
        Some(Json::True) => true
        _ => false
      }
    _ => false
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
  sb.write_string("{\"repo\":\{@text.json_escape(repo)},\"sections\":[")
  for i = 0; i < sections.length(); i = i + 1 {
    if i > 0 {
      sb.write_char(',')
    }
    let s = sections[i]
    sb.write_string(
      "{\"id\":\{@text.json_escape(s.id)},\"level\":\{s.level},\"title\":\{@text.json_escape(s.title)},\"path\":\{@text.json_escape(s.doc_path)},\"bytes\":[\{s.byte_start},\{s.byte_end}],\"parent\":\{@text.json_escape(s.parent_id)}}",
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
    let (index, changed) = @index.build_index_checked(
      root, repo, doc_path, text,
    ) catch {
      e => return failure("index failed: \{e.to_string()}")
    }
    return Ok(
      text_result(
        "{\"repo\":\{@text.json_escape(repo)},\"doc\":\{@text.json_escape(doc_path)},\"sections\":\{index.sections.length()},\"changed\":\{changed}}",
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
  let (index, changed) = @index.build_index_checked(
    root, repo, doc_path, markdown,
  ) catch {
    e => return failure("index failed: \{e.to_string()}")
  }
  Ok(
    text_result(
      "{\"repo\":\{@text.json_escape(repo)},\"doc\":\{@text.json_escape(doc_path)},\"title\":\{@text.json_escape(ex.title)},\"sections\":\{index.sections.length()},\"changed\":\{changed}}",
    ),
  )
}

///|
/// Build the docmunch MCP server rooted at `root`.

///|
/// Build the docmunch MCP server rooted at `root`.
///
/// Every tool lives in `tools_read.mbt` / `tools_write.mbt`; this function only
/// assembles them, so adding a tool touches one registration line here.
pub fn build_server(root : String) -> @mcpsdk.MCPServer raise @mcpsdk.MCPError {
  let mut server = @mcpsdk.MCPServer::MCPServer("docmunch", "0.1.0")
  // Serialize index mutations: the HTTP transport handles requests concurrently
  // and index writes are read-modify-write (D44). The array keeps one shared
  // mutex across the closures that capture it.
  let index_gate : Array[@async.Mutex] = [@async.Mutex::Mutex()]
  server = register_list_repos(server, root)
  server = register_get_toc(server, root)
  server = register_list_docs(server, root)
  server = register_get_doc(server, root)
  server = register_get_section_descendants(server, root)
  server = register_search_titles(server, root)
  server = register_get_section(server, root)
  server = register_get_section_context(server, root)
  server = register_search_sections(server, root)
  server = register_index_url(server, root, index_gate)
  server = register_index_local(server, root, index_gate)
  server = register_delete_index(server, root, index_gate)
  server
}
