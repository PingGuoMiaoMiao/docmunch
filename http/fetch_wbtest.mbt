// Local-server integration tests for the fetch stage, plus unit tests for the
// naming/cache helpers that do not need a socket.
//
// No test depends on a fixed port: `bind_any` starts at the requested port and
// walks upwards until it can bind, then reports the port it actually got. A
// stale listener or a parallel run therefore cannot make a test flaky. Every
// test closes its listener before returning.

///|
fn http_response(
  status_line : String,
  content_type : String,
  body : String,
) -> String {
  status_line +
  "\r\nContent-Type: " +
  content_type +
  "\r\nContent-Length: " +
  body.length().to_string() +
  "\r\nConnection: close\r\n\r\n" +
  body
}

///|
/// Answer one connection. An empty `response` closes the connection without
/// writing anything; the retry test uses that to produce a network error.
async fn serve_once(
  srv : @socket.TcpServer,
  response : String,
  delay_ms : Int32,
) -> Unit {
  let accepted = srv.accept() catch { _ => return }
  let (client, _peer) = accepted
  if delay_ms > 0 {
    @async.sleep(delay_ms)
  }
  ignore(client.read_until("\r\n\r\n") catch { _ => None })
  if response != "" {
    ignore(client.write(response) catch { _ => () })
  }
  client.close()
}

///|
/// Bind a loopback server on the first free port at or after `start_port`, and
/// report the port that was actually bound (never via the deprecated `addr()`).
async fn bind_any(start_port : Int32) -> (Int32, @socket.TcpServer) {
  let mut port = start_port
  let mut attempts = 0
  while attempts < 32 {
    let addr = @socket.Addr::parse("127.0.0.1:\{port}") catch {
      _ => abort("bad test address")
    }
    let candidate = Some(@socket.TcpServer::TcpServer(addr)) catch { _ => None }
    match candidate {
      Some(srv) => return (srv.addr.port(), srv)
      None => ()
    }
    port = port + 1
    attempts = attempts + 1
  }
  abort("no free loopback port for the test server")
}

///|
async fn with_server(
  start_port : Int32,
  responses : Array[String],
  delay_ms : Int32,
  body : async (Int32) -> Unit,
) -> Unit {
  let (port, srv) = bind_any(start_port)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(
      async fn() {
        for i = 0; i < responses.length(); i = i + 1 {
          serve_once(srv, responses[i], delay_ms)
        }
      },
      allow_failure=true,
    )
    @async.sleep(50)
    body(port)
    srv.close()
  })
}

///|
fn test_options(
  allow_private~ : Bool = true,
  use_cache~ : Bool = false,
  cache_root~ : String = ".doc-index-test",
  cache_ttl_ms~ : Int64 = 86_400_000,
  max_retries~ : Int32 = 2,
  timeout_ms~ : Int32 = 5_000,
  max_bytes~ : Int32 = 5_000_000,
) -> FetchOptions {
  {
    timeout_ms,
    max_bytes,
    max_redirects: 5,
    allow_private,
    user_agent: "docmunch-test",
    accept: "text/html",
    use_cache,
    cache_root,
    cache_ttl_ms,
    max_retries,
  }
}

///|
fn local_opts(allow_private : Bool) -> FetchOptions {
  test_options(allow_private~)
}

///|
async test "fetch 200 returns body, platform and cache path" {
  let body = "<html><head><title>x</title></head><body>hello</body></html>"
  let resp = http_response("HTTP/1.1 200 OK", "text/html; charset=utf-8", body)
  let root = ".doc-index-test/fetch-200"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  with_server(18801, [resp], 0, async fn(port) {
    let opts = test_options(use_cache=true, cache_root=root)
    let r = fetch("http://127.0.0.1:\{port}/doc", options=opts) catch {
      e => abort(e.message())
    }
    assert_eq(r.status, 200)
    assert_eq(r.bytes_len, body.length())
    assert_true(r.body.contains("<title>x</title>"))
    assert_eq(r.platform.name(), "generic")
    assert_true(r.cache_path != "")
    assert_eq(r.charset_warning, false)
    assert_eq(r.from_cache, false)
  })
}

