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
  let sections = @section.split_document(repo, doc_path, text)
  let existing = load_index(root, repo)
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
  index
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
