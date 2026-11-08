// Fetch policy: SSRF guard, redirect rules, content-type allowlist.
//
// Everything here except `check_target` is a pure function, because this is the
// part where a security regression is worst and tests are cheapest.

///|
fn chars_of(s : String) -> Array[Char] {
  let out : Array[Char] = []
  for c in s {
    out.push(c)
  }
  out
}

///|
fn substring_chars(cs : Array[Char], start : Int32, end : Int32) -> String {
  let sb = StringBuilder::StringBuilder()
  for i = start; i < end; i = i + 1 {
    sb.write_char(cs[i])
  }
  sb.to_string()
}

///|
fn index_of_char(cs : Array[Char], target : Char) -> Int32 {
  let mut found = -1
  for i = 0; i < cs.length(); i = i + 1 {
    if cs[i] == target {
      found = i
      break
    }
  }
  found
}

///|
fn last_index_of_char(cs : Array[Char], target : Char) -> Int32 {
  let mut found = -1
  for i = 0; i < cs.length(); i = i + 1 {
    if cs[i] == target {
      found = i
    }
  }
  found
}

///|
fn is_blank(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
fn trim_ascii(s : String) -> String {
  let cs = chars_of(s)
  let mut start = 0
  let mut end = cs.length()
  while start < end && is_blank(cs[start]) {
    start = start + 1
  }
  while end > start && is_blank(cs[end - 1]) {
    end = end - 1
  }
  substring_chars(cs, start, end)
}

///|
fn octets_of_ipv4(s : String) -> Array[Int32]? {
  let out : Array[Int32] = []
  let mut cur = 0
  let mut digits = 0
  let mut ok = true
  for c in s {
    if c == '.' {
      if digits == 0 {
        ok = false
      }
      out.push(cur)
      cur = 0
      digits = 0
    } else {
      let n = c.to_int() - 48
      if n < 0 || n > 9 {
        ok = false
      } else {
        cur = cur * 10 + n
        digits = digits + 1
        if cur > 255 {
          ok = false
        }
      }
    }
  }
  if digits == 0 {
    ok = false
  }
  out.push(cur)
  if !ok || out.length() != 4 {
    None
  } else {
    Some(out)
  }
}

///|
/// True for loopback, link-local, RFC1918, CGNAT, benchmark and multicast IPv4.
pub fn is_private_ipv4(s : String) -> Bool {
  match octets_of_ipv4(s) {
    None => false
    Some(o) => {
      let a = o[0]
      let b = o[1]
      a == 0 ||
      a == 10 ||
      a == 127 ||
      (a == 169 && b == 254) ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      (a == 100 && b >= 64 && b <= 127) ||
      (a == 198 && (b == 18 || b == 19)) ||
      a >= 224
    }
  }
}

///|
/// Strip an optional `:port`, and brackets for IPv6 literals.
pub fn strip_port(s : String) -> String {
  let cs = chars_of(s)
  if cs.length() > 0 && cs[0] == '[' {
    let close = index_of_char(cs, ']')
    if close < 0 {
      substring_chars(cs, 1, cs.length())
    } else {
      substring_chars(cs, 1, close)
    }
  } else {
    let colon = last_index_of_char(cs, ':')
    let first_colon = index_of_char(cs, ':')
    if colon < 0 || (first_colon >= 0 && first_colon != colon) {
      // No port, or a bare IPv6 literal (more than one colon, no brackets).
      s
    } else {
      substring_chars(cs, 0, colon)
    }
  }
}

///|
/// True for `::1`, unspecified, link-local, unique-local and v4-mapped private.
pub fn is_private_ipv6(raw : String) -> Bool {
  let h = strip_port(raw).to_lower()
  h == "::1" ||
  h == "::" ||
  h.has_prefix("fe80") ||
  h.has_prefix("fc") ||
  h.has_prefix("fd") ||
  h.has_prefix("::ffff:127.") ||
  h.has_prefix("::ffff:10.") ||
  h.has_prefix("::ffff:192.168.")
}

///|
/// True when the given IP literal is private, loopback, link-local or reserved.
pub fn is_private_ip(ip : String) -> Bool {
  let s = strip_port(ip)
  if s.contains(":") {
    is_private_ipv6(s)
  } else {
    is_private_ipv4(s)
  }
}

///|
/// Hostname-level blocklist, checked before any DNS lookup.
pub fn is_private_host(host : String) -> Bool {
  let h = host.to_lower()
  h == "" ||
  h == "localhost" ||
  h == "0.0.0.0" ||
  h == "::1" ||
  h.has_prefix("127.") ||
  h.has_prefix("10.") ||
  h.has_prefix("192.168.") ||
  h.has_prefix("169.254.") ||
  h.has_suffix(".local") ||
  h.has_suffix(".localhost") ||
  h.has_suffix(".internal")
}

///|
/// Resolve the host and reject private targets. `allow_private` skips the check
/// (used by tests and by explicit local-docs mode).
pub async fn check_target(
  t : Target,
  opts : FetchOptions,
) -> Unit raise FetchError {
  if opts.allow_private {
    return
  }
  let host = t.host()
  if is_private_host(host) {
    raise Blocked(host)
  }
  let addr = @socket.Addr::resolve(host, port=t.default_port()) catch {
    _ => raise DnsError(host)
  }
  let ip = addr.to_string()
  if is_private_ip(ip) {
    raise Blocked(host)
  }
}

///|
/// Redirect policy: bound the hop count, forbid https -> http, and only allow
/// cross-host hops when the target stays on https.
pub fn redirect_allowed(
  from : Target,
  to : Target,
  hops : Int32,
  max_hops : Int32,
) -> Bool {
  if hops > max_hops {
    false
  } else if from.is_secure() && !to.is_secure() {
    false
  } else if !to.is_secure() && from.host() != to.host() {
    false
  } else {
    true
  }
}

///|
/// Content types the extract stage can consume.
pub fn content_type_allowed(raw : String) -> Bool {
  let cs = chars_of(raw.to_lower())
  let semi = index_of_char(cs, ';')
  let head = if semi < 0 {
    substring_chars(cs, 0, cs.length())
  } else {
    substring_chars(cs, 0, semi)
  }
  let t = trim_ascii(head)
  t == "text/html" ||
  t == "application/xhtml+xml" ||
  t == "text/markdown" ||
  t == "text/plain" ||
  t == "application/xml" ||
  t == "text/xml" ||
  t == ""
}
