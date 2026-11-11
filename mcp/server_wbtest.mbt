// Unit tests for the MCP adapter's pure parts.
//
// The tool bodies themselves are covered end-to-end by tools/mcp_e2e.py and
// tools/mcp_http_e2e.py (they need a live server and a temp index). What can be
// tested without a socket is the argument handling, the schema shape and the
// failure envelope — those are exactly the places a silent typo would produce a
// wire-format bug.

///|
test "arg_str returns the value or empty string" {
  let args = @json.parse("{\"url\":\"https://example.com\",\"n\":3}") catch {
    _ => abort("bad json")
  }
  assert_eq(arg_str(args, "url"), "https://example.com")
  assert_eq(arg_str(args, "missing"), "")
  // Wrong JSON type must not throw, just fall back.
  assert_eq(arg_str(args, "n"), "")
  assert_eq(
    arg_str(@json.parse("null") catch { _ => abort("bad json") }, "url"),
    "",
  )
}

///|
test "arg_opt_str distinguishes absent from empty" {
  let args = @json.parse("{\"repo\":\"\",\"name\":\"x\"}") catch {
    _ => abort("bad json")
  }
  assert_eq(arg_opt_str(args, "name"), Some("x"))
  assert_eq(arg_opt_str(args, "repo"), Some(""))
  assert_true(arg_opt_str(args, "nope") is None)
}

///|
test "arg_int parses numbers and falls back" {
  let args = @json.parse("{\"limit\":25,\"flag\":true}") catch {
    _ => abort("bad json")
  }
  assert_eq(arg_int(args, "limit", 10), 25)
  assert_eq(arg_int(args, "missing", 10), 10)
  // A non-number falls back instead of raising.
  assert_eq(arg_int(args, "flag", 10), 10)
}

///|
test "arg_bool is true only for JSON true" {
  let args = @json.parse("{\"yes\":true,\"no\":false,\"str\":\"true\"}") catch {
    _ => abort("bad json")
  }
  assert_true(arg_bool(args, "yes"))
  assert_false(arg_bool(args, "no"))
  // The string "true" is not a boolean.
  assert_false(arg_bool(args, "str"))
  assert_false(arg_bool(args, "missing"))
}

///|
test "prop helpers emit a single property entry" {
  assert_eq(
    prop_str("repo", "Repo name."),
    "\"repo\":{\"type\":\"string\",\"description\":\"Repo name.\"}",
  )
  assert_eq(
    prop_int("limit", "Max hits."),
    "\"limit\":{\"type\":\"integer\",\"description\":\"Max hits.\"}",
  )
  assert_eq(
    prop_bool("verify", "Re-hash."),
    "\"verify\":{\"type\":\"boolean\",\"description\":\"Re-hash.\"}",
  )
}

///|
test "schema parses as an object schema with the given required list" {
  let s = schema(prop_str("repo", "Repo name."), "\"repo\"") catch {
    _ => abort("schema failed")
  }
  assert_true(s is Json::Object(_))
  let obj = match s {
    Json::Object(o) => o
    _ => abort("not an object")
  }
  assert_true(obj.get("type") is Some(Json::String("object")))
  match obj.get("properties") {
    Some(Json::Object(props)) => assert_true(props.get("repo") is Some(_))
    _ => abort("properties missing")
  }
  match obj.get("required") {
    Some(Json::Array(items)) => assert_eq(items.length(), 1)
    _ => abort("required missing")
  }
}

///|
test "empty schema covers the no-argument tool" {
  let s = schema("", "") catch { _ => abort("schema failed") }
  match s {
    Json::Object(obj) =>
      match obj.get("required") {
        Some(Json::Array(items)) => assert_eq(items.length(), 0)
        _ => abort("required missing")
      }
    _ => abort("not an object")
  }
}

///|
test "failure envelope is an error result with a text block" {
  let r = failure("repo not indexed: x")
  match r {
    Ok(result) => {
      assert_true(result.is_error is Some(true))
      assert_eq(result.content.length(), 1)
    }
    Err(_) => abort("failure must not raise")
  }
}
