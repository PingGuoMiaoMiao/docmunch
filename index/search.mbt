// Weighted section search over index metadata.
//
// Deliberately no embeddings (D11): the index carries titles and paths, so the
// score is explainable and reproducible. Content scoring would require reading
// the raw files, which is exactly what `get_section` is for.

///|
pub(all) struct SearchHit {
  id : String
  doc_path : String
  title : String
  level : Int32
  score : Int32
}

///|
fn is_word_char(c : Char) -> Bool {
  let n = c.to_int()
  (n >= 97 && n <= 122) ||
  (n >= 65 && n <= 90) ||
  (n >= 48 && n <= 57) ||
  n > 127
}

///|
pub fn words_of(text : String) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder::StringBuilder()
  for c in text {
    if is_word_char(c) {
      sb.write_char(c)
    } else if sb.to_string() != "" {
      out.push(sb.to_string().to_lower())
      sb.reset()
    }
  }
  if sb.to_string() != "" {
    out.push(sb.to_string().to_lower())
  }
  out
}

///|
fn count_occurrences(hay : String, needle : String) -> Int32 {
  if needle == "" {
    return 0
  }
  let n = hay.length()
  let m = needle.length()
  if m > n {
    return 0
  }
  let mut i = 0
  let mut hits = 0
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
      hits = hits + 1
    }
    i = i + 1
  }
  hits
}

///|
fn score_section(
  s : @core.Section,
  query : String,
  query_words : Array[String],
) -> Int32 {
  let title = s.title.to_lower()
  let path = s.doc_path.to_lower()
  let mut score = 0
  if title == query {
    score = score + 20
  } else if count_occurrences(title, query) > 0 {
    score = score + 10
  }
  let title_words = words_of(s.title)
  let mut body_hits = 0
  for word in query_words {
    if title_words.contains(word) {
      score = score + 5
    }
    if count_occurrences(path, word) > 0 {
      score = score + 2
    }
    if s.keywords.contains(word) {
      body_hits = body_hits + 1
    }
  }
  // Body keywords are weaker evidence than titles; cap their contribution.
  let body_cap = if body_hits > 5 { 5 } else { body_hits }
  score + body_cap
}

///|
pub fn search(
  index : @core.DocIndex,
  query : String,
  max_results? : Int32,
) -> Array[SearchHit] {
  let limit = match max_results {
    Some(n) => n
    None => 10
  }
  let q = query.trim().to_lower().to_owned()
  if q == "" {
    return []
  }
  let qwords = words_of(q)
  let hits : Array[SearchHit] = []
  for s in index.sections {
    let score = score_section(s, q, qwords)
    if score > 0 {
      hits.push({
        id: s.id,
        doc_path: s.doc_path,
        title: s.title,
        level: s.level,
        score,
      })
    }
  }
  // Insertion sort: indexes are small and this keeps ties in document order.
  for i = 1; i < hits.length(); i = i + 1 {
    let item = hits[i]
    let mut j = i - 1
    while j >= 0 && hits[j].score < item.score {
      hits[j + 1] = hits[j]
      j = j - 1
    }
    hits[j + 1] = item
  }
  if hits.length() > limit {
    let trimmed : Array[SearchHit] = []
    for i = 0; i < limit; i = i + 1 {
      trimmed.push(hits[i])
    }
    trimmed
  } else {
    hits
  }
}
