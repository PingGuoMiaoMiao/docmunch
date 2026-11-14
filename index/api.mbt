// High-level index operations: build, merge, look up, retrieve.

///|
/// Index one document under `repo`. Replaces any previous entry for the same
/// `doc_path`, so re-indexing is idempotent.
pub async fn build_index(
  root : String,
  repo : String,
  doc_path : String,
  text : String,
) -> @core.DocIndex {
  let (index, _changed) = build_index_checked(root, repo, doc_path, text)
  index
}

///|
/// Same as `build_index`, but also reports whether anything was re-parsed.
///
/// A document whose bytes are unchanged does not get re-split: the raw cache is
/// the exact text the offsets point into, so comparing its sha256 with the
/// incoming text is enough to prove the index is current (D51).
pub async fn build_index_checked(
  root : String,
  repo : String,
  doc_path : String,
  text : String,
) -> (@core.DocIndex, Bool) {
  let incoming = @section.sha256_of(text)
  let existing = load_index(root, repo)
  match existing {
    Some(index) =>
      if index.doc_paths.contains(doc_path) {
        let cached = read_document_text(root, repo, doc_path) catch { _ => "" }
        if cached != "" && @section.sha256_of(cached) == incoming {
          return (index, false)
        }
      }
    None => ()
  }
  let sections = @section.split_document(repo, doc_path, text)
  let merged : Array[@core.Section] = []
  let docs : Array[String] = []
  match existing {
    Some(index) => {
      for d in index.doc_paths {
        if d != doc_path {
          docs.push(d)
        }
      }
      for s in index.sections {
        if s.doc_path != doc_path {
          merged.push(s)
        }
      }
    }
    None => ()
  }
  docs.push(doc_path)
  for s in sections {
    merged.push(s)
  }
  docs.sort()
  write_raw(root, repo, doc_path, text)
  let index : @core.DocIndex = {
    repo,
    doc_paths: docs,
    sections: merged,
    index_version: @core.index_version,
  }
  save_index(root, repo, index)
  (index, true)
}

///|
pub fn section_by_id(index : @core.DocIndex, id : String) -> @core.Section? {
  for s in index.sections {
    if s.id == id {
      return Some(s)
    }
  }
  None
}

///|
/// Ancestors from root down to the immediate parent.
pub fn ancestors_of(
  index : @core.DocIndex,
  s : @core.Section,
) -> Array[@core.Section] {
  let chain : Array[@core.Section] = []
  let mut parent = s.parent_id
  while parent != "" {
    match section_by_id(index, parent) {
      Some(p) => {
        chain.insert(0, p)
        parent = p.parent_id
      }
      None => break
    }
  }
  chain
}

///|
pub fn children_of(
  index : @core.DocIndex,
  s : @core.Section,
) -> Array[@core.Section] {
  let out : Array[@core.Section] = []
  for other in index.sections {
    if other.parent_id == s.id {
      out.push(other)
    }
  }
  out
}

///|
/// Retrieve a section's bytes, optionally verifying the stored hash.
pub async fn get_section_text(
  root : String,
  repo : String,
  index : @core.DocIndex,
  id : String,
  verify? : Bool,
) -> (String, Bool) {
  match section_by_id(index, id) {
    None => ("", false)
    Some(s) => {
      let text = read_section_text(root, repo, s.doc_path, s)
      let ok = match verify {
        Some(true) => @section.sha256_of(text) == s.content_hash
        _ => true
      }
      (text, ok)
    }
  }
}

///|
/// Every descendant of `s`, depth-first in document order.
pub fn descendants_of(
  index : @core.DocIndex,
  s : @core.Section,
) -> Array[@core.Section] {
  let out : Array[@core.Section] = []
  let mut frontier = children_of(index, s)
  while frontier.length() > 0 {
    let next : Array[@core.Section] = []
    for child in frontier {
      out.push(child)
      for grandchild in children_of(index, child) {
        next.push(grandchild)
      }
    }
    frontier = next
  }
  out
}

///|
/// Sections whose title matches `query` (case-insensitive substring), with the
/// exact match ranked first. Titles are cheap, so this does not touch bodies.
pub fn search_titles(
  index : @core.DocIndex,
  query : String,
  limit? : Int32,
) -> Array[@core.Section] {
  let max = match limit {
    Some(n) => n
    None => 20
  }
  let q = query.trim().to_lower().to_owned()
  if q == "" {
    return []
  }
  let exact : Array[@core.Section] = []
  let partial : Array[@core.Section] = []
  for s in index.sections {
    let title = s.title.to_lower()
    if title == q {
      exact.push(s)
    } else if title.contains(q) {
      partial.push(s)
    }
  }
  let out : Array[@core.Section] = []
  for s in exact {
    if out.length() < max {
      out.push(s)
    }
  }
  for s in partial {
    if out.length() < max {
      out.push(s)
    }
  }
  out
}
