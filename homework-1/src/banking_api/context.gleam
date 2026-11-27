import banking_api/middleware/rate_limiter.{type RateLimitMessage}
import banking_api/storage/transaction_store.{type StoreMessage}
import gleam/erlang/process.{type Subject}

pub type Context {
  Context(
    store: Subject(StoreMessage),
    rate_limiter: Subject(RateLimitMessage),
    trust_proxy: Bool,
    now_ns: fn() -> Int,
  )
}
