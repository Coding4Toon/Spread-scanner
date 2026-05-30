-- ----------------------------------------------------------------
-- Migration 008 — Alert deduplication trigger + column rename
--
-- Context: spread_alerts was accumulating ~7 identical rows/minute
-- per symbol (same spread open for hours). This migration:
-- 1. Renames jup_price_change_5m → jup_price_change (value comes
--    from best available timeframe, not always 5m for small caps)
-- 2. Adds BEFORE INSERT triggers that skip inserts when the same
--    symbol was alerted in the last 5 minutes (dedup window).
--    Updated in migration 009 to also allow alerts on ≥2% spread change.
-- ----------------------------------------------------------------

TRUNCATE TABLE spread_alerts CASCADE;
TRUNCATE TABLE spread_alerts_futures CASCADE;

ALTER TABLE public.spread_alerts
  RENAME COLUMN jup_price_change_5m TO jup_price_change;

ALTER TABLE public.spread_alerts_futures
  RENAME COLUMN jup_price_change_5m TO jup_price_change;

CREATE OR REPLACE FUNCTION dedup_spread_alert()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM spread_alerts
    WHERE symbol = NEW.symbol
      AND scanned_at > NEW.scanned_at - INTERVAL '5 minutes'
  ) THEN
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_dedup_spread_alerts
BEFORE INSERT ON spread_alerts
FOR EACH ROW EXECUTE FUNCTION dedup_spread_alert();

CREATE OR REPLACE FUNCTION dedup_spread_alert_futures()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM spread_alerts_futures
    WHERE symbol = NEW.symbol
      AND scanned_at > NEW.scanned_at - INTERVAL '5 minutes'
  ) THEN
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_dedup_spread_alerts_futures
BEFORE INSERT ON spread_alerts_futures
FOR EACH ROW EXECUTE FUNCTION dedup_spread_alert_futures();
