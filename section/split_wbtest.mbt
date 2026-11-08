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
test "non-ascii heading gets a stable hash slug" {
  let sections = split_document("local/x", "doc.md", "# 中文标题\n")
  assert_eq(sections.length(), 1)
  assert_true(sections[0].id.has_prefix("local/x::doc.md::h"))
  assert_eq(sections[0].id.length(), "local/x::doc.md::h".length() + 8 + 2)
  let again = split_document("local/x", "doc.md", "# 中文标题\n")
  assert_eq(sections[0].id, again[0].id)
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

///|
test "headings inside fenced code blocks are ignored" {
  let text = "# A\n```\n# not a heading\n```\n## B\n"
  let sections = split_document("local/x", "doc.md", text)
  assert_eq(sections.length(), 2)
  assert_eq(sections[1].title, "B")
}

///|
test "setext headings become level 1 and 2" {
  let text = "Title\n=====\n\nbody\n\nSub\n---\n"
  let sections = split_document("local/x", "doc.md", text)
  assert_eq(sections.length(), 2)
  assert_eq(sections[0].level, 1)
  assert_eq(sections[0].title, "Title")
  assert_eq(sections[1].level, 2)
  assert_eq(sections[1].title, "Sub")
}

///|
test "yaml frontmatter does not produce fake headings" {
  let text = "---\ntitle: x\ntags: [a, b]\n---\n\n# Real\n"
  let sections = split_document("local/x", "doc.md", text)
  assert_eq(sections.length(), 2)
  assert_eq(sections[0].level, 0)
  assert_eq(sections[0].title, "")
  assert_eq(sections[1].title, "Real")
  for s in sections {
    assert_false(s.title.contains("tags"))
  }
  // preamble + first section cover every byte with no gaps.
  assert_eq(sections[0].byte_start, 0)
  assert_eq(sections[0].byte_end, sections[1].byte_start)
  assert_eq(sections[1].byte_end, @core.utf8_len(text))
}

///|
test "frontmatter after a BOM is still skipped" {
  let text = "\u{FEFF}---\ntitle: x\n---\n# A\n"
  let sections = split_document("local/x", "doc.md", text)
  assert_eq(sections.length(), 2)
  assert_eq(sections[0].level, 0)
  assert_eq(sections[1].title, "A")
  assert_eq(sections[0].byte_end, sections[1].byte_start)
  assert_eq(sections[1].byte_end, @core.utf8_len(text))
}

///|
test "unclosed frontmatter falls back to plain text" {
  let text = "---\ntitle: x\n# A\n"
  let sections = split_document("local/x", "doc.md", text)
  assert_eq(sections.length(), 2)
  assert_eq(sections[0].level, 0)
  assert_eq(sections[1].title, "A")
}

///|
test "byte offsets stay correct with CJK text" {
  let text = "# 中文\n\n内容\n\n## 下一节\n"
  let sections = split_document("local/x", "doc.md", text)
  assert_eq(sections.length(), 2)
  assert_eq(sections[0].byte_start, 0)
  assert_eq(sections[1].byte_start, 18)
  assert_eq(section_text(text, sections[0]), "# 中文\n\n内容\n\n")
}

///|
test "every section carries a stable sha256 of its bytes" {
  let text = "# A\n\ntext\n## B\nmore\n"
  let sections = split_document("local/x", "doc.md", text)
  assert_eq(sections.length(), 2)
  for s in sections {
    assert_eq(s.content_hash.length(), 64)
    assert_eq(s.content_hash, sha256_of(section_text(text, s)))
  }
  let again = split_document("local/x", "doc.md", text)
  assert_eq(sections[0].content_hash, again[0].content_hash)
}
