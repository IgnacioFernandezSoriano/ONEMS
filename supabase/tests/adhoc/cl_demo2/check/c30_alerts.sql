-- READ-ONLY. Alerts of the DEMO plan.
SELECT a.alert_type, a.severity, a.status, a.created_at, a.details
  FROM public.cl_alerts a
 WHERE a.plan_id = 'c1de2000-0000-4000-8000-0000000000a1'
 ORDER BY a.created_at, a.alert_type;
