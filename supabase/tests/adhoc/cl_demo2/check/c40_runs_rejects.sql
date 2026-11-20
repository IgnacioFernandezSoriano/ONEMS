-- READ-ONLY. Per stratum of every batch of the DEMO plan: sampling run (population, valid candidates, required,
-- selected) and rejected readings with their reasons.
SELECT b.connector_batch_id, b.status AS batch_status, o.name || ' -> ' || d.name AS route, q.iso_year || '-W' || q.iso_week AS week,
       r.population_size, r.candidates_valid, r.samples_required, r.samples_selected,
       (SELECT jsonb_object_agg(x.reject_reason, x.n) FROM (
          SELECT sc.reject_reason, count(*) AS n FROM public.cl_batch_scans sc
           WHERE sc.batch_id = b.id AND sc.stratum_id = q.id AND sc.status = 'rejected' GROUP BY 1) x) AS rejected_rows
  FROM public.cl_batches b
  JOIN public.cl_demands dm ON dm.id = b.demand_id
  JOIN public.cl_plan_quotas q ON q.plan_id = dm.plan_id
  JOIN public.cities o ON o.id = q.origin_city_id
  JOIN public.cities d ON d.id = q.destination_city_id
  LEFT JOIN public.cl_sampling_runs r ON r.batch_id = b.id AND r.stratum_id = q.id
 WHERE dm.plan_id = 'c1de2000-0000-4000-8000-0000000000a1'
 ORDER BY b.received_at, q.iso_week, route;
