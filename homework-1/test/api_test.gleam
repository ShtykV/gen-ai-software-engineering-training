import banking_api/context.{Context}
import banking_api/middleware/rate_limiter.{Config}
import banking_api/router
import banking_api/storage/transaction_store
import gleam/dynamic/decode
import gleam/http
import gleam/http/response
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import wisp/simulate

const fixed_now_ns = 1_768_435_200_000_000_000

fn new_test_context(max_requests: Int) -> context.Context {
  let assert Ok(store) = transaction_store.start()
  let assert Ok(limiter) =
    rate_limiter.start(Config(max_requests: max_requests, window_ms: 60_000))
  Context(store: store, rate_limiter: limiter, now_ns: fn() { fixed_now_ns })
}

pub fn health_endpoint_returns_ok_test() {
  let ctx = new_test_context(100)
  let req = simulate.request(http.Get, "/health")
  let resp = router.handle_request(req, ctx)

  resp.status |> should.equal(200)
  simulate.read_body(resp) |> should.equal("{\"status\":\"ok\"}")
}

pub fn create_get_list_and_balance_flow_test() {
  let ctx = new_test_context(100)

  // POST /transactions (transfer on empty store -> overdraft allowed)
  let create_req =
    simulate.request(http.Post, "/transactions")
    |> simulate.json_body(
      json.object([
        #("fromAccount", json.string("ACC-12345")),
        #("toAccount", json.string("ACC-67890")),
        #("amount", json.float(100.5)),
        #("currency", json.string("USD")),
        #("type", json.string("transfer")),
      ]),
    )
  let create_resp = router.handle_request(create_req, ctx)
  create_resp.status |> should.equal(201)

  let created_body = simulate.read_body(create_resp)
  let id_decoder = decode.at(["id"], decode.string)
  let assert Ok(tx_id) = json.parse(created_body, id_decoder)
  string.starts_with(tx_id, "TXN-") |> should.be_true

  // GET /transactions/:id
  let get_resp =
    simulate.request(http.Get, "/transactions/" <> tx_id)
    |> router.handle_request(ctx)
  get_resp.status |> should.equal(200)
  string.contains(simulate.read_body(get_resp), tx_id) |> should.be_true

  // GET /transactions/:id (unknown -> 404)
  let missing_resp =
    simulate.request(http.Get, "/transactions/TXN-NOPE")
    |> router.handle_request(ctx)
  missing_resp.status |> should.equal(404)

  // GET /transactions?accountId=ACC-12345&type=transfer
  let list_resp =
    simulate.request(
      http.Get,
      "/transactions?accountId=ACC-12345&type=transfer",
    )
    |> router.handle_request(ctx)
  list_resp.status |> should.equal(200)
  let assert Ok(items) =
    json.parse(simulate.read_body(list_resp), decode.list(decode.dynamic))
  list.length(items) |> should.equal(1)

  // GET /accounts/ACC-12345/balance -> -100.5 USD
  let bal_resp =
    simulate.request(http.Get, "/accounts/ACC-12345/balance")
    |> router.handle_request(ctx)
  bal_resp.status |> should.equal(200)
  let assert Ok(usd_bal) =
    json.parse(
      simulate.read_body(bal_resp),
      decode.at(["balances", "USD"], decode.float),
    )
  usd_bal |> should.equal(-100.5)

  // GET /accounts/ACC-67890/balance?currency=USD -> 100.5 USD
  let to_bal_resp =
    simulate.request(http.Get, "/accounts/ACC-67890/balance?currency=USD")
    |> router.handle_request(ctx)
  to_bal_resp.status |> should.equal(200)
  let assert Ok(to_usd) =
    json.parse(
      simulate.read_body(to_bal_resp),
      decode.at(["balances", "USD"], decode.float),
    )
  to_usd |> should.equal(100.5)
}

