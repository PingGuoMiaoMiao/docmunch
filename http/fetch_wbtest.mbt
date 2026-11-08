// Local-server integration tests for the fetch stage.
//
// Ports are fixed per test to keep the harness simple (no port-0 + addr() dance);
// each test owns a distinct port and closes its listener before returning.

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
  ignore(client.write(response) catch { _ => () })
  client.close()
}

///|
async fn with_server(
  port : Int32,
  responses : Array[String],
  delay_ms : Int32,
  body : async () -> Unit,
) -> Unit {
  let addr = @socket.Addr::parse("127.0.0.1:\{port}") catch {
    _ => abort("bad test addr")
  }
  let srv = @socket.TcpServer::TcpServer(addr)
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
    body()
    srv.close()
  })
}

///|
fn local_opts(allow_private : Bool) -> FetchOptions {
  {
    timeout_ms: 5_000,
    max_bytes: 5_000_000,
    max_redirects: 5,
    allow_private,
    user_agent: "docmunch-test",
    accept: "text/html",
    use_cache: false,
    cache_root: ".doc-index-test",
  }
}

///|
async test "fetch 200 returns body, platform and cache path" {
  let body = "<html><head><title>x</title></head><body>hello</body></html>"
  let resp = http_response("HTTP/1.1 200 OK", "text/html; charset=utf-8", body)
  let port = 18801
  with_server(port, [resp], 0, async fn() {
    let opts = {
      timeout_ms: 5_000,
      max_bytes: 5_000_000,
      max_redirects: 5,
      allow_private: true,
      user_agent: "docmunch-test",
      accept: "text/html",
      use_cache: true,
      cache_root: ".doc-index-test",
    }
    let r = fetch("http://127.0.0.1:\{port}/doc", options=opts) catch {
      e => abort(e.message())
    }
    assert_eq(r.status, 200)
    assert_eq(r.bytes_len, body.length())
    assert_true(r.body.contains("<title>x</title>"))
    assert_eq(r.platform.name(), "generic")
    assert_true(r.cache_path != "")
    assert_eq(r.charset_warning, false)
  })
}

///|
async test "fetch follows a relative redirect" {
  let redirect = "HTTP/1.1 301 Moved\r\nLocation: /final\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
  let ok = http_response("HTTP/1.1 200 OK", "text/html", "final")
  let port = 18802
  with_server(port, [redirect, ok], 0, async fn() {
    let r = fetch("http://127.0.0.1:\{port}/start", options=local_opts(true)) catch {
      e => abort(e.message())
    }
    assert_eq(r.status, 200)
    assert_eq(r.final_url, "http://127.0.0.1:\{port}/final")
    assert_eq(r.body, "final")
  })
}

///|
async test "fetch rejects redirect loops" {
  let loop_resp = "HTTP/1.1 302 Found\r\nLocation: /loop\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
  let port = 18803
  let responses = [
    loop_resp, loop_resp, loop_resp, loop_resp, loop_resp, loop_resp,
  ]
  with_server(port, responses, 0, async fn() {
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
  let port = 18804
  with_server(port, [resp], 0, async fn() {
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
  let port = 18805
  with_server(port, [resp], 0, async fn() {
    let opts = {
      timeout_ms: 5_000,
      max_bytes: 1_000,
      max_redirects: 5,
      allow_private: true,
      user_agent: "docmunch-test",
      accept: "text/html",
      use_cache: false,
      cache_root: ".doc-index-test",
    }
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
  let port = 18806
  with_server(port, [resp], 400, async fn() {
    let opts = {
      timeout_ms: 60,
      max_bytes: 5_000_000,
      max_redirects: 5,
      allow_private: true,
      user_agent: "docmunch-test",
      accept: "text/html",
      use_cache: false,
      cache_root: ".doc-index-test",
    }
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
