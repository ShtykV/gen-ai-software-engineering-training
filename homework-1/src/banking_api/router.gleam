import banking_api/context.{type Context}
import banking_api/middleware/rate_limiter
import banking_api/routes/accounts
import banking_api/routes/transactions
import gleam/http
import gleam/json
import wisp

pub fn handle_request(req: wisp.Request, ctx: Context) -> wisp.Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use <- rate_limiter.middleware(req, ctx.rate_limiter, ctx.trust_proxy, fn() {
    ctx.now_ns() / 1_000_000
  })

  case wisp.path_segments(req), req.method {
    ["health"], http.Get ->
      json.object([#("status", json.string("ok"))])
      |> json.to_string
      |> wisp.json_response(200)

    ["transactions"], http.Post -> transactions.create(req, ctx)
    ["transactions"], http.Get -> transactions.list(req, ctx)
    ["transactions"], _ -> method_not_allowed()

    ["transactions", id], http.Get -> transactions.get_by_id(id, ctx)
    ["transactions", _], _ -> method_not_allowed()

    ["accounts", account_id, "balance"], http.Get ->
      accounts.get_balance(req, account_id, ctx)
    ["accounts", _, "balance"], _ -> method_not_allowed()

    _, _ ->
      json.object([
        #("error", json.string("Not found")),
        #("message", json.string("Route not found")),
      ])
      |> json.to_string
      |> wisp.json_response(404)
  }
}

fn method_not_allowed() -> wisp.Response {
  json.object([
    #("error", json.string("Method not allowed")),
    #("message", json.string("HTTP method not allowed for this endpoint")),
  ])
  |> json.to_string
  |> wisp.json_response(405)
}
