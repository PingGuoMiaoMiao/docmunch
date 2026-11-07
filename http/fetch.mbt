// HTTP fetch stage (P1). v0 only ships the SSRF guard so the contract is fixed
// early: the MCP server runs on the user's machine, so private ranges are denied
// by default (docs/decisions.md D13).

///|
pub(all) struct FetchOptions {
  timeout_ms : Int32
  max_bytes : Int32
  allow_private : Bool
}

///|
pub fn default_fetch_options() -> FetchOptions {
  { timeout_ms: 20_000, max_bytes: 5_000_000, allow_private: false, }
}

///|
/// True for loopback / link-local / RFC1918 style hosts.
pub fn is_private_host(host : String) -> Bool {
  let h = host.to_lower()
  h == "localhost" ||
  h == "::1" ||
  h == "0.0.0.0" ||
  h.has_prefix("127.") ||
  h.has_prefix("10.") ||
  h.has_prefix("192.168.") ||
  h.has_prefix("169.254.")
}
