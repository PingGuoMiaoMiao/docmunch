///|
test "split two sections with byte offsets" {
  let text = "# A\n\ntext\n## B\nmore\n"
  let sections = split_document("local/x", "doc.md", text)
  assert_eq(sections.length(), 2)
  assert_eq(sections[0].id, "local/x::doc.md::a#1")
  assert_eq(sections[0].byte_start, 0)
  assert_eq(sections[0].byte_end, 10)
  assert_eq(sections[1].id, "local/x::doc.md::a/b#2")
  assert_eq(sections[1].parent_id, "local/x::doc.md::a#1")
  assert_eq(sections[1].byte_start, 10)
  assert_eq(sections[1].byte_end, 20)
}

///|
test "preamble becomes level 0" {
  let text = "intro\n# A\n"
  let sections = split_document("local/x", "doc.md", text)
  assert_eq(sections.length(), 2)
  assert_eq(sections[0].level, 0)
  assert_eq(sections[0].byte_start, 0)
  assert_eq(sections[0].byte_end, 6)
  assert_eq(sections[1].byte_start, 6)
}

///|
test "non-ascii heading falls back to positional slug" {
  let sections = split_document("local/x", "doc.md", "# 中文标题\n")
  assert_eq(sections.length(), 1)
  assert_eq(sections[0].id, "local/x::doc.md::sec0#1")
}

///|
test "duplicate sibling headings get suffixes" {
  let text = "# A\n## X\n## X\n"
  let sections = split_document("local/x", "doc.md", text)
  assert_eq(sections.length(), 3)
  assert_eq(sections[1].id, "local/x::doc.md::a/x#2")
  assert_eq(sections[2].id, "local/x::doc.md::a/x-2#2")
}

///|
test "hashes without space are not headings" {
  let sections = split_document("local/x", "doc.md", "#nope\n")
  assert_eq(sections.length(), 0)
}
