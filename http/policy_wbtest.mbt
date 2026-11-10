///|
test "private ipv4 ranges" {
  let private = [
    "0.0.0.0", "10.1.2.3", "127.0.0.1", "169.254.1.1", "172.16.0.1", "172.31.255.255",
    "192.168.1.1", "100.64.0.1", "198.18.0.1", "224.0.0.1", "255.255.255.255",
  ]
  for ip in private {
    assert_true(is_private_ipv4(ip))
  }
  let public = ["1.1.1.1", "8.8.8.8", "172.15.0.1", "172.32.0.1", "104.16.0.1"]
  for ip in public {
    assert_false(is_private_ipv4(ip))
  }
}

///|
test "private ipv6 and port stripping" {
  assert_true(is_private_ip("::1"))
  assert_true(is_private_ip("[::1]:443"))
  assert_true(is_private_ip("fe80::1"))
  assert_true(is_private_ip("fd00::1"))
  assert_true(is_private_ip("::ffff:127.0.0.1"))
  assert_false(is_private_ip("[2606:4700::1111]:443"))
  assert_eq(strip_port("1.2.3.4:8080"), "1.2.3.4")
  assert_eq(strip_port("[2606:4700::1111]:443"), "2606:4700::1111")
}

///|
test "private hostnames" {
  assert_true(is_private_host("localhost"))
  assert_true(is_private_host("foo.local"))
  assert_true(is_private_host("127.0.0.1"))
  assert_false(is_private_host("example.com"))
  // Domain names that merely start with a private-range prefix are not IPs.
  assert_false(is_private_host("10.example.com"))
  assert_false(is_private_host("192.168.example.com"))
  assert_true(is_private_host("10.1.2.3"))
  assert_true(is_private_host("192.168.1.1"))
  assert_true(is_private_host("fd00::1"))
}

///|
test "redirect policy" {
  let https_a = Target::parse("https://a.example/x") catch {
    _ => abort("parse failed")
  }
  let https_b = Target::parse("https://b.example/y") catch {
    _ => abort("parse failed")
  }
  let http_a = Target::parse("http://a.example/x") catch {
    _ => abort("parse failed")
  }
  assert_true(redirect_allowed(https_a, https_b, 1, 5))
  assert_false(redirect_allowed(https_a, http_a, 1, 5))
  assert_false(redirect_allowed(http_a, https_a, 6, 5))
  assert_false(redirect_allowed(http_a, http_a, 6, 5))
}

///|
test "content type allowlist" {
  assert_true(content_type_allowed("text/html; charset=utf-8"))
  assert_true(content_type_allowed("TEXT/HTML"))
  assert_true(content_type_allowed("text/plain"))
  assert_false(content_type_allowed("image/png"))
  assert_false(content_type_allowed("application/pdf"))
}

///|
test "target parsing rejects unsupported schemes" {
  let bad = try {
    ignore(Target::parse("ftp://example.com/x"))
    false
  } catch {
    UnsupportedScheme(_) => true
    _ => false
  }
  assert_true(bad)
  let bad_url = try {
    ignore(Target::parse("not a url"))
    false
  } catch {
    BadUrl(_) => true
    _ => false
  }
  assert_true(bad_url)
}

///|
test "relative redirect resolution" {
  let base = Target::parse("https://example.com/a/b/c") catch {
    _ => abort("parse failed")
  }
  let rel = base.resolve("../d") catch { _ => abort("resolve failed") }
  assert_eq(rel.href(), "https://example.com/a/d")
  let root = base.resolve("/root") catch { _ => abort("resolve failed") }
  assert_eq(root.href(), "https://example.com/root")
  let abs = base.resolve("https://other.example/x") catch {
    _ => abort("resolve failed")
  }
  assert_eq(abs.href(), "https://other.example/x")
}

///|
test "platform detection from url" {
  let cases = [
    ("https://github.com/mozilla/readability", Platform::GitHub),
    ("https://gitlab.com/a/b", Platform::GitLab),
    ("https://www.moonbitlang.cn/updates/", Platform::MoonBit),
    ("https://docs.moonbitlang.com/x", Platform::MoonBit),
    ("https://foo.readthedocs.io/en/latest/", Platform::ReadTheDocs),
    ("https://example.com/docs", Platform::Generic),
  ]
  for pair in cases {
    let (url, expected) = pair
    let t = Target::parse(url) catch { _ => abort("parse failed") }
    assert_eq(detect_from_url(t).name(), expected.name())
  }
}

///|
test "platform detection from html markers" {
  let cases = [
    ("<html><script src=\"/docsify.min.js\"></script>", Platform::Docsify),
    ("<div data-vp-hash-map=\"x\">vitepress</div>", Platform::VitePress),
    ("<html data-docusaurus>", Platform::Docusaurus),
    ("<meta name=\"generator\" content=\"mkdocs\">", Platform::MkDocs),
    ("<meta name=\"generator\" content=\"Sphinx\">", Platform::Sphinx),
    ("<script id=\"__NEXT_DATA__\"></script>", Platform::Nextjs),
  ]
  for pair in cases {
    let (html, expected) = pair
    assert_eq(
      detect_from_html(html).unwrap_or(Platform::Generic).name(),
      expected.name(),
    )
  }
  assert_eq(detect_from_html("<html><body>plain</body></html>") is None, true)
}

///|
test "rate limiter paces one host only" {
  let rl = RateLimiter::new(1000)
  assert_eq(rl.reserve("a.example", 0), 0)
  assert_eq(rl.reserve("a.example", 100), 900)
  assert_eq(rl.reserve("a.example", 2000), 0)
  assert_eq(rl.reserve("b.example", 100), 0)
}

///|
test "cache key is stable and url-specific" {
  let a = cache_key("https://example.com/x")
  let b = cache_key("https://example.com/x")
  let c = cache_key("https://example.com/y")
  assert_eq(a, b)
  assert_true(a != c)
  assert_eq(a.length(), 64)
}
