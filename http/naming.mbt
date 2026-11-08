// Naming rules shared by the CLI, the index and the MCP layer.
//
// These live in the http package because they need WHATWG URL parsing and the
// same digest format as the raw cache. Keeping one implementation here means the
// CLI, the index and the MCP tools cannot disagree about which document a URL or
// a local file maps to.

///|
/// Turn a filesystem path into a repo-relative, POSIX-style document path:
///
/// - `\` becomes `/`, so a Windows path and its POSIX spelling agree;
/// - repeated leading `./` segments are dropped (`././a` -> `a`);
/// - runs of `/` collapse into a single one (`a//b` -> `a/b`).
///
/// An input that normalises to nothing stays empty; callers decide what "no
/// path" means. A leading `/` is kept, because absolute inputs are meaningful to
/// the caller and silently making them relative would hide a caller bug.
pub fn normalize_local_path(path : String) -> String {
  let cs = chars_of(path)
  let n = cs.length()
  for i = 0; i < n; i = i + 1 {
    if cs[i] == '\\' {
      cs[i] = '/'
    }
  }
  let mut start = 0
  while start + 1 < n && cs[start] == '.' && cs[start + 1] == '/' {
    start = start + 2
  }
  let out = StringBuilder::StringBuilder()
  let mut after_slash = false
  for i = start; i < n; i = i + 1 {
    let c = cs[i]
    if c == '/' {
      if !after_slash {
        out.write_char('/')
      }
      after_slash = true
    } else {
      out.write_char(c)
      after_slash = false
    }
  }
  out.to_string()
}

///|
/// Strip the leading and trailing slashes of a URL pathname, so `/`, `//docs/`
/// and the empty string all reduce to something a file name can be built from.
fn pathname_body(pathname : String) -> String {
  let cs = chars_of(pathname)
  let mut start = 0
  let mut end = cs.length()
  while start < end && cs[start] == '/' {
    start = start + 1
  }
  while end > start && cs[end - 1] == '/' {
    end = end - 1
  }
  substring_chars(cs, start, end)
}

///|
/// Map a URL to the repo-relative Markdown path the index stores for it.
///
/// - `/docs/install` -> `docs/install.md`, the site root -> `index.md`;
/// - a URL with a query string or a fragment gets the first 8 hex digits of
///   sha256(URL) folded in, so `/docs?x=1` and `/docs?x=2` cannot overwrite each
///   other (`/docs?x=1` -> `docs-<sha8>.md`);
/// - a URL that does not parse falls back to `index.md` rather than raising, so
///   a bad input can never write outside the repo directory.
pub fn doc_path_for_url(url : String) -> String {
  let parsed = @url.Url::parse(url) catch { _ => return "index.md" }
  let body = pathname_body(parsed.pathname())
  let base = if body == "" { "index" } else { body }
  if parsed.search() == "" && parsed.hash() == "" {
    base + ".md"
  } else {
    let digest = sha256_hex(@utf8.encode(url))
    base + "-" + digest[0:8].to_owned() + ".md"
  }
}

///|
/// UTF-8 width of one scalar, used to keep `truncate_utf8` on character
/// boundaries.
fn utf8_width(c : Char) -> Int32 {
  let code = c.to_int()
  if code < 0x80 {
    1
  } else if code < 0x800 {
    2
  } else if code < 0x10000 {
    3
  } else {
    4
  }
}

///|
/// Truncate `s` to at most `max_bytes` bytes of UTF-8 **without splitting a
/// multi-byte character**: the result may be shorter than the limit, never
/// longer, and always decodes cleanly. `max_bytes <= 0` returns `s` untouched
/// (the usual "no limit" convention).
pub fn truncate_utf8(s : String, max_bytes : Int32) -> String {
  if max_bytes <= 0 {
    return s
  }
  let out = StringBuilder::StringBuilder()
  let mut used = 0
  for c in s {
    let width = utf8_width(c)
    if used + width > max_bytes {
      break
    }
    out.write_char(c)
    used = used + width
  }
  out.to_string()
}
