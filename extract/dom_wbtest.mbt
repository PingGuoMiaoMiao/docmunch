///|
test "clean removes header/nav subtrees" {
  let doc = @html.parse(
    "<html><body><div class=\"site-header\">menu</div><div class=\"content\"><p>this is a real paragraph with, commas, and enough text to score.</p></div></body></html>",
  )
  let before = body_inner_html(doc)
  assert_true(before.contains("site-header"))
  clean(doc)
  let after = body_inner_html(doc)
  assert_false(after.contains("site-header"))
  assert_true(after.contains("real paragraph"))
}

///|
test "collect_elements walks the body" {
  let doc = @html.parse("<html><body><div><p>a</p><p>b</p></div></body></html>")
  let ids = collect_elements(doc, body_id(doc))
  assert_eq(ids.length(), 3)
}

///|
test "body_inner_html strips wrappers" {
  let doc = @html.parse(
    "<html><head><title>t</title></head><body><p>hi</p></body></html>",
  )
  let inner = body_inner_html(doc)
  assert_true(inner.contains("<p>"))
  assert_false(inner.contains("<body"))
  assert_false(inner.contains("<title>"))
}
