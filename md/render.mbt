// HTML -> CommonMark conversion for extracted article content.
//
// We render from the same DOM the extractor already pruned, rather than
// re-parsing through a second HTML library (ADR D24). Output is validated by
// feeding it back through moonbit-community/cmark in tests.

///|
// Render entry point, block classification and whitespace normalization.

fn is_block_tag(tag : String) -> Bool {
  tag == "p" ||
  tag == "div" ||
  tag == "section" ||
  tag == "article" ||
  tag == "main" ||
  tag == "header" ||
  tag == "footer" ||
  tag == "aside" ||
  tag == "figure" ||
  tag == "figcaption" ||
  tag == "ul" ||
  tag == "ol" ||
  tag == "li" ||
  tag == "pre" ||
  tag == "table" ||
  tag == "blockquote" ||
  tag == "h1" ||
  tag == "h2" ||
  tag == "h3" ||
  tag == "h4" ||
  tag == "h5" ||
  tag == "h6" ||
  tag == "hr"
}

///|
fn line_fence_marker(line : String) -> String {
  let t = line.trim().to_owned()
  if t.has_prefix("```") {
    "```"
  } else if t.has_prefix("~~~") {
    "~~~"
  } else {
    ""
  }
}

///|
/// Collapse consecutive blank lines outside fenced code blocks. Blank lines
/// inside a fence are content and stay verbatim; outside, a run of blank lines
/// becomes one. The result ends with exactly one newline (or is empty).
fn squash_blank_lines(s : String) -> String {
  let out : Array[String] = []
  let mut fence = ""
  let mut pending_blanks = 0
  for line in @text.split_lines(s) {
    let marker = line_fence_marker(line)
    if fence != "" {
      // Inside a fence every line, including blank ones, is preserved.
      out.push(line)
      if marker == fence {
        fence = ""
      }
      continue
    }
    if marker != "" {
      if pending_blanks > 0 && out.length() > 0 {
        out.push("")
      }
      pending_blanks = 0
      out.push(line)
      fence = marker
      continue
    }
    if line.trim() == "" {
      pending_blanks = pending_blanks + 1
    } else {
      if pending_blanks > 0 && out.length() > 0 {
        out.push("")
      }
      pending_blanks = 0
      out.push(line)
    }
  }
  if out.length() == 0 {
    return ""
  }
  let sb = StringBuilder::StringBuilder()
  for i = 0; i < out.length(); i = i + 1 {
    if i > 0 {
      sb.write_char('\n')
    }
    sb.write_string(out[i])
  }
  let trimmed = sb.to_string().trim().to_owned()
  if trimmed == "" {
    ""
  } else {
    trimmed + "\n"
  }
}

///|
/// Convert an HTML document/string to CommonMark.
pub fn html_to_markdown(html : String, base_url? : String) -> String {
  let doc = @html.parse(html)
  match base_url {
    Some(base) => absolutize(doc, base)
    None => ()
  }
  let body = @extract.body_id(doc)
  let raw = if body >= 0 { block_children(doc, body) } else { "" }
  squash_blank_lines(raw)
}
