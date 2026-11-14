// Tokenizer shared by the indexer and the query side.
//
// ASCII runs become lowercased words. CJK runs have no spaces, so they are cut
// into overlapping bigrams (and a lone character stands for itself): that is
// the classic dictionary-free approach and it makes a Chinese query match a
// Chinese section without shipping a segmentation model (D54).

///|
fn is_cjk(c : Char) -> Bool {
  let n = c.to_int()
  (n >= 0x4E00 && n <= 0x9FFF) ||
  (n >= 0x3400 && n <= 0x4DBF) ||
  (n >= 0x3040 && n <= 0x30FF) ||
  (n >= 0xAC00 && n <= 0xD7AF) ||
  (n >= 0xF900 && n <= 0xFAFF)
}

///|
/// Unicode punctuation, CJK symbols and full-width forms act as separators.
/// Without this, "，" or "。" would be glued into words because they are
/// non-ASCII.
fn is_separator(c : Char) -> Bool {
  let n = c.to_int()
  (n >= 0x2000 && n <= 0x206F) ||
  (n >= 0x3000 && n <= 0x303F) ||
  (n >= 0xFF00 && n <= 0xFF0F) ||
  (n >= 0xFF1A && n <= 0xFF20) ||
  (n >= 0xFF3B && n <= 0xFF40) ||
  (n >= 0xFF5B && n <= 0xFF65) ||
  (n >= 0xFFE0 && n <= 0xFFEE)
}

///|
fn is_word_char(c : Char) -> Bool {
  let n = c.to_int()
  (n >= 97 && n <= 122) ||
  (n >= 65 && n <= 90) ||
  (n >= 48 && n <= 57) ||
  (n > 127 && !is_cjk(c) && !is_separator(c))
}

///|
fn push_cjk_run(run : Array[Char], out : Array[String]) -> Unit {
  if run.length() == 1 {
    let sb = StringBuilder::StringBuilder()
    sb.write_char(run[0])
    out.push(sb.to_string())
  } else {
    for i = 0; i + 1 < run.length(); i = i + 1 {
      let sb = StringBuilder::StringBuilder()
      sb.write_char(run[i])
      sb.write_char(run[i + 1])
      out.push(sb.to_string())
    }
  }
}

///|
/// Split `text` into index terms: lowercased ASCII words plus CJK bigrams.
pub fn tokenize(text : String) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder::StringBuilder()
  let cjk : Array[Char] = []
  for c in text {
    if is_cjk(c) {
      if sb.to_string() != "" {
        out.push(sb.to_string().to_lower())
        sb.reset()
      }
      cjk.push(c)
    } else if is_word_char(c) {
      if cjk.length() > 0 {
        push_cjk_run(cjk, out)
        cjk.clear()
      }
      sb.write_char(c)
    } else {
      if sb.to_string() != "" {
        out.push(sb.to_string().to_lower())
        sb.reset()
      }
      if cjk.length() > 0 {
        push_cjk_run(cjk, out)
        cjk.clear()
      }
    }
  }
  if sb.to_string() != "" {
    out.push(sb.to_string().to_lower())
  }
  if cjk.length() > 0 {
    push_cjk_run(cjk, out)
  }
  out
}
