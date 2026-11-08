// docmunch CLI.
//
// Kept deliberately dumb: parse argv, call one library function, print a stable
// single-line summary that scripts (and the smoke run) can grep.

///|
fn usage() -> Unit {
  println("docmunch 0.1.0")
  println("usage:")
  println("  docmunch fetch <url> [--out PATH] [--allow-private] [--no-cache]")
  println("                       [--max-bytes N] [--timeout MS]")
  println("  docmunch detect <url>")
  println("  docmunch extract <url|file> [--allow-private] [--out-html PATH]")
  println("  docmunch markdown <url|file> [--out PATH] [--allow-private]")
  println("  docmunch toc <file.md> [--verify]")
  println("  docmunch smoke <url-file>")
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
  {
    timeout_ms: timeout,
    max_bytes,
    max_redirects: base.max_redirects,
    allow_private: has_flag(args, "--allow-private"),
    user_agent: base.user_agent,
    accept: base.accept,
    use_cache: !has_flag(args, "--no-cache"),
    cache_root: base.cache_root,
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
      println("error=\{e.code()} \{e.message()}")
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
        e => println("write_error=\{e.to_string()}")
      }
    None => ()
  }
}

///|
async fn cmd_detect(url : String) -> Unit {
  let target = @http.Target::parse(url) catch {
    e => {
      println("error=\{e.code()} \{e.message()}")
      return
    }
  }
  println(
    "platform=\{@http.detect_from_url(target).name()} host=\{target.host()}",
  )
}

///|
async fn load_document(input : String, args : Array[String]) -> String? {
  if input.has_prefix("http://") || input.has_prefix("https://") {
    let result = @http.fetch(input, options=fetch_options(args)) catch {
      e => {
        println("error=\{e.code()} \{e.message()}")
        return None
      }
    }
    Some(result.body)
  } else {
    let text = @fs.read_file(input).text() catch {
      e => {
        println("error=read \{e.to_string()}")
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
        e => println("write_error=\{e.to_string()}")
      }
    None => ()
  }
}

///|
async fn cmd_smoke(path : String) -> Unit {
  let text = @fs.read_file(path).text() catch {
    e => {
      println("error=read \{e.to_string()}")
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
        e => println("write_error=\{e.to_string()}")
      }
    None => println(markdown)
  }
}

///|
async fn cmd_toc(path : String, args : Array[String]) -> Unit {
  let text = @fs.read_file(path).text() catch {
    e => {
      println("error=read \{e.to_string()}")
      return
    }
  }
  let sections = @section.split_document("local", path, text)
  let verify = has_flag(args, "--verify")
  for s in sections {
    if verify {
      let actual = @section.sha256_of(@section.section_text(text, s))
      let ok = actual == s.content_hash
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
    cmd_detect(args[2])
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
