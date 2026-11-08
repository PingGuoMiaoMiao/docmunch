// Index storage: metadata-only JSON + raw document cache.
//
// Layout (D8):
//   <root>/<repo>/index.json           metadata only, no section bodies
//   <root>/<repo>/raw/<sha256(path)>.bin   exact Markdown bytes the offsets point into
//
// Writes go through a temp file + rename so an interrupted run cannot leave a
// truncated index behind.

///|
pub fn repo_dir(root : String, repo : String) -> String {
  root + "/" + repo
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
fn sanitize_repo(repo : String) -> String {
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
  sb.to_string()
}

///|
pub async fn load_index(root : String, repo : String) -> @core.DocIndex? {
  let path = index_file_path(root, sanitize_repo(repo))
  if not(@fs.exists(path)) {
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
  let name = sanitize_repo(repo)
  let dir = repo_dir(root, name)
  @fs.mkdir(dir, recursive=true, allow_exist=true)
  let json = @json.to_json(index).stringify(indent=2)
  let path = index_file_path(root, name)
  let tmp = path + ".tmp"
  @fs.write_file(tmp, json, create_mode=CreateOrTruncate)
  @fs.rename(tmp, path, replace=true)
}

///|
pub async fn write_raw(
  root : String,
  repo : String,
  doc_path : String,
  text : String,
) -> Unit {
  let name = sanitize_repo(repo)
  let dir = raw_dir(root, name)
  @fs.mkdir(dir, recursive=true, allow_exist=true)
  let path = raw_file_path(root, name, doc_path)
  let tmp = path + ".tmp"
  @fs.write_file(tmp, text, create_mode=CreateOrTruncate)
  @fs.rename(tmp, path, replace=true)
}

///|
pub async fn list_repos(root : String) -> Array[String] {
  if not(@fs.exists(root)) {
    return []
  }
  let entries = @fs.readdir(root, sort=true)
  let out : Array[String] = []
  for name in entries {
    let candidate = root + "/" + name + "/index.json"
    if @fs.exists(candidate) {
      out.push(name)
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
  let path = raw_file_path(root, sanitize_repo(repo), doc_path)
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let len = section.byte_end - section.byte_start
  if len <= 0 {
    return ""
  }
  let buf = FixedArray::make(len, Byte::default())
  let read = file.read_at(buf, position=section.byte_start.to_int64(), len~)
  let bytes = Bytes::from_fixedarray(buf, len=read)
  @utf8.decode_lossy(bytes)
}
