// Core model shared by the whole pipeline.
//
// A `Section` is a heading-delimited slice of one source document. It stores
// byte offsets (UTF-8) into the cached raw file instead of the text itself, so
// retrieval is O(1) seek+read and the index stays small.
//
// See docs/decisions.md (D7, D8) for why the id scheme mirrors jdocmunch.

///|
pub(all) struct Section {
  id : String
  repo : String
  doc_path : String
  title : String
  level : Int32
  byte_start : Int32
  byte_end : Int32
  parent_id : String
  content_hash : String
}

///|
pub(all) struct DocIndex {
  repo : String
  doc_paths : Array[String]
  sections : Array[Section]
  index_version : Int32
}

///|
pub let index_version : Int32 = 1

///|
/// Number of UTF-8 bytes a single code point occupies.
pub fn utf8_len_of_char(c : Char) -> Int32 {
  let n = c.to_int()
  if n < 0x80 {
    1
  } else if n < 0x800 {
    2
  } else if n < 0x10000 {
    3
  } else {
    4
  }
}

///|
/// Number of UTF-8 bytes in a string.
///
/// Byte offsets must be UTF-8 based: they are used with `seek()` on the raw
/// file, and MoonBit strings are indexed by code units, not bytes.
pub fn utf8_len(s : String) -> Int32 {
  let mut total = 0
  for c in s {
    total = total + utf8_len_of_char(c)
  }
  total
}

///|
fn is_ascii_lower(c : Char) -> Bool {
  let n = c.to_int()
  n >= 0x61 && n <= 0x7a
}

///|
fn is_ascii_digit(c : Char) -> Bool {
  let n = c.to_int()
  n >= 0x30 && n <= 0x39
}

///|
fn is_ascii_upper(c : Char) -> Bool {
  let n = c.to_int()
  n >= 0x41 && n <= 0x5a
}

///|
/// Lowercase ASCII and replace every other character run with a single `-`.
///
/// Non-ASCII headings (e.g. Chinese) produce an empty slug; callers fall back
/// to the heading level and a counter so ids stay unique. Documented limitation,
/// see docs/decisions.md (D7).
pub fn slugify(title : String) -> String {
  let buf = StringBuilder::StringBuilder()
  let mut count = 0
  let mut pending_dash = false
  for c in title {
    if is_ascii_lower(c) || is_ascii_digit(c) {
      if pending_dash && count > 0 {
        buf.write_char('-')
        count = count + 1
      }
      pending_dash = false
      buf.write_char(c)
      count = count + 1
    } else if is_ascii_upper(c) {
      if pending_dash && count > 0 {
        buf.write_char('-')
        count = count + 1
      }
      pending_dash = false
      buf.write_char(Int32::unsafe_to_char(c.to_int() + 0x20))
      count = count + 1
    } else {
      pending_dash = true
    }
  }
  buf.to_string()
}

///|
/// Build a section id: `{repo}::{doc_path}::{hierarchical_slug}#{level}`.
///
/// The slug path carries the ancestor chain (e.g. `installation/prerequisites`),
/// so inserting a sibling heading does not renumber other branches.
pub fn make_section_id(
  repo : String,
  doc_path : String,
  slug_path : String,
  level : Int32,
) -> String {
  "\{repo}::\{doc_path}::\{slug_path}#\{level}"
}

///|
pub fn Section::byte_len(self : Section) -> Int32 {
  self.byte_end - self.byte_start
}

///|
pub fn Section::is_root(self : Section) -> Bool {
  self.level == 0
}
