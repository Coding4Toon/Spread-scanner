# CEX/DEX Spread Scanner — MEXC × Jupiter (Solana)

Automated arbitrage opportunity scanner that detects price spreads between **MEXC** (centralized exchange, spot & futures) and **Jupiter** (Solana DEX aggregator). Built as n8n workflows backed by a Supabase database.

---

## How It Works

The system is split into two layers:

### 1. Token Discovery (runs weekly)
Before scanning spreads, the system needs to know which tokens exist on **both** exchanges with the **same underlying asset**. A naive symbol match (e.g. "SOL") can produce false positives if the same ticker maps to different assets. The discovery workflows solve this with a **price sanity filter**: a token is only added to the watchlist if its Jupiter price is within **5%** of the MEXC price at discovery time.

### 2. Spread Scanning (runs every 30 seconds)
The scanners read the pre-validated token list from Supabase, fetch live prices from both exchanges in parallel, and flag any pair where the price difference is **≥ 5%**. Every run is logged, and alerts are saved with direction (which side to buy, which to sell).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Token Discovery (weekly)                     │
│                                                                   │
│  MEXC Tickers ──► Build Symbol Map ──► Jupiter Ultra Search      │
│                                            │                      │
│                          Price filter (<5% diff) ──► Supabase    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   Spread Scanner (every 30s)                     │
│                                                                   │
│  MEXC Tickers ──► Build Price Map ──► Fetch DB Tokens            │
│                                            │                      │
│                          Find Common Tokens (merge)               │
│                                │                                  │
│                    Prepare Batches (50 mints/batch)               │
│                                │                                  │
│                  Fetch Jupiter Prices (price/v3 batch)            │
│                                │                                  │
│                      Calculate Spreads (≥5%)                      │
│                           │         │                             │
│                      Log Scan    Has Spreads?                     │
│                                       │                           │
│                               Save Spread Alerts                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Workflows

### `common-token-discovery.json`
**MEXC Spot / Jupiter — Common Token Discovery**

| Property | Value |
|---|---|
| Trigger | Weekly (Monday 00:00) + manual webhook |
| MEXC endpoint | `api.mexc.com/api/v3/ticker/price` |
| Symbol format | `BTCUSDT` → strip `USDT` (4 chars) |
| Jupiter endpoint | `api.jup.ag/ultra/v1/search` (one request per symbol) |
| Price filter | Reject if Jupiter price differs >5% from MEXC |
| Supabase table | `common_tokens` (upsert on `mint`) |
| Result | ~73 validated spot tokens |

**Why the 5% filter?** Many symbols clash (e.g. "PNUT" can be multiple tokens on Solana). Without price verification, the scanner would compare apples to oranges and generate false alerts.

---

### `futures-common-token-discovery.json`
**MEXC Futures / Jupiter — Common Token Discovery**

Same logic as the spot discovery, adapted for MEXC Futures:

| Property | Value |
|---|---|
| MEXC endpoint | `contract.mexc.com/api/v1/contract/ticker` |
| Symbol format | `BTC_USDT` → strip `_USDT` (5 chars) |
| Response format | `{ success: true, data: [...] }` (wrapped array) |
| Supabase table | `common_tokens_futures` (upsert on `mint`) |
| Result | ~53 validated futures tokens |

---

### `spread-scanner.json`
**CEX/DEX Spread Scanner — MEXC Spot vs Jupiter**

| Property | Value |
|---|---|
| Interval | Every 30 seconds |
| MEXC endpoint | `api.mexc.com/api/v3/ticker/price` |
| Jupiter endpoint | `api.jup.ag/price/v3?ids=mint1,mint2,...` (batch, 50/call) |
| Spread threshold | ≥ 5% |
| Supabase tables | `spread_scans` (audit log), `spread_alerts` (opportunities) |

**Key optimization — batch pricing:** Instead of 73 individual Jupiter calls (~60s), all mints are split into batches of 50 and fetched in 1–2 HTTP calls (~3s total). This is what makes 30-second intervals feasible.

