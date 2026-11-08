// Minimal JSON emission helpers for CLI output (no dependency on a JSON lib yet).

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
