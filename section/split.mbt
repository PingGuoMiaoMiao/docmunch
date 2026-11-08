// Heading-based section splitting with UTF-8 byte offsets.
//
// v1 covers ATX and setext headings, ignores heading-like lines inside fenced
// code blocks, and stamps every section with a sha256 of its bytes. The id
// scheme and byte offsets follow the contracts in docs/pre-research.md §2.

///|
pub(all) struct Heading {
  start : Int32
  level : Int32
  title : String
}

///|
pub(all) struct Line {
  text : String
  start : Int32
}

///|
fn is_space_char(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
fn trim_spaces(s : String) -> String {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  let mut start = 0
  let mut end = chars.length()
  while start < end && is_space_char(chars[start]) {
    start = start + 1
  }
  while end > start && is_space_char(chars[end - 1]) {
    end = end - 1
  }
  let buf = StringBuilder::StringBuilder()
  for i = start; i < end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// Parse an ATX heading line (`## Title`). Returns level 0 when not a heading.
pub fn parse_atx(line : String) -> Heading? {
  let mut level = 0
  let body = StringBuilder::StringBuilder()
  let mut in_body = false
  for c in line {
    if in_body {
      body.write_char(c)
    } else if c == '#' && level < 6 {
      level = level + 1
    } else if c == ' ' && level > 0 {
      in_body = true
    } else {
      return None
    }
  }
  if !in_body || level == 0 {
    return None
  }
  Some({ start: 0, level, title: trim_spaces(body.to_string()), })
}

///|
fn is_setext_underline(line : String) -> Int32 {
  let t = trim_spaces(line)
  if t == "" {
    return 0
  }
  let chars : Array[Char] = []
  for c in t {
    chars.push(c)
  }
  let first = chars[0]
  if first != '=' && first != '-' {
    return 0
  }
  for i = 1; i < chars.length(); i = i + 1 {
    if chars[i] != first {
      return 0
    }
  }
  if first == '=' {
    1
  } else {
    2
  }
}

///|
/// True when the line opens/closes a fenced code block.
fn fence_marker(line : String) -> String {
  let t = trim_spaces(line)
  if t.has_prefix("```") {
    "```"
  } else if t.has_prefix("~~~") {
    "~~~"
  } else {
    ""
  }
}

///|
/// Split the text into lines carrying their UTF-8 byte offset.
pub fn split_lines_with_offsets(text : String) -> Array[Line] {
  let lines : Array[Line] = []
  let sb = StringBuilder::StringBuilder()
  let mut line_start = 0
  let mut byte = 0
  for c in text {
    byte = byte + @core.utf8_len_of_char(c)
    if c == '\n' {
      lines.push({ text: sb.to_string(), start: line_start, })
      sb.reset()
      line_start = byte
    } else if c != '\r' {
      sb.write_char(c)
    }
  }
  let tail = sb.to_string()
  if tail != "" {
    lines.push({ text: tail, start: line_start, })
  }
  lines
}

///|
/// Remove zero-width/BOM/NBSP noise that survives HTML->Markdown conversion.
fn sanitize_title(raw : String) -> String {
  let sb = StringBuilder::StringBuilder()
  for c in raw {
    let n = c.to_int()
    if n != 0x200B && n != 0xFEFF && n != 0x00A0 && n != 0x00B6 {
      sb.write_char(c)
    }
  }
  trim_spaces(sb.to_string())
}

///|
fn stable_slug(title : String, fallback_index : Int32) -> String {
  let base = @core.slugify(title)
  if base != "" {
    base
  } else {
    let h = sha256_of(title)
    if h.length() >= 8 {
      "h" + h[0:8].to_owned()
    } else {
      "sec\{fallback_index}"
    }
  }
}

///|
/// Extract a string slice by UTF-8 byte offsets.
pub fn slice_bytes(text : String, start : Int32, end : Int32) -> String {
  let sb = StringBuilder::StringBuilder()
  let mut byte = 0
  for c in text {
    let next = byte + @core.utf8_len_of_char(c)
    if byte >= end {
      break
    }
    if byte >= start {
      sb.write_char(c)
    }
    byte = next
  }
  sb.to_string()
}

///|
pub fn sha256_of(s : String) -> String {
  sha256_hex_text(s)
}

///|
fn sha256_hex_text(s : String) -> String {
  let d = @sha256.Digest::new()
  for b in @utf8.encode(s) {
    d.write(b)
  }
  d.check_sum()
}

///|
/// Split a document into sections. A section spans from its heading line to the
/// next heading line (or end of file). Content before the first heading becomes a
/// level-0 preamble section when it has non-whitespace text.
pub fn split_document(
  repo : String,
  doc_path : String,
  text : String,
) -> Array[@core.Section] {
  let lines = split_lines_with_offsets(text)
  let heads : Array[Heading] = []
  let mut fence = ""
  let mut seen_heading = false
  let mut preamble_has_content = false
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    let marker = fence_marker(line.text)
    if marker != "" {
      if fence == "" {
        fence = marker
      } else if fence == marker {
        fence = ""
      }
      i = i + 1
      continue
    }
    if fence != "" {
      i = i + 1
      continue
    }
    match parse_atx(line.text) {
      Some(h) => {
        seen_heading = true
        heads.push({
          start: line.start,
          level: h.level,
          title: sanitize_title(h.title),
        })
        i = i + 1
      }
      None => {
        let level = if i + 1 < lines.length() {
          is_setext_underline(lines[i + 1].text)
        } else {
          0
        }
        if level > 0 && trim_spaces(line.text) != "" {
          seen_heading = true
          heads.push({
            start: line.start,
            level,
            title: sanitize_title(line.text),
          })
          i = i + 2
        } else {
          if !seen_heading && trim_spaces(line.text) != "" {
            preamble_has_content = true
          }
          i = i + 1
        }
      }
    }
  }

  let total = @core.utf8_len(text)
  let sections : Array[@core.Section] = []
  let ancestors : Array[(Int32, String, String)] = []
  let slug_seen : Map[String, Int32] = Map([])

  if preamble_has_content && heads.length() > 0 && heads[0].start > 0 {
    let id = @core.make_section_id(repo, doc_path, "preamble", 0)
    sections.push({
      id,
      repo,
      doc_path,
      title: "",
      level: 0,
      byte_start: 0,
      byte_end: heads[0].start,
      parent_id: "",
      content_hash: sha256_hex_text(slice_bytes(text, 0, heads[0].start)),
      keywords: @core.extract_keywords(slice_bytes(text, 0, heads[0].start)),
    })
  }

  for idx = 0; idx < heads.length(); idx = idx + 1 {
    let h = heads[idx]
    while ancestors.length() > 0 &&
          ancestors[ancestors.length() - 1].0 >= h.level {
      ignore(ancestors.pop())
    }
    let parent_id = if ancestors.length() == 0 {
      ""
    } else {
      ancestors[ancestors.length() - 1].1
    }
    let parent_slug = if ancestors.length() == 0 {
      ""
    } else {
      ancestors[ancestors.length() - 1].2
    }
    let mut slug = stable_slug(h.title, idx)
    if slug == "" {
      slug = "sec\{idx}"
    }
    let base = if parent_slug == "" { slug } else { parent_slug + "/" + slug }
    let seen = match slug_seen.get(base) {
      Some(n) => n
      None => 0
    }
    slug_seen[base] = seen + 1
    let unique = if seen == 0 { base } else { base + "-\{seen + 1}" }
    let id = @core.make_section_id(repo, doc_path, unique, h.level)
    let byte_end = if idx + 1 < heads.length() {
      heads[idx + 1].start
    } else {
      total
    }
    sections.push({
      id,
      repo,
      doc_path,
      title: h.title,
      level: h.level,
      byte_start: h.start,
      byte_end,
      parent_id,
      content_hash: sha256_hex_text(slice_bytes(text, h.start, byte_end)),
      keywords: @core.extract_keywords(slice_bytes(text, h.start, byte_end)),
    })
    ancestors.push((h.level, id, unique))
  }
  sections
}

///|
pub fn section_text(text : String, s : @core.Section) -> String {
  slice_bytes(text, s.byte_start, s.byte_end)
}
