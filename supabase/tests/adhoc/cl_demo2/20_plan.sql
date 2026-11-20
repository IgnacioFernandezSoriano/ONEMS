-- Carrier Link DEMO2 synthetic test, phase "setup" step b (WRITES; one transaction; idempotent).
-- Plan "Carrier Link DEMO" (Carrier A / A STANDARD), 2026-11-02 .. 2026-11-29, close_lag_days 3, oversampling 2.
-- Quotas only on the two past ISO weeks 2026-W45 (Nov 2-8) and 2026-W46 (Nov 9-15), 18 samples:
--   New York -> Baltimore    4 + 4   (standard 4 days, equivalence +1 day)
--   Baltimore -> New York    3 + 3   (standard 4 days, equivalence +1 day)
--   New York -> Philadelphia 2 + 2   (NO A STANDARD standard -> missing_standard alert, R18)
-- Both weeks are due once period_end + 3 <= local date (W46: from 2026-11-18). end_date is kept after today on purpose:
-- the emitter closes a plan when end_date + close_lag_days has passed and no quota is pending/open, and a closed plan
-- never re-asks undone quotas (needed by run.sh undo-test). Weeks W47/W48 have no quota.
DO $$
DECLARE
  c_acc  constant uuid := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  c_plan constant uuid := 'c1de2000-0000-4000-8000-0000000000a1';
  c_ny   constant text := 'f86f46c1-98dd-4ec1-9cab-d435856c3125';
  c_bal  constant text := '9ebc9d84-e121-42bf-a163-e8726448b796';
  c_phl  constant text := 'a47bbac3-0edb-46a5-8bd0-cb51dd70200d';
  v_status text;
BEGIN
  IF (SELECT slug FROM public.accounts WHERE id = c_acc) IS DISTINCT FROM 'DEMO2' THEN
    RAISE EXCEPTION 'GUARD: account % is not DEMO2', c_acc;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cl_feeds WHERE id = 'c1de2000-0000-4000-8000-0000000000f1') THEN
    RAISE EXCEPTION 'GUARD: run 10_points_feed.sql first';
  END IF;

  INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date,
                               status, close_lag_days, oversampling_factor, feed_id, feed_diagnosis)
  VALUES (c_plan, c_acc, 'Carrier Link DEMO', '856b4a5c-1716-4110-ac5e-0d7c909b9237', '8325a692-7e1c-40a6-9a54-59527d19634f',
          18, DATE '2026-11-02', DATE '2026-11-29', 'draft', 3, 2, 'c1de2000-0000-4000-8000-0000000000f1', false)
  ON CONFLICT (id) DO NOTHING;

  SELECT status INTO v_status FROM public.cl_plans WHERE id = c_plan;
  IF v_status = 'draft' THEN
    PERFORM public.cl_plan_set_quotas(c_plan, jsonb_build_array(
      jsonb_build_object('origin_city_id', c_ny,  'destination_city_id', c_bal, 'iso_year', 2026, 'iso_week', 45, 'samples', 4),
      jsonb_build_object('origin_city_id', c_ny,  'destination_city_id', c_bal, 'iso_year', 2026, 'iso_week', 46, 'samples', 4),
      jsonb_build_object('origin_city_id', c_bal, 'destination_city_id', c_ny,  'iso_year', 2026, 'iso_week', 45, 'samples', 3),
      jsonb_build_object('origin_city_id', c_bal, 'destination_city_id', c_ny,  'iso_year', 2026, 'iso_week', 46, 'samples', 3),
      jsonb_build_object('origin_city_id', c_ny,  'destination_city_id', c_phl, 'iso_year', 2026, 'iso_week', 45, 'samples', 2),
      jsonb_build_object('origin_city_id', c_ny,  'destination_city_id', c_phl, 'iso_year', 2026, 'iso_week', 46, 'samples', 2)));
    -- R16: refuses if a city/role has no active carrier point.
    PERFORM public.cl_plan_activate(c_plan);
  END IF;
END $$;

SELECT jsonb_build_object(
  'plan', (SELECT jsonb_build_object('id', id, 'name', plan_name, 'status', status, 'start', start_date, 'end', end_date,
                                     'close_lag_days', close_lag_days, 'oversampling', oversampling_factor)
             FROM public.cl_plans WHERE id = 'c1de2000-0000-4000-8000-0000000000a1'),
  'quotas', (SELECT jsonb_agg(jsonb_build_object('route', o.name || ' -> ' || d.name, 'week', q.iso_year || '-W' || q.iso_week,
                                                 'planned', q.samples_planned, 'status', q.status) ORDER BY q.iso_week, o.name, d.name)
               FROM public.cl_plan_quotas q JOIN public.cities o ON o.id = q.origin_city_id JOIN public.cities d ON d.id = q.destination_city_id
              WHERE q.plan_id = 'c1de2000-0000-4000-8000-0000000000a1'),
  'missing_points', (SELECT count(*) FROM public.cl_plan_missing_points('c1de2000-0000-4000-8000-0000000000a1')),
  'missing_standards', (SELECT count(*) FROM public.cl_plan_missing_standards('c1de2000-0000-4000-8000-0000000000a1'))
) AS step_b;
