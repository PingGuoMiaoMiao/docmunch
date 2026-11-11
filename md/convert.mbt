// HTML -> CommonMark conversion for extracted article content.
//
// We render from the same DOM the extractor already pruned, rather than
// re-parsing through a second HTML library (ADR D24). Output is validated by
// feeding it back through moonbit-community/cmark in tests.

///|
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
fn escape_md(s : String) -> String {
  let sb = StringBuilder::StringBuilder()
  for c in s {
    if c == '\\' || c == '`' || c == '*' || c == '_' {
      sb.write_char('\\')
    }
    sb.write_char(c)
  }
  sb.to_string()
}

///|
/// Collapse whitespace runs but keep a single leading/trailing space, so inline
/// spans do not get glued together.
fn collapse_inline(s : String) -> String {
  let sb = StringBuilder::StringBuilder()
  let mut pending = false
  for c in s {
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      pending = true
    } else {
      if pending {
        sb.write_char(' ')
        pending = false
      }
      sb.write_char(c)
    }
  }
  if pending {
    sb.write_char(' ')
  }
  sb.to_string()
}

///|
fn heading_level(tag : String) -> Int32 {
  match tag {
    "h1" => 1
    "h2" => 2
    "h3" => 3
    "h4" => 4
    "h5" => 5
    "h6" => 6
    _ => 0
  }
}

///|
fn repeat_char(c : Char, n : Int32) -> String {
  let sb = StringBuilder::StringBuilder()
  for i = 0; i < n; i = i + 1 {
    sb.write_char(c)
  }
  sb.to_string()
}

///|
fn text_of_node(doc : @html.Document, id : Int32, sb : StringBuilder) -> Unit {
  match doc.get_node(id) {
    Some(@htmlsrc.Node::TextNode(t)) => sb.write_string(t)
    Some(@htmlsrc.Node::ElementNode(_)) =>
      if @extract.tag_name(doc, id) == "br" {
        sb.write_char('\n')
      } else {
        for child in doc.get_children(id) {
          text_of_node(doc, child, sb)
        }
      }
    _ => ()
  }
}

///|
/// Raw text (whitespace preserved) for `<pre>` blocks.
fn raw_text(doc : @html.Document, id : Int32) -> String {
  let sb = StringBuilder::StringBuilder()
  text_of_node(doc, id, sb)
  sb.to_string()
}

///|
fn code_language(doc : @html.Document, id : Int32) -> String {
  let ci = @extract.class_and_id(doc, id)
  let marker = "language-"
  let at = @text.find_sub(ci, marker)
  if at < 0 {
    return ""
  }
  let start = at + marker.length()
  let sb = StringBuilder::StringBuilder()
  let mut i = start
  while i < ci.length() {
    let c = ci[i].to_int()
    let is_word = (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) ||
      c == 45 ||
      c == 95
    if !is_word {
      break
    }
    sb.write_char(Int32::unsafe_to_char(c))
    i = i + 1
  }
  sb.to_string()
}

///|
fn inline_children(doc : @html.Document, id : Int32) -> String {
  let sb = StringBuilder::StringBuilder()
  for child in doc.get_children(id) {
    sb.write_string(inline_of(doc, child))
  }
  collapse_inline(sb.to_string()).trim().to_owned()
}

///|
/// Render inline content (text + emphasis/link/code) for one node.
fn inline_of(doc : @html.Document, id : Int32) -> String {
  match doc.get_node(id) {
    Some(@htmlsrc.Node::TextNode(t)) => escape_md(collapse_inline(t))
    Some(@htmlsrc.Node::CommentNode(_)) => ""
    Some(@htmlsrc.Node::ElementNode(_)) => {
      let tag = @extract.tag_name(doc, id)
      let inner = inline_children(doc, id)
      match tag {
        "strong" | "b" => "**\{inner}**"
        "em" | "i" => "*\{inner}*"
        "del" | "s" => "~~\{inner}~~"
        "code" => "`\{raw_text(doc, id)}`"
        "a" => {
          let href = @extract.attr(doc, id, "href")
          if href == "" || href.has_prefix("#") {
            inner
          } else {
            "[\{inner}](\{href})"
          }
        }
        "img" => {
          let alt = @extract.attr(doc, id, "alt")
          let src = @extract.attr(doc, id, "src")
          "![\{alt}](\{src})"
        }
        "br" => "  \n"
        _ => if is_block_tag(tag) { "" } else { inner }
      }
    }
    _ => ""
  }
}

///|
fn block_children(doc : @html.Document, id : Int32) -> String {
  let sb = StringBuilder::StringBuilder()
  let run = StringBuilder::StringBuilder()
  for child in doc.get_children(id) {
    let tag = @extract.tag_name(doc, child)
    if tag == "" || !is_block_tag(tag) {
      // Inline run: keep consecutive inline nodes inside one paragraph.
      run.write_string(inline_of(doc, child))
      continue
    }
    let run_text = collapse_inline(run.to_string()).trim().to_owned()
    if run_text != "" {
      sb.write_string(run_text)
      sb.write_string("\n\n")
      run.reset()
    }
    let block = block_of(doc, child).trim().to_owned()
    if block != "" {
      sb.write_string(block)
      sb.write_string("\n\n")
    }
  }
  let tail = collapse_inline(run.to_string()).trim().to_owned()
  if tail != "" {
    sb.write_string(tail)
    sb.write_string("\n\n")
  }
  sb.to_string()
}

