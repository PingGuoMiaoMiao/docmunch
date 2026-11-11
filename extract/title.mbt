// Title and metadata cleanup.

///|
fn host_of(url : String) -> String {
  let mut start = 0
  let scheme_end = @text.find_sub(url, "://")
  if scheme_end >= 0 {
    start = scheme_end + 3
  }
  let mut end = url.length()
  let mut i = start
  while i < url.length() {
    let c = url[i].to_int()
    if c == 47 || c == 63 || c == 35 {
      end = i
      break
    }
    i = i + 1
  }
  if end <= start {
    ""
  } else {
    url[start:end].to_owned()
  }
}

///|
fn clean_title(raw : String, site_name : String) -> String {
  let mut t = collapse_whitespace(raw)
  let site = site_name.to_lower()
  if site != "" && t.to_lower().has_prefix(site + " - ") {
    t = collapse_whitespace(t[site.length() + 3:t.length()].to_owned())
  }
  if t.has_prefix("[") {
    let close = @text.find_sub(t, "]")
    if close > 0 && close < 40 {
      t = collapse_whitespace(t[close + 1:t.length()].to_owned())
    }
  }
  for sep in [" | ", " · ", " — ", " – "] {
    let at = @text.rfind_sub(t, sep)
    if at > 0 {
      let tail_len = t.length() - at - sep.length()
      if tail_len > 0 && tail_len <= 40 {
        t = collapse_whitespace(t[0:at].to_owned())
      }
    }
  }
  let dash = @text.rfind_sub(t, " - ")
  if dash > 20 {
    let tail = t[dash + 3:t.length()].to_owned()
    if tail.length() <= 30 {
      t = collapse_whitespace(t[0:dash].to_owned())
    }
  }
  t
}

///|
