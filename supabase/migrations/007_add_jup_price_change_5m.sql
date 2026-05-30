-- ----------------------------------------------------------------
-- Migration 007 — Add jup_price_change_5m to alert tables
--
-- Context: when a spread is detected, a separate call to
-- api.jup.ag/ultra/v1/search?query={mint}&mode=strict fetches
-- stats5m.priceChange for each token. This enriches alerts with
-- Jupiter's 5-minute price momentum, useful for filtering
-- actionable opportunities from pump artifacts.
-- ----------------------------------------------------------------

ALTER TABLE public.spread_alerts
  ADD COLUMN IF NOT EXISTS jup_price_change_5m real;

ALTER TABLE public.spread_alerts_futures
  ADD COLUMN IF NOT EXISTS jup_price_change_5m real;
