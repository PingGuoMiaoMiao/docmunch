// Section search: BM25 by default, with the older weighted score kept as a mode.
//
// Both modes work off index metadata only — no raw file is read while searching,
// so a query costs the same whether the corpus is one page or a thousand (D50).
//
// BM25 scores three fields with fixed weights: title (3), path (2), body terms
// (1). `k1 = 1.2`, `b = 0.75`; both are the values the reference implementation
// ships as defaults.

///|
pub(all) struct SearchHit {
  id : String
  doc_path : String
  title : String
  level : Int32
  score : Int32
}

///|
pub(all) enum SearchMode {
  Bm25
  Weighted
}

///|
pub fn SearchMode::parse(raw : String) -> SearchMode {
  match raw.trim().to_lower() {
    "weighted" => SearchMode::Weighted
    _ => SearchMode::Bm25
  }
}

///|
/// Query/index terms: same tokenizer as the indexer, so CJK queries line up with
/// the stored bigrams (D54).
pub fn words_of(text : String) -> Array[String] {
  @text.tokenize(text)
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
fn count_in(items : Array[String], needle : String) -> Int32 {
  let mut hits = 0
  for item in items {
    if item == needle {
      hits = hits + 1
    }
  }
  hits
}

///|
/// Terms of one section with repeats collapsed to counts.
fn term_counts(s : @core.Section) -> Map[String, Int32] {
  let counts : Map[String, Int32] = Map([])
  for t in s.terms {
    let n = match counts.get(t) {
      Some(v) => v
      None => 0
    }
    counts[t] = n + 1
  }
  counts
}

///|
/// Document frequency of each query term across the corpus.
fn document_frequencies(
  index : @core.DocIndex,
  query_words : Array[String],
) -> Map[String, Int32] {
  let df : Map[String, Int32] = Map([])
  for s in index.sections {
    let title_words = words_of(s.title)
    let path_words = words_of(s.doc_path)
    let terms = term_counts(s)
    for w in query_words {
      let present = title_words.contains(w) ||
        path_words.contains(w) ||
        terms.get(w) is Some(_)
      if present {
        let n = match df.get(w) {
          Some(v) => v
          None => 0
        }
        df[w] = n + 1
      }
    }
  }
  df
}

///|
fn field_length(s : @core.Section) -> Int32 {
  let mut len = s.tokens
  len = len + words_of(s.title).length() * 3
  len = len + words_of(s.doc_path).length()
  len
}

///|
fn bm25_term(
  idf : Double,
  tf : Double,
  k1 : Double,
  b : Double,
  len : Double,
  avg_len : Double,
) -> Double {
  let norm = 1.0 - b + b * len / avg_len
  idf * (tf * (k1 + 1.0)) / (tf + k1 * norm)
}

///|
fn score_bm25(
  s : @core.Section,
  index : @core.DocIndex,
  query_words : Array[String],
  df : Map[String, Int32],
  avg_len : Double,
) -> Double {
  let n = index.sections.length().to_double()
  let title_words = words_of(s.title)
  let path_words = words_of(s.doc_path)
  let terms = term_counts(s)
  let len = field_length(s).to_double()
  let k1 = 1.2
  let b = 0.75
  let mut total = 0.0
  for w in query_words {
    let term_df = match df.get(w) {
      Some(v) => v.to_double()
      None => 0.0
    }
    if term_df <= 0.0 {
      continue
    }
    let idf = @math.ln(1.0 + (n - term_df + 0.5) / (term_df + 0.5))
    let tf = count_in(title_words, w).to_double() * 3.0 +
      count_in(path_words, w).to_double() * 2.0 +
      (match terms.get(w) {
        Some(v) => v.to_double()
        None => 0.0
      })
    if tf > 0.0 {
      total = total + bm25_term(idf, tf, k1, b, len, avg_len)
    }
  }
  total
}

///|
fn score_weighted(
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
    if s.terms.contains(word) {
      body_hits = body_hits + 1
    }
  }
  let body_cap = if body_hits > 5 { 5 } else { body_hits }
  score + body_cap
}

///|
/// Stable descending sort by score, keeping document order for ties.
fn sort_hits(hits : Array[SearchHit]) -> Unit {
  for i = 1; i < hits.length(); i = i + 1 {
    let item = hits[i]
    let mut j = i - 1
    while j >= 0 && hits[j].score < item.score {
      hits[j + 1] = hits[j]
      j = j - 1
    }
    hits[j + 1] = item
  }
}

///|
pub fn search_with_mode(
  index : @core.DocIndex,
  query : String,
  mode : SearchMode,
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
  match mode {
    SearchMode::Weighted =>
      for s in index.sections {
        let score = score_weighted(s, q, qwords)
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
    SearchMode::Bm25 => {
      let df = document_frequencies(index, qwords)
      let mut total_len = 0
      for s in index.sections {
        total_len = total_len + field_length(s)
      }
      let avg_len = if index.sections.length() == 0 {
        1.0
      } else {
        (total_len.to_double() / index.sections.length().to_double()).max(1.0)
      }
      for s in index.sections {
        let raw = score_bm25(s, index, qwords, df, avg_len)
        // Scale to a readable integer; 1.0 of BM25 score ~ 100 points.
        let score = (raw * 100.0).to_int()
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
    }
  }
  sort_hits(hits)
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

///|
/// Default search: BM25.
pub fn search(
  index : @core.DocIndex,
  query : String,
  max_results? : Int32,
) -> Array[SearchHit] {
  search_with_mode(index, query, SearchMode::Bm25, max_results?)
}
