// Directory walks for `index-dir`.
//
// Shared by the CLI and the MCP tool so both agree on which files count and
// which directories to skip.

///|
pub fn is_indexable_name(name : String) -> Bool {
  let lower = name.to_lower()
  lower.has_suffix(".md") ||
  lower.has_suffix(".markdown") ||
  lower.has_suffix(".html") ||
  lower.has_suffix(".htm") ||
  lower.has_suffix(".ipynb") ||
  lower.has_suffix(".rst")
}

///|
pub fn skip_dir_name(name : String) -> Bool {
  let lower = name.to_lower()
  name.has_prefix(".") ||
  lower == "node_modules" ||
  lower == "_build" ||
  lower == "target" ||
  lower == "dist"
}

///|
/// Append every indexable file under `dir` to `out`, as paths relative to the
/// walk root and always POSIX style.
pub async fn collect_documents(
  dir : String,
  prefix : String,
  out : Array[String],
) -> Unit {
  let entries = @fs.readdir(dir, sort=true) catch { _ => return }
  for name in entries {
    let full = dir + "/" + name
    let rel = if prefix == "" { name } else { prefix + "/" + name }
    let kind = @fs.kind(full) catch { _ => @fs.FileKind::Unknown }
    match kind {
      @fs.FileKind::Directory =>
        if !skip_dir_name(name) {
          collect_documents(full, rel, out)
        }
      @fs.FileKind::Regular => if is_indexable_name(name) { out.push(rel) }
      _ => ()
    }
  }
}
