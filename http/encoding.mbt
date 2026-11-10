// Response body decoding with WHATWG charset labels.
//
// Pages served as GBK/Big5/Shift_JIS used to be decoded as lossy UTF-8, which
// silently stored mojibake in the index. We now honour the charset from the
// Content-Type header (or a <meta charset> in the first 1 KiB) and fall back to
// lossy UTF-8 only when the label is missing or unsupported (D45).

///|
fn token_after_charset(lowered : String) -> String {
  let marker = "charset="
  let at = find_substring(lowered, marker)
  if at < 0 {
    return ""
  }
  let mut i = at + marker.length()
  // Skip an optional opening quote: charset="gbk" / charset='gbk'.
  while i < lowered.length() {
    let c = lowered[i].to_int()
    if c == 34 || c == 39 {
      i = i + 1
    } else {
      break
    }
  }
  let sb = StringBuilder::StringBuilder()
  while i < lowered.length() {
    let c = lowered[i].to_int()
    if c == 59 || c == 32 || c == 9 || c == 34 || c == 39 || c == 62 || c == 44 {
      break
    }
    sb.write_char(Int32::unsafe_to_char(c))
    i = i + 1
  }
  sb.to_string()
}

///|
fn find_substring(hay : String, needle : String) -> Int32 {
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
fn head_text(bytes : Bytes, limit : Int32) -> String {
  let take = if bytes.length() < limit { bytes.length() } else { limit }
  @utf8.decode_lossy(bytes[0:take])
}

///|
/// Charset label from the Content-Type header, else from `<meta charset>` /
/// `<meta http-equiv=content-type>` in the first 1 KiB.
pub fn charset_label(content_type : String, bytes : Bytes) -> String {
  let from_header = token_after_charset(content_type.to_lower())
  if from_header != "" {
    return from_header
  }
  let head = head_text(bytes, 1024).to_lower()
  let from_meta = token_after_charset(head)
  from_meta
}

///|
/// Decode a response body. Returns `(text, charset_warning)`; the warning is set
/// when a declared label could not be used and we fell back to lossy UTF-8.
pub fn decode_body(bytes : Bytes, content_type : String) -> (String, Bool) {
  let label = charset_label(content_type, bytes)
  if label == "" || label == "utf-8" || label == "utf8" {
    return (@utf8.decode_lossy(bytes), false)
  }
  match @moon_encoding.decode(bytes, label) {
    Ok(text) => (text, false)
    Err(_) => (@utf8.decode_lossy(bytes), true)
  }
}