///|
fn split_lines_local(text : String) -> Array[String] {
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

///|
fn list_of(doc : @html.Document, id : Int32, ordered : Bool) -> String {
  let sb = StringBuilder::StringBuilder()
  let mut index = 1
  for child in doc.get_children(id) {
    if @extract.tag_name(doc, child) != "li" {
      continue
    }
    let marker = if ordered { "\{index}. " } else { "- " }
    index = index + 1
    let body = block_children(doc, child)
    let body = if body.trim() == "" {
      inline_children(doc, child)
    } else {
      body.trim().to_owned()
    }
    let mut first = true
    for line in split_lines_local(body) {
      if first {
        sb.write_string(marker)
        first = false
      } else {
        sb.write_string("  ")
      }
      sb.write_string(line)
      sb.write_char('\n')
    }
  }
  sb.to_string()
}

///|
fn collect_rows(
  doc : @html.Document,
  id : Int32,
  out : Array[Array[String]],
) -> Unit {
  for child in doc.get_children(id) {
    let tag = @extract.tag_name(doc, child)
    if tag == "tr" {
      let cells : Array[String] = []
      for cell in doc.get_children(child) {
        let cell_tag = @extract.tag_name(doc, cell)
        if cell_tag == "td" || cell_tag == "th" {
          cells.push(inline_children(doc, cell))
        }
      }
      if cells.length() > 0 {
        out.push(cells)
      }
    } else if tag == "thead" ||
      tag == "tbody" ||
      tag == "tfoot" ||
      tag == "table" {
      collect_rows(doc, child, out)
    }
  }
}

///|
fn escape_pipes(s : String) -> String {
  let sb = StringBuilder::StringBuilder()
  for c in s {
    if c == '|' {
      sb.write_char('\\')
    }
    sb.write_char(c)
  }
  sb.to_string()
}

///|
fn table_of(doc : @html.Document, id : Int32) -> String {
  let rows : Array[Array[String]] = []
  collect_rows(doc, id, rows)
  if rows.length() == 0 {
    return ""
  }
  let sb = StringBuilder::StringBuilder()
  let width = rows[0].length()
  for i = 0; i < rows.length(); i = i + 1 {
    sb.write_char('|')
    for j = 0; j < width; j = j + 1 {
      let cell = if j < rows[i].length() { rows[i][j] } else { "" }
      sb.write_string(" \{escape_pipes(cell)} |")
    }
    sb.write_char('\n')
    if i == 0 {
      sb.write_char('|')
      for j = 0; j < width; j = j + 1 {
        sb.write_string(" --- |")
      }
      sb.write_char('\n')
    }
  }
  sb.to_string()
}

///|
fn prefix_lines(text : String, prefix : String) -> String {
  let sb = StringBuilder::StringBuilder()
  for line in split_lines_local(text.trim().to_owned()) {
    sb.write_string(prefix)
    sb.write_string(line.trim_end().to_owned())
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
fn block_of(doc : @html.Document, id : Int32) -> String {
  match doc.get_node(id) {
    Some(@htmlsrc.Node::TextNode(t)) => escape_md(collapse_inline(t))
    Some(@htmlsrc.Node::CommentNode(_)) => ""
    Some(@htmlsrc.Node::ElementNode(_)) => {
      let tag = @extract.tag_name(doc, id)
      let level = heading_level(tag)
      if level > 0 {
        "\{repeat_char('#', level)} \{inline_children(doc, id)}\n\n"
      } else {
        match tag {
          "p" => "\{inline_children(doc, id)}\n\n"
          "pre" => {
            let code = raw_text(doc, id)
            let lang = code_language(doc, id)
            "\n```\{lang}\n\{code}\n```\n\n"
          }
          "ul" => "\{list_of(doc, id, false)}\n"
          "ol" => "\{list_of(doc, id, true)}\n"
          "blockquote" => "\{prefix_lines(block_children(doc, id), "> ")}\n"
          "table" => "\{table_of(doc, id)}\n"
          "hr" => "---\n\n"
          "br" => "  \n"
          "li" => "\{block_children(doc, id)}\n"
          _ => block_children(doc, id)
        }
      }
    }
    _ => ""
  }
}

///|
fn is_absolute_url(href : String) -> Bool {
  href.has_prefix("http://") ||
  href.has_prefix("https://") ||
  href.has_prefix("//") ||
  href.has_prefix("#") ||
  href.has_prefix("mailto:") ||
  href.has_prefix("data:") ||
  href.has_prefix("javascript:")
}

///|
/// Resolve `href` against `base`; returns `href` unchanged when it cannot.
fn resolve_url(base : String, href : String) -> String {
  if href == "" || is_absolute_url(href) {
    return href
  }
  if base == "" {
    return href
  }
  let base_url = @url.Url::parse(base) catch { _ => return href }
  let joined = @url.Url::parse(href, base=base_url) catch { _ => return href }
  joined.href()
}

///|
/// Rewrite relative `href`/`src` attributes in place so the Markdown output is
/// usable outside the original page context.
fn absolutize(doc : @html.Document, base_url : String) -> Unit {
  if base_url == "" {
    return
  }
  for id in @extract.collect_elements(doc, doc.document_element) {
    let tag = @extract.tag_name(doc, id)
    if tag == "a" {
      let href = @extract.attr(doc, id, "href")
      if href != "" {
        doc.set_attribute(id, "href", resolve_url(base_url, href))
      }
    } else if tag == "img" {
      let src = @extract.attr(doc, id, "src")
      if src != "" {
        doc.set_attribute(id, "src", resolve_url(base_url, src))
      }
    }
  }
}

///|
/// Fence marker (` ``` ` or `~~~`) when the line opens/closes a fenced block.
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
  for line in split_lines_local(s) {
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
