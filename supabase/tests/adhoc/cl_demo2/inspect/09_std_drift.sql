-- Read-only: panelist one_db rows of the chosen routes whose stored on_time would change if the standard trigger
-- recalculated it (UPDATE of cl_last_mile_time fires recalculate_on_time_delivery_on_sla_change). Expect 0.
SELECT o.name AS orig, d.name AS dest, ds.standard_time, ds.time_unit, count(x.*) AS rows,
       count(x.*) FILTER (WHERE x.on_time_delivery IS DISTINCT FROM public.one_db_on_time(x.business_transit_hours, x.business_transit_days, ds.standard_time, ds.time_unit)) AS would_change
  FROM public.delivery_standards ds
  JOIN public.carriers ca ON ca.id = ds.carrier_id
  JOIN public.products p ON p.id = ds.product_id
  JOIN public.cities o ON o.id = ds.origin_city_id
  JOIN public.cities d ON d.id = ds.destination_city_id
  LEFT JOIN public.one_db x ON x.account_id = ds.account_id AND btrim(x.carrier_name) = btrim(ca.name)
       AND btrim(x.product_name) = btrim(p.description) AND btrim(x.origin_city_name) = btrim(o.name)
       AND btrim(x.destination_city_name) = btrim(d.name)
 WHERE ds.account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND btrim(ca.code) = 'CARRIER A' AND btrim(p.code) = 'A STANDARD'
 GROUP BY 1,2,3,4 ORDER BY 1,2;