pub fn validation_errors_return_400_with_tasks_contract_test() {
  let ctx = new_test_context(100)

  let bad_req =
    simulate.request(http.Post, "/transactions")
    |> simulate.json_body(
      json.object([
        #("fromAccount", json.string("INVALID")),
        #("toAccount", json.string("ACC-67890")),
        #("amount", json.float(-5.0)),
        #("currency", json.string("FAKE")),
        #("type", json.string("transfer")),
      ]),
    )
  let resp = router.handle_request(bad_req, ctx)
  resp.status |> should.equal(400)

  let body = simulate.read_body(resp)
  let assert Ok(error_title) =
    json.parse(body, decode.at(["error"], decode.string))
  error_title |> should.equal("Validation failed")

  let detail_decoder = {
    use field <- decode.field("field", decode.string)
    use _msg <- decode.field("message", decode.string)
    decode.success(field)
  }
  let assert Ok(fields) =
    json.parse(body, decode.at(["details"], decode.list(detail_decoder)))
  list.contains(fields, "fromAccount") |> should.be_true
  list.contains(fields, "amount") |> should.be_true
  list.contains(fields, "currency") |> should.be_true
}

pub fn malformed_json_and_wrong_content_type_return_structured_400_test() {
  let ctx = new_test_context(100)

  let malformed_req =
    simulate.request(http.Post, "/transactions")
    |> simulate.string_body("{broken json")
    |> simulate.header("content-type", "application/json")
  let malformed_resp = router.handle_request(malformed_req, ctx)
  malformed_resp.status |> should.equal(400)
  string.contains(simulate.read_body(malformed_resp), "Validation failed")
  |> should.be_true

  let plain_req =
    simulate.request(http.Post, "/transactions")
    |> simulate.string_body("{\"amount\":10}")
  let plain_resp = router.handle_request(plain_req, ctx)
  plain_resp.status |> should.equal(400)
  string.contains(simulate.read_body(plain_resp), "application/json")
  |> should.be_true
}

pub fn balance_endpoint_validates_account_currency_and_returns_404_test() {
  let ctx = new_test_context(100)

  // Invalid account format -> 400
  let bad_acc =
    simulate.request(http.Get, "/accounts/INVALID/balance")
    |> router.handle_request(ctx)
  bad_acc.status |> should.equal(400)

  // Invalid currency filter -> 400
  let bad_curr =
    simulate.request(http.Get, "/accounts/ACC-12345/balance?currency=ZZZ")
    |> router.handle_request(ctx)
  bad_curr.status |> should.equal(400)

  // Valid format but unknown account -> 404
  let unknown =
    simulate.request(http.Get, "/accounts/ACC-99999/balance")
    |> router.handle_request(ctx)
  unknown.status |> should.equal(404)
}

pub fn invalid_history_filters_return_400_test() {
  let ctx = new_test_context(100)

  let resp =
    simulate.request(
      http.Get,
      "/transactions?from=2026-05-01&to=2026-01-01&type=invalid",
    )
    |> router.handle_request(ctx)
  resp.status |> should.equal(400)
  string.contains(simulate.read_body(resp), "Validation failed")
  |> should.be_true
}

pub fn router_enforces_rate_limit_end_to_end_test() {
  let ctx = new_test_context(2)

  let r1 =
    simulate.request(http.Get, "/transactions")
    |> simulate.header("x-forwarded-for", "198.51.100.7")
    |> router.handle_request(ctx)
  r1.status |> should.equal(200)
  response.get_header(r1, "x-ratelimit-remaining") |> should.equal(Ok("1"))

  let r2 =
    simulate.request(http.Get, "/transactions")
    |> simulate.header("x-forwarded-for", "198.51.100.7")
    |> router.handle_request(ctx)
  r2.status |> should.equal(200)
  response.get_header(r2, "x-ratelimit-remaining") |> should.equal(Ok("0"))

  let r3 =
    simulate.request(http.Get, "/transactions")
    |> simulate.header("x-forwarded-for", "198.51.100.7")
    |> router.handle_request(ctx)
  r3.status |> should.equal(429)
  response.get_header(r3, "retry-after") |> should.be_ok
}
