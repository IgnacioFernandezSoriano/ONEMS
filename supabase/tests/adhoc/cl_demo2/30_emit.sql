-- Carrier Link DEMO2 synthetic test, phase "setup" step c, reused by undo-test to re-ask the undone quotas (WRITES).
-- Emits ONE demand for plan "Carrier Link DEMO" with cl_emit_due_demands(p_now) and an explicit p_now:
--   * slot = the current local hour (account zone, Europe/Madrid); the emitter allows one demand per plan and local
--     hour, so if this hour is taken the script stops and asks to run again in the next hour (run.sh undo-test checks
--     this BEFORE undoing). Only the local simulation (setting cl_demo.allow_past_slot = on) falls back to an earlier
--     free hour;
--   * the connector calendar is set to every day at that hour (emit_days 1-7, emit_hour = slot hour), so the call is
--     inside the connector window (R22); p_now = slot + 5 min (never in the future).
-- cl_emit_due_demands is global (all accounts). GUARD: aborts if any active Carrier Link plan exists outside DEMO2,
-- so no other account can receive a demand from this call. The hourly cron 'cl-emit-demands' (minute 15) runs the
-- same function; it finds no pending quota after this call.
DO $$
DECLARE
  c_acc  constant uuid := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  c_plan constant uuid := 'c1de2000-0000-4000-8000-0000000000a1';
  c_feed constant uuid := 'c1de2000-0000-4000-8000-0000000000f1';
  v_tz   text;
  v_slot timestamp;
  v_now  timestamptz;
  v_n    integer;
  i      integer;
BEGIN
  IF EXISTS (SELECT 1 FROM public.cl_plans WHERE status = 'active' AND account_id <> c_acc) THEN
    RAISE EXCEPTION 'GUARD: another account has an active Carrier Link plan; cl_emit_due_demands(p_now) would touch it';
  END IF;
  IF (SELECT status FROM public.cl_plans WHERE id = c_plan) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'GUARD: plan Carrier Link DEMO is not active';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cl_plan_quotas WHERE plan_id = c_plan AND status = 'pending') THEN
    RAISE EXCEPTION 'GUARD: no pending quota to ask (already emitted?)';
  END IF;

  v_tz := COALESCE((SELECT emit_timezone FROM public.cl_feeds WHERE id = c_feed),
                   (SELECT timezone FROM public.accounts WHERE id = c_acc), 'UTC');
  v_slot := date_trunc('hour', now() AT TIME ZONE v_tz);
  IF EXISTS (SELECT 1 FROM public.cl_demands d WHERE d.plan_id = c_plan AND d.requested_at >= (v_slot AT TIME ZONE v_tz)) THEN
    -- The current local hour already has a demand of this plan (setup and undo-test in the same hour). Going back to an
    -- earlier hour would make the new demand look OLDER than the undone one (cl_settle_quota reads the population of
    -- the latest demand by requested_at), so remotely we stop; the local simulation allows it (custom setting).
    IF COALESCE(current_setting('cl_demo.allow_past_slot', true), '') <> 'on' THEN
      RAISE EXCEPTION 'EMIT: this plan already has a demand in the current local hour (%); run again after %:00 (%)',
        v_slot, extract(hour FROM v_slot + interval '1 hour'), v_tz;
    END IF;
    FOR i IN 1..72 LOOP
      v_slot := date_trunc('hour', now() AT TIME ZONE v_tz) - make_interval(hours => i);
      EXIT WHEN NOT EXISTS (SELECT 1 FROM public.cl_demands d
                             WHERE d.plan_id = c_plan
                               AND d.requested_at >= (v_slot AT TIME ZONE v_tz)
                               AND d.requested_at <  ((v_slot + interval '1 hour') AT TIME ZONE v_tz));
    END LOOP;
  END IF;
  v_now := LEAST(now(), (v_slot + interval '5 minutes') AT TIME ZONE v_tz);

  UPDATE public.cl_feeds SET emit_days = '{1,2,3,4,5,6,7}', emit_hour = extract(hour FROM v_slot)::smallint
   WHERE id = c_feed;

  v_n := public.cl_emit_due_demands(v_now);
  IF v_n <> 1 OR NOT EXISTS (SELECT 1 FROM public.cl_demands WHERE plan_id = c_plan AND status = 'open' AND requested_at = v_now) THEN
    RAISE EXCEPTION 'EMIT: expected 1 demand for the DEMO plan at %, got % (see cl_alerts emit_failed)', v_now, v_n;
  END IF;
END $$;

SELECT jsonb_build_object(
  'demands', (SELECT jsonb_agg(jsonb_build_object('id', d.id, 'status', d.status, 'requested_at', d.requested_at,
                                                  'feed_testing', d.feed_testing,
                                                  'strata', jsonb_array_length(d.payload->'strata')) ORDER BY d.requested_at)
                FROM public.cl_demands d WHERE d.plan_id = 'c1de2000-0000-4000-8000-0000000000a1'),
  'quotas', (SELECT jsonb_object_agg(s, n) FROM (SELECT q.status AS s, count(*) AS n FROM public.cl_plan_quotas q
                                                  WHERE q.plan_id = 'c1de2000-0000-4000-8000-0000000000a1' GROUP BY q.status) x),
  'feed', (SELECT jsonb_build_object('status', status, 'emit_hour', emit_hour) FROM public.cl_feeds
            WHERE id = 'c1de2000-0000-4000-8000-0000000000f1')
) AS step_c;
