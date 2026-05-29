-- ----------------------------------------------------------------
-- spread_scans_futures
-- One row per futures scanner run (every 2 minutes).
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spread_scans_futures (
  id               BIGSERIAL   PRIMARY KEY,
  scanned_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  tokens_compared  INTEGER     NOT NULL DEFAULT 0,
  alerts_count     INTEGER     NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_spread_scans_futures_scanned_at ON spread_scans_futures (scanned_at DESC);

-- ----------------------------------------------------------------
-- spread_alerts_futures
-- Individual spread opportunities (≥5%) between MEXC Futures
-- and Jupiter detected per scan.
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spread_alerts_futures (
  id              BIGSERIAL   PRIMARY KEY,
  scan_id         BIGINT      REFERENCES spread_scans_futures(id) ON DELETE CASCADE,
  scanned_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  symbol          TEXT        NOT NULL,
  mint            TEXT        NOT NULL,
  mexc_price      NUMERIC     NOT NULL,
  jup_price       NUMERIC     NOT NULL,
  spread_pct      NUMERIC     NOT NULL,
  abs_spread_pct  NUMERIC     NOT NULL,
  direction       TEXT        NOT NULL,  -- 'Buy JUP -> Sell MEXC Futures' or 'Buy MEXC Futures -> Sell JUP'
  exchanges       TEXT        NOT NULL DEFAULT 'MEXC Futures/Jupiter'
);

CREATE INDEX IF NOT EXISTS idx_spread_alerts_futures_scanned_at  ON spread_alerts_futures (scanned_at DESC);
CREATE INDEX IF NOT EXISTS idx_spread_alerts_futures_symbol      ON spread_alerts_futures (symbol);
CREATE INDEX IF NOT EXISTS idx_spread_alerts_futures_abs_spread  ON spread_alerts_futures (abs_spread_pct DESC);
