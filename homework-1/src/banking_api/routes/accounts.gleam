import banking_api/context.{type Context}
import banking_api/models/transaction
import banking_api/services/transaction_service
import banking_api/validators/transaction_validator
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import wisp

pub fn get_balance(
  req: wisp.Request,
  account_id: String,
  ctx: Context,
) -> wisp.Response {
  let account_res = transaction_validator.validate_account_id(account_id)
  let currency_res = case list.key_find(wisp.get_query(req), "currency") {
    Error(_) | Ok("") -> Ok(None)
    Ok(code) -> transaction_validator.validate_currency(code) |> result.map(Some)
  }

  let errors =
    []
    |> append_error(account_res)
    |> append_error(currency_res)

  case errors {
    [_, ..] ->
      errors
      |> transaction.validation_errors_to_json
      |> json.to_string
      |> wisp.json_response(400)
    [] -> {
      let assert Ok(valid_account) = account_res
      let assert Ok(currency_opt) = currency_res
      case
        transaction_service.get_account_balance(
          ctx.store,
          valid_account,
          currency_opt,
        )
      {
        Ok(balance) ->
          balance
          |> transaction.account_balance_to_json
          |> json.to_string
          |> wisp.json_response(200)
        Error(Nil) ->
          json.object([
            #("error", json.string("Not found")),
            #(
              "message",
              json.string("Account '" <> valid_account <> "' not found"),
            ),
          ])
          |> json.to_string
          |> wisp.json_response(404)
      }
    }
  }
}

fn append_error(
  acc: List(transaction.ValidationError),
  res: Result(a, transaction.ValidationError),
) -> List(transaction.ValidationError) {
  case res {
    Ok(_) -> acc
    Error(err) -> list.append(acc, [err])
  }
}
