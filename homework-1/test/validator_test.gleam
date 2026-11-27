import banking_api/models/transaction.{
  type ValidationError, Completed, Deposit, Failed, Pending, Transfer,
  ValidationError, Withdrawal,
}
import banking_api/utils/currencies
import banking_api/validators/transaction_validator
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

pub fn valid_iso4217_currencies_test() {
  currencies.is_valid_iso4217("USD") |> should.be_true
  currencies.is_valid_iso4217("EUR") |> should.be_true
  currencies.is_valid_iso4217("GBP") |> should.be_true
  currencies.is_valid_iso4217("JPY") |> should.be_true
  currencies.is_valid_iso4217("UAH") |> should.be_true
  currencies.is_valid_iso4217("usd") |> should.be_false
  currencies.is_valid_iso4217("ZZZ") |> should.be_false
  currencies.is_valid_iso4217("") |> should.be_false
}

pub fn validate_account_id_format_test() {
  transaction_validator.validate_account_id("ACC-12345")
  |> should.equal(Ok("ACC-12345"))

  transaction_validator.validate_account_id("ACC-A1b2C")
  |> should.equal(Ok("ACC-A1b2C"))

  transaction_validator.validate_account_id("12345") |> should.be_error
  transaction_validator.validate_account_id("ACC-1234") |> should.be_error
  transaction_validator.validate_account_id("ACC-123456") |> should.be_error
  transaction_validator.validate_account_id("ACC-12_45") |> should.be_error
  transaction_validator.validate_account_id("acc-12345") |> should.be_error
}

pub fn validate_valid_transfer_payload_test() {
  let body =
    "{\"fromAccount\":\"ACC-12345\",\"toAccount\":\"ACC-67890\",\"amount\":100.50,\"currency\":\"USD\",\"type\":\"transfer\"}"

  let assert Ok(input) = transaction_validator.validate_create_payload(body)
  input.from_account |> should.equal(Some("ACC-12345"))
  input.to_account |> should.equal(Some("ACC-67890"))
  input.amount_cents |> should.equal(10_050)
  input.currency |> should.equal("USD")
  input.tx_type |> should.equal(Transfer)
  input.status |> should.equal(Completed)
  input.timestamp |> should.equal(None)
}

pub fn validate_valid_deposit_and_withdrawal_optional_counterparty_test() {
  let deposit_body =
    "{\"toAccount\":\"ACC-12345\",\"amount\":250,\"currency\":\"EUR\",\"type\":\"deposit\",\"status\":\"pending\",\"timestamp\":\"2026-01-15T10:30:00Z\"}"

  let assert Ok(dep) =
    transaction_validator.validate_create_payload(deposit_body)
  dep.from_account |> should.equal(None)
  dep.to_account |> should.equal(Some("ACC-12345"))
  dep.amount_cents |> should.equal(25_000)
  dep.tx_type |> should.equal(Deposit)
  dep.status |> should.equal(Pending)
  dep.timestamp |> should.be_some

  let withdrawal_body =
    "{\"fromAccount\":\"ACC-12345\",\"amount\":49.99,\"currency\":\"GBP\",\"type\":\"withdrawal\",\"status\":\"failed\"}"

  let assert Ok(wd) =
    transaction_validator.validate_create_payload(withdrawal_body)
  wd.from_account |> should.equal(Some("ACC-12345"))
  wd.to_account |> should.equal(None)
  wd.amount_cents |> should.equal(4999)
  wd.tx_type |> should.equal(Withdrawal)
  wd.status |> should.equal(Failed)
}

pub fn validate_rejects_invalid_amounts_test() {
  // Zero amount
  let assert Error(errs_zero) =
    transaction_validator.validate_create_payload(
      "{\"toAccount\":\"ACC-12345\",\"amount\":0,\"currency\":\"USD\",\"type\":\"deposit\"}",
    )
  list.any(errs_zero, fn(e: ValidationError) { e.field == "amount" })
  |> should.be_true

  // Negative amount
  let assert Error(errs_neg) =
    transaction_validator.validate_create_payload(
      "{\"toAccount\":\"ACC-12345\",\"amount\":-5.25,\"currency\":\"USD\",\"type\":\"deposit\"}",
    )
  list.any(errs_neg, fn(e) { e.field == "amount" }) |> should.be_true

  // More than 2 decimal places
  let assert Error(errs_dec) =
    transaction_validator.validate_create_payload(
      "{\"toAccount\":\"ACC-12345\",\"amount\":10.123,\"currency\":\"USD\",\"type\":\"deposit\"}",
    )
  list.any(errs_dec, fn(e) { e.field == "amount" }) |> should.be_true

  // String instead of number
  let assert Error(errs_str) =
    transaction_validator.validate_create_payload(
      "{\"toAccount\":\"ACC-12345\",\"amount\":\"100\",\"currency\":\"USD\",\"type\":\"deposit\"}",
    )
  list.any(errs_str, fn(e) { e.field == "amount" }) |> should.be_true

  // Boolean instead of number
  let assert Error(errs_bool) =
    transaction_validator.validate_create_payload(
      "{\"toAccount\":\"ACC-12345\",\"amount\":true,\"currency\":\"USD\",\"type\":\"deposit\"}",
    )
  list.any(errs_bool, fn(e) { e.field == "amount" }) |> should.be_true

  // 9 decimal places must NOT slip past a float epsilon check
  let assert Error(errs_tiny_dec) =
    transaction_validator.validate_create_payload(
      "{\"toAccount\":\"ACC-12345\",\"amount\":1.000000001,\"currency\":\"USD\",\"type\":\"deposit\"}",
    )
  list.any(errs_tiny_dec, fn(e) { e.field == "amount" }) |> should.be_true
}

