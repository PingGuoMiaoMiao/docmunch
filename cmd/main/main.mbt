// docmunch CLI.
//
// Kept deliberately dumb: parse argv, call one library function, print a stable
// single-line summary that scripts (and the smoke run) can grep.

///|
fn usage() -> Unit {
  println("docmunch 0.1.0")
  println("usage:")
  println("  docmunch fetch <url> [--out PATH] [--allow-private] [--no-cache]")
  println(
    "                       [--max-bytes N] [--timeout MS] [--cache-ttl MS] [--retries N]",
  )
  println("  docmunch detect <url>")
  println("  docmunch extract <url|file> [--allow-private] [--out-html PATH]")
  println("  docmunch markdown <url|file> [--out PATH] [--allow-private]")
  println("  docmunch toc <file.md> [--verify]")
  println("  docmunch index <url|file> [--repo NAME] [--root DIR]")
  println("  docmunch search <repo> <query> [--root DIR]")
  println("  docmunch section <repo> <id> [--verify] [--root DIR]")
  println("  docmunch repos [--root DIR]")
  println("  docmunch delete <repo> [--root DIR]")
  println(
    "  docmunch mcp [--root DIR] [--http] [--port N]   # stdio or HTTP MCP server",
  )
  println("  docmunch smoke <url-file>")
}

///|
/// Diagnostics go to stderr so callers can keep treating stdout as data.
async fn fail(msg : String) -> Unit {
  @stdio.stderr.write(msg + "\n")
}

///|
fn has_flag(args : Array[String], flag : String) -> Bool {
  for a in args {
    if a == flag {
      return true
    }
  }
  false
}

///|
fn option_value(args : Array[String], name : String) -> String? {
  for i = 0; i < args.length() - 1; i = i + 1 {
    if args[i] == name {
      return Some(args[i + 1])
    }
  }
  None
}

///|
fn fetch_options(args : Array[String]) -> @http.FetchOptions {
  let base = @http.default_fetch_options()
  let max_bytes = match option_value(args, "--max-bytes") {
    Some(v) => @http.parse_int_or(v, base.max_bytes)
    None => base.max_bytes
  }
  let timeout = match option_value(args, "--timeout") {
    Some(v) => @http.parse_int_or(v, base.timeout_ms)
    None => base.timeout_ms
  }
  let cache_ttl = match option_value(args, "--cache-ttl") {
    Some(v) => @http.parse_int64_or(v, base.cache_ttl_ms)
    None => base.cache_ttl_ms
  }
  let max_retries = match option_value(args, "--retries") {
    Some(v) => @http.parse_int_or(v, base.max_retries)
    None => base.max_retries
  }
  {
    timeout_ms: timeout,
    max_bytes,
    max_redirects: base.max_redirects,
    allow_private: has_flag(args, "--allow-private"),
    user_agent: base.user_agent,
    accept: base.accept,
    use_cache: !has_flag(args, "--no-cache"),
    cache_root: base.cache_root,
    cache_ttl_ms: cache_ttl,
    max_retries,
  }
}

///|
fn summarize(r : @http.FetchResult) -> String {
  "status=\{r.status} bytes=\{r.bytes_len} platform=\{r.platform.name()} type=\{r.content_type} url=\{r.final_url} cache=\{r.cache_path}"
}

///|
async fn cmd_fetch(url : String, args : Array[String]) -> Unit {
  let opts = fetch_options(args)
  let result = @http.fetch(url, options=opts) catch {
    e => {
      fail("error=\{e.code()} \{e.message()}")
      return
    }
  }
  println(summarize(result))
  match option_value(args, "--out") {
    Some(path) =>
      try {
        @fs.write_file(path, result.body, create_mode=CreateOrTruncate)
        println("wrote=\{path}")
      } catch {
        e => fail("write_error=\{e.to_string()}")
      }
    None => ()
  }
}

///|
/// Detection is synchronous; the caller decides where the summary or the error
/// line goes (stdout vs stderr).
fn cmd_detect(url : String) -> Result[String, String] {
  let target = @http.Target::parse(url) catch {
    e => return Err("error=\{e.code()} \{e.message()}")
  }
  Ok("platform=\{@http.detect_from_url(target).name()} host=\{target.host()}")
}

///|
async fn load_document(input : String, args : Array[String]) -> String? {
  if input.has_prefix("http://") || input.has_prefix("https://") {
    let result = @http.fetch(input, options=fetch_options(args)) catch {
      e => {
        fail("error=\{e.code()} \{e.message()}")
        return None
      }
    }
    Some(result.body)
  } else {
    let text = @fs.read_file(input).text() catch {
      e => {
        fail("error=read \{e.to_string()}")
        return None
      }
    }
    Some(text)
  }
}

