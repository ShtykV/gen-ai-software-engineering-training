import banking_api/models/transaction.{
  type AccountBalance, type Transaction, type TransactionFilter,
  type ValidatedCreateInput, AccountBalance, Completed, Deposit, Transaction,
  Transfer, Withdrawal,
}
import banking_api/storage/transaction_store.{type StoreMessage}
import banking_api/validators/transaction_validator
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import simplifile
import wisp

pub fn create_transaction(
  store: Subject(StoreMessage),
  input: ValidatedCreateInput,
  now_ns: Int,
) -> Transaction {
  let #(timestamp_str, timestamp_ns) = case input.timestamp {
    Some(pair) -> pair
    None -> #(transaction_validator.ns_to_rfc3339(now_ns), now_ns)
  }

  let tx =
    Transaction(
      id: "TXN-" <> wisp.random_string(8),
      from_account: input.from_account,
      to_account: input.to_account,
      amount_cents: input.amount_cents,
      currency: input.currency,
      tx_type: input.tx_type,
      timestamp: timestamp_str,
      timestamp_ns: timestamp_ns,
      status: input.status,
    )

  transaction_store.insert(store, tx)
}

pub fn get_transaction(
  store: Subject(StoreMessage),
  id: String,
) -> Result(Transaction, Nil) {
  case transaction_store.get_by_id(store, id) {
    Some(tx) -> Ok(tx)
    None -> Error(Nil)
  }
}

pub fn list_transactions(
  store: Subject(StoreMessage),
  filter: TransactionFilter,
) -> List(Transaction) {
  transaction_store.list_all(store)
  |> list.filter(fn(tx) { matches_filter(tx, filter) })
  |> list.sort(fn(a, b) { int.compare(b.timestamp_ns, a.timestamp_ns) })
}

fn matches_filter(tx: Transaction, filter: TransactionFilter) -> Bool {
  let account_ok = case filter.account_id {
    None -> True
    Some(acc) -> tx.from_account == Some(acc) || tx.to_account == Some(acc)
  }

  let type_ok = case filter.tx_type {
    None -> True
    Some(expected) -> tx.tx_type == expected
  }

  let from_ok = case filter.from_ns {
    None -> True
    Some(from_ns) -> tx.timestamp_ns >= from_ns
  }

  let to_ok = case filter.to_ns {
    None -> True
    Some(to_ns) -> tx.timestamp_ns <= to_ns
  }

  account_ok && type_ok && from_ok && to_ok
}

pub fn get_account_balance(
  store: Subject(StoreMessage),
  account_id: String,
  currency_filter: Option(String),
) -> Result(AccountBalance, Nil) {
  let involved =
    transaction_store.list_all(store)
    |> list.filter(fn(tx) {
      tx.from_account == Some(account_id) || tx.to_account == Some(account_id)
    })

  case involved {
    [] -> Error(Nil)
    txs -> {
      let balances =
        list.fold(txs, dict.new(), fn(acc, tx) {
          let current = dict.get(acc, tx.currency) |> result.unwrap(0)
          let delta = balance_delta_for_account(tx, account_id)
          dict.insert(acc, tx.currency, current + delta)
        })

      let final_balances = case currency_filter {
        None -> balances
        Some(code) ->
          dict.from_list([#(code, dict.get(balances, code) |> result.unwrap(0))])
      }

      Ok(AccountBalance(
        account_id: account_id,
        balances_cents: final_balances,
        transaction_count: list.length(txs),
      ))
    }
  }
}

fn balance_delta_for_account(tx: Transaction, account_id: String) -> Int {
  case tx.status {
    Completed ->
      case tx.tx_type {
        Deposit ->
          case tx.to_account == Some(account_id) {
            True -> tx.amount_cents
            False -> 0
          }
        Withdrawal ->
          case tx.from_account == Some(account_id) {
            True -> -tx.amount_cents
            False -> 0
          }
        Transfer -> {
          let incoming = case tx.to_account == Some(account_id) {
            True -> tx.amount_cents
            False -> 0
          }
          let outgoing = case tx.from_account == Some(account_id) {
            True -> -tx.amount_cents
            False -> 0
          }
          incoming + outgoing
        }
      }
    _ -> 0
  }
}

/// Seeds the transaction store from a JSON array file (e.g. demo/sample-data.json).
pub fn seed_from_json_file(
  store: Subject(StoreMessage),
  path: String,
  now_ns: Int,
) -> Result(Int, String) {
  use content <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(_) { "Failed to read seed file: " <> path }),
  )

  let array_decoder = decode.list(decode.dict(decode.string, decode.dynamic))
  use raw_items <- result.try(
    json.parse(content, array_decoder)
    |> result.map_error(fn(_) { "Invalid JSON array in seed file: " <> path }),
  )

  list.try_fold(raw_items, 0, fn(count, fields) {
    case transaction_validator.validate_create_fields(fields) {
      Ok(input) -> {
        let _ = create_transaction(store, input, now_ns)
        Ok(count + 1)
      }
      Error(_) ->
        Error("Invalid transaction entry found in seed file: " <> path)
    }
  })
}
