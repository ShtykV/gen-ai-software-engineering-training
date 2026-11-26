import banking_api/context.{Context}
import banking_api/middleware/rate_limiter.{Config}
import banking_api/router
import banking_api/services/transaction_service
import banking_api/storage/transaction_store
import banking_api/validators/transaction_validator
import envoy
import gleam/erlang/process
import gleam/http/request
import gleam/int
import gleam/io
import gleam/result
import gleam/string
import gleam/time/timestamp
import mist
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()

  let port = env_int("PORT", 3000)
  let max_requests = env_int("RATE_LIMIT_REQUESTS", 100)
  let window_seconds = env_int("RATE_LIMIT_WINDOW_SECONDS", 60)
  let should_seed = env_bool("SEED_DATA", False)
  let seed_file =
    envoy.get("SEED_FILE") |> result.unwrap("demo/sample-data.json")

  let assert Ok(store) = transaction_store.start()
  let assert Ok(limiter) =
    rate_limiter.start(Config(
      max_requests: max_requests,
      window_ms: window_seconds * 1000,
    ))

  let now_ns = fn() {
    timestamp.system_time() |> transaction_validator.timestamp_to_ns
  }

  case should_seed {
    True ->
      case transaction_service.seed_from_json_file(store, seed_file, now_ns()) {
        Ok(count) ->
          io.println(
            "Seeded "
            <> int.to_string(count)
            <> " sample transactions from "
            <> seed_file,
          )
        Error(reason) -> io.println("Warning: " <> reason)
      }
    False -> Nil
  }

  let ctx = Context(store: store, rate_limiter: limiter, now_ns: now_ns)
  let secret_key_base = wisp.random_string(64)
  let wisp_handler =
    wisp_mist.handler(
      fn(req) { router.handle_request(req, ctx) },
      secret_key_base,
    )

  // Forward the real TCP peer IP from Mist so rate limiting works per client IP
  let mist_handler = fn(req: request.Request(mist.Connection)) {
    let enriched_req = case mist.get_connection_info(req.body) {
      Ok(info) ->
        request.set_header(
          req,
          "x-client-ip",
          mist.ip_address_to_string(info.ip_address),
        )
      Error(_) -> req
    }
    wisp_handler(enriched_req)
  }

  io.println(
    "Starting Banking Transactions API on http://localhost:"
    <> int.to_string(port)
    <> " (rate limit: "
    <> int.to_string(max_requests)
    <> " req/"
    <> int.to_string(window_seconds)
    <> "s)",
  )

  let assert Ok(_) =
    mist_handler
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(port)
    |> mist.start

  process.sleep_forever()
}

fn env_int(name: String, default: Int) -> Int {
  envoy.get(name)
  |> result.try(int.parse)
  |> result.map(fn(v) {
    case v > 0 {
      True -> v
      False -> default
    }
  })
  |> result.unwrap(default)
}

fn env_bool(name: String, default: Bool) -> Bool {
  case envoy.get(name) {
    Ok(value) ->
      case string.lowercase(string.trim(value)) {
        "true" | "1" | "yes" -> True
        "false" | "0" | "no" -> False
        _ -> default
      }
    Error(_) -> default
  }
}
