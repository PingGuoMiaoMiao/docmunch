// Markdown normalization stage (P3).
//
// The converter is HTML -> CommonMark; both are produced/validated with
// moonbit-community/cmark in P3. v0 normalizes line endings so golden files stay
// stable across platforms.

///|
pub fn normalize_newlines(s : String) -> String {
  let buf = StringBuilder::StringBuilder()
  let mut prev_cr = false
  for c in s {
    if c == '\r' {
      buf.write_char('\n')
      prev_cr = true
    } else if c == '\n' {
      if !prev_cr {
        buf.write_char('\n')
      }
      prev_cr = false
    } else {
      buf.write_char(c)
      prev_cr = false
    }
  }
  buf.to_string()
}
