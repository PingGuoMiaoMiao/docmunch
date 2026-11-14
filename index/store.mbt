// Index storage: metadata-only JSON + raw document cache.
//
// Layout (D8):
//   <root>/<repo-key>/index.json           metadata only, no section bodies
//   <root>/<repo-key>/repo.json            original repo label (read by list_repos)
//   <root>/<repo-key>/raw/<sha256(path)>.bin   exact Markdown bytes the offsets point into
//
// `repo_key` maps an arbitrary repo label onto one filesystem-safe directory
// name. The mapping is injective: names that had to be rewritten carry a short
// digest suffix, so "a b" and "a_b" never collide. Public path functions accept
// the original label and apply the key themselves; callers must not sanitize.

///|
/// Short lowercase hex prefix of a SHA-256 digest, used to disambiguate keys.
fn sha8(text : String) -> String {
  let d = @sha256.Digest::new()
  for b in @utf8.encode(text) {
    d.write(b)
  }
  d.check_sum()[:8].to_owned()
}

///|
/// Filesystem-safe directory name for a repo label.
///
/// Every character outside `[A-Za-z0-9._-]` becomes `_`. That rewrite is lossy,
/// so a label that changed gets `-<sha256[0..8]>` appended: `"my repo"` becomes
/// `"my_repo-<hash>"` and stays distinct from `"my_repo"`. Empty, `"."` and
/// `".."` are never usable as directory names (and could escape the root), so
/// they map to `"repo-<sha256[0..8]>"`.
pub fn repo_key(repo : String) -> String {
  if repo == "" || repo == "." || repo == ".." {
    return "repo-" + sha8(repo)
  }
  let sb = StringBuilder::StringBuilder()
  for c in repo {
    let n = c.to_int()
    let ok = (n >= 97 && n <= 122) ||
      (n >= 65 && n <= 90) ||
      (n >= 48 && n <= 57) ||
      c == '-' ||
      c == '_' ||
      c == '.'
    if ok {
      sb.write_char(c)
    } else {
      sb.write_char('_')
    }
  }
  let sanitized = sb.to_string()
  let base = if sanitized == "" { "repo" } else { sanitized }
  // Windows strips trailing dots/spaces and is case-insensitive, so these names
  // would collide with a sibling repo; reserved device names cannot be created
  // at all.
  let mut needs_hash = sanitized != repo
  if sanitized != "" {
    let last = sanitized[sanitized.length() - 1]
    if last == '.' || last == ' ' {
      needs_hash = true
    }
  }
  if is_reserved_windows_name(sanitized) {
    needs_hash = true
  }
  if needs_hash {
    base + "-" + sha8(repo)
  } else {
    base
  }
}

///|
fn is_reserved_windows_name(name : String) -> Bool {
  let upper = name.to_upper()
  if upper == "CON" || upper == "PRN" || upper == "AUX" || upper == "NUL" {
    return true
  }
  if upper.length() == 4 && (upper.has_prefix("COM") || upper.has_prefix("LPT")) {
    let n = upper[3]
    return n >= '1' && n <= '9'
  }
  false
}

///|
pub fn repo_dir(root : String, repo : String) -> String {
  root + "/" + repo_key(repo)
}

///|
pub fn index_file_path(root : String, repo : String) -> String {
  repo_dir(root, repo) + "/index.json"
}

///|
pub fn raw_dir(root : String, repo : String) -> String {
  repo_dir(root, repo) + "/raw"
}

///|
pub fn raw_file_path(root : String, repo : String, doc_path : String) -> String {
  let d = @sha256.Digest::new()
  for b in @utf8.encode(doc_path) {
    d.write(b)
  }
  raw_dir(root, repo) + "/" + d.check_sum() + ".bin"
}

///|
fn repo_meta_path(root : String, repo : String) -> String {
  repo_dir(root, repo) + "/repo.json"
}

///|
/// Shape of `<repo-dir>/repo.json`: the label the user originally supplied.
#derive(ToJson, FromJson)
priv struct RepoMeta {
  name : String
}

