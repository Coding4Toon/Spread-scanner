-- ----------------------------------------------------------------
-- Migration 004 — Parallelisation: add group_id to token and scan tables
--
-- Context: split 1 workflow (30s, all tokens) into 12 parallel workflows
-- (5s, ~10 tokens each) for faster arbitrage detection.
-- Spot:    7 groups of ~10-11 tokens (73 total)
-- Futures: 5 groups of ~10-11 tokens (53 total)
-- ----------------------------------------------------------------

-- Add group_id to token tables
ALTER TABLE common_tokens         ADD COLUMN IF NOT EXISTS group_id INTEGER;
ALTER TABLE common_tokens_futures  ADD COLUMN IF NOT EXISTS group_id INTEGER;

-- Assign spot tokens to groups 1-7 (alphabetical order, ~11 per group)
UPDATE common_tokens ct
SET group_id = sub.grp
FROM (
  SELECT symbol,
    CEIL(ROW_NUMBER() OVER (ORDER BY symbol)::numeric / 11) AS grp
  FROM common_tokens
) sub
WHERE ct.symbol = sub.symbol;

-- Assign futures tokens to groups 1-5 (alphabetical order, ~11 per group)
UPDATE common_tokens_futures ct
SET group_id = sub.grp
FROM (
  SELECT symbol,
    CEIL(ROW_NUMBER() OVER (ORDER BY symbol)::numeric / 11) AS grp
  FROM common_tokens_futures
) sub
WHERE ct.symbol = sub.symbol;

-- Add group_id to scan log tables (for analytics per group)
ALTER TABLE spread_scans         ADD COLUMN IF NOT EXISTS group_id INTEGER;
ALTER TABLE spread_scans_futures  ADD COLUMN IF NOT EXISTS group_id INTEGER;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_common_tokens_group          ON common_tokens(group_id);
CREATE INDEX IF NOT EXISTS idx_common_tokens_futures_group  ON common_tokens_futures(group_id);
CREATE INDEX IF NOT EXISTS idx_spread_scans_group           ON spread_scans(group_id);
CREATE INDEX IF NOT EXISTS idx_spread_scans_futures_group   ON spread_scans_futures(group_id);
