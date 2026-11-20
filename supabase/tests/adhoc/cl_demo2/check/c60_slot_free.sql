-- READ-ONLY. true when plan "Carrier Link DEMO" has no demand in the current local hour (Europe/Madrid), i.e.
-- 30_emit.sql can emit now. run.sh undo-test refuses to undo otherwise (the demo data would stay removed).
SELECT jsonb_build_object('slot_free', NOT EXISTS (
         SELECT 1 FROM public.cl_demands d
          WHERE d.plan_id = 'c1de2000-0000-4000-8000-0000000000a1'
            AND d.requested_at >= (date_trunc('hour', now() AT TIME ZONE 'Europe/Madrid') AT TIME ZONE 'Europe/Madrid')),
       'local_now', now() AT TIME ZONE 'Europe/Madrid') AS slot;
