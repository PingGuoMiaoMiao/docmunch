// Inline rendering: text, emphasis, code spans, links and images.

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
