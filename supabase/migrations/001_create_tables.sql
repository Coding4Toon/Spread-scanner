-- ============================================================
-- Spread Scanner — Supabase Schema
-- Project: ymwjfvtqtgtfqfiojsyx (ap-southeast-1)
-- ============================================================

-- ----------------------------------------------------------------
-- common_tokens
-- Populated weekly by the Common Token Discovery workflow.
-- Stores tokens confirmed to exist on both MEXC and Jupiter
-- with matching prices (within 5%) to avoid false symbol matches.
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS common_tokens (
  symbol          TEXT        NOT NULL,
  mint            TEXT        NOT NULL,
  name            TEXT,
  decimals        INTEGER,
  mexc_price      NUMERIC,
  jup_price       NUMERIC,
  jup_volume_24h  NUMERIC     DEFAULT 0,
  jup_liquidity   NUMERIC     DEFAULT 0,
  tags            TEXT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (mint)
);

CREATE INDEX IF NOT EXISTS idx_common_tokens_symbol ON common_tokens (symbol);

-- ----------------------------------------------------------------
-- spread_scans
-- One row per scanner run (every 2 minutes).
-- Records how many tokens were compared and how many alerts fired.
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spread_scans (
  id               BIGSERIAL   PRIMARY KEY,
  scanned_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  tokens_compared  INTEGER     NOT NULL DEFAULT 0,
  alerts_count     INTEGER     NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_spread_scans_scanned_at ON spread_scans (scanned_at DESC);

-- ----------------------------------------------------------------
-- spread_alerts
-- Individual spread opportunities (≥5%) detected per scan.
-- scan_id references the spread_scans row for that run.
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spread_alerts (
  id              BIGSERIAL   PRIMARY KEY,
  scan_id         BIGINT      REFERENCES spread_scans(id) ON DELETE CASCADE,
  scanned_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  symbol          TEXT        NOT NULL,
  mint            TEXT        NOT NULL,
  mexc_price      NUMERIC     NOT NULL,
  jup_price       NUMERIC     NOT NULL,
  spread_pct      NUMERIC     NOT NULL,
  abs_spread_pct  NUMERIC     NOT NULL,
  direction       TEXT        NOT NULL,  -- 'Buy JUP -> Sell MEXC' or 'Buy MEXC -> Sell JUP'
  exchanges       TEXT        NOT NULL DEFAULT 'MEXC/Jupiter'
);

CREATE INDEX IF NOT EXISTS idx_spread_alerts_scanned_at   ON spread_alerts (scanned_at DESC);
CREATE INDEX IF NOT EXISTS idx_spread_alerts_symbol       ON spread_alerts (symbol);
CREATE INDEX IF NOT EXISTS idx_spread_alerts_abs_spread   ON spread_alerts (abs_spread_pct DESC);
