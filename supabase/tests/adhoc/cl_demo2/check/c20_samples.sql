-- READ-ONLY. Active samples of the DEMO plan as they reach the E2E base (one_db), one row per sample.
SELECT q.iso_year || '-W' || q.iso_week AS week,
       o.origin_city_name || ' -> ' || o.destination_city_name AS real_route,
       s.item_id, s.possible_misrouting AS misrouting,
       (SELECT count(*) FROM public.cl_sample_scans sc WHERE sc.sample_id = s.id) AS scans,
       o.measured_total_hours, o.measured_business_days, o.equivalence_days, o.business_transit_days, o.on_time_delivery
  FROM public.cl_samples s
  JOIN public.cl_plan_quotas q ON q.id = s.quota_id
  JOIN public.one_db o ON o.cl_sample_id = s.id
 WHERE s.plan_id = 'c1de2000-0000-4000-8000-0000000000a1' AND s.status = 'active'
 ORDER BY q.iso_week, real_route, s.item_id;
