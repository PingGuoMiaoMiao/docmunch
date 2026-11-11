// Block rendering: paragraphs, lists, tables, blockquotes and code fences.

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
    for line in @text.split_lines(body) {
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
  for line in @text.split_lines(text.trim().to_owned()) {
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