///|
/// Original label stored in `repo.json`, or `None` for pre-repo.json indexes.
async fn read_repo_name(path : String) -> String? {
  if !@fs.exists(path) {
    return None
  }
  let text = @fs.read_file(path).text() catch { _ => return None }
  let parsed = @json.parse(text) catch { _ => return None }
  let meta : RepoMeta = @json.from_json(parsed) catch { _ => return None }
  Some(meta.name)
}

///|
pub async fn load_index(root : String, repo : String) -> @core.DocIndex? {
  let path = index_file_path(root, repo)
  if !@fs.exists(path) {
    return None
  }
  let text = @fs.read_file(path).text() catch { _ => return None }
  let parsed = @json.parse(text) catch { _ => return None }
  let index : @core.DocIndex = @json.from_json(parsed) catch {
    _ => return None
  }
  // Version gate: a stale schema means "rebuild", not "best effort".
  if index.index_version != @core.index_version {
    None
  } else {
    Some(index)
  }
}

///|
pub async fn save_index(
  root : String,
  repo : String,
  index : @core.DocIndex,
) -> Unit {
  let dir = repo_dir(root, repo)
  @fs.mkdir(dir, recursive=true, allow_exist=true)
  let json = @json.to_json(index).stringify(indent=2)
  let path = index_file_path(root, repo)
  let tmp = path + ".tmp"
  @fs.write_file(tmp, json, create_mode=CreateOrTruncate)
  @fs.rename(tmp, path, replace=true)
  // The directory name is a lossy key; remember the label the user gave us.
  let meta : RepoMeta = { name: repo, }
  @fs.write_file(
    repo_meta_path(root, repo),
    @json.to_json(meta).stringify(),
    create_mode=CreateOrTruncate,
  )
}

///|
pub async fn write_raw(
  root : String,
  repo : String,
  doc_path : String,
  text : String,
) -> Unit {
  let dir = raw_dir(root, repo)
  @fs.mkdir(dir, recursive=true, allow_exist=true)
  let path = raw_file_path(root, repo, doc_path)
  let tmp = path + ".tmp"
  @fs.write_file(tmp, text, create_mode=CreateOrTruncate)
  @fs.rename(tmp, path, replace=true)
}

///|
/// Delete a repo's index, raw cache, and metadata. A missing directory is a
/// no-op, so deleting an unindexed repo is idempotent.
pub async fn delete_repo(root : String, repo : String) -> Unit {
  let dir = repo_dir(root, repo)
  if @fs.exists(dir) {
    @fs.rmdir(dir, recursive=true)
  }
}

///|
pub async fn list_repos(root : String) -> Array[String] {
  if !@fs.exists(root) {
    return []
  }
  let entries = @fs.readdir(root, sort=true)
  let out : Array[String] = []
  for name in entries {
    let candidate = root + "/" + name + "/index.json"
    if @fs.exists(candidate) {
      // Older indexes have no repo.json; the directory name is all we have.
      let display = match read_repo_name(root + "/" + name + "/repo.json") {
        Some(original) => original
        None => name
      }
      out.push(display)
    }
  }
  out
}

///|
/// Read one section's bytes via seek, not by loading the whole document.
pub async fn read_section_text(
  root : String,
  repo : String,
  doc_path : String,
  section : @core.Section,
) -> String {
  let path = raw_file_path(root, repo, doc_path)
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let len = section.byte_end - section.byte_start
  if len <= 0 {
    return ""
  }
  let buf = FixedArray::make(len, Byte::default())
  let read = file.read_at(buf, position=section.byte_start.to_int64(), len~)
  let bytes = Bytes::from_array(buf[:read])
  @utf8.decode_lossy(bytes)
}

///|
/// Read a whole cached document (the raw file the byte offsets point into).
pub async fn read_document_text(
  root : String,
  repo : String,
  doc_path : String,
) -> String {
  let path = raw_file_path(root, repo, doc_path)
  if !(@fs.exists(path) catch { _ => false }) {
    return ""
  }
  @fs.read_file(path).text()
}

///|
/// True when the raw cache for `doc_path` is present. Retrieval needs it: the
/// byte offsets in the index only make sense against that exact file.
pub async fn has_raw(root : String, repo : String, doc_path : String) -> Bool {
  @fs.exists(raw_file_path(root, repo, doc_path)) catch {
    _ => false
  }
}
