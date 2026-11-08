// Parsing helpers shared by the CLI and tests.

///|
/// Parse an integer, falling back to `fallback` on malformed input.
pub fn parse_int_or(input : String, fallback : Int32) -> Int32 {
  let mut value = 0
  let mut digits = 0
  let mut negative = false
  for c in input {
    if c == '-' && digits == 0 {
      negative = true
    } else {
      let n = c.to_int() - 48
      if n < 0 || n > 9 {
        return fallback
      }
      value = value * 10 + n
      digits = digits + 1
    }
  }
  if digits == 0 {
    fallback
  } else if negative {
    -value
  } else {
    value
  }
}

///|
/// Split on `\n`, dropping a trailing `\r`. Empty input yields an empty array.
pub fn split_lines(text : String) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder::StringBuilder()
  for c in text {
    if c == '\n' {
      out.push(sb.to_string())
      sb.reset()
    } else if c != '\r' {
      sb.write_char(c)
    }
  }
  let tail = sb.to_string()
  if tail != "" {
    out.push(tail)
  }
  out
}
