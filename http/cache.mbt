// Raw-response cache.
//
// Layout: <root>/raw/<sha256(url)>.bin  +  <sha256(url)>.meta
// The .bin is the exact bytes the parser will see later, so byte offsets stay
// meaningful across runs (P4 depends on that).

///|
pub fn sha256_hex(bytes : Bytes) -> String {
  let d = @sha256.Digest::new()
  for b in bytes {
    d.write(b)
  }
  d.check_sum()
}

///|
pub fn cache_key(url : String) -> String {
  sha256_hex(@utf8.encode(url))
}

///|
pub fn raw_dir(root : String) -> String {
  root + "/raw"
}

///|
pub fn cache_bin_path(root : String, key : String) -> String {
  raw_dir(root) + "/" + key + ".bin"
}

///|
pub fn cache_meta_path(root : String, key : String) -> String {
  raw_dir(root) + "/" + key + ".meta"
}

///|
/// Write the body and its metadata. The body goes through a temp file + rename
/// so an interrupted run cannot leave a truncated document behind.
pub async fn save_entry(
  root : String,
  key : String,
  body : Bytes,
  meta : String,
) -> Unit raise FetchError {
  let dir = raw_dir(root)
  let bin = cache_bin_path(root, key)
  let tmp = bin + ".tmp"
  try {
    @fs.mkdir(dir, recursive=true, allow_exist=true)
    @fs.write_file(tmp, body, create_mode=CreateOrTruncate)
    @fs.rename(tmp, bin, replace=true)
    @fs.write_file(
      cache_meta_path(root, key),
      meta,
      create_mode=CreateOrTruncate,
    )
  } catch {
    e => raise CacheError(e.to_string())
  }
}
