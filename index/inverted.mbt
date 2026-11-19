// Inverted index for BM25.
//
// `search_with_mode` scores every section on every query, which costs O(sections)
// per query regardless of how selective the query is. This module builds the
// postings once per loaded index (term -> (section, tf)) and answers a query
// from the postings of the query terms only, so repeat queries stop paying for
// the whole corpus.
//
// Fields keep the same weights as the scanning scorer (title 3 / path 2 / body 1)
// so results are identical, not merely similar; a test asserts that.

///|
/// One posting: section position plus the weighted term frequency in that section.
pub(all) struct Posting {
  section : Int32
  tf : Double
}

///|
pub(all) struct InvertedIndex {
  postings : Map[String, Array[Posting]]
  lengths : Array[Double]
  avg_len : Double
  total : Int32
}

///|
pub fn InvertedIndex::build(index : @core.DocIndex) -> InvertedIndex {
  let postings : Map[String, Array[Posting]] = Map([])
  let lengths : Array[Double] = []
  let mut total_len = 0.0
  let sections = index.sections
  for i = 0; i < sections.length(); i = i + 1 {
    let s = sections[i]
    let title_words = words_of(s.title)
    let path_words = words_of(s.doc_path)
    let mut len = s.tokens.to_double()
    len = len + title_words.length().to_double() * 3.0
    len = len + path_words.length().to_double()
    lengths.push(len)
    total_len = total_len + len
    // weighted tf: title 3, path 2, body 1
    let tf : Map[String, Double] = Map([])
    for w in title_words {
      let cur = match tf.get(w) {
        Some(v) => v
        None => 0.0
      }
      tf[w] = cur + 3.0
    }
    for w in path_words {
      let cur = match tf.get(w) {
        Some(v) => v
        None => 0.0
      }
      tf[w] = cur + 2.0
    }
    for w in s.terms {
      let cur = match tf.get(w) {
        Some(v) => v
        None => 0.0
      }
      tf[w] = cur + 1.0
    }
    for term, weight in tf {
      let list = match postings.get(term) {
        Some(v) => v
        None => []
      }
      list.push({ section: i, tf: weight, })
      postings[term] = list
    }
  }
  let n = sections.length()
  let avg = if n == 0 { 1.0 } else { (total_len / n.to_double()).max(1.0) }
  InvertedIndex::{ postings, lengths, avg_len: avg, total: n, }
}

///|
/// Same scoring as the scanning path, but only over sections that contain at
/// least one query term. Returns hits in the same order and with the same
/// integer scores as `search_with_mode`.
pub fn InvertedIndex::search(
  self : InvertedIndex,
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
  if qwords.length() == 0 {
    return []
  }
  let scores : Map[Int32, Double] = Map([])
  let k1 = 1.2
  let b = 0.75
  let n = self.total.to_double()
  for w in qwords {
    let list = match self.postings.get(w) {
      Some(v) => v
      None => continue
    }
    let df = list.length().to_double()
    let idf = @math.ln(1.0 + (n - df + 0.5) / (df + 0.5))
    for p in list {
      let len = self.lengths[p.section]
      let norm = 1.0 - b + b * len / self.avg_len
      let term_score = idf * (p.tf * (k1 + 1.0)) / (p.tf + k1 * norm)
      let cur = match scores.get(p.section) {
        Some(v) => v
        None => 0.0
      }
      scores[p.section] = cur + term_score
    }
  }
  let hits : Array[SearchHit] = []
  let sections = index.sections
  // Emit in document order so equal scores keep a stable tie-break, exactly like
  // the scanning scorer (Map iteration order must not leak into results).
  for i = 0; i < sections.length(); i = i + 1 {
    let raw = match scores.get(i) {
      Some(v) => v
      None => continue
    }
    let score = (raw * 100.0).to_int()
    if score > 0 {
      let s = sections[i]
      hits.push({
        id: s.id,
        doc_path: s.doc_path,
        title: s.title,
        level: s.level,
        score,
      })
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
