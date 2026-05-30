-- ----------------------------------------------------------------
-- Migration 006 — Auto-prune spread_scans + FK CASCADE
--
-- Context: spread_scans and spread_scans_futures grew unboundedly
-- (one row per scan cycle = thousands/day). Keep only the last 50
-- per group_id. Cascade deletes to spread_alerts so pruned scans
-- also clean up their alerts automatically.
--
-- Also: Log Scan node moved AFTER Has Spreads? check in n8n,
-- so scans are only logged when spreads are found (~5% of cycles).
-- ----------------------------------------------------------------

-- Fix FK to CASCADE on delete
ALTER TABLE public.spread_alerts
  DROP CONSTRAINT spread_alerts_scan_id_fkey,
  ADD CONSTRAINT spread_alerts_scan_id_fkey
    FOREIGN KEY (scan_id) REFERENCES public.spread_scans(id) ON DELETE CASCADE;

ALTER TABLE public.spread_alerts_futures
  DROP CONSTRAINT spread_alerts_futures_scan_id_fkey,
  ADD CONSTRAINT spread_alerts_futures_scan_id_fkey
    FOREIGN KEY (scan_id) REFERENCES public.spread_scans_futures(id) ON DELETE CASCADE;

-- Auto-prune: keep last 50 rows per group_id after each insert
CREATE OR REPLACE FUNCTION prune_spread_scans()
RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM spread_scans
  WHERE group_id = NEW.group_id
    AND id NOT IN (
      SELECT id FROM spread_scans
      WHERE group_id = NEW.group_id
      ORDER BY scanned_at DESC
      LIMIT 50
    );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_prune_spread_scans ON spread_scans;
CREATE TRIGGER trigger_prune_spread_scans
AFTER INSERT ON spread_scans
FOR EACH ROW EXECUTE FUNCTION prune_spread_scans();

CREATE OR REPLACE FUNCTION prune_spread_scans_futures()
RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM spread_scans_futures
  WHERE group_id = NEW.group_id
    AND id NOT IN (
      SELECT id FROM spread_scans_futures
      WHERE group_id = NEW.group_id
      ORDER BY scanned_at DESC
      LIMIT 50
    );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_prune_spread_scans_futures ON spread_scans_futures;
CREATE TRIGGER trigger_prune_spread_scans_futures
AFTER INSERT ON spread_scans_futures
FOR EACH ROW EXECUTE FUNCTION prune_spread_scans_futures();