///|
async test "fetch follows a relative redirect" {
  let redirect = "HTTP/1.1 301 Moved\r\nLocation: /final\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
  let ok = http_response("HTTP/1.1 200 OK", "text/html", "final")
  with_server(18802, [redirect, ok], 0, async fn(port) {
    let r = fetch("http://127.0.0.1:\{port}/start", options=local_opts(true)) catch {
      e => abort(e.message())
    }
    assert_eq(r.status, 200)
    assert_eq(r.final_url, "http://127.0.0.1:\{port}/final")
    assert_eq(r.body, "final")
    assert_eq(r.from_cache, false)
  })
}

///|
async test "fetch rejects redirect loops" {
  let loop_resp = "HTTP/1.1 302 Found\r\nLocation: /loop\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
  let responses = [
    loop_resp, loop_resp, loop_resp, loop_resp, loop_resp, loop_resp,
  ]
  with_server(18803, responses, 0, async fn(port) {
    let outcome = try {
      ignore(fetch("http://127.0.0.1:\{port}/loop", options=local_opts(true)))
      "no-error"
    } catch {
      TooManyRedirects(_) => "too-many"
      e => e.message()
    }
    assert_eq(outcome, "too-many")
  })
}

///|
async test "fetch returns 404 as a result" {
  let resp = http_response("HTTP/1.1 404 Not Found", "text/html", "missing")
  with_server(18804, [resp], 0, async fn(port) {
    let r = fetch("http://127.0.0.1:\{port}/nope", options=local_opts(true)) catch {
      e => abort(e.message())
    }
    assert_eq(r.status, 404)
    assert_eq(r.body, "missing")
  })
}

///|
async test "fetch enforces max_bytes while streaming" {
  let body = "x".repeat(5_000)
  let resp = http_response("HTTP/1.1 200 OK", "text/html", body)
  with_server(18805, [resp], 0, async fn(port) {
    let opts = test_options(max_bytes=1_000)
    let outcome = try {
      ignore(fetch("http://127.0.0.1:\{port}/big", options=opts))
      "no-error"
    } catch {
      TooLarge(_) => "too-large"
      e => e.message()
    }
    assert_eq(outcome, "too-large")
  })
}

///|
async test "fetch times out on a slow response" {
  let resp = http_response("HTTP/1.1 200 OK", "text/html", "late")
  with_server(18806, [resp], 400, async fn(port) {
    let opts = test_options(timeout_ms=60)
    let outcome = try {
      ignore(fetch("http://127.0.0.1:\{port}/slow", options=opts))
      "no-error"
    } catch {
      Timeout => "timeout"
      e => e.message()
    }
    assert_eq(outcome, "timeout")
  })
}

///|
async test "fetch blocks loopback when allow_private is false" {
  let outcome = try {
    ignore(fetch("http://127.0.0.1:18807/x", options=local_opts(false)))
    "no-error"
  } catch {
    Blocked(_) => "blocked"
    e => e.message()
  }
  assert_eq(outcome, "blocked")
}

///|
async test "a retryable network error is retried" {
  // First connection dies before the status line, the retry gets a real answer.
  let ok = http_response("HTTP/1.1 200 OK", "text/html", "after-retry")
  with_server(18808, ["", ok], 0, async fn(port) {
    let opts = test_options(max_retries=2)
    let r = fetch("http://127.0.0.1:\{port}/retry", options=opts) catch {
      e => abort(e.message())
    }
    assert_eq(r.status, 200)
    assert_eq(r.body, "after-retry")
    assert_eq(r.from_cache, false)
  })
}

