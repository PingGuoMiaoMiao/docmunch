///|
test "find_sub finds the first match" {
  assert_eq(find_sub("hello world", "world"), 6)
  assert_eq(find_sub("aaa", "a"), 0)
  assert_eq(find_sub("hello", "l"), 2)
}

///|
test "find_sub reports absence and edge cases" {
  assert_eq(find_sub("hello", "zz"), -1)
  assert_eq(find_sub("hello", ""), -1)
  assert_eq(find_sub("hi", "hello"), -1)
  assert_eq(find_sub("", "a"), -1)
}

///|
test "find_sub honours the from offset" {
  assert_eq(find_sub("aaa", "a", from=1), 1)
  assert_eq(find_sub("aaa", "a", from=2), 2)
  assert_eq(find_sub("aaa", "a", from=3), -1)
  assert_eq(find_sub("abc", "b", from=-5), 1)
}

///|
test "rfind_sub returns the last match" {
  assert_eq(rfind_sub("a.b.c", "."), 3)
  assert_eq(rfind_sub("abc", "."), -1)
  assert_eq(rfind_sub("abc", ""), -1)
}

///|
test "split_lines handles the common shapes" {
  assert_eq(split_lines("a\nb\nc").length(), 3)
  assert_eq(split_lines("a\nb\nc")[1], "b")
  // A trailing newline does not add an empty element.
  assert_eq(split_lines("a\nb\n").length(), 2)
  assert_eq(split_lines("").length(), 0)
  assert_eq(split_lines("only").length(), 1)
}

///|
test "split_lines strips CR so CRLF input behaves like LF" {
  let lines = split_lines("a\r\nb\r\n")
  assert_eq(lines.length(), 2)
  assert_eq(lines[0], "a")
  assert_eq(lines[1], "b")
}

///|
test "split_lines keeps interior empty lines" {
  let lines = split_lines("a\n\nb")
  assert_eq(lines.length(), 3)
  assert_eq(lines[1], "")
}