-- ----------------------------------------------------------------
-- Migration 005 — RLS policies for all public tables
--
-- Context: 9 tables were exposed without RLS. Enable RLS and add
-- appropriate policies based on usage pattern:
--   - Spread Futures tables: anon SELECT + INSERT (n8n uses anon key)
--   - common_tokens tables: anon SELECT + INSERT + UPDATE (upsert by discovery workflows)
--   - HYPE tables: RLS only, no policies (service_role bypasses RLS)
-- ----------------------------------------------------------------

-- Spread Futures tables (mirror spot pattern)
ALTER TABLE public.spread_scans_futures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spread_alerts_futures ENABLE ROW LEVEL SECURITY;

CREATE POLICY allow_select_spread_scans_futures ON public.spread_scans_futures
  FOR SELECT TO anon USING (true);
CREATE POLICY allow_insert_spread_scans_futures ON public.spread_scans_futures
  FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY allow_select_spread_alerts_futures ON public.spread_alerts_futures
  FOR SELECT TO anon USING (true);
CREATE POLICY allow_insert_spread_alerts_futures ON public.spread_alerts_futures
  FOR INSERT TO anon WITH CHECK (true);

-- common_tokens (token discovery workflows need SELECT + upsert)
ALTER TABLE public.common_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.common_tokens_futures ENABLE ROW LEVEL SECURITY;

CREATE POLICY allow_select_common_tokens ON public.common_tokens
  FOR SELECT TO anon USING (true);
CREATE POLICY allow_insert_common_tokens ON public.common_tokens
  FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY allow_update_common_tokens ON public.common_tokens
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

CREATE POLICY allow_select_common_tokens_futures ON public.common_tokens_futures
  FOR SELECT TO anon USING (true);
CREATE POLICY allow_insert_common_tokens_futures ON public.common_tokens_futures
  FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY allow_update_common_tokens_futures ON public.common_tokens_futures
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- HYPE internal tables: block anon/authenticated, service_role bypasses RLS
ALTER TABLE public.option_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hourly_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backtest_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.option_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.synthetic_regime_results ENABLE ROW LEVEL SECURITY;
