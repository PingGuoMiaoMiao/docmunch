///|
test "slugify basic" {
  assert_eq(slugify("Quick Start"), "quick-start")
  assert_eq(slugify("  Installation  "), "installation")
  assert_eq(slugify("API v2.0 (beta)"), "api-v2-0-beta")
  assert_eq(slugify("!!!"), "")
}

///|
test "utf8 length" {
  assert_eq(utf8_len("abc"), 3)
  assert_eq(utf8_len("中文"), 6)
  assert_eq(utf8_len("é"), 2)
  assert_eq(utf8_len(""), 0)
}

///|
test "section id shape" {
  let id = make_section_id("local/demo", "README.md", "quick-start", 2)
  assert_eq(id, "local/demo::README.md::quick-start#2")
}
