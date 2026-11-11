// Zero-dependency text helpers.
//
// Several packages need plain string primitives (substring search, line
// splitting, JSON escaping, UTF-8 truncation). They used to live in `http`,
// which also pulls in the transport stack (async / url / sha256 / encoding),
// so packages that only wanted a string function re-implemented it instead.
// Keeping them here means `md`, `index`, `mcp` and `cmd` can share one copy
// without dragging the HTTP client in (see ADR D48).

///|
/// Index of `needle` in `hay` at or after `from`.
///
/// Returns -1 when absent, when `needle` is empty, or when it cannot fit.
pub fn find_sub(hay : String, needle : String, from? : Int32) -> Int32 {
  let start = match from {
    Some(v) => if v < 0 { 0 } else { v }
    None => 0
  }
  let n = hay.length()
  let m = needle.length()
  if m == 0 || m > n || start >= n {
    return -1
  }
  let mut i = start
  while i + m <= n {
    let mut j = 0
    let mut same = true
    while j < m {
      if hay[i + j] != needle[j] {
        same = false
        break
      }
      j = j + 1
    }
    if same {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// Last index of `needle` in `hay`, or -1.
pub fn rfind_sub(hay : String, needle : String) -> Int32 {
  let n = hay.length()
  let m = needle.length()
  if m == 0 || m > n {
    return -1
  }
  let mut found = -1
  let mut i = 0
  while i + m <= n {
    let mut j = 0
    let mut same = true
    while j < m {
      if hay[i + j] != needle[j] {
        same = false
        break
      }
      j = j + 1
    }
    if same {
      found = i
    }
    i = i + 1
  }
  found
}

///|
/// Split on `\n`, dropping a trailing `\r` from each line.
///
/// A trailing newline does not produce a final empty element; empty input
/// yields an empty array.
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
