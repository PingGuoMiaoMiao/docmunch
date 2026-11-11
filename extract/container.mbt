// Container selection: trim the tree down to the winning article block.
///|
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
  let document_root = doc.document_element
  // Candidate already sits directly under <body>: nothing to collapse. Without
  // this guard the collapse loop walks up to the document node, prunes every
  // body child and then unwraps the document node forever.
  if parent == root {
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
    if p < 0 || p == body || p == document_root {
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
    if p < 0 || p == body || p == document_root {
      break
    }
    unwrap_node(doc, p)
  }
  parent
}

///|
/// Bottom-up link text length per node: a link's whole subtree counts as link
