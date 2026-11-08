// URL targets: scheme whitelist + WHATWG parsing + relative redirect resolution.
//
// Parsing is delegated to tonyfettes/url (WHATWG, 3700+ WPT vectors); this file
// only adds the docmunch policy layer on top.

///|
pub(all) enum Scheme {
  Http
  Https
}

///|
pub(all) struct Target {
  url : @url.Url
  scheme : Scheme
}

///|
pub fn Target::from_url(u : @url.Url) -> Target raise FetchError {
  match u.protocol() {
    "https:" => { url: u, scheme: Scheme::Https, }
    "http:" => { url: u, scheme: Scheme::Http, }
    other => raise UnsupportedScheme(other)
  }
}

///|
pub fn Target::parse(input : String) -> Target raise FetchError {
  let u = @url.Url::parse(input) catch { _ => raise BadUrl(input) }
  Target::from_url(u)
}

///|
pub fn Target::resolve(
  self : Target,
  location : String,
) -> Target raise FetchError {
  let u = @url.Url::parse(location, base=self.url) catch {
    _ => raise BadUrl(location)
  }
  Target::from_url(u)
}

///|
pub fn Target::href(self : Target) -> String {
  self.url.href()
}

///|
pub fn Target::host(self : Target) -> String {
  self.url.hostname()
}

///|
pub fn Target::path(self : Target) -> String {
  let p = self.url.pathname()
  let q = self.url.search()
  if q == "" {
    p
  } else {
    p + q
  }
}

///|
pub fn Target::default_port(self : Target) -> Int32 {
  match self.scheme {
    Scheme::Http => 80
    Scheme::Https => 443
  }
}

///|
pub fn Target::is_secure(self : Target) -> Bool {
  match self.scheme {
    Scheme::Http => false
    Scheme::Https => true
  }
}
