// MCP tools that mutate the index.
//
// Each takes the shared gate mutex so concurrent HTTP requests cannot interleave
// a read-modify-write of the index (D44).

///|
fn register_index_url(
  server : @mcpsdk.MCPServer,
  root : String,
  gate : Array[@async.Mutex],
) -> @mcpsdk.MCPServer raise @mcpsdk.MCPError {
  server.tool(
    "index_url",
    "Fetch a URL, extract the article, and index it. Returns repo/doc/section count.",
    schema(
      prop_str("url", "Absolute http(s) URL of the page to index.") +
      "," +
      prop_str("repo", "Optional repo name; defaults to the URL host."),
      "\"url\"",
    ),
    async fn(_ctx, args) {
      gate[0].acquire()
      defer gate[0].release()
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
}

///|
fn register_index_local(
  server : @mcpsdk.MCPServer,
  root : String,
  gate : Array[@async.Mutex],
) -> @mcpsdk.MCPServer raise @mcpsdk.MCPError {
  server.tool(
    "index_local",
    "Index a local Markdown or HTML file.",
    schema(
      prop_str("path", "Path to a .md/.markdown/.html file.") +
      "," +
      prop_str("repo", "Optional repo name; defaults to 'local'."),
      "\"path\"",
    ),
    async fn(_ctx, args) {
      gate[0].acquire()
      defer gate[0].release()
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
}

///|
fn register_delete_index(
  server : @mcpsdk.MCPServer,
  root : String,
  gate : Array[@async.Mutex],
) -> @mcpsdk.MCPServer raise @mcpsdk.MCPError {
  server.tool(
    "delete_index",
    "Delete a repo's index and raw cache.",
    schema(prop_str("repo", "Repo name."), "\"repo\""),
    async fn(_ctx, args) {
      gate[0].acquire()
      defer gate[0].release()
      let repo = arg_str(args, "repo")
      @index.delete_repo(root, repo) catch {
        e => return failure("delete failed: \{e.to_string()}")
      }
      Ok(text_result("{\"deleted\":\{@text.json_escape(repo)}}"))
    },
  )
}
