import banking_api/middleware/rate_limiter.{Allowed, Config, Limited}
import gleam/http
import gleam/http/response
import gleam/string
import gleeunit/should
import wisp
import wisp/simulate

pub fn allows_requests_up_to_limit_and_blocks_next_test() {
  let assert Ok(limiter) =
    rate_limiter.start(Config(max_requests: 3, window_ms: 60_000))

  let t0 = 1_700_000_000_000

  let assert Allowed(limit: 3, remaining: 2, ..) =
    rate_limiter.check(limiter, "10.0.0.1", t0)
  let assert Allowed(limit: 3, remaining: 1, ..) =
    rate_limiter.check(limiter, "10.0.0.1", t0 + 1000)
  let assert Allowed(limit: 3, remaining: 0, ..) =
    rate_limiter.check(limiter, "10.0.0.1", t0 + 2000)

  let assert Limited(limit: 3, retry_after_s: retry_after, ..) =
    rate_limiter.check(limiter, "10.0.0.1", t0 + 3000)
  { retry_after >= 57 && retry_after <= 58 } |> should.be_true
}

pub fn isolates_rate_limits_per_client_ip_test() {
  let assert Ok(limiter) =
    rate_limiter.start(Config(max_requests: 1, window_ms: 60_000))

  let t0 = 1_700_000_000_000

  let assert Allowed(remaining: 0, ..) =
    rate_limiter.check(limiter, "10.0.0.1", t0)
  let assert Limited(..) = rate_limiter.check(limiter, "10.0.0.1", t0 + 500)

  // Different IP is unaffected
  let assert Allowed(remaining: 0, ..) =
    rate_limiter.check(limiter, "10.0.0.2", t0 + 500)
}

pub fn sliding_window_evicts_expired_timestamps_test() {
  let assert Ok(limiter) =
    rate_limiter.start(Config(max_requests: 2, window_ms: 60_000))

  let t0 = 1_700_000_000_000

  let assert Allowed(remaining: 1, ..) =
    rate_limiter.check(limiter, "10.0.0.1", t0)
  let assert Allowed(remaining: 0, ..) =
    rate_limiter.check(limiter, "10.0.0.1", t0 + 10_000)
  let assert Limited(..) = rate_limiter.check(limiter, "10.0.0.1", t0 + 20_000)

  // At t0 + 60_001, the first request at t0 has expired -> 1 slot opens
  let assert Allowed(remaining: 0, ..) =
    rate_limiter.check(limiter, "10.0.0.1", t0 + 60_001)
  // Still limited immediately after because t0 + 10_000 and t0 + 60_001 are active
  let assert Limited(..) = rate_limiter.check(limiter, "10.0.0.1", t0 + 60_002)
}

pub fn middleware_sets_headers_and_returns_429_json_test() {
  let assert Ok(limiter) =
    rate_limiter.start(Config(max_requests: 1, window_ms: 60_000))

  let req =
    simulate.request(http.Get, "/transactions")
    |> simulate.header("x-forwarded-for", "203.0.113.10, 10.0.0.1")

  let ok_resp =
    rate_limiter.middleware(req, limiter, fn() { 1_700_000_000_000 }, fn() {
      wisp.json_response("[]", 200)
    })

  ok_resp.status |> should.equal(200)
  response.get_header(ok_resp, "x-ratelimit-limit") |> should.equal(Ok("1"))
  response.get_header(ok_resp, "x-ratelimit-remaining") |> should.equal(Ok("0"))
  response.get_header(ok_resp, "x-ratelimit-reset") |> should.be_ok

  let blocked_resp =
    rate_limiter.middleware(req, limiter, fn() { 1_700_000_005_000 }, fn() {
      wisp.json_response("[]", 200)
    })

  blocked_resp.status |> should.equal(429)
  response.get_header(blocked_resp, "x-ratelimit-limit")
  |> should.equal(Ok("1"))
  response.get_header(blocked_resp, "x-ratelimit-remaining")
  |> should.equal(Ok("0"))
  response.get_header(blocked_resp, "retry-after") |> should.be_ok
  let body = simulate.read_body(blocked_resp)
  string.contains(body, "Too Many Requests") |> should.be_true
}
