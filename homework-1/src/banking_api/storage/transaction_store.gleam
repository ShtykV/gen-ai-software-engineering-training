import banking_api/models/transaction.{type Transaction}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/option.{type Option}
import gleam/result

const call_timeout_ms = 5000

pub opaque type StoreMessage {
  Insert(tx: Transaction, reply: Subject(Transaction))
  GetById(id: String, reply: Subject(Option(Transaction)))
  ListAll(reply: Subject(List(Transaction)))
}

type StoreState {
  StoreState(by_id: Dict(String, Transaction), items: List(Transaction))
}

/// Starts a type-safe OTP Actor holding in-memory transactions.
pub fn start() -> Result(Subject(StoreMessage), actor.StartError) {
  actor.new(StoreState(by_id: dict.new(), items: []))
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

fn handle_message(
  state: StoreState,
  message: StoreMessage,
) -> actor.Next(StoreState, StoreMessage) {
  case message {
    Insert(tx, reply) -> {
      let next_state =
        StoreState(
          by_id: dict.insert(state.by_id, tx.id, tx),
          items: [tx, ..state.items],
        )
      process.send(reply, tx)
      actor.continue(next_state)
    }
    GetById(id, reply) -> {
      let found = case dict.get(state.by_id, id) {
        Ok(tx) -> option.Some(tx)
        Error(_) -> option.None
      }
      process.send(reply, found)
      actor.continue(state)
    }
    ListAll(reply) -> {
      process.send(reply, state.items)
      actor.continue(state)
    }
  }
}

pub fn insert(store: Subject(StoreMessage), tx: Transaction) -> Transaction {
  process.call(store, call_timeout_ms, fn(reply) { Insert(tx, reply) })
}

pub fn get_by_id(
  store: Subject(StoreMessage),
  id: String,
) -> Option(Transaction) {
  process.call(store, call_timeout_ms, fn(reply) { GetById(id, reply) })
}

pub fn list_all(store: Subject(StoreMessage)) -> List(Transaction) {
  process.call(store, call_timeout_ms, ListAll)
}
