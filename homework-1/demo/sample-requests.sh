#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"

echo "=== 1. Health Check ==="
curl -sS -i "${BASE_URL}/health"
echo -e "\n"

echo "=== 2. Create Transfer Transaction (201) ==="
CREATED=$(curl -sS -X POST "${BASE_URL}/transactions" \
  -H "Content-Type: application/json" \
  -d '{
    "fromAccount": "ACC-12345",
    "toAccount": "ACC-67890",
    "amount": 100.50,
    "currency": "USD",
    "type": "transfer"
  }')
echo "${CREATED}"
echo ""

echo "=== 3. List All Transactions ==="
curl -sS "${BASE_URL}/transactions"
echo -e "\n"

echo "=== 4. Combined Filter (accountId + type + date range) ==="
curl -sS "${BASE_URL}/transactions?accountId=ACC-12345&type=transfer&from=2026-01-01&to=2026-12-31"
echo -e "\n"

echo "=== 5. Multi-Currency Account Balance ==="
curl -sS "${BASE_URL}/accounts/ACC-12345/balance"
echo -e "\n"

echo "=== 6. Currency-Filtered Account Balance ==="
curl -sS "${BASE_URL}/accounts/ACC-12345/balance?currency=USD"
echo -e "\n"

echo "=== 7. Validation Error (400) ==="
curl -sS -i -X POST "${BASE_URL}/transactions" \
  -H "Content-Type: application/json" \
  -d '{
    "fromAccount": "BAD",
    "toAccount": "ACC-67890",
    "amount": -50.123,
    "currency": "NOPE",
    "type": "transfer"
  }'
echo -e "\n"

echo "=== 8. Not Found (404) ==="
curl -sS -i "${BASE_URL}/accounts/ACC-99999/balance"
echo ""
