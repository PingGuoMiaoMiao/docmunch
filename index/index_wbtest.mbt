///|
fn sample_md() -> String {
  "# Guide\n\nintro text\n\n## Install\n\nrun it twice\n\n## Usage\n\nuse it well\n"
}

///|
async test "build, load, search and retrieve a section" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  let index = build_index(root, "local", "guide.md", sample_md())
  assert_eq(index.sections.length(), 3)
  let loaded = match load_index(root, "local") {
    Some(i) => i
    None => abort("index was not written")
  }
  assert_eq(loaded.sections.length(), 3)
  assert_eq(loaded.doc_paths.length(), 1)
  let hits = search(loaded, "install")
  assert_true(hits.length() >= 1)
  assert_eq(hits[0].title, "Install")
  let (text, ok) = get_section_text(
    root,
    "local",
    loaded,
    hits[0].id,
    verify=true,
  )
  assert_true(ok)
  assert_true(text.contains("run it twice"))
}

///|
async test "re-indexing the same document is idempotent" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  ignore(build_index(root, "local", "guide.md", sample_md()))
  let index = build_index(root, "local", "guide.md", sample_md())
  assert_eq(index.sections.length(), 3)
  assert_eq(index.doc_paths.length(), 1)
}

///|
async test "search ranks exact titles above path matches" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  let index = build_index(root, "local", "guide.md", sample_md())
  let hits = search(index, "usage")
  assert_eq(hits[0].title, "Usage")
}

///|
async test "missing repo loads as none" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  let loaded = load_index(root, "nope")
  assert_true(loaded is None)
}

///|
async test "search matches body keywords, not just titles" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  let index = build_index(root, "local", "guide.md", sample_md())
  let hits = search(index, "twice")
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].title, "Install")
}
