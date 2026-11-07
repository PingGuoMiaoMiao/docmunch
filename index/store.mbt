// Index storage stage (P5).
//
// Layout under the index root:
//   {owner}/{name}.json              metadata only, no section bodies
//   {owner}/{name}/<doc_path>        raw source cache for byte-range reads
//
// Raw files are what byte offsets point into, so the cache and the index must be
// written together and version-gated (docs/decisions.md D8).

///|
pub fn index_file_path(root : String, owner : String, name : String) -> String {
  root + "/" + owner + "/" + name + ".json"
}

///|
pub fn cache_dir_path(root : String, owner : String, name : String) -> String {
  root + "/" + owner + "/" + name
}
