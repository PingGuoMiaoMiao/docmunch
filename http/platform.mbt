// Documentation platform fingerprinting.
//
// Two passes: domain/path rules (cheap, works before fetch) and HTML markers
// (precise, works after fetch). The result drives extraction heuristics in P2.

///|
pub(all) enum Platform {
  GitHub
  GitLab
  MoonBit
  Docusaurus
  VitePress
  MkDocs
  Sphinx
  ReadTheDocs
  GitBook
  Hugo
  JupyterBook
  Confluence
  Notion
  Docsify
  Nextjs
  Generic
}

///|
pub fn Platform::name(self : Platform) -> String {
  match self {
    GitHub => "github"
    GitLab => "gitlab"
    MoonBit => "moonbit"
    Docusaurus => "docusaurus"
    VitePress => "vitepress"
    MkDocs => "mkdocs"
    Sphinx => "sphinx"
    ReadTheDocs => "readthedocs"
    GitBook => "gitbook"
    Hugo => "hugo"
    JupyterBook => "jupyter-book"
    Confluence => "confluence"
    Notion => "notion"
    Docsify => "docsify"
    Nextjs => "nextjs"
    Generic => "generic"
  }
}

///|
fn str_contains(hay : String, needle : String) -> Bool {
  let h = chars_of(hay)
  let n = chars_of(needle)
  if n.length() == 0 {
    return true
  }
  if n.length() > h.length() {
    return false
  }
  let mut i = 0
  while i + n.length() <= h.length() {
    let mut j = 0
    let mut same = true
    while j < n.length() {
      if h[i + j] != n[j] {
        same = false
        break
      }
      j = j + 1
    }
    if same {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn str_ends_with(s : String, suffix : String) -> Bool {
  let cs = chars_of(s)
  let ss = chars_of(suffix)
  if ss.length() > cs.length() {
    return false
  }
  let off = cs.length() - ss.length()
  let mut j = 0
  while j < ss.length() {
    if cs[off + j] != ss[j] {
      return false
    }
    j = j + 1
  }
  true
}

///|
/// Domain and path rules. Only high-confidence platforms are returned here.
pub fn detect_from_url(t : Target) -> Platform {
  let host = t.host().to_lower()
  let path = t.url.pathname().to_lower()
  if host == "github.com" {
    Platform::GitHub
  } else if host == "gitlab.com" {
    Platform::GitLab
  } else if str_ends_with(host, "moonbitlang.cn") ||
    str_ends_with(host, "moonbitlang.com") {
    Platform::MoonBit
  } else if str_ends_with(host, ".readthedocs.io") || host == "readthedocs.org" {
    Platform::ReadTheDocs
  } else if str_ends_with(host, ".gitbook.io") || str_contains(path, "gitbook") {
    Platform::GitBook
  } else if str_ends_with(host, ".notion.site") {
    Platform::Notion
  } else if str_ends_with(host, ".atlassian.net") {
    Platform::Confluence
  } else {
    Platform::Generic
  }
}

///|
/// Marker scan over the raw HTML. Order matters: the most specific marker wins.
pub fn detect_from_html(html : String) -> Platform? {
  let h = if html.length() > 200_000 {
    html[0:200_000].to_owned()
  } else {
    html
  }
  let low = h.to_lower()
  if str_contains(low, "docsify") {
    Some(Platform::Docsify)
  } else if str_contains(low, "vitepress") || str_contains(h, "__VP_HASH_MAP__") {
    Some(Platform::VitePress)
  } else if str_contains(low, "docusaurus") {
    Some(Platform::Docusaurus)
  } else if str_contains(low, "mkdocs") {
    Some(Platform::MkDocs)
  } else if str_contains(low, "sphinx") {
    Some(Platform::Sphinx)
  } else if str_contains(low, "readthedocs") {
    Some(Platform::ReadTheDocs)
  } else if str_contains(low, "gitbook") {
    Some(Platform::GitBook)
  } else if str_contains(low, "confluence") {
    Some(Platform::Confluence)
  } else if str_contains(low, "notion") {
    Some(Platform::Notion)
  } else if str_contains(low, "jupyter") {
    Some(Platform::JupyterBook)
  } else if str_contains(low, "hugo") {
    Some(Platform::Hugo)
  } else if str_contains(h, "__NEXT_DATA__") {
    Some(Platform::Nextjs)
  } else {
    None
  }
}

///|
/// Combine both passes: strong URL signals win, otherwise trust the markup.
pub fn detect(t : Target, html : String) -> Platform {
  match detect_from_url(t) {
    Platform::Generic =>
      match detect_from_html(html) {
        Some(p) => p
        None => Platform::Generic
      }
    other => other
  }
}
