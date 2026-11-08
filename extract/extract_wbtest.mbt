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
test "empty body does not panic" {
  let ex = extract("<html><body></body></html>", "https://example.com/")
  assert_eq(ex.length, 0)
  assert_eq(ex.text, "")
}
