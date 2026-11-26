import banking_api/models/transaction.{
  Completed, Deposit, Failed, Pending, TransactionFilter, Transfer,
  ValidatedCreateInput, Withdrawal,
}
import banking_api/services/transaction_service
import banking_api/storage/transaction_store
import banking_api/validators/transaction_validator
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

const jan_10_ns = 1_768_003_200_000_000_000

const jan_15_ns = 1_768_435_200_000_000_000

const jan_20_ns = 1_768_867_200_000_000_000

pub fn create_and_get_transaction_by_id_test() {
  let assert Ok(store) = transaction_store.start()

  let input =
    ValidatedCreateInput(
      from_account: Some("ACC-12345"),
      to_account: Some("ACC-67890"),
      amount_cents: 10_050,
      currency: "USD",
      tx_type: Transfer,
      timestamp: None,
      status: Completed,
    )

  let created =
    transaction_service.create_transaction(store, input, jan_15_ns)

  string.starts_with(created.id, "TXN-") |> should.be_true
  created.amount_cents |> should.equal(10_050)
  created.timestamp_ns |> should.equal(jan_15_ns)

  transaction_service.get_transaction(store, created.id)
  |> should.equal(Ok(created))

  transaction_service.get_transaction(store, "TXN-MISSING")
  |> should.equal(Error(Nil))
}

pub fn list_transactions_combines_filters_and_sorts_newest_first_test() {
  let assert Ok(store) = transaction_store.start()

  let t1 =
    transaction_service.create_transaction(
      store,
      ValidatedCreateInput(
        from_account: None,
        to_account: Some("ACC-11111"),
        amount_cents: 50_000,
        currency: "USD",
        tx_type: Deposit,
        timestamp: Some(#("2026-01-10T00:00:00Z", jan_10_ns)),
        status: Completed,
      ),
      jan_10_ns,
    )

  let t2 =
    transaction_service.create_transaction(
      store,
      ValidatedCreateInput(
        from_account: Some("ACC-11111"),
        to_account: Some("ACC-22222"),
        amount_cents: 12_500,
        currency: "USD",
        tx_type: Transfer,
        timestamp: Some(#("2026-01-15T00:00:00Z", jan_15_ns)),
        status: Completed,
      ),
      jan_15_ns,
    )

  let _t3 =
    transaction_service.create_transaction(
      store,
      ValidatedCreateInput(
        from_account: Some("ACC-22222"),
        to_account: None,
        amount_cents: 5000,
        currency: "EUR",
        tx_type: Withdrawal,
        timestamp: Some(#("2026-01-20T00:00:00Z", jan_20_ns)),
        status: Completed,
      ),
      jan_20_ns,
    )

  // All transactions sorted newest first
  let all =
    transaction_service.list_transactions(
      store,
      TransactionFilter(None, None, None, None),
    )
  list.length(all) |> should.equal(3)
  let assert [first, ..] = all
  first.timestamp_ns |> should.equal(jan_20_ns)

  // Filter by accountId matches both fromAccount and toAccount
  let for_acc1 =
    transaction_service.list_transactions(
      store,
      TransactionFilter(Some("ACC-11111"), None, None, None),
    )
  list.map(for_acc1, fn(t) { t.id }) |> should.equal([t2.id, t1.id])

  // Combined filter: accountId + type + date range
  let assert Ok(filter) =
    transaction_validator.validate_history_filters([
      #("accountId", "ACC-22222"),
      #("type", "transfer"),
      #("from", "2026-01-14"),
      #("to", "2026-01-16"),
    ])
  let filtered = transaction_service.list_transactions(store, filter)
  list.map(filtered, fn(t) { t.id }) |> should.equal([t2.id])
}

pub fn multi_currency_balance_exact_cents_and_overdraft_test() {
  let assert Ok(store) = transaction_store.start()

  // 0.10 + 0.20 USD deposit (exact cents -> 30 cents, zero float drift)
  let _ =
    transaction_service.create_transaction(
      store,
      ValidatedCreateInput(
        None,
        Some("ACC-12345"),
        10,
        "USD",
        Deposit,
        None,
        Completed,
      ),
      jan_10_ns,
    )
  let _ =
    transaction_service.create_transaction(
      store,
      ValidatedCreateInput(
        None,
        Some("ACC-12345"),
        20,
        "USD",
        Deposit,
        None,
        Completed,
      ),
      jan_10_ns,
    )
  // Overdraft transfer out in EUR (-100.50 EUR)
  let _ =
    transaction_service.create_transaction(
      store,
      ValidatedCreateInput(
        Some("ACC-12345"),
        Some("ACC-67890"),
        10_050,
        "EUR",
        Transfer,
        None,
        Completed,
      ),
      jan_15_ns,
    )
  // Pending and failed transactions do NOT alter balance
  let _ =
    transaction_service.create_transaction(
      store,
      ValidatedCreateInput(
        None,
        Some("ACC-12345"),
        99_900,
        "USD",
        Deposit,
        None,
        Pending,
      ),
      jan_15_ns,
    )
  let _ =
    transaction_service.create_transaction(
      store,
      ValidatedCreateInput(
        Some("ACC-12345"),
        None,
        50_000,
        "USD",
        Withdrawal,
        None,
        Failed,
      ),
      jan_20_ns,
    )

  let assert Ok(bal) =
    transaction_service.get_account_balance(store, "ACC-12345", None)
  bal.account_id |> should.equal("ACC-12345")
  bal.transaction_count |> should.equal(5)
  dict.get(bal.balances_cents, "USD") |> should.equal(Ok(30))
  dict.get(bal.balances_cents, "EUR") |> should.equal(Ok(-10_050))

  // Recipient ACC-67890 received +100.50 EUR
  let assert Ok(recipient) =
    transaction_service.get_account_balance(store, "ACC-67890", Some("EUR"))
  dict.get(recipient.balances_cents, "EUR") |> should.equal(Ok(10_050))
  dict.size(recipient.balances_cents) |> should.equal(1)

  // Currency filter for currency with no activity on an existing account -> 0
  let assert Ok(zero_gbp) =
    transaction_service.get_account_balance(store, "ACC-67890", Some("GBP"))
  dict.get(zero_gbp.balances_cents, "GBP") |> should.equal(Ok(0))
}

pub fn pending_only_account_exists_and_unknown_account_returns_error_test() {
  let assert Ok(store) = transaction_store.start()

  let _ =
    transaction_service.create_transaction(
      store,
      ValidatedCreateInput(
        None,
        Some("ACC-PEND1"),
        5000,
        "USD",
        Deposit,
        None,
        Pending,
      ),
      jan_15_ns,
    )

  let assert Ok(bal) =
    transaction_service.get_account_balance(store, "ACC-PEND1", None)
  bal.transaction_count |> should.equal(1)
  dict.get(bal.balances_cents, "USD") |> should.equal(Ok(0))

  transaction_service.get_account_balance(store, "ACC-NOPE1", None)
  |> should.equal(Error(Nil))
}
