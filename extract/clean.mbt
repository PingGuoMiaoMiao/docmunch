// Unlikely-candidate filtering: drop scripts, navigation, ads and link-heavy blocks.

///|
fn is_junk_tag(tag : String) -> Bool {
  tag == "script" ||
  tag == "style" ||
  tag == "noscript" ||
  tag == "iframe" ||
  tag == "svg" ||
  tag == "canvas" ||
  tag == "form" ||
  tag == "input" ||
  tag == "select" ||
  tag == "button" ||
  tag == "textarea" ||
  tag == "link" ||
  tag == "meta" ||
  tag == "nav" ||
  tag == "footer" ||
  tag == "aside" ||
  tag == "dialog" ||
  tag == "template"
}

///|
fn is_alnum_ci(c : Char) -> Bool {
  let n = c.to_int()
  (n >= 97 && n <= 122) || (n >= 48 && n <= 57)
}

///|
/// Split a class/id blob into lowercase tokens on any non-alphanumeric char.
fn tokens_of(ci : String) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder::StringBuilder()
  for c in ci {
    if is_alnum_ci(c) {
      sb.write_char(c)
    } else if sb.to_string() != "" {
      out.push(sb.to_string())
      sb.reset()
    }
  }
  if sb.to_string() != "" {
    out.push(sb.to_string())
  }
  out
}

///|
fn is_negative_token(t : String) -> Bool {
  t == "header" ||
  t == "menu" ||
  t == "sidebar" ||
  t == "sponsor" ||
  t == "advert" ||
  t == "advertisement" ||
  t == "ads" ||
  t == "cookie" ||
  t == "cookies" ||
  t == "banner" ||
  t == "share" ||
  t == "sharing" ||
  t == "related" ||
  t == "promo" ||
  t == "modal" ||
  t == "popup" ||
  t == "newsletter" ||
  t == "subscribe" ||
  t == "breadcrumb" ||
  t == "breadcrumbs" ||
  t == "pagination" ||
  t == "toolbar" ||
  t == "masthead" ||
  t == "topbar" ||
  t == "drawer" ||
  t == "social" ||
  t == "disqus" ||
  t == "gdpr" ||
  t == "legend" ||
  t == "supplemental" ||
  t == "skyscraper" ||
  t == "combx" ||
  t == "remark" ||
  t == "replies" ||
  t == "shoutbox" ||
  t == "comment" ||
  t == "comments"
}

///|
fn has_negative_signal(ci : String) -> Bool {
  for t in tokens_of(ci) {
    if is_negative_token(t) {
      return true
    }
  }
  false
}

///|
fn is_positive_token(t : String) -> Bool {
  t == "article" ||
  t == "content" ||
  t == "entry" ||
  t == "main" ||
  t == "post" ||
  t == "story" ||
  t == "body" ||
  t == "markdown" ||
  t == "text" ||
  t == "readme"
}

///|
fn has_positive_signal(ci : String) -> Bool {
  for t in tokens_of(ci) {
    if is_positive_token(t) {
      return true
    }
  }
  false
}

///|
fn is_detached(doc : @html.Document, id : Int32) -> Bool {
  let mut cur = id
  while cur >= 0 {
    if cur == doc.document_element || cur == 0 {
      return false
    }
    let p = doc.get_parent(cur)
    if p < 0 {
      return true
    }
    cur = p
  }
  true
}

///|
pub fn clean(doc : @html.Document) -> Unit {
  let root = doc.body_element
  if root < 0 {
    return
  }
  for id in collect_elements(doc, root) {
    if is_detached(doc, id) {
      continue
    }
    let tag = tag_name(doc, id)
    if is_junk_tag(tag) {
      remove_node(doc, id)
      continue
    }
    let ci = class_and_id(doc, id)
    if has_negative_signal(ci) {
      remove_node(doc, id)
      continue
    }
    if attr(doc, id, "hidden") != "" || attr(doc, id, "aria-hidden") == "true" {
      remove_node(doc, id)
      continue
    }
    let role = attr(doc, id, "role").to_lower()
    if role == "navigation" ||
      role == "banner" ||
      role == "complementary" ||
      role == "contentinfo" ||
      role == "search" {
      remove_node(doc, id)
    }
  }
}

///|
fn link_lengths(doc : @html.Document, root : Int32) -> Map[Int32, Int32] {
  let lengths : Map[Int32, Int32] = Map([])
  fn visit(id : Int32) -> (Int32, Int32) {
    let mut text_total = 0
    let mut link_total = 0
    let is_link = tag_name(doc, id) == "a"
    match doc.get_node(id) {
      Some(@htmlsrc.Node::TextNode(t)) => text_total = t.length()
      _ => ()
    }
    for child in doc.get_children(id) {
      let (c_text, c_link) = visit(child)
      text_total = text_total + c_text
      link_total = link_total + c_link
    }
    if is_link {
      link_total = text_total
    }
    lengths[id] = link_total
    (text_total, link_total)
  }
  ignore(visit(root))
  lengths
}

///|
pub fn strip_link_blocks(doc : @html.Document) -> Unit {
  let root = doc.body_element
  if root < 0 {
    return
  }
  let text = text_lengths(doc, root)
  let links = link_lengths(doc, root)
  for id in collect_elements(doc, root) {
    if is_detached(doc, id) {
      continue
    }
    let tag = tag_name(doc, id)
    if !(tag == "div" ||
      tag == "section" ||
      tag == "ul" ||
      tag == "ol" ||
      tag == "p" ||
      tag == "table" ||
      tag == "nav") {
      continue
    }
    let total = match text.get(id) {
      Some(v) => v
      None => 0
    }
    if total < 120 {
      continue
    }
    let link = match links.get(id) {
      Some(v) => v
      None => 0
    }
    if link * 100 / total >= 65 {
      remove_node(doc, id)
    }
  }
}
