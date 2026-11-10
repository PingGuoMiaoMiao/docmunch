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

///|
async test "repo label with spaces round-trips through list and delete" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  ignore(build_index(root, "my repo", "guide.md", sample_md()))
  let repos = list_repos(root)
  assert_eq(repos.length(), 1)
  assert_eq(repos[0], "my repo")
  assert_true(load_index(root, "my repo") is Some(_))
  delete_repo(root, "my repo")
  let after = list_repos(root)
  assert_eq(after.length(), 0)
  // Deleting an unindexed repo is idempotent, not an error.
  delete_repo(root, "my repo")
  assert_eq(list_repos(root).length(), 0)
}

///|
async test "space and underscore repo names stay distinct" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  // Safe names are used verbatim; rewritten names gain a digest suffix.
  assert_eq(repo_key("a_b"), "a_b")
  assert_true(repo_key("a b").has_prefix("a_b-"))
  ignore(build_index(root, "a b", "one.md", sample_md()))
  ignore(build_index(root, "a_b", "two.md", sample_md()))
  assert_true(repo_dir(root, "a b") != repo_dir(root, "a_b"))
  assert_true(load_index(root, "a b") is Some(_))
  assert_true(load_index(root, "a_b") is Some(_))
  let repos = list_repos(root)
  assert_eq(repos.length(), 2)
  let mut saw_space = false
  let mut saw_underscore = false
  for r in repos {
    if r == "a b" {
      saw_space = true
    }
    if r == "a_b" {
      saw_underscore = true
    }
  }
  assert_true(saw_space)
  assert_true(saw_underscore)
}

///|
async test "dot-dot repo name never escapes the root" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  // ".", ".." and "" are never emitted as directory names.
  assert_true(repo_key("..").has_prefix("repo-"))
  assert_true(repo_key(".").has_prefix("repo-"))
  assert_true(repo_key("").has_prefix("repo-"))
  let dir = repo_dir(root, "..")
  assert_true(dir.has_prefix(root + "/"))
  ignore(build_index(root, "..", "guide.md", sample_md()))
  assert_true(load_index(root, "..") is Some(_))
  let repos = list_repos(root)
  assert_eq(repos.length(), 1)
  assert_eq(repos[0], "..")
}

///|
async test "windows-hostile repo names get distinct directories" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  // "foo." collapses to "foo" on Windows; "Repo"/"repo" collide case-insensitively.
  ignore(build_index(root, "foo", "a.md", sample_md()))
  ignore(build_index(root, "foo.", "a.md", sample_md()))
  ignore(build_index(root, "Repo", "a.md", sample_md()))
  let repos = list_repos(root)
  assert_eq(repos.length(), 3)
  assert_true(repos.contains("foo"))
  assert_true(repos.contains("foo."))
  assert_true(repos.contains("Repo"))
}

///|
async test "reserved device names still work" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  ignore(build_index(root, "CON", "a.md", sample_md()))
  let repos = list_repos(root)
  assert_true(repos.contains("CON"))
  delete_repo(root, "CON")
  assert_eq(list_repos(root).length(), 0)
}