///|
async fn cmd_extract(input : String, args : Array[String]) -> Unit {
  let source = match load_document(input, args) {
    Some(html) => html
    None => return
  }
  let ex = @extract.extract(source, input)
  println(
    "{\"title\":\{@http.json_escape(ex.title)},\"byline\":\{@http.json_escape(ex.byline)},\"site_name\":\{@http.json_escape(ex.site_name)},\"lang\":\{@http.json_escape(ex.lang)},\"length\":\{ex.length},\"html_len\":\{ex.html.length()},\"text\":\{@http.json_escape(ex.text)}}",
  )
  match option_value(args, "--out-html") {
    Some(path) =>
      try {
        @fs.write_file(path, ex.html, create_mode=CreateOrTruncate)
        println("wrote=\{path}")
      } catch {
        e => fail("write_error=\{e.to_string()}")
      }
    None => ()
  }
}

///|
async fn cmd_smoke(path : String) -> Unit {
  let text = @fs.read_file(path).text() catch {
    e => {
      fail("error=read \{e.to_string()}")
      return
    }
  }
  let opts : @http.FetchOptions = {
    timeout_ms: 20_000,
    max_bytes: 5_000_000,
    max_redirects: 5,
    allow_private: false,
    user_agent: "docmunch/0.1 (smoke)",
    accept: "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.1",
    use_cache: true,
    cache_root: ".doc-index",
    cache_ttl_ms: 86_400_000,
    max_retries: 2,
  }
  for line in @http.split_lines(text) {
    let url = line.trim().to_owned()
    if url == "" || url.has_prefix("#") {
      continue
    }
    let started = @async.now()
    let status = try {
      let r = @http.fetch(url, options=opts)
      summarize(r)
    } catch {
      e => "error=\{e.code()} \{e.message()}"
    }
    let elapsed = @async.now() - started
    println("smoke url=\{url} took_ms=\{elapsed} \{status}")
  }
}

///|
async fn cmd_markdown(input : String, args : Array[String]) -> Unit {
  let source = match load_document(input, args) {
    Some(html) => html
    None => return
  }
  let ex = @extract.extract(source, input)
  let base = if input.has_prefix("http://") || input.has_prefix("https://") {
    input
  } else {
    ""
  }
  let markdown = @md.html_to_markdown(ex.html, base_url=base)
  match option_value(args, "--out") {
    Some(path) =>
      try {
        @fs.write_file(path, markdown, create_mode=CreateOrTruncate)
        println("wrote=\{path} bytes=\{markdown.length()}")
      } catch {
        e => fail("write_error=\{e.to_string()}")
      }
    None => println(markdown)
  }
}

///|
async fn cmd_toc(path : String, args : Array[String]) -> Unit {
  let text = @fs.read_file(path).text() catch {
    e => {
      fail("error=read \{e.to_string()}")
      return
    }
  }
  // Same normalisation the index uses, so a Windows path and its POSIX
  // spelling produce the same section ids.
  let doc_path = @http.normalize_local_path(path)
  let sections = @section.split_document("local", doc_path, text)
  let verify = has_flag(args, "--verify")
  for s in sections {
    if verify {
      let actual = @section.sha256_of(@section.section_text(text, s))
      let ok = actual == s.content_hash
      if !ok {
        abort("hash mismatch: \{s.id}")
      }
      println(
        "\{s.id}\tlevel=\{s.level}\tbytes=\{s.byte_start}-\{s.byte_end}\thash_ok=\{ok}\ttitle=\{s.title}",
      )
    } else {
      println(
        "\{s.id}\tlevel=\{s.level}\tbytes=\{s.byte_start}-\{s.byte_end}\thash=\{s.content_hash}\ttitle=\{s.title}",
      )
    }
  }
}

///|
fn root_of(args : Array[String]) -> String {
  match option_value(args, "--root") {
    Some(v) => v
    None => ".doc-index"
  }
}

///|
fn repo_for(input : String) -> String {
  if input.has_prefix("http://") || input.has_prefix("https://") {
    let t = @http.Target::parse(input) catch { _ => return "web" }
    t.host()
  } else {
    "local"
  }
}

///|
async fn markdown_of(input : String, args : Array[String]) -> String? {
  if input.has_suffix(".md") || input.has_suffix(".markdown") {
    let text = @fs.read_file(input).text() catch {
      e => {
        fail("error=read \{e.to_string()}")
        return None
      }
    }
    Some(text)
  } else {
    let html = match load_document(input, args) {
      Some(h) => h
      None => return None
    }
    let ex = @extract.extract(html, input)
    let base = if input.has_prefix("http://") || input.has_prefix("https://") {
      input
    } else {
      ""
    }
    Some(@md.html_to_markdown(ex.html, base_url=base))
  }
}

