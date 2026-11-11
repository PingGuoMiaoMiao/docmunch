// JSON and UTF-8 helpers shared by the CLI and the MCP layer.
//
// These used to live in `http`, which forced the MCP server (a pure protocol
// adapter) to depend on the whole transport stack just to escape a string.

///|
/// Escape a string as a JSON string literal, including the surrounding quotes.
pub fn json_escape(s : String) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_char('"')
  for c in s {
    let n = c.to_int()
    if c == '"' {
      sb.write_string("\\\"")
    } else if c == '\\' {
      sb.write_string("\\\\")
    } else if n == 10 {
      sb.write_string("\\n")
    } else if n == 13 {
      sb.write_string("\\r")
    } else if n == 9 {
      sb.write_string("\\t")
    } else if n < 32 {
      sb.write_string("\\u00")
      let hi = n / 16
      let lo = n % 16
      sb.write_char(
        Int32::unsafe_to_char(if hi < 10 { 48 + hi } else { 87 + hi }),
      )
      sb.write_char(
        Int32::unsafe_to_char(if lo < 10 { 48 + lo } else { 87 + lo }),
      )
    } else {
      sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
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
/// longer. `max_bytes <= 0` means "no limit" and returns `s` unchanged.
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
