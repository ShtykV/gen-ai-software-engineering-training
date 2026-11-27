import gleam/dict.{type Dict}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import gleam/string

pub type TransactionType {
  Deposit
  Withdrawal
  Transfer
}

pub type TransactionStatus {
  Pending
  Completed
  Failed
}

pub type ValidationError {
  ValidationError(field: String, message: String)
}

pub type Transaction {
  Transaction(
    id: String,
    from_account: Option(String),
    to_account: Option(String),
    amount_cents: Int,
    currency: String,
    tx_type: TransactionType,
    timestamp: String,
    timestamp_ns: Int,
    status: TransactionStatus,
  )
}

pub type ValidatedCreateInput {
  ValidatedCreateInput(
    from_account: Option(String),
    to_account: Option(String),
    amount_cents: Int,
    currency: String,
    tx_type: TransactionType,
    timestamp: Option(#(String, Int)),
    status: TransactionStatus,
  )
}

pub type TransactionFilter {
  TransactionFilter(
    account_id: Option(String),
    tx_type: Option(TransactionType),
    from_ns: Option(Int),
    to_ns: Option(Int),
  )
}

pub type AccountBalance {
  AccountBalance(
    account_id: String,
    balances_cents: Dict(String, Int),
    transaction_count: Int,
  )
}

pub fn tx_type_to_string(tx_type: TransactionType) -> String {
  case tx_type {
    Deposit -> "deposit"
    Withdrawal -> "withdrawal"
    Transfer -> "transfer"
  }
}

pub fn tx_type_from_string(value: String) -> Result(TransactionType, Nil) {
  case value {
    "deposit" -> Ok(Deposit)
    "withdrawal" -> Ok(Withdrawal)
    "transfer" -> Ok(Transfer)
    _ -> Error(Nil)
  }
}

pub fn tx_status_to_string(status: TransactionStatus) -> String {
  case status {
    Pending -> "pending"
    Completed -> "completed"
    Failed -> "failed"
  }
}

pub fn tx_status_from_string(value: String) -> Result(TransactionStatus, Nil) {
  case value {
    "pending" -> Ok(Pending)
    "completed" -> Ok(Completed)
    "failed" -> Ok(Failed)
    _ -> Error(Nil)
  }
}

/// Converts exact integer cents to a JSON number.
/// All arithmetic happens on arbitrary-precision Int cents before conversion,
/// preventing floating-point drift (e.g. 10 + 20 = 30 -> 0.3).
pub fn cents_to_json_number(cents: Int) -> Json {
  json.float(int.to_float(cents) /. 100.0)
}

pub fn to_json(tx: Transaction) -> Json {
  json.object([
    #("id", json.string(tx.id)),
    #("fromAccount", json.nullable(tx.from_account, json.string)),
    #("toAccount", json.nullable(tx.to_account, json.string)),
    #("amount", cents_to_json_number(tx.amount_cents)),
    #("currency", json.string(tx.currency)),
    #("type", json.string(tx_type_to_string(tx.tx_type))),
    #("timestamp", json.string(tx.timestamp)),
    #("status", json.string(tx_status_to_string(tx.status))),
  ])
}

pub fn list_to_json(transactions: List(Transaction)) -> Json {
  json.array(transactions, to_json)
}

pub fn validation_errors_to_json(errors: List(ValidationError)) -> Json {
  json.object([
    #("error", json.string("Validation failed")),
    #(
      "details",
      json.array(errors, fn(err) {
        json.object([
          #("field", json.string(err.field)),
          #("message", json.string(err.message)),
        ])
      }),
    ),
  ])
}

pub fn account_balance_to_json(balance: AccountBalance) -> Json {
  let sorted_balances =
    balance.balances_cents
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(entry) { #(entry.0, cents_to_json_number(entry.1)) })

  json.object([
    #("accountId", json.string(balance.account_id)),
    #("balances", json.object(sorted_balances)),
    #("transactionCount", json.int(balance.transaction_count)),
  ])
}
