// Errors raised by the fetch stage. Every variant carries enough context to be
// actionable in an MCP tool response, and the variants are deliberately distinct
// so callers can tell "policy blocked it" from "the network broke".

///|
pub suberror FetchError {
  BadUrl(String)
  UnsupportedScheme(String)
  Blocked(String)
  DnsError(String)
  NetworkError(String)
  TooLarge(Int32)
  TooManyRedirects(Int32)
  Timeout
  UnsupportedContentType(String)
  CacheError(String)
}

///|
/// True only for failures that a second attempt can plausibly fix. Everything
/// else (bad URL, policy block, oversized body, timeout, cache trouble) is
/// deterministic-ish, so retrying it would just double the latency.
pub fn is_retryable(e : FetchError) -> Bool {
  match e {
    NetworkError(_) => true
    _ => false
  }
}

///|
pub fn FetchError::code(self : FetchError) -> String {
  match self {
    BadUrl(_) => "bad_url"
    UnsupportedScheme(_) => "unsupported_scheme"
    Blocked(_) => "blocked"
    DnsError(_) => "dns_error"
    NetworkError(_) => "network_error"
    TooLarge(_) => "too_large"
    TooManyRedirects(_) => "too_many_redirects"
    Timeout => "timeout"
    UnsupportedContentType(_) => "unsupported_content_type"
    CacheError(_) => "cache_error"
  }
}

///|
pub fn FetchError::message(self : FetchError) -> String {
  match self {
    BadUrl(u) => "invalid URL: \{u}"
    UnsupportedScheme(s) => "unsupported scheme: \{s}"
    Blocked(h) => "blocked private or reserved host: \{h}"
    DnsError(h) => "cannot resolve host: \{h}"
    NetworkError(m) => "network error: \{m}"
    TooLarge(n) => "response exceeds max_bytes (\{n})"
    TooManyRedirects(n) => "too many redirects (max \{n})"
    Timeout => "request timed out"
    UnsupportedContentType(t) => "unsupported content type: \{t}"
    CacheError(m) => "cache error: \{m}"
  }
}
