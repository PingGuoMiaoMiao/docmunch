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
// The mutex matters because the HTTP transport interleaves requests at await
// points; without it two concurrent first-reads could both load and one could
// overwrite the other's newer entry.

///|
pub(all) struct IndexCacheEntry {
  mtime : Int64
  index : @core.DocIndex
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
/// Cached index for `repo`, or `None` when the repo is not indexed.
pub async fn IndexCache::get(
  self : IndexCache,
  root : String,
  repo : String,
) -> @core.DocIndex? {
  self.lock.acquire()
  defer self.lock.release()
  let mtime = cache_mtime(root, repo)
  if mtime < 0 {
    // Not indexed (or just deleted): drop any cached copy.
    self.entries.remove(repo)
    return None
  }
  match self.entries.get(repo) {
    Some(entry) => if entry.mtime == mtime { return Some(entry.index) }
    None => ()
  }
  match load_index(root, repo) {
    Some(index) => {
      self.entries[repo] = { mtime, index, }
      Some(index)
    }
    None => {
      self.entries.remove(repo)
      None
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
  self.entries.size()
}
