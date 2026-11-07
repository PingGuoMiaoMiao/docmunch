// Heading-based section splitting with UTF-8 byte offsets.
//
// v0 covers Markdown ATX headings. Setext headings, RST/AsciiDoc and HTML come
// later (see docs/roadmap). The output id scheme and byte offsets follow the
// contracts captured in docs/pre-research.md §2.

///|
pub(all) struct Heading {
  start : Int32
  level : Int32
  title : String
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
/// Split a document into sections. A section spans from its heading line to the
/// next heading line (or end of file). Content before the first heading becomes a
/// level-0 preamble section when it has non-whitespace text.
pub fn split_document(
  repo : String,
  doc_path : String,
  text : String,
) -> Array[@core.Section] {
  let heads : Array[Heading] = []
  let mut line = StringBuilder::StringBuilder()
  let mut line_len = 0
  let mut line_start = 0
  let mut total = 0
  let mut preamble_has_content = false
  let mut seen_heading = false

  let flush_line = () => {
    let raw = line.to_string()
    if !seen_heading && trim_spaces(raw) != "" {
      preamble_has_content = true
    }
    match parse_atx(raw) {
      Some(h) => {
        seen_heading = true
        heads.push({ start: line_start, level: h.level, title: h.title, })
      }
      None => ()
    }
    line = StringBuilder::StringBuilder()
    line_len = 0
  }

  for c in text {
    total = total + @core.utf8_len_of_char(c)
    if c == '\n' {
      flush_line()
      line_start = total
    } else {
      line.write_char(c)
      line_len = line_len + 1
    }
  }
  if line_len > 0 {
    flush_line()
  }

  let sections : Array[@core.Section] = []
  let ancestors : Array[(Int32, String, String)] = []
  let slug_seen : Map[String, Int32] = Map([])

  // Preamble: content before the first heading.
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
    })
  }

  for i = 0; i < heads.length(); i = i + 1 {
    let h = heads[i]
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
    let mut slug = @core.slugify(h.title)
    if slug == "" {
      slug = "sec\{i}"
    }
    let base = if parent_slug == "" { slug } else { parent_slug + "/" + slug }
    let seen = match slug_seen.get(base) {
      Some(n) => n
      None => 0
    }
    slug_seen[base] = seen + 1
    let unique = if seen == 0 { base } else { base + "-\{seen + 1}" }
    let id = @core.make_section_id(repo, doc_path, unique, h.level)
    let byte_end = if i + 1 < heads.length() {
      heads[i + 1].start
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
    })
    ancestors.push((h.level, id, unique))
  }
  sections
}