///|
async test "a fresh cache entry is served without the network" {
  let html = "<html><head><title>cache</title></head><body>cached copy</body></html>"
  let resp = http_response("HTTP/1.1 200 OK", "text/html; charset=utf-8", html)
  let root = ".doc-index-test/cache-hit"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  let (port, srv) = bind_any(18809)
  let url = "http://127.0.0.1:\{port}/cached"
  let opts = test_options(use_cache=true, cache_root=root)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { serve_once(srv, resp, 0) }, allow_failure=true)
    @async.sleep(50)
    let first = fetch(url, options=opts) catch { e => abort(e.message()) }
    assert_eq(first.from_cache, false)
    assert_eq(first.status, 200)
    assert_eq(first.body, html)
    assert_true(first.cache_path != "")
    srv.close()
  })
  // The listener is gone now: only the cache can answer this one.
  let second = fetch(url, options=opts) catch { e => abort(e.message()) }
  assert_eq(second.from_cache, true)
  assert_eq(second.status, 200)
  assert_eq(second.content_type, "text/html; charset=utf-8")
  assert_eq(second.body, html)
  assert_eq(second.bytes_len, html.length())
  assert_true(second.cache_path.has_suffix(".bin"))
  assert_eq(second.platform.name(), "generic")
}

///|
async test "a stale cache entry falls back to the network" {
  let html = "<html><body>fresh copy</body></html>"
  let resp = http_response("HTTP/1.1 200 OK", "text/html", html)
  let root = ".doc-index-test/cache-stale"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  let (port, srv) = bind_any(18810)
  let url = "http://127.0.0.1:\{port}/stale"
  let warm = test_options(use_cache=true, cache_root=root)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { serve_once(srv, resp, 0) }, allow_failure=true)
    @async.sleep(50)
    let first = fetch(url, options=warm) catch { e => abort(e.message()) }
    assert_eq(first.from_cache, false)
    srv.close()
  })
  // Same entry, but a zero TTL makes it unusable: the fetch must go back out,
  // and with the server gone that is a network error rather than silent stale
  // data.
  let cold = test_options(
    use_cache=true,
    cache_root=root,
    cache_ttl_ms=0,
    max_retries=0,
  )
  let outcome = try {
    ignore(fetch(url, options=cold))
    "no-error"
  } catch {
    NetworkError(_) => "network"
    e => e.code()
  }
  assert_eq(outcome, "network")
  // A cache entry written under a larger byte cap must not bypass a smaller one.
  let tight = test_options(
    use_cache=true,
    cache_root=root,
    max_bytes=10,
    max_retries=0,
  )
  let tight_outcome = try {
    ignore(fetch(url, options=tight))
    "no-error"
  } catch {
    NetworkError(_) => "network"
    e => e.code()
  }
  assert_eq(tight_outcome, "network")
}

///|
async test "load_cached round-trips metadata and honours the ttl" {
  let root = ".doc-index-test/ttl"
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  let url = "https://example.com/ttl"
  let key = cache_key(url)
  let meta = "url=\{url}\nstatus=201\ncontent_type=text/plain; charset=utf-8\n"
  save_entry(root, key, @utf8.encode("cached body"), meta) catch {
    e => abort(e.message())
  }
  let hit = load_cached(root, key, 60_000) catch { e => abort(e.message()) }
  match hit {
    None => abort("expected a cache hit")
    Some(e) => {
      assert_eq(e.status, "201")
      assert_eq(e.content_type, "text/plain; charset=utf-8")
      assert_eq(@utf8.decode_lossy(e.body), "cached body")
    }
  }
  // Absent fields fall back to 200 / "" instead of failing the read.
  let bare = cache_key("https://example.com/bare")
  save_entry(root, bare, @utf8.encode("bare"), "url=https://example.com/bare\n") catch {
    e => abort(e.message())
  }
  let defaults = load_cached(root, bare, 60_000) catch {
    e => abort(e.message())
  }
  match defaults {
    None => abort("expected a cache hit for the bare entry")
    Some(e) => {
      assert_eq(e.status, "200")
      assert_eq(e.content_type, "")
    }
  }
  // An unknown key is a miss, not an error.
  let missing = load_cached(root, cache_key("https://example.com/nope"), 60_000) catch {
    e => abort(e.message())
  }
  assert_true(missing is None)
  // A non-positive TTL means "never fresh", so even a just-written entry misses.
  let cold = load_cached(root, key, 0) catch { e => abort(e.message()) }
  assert_true(cold is None)
  let colder = load_cached(root, key, -5) catch { e => abort(e.message()) }
  assert_true(colder is None)
}

