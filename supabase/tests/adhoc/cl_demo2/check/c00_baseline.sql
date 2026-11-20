-- READ-ONLY. Fingerprint of what the test must NOT change: panelist E2E rows (all accounts and DEMO2, with a hash of
-- DEMO2's panelist on_time / transit values), DEMO2 allocation_plan_details and incidents. run.sh saves it before the
-- setup (out/baseline.json) and compares it in `check`. Other accounts change by real activity (Kenya), so only the
-- DEMO2 values are compared strictly; the all-accounts count is reported as a delta.
SELECT jsonb_build_object(
  'panelist_rows_all', (SELECT count(*) FROM public.one_db WHERE source = 'panelist'),
  'panelist_rows_demo2', (SELECT count(*) FROM public.one_db WHERE source = 'panelist' AND account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'),
  'panelist_hash_demo2', (SELECT md5(COALESCE(string_agg(id::text || ':' || COALESCE(on_time_delivery::text, '-') || ':' ||
                                                         COALESCE(business_transit_days::text, '-') || ':' || COALESCE(total_transit_hours::text, '-'),
                                                         ',' ORDER BY id), ''))
                            FROM public.one_db WHERE source = 'panelist' AND account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'),
  'apd_demo2', (SELECT count(*) FROM public.allocation_plan_details WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'),
  'incidents_demo2', (SELECT count(*) FROM public.incidents WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e')
) AS baseline;
