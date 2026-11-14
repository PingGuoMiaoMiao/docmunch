// Section keywords for body-aware search.
//
// We keep a small, deterministic keyword list per section instead of a full
// inverted index: the index stays compact, search stays explainable, and the
// raw document is never read during search (see ADR D35).
//
// Terms come from `core/text`'s tokenizer: ASCII words plus CJK bigrams, so a
// Chinese query can match a Chinese section without a segmentation model (D54).

///|
/// Index terms for `text`: ASCII words plus CJK bigrams, shared with the query
/// side so both sides speak the same vocabulary (D54).
fn ascii_words(text : String) -> Array[String] {
  @text.tokenize(text)
}

///|
let stopwords : Array[String] = [
  "the", "and", "for", "with", "that", "this", "from", "are", "was", "were", "have",
  "has", "had", "not", "but", "you", "your", "can", "will", "all", "any", "our",
  "out", "use", "using", "used", "into", "when", "then", "than", "them", "they",
  "their", "its", "also", "may", "more", "most", "such", "only", "other", "these",
  "those", "which", "while", "what", "how", "why", "who", "per", "via", "etc", "one",
  "two", "see", "new", "get", "set", "over", "under", "about", "there", "here", "where",
  "been", "being", "does", "did", "done", "each", "both", "after", "before", "between",
  "through",
]

///|
/// True for tokens worth indexing: ASCII words need 3+ characters to avoid
/// noise, but CJK bigrams are 2 characters by construction and must survive
/// that filter (D54).
fn is_usable_term(w : String) -> Bool {
  if w.length() >= 3 {
    return true
  }
  for c in w {
    if c.to_int() > 127 {
      return true
    }
  }
  false
}

///|
fn is_stopword(w : String) -> Bool {
  stopwords.contains(w)
}

///|
/// Most frequent non-stopword terms in `text`, capped at `max_count` (default 20).
/// Order is deterministic: descending frequency, then first appearance.
pub fn extract_keywords(text : String, max_count? : Int32) -> Array[String] {
  let limit = match max_count {
    Some(n) => n
    None => 20
  }
  let order : Array[String] = []
  let counts : Map[String, Int32] = Map([])
  for w in ascii_words(text) {
    if !is_usable_term(w) || is_stopword(w) {
      continue
    }
    let n = match counts.get(w) {
      Some(v) => v
      None => 0
    }
    if n == 0 {
      order.push(w)
    }
    counts[w] = n + 1
  }
  let pairs : Array[(String, Int32)] = []
  for w in order {
    let n = match counts.get(w) {
      Some(v) => v
      None => 0
    }
    pairs.push((w, n))
  }
  // Stable insertion sort: higher count first, ties keep first-appearance order.
  for i = 1; i < pairs.length(); i = i + 1 {
    let item = pairs[i]
    let mut j = i - 1
    while j >= 0 && pairs[j].1 < item.1 {
      pairs[j + 1] = pairs[j]
      j = j - 1
    }
    pairs[j + 1] = item
  }
  let out : Array[String] = []
  let take = if pairs.length() < limit { pairs.length() } else { limit }
  for i = 0; i < take; i = i + 1 {
    out.push(pairs[i].0)
  }
  out
}

///|
/// Term frequencies for BM25: the first `max_terms` most frequent terms, each
/// repeated `min(count, cap)` times, plus the total number of qualifying tokens
/// (used for length normalisation).
///
/// The list stays an `Array[String]` on purpose: it derives to JSON without a
/// custom codec, and repeats give us `tf` without a second field.
pub fn term_stats(text : String, max_terms? : Int32) -> (Array[String], Int32) {
  let limit = match max_terms {
    Some(n) => n
    None => 40
  }
  let order : Array[String] = []
  let counts : Map[String, Int32] = Map([])
  let mut total = 0
  for w in ascii_words(text) {
    if !is_usable_term(w) || is_stopword(w) {
      continue
    }
    total = total + 1
    let n = match counts.get(w) {
      Some(v) => v
      None => 0
    }
    if n == 0 {
      order.push(w)
    }
    counts[w] = n + 1
  }
  let pairs : Array[(String, Int32)] = []
  for w in order {
    let n = match counts.get(w) {
      Some(v) => v
      None => 0
    }
    pairs.push((w, n))
  }
  for i = 1; i < pairs.length(); i = i + 1 {
    let item = pairs[i]
    let mut j = i - 1
    while j >= 0 && pairs[j].1 < item.1 {
      pairs[j + 1] = pairs[j]
      j = j - 1
    }
    pairs[j + 1] = item
  }
  let out : Array[String] = []
  let take = if pairs.length() < limit { pairs.length() } else { limit }
  for i = 0; i < take; i = i + 1 {
    let (word, count) = pairs[i]
    let repeat = if count > 8 { 8 } else { count }
    for _k = 0; _k < repeat; _k = _k + 1 {
      out.push(word)
    }
  }
  (out, total)
}