///|
test "local paths normalise to posix repo-relative paths" {
  assert_eq(normalize_local_path("docs\\guide\\x.md"), "docs/guide/x.md")
  assert_eq(normalize_local_path(".\\docs\\x.md"), "docs/x.md")
  assert_eq(normalize_local_path("././docs/x.md"), "docs/x.md")
  assert_eq(normalize_local_path("docs//guide///x.md"), "docs/guide/x.md")
  assert_eq(normalize_local_path("./"), "")
  assert_eq(normalize_local_path(""), "")
  assert_eq(normalize_local_path("docs/x.md"), "docs/x.md")
}

///|
test "url doc paths keep the path and disambiguate queries" {
  assert_eq(
    doc_path_for_url("https://example.com/docs/install"),
    "docs/install.md",
  )
  assert_eq(doc_path_for_url("https://example.com/"), "index.md")
  assert_eq(doc_path_for_url("https://example.com"), "index.md")
  assert_eq(doc_path_for_url("https://example.com/guide/"), "guide.md")
  assert_eq(doc_path_for_url("not a url"), "index.md")
  let plain = doc_path_for_url("https://example.com/docs")
  let q1 = doc_path_for_url("https://example.com/docs?x=1")
  let q2 = doc_path_for_url("https://example.com/docs?x=2")
  let frag = doc_path_for_url("https://example.com/docs#top")
  assert_eq(plain, "docs.md")
  assert_true(q1 != q2)
  assert_true(q1 != plain && q2 != plain && frag != plain)
  assert_true(q1.has_prefix("docs-"))
  assert_true(q1.has_suffix(".md"))
  assert_eq(q1.length(), "docs-".length() + 8 + 3)
}

///|
test "truncate_utf8 never splits a multi-byte character" {
  // "中éab" is 3 + 2 + 1 + 1 = 7 UTF-8 bytes.
  let s = "中éab"
  assert_eq(truncate_utf8(s, 1), "")
  assert_eq(truncate_utf8(s, 2), "")
  assert_eq(truncate_utf8(s, 3), "中")
  assert_eq(truncate_utf8(s, 4), "中")
  assert_eq(truncate_utf8(s, 5), "中é")
  assert_eq(truncate_utf8(s, 6), "中éa")
  assert_eq(truncate_utf8(s, 7), s)
  assert_eq(truncate_utf8(s, 100), s)
  assert_eq(truncate_utf8(s, 0), s)
  assert_eq(truncate_utf8(s, -1), s)
  assert_eq(@utf8.encode(truncate_utf8(s, 4)).length(), 3)
  // A four-byte scalar counts as four bytes, not as four characters.
  let emoji = "a\u{1F600}b"
  assert_eq(truncate_utf8(emoji, 4), "a")
  assert_eq(truncate_utf8(emoji, 5), "a\u{1F600}")
  assert_eq(truncate_utf8(emoji, 6), "a\u{1F600}b")
}

///|
test "only network errors are retryable" {
  assert_true(is_retryable(NetworkError("connection reset")))
  assert_false(is_retryable(Timeout))
  assert_false(is_retryable(Blocked("127.0.0.1")))
  assert_false(is_retryable(BadUrl("nope")))
  assert_false(is_retryable(DnsError("example.invalid")))
  assert_false(is_retryable(TooLarge(10)))
  assert_false(is_retryable(TooManyRedirects(5)))
  assert_false(is_retryable(UnsupportedContentType("image/png")))
  assert_false(is_retryable(CacheError("disk full")))
}

///|
test "int64 option parsing falls back on junk" {
  assert_eq(parse_int64_or("86400000", 1), 86_400_000)
  assert_eq(parse_int64_or("-5", 1), -5)
  assert_eq(parse_int64_or("12x", 99), 99)
  assert_eq(parse_int64_or("", 99), 99)
  assert_eq(parse_int64_or("-", 99), 99)
}
