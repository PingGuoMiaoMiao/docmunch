// Readability-compatible extraction.
//
// Not a line-by-line port (see ADR D4): we keep the scoring shape — candidate
// paragraphs weighted by text density and class/id semantics, propagated to
// ancestors — then prune the live tree to the winning container and serialize it.
// Dependencies on node cloning are avoided on purpose (ADR D20).

///|
pub(all) struct Extracted {
  title : String
  byline : String
  site_name : String
  lang : String
  text : String
  html : String
  length : Int32
}

///|
fn text_of(doc : @html.Document, id : Int32) -> String {
  if id < 0 {
    return ""
  }
  collapse_whitespace(doc.get_text_content(id))
}

///|
fn find_tag(doc : @html.Document, tag : String) -> Int32 {
  let root = doc.document_element
  if root < 0 {
    return -1
  }
  for id in collect_elements(doc, root) {
    if tag_name(doc, id) == tag {
      return id
    }
  }
  -1
}

///|
fn meta_content(doc : @html.Document, key : String) -> String {
  let root = doc.document_element
  if root < 0 {
    return ""
  }
  for id in collect_elements(doc, root) {
    if tag_name(doc, id) == "meta" {
      let name = (attr(doc, id, "name") + " " + attr(doc, id, "property")).to_lower()
      if str_contains_pub(name, key) {
        let content = attr(doc, id, "content")
        if content != "" {
          return content
        }
      }
    }
  }
  ""
}

///|
pub fn extract(html : String, url : String) -> Extracted {
  let doc = @html.parse(html)
  let root = doc.document_element
  let lang = if root >= 0 { attr(doc, root, "lang") } else { "" }
  let title_tag = find_tag(doc, "title")
  let mut title = text_of(doc, title_tag)
  if title == "" {
    title = meta_content(doc, "og:title")
  }
  if title == "" {
    let h1 = find_tag(doc, "h1")
    title = text_of(doc, h1)
  }
  let byline = {
    let a = meta_content(doc, "author")
    if a != "" {
      a
    } else {
      meta_content(doc, "article:author")
    }
  }
  let site_name = {
    let s = meta_content(doc, "og:site_name")
    if s != "" {
      s
    } else if url.has_prefix("http://") || url.has_prefix("https://") {
      host_of(url)
    } else {
      // Local paths/plain names are not URLs: there is no site to name.
      ""
    }
  }
  clean(doc)
  strip_link_blocks(doc)
  let container = extract_main(doc)
  let text = text_of(doc, container)
  let out_html = body_inner_html(doc)
  {
    title: clean_title(title, site_name),
    byline,
    site_name,
    lang,
    text,
    html: out_html,
    length: text.length(),
  }
}
