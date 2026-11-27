import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import wisp

const call_timeout_ms = 5000

pub type Config {
  Config(max_requests: Int, window_ms: Int)
}

pub type Decision {
  Allowed(limit: Int, remaining: Int, reset_epoch_s: Int)
  Limited(limit: Int, retry_after_s: Int, reset_epoch_s: Int, window_s: Int)
}

pub opaque type RateLimitMessage {
  Check(ip: String, now_ms: Int, reply: Subject(Decision))
  ActiveBucketCount(reply: Subject(Int))
}

type LimiterState {
  LimiterState(config: Config, buckets: Dict(String, List(Int)))
}

/// Starts a type-safe OTP Actor enforcing a per-IP sliding-window rate limit.
pub fn start(config: Config) -> Result(Subject(RateLimitMessage), actor.StartError) {
  actor.new(LimiterState(config: config, buckets: dict.new()))
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

fn handle_message(
  state: LimiterState,
  message: RateLimitMessage,
) -> actor.Next(LimiterState, RateLimitMessage) {
  case message {
    ActiveBucketCount(reply) -> {
      process.send(reply, dict.size(state.buckets))
      actor.continue(state)
    }
    Check(ip, now_ms, reply) -> {
      let cutoff = now_ms - state.config.window_ms
      let pruned_buckets = prune_expired_buckets(state.buckets, cutoff)
      let active = dict.get(pruned_buckets, ip) |> result.unwrap([])
      let count = list.length(active)

      case count < state.config.max_requests {
        True -> {
          let updated = [now_ms, ..active]
          let remaining = state.config.max_requests - { count + 1 }
          let oldest = list.fold(updated, now_ms, int.min)
          let reset_epoch_s = { oldest + state.config.window_ms + 999 } / 1000
          let next_buckets = dict.insert(pruned_buckets, ip, updated)
          process.send(
            reply,
            Allowed(
              limit: state.config.max_requests,
              remaining: remaining,
              reset_epoch_s: reset_epoch_s,
            ),
          )
          actor.continue(LimiterState(..state, buckets: next_buckets))
        }
        False -> {
          let oldest = list.fold(active, now_ms, int.min)
          let reset_ms = oldest + state.config.window_ms
          let retry_after_ms = int.max(1000, reset_ms - now_ms)
          let retry_after_s = { retry_after_ms + 999 } / 1000
          let reset_epoch_s = { reset_ms + 999 } / 1000
          let window_s = int.max(1, state.config.window_ms / 1000)
          let next_buckets = dict.insert(pruned_buckets, ip, active)
          process.send(
            reply,
            Limited(
              limit: state.config.max_requests,
              retry_after_s: retry_after_s,
              reset_epoch_s: reset_epoch_s,
              window_s: window_s,
            ),
          )
          actor.continue(LimiterState(..state, buckets: next_buckets))
        }
      }
    }
  }
}

fn prune_expired_buckets(
  buckets: Dict(String, List(Int)),
  cutoff: Int,
) -> Dict(String, List(Int)) {
  dict.fold(buckets, dict.new(), fn(acc, ip, timestamps) {
    case list.filter(timestamps, fn(ts) { ts > cutoff }) {
      [] -> acc
      active -> dict.insert(acc, ip, active)
    }
  })
}

pub fn active_bucket_count(limiter: Subject(RateLimitMessage)) -> Int {
  process.call(limiter, call_timeout_ms, ActiveBucketCount)
}

pub fn check(
  limiter: Subject(RateLimitMessage),
  ip: String,
  now_ms: Int,
) -> Decision {
  process.call(limiter, call_timeout_ms, fn(reply) { Check(ip, now_ms, reply) })
}

/// Resolves client IP. Only trusts X-Forwarded-For when trust_proxy is True;
/// otherwise uses the Mist peer IP (x-client-ip) or localhost fallback.
pub fn resolve_client_ip(req: wisp.Request, trust_proxy: Bool) -> String {
  case trust_proxy {
    False -> fallback_client_ip(req)
    True ->
      case request.get_header(req, "x-forwarded-for") {
        Ok(forwarded) -> {
          let first =
            forwarded
            |> string.split(",")
            |> list.first
            |> result.unwrap("")
            |> string.trim
          case first {
            "" -> fallback_client_ip(req)
            ip -> ip
          }
        }
        Error(_) -> fallback_client_ip(req)
      }
  }
}

fn fallback_client_ip(req: wisp.Request) -> String {
  case request.get_header(req, "x-client-ip") {
    Ok(ip) ->
      case string.trim(ip) {
        "" -> "127.0.0.1"
        trimmed -> trimmed
      }
    Error(_) -> "127.0.0.1"
  }
}

/// Wisp middleware enforcing per-IP rate limiting and setting X-RateLimit-* headers.
pub fn middleware(
  req: wisp.Request,
  limiter: Subject(RateLimitMessage),
  trust_proxy: Bool,
  now_ms: fn() -> Int,
  next: fn() -> wisp.Response,
) -> wisp.Response {
  let ip = resolve_client_ip(req, trust_proxy)
  case check(limiter, ip, now_ms()) {
    Allowed(limit:, remaining:, reset_epoch_s:) ->
      next()
      |> response.set_header("x-ratelimit-limit", int.to_string(limit))
      |> response.set_header("x-ratelimit-remaining", int.to_string(remaining))
      |> response.set_header("x-ratelimit-reset", int.to_string(reset_epoch_s))

    Limited(limit:, retry_after_s:, reset_epoch_s:, window_s:) -> {
      let message =
        "Rate limit exceeded. Maximum "
        <> int.to_string(limit)
        <> " requests per "
        <> int.to_string(window_s)
        <> " seconds."
      let body =
        json.object([
          #("error", json.string("Too Many Requests")),
          #("message", json.string(message)),
        ])
        |> json.to_string

      wisp.json_response(body, 429)
      |> response.set_header("x-ratelimit-limit", int.to_string(limit))
      |> response.set_header("x-ratelimit-remaining", "0")
      |> response.set_header("x-ratelimit-reset", int.to_string(reset_epoch_s))
      |> response.set_header("retry-after", int.to_string(retry_after_s))
    }
  }
}
