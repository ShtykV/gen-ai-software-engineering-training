import banking_api/context.{type Context}
import banking_api/models/transaction.{ValidationError}
import banking_api/services/transaction_service
import banking_api/validators/transaction_validator
import gleam/http/request
import gleam/json
import gleam/string
import wisp

pub fn create(req: wisp.Request, ctx: Context) -> wisp.Response {
  case has_json_content_type(req) {
    False ->
      validation_error_response([
        ValidationError(
          field: "content-type",
          message: "Content-Type header must be application/json",
        ),
      ])
    True -> {
      use raw_body <- wisp.require_string_body(req)
      case transaction_validator.validate_create_payload(raw_body) {
        Error(errors) -> validation_error_response(errors)
        Ok(input) -> {
          let created =
            transaction_service.create_transaction(
              ctx.store,
              input,
              ctx.now_ns(),
            )
          created
          |> transaction.to_json
          |> json.to_string
          |> wisp.json_response(201)
        }
      }
    }
  }
}

pub fn list(req: wisp.Request, ctx: Context) -> wisp.Response {
  let query = wisp.get_query(req)
  case transaction_validator.validate_history_filters(query) {
    Error(errors) -> validation_error_response(errors)
    Ok(filter) -> {
      let items = transaction_service.list_transactions(ctx.store, filter)
      items
      |> transaction.list_to_json
      |> json.to_string
      |> wisp.json_response(200)
    }
  }
}

pub fn get_by_id(id: String, ctx: Context) -> wisp.Response {
  case transaction_service.get_transaction(ctx.store, id) {
    Ok(tx) ->
      tx
      |> transaction.to_json
      |> json.to_string
      |> wisp.json_response(200)
    Error(Nil) -> not_found_response("Transaction '" <> id <> "' not found")
  }
}

fn has_json_content_type(req: wisp.Request) -> Bool {
  case request.get_header(req, "content-type") {
    Ok(value) -> {
      let media_type = case string.split_once(value, ";") {
        Ok(#(main, _)) -> main
        Error(_) -> value
      }
      string.lowercase(string.trim(media_type)) == "application/json"
    }
    Error(_) -> False
  }
}

fn validation_error_response(
  errors: List(transaction.ValidationError),
) -> wisp.Response {
  errors
  |> transaction.validation_errors_to_json
  |> json.to_string
  |> wisp.json_response(400)
}

fn not_found_response(message: String) -> wisp.Response {
  json.object([
    #("error", json.string("Not found")),
    #("message", json.string(message)),
  ])
  |> json.to_string
  |> wisp.json_response(404)
}