**Node pipeline:**
1. **Schedule Trigger** — fires every 30s
2. **MEXC Tickers** — fetches all ~2400 MEXC spot prices
3. **Build MEXC Price Map** — collapses array into `{ symbol → price }` map (prevents fan-out)
4. **Fetch DB Tokens** — reads `common_tokens` from Supabase
5. **Find Common Tokens** — intersects DB tokens with MEXC price map
6. **Prepare Batches** — groups mints into batches of 50
7. **Fetch Jupiter Prices** — calls `price/v3` batch endpoint per batch
8. **Calculate Spreads** — merges all batch results, computes spread %, filters ≥5%
9. **Log Scan** — inserts row into `spread_scans` (always runs)
10. **Has Spreads?** — IF node: branches if `count > 0`
11. **Save Spread Alerts** — bulk-inserts opportunities into `spread_alerts`

**Spread formula:**
```
spreadPct = ((mexcPrice - jupPrice) / jupPrice) * 100

If positive → MEXC is more expensive → Buy JUP, Sell MEXC
If negative → JUP is more expensive  → Buy MEXC, Sell JUP
```

---

### `spread-scanner-futures.json`
**CEX/DEX Spread Scanner — MEXC Futures vs Jupiter**

Identical pipeline to the spot scanner, with these differences:

| Property | Value |
|---|---|
| MEXC endpoint | `contract.mexc.com/api/v1/contract/ticker` |
| Symbol format | Strip `_USDT` (5 chars), read `lastPrice` field |
| DB table | `common_tokens_futures` |
| Supabase tables | `spread_scans_futures`, `spread_alerts_futures` |
| Direction labels | `Buy JUP -> Sell MEXC Futures` / `Buy MEXC Futures -> Sell JUP` |

---

## Database Schema

```
Supabase project: ymwjfvtqtgtfqfiojsyx (ap-southeast-1)
```

### `common_tokens`
Validated spot tokens that exist on both MEXC and Jupiter.

| Column | Type | Description |
|---|---|---|
| mint | TEXT (PK) | Solana token mint address |
| symbol | TEXT | Ticker (e.g. `SOL`) |
| name | TEXT | Full token name |
| decimals | INTEGER | Token decimals |
| mexc_price | NUMERIC | MEXC price at last discovery |
| jup_price | NUMERIC | Jupiter price at last discovery |
| jup_volume_24h | NUMERIC | 24h volume on Jupiter |
| jup_liquidity | NUMERIC | Liquidity on Jupiter |
| tags | TEXT | Comma-separated Jupiter tags |
| updated_at | TIMESTAMPTZ | Last upsert timestamp |

### `common_tokens_futures`
Same schema as `common_tokens`, for MEXC Futures pairs.

### `spread_scans`
Audit log: one row per spot scanner run.

| Column | Type | Description |
|---|---|---|
| id | BIGSERIAL (PK) | Scan ID |
| scanned_at | TIMESTAMPTZ | When the scan ran |
| tokens_compared | INTEGER | How many tokens were priced |
| alerts_count | INTEGER | How many ≥5% spreads were found |

### `spread_scans_futures`
Same schema as `spread_scans`, for the futures scanner.

### `spread_alerts`
Individual spread opportunities from the spot scanner.

| Column | Type | Description |
|---|---|---|
| id | BIGSERIAL (PK) | Alert ID |
| scan_id | BIGINT (FK) | References `spread_scans.id` |
| scanned_at | TIMESTAMPTZ | Timestamp of the scan |
| symbol | TEXT | Token ticker |
| mint | TEXT | Solana mint address |
| mexc_price | NUMERIC | MEXC price at detection |
| jup_price | NUMERIC | Jupiter price at detection |
| spread_pct | NUMERIC | Signed spread (%) |
| abs_spread_pct | NUMERIC | Absolute spread (%) |
| direction | TEXT | Which side to buy/sell |
| exchanges | TEXT | Always `MEXC/Jupiter` |

### `spread_alerts_futures`
Same schema as `spread_alerts`, with `exchanges = 'MEXC Futures/Jupiter'`.

