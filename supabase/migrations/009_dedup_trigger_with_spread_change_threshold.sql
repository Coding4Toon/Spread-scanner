-- ----------------------------------------------------------------
-- Migration 009 — Dedup trigger: allow new alert on ≥2% spread change
--
-- Context: migration 008 blocked ALL inserts within 5-minute window.
-- This update adds a threshold: if the spread changes by ≥2% compared
-- to the last alert within the window, a new alert IS created and the
-- 5-minute window resets.
--
-- Logic:
--   no recent alert → allow insert
--   recent alert exists AND |new_spread - last_spread| < 2% → skip
--   recent alert exists AND |new_spread - last_spread| >= 2% → allow
-- ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION dedup_spread_alert()
RETURNS TRIGGER AS $$
DECLARE
  last_spread NUMERIC;
BEGIN
  SELECT spread_pct INTO last_spread
  FROM spread_alerts
  WHERE symbol = NEW.symbol
    AND scanned_at > NEW.scanned_at - INTERVAL '5 minutes'
  ORDER BY scanned_at DESC
  LIMIT 1;

  IF last_spread IS NOT NULL AND ABS(NEW.spread_pct - last_spread) < 2 THEN
    RETURN NULL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dedup_spread_alert_futures()
RETURNS TRIGGER AS $$
DECLARE
  last_spread NUMERIC;
BEGIN
  SELECT spread_pct INTO last_spread
  FROM spread_alerts_futures
  WHERE symbol = NEW.symbol
    AND scanned_at > NEW.scanned_at - INTERVAL '5 minutes'
  ORDER BY scanned_at DESC
  LIMIT 1;

  IF last_spread IS NOT NULL AND ABS(NEW.spread_pct - last_spread) < 2 THEN
    RETURN NULL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
