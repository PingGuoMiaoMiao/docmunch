// Candidate scoring: paragraph weight propagated to ancestors (Readability-compatible).

///|
/// True when `needle` occurs in `hay`. Thin wrapper over the shared text
/// helper so this package does not carry a second substring scan.
pub fn str_contains_pub(hay : String, needle : String) -> Bool {
  @text.find_sub(hay, needle) >= 0
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
