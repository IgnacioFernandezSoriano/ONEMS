-- READ-ONLY. One-row verification of the DEMO2 Carrier Link test after `ingest` (and again after `undo-test`).
-- "expect" holds the pass/fail booleans; run.sh prints them and fails if any is false.
WITH p AS (SELECT 'c1de2000-0000-4000-8000-0000000000a1'::uuid AS plan, 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'::uuid AS acc),
q AS (SELECT q.* FROM public.cl_plan_quotas q, p WHERE q.plan_id = p.plan),
s AS (SELECT s.* FROM public.cl_samples s, p WHERE s.plan_id = p.plan AND s.status = 'active'),
o AS (SELECT o.*, (o.origin_city_name IN ('New York','Baltimore') AND o.destination_city_name IN ('New York','Baltimore')) AS has_std
        FROM public.one_db o, p WHERE o.account_id = p.acc AND o.source = 'carrier'),
lb AS (SELECT b.* FROM public.cl_batches b JOIN public.cl_demands d ON d.id = b.demand_id, p
        WHERE d.plan_id = p.plan AND b.status = 'sampled' ORDER BY b.received_at DESC LIMIT 1),
a AS (SELECT al.* FROM public.cl_alerts al, p WHERE al.plan_id = p.plan),
r AS (SELECT
  (SELECT status FROM public.cl_plans, p WHERE id = p.plan) AS plan_status,
  (SELECT jsonb_object_agg(st, n) FROM (SELECT d.status st, count(*) n FROM public.cl_demands d, p WHERE d.plan_id = p.plan GROUP BY 1) x) AS demands,
  (SELECT jsonb_object_agg(st, n) FROM (SELECT b.status st, count(*) n FROM public.cl_batches b JOIN public.cl_demands d ON d.id = b.demand_id, p
                                         WHERE d.plan_id = p.plan GROUP BY 1) x) AS batches,
  (SELECT sum(samples_planned) FROM q) AS planned,
  (SELECT sum(samples_obtained) FROM q) AS obtained,
  (SELECT jsonb_object_agg(st, n) FROM (SELECT status st, count(*) n FROM q GROUP BY 1) x) AS quotas,
  (SELECT count(*) FROM s) AS samples_active,
  (SELECT count(*) FROM s WHERE possible_misrouting) AS samples_misrouting,
  (SELECT count(*) FROM o) AS onedb_carrier,
  (SELECT count(*) FROM o WHERE cl_sample_id IN (SELECT id FROM s)) AS onedb_linked,
  (SELECT count(*) FROM o WHERE has_std) AS onedb_with_std,
  (SELECT count(*) FROM o WHERE has_std AND on_time_delivery IS NOT NULL AND equivalence_days = 1 AND equivalence_hours = 24
                             AND measured_business_days IS NOT NULL AND business_transit_days = measured_business_days + 1) AS onedb_std_ok,
  (SELECT count(*) FROM o WHERE has_std AND on_time_delivery) AS onedb_on_time,
  (SELECT count(*) FROM o WHERE has_std AND NOT on_time_delivery) AS onedb_late,
  (SELECT count(*) FROM o WHERE NOT has_std) AS onedb_without_std,
  (SELECT count(*) FROM o WHERE NOT has_std AND on_time_delivery IS NULL AND equivalence_days IS NULL AND measured_total_hours IS NOT NULL) AS onedb_nostd_ok,
  (SELECT jsonb_object_agg(t, n) FROM (SELECT alert_type t, count(*) n FROM a GROUP BY 1) x) AS alerts,
  (SELECT count(*) FROM a WHERE alert_type = 'missing_standard' AND details->>'destination_city_id' = 'a47bbac3-0edb-46a5-8bd0-cb51dd70200d') AS alert_missing_std_phl,
  (SELECT jsonb_object_agg(rr, n) FROM (SELECT sc.reject_reason rr, count(DISTINCT sc.item_id) n FROM public.cl_batch_scans sc, lb
                                         WHERE sc.batch_id = lb.id AND sc.status = 'rejected' GROUP BY 1) x) AS rejected_items,
  (SELECT count(*) FROM public.cl_sampling_runs sr, lb WHERE sr.batch_id = lb.id) AS sampling_runs,
  (SELECT sum(sr.samples_selected) FROM public.cl_sampling_runs sr, lb WHERE sr.batch_id = lb.id) AS sampling_selected,
  (SELECT bool_and(sr.population_size >= sr.candidates_valid) FROM public.cl_sampling_runs sr, lb WHERE sr.batch_id = lb.id) AS runs_population_ok,
  (SELECT count(*) FROM lb WHERE raw_payload::text ~ '(recipient_|sender_email)') AS pii_in_raw_payload,
  (SELECT count(*) FROM public.cl_batch_scans sc, lb, jsonb_object_keys(COALESCE(sc.extra, '{}'::jsonb)) k
    WHERE sc.batch_id = lb.id AND k <> 'weight_kg') AS non_allowed_extra_keys,
  (SELECT count(*) FROM s, jsonb_object_keys(s.extra) k WHERE k <> 'weight_kg') AS sample_extra_bad_keys,
  (SELECT count(*) FROM public.one_db WHERE source = 'panelist') AS panelist_rows_all,
  (SELECT count(*) FROM public.one_db, p WHERE source = 'panelist' AND account_id = p.acc) AS panelist_rows_demo2,
  (SELECT md5(COALESCE(string_agg(id::text || ':' || COALESCE(on_time_delivery::text, '-') || ':' ||
                                  COALESCE(business_transit_days::text, '-') || ':' || COALESCE(total_transit_hours::text, '-'),
                                  ',' ORDER BY id), ''))
     FROM public.one_db, p WHERE source = 'panelist' AND account_id = p.acc) AS panelist_hash_demo2,
  (SELECT count(*) FROM public.allocation_plan_details, p WHERE account_id = p.acc) AS apd_demo2,
  (SELECT count(*) FROM public.incidents, p WHERE account_id = p.acc) AS incidents_demo2,
  (SELECT count(*) FROM public.one_db WHERE source = 'carrier' AND account_id <> 'f4d823d2-93e6-4755-9a89-9da87e7fa86e') AS carrier_rows_other_accounts
)
SELECT to_jsonb(r) || jsonb_build_object('expect', jsonb_build_object(
         'samples_eq_planned',        r.samples_active = r.planned AND r.obtained = r.planned,
         'all_quotas_fulfilled',      r.quotas = jsonb_build_object('fulfilled', 6),
         'onedb_one_per_sample',      r.onedb_carrier = r.samples_active AND r.onedb_linked = r.samples_active,
         'std_routes_on_time_and_eq', r.onedb_with_std > 0 AND r.onedb_std_ok = r.onedb_with_std,
         'no_std_route_no_on_time',   r.onedb_without_std > 0 AND r.onedb_nostd_ok = r.onedb_without_std,
         'missing_standard_alert',    r.alert_missing_std_phl = 1,
         'misrouting_flag_and_alert', r.samples_misrouting = 1 AND COALESCE((r.alerts->>'possible_misrouting')::int, 0) >= 1,
         'rejected_with_reasons',     COALESCE((r.rejected_items->>'start_after_end')::int, 0) = 1
                                      AND COALESCE((r.rejected_items->>'unknown_product')::int, 0) = 1,
         'sampling_runs_6',           r.sampling_runs = 6 AND r.sampling_selected = r.samples_active AND r.runs_population_ok,
         'no_personal_data',          r.pii_in_raw_payload = 0 AND r.non_allowed_extra_keys = 0 AND r.sample_extra_bad_keys = 0,
         'no_carrier_rows_elsewhere', r.carrier_rows_other_accounts = 0
       )) AS summary
  FROM r;
