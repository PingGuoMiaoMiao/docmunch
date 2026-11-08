///|
fn sample_page() -> String {
  (
    #|<html lang="en">
    #|<head>
    #|  <title>Understanding Chunking | Example Docs</title>
    #|  <meta name="author" content="A. Writer">
    #|  <meta property="og:site_name" content="Example Docs">
    #|  <style>.x{color:red}</style>
    #|</head>
    #|<body>
    #|  <nav class="site-menu"><a href="/a">Home</a><a href="/b">Guide</a></nav>
    #|  <div class="page">
    #|    <h1>Understanding Chunking</h1>
    #|    <div class="article-content">
    #|      <p>Chunking splits a document into sections, keeps context, and makes retrieval cheap.</p>
    #|      <p>Heading-aware splitting preserves the author's hierarchy, which matters for long manuals.</p>
    #|      <div class="share-buttons">share on social</div>
    #|    </div>
    #|  </div>
    #|  <footer>copyright</footer>
    #|  <script>console.log("noise")</script>
    #|</body>
    #|</html>
  )
}

///|
test "extract keeps article, drops nav/footer/share/script" {
  let ex = extract(sample_page(), "https://example.com/docs/chunking")
  assert_true(ex.text.contains("Chunking splits a document"))
  assert_true(ex.text.contains("Heading-aware splitting"))
  assert_false(ex.text.contains("Home"))
  assert_false(ex.text.contains("copyright"))
  assert_false(ex.text.contains("share on social"))
  assert_false(ex.text.contains("noise"))
}

///|
test "extract reads metadata" {
  let ex = extract(sample_page(), "https://example.com/docs/chunking")
  assert_eq(ex.title, "Understanding Chunking")
  assert_eq(ex.byline, "A. Writer")
  assert_eq(ex.site_name, "Example Docs")
  assert_eq(ex.lang, "en")
}

///|
test "title cleanup drops separators and id prefixes" {
  let ex = extract(
    "<html><head><title>[2509.11552] A Paper | arXiv</title></head><body><p>body text long enough to keep, with commas.</p></body></html>",
    "https://arxiv.org/abs/2509.11552",
  )
  assert_eq(ex.title, "A Paper")
}

///|
test "local path input has no site name" {
  let page = "<html><body><p>body text long enough to keep, with commas.</p></body></html>"
  assert_eq(extract(page, "docs/page.html").site_name, "")
  assert_eq(extract(page, "D:\\docs\\page.html").site_name, "")
  assert_eq(extract(page, "https://example.com/x").site_name, "example.com")
}

///|
test "empty body does not panic" {
  let ex = extract("<html><body></body></html>", "https://example.com/")
  assert_eq(ex.length, 0)
  assert_eq(ex.text, "")
}

///|
test "shallow article directly under body terminates" {
  // Regression: the candidate container was already a child of <body>, the
  // collapse loop walked to the document node and then unwrapped it forever.
  let ex = extract(
    "<html><body><article><h1>Title</h1><p>This is a long enough paragraph, with commas, to score as content.</p></article></body></html>",
    "https://example.com/x",
  )
  assert_true(ex.text.contains("long enough paragraph"))
  assert_eq(ex.title, "Title")
}

///|
test "body-level paragraph candidate terminates" {
  let ex = extract(
    "<html><body><p>Only one paragraph here, still with commas, long enough to score.</p></body></html>",
    "https://example.com/y",
  )
  assert_true(ex.text.contains("Only one paragraph"))
}
