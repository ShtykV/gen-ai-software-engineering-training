import banking_api/models/transaction.{
  type TransactionFilter, type TransactionStatus, type TransactionType,
  type ValidatedCreateInput, type ValidationError, Completed, Deposit,
  TransactionFilter, Transfer, ValidatedCreateInput, ValidationError, Withdrawal,
}
import banking_api/utils/currencies
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp

const max_amount_cents: Int = 9_999_999_999_999

/// Validates account ID format: ACC-XXXXX where X is ASCII alphanumeric.
pub fn validate_account_id(account_id: String) -> Result(String, ValidationError) {
  case account_id {
    "ACC-" <> suffix -> {
      let bytes = bit_array.from_string(suffix)
      case bit_array.byte_size(bytes) == 5 && is_ascii_alnum(bytes) {
        True -> Ok(account_id)
        False ->
          Error(ValidationError(
            field: "accountId",
            message: "Account number must follow format ACC-XXXXX (5 alphanumeric characters)",
          ))
      }
    }
    _ ->
      Error(ValidationError(
        field: "accountId",
        message: "Account number must follow format ACC-XXXXX (5 alphanumeric characters)",
      ))
  }
}

fn is_ascii_alnum(bytes: BitArray) -> Bool {
  case bytes {
    <<>> -> True
    <<b, rest:bits>> ->
      case
        { b >= 0x30 && b <= 0x39 }
        || { b >= 0x41 && b <= 0x5A }
        || { b >= 0x61 && b <= 0x7A }
      {
        True -> is_ascii_alnum(rest)
        False -> False
      }
    _ -> False
  }
}

/// Validates ISO 4217 uppercase 3-letter currency code.
pub fn validate_currency(code: String) -> Result(String, ValidationError) {
  case currencies.is_valid_iso4217(code) {
    True -> Ok(code)
    False ->
      Error(ValidationError(
        field: "currency",
        message: "Invalid ISO 4217 currency code",
      ))
  }
}

/// Validates a JSON request payload for creating a transaction.
/// Collects all field validation errors rather than failing on the first one.
pub fn validate_create_payload(
  raw_json: String,
) -> Result(ValidatedCreateInput, List(ValidationError)) {
  case json.parse(raw_json, decode.dict(decode.string, decode.dynamic)) {
    Error(_) ->
      Error([
        ValidationError(
          field: "body",
          message: "Request body must be a valid JSON object",
        ),
      ])
    Ok(fields) -> validate_create_fields(fields)
  }
}

pub fn validate_create_fields(
  fields: Dict(String, Dynamic),
) -> Result(ValidatedCreateInput, List(ValidationError)) {
  let type_res = validate_type_field(fields)
  let amount_res = validate_amount_field(fields)
  let currency_res = validate_currency_field(fields)
  let from_res = validate_optional_account_field(fields, "fromAccount")
  let to_res = validate_optional_account_field(fields, "toAccount")
  let timestamp_res = validate_optional_timestamp_field(fields)
  let status_res = validate_optional_status_field(fields)

  let base_errors =
    []
    |> collect_error(type_res)
    |> collect_error(amount_res)
    |> collect_error(currency_res)
    |> collect_error(from_res)
    |> collect_error(to_res)
    |> collect_error(timestamp_res)
    |> collect_error(status_res)

  let cross_errors = validate_account_rules(type_res, from_res, to_res)
  let all_errors = list.append(base_errors, cross_errors)

  case all_errors {
    [] -> {
      let assert Ok(tx_type) = type_res
      let assert Ok(amount_cents) = amount_res
      let assert Ok(currency) = currency_res
      let assert Ok(from_account) = from_res
      let assert Ok(to_account) = to_res
      let assert Ok(parsed_ts) = timestamp_res
      let assert Ok(status) = status_res
      Ok(ValidatedCreateInput(
        from_account: from_account,
        to_account: to_account,
        amount_cents: amount_cents,
        currency: currency,
        tx_type: tx_type,
        timestamp: parsed_ts,
        status: status,
      ))
    }
    errors -> Error(errors)
  }
}