pub fn validate_accepts_large_exact_two_decimal_amounts_test() {
  let assert Ok(large1) =
    transaction_validator.validate_create_payload(
      "{\"toAccount\":\"ACC-12345\",\"amount\":1000000000.01,\"currency\":\"USD\",\"type\":\"deposit\"}",
    )
  large1.amount_cents |> should.equal(100_000_000_001)

  let assert Ok(max_val) =
    transaction_validator.validate_create_payload(
      "{\"toAccount\":\"ACC-12345\",\"amount\":99999999999.99,\"currency\":\"USD\",\"type\":\"deposit\"}",
    )
  max_val.amount_cents |> should.equal(9_999_999_999_999)

  // Above maximum allowed value is rejected
  let assert Error(too_big) =
    transaction_validator.validate_create_payload(
      "{\"toAccount\":\"ACC-12345\",\"amount\":100000000000,\"currency\":\"USD\",\"type\":\"deposit\"}",
    )
  list.any(too_big, fn(e) { e.field == "amount" }) |> should.be_true
}

pub fn validate_rejects_self_transfer_and_missing_required_accounts_test() {
  let assert Error(errs_self) =
    transaction_validator.validate_create_payload(
      "{\"fromAccount\":\"ACC-12345\",\"toAccount\":\"ACC-12345\",\"amount\":10,\"currency\":\"USD\",\"type\":\"transfer\"}",
    )
  list.any(errs_self, fn(e) { e.field == "toAccount" }) |> should.be_true

  let assert Error(errs_dep) =
    transaction_validator.validate_create_payload(
      "{\"fromAccount\":\"ACC-12345\",\"amount\":10,\"currency\":\"USD\",\"type\":\"deposit\"}",
    )
  list.any(errs_dep, fn(e) { e.field == "toAccount" }) |> should.be_true

  let assert Error(errs_wd) =
    transaction_validator.validate_create_payload(
      "{\"toAccount\":\"ACC-12345\",\"amount\":10,\"currency\":\"USD\",\"type\":\"withdrawal\"}",
    )
  list.any(errs_wd, fn(e) { e.field == "fromAccount" }) |> should.be_true
}

pub fn validate_aggregates_all_field_errors_test() {
  let body =
    "{\"fromAccount\":\"BAD\",\"toAccount\":\"ALSO-BAD\",\"amount\":-10,\"currency\":\"NOPE\",\"type\":\"wire\",\"status\":\"unknown\",\"timestamp\":\"not-a-date\"}"

  let assert Error(errors) = transaction_validator.validate_create_payload(body)
  let fields = list.map(errors, fn(e) { e.field })
  list.contains(fields, "fromAccount") |> should.be_true
  list.contains(fields, "toAccount") |> should.be_true
  list.contains(fields, "amount") |> should.be_true
  list.contains(fields, "currency") |> should.be_true
  list.contains(fields, "type") |> should.be_true
  list.contains(fields, "status") |> should.be_true
  list.contains(fields, "timestamp") |> should.be_true
}

pub fn validate_malformed_json_returns_body_error_test() {
  let assert Error([ValidationError(field: "body", ..)]) =
    transaction_validator.validate_create_payload("{not valid json")
}

pub fn validate_history_filters_date_bounds_and_errors_test() {
  // Same-day date-only filter expands inclusively across the full UTC day
  let assert Ok(filter) =
    transaction_validator.validate_history_filters([
      #("accountId", "ACC-12345"),
      #("type", "transfer"),
      #("from", "2026-01-15"),
      #("to", "2026-01-15"),
    ])
  filter.account_id |> should.equal(Some("ACC-12345"))
  filter.tx_type |> should.equal(Some(Transfer))
  let assert Some(from_ns) = filter.from_ns
  let assert Some(to_ns) = filter.to_ns
  { to_ns > from_ns } |> should.be_true

  // Inverted range returns error on "from"
  let assert Error(inv_errs) =
    transaction_validator.validate_history_filters([
      #("from", "2026-02-01"),
      #("to", "2026-01-01"),
    ])
  list.any(inv_errs, fn(e) { e.field == "from" }) |> should.be_true

  // Invalid calendar date returns error
  let assert Error(bad_date_errs) =
    transaction_validator.validate_history_filters([
      #("from", "2026-02-30"),
      #("type", "invalid"),
      #("accountId", "BAD"),
    ])
  let fields = list.map(bad_date_errs, fn(e) { e.field })
  list.contains(fields, "from") |> should.be_true
  list.contains(fields, "type") |> should.be_true
  list.contains(fields, "accountId") |> should.be_true
}
