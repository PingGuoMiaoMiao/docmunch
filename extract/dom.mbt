// Content extraction stage (P2).
//
// Plan (docs/pre-research.md §3): the parser from moonbit-community/html gives a
// flat, read-only node tree; this package owns a mutable arena DOM on top of it
// and a Readability-compatible scorer. v0 only carries whitespace normalization,
// which both the scorer and the Markdown stage need.

///|
/// Collapse runs of ASCII whitespace into one space and trim the ends.
pub fn collapse_whitespace(s : String) -> String {
  let buf = StringBuilder::StringBuilder()
  let mut pending = false
  let mut started = false
  for c in s {
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      if started {
        pending = true
      }
    } else {
      if pending {
        buf.write_char(' ')
        pending = false
      }
      buf.write_char(c)
      started = true
    }
  }
  buf.to_string()
}
