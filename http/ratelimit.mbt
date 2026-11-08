// Per-host request pacing.
//
// Pure and injectable: tests pass a fake clock, production passes `@async.now()`
// and the returned wait is fed to `@async.sleep`. Kept out of `fetch` itself so a
// single-URL call has no hidden sleeps; batch callers own the limiter.

///|
pub(all) struct RateLimiter {
  interval_ms : Int32
  next_at : Map[String, Int32]
}

///|
pub fn RateLimiter::new(interval_ms : Int32) -> RateLimiter {
  { interval_ms, next_at: Map([]), }
}

///|
/// Reserve the next slot for `host` and return how long the caller must wait.
/// Advancing the schedule even when the wait is zero keeps bursts from stacking.
pub fn RateLimiter::reserve(
  self : RateLimiter,
  host : String,
  now_ms : Int32,
) -> Int32 {
  let prev = match self.next_at.get(host) {
    Some(v) => v
    None => 0
  }
  let start = if prev > now_ms { prev } else { now_ms }
  self.next_at[host] = start + self.interval_ms
  start - now_ms
}
