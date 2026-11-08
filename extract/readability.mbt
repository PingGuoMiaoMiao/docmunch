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
/// Plain substring test used by the heuristics (public so dom-level tests can reuse).
pub fn str_contains_pub(hay : String, needle : String) -> Bool {
  let n = hay.length()
  let m = needle.length()
  if m == 0 {
    return true
  }
  if m > n {
    return false
  }
  let mut i = 0
  while i + m <= n {
    let mut j = 0
    let mut same = true
    while j < m {
      if hay[i + j] != needle[j] {
        same = false
        break
      }
      j = j + 1
    }
    if same {
      return true
    }
    i = i + 1
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
/// Remove scripts, navigation, ads and other unlikely-candidate subtrees.
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
fn count_commas(text : String) -> Int32 {
  let mut n = 0
  for c in text {
    if c == ',' || c == '，' || c == '、' {
      n = n + 1
    }
  }
  n
}

///|
fn add_score(scores : Map[Int32, Double], id : Int32, delta : Double) -> Unit {
  if id < 0 {
    return
  }
  let prev = match scores.get(id) {
    Some(v) => v
    None => 0.0
  }
  scores[id] = prev + delta
}

///|
/// Score candidate paragraphs and propagate to their ancestors.
pub fn score_candidates(doc : @html.Document) -> Map[Int32, Double] {
  let root = doc.body_element
  let scores : Map[Int32, Double] = Map([])
  if root < 0 {
    return scores
  }
  let lengths = text_lengths(doc, root)
  let ids = collect_elements(doc, root)
  for id in ids {
    if is_detached(doc, id) {
      continue
    }
    let tag = tag_name(doc, id)
    let text_len = match lengths.get(id) {
      Some(v) => v
      None => 0
    }
    if text_len < 25 {
      continue
    }
    if tag == "p" || tag == "pre" || tag == "td" || tag == "blockquote" {
      let text = doc.get_text_content(id)
      let base = 1.0 +
        count_commas(text).to_double() +
        (text_len.to_double() / 100.0).min(3.0)
      let ci = class_and_id(doc, id)
      let weight = if has_positive_signal(ci) {
        25.0
      } else if has_negative_signal(ci) {
        -25.0
      } else {
        0.0
      }
      let total = base + weight
      let parent = doc.get_parent(id)
      add_score(scores, parent, total)
      if parent >= 0 {
        add_score(scores, doc.get_parent(parent), total / 2.0)
      }
    }
  }
  scores
}

///|
fn best_candidate(doc : @html.Document, scores : Map[Int32, Double]) -> Int32 {
  let root = doc.body_element
  let mut best = root
  let mut best_score = -1.0
  for pair in scores {
    let (id, score) = pair
    if is_detached(doc, id) {
      continue
    }
    if score > best_score {
      best = id
      best_score = score
    }
  }
  best
}

///|
/// Prune the document to the winning container: body keeps only that container,
/// the container keeps only the candidate and article-like siblings.
pub fn extract_main(doc : @html.Document) -> Int32 {
  let root = doc.body_element
  if root < 0 {
    return -1
  }
  let lengths = text_lengths(doc, root)
  let scores = score_candidates(doc)
  let candidate = best_candidate(doc, scores)
  if candidate == root {
    return root
  }
  let candidate_score = match scores.get(candidate) {
    Some(v) => v
    None => 0.0
  }
  let parent = doc.get_parent(candidate)
  if parent < 0 {
    return root
  }
  // Keep only article-like siblings inside the parent.
  for child in doc.get_children(parent) {
    let keep = if child == candidate {
      true
    } else {
      let tag = tag_name(doc, child)
      let len = match lengths.get(child) {
        Some(v) => v
        None => 0
      }
      let score = match scores.get(child) {
        Some(v) => v
        None => 0.0
      }
      if tag == "br" || tag == "hr" {
        true
      } else if score > 0.0 && score >= candidate_score * 0.2 {
        true
      } else {
        (tag == "p" || tag == "pre" || tag == "blockquote") && len >= 80
      }
    }
    if !keep {
      remove_node(doc, child)
    }
  }
  // Collapse the ancestor chain: at every level keep only the path to the
  // container, then unwrap intermediate wrappers so the container sits directly
  // under <body> and serialization yields just this container.
  let body = root
  let mut node = parent
  while true {
    let p = doc.get_parent(node)
    if p < 0 || p == body {
      break
    }
    for child in doc.get_children(p) {
      if child != node {
        remove_node(doc, child)
      }
    }
    node = p
  }
  for child in doc.get_children(body) {
    if child != node {
      remove_node(doc, child)
    }
  }
  while true {
    let p = doc.get_parent(parent)
    if p < 0 || p == body {
      break
    }
    unwrap_node(doc, p)
  }
  parent
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
fn host_of(url : String) -> String {
  let mut start = 0
  let scheme_end = str_find(url, "://")
  if scheme_end >= 0 {
    start = scheme_end + 3
  }
  let mut end = url.length()
  let mut i = start
  while i < url.length() {
    let c = url[i].to_int()
    if c == 47 || c == 63 || c == 35 {
      end = i
      break
    }
    i = i + 1
  }
  if end <= start {
    ""
  } else {
    url[start:end].to_owned()
  }
}

///|
fn str_find(hay : String, needle : String) -> Int32 {
  let n = hay.length()
  let m = needle.length()
  if m == 0 || m > n {
    return -1
  }
  let mut i = 0
  while i + m <= n {
    let mut j = 0
    let mut same = true
    while j < m {
      if hay[i + j] != needle[j] {
        same = false
        break
      }
      j = j + 1
    }
    if same {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn rfind_sub(hay : String, needle : String) -> Int32 {
  let n = hay.length()
  let m = needle.length()
  if m == 0 || m > n {
    return -1
  }
  let mut found = -1
  let mut i = 0
  while i + m <= n {
    let mut j = 0
    let mut same = true
    while j < m {
      if hay[i + j] != needle[j] {
        same = false
        break
      }
      j = j + 1
    }
    if same {
      found = i
    }
    i = i + 1
  }
  found
}

///|
/// Readability-style title cleanup: drop a leading `[id]`, then a trailing
/// `| Site` or short `- Site` suffix.
fn clean_title(raw : String, site_name : String) -> String {
  let mut t = collapse_whitespace(raw)
  let site = site_name.to_lower()
  if site != "" && t.to_lower().has_prefix(site + " - ") {
    t = collapse_whitespace(t[site.length() + 3:t.length()].to_owned())
  }
  if t.has_prefix("[") {
    let close = str_find(t, "]")
    if close > 0 && close < 40 {
      t = collapse_whitespace(t[close + 1:t.length()].to_owned())
    }
  }
  for sep in [" | ", " · ", " — ", " – "] {
    let at = rfind_sub(t, sep)
    if at > 0 {
      let tail_len = t.length() - at - sep.length()
      if tail_len > 0 && tail_len <= 40 {
        t = collapse_whitespace(t[0:at].to_owned())
      }
    }
  }
  let dash = rfind_sub(t, " - ")
  if dash > 20 {
    let tail = t[dash + 3:t.length()].to_owned()
    if tail.length() <= 30 {
      t = collapse_whitespace(t[0:dash].to_owned())
    }
  }
  t
}

///|
/// Full stage: parse, read metadata, clean, score, prune, serialize.
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
    } else {
      host_of(url)
    }
  }
  clean(doc)
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