---

## Setup

### Prerequisites
- [n8n](https://n8n.io) instance (self-hosted or cloud)
- [Supabase](https://supabase.com) project
- [Jupiter API key](https://portal.jup.ag) (for `ultra/v1/search` in discovery workflows)

### 1. Apply database migrations

Run the SQL files in order against your Supabase project:

```sql
-- In Supabase SQL editor, run in order:
supabase/migrations/001_create_tables.sql
supabase/migrations/002_create_common_tokens_futures.sql
supabase/migrations/003_create_spread_futures_tables.sql
```

### 2. Import workflows into n8n

Import all 4 JSON files in this order:

1. `common-token-discovery.json`
2. `futures-common-token-discovery.json`
3. `spread-scanner.json`
4. `spread-scanner-futures.json`

In n8n: **Workflows → Import from file**

### 3. Set your Jupiter API key

In each of the 4 workflows, find any node referencing `YOUR_JUPITER_API_KEY` and replace it with your actual key:

- `common-token-discovery.json` → **Jupiter Ultra Search** node → `x-api-key` header
- `futures-common-token-discovery.json` → **Jupiter Ultra Search** node → `x-api-key` header
- `spread-scanner.json` → **Fetch Jupiter Prices** node → `x-api-key` header
- `spread-scanner-futures.json` → **Fetch Jupiter Prices** node → `x-api-key` header

### 4. Run discovery workflows first

Before activating the scanners, populate the token lists:

1. Activate and manually trigger `common-token-discovery`
2. Activate and manually trigger `futures-common-token-discovery`
3. Verify rows appear in `common_tokens` and `common_tokens_futures`

### 5. Activate scanners

Activate `spread-scanner` and `spread-scanner-futures`. They will start scanning every 30 seconds automatically.

---

## Querying Results

```sql
-- Latest spread alerts (spot)
SELECT symbol, mexc_price, jup_price, spread_pct, direction, scanned_at
FROM spread_alerts
ORDER BY scanned_at DESC, abs_spread_pct DESC
LIMIT 50;

-- Latest spread alerts (futures)
SELECT symbol, mexc_price, jup_price, spread_pct, direction, scanned_at
FROM spread_alerts_futures
ORDER BY scanned_at DESC, abs_spread_pct DESC
LIMIT 50;

-- Scan frequency check
SELECT scanned_at, tokens_compared, alerts_count
FROM spread_scans
ORDER BY scanned_at DESC
LIMIT 10;

-- Top recurring opportunities (spot)
SELECT symbol, COUNT(*) as hit_count, AVG(abs_spread_pct) as avg_spread, MAX(abs_spread_pct) as max_spread
FROM spread_alerts
GROUP BY symbol
ORDER BY hit_count DESC;
```

---

## Performance Notes

| Metric | Value |
|---|---|
| Spot tokens monitored | ~73 |
| Futures tokens monitored | ~53 |
| Jupiter API calls per scan | 1–2 (batch of 50 mints) |
| Typical scan execution time | ~3 seconds |
| Scan interval | 30 seconds |
| MEXC Spot symbols processed | ~2,400 |
| MEXC Futures symbols processed | ~300 |

The batch `price/v3` endpoint is the key to performance. Without it, querying 73 tokens individually via `ultra/v1/search` takes ~60 seconds, making sub-minute intervals impossible.

---

## File Structure

```
spread-scanner/
├── README.md
├── common-token-discovery.json          # Spot token discovery (weekly)
├── futures-common-token-discovery.json  # Futures token discovery (weekly)
├── spread-scanner.json                  # MEXC Spot vs Jupiter (30s)
├── spread-scanner-futures.json          # MEXC Futures vs Jupiter (30s)
└── supabase/
    └── migrations/
        ├── 001_create_tables.sql                  # common_tokens, spread_scans, spread_alerts
        ├── 002_create_common_tokens_futures.sql   # common_tokens_futures
        └── 003_create_spread_futures_tables.sql   # spread_scans_futures, spread_alerts_futures
```
