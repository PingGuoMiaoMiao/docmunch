///|
test "explicit utf-8 is decoded without warning" {
  let (text, warning) = decode_body(b"hello", "text/html; charset=utf-8")
  assert_eq(text, "hello")
  assert_false(warning)
}

///|
test "gbk label from the header transcodes chinese" {
  // "你好" in GBK: C4E3 BAC3
  let (text, warning) = decode_body(
    b"\xC4\xE3\xBA\xC3", "text/html; charset=gbk",
  )
  assert_eq(text, "你好")
  assert_false(warning)
}

///|
test "meta charset is sniffed when the header has none" {
  let body = b"<meta charset=gbk>" + b"\xC4\xE3\xBA\xC3"
  let (text, warning) = decode_body(body, "text/html")
  assert_true(text.contains("你好"))
  assert_false(warning)
}

///|
test "unknown label falls back to lossy utf-8 with a warning" {
  let (_, warning) = decode_body(b"\xC4\xE3", "text/html; charset=x-unknown")
  assert_true(warning)
}

///|
test "quoted charset label is accepted" {
  let (text, warning) = decode_body(
    b"\xC4\xE3\xBA\xC3", "text/html; charset=\"gbk\"",
  )
  assert_eq(text, "你好")
  assert_false(warning)
}
