// Thin, mutable DOM helpers over moonbit-community/html.
//
// The parser ships a mutable tree (append_child / remove_child / insert_before /
// set_attribute), but its node constructors are package-private: we cannot build
// new nodes or clone across documents. So extraction works *in place* — clean up,
// score, prune, then serialize the surviving subtree. See ADR D20.

///|
pub fn body_id(doc : @html.Document) -> Int32 {
  doc.body_element
}

///|
pub fn node_children(doc : @html.Document, id : Int32) -> Array[Int32] {
  doc.get_children(id)
}

///|
pub fn node_parent(doc : @html.Document, id : Int32) -> Int32 {
  doc.get_parent(id)
}

///|
/// Tag name, or `""` for non-element nodes.
pub fn tag_name(doc : @html.Document, id : Int32) -> String {
  match doc.get_tag_name(id) {
    Some(t) => t
    None => ""
  }
}

///|
pub fn attr(doc : @html.Document, id : Int32, name : String) -> String {
  match doc.get_attribute(id, name) {
    Some(v) => v
    None => ""
  }
}

///|
/// Lowercased `class` + `id` + `itemprop`, used by the scoring heuristics.
pub fn class_and_id(doc : @html.Document, id : Int32) -> String {
  let c = attr(doc, id, "class")
  let i = attr(doc, id, "id")
  let p = attr(doc, id, "itemprop")
  (c + " " + i + " " + p).to_lower()
}

///|
/// Detach a node from its parent. No-op for the document root.
pub fn remove_node(doc : @html.Document, id : Int32) -> Unit {
  let p = doc.get_parent(id)
  if p >= 0 && p != id {
    doc.remove_child(p, id)
  }
}

///|
/// Replace a node by its children (used to unwrap inline wrappers).
pub fn unwrap_node(doc : @html.Document, id : Int32) -> Unit {
  let p = doc.get_parent(id)
  if p < 0 {
    return
  }
  for child in doc.get_children(id) {
    doc.insert_before(p, child, id)
  }
  doc.remove_child(p, id)
}

///|
/// Depth-first list of every element id under `root` (excluding `root`).
pub fn collect_elements(doc : @html.Document, root : Int32) -> Array[Int32] {
  let out : Array[Int32] = []
  let stack : Array[Int32] = [root]
  while stack.length() > 0 {
    let id = match stack.pop() {
      Some(v) => v
      None => break
    }
    if id != root && doc.get_tag_name(id) is Some(_) {
      out.push(id)
    }
    for child in doc.get_children(id) {
      stack.push(child)
    }
  }
  out
}

///|
/// Map every node id to the total text length of its subtree.
pub fn text_lengths(doc : @html.Document, root : Int32) -> Map[Int32, Int32] {
  let lengths : Map[Int32, Int32] = Map([])
  fn visit(id : Int32) -> Int32 {
    let mut total = 0
    match doc.get_node(id) {
      Some(@htmlsrc.Node::TextNode(t)) => total = t.length()
      _ => ()
    }
    for child in doc.get_children(id) {
      total = total + visit(child)
    }
    lengths[id] = total
    total
  }
  ignore(visit(root))
  lengths
}

///|
/// Inner HTML of `<body>` from the serialized document (wrapper `<body>` and
/// `<head>` are dropped; the parser always emits them).
pub fn body_inner_html(doc : @html.Document) -> String {
  let html = doc.to_html()
  let body_at = @text.find_sub(html, "<body")
  if body_at < 0 {
    return html
  }
  let gt = @text.find_sub(html, ">", from=body_at)
  if gt < 0 {
    return html
  }
  let end = @text.find_sub(html, "</body>", from=gt + 1)
  if end < 0 {
    return html
  }
  let start = gt + 1
  html[start:end].to_owned()
}

///|
/// Collapse ASCII whitespace runs into one space and trim both ends.
pub fn collapse_whitespace(s : String) -> String {
  let sb = StringBuilder::StringBuilder()
  let mut pending = false
  let mut started = false
  for c in s {
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      if started {
        pending = true
      }
    } else {
      if pending {
        sb.write_char(' ')
        pending = false
      }
      sb.write_char(c)
      started = true
    }
  }
  sb.to_string()
}
