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
/// A readable cache entry: the stored bytes plus the two response fields the
/// fetch stage has to report back. Everything else (platform, charset warning)
/// is recomputed from the body, so a cache hit cannot go stale in a way that
/// contradicts what a network fetch would have produced.
pub(all) struct CachedEntry {
  body : Bytes
  status : String
  content_type : String
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

///|
/// Pull one `key=value` field out of a metadata file. Only the first `=`
/// separates the key from the value, so a value may contain `=`.
fn meta_field(meta : String, key : String) -> String? {
  for line in split_lines(meta) {
    let cs = chars_of(line)
    let eq = index_of_char(cs, '=')
    if eq > 0 && substring_chars(cs, 0, eq) == key {
      return Some(substring_chars(cs, eq + 1, cs.length()))
    }
  }
  None
}

///|
/// Read a cached response back.
///
/// `None` means "no usable entry": nothing is cached for `key`, the metadata is
/// missing, or the body is older than `ttl_ms`. A non-positive TTL means entries
/// are never fresh, so reads are disabled while writes still happen (a later run
/// with a real TTL can then use them). Missing `status` / `content_type` fields
/// fall back to `200` / `""`, so an entry written by an older build stays
/// readable.
///
/// An entry that exists but cannot be read raises `CacheError`: callers may log
/// that, and the fetch stage treats it as a miss rather than a failed fetch.
pub async fn load_cached(
  root : String,
  key : String,
  ttl_ms : Int64,
) -> CachedEntry? raise FetchError {
  if ttl_ms <= 0 {
    return None
  }
  let bin = cache_bin_path(root, key)
  if !(@fs.exists(bin) catch { _ => false }) {
    return None
  }
  let (seconds, nanos) = @fs.mtime(bin) catch {
    e => raise CacheError(e.to_string())
  }
  // File timestamps are Unix-epoch based, so they must be compared against the
  // epoch clock, not against `@async.now()` (which is a monotonic timer clock).
  let stored_ms = seconds * 1000L + nanos.to_int64() / 1_000_000L
  if @env.now().reinterpret_as_int64() - stored_ms > ttl_ms {
    return None
  }
  // A body without metadata cannot be reported faithfully, so it is a miss.
  let meta = @fs.read_file(cache_meta_path(root, key)).text() catch {
    _ => return None
  }
  let body = @fs.read_file(bin).binary() catch {
    e => raise CacheError(e.to_string())
  }
  Some({
    body,
    status: meta_field(meta, "status").unwrap_or("200"),
    content_type: meta_field(meta, "content_type").unwrap_or(""),
  })
}