fn collect_error(
  acc: List(ValidationError),
  res: Result(a, ValidationError),
) -> List(ValidationError) {
  case res {
    Ok(_) -> acc
    Error(err) -> list.append(acc, [err])
  }
}

fn validate_type_field(
  fields: Dict(String, Dynamic),
) -> Result(TransactionType, ValidationError) {
  case dict.get(fields, "type") {
    Error(_) ->
      Error(ValidationError(
        field: "type",
        message: "Transaction type is required (deposit, withdrawal, or transfer)",
      ))
    Ok(dyn) ->
      case decode.run(dyn, decode.string) {
        Ok(value) ->
          transaction.tx_type_from_string(value)
          |> result.replace_error(ValidationError(
            field: "type",
            message: "Transaction type must be one of: deposit, withdrawal, transfer",
          ))
        Error(_) ->
          Error(ValidationError(
            field: "type",
            message: "Transaction type must be a string (deposit, withdrawal, or transfer)",
          ))
      }
  }
}

fn validate_amount_field(
  fields: Dict(String, Dynamic),
) -> Result(Int, ValidationError) {
  case dict.get(fields, "amount") {
    Error(_) ->
      Error(ValidationError(
        field: "amount",
        message: "Amount is required and must be a positive number",
      ))
    Ok(dyn) -> parse_positive_cents(dyn)
  }
}

fn parse_positive_cents(dyn: Dynamic) -> Result(Int, ValidationError) {
  case decode.run(dyn, decode.int) {
    Ok(n) ->
      case n <= 0 {
        True ->
          Error(ValidationError(
            field: "amount",
            message: "Amount must be a positive number",
          ))
        False -> {
          let cents = n * 100
          case cents <= max_amount_cents {
            True -> Ok(cents)
            False ->
              Error(ValidationError(
                field: "amount",
                message: "Amount exceeds maximum allowed value (99999999999.99)",
              ))
          }
        }
      }
    Error(_) ->
      case decode.run(dyn, decode.float) {
        Ok(f) ->
          case f >. 0.0 {
            False ->
              Error(ValidationError(
                field: "amount",
                message: "Amount must be a positive number",
              ))
            True ->
              case float_to_exact_cents(f) {
                Ok(cents) if cents > 0 && cents <= max_amount_cents -> Ok(cents)
                Ok(cents) if cents > max_amount_cents ->
                  Error(ValidationError(
                    field: "amount",
                    message: "Amount exceeds maximum allowed value (99999999999.99)",
                  ))
                _ ->
                  Error(ValidationError(
                    field: "amount",
                    message: "Amount must have at most 2 decimal places",
                  ))
              }
          }
        Error(_) ->
          Error(ValidationError(
            field: "amount",
            message: "Amount must be a positive number",
          ))
      }
  }
}

/// Converts a positive Float to exact integer cents using Erlang's shortest
/// round-trip decimal string representation (Ryu), avoiding float ULP drift.
fn float_to_exact_cents(f: Float) -> Result(Int, Nil) {
  let raw = string.lowercase(float.to_string(f))
  let #(mantissa, exp_res) = case string.split_once(raw, "e") {
    Ok(#(m, e)) -> #(m, int.parse(e))
    Error(_) -> #(raw, Ok(0))
  }
  use exp <- result.try(exp_res)

  let #(int_part, frac_part) = case string.split_once(mantissa, ".") {
    Ok(#(i, fr)) -> #(i, fr)
    Error(_) -> #(mantissa, "")
  }

  let digits = int_part <> frac_part
  let shift = exp - string.length(frac_part) + 2

  case shift >= 0 {
    True -> {
      use base <- result.try(int.parse(digits))
      Ok(base * pow10(shift, 1))
    }
    False -> {
      let drop_count = -shift
      let total_len = string.length(digits)
      case drop_count >= total_len {
        True ->
          case is_all_zeros(digits) {
            True -> Ok(0)
            False -> Error(Nil)
          }
        False -> {
          let keep_len = total_len - drop_count
          let kept = string.slice(digits, at_index: 0, length: keep_len)
          let dropped =
            string.slice(digits, at_index: keep_len, length: drop_count)
          case is_all_zeros(dropped) {
            True -> int.parse(kept)
            False -> Error(Nil)
          }
        }
      }
    }
  }
}

