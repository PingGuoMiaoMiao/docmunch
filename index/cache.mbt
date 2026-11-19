// In-process index cache for long-lived processes.
//
// `load_index` re-reads and re-parses `index.json` on every call, which costs
// O(sections) per request. A CLI invocation pays that once and exits, but an MCP
// server lives for the whole session, so it should pay it once per repo.
//
// Invalidation is by mtime: any writer (this process or the CLI) updating
// index.json changes the mtime, and the next read reloads. Writes made through
// this server additionally call `invalidate` so a fast follow-up read cannot see
// a stale entry within the filesystem's mtime granularity.
//
// Each entry also lazily holds the inverted index, so a search pays the posting
// build once per repo instead of scoring every section on every query.
//
// The mutex matters because the HTTP transport interleaves requests at await
// points; without it two concurrent first-reads could both load and one could
// overwrite the other's newer entry.

///|
pub(all) struct IndexCacheEntry {
  mtime : Int64
  index : @core.DocIndex
  inverted : InvertedIndex?
}

///|
pub(all) struct IndexCache {
  entries : Map[String, IndexCacheEntry]
  lock : @async.Mutex
}

///|
pub fn IndexCache::new() -> IndexCache {
  IndexCache::{ entries: Map([]), lock: @async.Mutex::Mutex(), }
}

///|
async fn cache_mtime(root : String, repo : String) -> Int64 {
  let path = index_file_path(root, repo)
  let pair = @fs.mtime(path) catch { _ => return -1 }
  pair.0
}

///|
/// Loaded index for `repo`, loading or reloading as needed. Caller holds the lock.
async fn ensure_entry(
  cache : IndexCache,
  root : String,
  repo : String,
) -> IndexCacheEntry? {
  let mtime = cache_mtime(root, repo)
  if mtime < 0 {
    cache.entries.remove(repo)
    return None
  }
  match cache.entries.get(repo) {
    Some(entry) => if entry.mtime == mtime { return Some(entry) }
    None => ()
  }
  match load_index(root, repo) {
    Some(index) => {
      let entry : IndexCacheEntry = { mtime, index, inverted: None, }
      cache.entries[repo] = entry
      Some(entry)
    }
    None => {
      cache.entries.remove(repo)
      None
    }
  }
}

///|
/// Cached index for `repo`, or `None` when the repo is not indexed.
pub async fn IndexCache::get(
  self : IndexCache,
  root : String,
  repo : String,
) -> @core.DocIndex? {
  self.lock.acquire()
  defer self.lock.release()
  match ensure_entry(self, root, repo) {
    Some(entry) => Some(entry.index)
    None => None
  }
}

///|
/// Cached inverted index for `repo`, building the postings on first use.
pub async fn IndexCache::inverted(
  self : IndexCache,
  root : String,
  repo : String,
) -> InvertedIndex? {
  self.lock.acquire()
  defer self.lock.release()
  let entry = match ensure_entry(self, root, repo) {
    Some(e) => e
    None => return None
  }
  match entry.inverted {
    Some(inv) => Some(inv)
    None => {
      let inv = InvertedIndex::build(entry.index)
      self.entries[repo] = { ..entry, inverted: Some(inv), }
      Some(inv)
    }
  }
}

///|
/// Drop the cached copy after a write, so the next read reloads.
pub fn IndexCache::invalidate(self : IndexCache, repo : String) -> Unit {
  self.entries.remove(repo)
}

///|
/// Number of cached repos (used by tests and the bench).
pub fn IndexCache::size(self : IndexCache) -> Int32 {
  self.entries.length()
}
