-- Resumen diario a las 09:00 locales de cada cuenta: daily_summary_due_accounts + dispatch_daily_parcel_summary + cron.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
-- Cuenta 1 en Nairobi (UTC+3), cuenta 2 en Dakar (UTC+0, sin envios). Pan1 (origen N1) con chat numerico.
UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
UPDATE public.accounts SET timezone = 'Africa/Dakar'   WHERE id = 'a0000000-0000-0000-0000-000000000002';
UPDATE public.panelists SET telegram_id = '111' WHERE id = 'e1000000-0000-0000-0000-000000000001';
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada,
                                            week_number, month, year, status, generation_source)
VALUES ('dd000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10',10,3,2027,'pending','plan');

-- Vault no existe en el Postgres local: tabla equivalente solo dentro de esta transaccion.
CREATE TABLE IF NOT EXISTS vault.decrypted_secrets (name text, decrypted_secret text);

DO $$
DECLARE n int;
BEGIN
  -- (a) 06:00 UTC = 09:00 Nairobi: cuenta 1 debida con su fecha local; Dakar (06:00 local) no.
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.daily_summary_due_accounts('2027-03-10 06:00+00')) <> 1, 'a: una cuenta');
  PERFORM pg_temp.fail_if((SELECT account_id FROM public.daily_summary_due_accounts('2027-03-10 06:00+00'))
                          IS DISTINCT FROM 'a0000000-0000-0000-0000-000000000001', 'a: cuenta 1');
  PERFORM pg_temp.fail_if((SELECT local_date FROM public.daily_summary_due_accounts('2027-03-10 06:00+00'))
                          IS DISTINCT FROM '2027-03-10'::date, 'a: fecha local');
  -- (b) 06:59 UTC sigue siendo las 09 en Nairobi; 07:00 y 05:00 no.
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.daily_summary_due_accounts('2027-03-10 06:59+00')) <> 1, 'b: 09:59 local');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.daily_summary_due_accounts('2027-03-10 07:00+00')) <> 0, 'b: 10:00 local');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.daily_summary_due_accounts('2027-03-10 05:00+00')) <> 0, 'b: 08:00 local');
  -- (c) 09:00 UTC = 09:00 Dakar: cuenta 2 sin envios -> nadie.
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.daily_summary_due_accounts('2027-03-10 09:00+00')) <> 0, 'c: Dakar sin envios');
  -- (d) Otro dia sin envio de hoy ni atrasados notified -> nadie (el pending de ayer no cuenta: solo notified atrasados).
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.daily_summary_due_accounts('2027-03-11 06:00+00')) <> 0, 'd: pending de ayer');
  UPDATE public.allocation_plan_details SET status = 'notified' WHERE id = 'dd000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.daily_summary_due_accounts('2027-03-11 06:00+00')) <> 1, 'd: notified atrasado');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.daily_summary_due_accounts('2027-03-10 06:00+00')) <> 0, 'd: notified de hoy ya avisado');
  UPDATE public.allocation_plan_details SET status = 'pending' WHERE id = 'dd000000-0000-0000-0000-000000000001';
  -- (e) Chat no numerico -> nadie.
  UPDATE public.panelists SET telegram_id = '@pan1' WHERE id = 'e1000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.daily_summary_due_accounts('2027-03-10 06:00+00')) <> 0, 'e: chat @alias');
  UPDATE public.panelists SET telegram_id = '111' WHERE id = 'e1000000-0000-0000-0000-000000000001';
  -- (f) Destino sin panelista activo -> nadie.
  UPDATE public.panelists SET status = 'inactive' WHERE id = 'e4000000-0000-0000-0000-000000000004';
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.daily_summary_due_accounts('2027-03-10 06:00+00')) <> 0, 'f: destino inactivo');
  UPDATE public.panelists SET status = 'active' WHERE id = 'e4000000-0000-0000-0000-000000000004';

  -- (g) dispatch: sin secretos no llama; con secretos, una llamada a la hora debida y ninguna fuera de ella.
  n := public.dispatch_daily_parcel_summary('2027-03-10 06:00+00');
  PERFORM pg_temp.fail_if(n <> 0, 'g: sin secretos');
  INSERT INTO vault.decrypted_secrets VALUES ('daily_summary_webhook_url','https://example.test/webhook'),
                                             ('daily_summary_webhook_secret','s3cret');
  n := public.dispatch_daily_parcel_summary('2027-03-10 06:00+00');
  PERFORM pg_temp.fail_if(n <> 1, 'g: una llamada: ' || n);
  n := public.dispatch_daily_parcel_summary('2027-03-10 08:00+00');
  PERFORM pg_temp.fail_if(n <> 0, 'g: fuera de hora: ' || n);

  -- (h) cron horario.
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-parcel-summary-hourly'
                                        AND schedule = '0 * * * *'), 'h: cron');
  RAISE NOTICE 'PASS daily_summary_local_9am';
END $$;
ROLLBACK;
