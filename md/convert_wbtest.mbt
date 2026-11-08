///|
test "headings, paragraphs and emphasis" {
  let md = html_to_markdown(
    "<h1>Title</h1><p>Hello <strong>bold</strong> and <em>italic</em>.</p><h2>Sub</h2>",
  )
  assert_eq(md, "# Title\n\nHello **bold** and *italic*.\n\n## Sub\n")
}

///|
test "unordered and ordered lists" {
  let md = html_to_markdown(
    "<ul><li>one</li><li>two</li></ul><ol><li>first</li><li>second</li></ol>",
  )
  assert_eq(md, "- one\n- two\n\n1. first\n2. second\n")
}

///|
test "code block keeps whitespace and language" {
  let md = html_to_markdown(
    "<pre class=\"language-mbt\"><code>fn main {\n  println(\"hi\")\n}</code></pre>",
  )
  assert_true(md.contains("```mbt"))
  assert_true(md.contains("  println(\"hi\")"))
}

///|
test "blank lines inside fenced code blocks are preserved" {
  let md = html_to_markdown("<pre>line1\n\n\nline2</pre>")
  assert_true(md.contains("line1\n\n\nline2"))
  assert_eq(md, "```\nline1\n\n\nline2\n```\n")
}

///|
test "squash keeps tilde-fenced blocks and collapses outside blanks" {
  assert_eq(squash_blank_lines("~~~\na\n\n\nb\n~~~\n"), "~~~\na\n\n\nb\n~~~\n")
  assert_eq(squash_blank_lines("a\n\n\n\nb\n"), "a\n\nb\n")
}

///|
test "table becomes a pipe table" {
  let md = html_to_markdown(
    "<table><tr><th>Name</th><th>Type</th></tr><tr><td>a</td><td>int</td></tr></table>",
  )
  assert_eq(md, "| Name | Type |\n| --- | --- |\n| a | int |\n")
}

///|
test "links keep href, anchors are unwrapped" {
  let md = html_to_markdown(
    "<p>See <a href=\"https://example.com/x\">docs</a> and <a href=\"#top\">top</a>.</p>",
  )
  assert_true(md.contains("[docs](https://example.com/x)"))
  assert_true(md.contains("and top."))
}

///|
test "blockquote is prefixed" {
  let md = html_to_markdown("<blockquote><p>quoted line</p></blockquote>")
  assert_eq(md, "> quoted line\n")
}

///|
test "output parses back through cmark" {
  let md = html_to_markdown(
    "<h1>T</h1><p>Hello <strong>w</strong> and <a href=\"https://e.com\">l</a>.</p><ul><li>a</li></ul>",
  )
  let html = @cmark_html.render(md) catch {
    _ => abort("cmark failed to parse generated markdown")
  }
  assert_true(html.contains("<h1>"))
  assert_true(html.contains("<strong>"))
  assert_true(html.contains("<ul>"))
  assert_true(html.contains("href=\"https://e.com\""))
}

///|
test "relative links are absolutized against the page url" {
  let md = html_to_markdown(
    "<p><a href=\"/docs/x\">rel</a> <a href=\"next.html\">next</a></p>",
    base_url="https://example.com/guide/intro.html",
  )
  assert_true(md.contains("(https://example.com/docs/x)"))
  assert_true(md.contains("(https://example.com/guide/next.html)"))
}
