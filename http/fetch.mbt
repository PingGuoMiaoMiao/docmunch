// Fetch stage: one URL in, raw document + platform label out.
//
// Design notes (see docs/pre-research.md §3 and docs/decisions.md D2/D12/D13):
// - streaming read so `max_bytes` is enforced while downloading, not after;
// - redirects are followed manually so every hop goes through the SSRF policy;
// - the whole call is bounded by `with_timeout`, which cancels the socket work.

///|
pub(all) struct FetchOptions {
  timeout_ms : Int32
  max_bytes : Int32
  max_redirects : Int32
  allow_private : Bool
  user_agent : String
  accept : String
  use_cache : Bool
  cache_root : String
}

///|
pub fn default_fetch_options() -> FetchOptions {
  {
    timeout_ms: 20_000,
    max_bytes: 5_000_000,
    max_redirects: 5,
    allow_private: false,
    user_agent: "docmunch/0.1 (+https://github.com/moonbitlang)",
    accept: "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.1",
    use_cache: true,
    cache_root: ".doc-index",
  }
}

///|
pub(all) struct FetchResult {
  requested_url : String
  final_url : String
  status : Int32
  content_type : String
  bytes_len : Int32
  body : String
  charset_warning : Bool
  platform : Platform
  cache_path : String
}

///|
fn request_headers(
  opts : FetchOptions,
) -> Map[@httpclient.CaseInsensitiveString, String] {
  let headers : Map[@httpclient.CaseInsensitiveString, String] = Map([])
  headers[@httpclient.CaseInsensitiveString::CaseInsensitiveString("User-Agent")] = opts.user_agent
  headers[@httpclient.CaseInsensitiveString::CaseInsensitiveString("Accept")] = opts.accept
  headers
}

///|
fn header_of(
  headers : Map[@httpclient.CaseInsensitiveString, String],
  name : String,
) -> String? {
  headers.get(@httpclient.CaseInsensitiveString::CaseInsensitiveString(name))
}

///|
fn is_redirect(status : Int32) -> Bool {
  status == 301 ||
  status == 302 ||
  status == 303 ||
  status == 307 ||
  status == 308
}

///|
/// Heuristic: a page that declares a non-UTF-8 charset is decoded lossily and
/// flagged rather than silently mangled (full transcoding is out of scope for v1).
fn declares_non_utf8(html : String) -> Bool {
  let head = if html.length() > 4096 { html[0:4096].to_owned() } else { html }
  let low = head.to_lower()
  if str_contains(low, "charset=") {
    !str_contains(low, "charset=utf-8") && !str_contains(low, "charset=\"utf-8")
  } else {
    false
  }
}

///|
async fn fetch_hop(
  current : Target,
  requested : String,
  hops : Int32,
  opts : FetchOptions,
) -> FetchResult raise FetchError {
  check_target(current, opts)
  let headers = request_headers(opts)
  let (resp, client) = @httpclient.get_stream(current.href(), headers~) catch {
    e => raise NetworkError(e.to_string())
  }
  let status = resp.code
  if is_redirect(status) {
    let location = match header_of(resp.headers, "Location") {
      Some(l) => l
      None => {
        client.close()
        raise BadUrl("redirect without Location: \{current.href()}")
      }
    }
    ignore(client.skip_response_body() catch { _ => () })
    client.close()
    let next = current.resolve(location)
    if !redirect_allowed(current, next, hops + 1, opts.max_redirects) {
      raise TooManyRedirects(opts.max_redirects)
    }
    return fetch_hop(next, requested, hops + 1, opts)
  }
  let content_type = match header_of(resp.headers, "Content-Type") {
    Some(v) => v
    None => ""
  }
  if !content_type_allowed(content_type) {
    ignore(client.skip_response_body() catch { _ => () })
    client.close()
    raise UnsupportedContentType(content_type)
  }
  let buf = @buffer.Buffer::Buffer()
  let mut total = 0
  let mut reading = true
  while reading {
    let chunk = client.read_some(max_len=65_536) catch {
      e => {
        client.close()
        raise NetworkError(e.to_string())
      }
    }
    match chunk {
      None => reading = false
      Some(bytes) => {
        total = total + bytes.length()
        if total > opts.max_bytes {
          client.close()
          raise TooLarge(opts.max_bytes)
        }
        buf.write_bytes(bytes)
      }
    }
  }
  client.close()
  let bytes = buf.to_bytes()
  let body = @utf8.decode_lossy(bytes)
  let platform = detect(current, body)
  let key = cache_key(requested)
  let cache_path = if opts.use_cache {
    let meta = "url=\{requested}\nfinal_url=\{current.href()}\nstatus=\{status}\ncontent_type=\{content_type}\nbytes=\{total}\nplatform=\{platform.name()}\n"
    try {
      save_entry(opts.cache_root, key, bytes, meta)
      cache_bin_path(opts.cache_root, key)
    } catch {
      _ => ""
    }
  } else {
    ""
  }
  {
    requested_url: requested,
    final_url: current.href(),
    status,
    content_type,
    bytes_len: total,
    body,
    charset_warning: declares_non_utf8(body),
    platform,
    cache_path,
  }
}

///|
/// Fetch one URL. Never raises for 4xx/5xx: those are returned as a result so the
/// caller decides (an MCP tool should report "404" rather than crash).
pub async fn fetch(
  url : String,
  options? : FetchOptions,
) -> FetchResult raise FetchError {
  let opts = match options {
    Some(o) => o
    None => default_fetch_options()
  }
  let target = Target::parse(url)
  @async.with_timeout(opts.timeout_ms, async fn() {
    fetch_hop(target, target.href(), 0, opts)
  }) catch {
    @async.TimeoutError => raise Timeout
    FetchError::_ as e => raise e
    e => raise NetworkError(e.to_string())
  }
}
