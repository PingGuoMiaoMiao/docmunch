// reStructuredText -> Markdown (subset).
//
// RST has no explicit heading markers: a title is a line followed by a line of
// repeated punctuation, and the *order in which each adornment character first
// appears* decides the level. That is the rule this converter implements, plus
// the two block constructs documentation actually uses: directive blocks
// (`.. code-block:: python`) and literal blocks (a paragraph ending in `::`).
//
// Everything else degrades to plain text rather than being dropped, so a
// document always yields something indexable (D53).

///|
fn is_rst_adornment(line : String) -> Int32 {
  let trimmed = line.trim()
  if trimmed.length() < 3 {
    return 0
  }
  let first = trimmed[0].to_int()
  let allowed = first == 61 ||
    first == 45 ||
    first == 126 ||
    first == 94 ||
    first == 42 ||
    first == 43 ||
    first == 35 ||
    first == 34 ||
    first == 39 ||
    first == 96 ||
    first == 58 ||
    first == 46 ||
    first == 95
  if !allowed {
    return 0
  }
  for c in trimmed {
    if c.to_int() != first {
      return 0
    }
  }
  trimmed.length()
}

///|
fn indent_of(line : String) -> Int32 {
  let mut n = 0
  for c in line {
    if c == ' ' {
      n = n + 1
    } else if c == '\t' {
      n = n + 4
    } else {
      break
    }
  }
  n
}

///|
fn directive_language(line : String) -> String? {
  let trimmed = line.trim()
  for marker in [".. code-block:: ", ".. code:: ", ".. sourcecode:: "] {
    if trimmed.has_prefix(marker) {
      return Some(trimmed[marker.length():trimmed.length()].trim().to_owned())
    }
  }
  None
}

///|
fn is_directive(line : String) -> Bool {
  line.trim().has_prefix(".. ")
}

///|
/// Convert an RST document to Markdown.
pub fn rst_to_markdown(source : String) -> String {
  let lines = @text.split_lines(source)
  let levels : Array[Char] = []
  let out = StringBuilder::StringBuilder()
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    // Heading: current line + adornment line.
    if i + 1 < lines.length() &&
      is_rst_adornment(lines[i + 1]) > 0 &&
      line.trim() != "" &&
      is_rst_adornment(line) == 0 {
      let mark = Char::from_int(lines[i + 1].trim()[0].to_int())
      let mut level = 0
      let mut found = false
      for idx = 0; idx < levels.length(); idx = idx + 1 {
        if levels[idx] == mark {
          level = idx + 1
          found = true
        }
      }
      if !found {
        levels.push(mark)
        level = levels.length()
      }
      let hashed = if level > 6 { 6 } else { level }
      out.write_string("\{repeat_char('#', hashed)} \{line.trim()}\n\n")
      i = i + 2
      continue
    }
    // Directive block: collect the indented body, emit a fence when it is code.
    if is_directive(line) {
      let lang = directive_language(line)
      let base_indent = indent_of(line)
      let body = StringBuilder::StringBuilder()
      let mut j = i + 1
      while j < lines.length() {
        if lines[j].trim() == "" {
          body.write_char('\n')
          j = j + 1
          continue
        }
        if indent_of(lines[j]) <= base_indent {
          break
        }
        body.write_string(strip_indent(lines[j], base_indent + 3))
        body.write_char('\n')
        j = j + 1
      }
      match lang {
        Some(language) =>
          out.write_string(
            "\n```\{language}\n\{body.to_string().trim_end().to_owned()}\n```\n\n",
          )
        None => {
          let text = body.to_string().trim().to_owned()
          if text != "" {
            out.write_string("> \{text}\n\n")
          }
        }
      }
      i = j
      continue
    }
    // Literal block: paragraph ending with `::`.
    if line.trim().has_suffix("::") {
      out.write_string(line.trim_end().to_owned())
      out.write_string("\n\n")
      let base_indent = indent_of(line)
      let body = StringBuilder::StringBuilder()
      let mut j = i + 1
      while j < lines.length() {
        if lines[j].trim() == "" {
          body.write_char('\n')
          j = j + 1
          continue
        }
        if indent_of(lines[j]) <= base_indent {
          break
        }
        body.write_string(strip_indent(lines[j], base_indent + 3))
        body.write_char('\n')
        j = j + 1
      }
      let text = body.to_string().trim_end().to_owned()
      if text != "" {
        out.write_string("\n```\n\{text}\n```\n\n")
      }
      i = j
      continue
    }
    out.write_string(line)
    out.write_char('\n')
    i = i + 1
  }
  squash_blank_lines(out.to_string())
}

///|
fn strip_indent(line : String, width : Int32) -> String {
  let mut skip = 0
  let mut cut = 0
  for c in line {
    if skip >= width {
      break
    }
    if c == ' ' {
      skip = skip + 1
      cut = cut + 1
    } else if c == '\t' {
      skip = skip + 4
      cut = cut + 1
    } else {
      break
    }
  }
  line[cut:line.length()].to_owned()
}