fn pow10(exp: Int, acc: Int) -> Int {
  case exp <= 0 {
    True -> acc
    False -> pow10(exp - 1, acc * 10)
  }
}

fn is_all_zeros(s: String) -> Bool {
  case string.pop_grapheme(s) {
    Error(_) -> True
    Ok(#("0", rest)) -> is_all_zeros(rest)
    Ok(_) -> False
  }
}

fn validate_currency_field(
  fields: Dict(String, Dynamic),
) -> Result(String, ValidationError) {
  case dict.get(fields, "currency") {
    Error(_) ->
      Error(ValidationError(
        field: "currency",
        message: "Currency is required (ISO 4217 code)",
      ))
    Ok(dyn) ->
      case decode.run(dyn, decode.string) {
        Ok(code) -> validate_currency(code)
        Error(_) ->
          Error(ValidationError(
            field: "currency",
            message: "Invalid ISO 4217 currency code",
          ))
      }
  }
}

fn validate_optional_account_field(
  fields: Dict(String, Dynamic),
  field_name: String,
) -> Result(Option(String), ValidationError) {
  case dict.get(fields, field_name) {
    Error(_) -> Ok(None)
    Ok(dyn) ->
      case decode.run(dyn, decode.optional(decode.string)) {
        Ok(None) -> Ok(None)
        Ok(Some(value)) ->
          case validate_account_id(value) {
            Ok(valid) -> Ok(Some(valid))
            Error(err) -> Error(ValidationError(..err, field: field_name))
          }
        Error(_) ->
          Error(ValidationError(
            field: field_name,
            message: "Account number must follow format ACC-XXXXX (5 alphanumeric characters)",
          ))
      }
  }
}

fn validate_account_rules(
  type_res: Result(TransactionType, ValidationError),
  from_res: Result(Option(String), ValidationError),
  to_res: Result(Option(String), ValidationError),
) -> List(ValidationError) {
  case type_res {
    Error(_) -> []
    Ok(Deposit) ->
      case to_res {
        Ok(None) -> [
          ValidationError(
            field: "toAccount",
            message: "toAccount is required for deposit transactions",
          ),
        ]
        _ -> []
      }
    Ok(Withdrawal) ->
      case from_res {
        Ok(None) -> [
          ValidationError(
            field: "fromAccount",
            message: "fromAccount is required for withdrawal transactions",
          ),
        ]
        _ -> []
      }
    Ok(Transfer) -> {
      let missing_from = case from_res {
        Ok(None) -> [
          ValidationError(
            field: "fromAccount",
            message: "fromAccount is required for transfer transactions",
          ),
        ]
        _ -> []
      }
      let missing_to = case to_res {
        Ok(None) -> [
          ValidationError(
            field: "toAccount",
            message: "toAccount is required for transfer transactions",
          ),
        ]
        _ -> []
      }
      let same_account = case from_res, to_res {
        Ok(Some(from_acc)), Ok(Some(to_acc)) if from_acc == to_acc -> [
          ValidationError(
            field: "toAccount",
            message: "Source and destination accounts must be different for transfers",
          ),
        ]
        _, _ -> []
      }
      list.flatten([missing_from, missing_to, same_account])
    }
  }
}

fn validate_optional_timestamp_field(
  fields: Dict(String, Dynamic),
) -> Result(Option(#(String, Int)), ValidationError) {
  case dict.get(fields, "timestamp") {
    Error(_) -> Ok(None)
    Ok(dyn) ->
      case decode.run(dyn, decode.optional(decode.string)) {
        Ok(None) -> Ok(None)
        Ok(Some(raw)) ->
          case timestamp.parse_rfc3339(raw) {
            Ok(ts) ->
              Ok(
                Some(#(
                  timestamp.to_rfc3339(ts, calendar.utc_offset),
                  timestamp_to_ns(ts),
                )),
              )
            Error(_) ->
              Error(ValidationError(
                field: "timestamp",
                message: "Timestamp must be a valid ISO 8601 / RFC 3339 datetime",
              ))
          }
        Error(_) ->
          Error(ValidationError(
            field: "timestamp",
            message: "Timestamp must be a valid ISO 8601 / RFC 3339 datetime",
          ))
      }
  }
}

fn validate_optional_status_field(
  fields: Dict(String, Dynamic),
) -> Result(TransactionStatus, ValidationError) {
  case dict.get(fields, "status") {
    Error(_) -> Ok(Completed)
    Ok(dyn) ->
      case decode.run(dyn, decode.optional(decode.string)) {
        Ok(None) -> Ok(Completed)
        Ok(Some(raw)) ->
          transaction.tx_status_from_string(raw)
          |> result.replace_error(ValidationError(
            field: "status",
            message: "Status must be one of: pending, completed, failed",
          ))
        Error(_) ->
          Error(ValidationError(
            field: "status",
            message: "Status must be one of: pending, completed, failed",
          ))
      }
  }
}

/// Validates query parameters for GET /transactions filtering.
pub fn validate_history_filters(
  query: List(#(String, String)),
) -> Result(TransactionFilter, List(ValidationError)) {
  let account_res = case list.key_find(query, "accountId") {
    Error(_) | Ok("") -> Ok(None)
    Ok(value) -> validate_account_id(value) |> result.map(Some)
  }

  let type_res = case list.key_find(query, "type") {
    Error(_) | Ok("") -> Ok(None)
    Ok(value) ->
      transaction.tx_type_from_string(value)
      |> result.map(Some)
      |> result.replace_error(ValidationError(
        field: "type",
        message: "Transaction type must be one of: deposit, withdrawal, transfer",
      ))
  }

  let from_res = case list.key_find(query, "from") {
    Error(_) | Ok("") -> Ok(None)
    Ok(value) -> parse_filter_date(value, "from", False) |> result.map(Some)
  }

  let to_res = case list.key_find(query, "to") {
    Error(_) | Ok("") -> Ok(None)
    Ok(value) -> parse_filter_date(value, "to", True) |> result.map(Some)
  }

  let base_errors =
    []
    |> collect_error(account_res)
    |> collect_error(type_res)
    |> collect_error(from_res)
    |> collect_error(to_res)

  let range_errors = case from_res, to_res {
    Ok(Some(from_ns)), Ok(Some(to_ns)) if from_ns > to_ns -> [
      ValidationError(
        field: "from",
        message: "'from' date must be earlier than or equal to 'to' date",
      ),
    ]
    _, _ -> []
  }

  let all_errors = list.append(base_errors, range_errors)
  case all_errors {
    [] -> {
      let assert Ok(account_id) = account_res
      let assert Ok(tx_type) = type_res
      let assert Ok(from_ns) = from_res
      let assert Ok(to_ns) = to_res
      Ok(TransactionFilter(
        account_id: account_id,
        tx_type: tx_type,
        from_ns: from_ns,
        to_ns: to_ns,
      ))
    }
    errors -> Error(errors)
  }
}

fn parse_filter_date(
  raw: String,
  field_name: String,
  end_of_day: Bool,
) -> Result(Int, ValidationError) {
  let candidate = case string.length(raw) == 10 {
    True ->
      case end_of_day {
        True -> raw <> "T23:59:59.999999999Z"
        False -> raw <> "T00:00:00Z"
      }
    False -> raw
  }

  case timestamp.parse_rfc3339(candidate) {
    Ok(ts) -> Ok(timestamp_to_ns(ts))
    Error(_) ->
      Error(ValidationError(
        field: field_name,
        message: "Date must be a valid YYYY-MM-DD or ISO 8601 / RFC 3339 datetime",
      ))
  }
}

pub fn timestamp_to_ns(ts: timestamp.Timestamp) -> Int {
  let #(secs, nanos) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  secs * 1_000_000_000 + nanos
}

pub fn ns_to_rfc3339(ns: Int) -> String {
  let secs = ns / 1_000_000_000
  let nanos = ns % 1_000_000_000
  timestamp.from_unix_seconds_and_nanoseconds(secs, nanos)
  |> timestamp.to_rfc3339(calendar.utc_offset)
}
