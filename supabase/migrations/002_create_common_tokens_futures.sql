-- ----------------------------------------------------------------
-- common_tokens_futures
-- Populated weekly by the MEXC Futures / Jupiter Common Token
-- Discovery workflow. Stores tokens confirmed on both MEXC futures
-- (contract.mexc.com) and Jupiter, with prices within 5%.
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS common_tokens_futures (
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

CREATE INDEX IF NOT EXISTS idx_common_tokens_futures_symbol ON common_tokens_futures (symbol);
