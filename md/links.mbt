// Link absolutization against the page URL.

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
