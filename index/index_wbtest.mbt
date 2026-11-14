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

///|
async test "bm25 favours the rare term over the common one" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  let text =
    #|# Alpha
    #|
    #|alpha alpha alpha common common content here
    #|
    #|# Beta
    #|
    #|beta uncommon rarewording content here
    #|
    #|# Gamma
    #|
    #|gamma common common content here
  let index = build_index(root, "bm25", "doc.md", text)
  // "uncommon" appears once, in one section; "common" appears in two.
  let hits = search(index, "uncommon")
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].title, "Beta")
  let common_hits = search(index, "common")
  assert_eq(common_hits.length(), 2)
}

///|
async test "bm25 prefers the shorter section for the same term" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  let text =
    #|# Short
    #|
    #|deployment
    #|
    #|# Long
    #|
    #|deployment plus a great many other words that make this section much longer than the first one
  let index = build_index(root, "bm25", "doc.md", text)
  let hits = search(index, "deployment")
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].title, "Short")
}

///|
async test "weighted mode is still selectable" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  let index = build_index(root, "local", "guide.md", sample_md())
  let hits = search_with_mode(index, "usage", SearchMode::Weighted)
  assert_eq(hits[0].title, "Usage")
  let parsed = SearchMode::parse("weighted")
  assert_true(parsed is SearchMode::Weighted)
  assert_true(SearchMode::parse("bm25") is SearchMode::Bm25)
  assert_true(SearchMode::parse("") is SearchMode::Bm25)
}

///|
async test "descendants_of walks the whole subtree" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  let text = "# A\n\ntext\n## B\nmore\n### C\ndeep\n## D\nsibling\n"
  let index = build_index(root, "local", "doc.md", text)
  let a = match section_by_id(index, "local::doc.md::a#1") {
    Some(s) => s
    None => abort("section a missing")
  }
  let kids = descendants_of(index, a)
  assert_eq(kids.length(), 3)
  assert_eq(kids[0].title, "B")
}

///|
async test "search_titles puts the exact match first and ignores bodies" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  let text = "# Install\n\nrun it\n\n# Installation notes\n\nmore\n"
  let index = build_index(root, "local", "doc.md", text)
  let hits = search_titles(index, "install")
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].title, "Install")
  // A term that only exists in a body is not a title hit.
  assert_eq(search_titles(index, "more").length(), 0)
}

///|
async test "re-indexing unchanged bytes skips the re-parse" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  let text = "# A\n\nsame text\n\n## B\n\nmore\n"
  let (_, first) = build_index_checked(root, "inc", "doc.md", text)
  assert_true(first)
  let (index, second) = build_index_checked(root, "inc", "doc.md", text)
  assert_false(second)
  assert_eq(index.sections.length(), 2)
}

///|
async test "changed bytes are re-parsed" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  ignore(build_index_checked(root, "inc", "doc.md", "# A\n\none\n"))
  let (index, changed) = build_index_checked(
    root, "inc", "doc.md", "# A\n\none\n\n## B\n\ntwo\n",
  )
  assert_true(changed)
  assert_eq(index.sections.length(), 2)
}

///|
async test "collect_documents walks subdirectories and skips noise" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  @fs.mkdir(root + "/sub", recursive=true, allow_exist=true)
  @fs.mkdir(root + "/node_modules", recursive=true, allow_exist=true)
  @fs.write_file(root + "/a.md", "# A\n", create_mode=CreateOrTruncate)
  @fs.write_file(root + "/sub/b.html", "<p>x</p>", create_mode=CreateOrTruncate)
  @fs.write_file(root + "/sub/skip.txt", "no", create_mode=CreateOrTruncate)
  @fs.write_file(
    root + "/node_modules/c.md",
    "# C\n",
    create_mode=CreateOrTruncate,
  )
  let out : Array[String] = []
  collect_documents(root, "", out)
  assert_true(out.contains("a.md"))
  assert_true(out.contains("sub/b.html"))
  assert_false(out.contains("sub/skip.txt"))
  assert_false(out.contains("node_modules/c.md"))
}

///|
async test "chinese queries match chinese bodies" {
  let root = @fs.tmpdir(prefix="docmunch-test-")
  defer @fs.rmdir(root, recursive=true)
  let text = "# 语言更新\n\n本次更新了派生语法与类型重命名。\n\n## 工具链更新\n\n编译器性能提升。\n"
  let index = build_index(root, "cn", "doc.md", text)
  let hits = search(index, "编译器")
  assert_true(hits.length() >= 1)
  assert_eq(hits[0].title, "工具链更新")
  let none = search(index, "量子计算")
  assert_eq(none.length(), 0)
}