///|
async fn cmd_index(input : String, args : Array[String]) -> Unit {
  let root = root_of(args)
  let repo = match option_value(args, "--repo") {
    Some(v) => v
    None => repo_for(input)
  }
  let doc_path = if input.has_prefix("http://") || input.has_prefix("https://") {
    @http.doc_path_for_url(input)
  } else {
    @http.normalize_local_path(input)
  }
  let text = match markdown_of(input, args) {
    Some(t) => t
    None => return
  }
  let index = @index.build_index(root, repo, doc_path, text) catch {
    e => {
      fail("error=index \{e.to_string()}")
      return
    }
  }
  println(
    "repo=\{repo} doc=\{doc_path} sections=\{index.sections.length()} docs=\{index.doc_paths.length()} root=\{root}",
  )
}

///|
async fn cmd_search(
  repo : String,
  query : String,
  args : Array[String],
) -> Unit {
  let root = root_of(args)
  let index = match @index.load_index(root, repo) {
    Some(i) => i
    None => {
      fail("error=repo_not_indexed \{repo}")
      return
    }
  }
  let hits = @index.search(index, query)
  for hit in hits {
    println(
      "score=\{hit.score} level=\{hit.level} id=\{hit.id} title=\{hit.title}",
    )
  }
  println("hits=\{hits.length()}")
}

///|
async fn cmd_section(repo : String, id : String, args : Array[String]) -> Unit {
  let root = root_of(args)
  let index = match @index.load_index(root, repo) {
    Some(i) => i
    None => {
      fail("error=repo_not_indexed \{repo}")
      return
    }
  }
  let (text, ok) = @index.get_section_text(
    root,
    repo,
    index,
    id,
    verify=has_flag(args, "--verify"),
  ) catch {
    e => {
      fail("error=read \{e.to_string()}")
      return
    }
  }
  if text == "" && !ok {
    fail("error=section_not_found \{id}")
    return
  }
  println("verified=\{ok} bytes=\{text.length()}")
  println(text)
}

///|
async fn cmd_repos(args : Array[String]) -> Unit {
  let root = root_of(args)
  let repos = @index.list_repos(root) catch {
    e => {
      fail("error=list \{e.to_string()}")
      return
    }
  }
  for r in repos {
    println("repo=\{r}")
  }
  println("repos=\{repos.length()}")
}

///|
async fn cmd_mcp(args : Array[String]) -> Unit {
  let root = root_of(args)
  let server = @mcp.build_server(root) catch {
    e => {
      fail("error=build \{e.message()}")
      return
    }
  }
  if has_flag(args, "--http") {
    let port = match option_value(args, "--port") {
      Some(v) => @http.parse_int_or(v, 4240)
      None => 4240
    }
    println("listening=http://127.0.0.1:\{port}/mcp")
    server.run_http(port~, path="/mcp") catch {
      e => fail("error=transport \{e.to_string()}")
    }
  } else {
    server.run_stdio() catch {
      e => fail("error=transport \{e.to_string()}")
    }
  }
}

///|
async fn cmd_delete(repo : String, args : Array[String]) -> Unit {
  let root = root_of(args)
  @index.delete_repo(root, repo)
  println("deleted=\{repo}")
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    return
  }
  let cmd = args[1]
  if cmd == "fetch" {
    if args.length() < 3 {
      usage()
      return
    }
    cmd_fetch(args[2], args)
  } else if cmd == "detect" {
    if args.length() < 3 {
      usage()
      return
    }
    match cmd_detect(args[2]) {
      Ok(line) => println(line)
      Err(msg) => fail(msg)
    }
  } else if cmd == "extract" {
    if args.length() < 3 {
      usage()
      return
    }
    cmd_extract(args[2], args)
  } else if cmd == "markdown" {
    if args.length() < 3 {
      usage()
      return
    }
    cmd_markdown(args[2], args)
  } else if cmd == "toc" {
    if args.length() < 3 {
      usage()
      return
    }
    cmd_toc(args[2], args)
  } else if cmd == "index" {
    if args.length() < 3 {
      usage()
      return
    }
    cmd_index(args[2], args)
  } else if cmd == "search" {
    if args.length() < 4 {
      usage()
      return
    }
    cmd_search(args[2], args[3], args)
  } else if cmd == "section" {
    if args.length() < 4 {
      usage()
      return
    }
    cmd_section(args[2], args[3], args)
  } else if cmd == "repos" {
    cmd_repos(args)
  } else if cmd == "delete" {
    if args.length() < 3 {
      usage()
      return
    }
    cmd_delete(args[2], args)
  } else if cmd == "mcp" {
    cmd_mcp(args)
  } else if cmd == "smoke" {
    if args.length() < 3 {
      usage()
      return
    }
    cmd_smoke(args[2])
  } else {
    usage()
  }
}
