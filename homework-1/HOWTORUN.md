# ▶️ How to Run — Banking Transactions API (Gleam + Wisp)

Step-by-step instructions to set up **Erlang/OTP**, **Gleam**, and **rebar3**, run the automated test suite, start the API server, and execute demo requests.

---

## 1. Prerequisites

- **Erlang/OTP** 26+ (tested with OTP 29.1.3)
- **Gleam** 1.14+ (tested with Gleam 1.19.2)
- **rebar3** (required by Gleam to compile Mist's Erlang dependency `hpack_erl`)
- `curl` (pre-installed on Windows 10/11, macOS, and Linux)

### Option A: Windows (Portable ZIPs — No Admin / UAC Required)

```powershell
# 1. Download official portable archives
curl.exe -fsSL -o "$env:TEMP\gleam.zip" https://github.com/gleam-lang/gleam/releases/download/v1.19.2/gleam-v1.19.2-x86_64-pc-windows-msvc.zip
curl.exe -fsSL -o "$env:TEMP\otp.zip" https://github.com/erlang/otp/releases/download/OTP-29.1.3/otp_win64_29.1.3.zip

# 2. Extract to %LOCALAPPDATA%\Programs
New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\Programs\gleam", "$env:LOCALAPPDATA\Programs\erlang" | Out-Null
tar.exe -xf "$env:TEMP\gleam.zip" -C "$env:LOCALAPPDATA\Programs\gleam"
tar.exe -xf "$env:TEMP\otp.zip" -C "$env:LOCALAPPDATA\Programs\erlang"

# 3. Install rebar3 escript + rebar3.cmd wrapper
curl.exe -fsSL -o "$env:LOCALAPPDATA\Programs\erlang\bin\rebar3" https://github.com/erlang/rebar3/releases/latest/download/rebar3
Set-Content -Path "$env:LOCALAPPDATA\Programs\erlang\bin\rebar3.cmd" -Value "@echo off`r`nescript.exe `"%~dp0rebar3`" %*" -Encoding Ascii

# 4. Add Gleam and Erlang bin to User PATH (restart terminal afterwards)
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
[Environment]::SetEnvironmentVariable('Path', "$userPath;$env:LOCALAPPDATA\Programs\gleam;$env:LOCALAPPDATA\Programs\erlang\bin", 'User')
```

*(Alternatively, on Windows with admin rights, `winget install --id=Erlang.ErlangOTP -e` and `winget install --id=Gleam.Gleam -e`, followed by installing `rebar3.cmd` into Erlang's `bin/` directory.)*

### Option B: macOS (Homebrew)

```bash
brew install erlang gleam rebar3
```

### Option C: Linux (Debian / Ubuntu / asdf / mise)

```bash
# Using mise (recommended)
mise use -g erlang@latest gleam@latest rebar@latest
```

### Verify Installation

```bash
gleam --version
erl -eval 'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().' -noshell
```

---

## 2. Run Automated Tests

All dependencies are locked in `manifest.toml` and downloaded automatically by Gleam on first build:

```bash
cd homework-1
gleam test
```

Expected output:
```text
  Compiling banking_api
   Compiled in 0.35s
    Running banking_api_test.main
............................
28 passed, no failures
```

---

## 3. Start the API Server

### Quick Start with Sample Seed Data (`demo/run.*`)

**Windows (PowerShell or CMD):**
```powershell
cd homework-1
.\demo\run.bat
```

**macOS / Linux / Git Bash:**
```bash
cd homework-1
chmod +x demo/run.sh demo/sample-requests.sh
./demo/run.sh
```

Both scripts start the server on **`http://localhost:3000`** with `SEED_DATA=true` (loading 7 multi-currency sample transactions from `demo/sample-data.json`).

### Start with an Empty Store (Default)

```bash
cd homework-1
gleam run
```

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PORT` | `3000` | HTTP port to bind |
| `SEED_DATA` | `false` | Set `true` to seed from `SEED_FILE` at startup |
| `SEED_FILE` | `demo/sample-data.json` | Path to JSON array seed file |
| `RATE_LIMIT_REQUESTS` | `100` | Max requests per IP within the sliding window |
| `RATE_LIMIT_WINDOW_SECONDS` | `60` | Sliding window duration in seconds |
| `TRUST_PROXY` | `false` | Set `true` behind a reverse proxy to read client IP from `X-Forwarded-For` |

---

## 4. Test the Running API

### Option 1: Run the Demo Script

```bash
cd homework-1
./demo/sample-requests.sh
```

### Option 2: VS Code REST Client / JetBrains HTTP Client
Open [`demo/sample-requests.http`](demo/sample-requests.http) and click **Send Request** on any section.

### Option 3: Manual `curl` Commands

```bash
# 1. Create a transfer transaction (201 Created)
curl -X POST http://localhost:3000/transactions \
  -H "Content-Type: application/json" \
  -d '{
    "fromAccount": "ACC-12345",
    "toAccount": "ACC-67890",
    "amount": 100.50,
    "currency": "USD",
    "type": "transfer"
  }'

# 2. List all transactions (newest first)
curl http://localhost:3000/transactions

# 3. Filter transactions (account + type + date range)
curl "http://localhost:3000/transactions?accountId=ACC-12345&type=transfer&from=2026-01-01&to=2026-12-31"

# 4. Get multi-currency account balance (or add ?currency=USD)
curl http://localhost:3000/accounts/ACC-12345/balance
curl "http://localhost:3000/accounts/ACC-12345/balance?currency=USD"

# 5. Trigger validation error (400 Bad Request)
curl -i -X POST http://localhost:3000/transactions \
  -H "Content-Type: application/json" \
  -d '{"fromAccount":"BAD","amount":-10.123,"currency":"ZZZ","type":"transfer"}'
```

### Testing Rate Limiting (`429 Too Many Requests`)

Start the server with a low threshold (e.g. `RATE_LIMIT_REQUESTS=3`) and send 4 requests:

```powershell
# Windows PowerShell
$env:RATE_LIMIT_REQUESTS = "3"
gleam run
# In a second terminal, run 4 times:
1..4 | ForEach-Object { curl.exe -sS -i http://localhost:3000/health }
```

The 4th request returns `HTTP/1.1 429 Too Many Requests` with `Retry-After` and `X-RateLimit-Remaining: 0`.
