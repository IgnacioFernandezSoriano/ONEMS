-- Carrier Link v4.1, tarea 8: control de incidencias (20261124100300_cl_incidents.sql).
-- Estructura y permiso cl_incidents (solo DEMO2), missing_delivery (abrir, anadir, un aviso por periodo aunque el job
-- corra cada hora, cierre automatico R31 y a mano), delivery_rejected, high_rejection, unknown_data, quota_unfilled
-- (D27; solo cierre a mano), destinatarios (AM + DO de la cuenta; carrier solo con notification_email en el maestro),
-- cola de avisos (arriendo, idempotencia, reintentos) y funciones de la pantalla (aislamiento, 42501 identico).
-- Todo en BEGIN ... ROLLBACK.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.raises(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ':' || SQLERRM; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.sha(p_n int) RETURNS text LANGUAGE sql AS $$
  SELECT encode(sha256(convert_to('inc-' || p_n, 'UTF8')), 'hex')
$$;

-- Entrega de un dia (conector diario) en el estado dado (insert directo; el disparador solo mira los UPDATE).
CREATE OR REPLACE FUNCTION pg_temp.dlv(p_feed uuid, p_day date, p_n int, p_status text DEFAULT 'received',
                                       p_test boolean DEFAULT false) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.cl_deliveries (account_id, feed_id, period_start, period_end, source, format, compression,
                                    file_path, sha256, status, is_test, received_at)
  SELECT f.account_id, f.id, p_day, p_day, 'api', 'jsonl', 'none', 't/inc-' || p_n || '.jsonl', pg_temp.sha(p_n),
         p_status, p_test, now()
    FROM public.cl_feeds f WHERE f.id = p_feed
  RETURNING id
$$;

-- Avisos (uno por evento y tipo de destinatario, sea cual sea el numero de direcciones) de las incidencias de un
-- conector y tipo (opcional: destinatario).
CREATE OR REPLACE FUNCTION pg_temp.nn(p_feed uuid, p_type text, p_kind text DEFAULT NULL) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(DISTINCT (n.incident_id, n.recipient_kind, n.event, n.periods::text))
    FROM public.cl_notifications n JOIN public.cl_incidents i ON i.id = n.incident_id
   WHERE i.feed_id = p_feed AND i.incident_type = p_type AND (p_kind IS NULL OR n.recipient_kind = p_kind)
$$;
-- Correos (una fila de cl_notifications = un correo a una direccion; sin contar los 'skipped' sin direccion).
CREATE OR REPLACE FUNCTION pg_temp.ne(p_feed uuid, p_type text) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM public.cl_notifications n JOIN public.cl_incidents i ON i.id = n.incident_id
   WHERE i.feed_id = p_feed AND i.incident_type = p_type AND n.recipient_email IS NOT NULL
$$;

-- Incidencia abierta de un conector y tipo.
CREATE OR REPLACE FUNCTION pg_temp.inc(p_feed uuid, p_type text) RETURNS public.cl_incidents LANGUAGE sql AS $$
  SELECT i.* FROM public.cl_incidents i
   WHERE i.feed_id = p_feed AND i.incident_type = p_type AND i.status <> 'resolved'
$$;

BEGIN;
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- A1 (Nairobi, frances). Conector F1 diario (carrier CA, con correo de avisos) y F2 diario (carrier CB de A1, sin
-- correo), ambos activos con plan del 10/11 al 30/11. A2: conector X para el aislamiento.
UPDATE public.accounts SET timezone = 'Africa/Nairobi', default_language = 'fr' WHERE id = 'a0000000-0000-0000-0000-000000000001';
UPDATE public.carriers SET notification_email = 'Ops@Carrier.example' WHERE id = 'ca000000-0000-0000-0000-000000000001';
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','CB','Carrier B'),
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CX','Carrier X');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000003','PB','ProdB',48),
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','PX','ProdX',48);
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour) VALUES
  ('f0000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed One','active','{1,2,3,4,5,6,7}',3),
  ('f0000000-0000-0000-0000-0000000000f2','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000003','Feed Two','active','{1,2,3,4,5,6,7}',3),
  ('f0000000-0000-0000-0000-0000000000f9','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','Feed X','active','{1,2,3,4,5,6,7}',3);
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-000000000001','P1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-11-10','2026-11-30','active','f0000000-0000-0000-0000-0000000000f1'),
  ('90000000-0000-0000-0000-0000000000f2','a0000000-0000-0000-0000-000000000001','P2','ca000000-0000-0000-0000-000000000003','cb000000-0000-0000-0000-000000000003',10,'2026-11-10','2026-11-30','active','f0000000-0000-0000-0000-0000000000f2');

-- Usuarios de A1: AM (91), DO (92), PM sin derecho (97). El actor 99 del fixture es UPU (no recibe avisos).
INSERT INTO auth.users (id, email) VALUES
  ('91000000-0000-0000-0000-000000000091','am@t.l'), ('92000000-0000-0000-0000-000000000092','do@t.l'),
  ('97000000-0000-0000-0000-000000000097','pm@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('91000000-0000-0000-0000-000000000091','AM@t.l','Ana AM','user','a0000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-000000000092','do@t.l','Dora DO','user','a0000000-0000-0000-0000-000000000001'),
  ('97000000-0000-0000-0000-000000000097','pm@t.l','Pedro PM','user','a0000000-0000-0000-0000-000000000001');
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000091','account_manager'),
  ('a0000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000092','do_coordinator'),
  ('a0000000-0000-0000-0000-000000000001','97000000-0000-0000-0000-000000000097','panelist_manager');

-- ================================================================ 1. estructura y permiso solo en DEMO2
DO $$
DECLARE f text;
BEGIN
  PERFORM pg_temp.ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.cl_incidents'::regclass)
                     AND (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.cl_notifications'::regclass), 'RLS');
  PERFORM pg_temp.ok(NOT has_table_privilege('authenticated', 'public.cl_notifications', 'SELECT')
                     AND NOT has_table_privilege('service_role', 'public.cl_notifications', 'SELECT')
                     AND NOT has_table_privilege('authenticated', 'public.cl_incidents', 'UPDATE')
                     AND NOT has_table_privilege('anon', 'public.cl_incidents', 'SELECT'), 'sin escritura directa');
  PERFORM pg_temp.ok(to_regclass('public.cl_feeds') IS NOT NULL
                     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'cl_feeds' AND column_name = 'contact_email')
                     AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'carriers' AND column_name = 'notification_email'),
                     'correo del carrier en el maestro');
  PERFORM pg_temp.ok(pg_temp.raises('UPDATE public.carriers SET notification_email = ''no-es-correo'' WHERE code = ''CB''') LIKE '23514:%',
                     'notification_email validado');
  FOREACH f IN ARRAY ARRAY['public.cl_incidents_list(uuid,text,text,uuid,integer,integer)', 'public.cl_incident_get(uuid)',
                           'public.cl_incident_update(uuid,text,uuid,text,boolean)', 'public.cl_incident_close(uuid,text)'] LOOP
    PERFORM pg_temp.ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=public, extensions'] FROM pg_proc WHERE oid = f::regprocedure), f || ' definer');
    PERFORM pg_temp.ok(has_function_privilege('authenticated', f, 'EXECUTE') AND NOT has_function_privilege('anon', f, 'EXECUTE')
                       AND NOT has_function_privilege('service_role', f, 'EXECUTE'), f || ' solo authenticated');
  END LOOP;
  FOREACH f IN ARRAY ARRAY['public.cl_notify_claim(text,integer,integer,timestamptz)',
                           'public.cl_notify_result(uuid,text,boolean,text,boolean,text,timestamptz)'] LOOP
    PERFORM pg_temp.ok(has_function_privilege('service_role', f, 'EXECUTE') AND NOT has_function_privilege('authenticated', f, 'EXECUTE')
                       AND NOT has_function_privilege('anon', f, 'EXECUTE'), f || ' solo service_role');
  END LOOP;
  FOREACH f IN ARRAY ARRAY['public.cl_incident_record(uuid,uuid,uuid,text,jsonb,jsonb,timestamptz)',
                           'public.cl_notify_kick(timestamptz)', 'public.cl_incidents_grant_demo2()',
                           'public.cl_settle_quota(uuid,boolean)', 'public.cl_housekeeping(timestamptz)'] LOOP
    PERFORM pg_temp.ok(NOT has_function_privilege('service_role', f, 'EXECUTE') AND NOT has_function_privilege('authenticated', f, 'EXECUTE'),
                       f || ' interna');
  END LOOP;
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cl-notify-kick' AND schedule = '* * * * *'), 'job cl-notify-kick');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM cron.job WHERE command ILIKE '%incident%'), 'sin job horario nuevo (va en cl_housekeeping)');

  -- Permiso: en el catalogo, fuera de la plantilla, en ninguna cuenta salvo DEMO2.
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.access_option WHERE key = 'cl_incidents' AND menu_group = 'carrier_link'), 'opcion cl_incidents');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.access_template WHERE option = 'cl_incidents'), 'no esta en la plantilla');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.account_access WHERE option = 'cl_incidents'), 'ninguna cuenta (no hay DEMO2 aqui)');
  INSERT INTO public.accounts (id, name, slug) VALUES ('f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'DEMO2', 'demo2');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.account_access WHERE option = 'cl_incidents'), 'cuenta nueva: la plantilla no lo trae');
  PERFORM pg_temp.ok(public.cl_incidents_grant_demo2() = 4, 'concedido en DEMO2');
  PERFORM pg_temp.ok(public.cl_incidents_grant_demo2() = 0, 'idempotente');
  PERFORM pg_temp.ok((SELECT count(DISTINCT account_id) FROM public.account_access WHERE option = 'cl_incidents') = 1
                     AND (SELECT string_agg(role || ':' || level, ',' ORDER BY role) FROM public.account_access
                           WHERE option = 'cl_incidents' AND account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e')
                         = 'account_manager:edit,allocation_plan_manager:view,do_coordinator:view,upu_account_manager:edit',
                     'solo DEMO2, niveles de cl_monitor');
  PERFORM pg_temp.ok(public.cl_feed_missing_grace_hours('{}') = 6 AND public.cl_feed_missing_grace_hours('{"missing_grace_hours":2}') = 2
                     AND public.cl_feed_missing_grace_hours('{"missing_grace_hours":999}') = 6
                     AND public.cl_feed_missing_grace_hours('{"missing_grace_hours":"x"}') = 6, 'margen por defecto 6 h');
END $$;

-- ================================================================ 2. missing_delivery
DO $$
DECLARE
  f1 constant uuid := 'f0000000-0000-0000-0000-0000000000f1';
  f2 constant uuid := 'f0000000-0000-0000-0000-0000000000f2';
  h jsonb; v public.cl_incidents; d uuid; i int;
BEGIN
  -- 12/11 08:00 Nairobi: vencido solo el periodo 10/11 (11/11 03:00 + 6 h); el 11/11 vence el 12/11 a las 09:00.
  h := public.cl_housekeeping('2026-11-12 08:00+03');
  v := pg_temp.inc(f1, 'missing_delivery');
  PERFORM pg_temp.ok(v.id IS NOT NULL AND v.status = 'open' AND jsonb_array_length(v.periods) = 1
                     AND v.periods->0->>'period_start' = '2026-11-10' AND v.periods->0->>'period_end' = '2026-11-10',
                     'abierta con el 10/11: ' || coalesce(v.periods::text, 'null') || ' ' || h::text);
  PERFORM pg_temp.ok(pg_temp.nn(f1, 'missing_delivery', 'account_manager') = 1 AND pg_temp.nn(f1, 'missing_delivery', 'carrier') = 1,
                     'un aviso a la cuenta y uno al carrier');
  PERFORM pg_temp.ok((SELECT event FROM public.cl_notifications n WHERE n.incident_id = v.id LIMIT 1) = 'opened', 'evento opened');
  -- F2: carrier sin correo -> solo la cuenta, sin error.
  PERFORM pg_temp.ok(pg_temp.nn(f2, 'missing_delivery', 'account_manager') = 1 AND pg_temp.nn(f2, 'missing_delivery', 'carrier') = 0,
                     'sin correo del carrier: solo la cuenta');

  -- El job corre cada hora: ningun aviso nuevo hasta que vence otro periodo.
  FOR i IN 1..3 LOOP
    h := public.cl_housekeeping('2026-11-12 08:30+03');
  END LOOP;
  PERFORM pg_temp.ok(pg_temp.nn(f1, 'missing_delivery') = 2 AND jsonb_array_length((pg_temp.inc(f1, 'missing_delivery')).periods) = 1,
                     'repetido: sin avisos nuevos');
  h := public.cl_housekeeping('2026-11-12 10:00+03');
  h := public.cl_housekeeping('2026-11-12 11:00+03');
  v := pg_temp.inc(f1, 'missing_delivery');
  PERFORM pg_temp.ok(jsonb_array_length(v.periods) = 2 AND v.periods->1->>'period_start' = '2026-11-11'
                     AND pg_temp.nn(f1, 'missing_delivery') = 4
                     AND (SELECT count(*) FROM public.cl_notifications n WHERE n.incident_id = v.id AND n.event = 'appended') = 3
                     AND pg_temp.ne(f1, 'missing_delivery') = 6,
                     'R32: el 11/11 se anade a la misma incidencia con un aviso nuevo por destinatario');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_incidents WHERE feed_id = f1 AND incident_type = 'missing_delivery') = 1,
                     'una sola incidencia');
  -- El margen es configurable: F2 con 0 h ve el 11/11 ya a las 03:00.
  UPDATE public.cl_feeds SET config = '{"missing_grace_hours":0}' WHERE id = f2;

  -- R31: la primera entrega que se reciba (aqui la del 12/11) la cierra sola; los avisos pendientes ya no salen.
  d := pg_temp.dlv(f1, '2026-11-12', 1, 'pending_upload');
  UPDATE public.cl_deliveries SET status = 'received', received_at = now() WHERE id = d;
  SELECT * INTO v FROM public.cl_incidents WHERE id = v.id;
  PERFORM pg_temp.ok(v.status = 'resolved' AND v.closed_how = 'auto' AND v.closed_by IS NULL, 'cerrada sola al recibir: ' || v.status);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_notifications n WHERE n.incident_id = v.id AND n.status = 'pending')
                     AND (SELECT count(*) FROM public.cl_notifications n WHERE n.incident_id = v.id AND n.status = 'skipped') = 6,
                     'avisos pendientes de la cerrada: skipped');
  -- Termina bien (sin abrir nada) para que F1 no quede "en vuelo".
  UPDATE public.cl_deliveries SET status = 'processing' WHERE id = d;
  UPDATE public.cl_deliveries SET status = 'processed', finished_at = now() WHERE id = d;

  -- Entrega de prueba (is_test) no cierra nada.
  PERFORM pg_temp.ok((pg_temp.inc(f2, 'missing_delivery')).id IS NOT NULL, 'F2 sigue abierta');
  d := pg_temp.dlv(f2, '2026-11-12', 2, 'pending_upload', true);
  UPDATE public.cl_deliveries SET status = 'received' WHERE id = d;
  PERFORM pg_temp.ok((pg_temp.inc(f2, 'missing_delivery')).id IS NOT NULL, 'una entrega de prueba no la cierra');
  UPDATE public.cl_deliveries SET status = 'rejected', error = 'CL_SHA256_MISMATCH', finished_at = now() WHERE id = d;
  PERFORM pg_temp.ok((pg_temp.inc(f2, 'delivery_rejected')).id IS NULL, 'ni abre delivery_rejected');
END $$;

-- Cierre a mano de F2 (como AM con Edit; el derecho se da aqui en A1 solo para el test) y lo ya visto no vuelve.
INSERT INTO public.account_access (account_id, role, option, level) VALUES
  ('a0000000-0000-0000-0000-000000000001','account_manager','cl_incidents','edit'),
  ('a0000000-0000-0000-0000-000000000001','do_coordinator','cl_incidents','view');
SET ROLE authenticated;
DO $$
DECLARE v public.cl_incidents; j jsonb;
BEGIN
  PERFORM pg_temp.as_user('91000000-0000-0000-0000-000000000091', 'authenticated');
  SELECT * INTO v FROM public.cl_incidents WHERE feed_id = 'f0000000-0000-0000-0000-0000000000f2'
                                             AND incident_type = 'missing_delivery' AND status <> 'resolved';
  j := public.cl_incident_close(v.id, 'Hablado con el carrier');
  PERFORM pg_temp.ok(j->>'status' = 'resolved' AND j->>'closed_how' = 'manual'
                     AND j->>'closed_by' = '91000000-0000-0000-0000-000000000091' AND j->>'notes' = 'Hablado con el carrier',
                     'cerrada a mano: ' || j::text);
  PERFORM pg_temp.ok(public.cl_incident_close(v.id)->>'closed_how' = 'manual', 'cerrar otra vez: idempotente');
END $$;
RESET ROLE;
DO $$
DECLARE f2 constant uuid := 'f0000000-0000-0000-0000-0000000000f2'; v public.cl_incidents; h jsonb;
BEGIN
  -- 12/11 11:00: F2 (margen 0) tiene vencidos 10/11 y 11/11, ya en la incidencia cerrada a mano: nada nuevo.
  h := public.cl_housekeeping('2026-11-12 11:00+03');
  PERFORM pg_temp.ok((pg_temp.inc(f2, 'missing_delivery')).id IS NULL, 'lo cerrado a mano no se reabre: ' || h::text);
  -- 13/11 04:00 vence el 12/11 (margen 0): incidencia nueva solo con el 12/11.
  h := public.cl_housekeeping('2026-11-13 04:00+03');
  v := pg_temp.inc(f2, 'missing_delivery');
  PERFORM pg_temp.ok(v.id IS NOT NULL AND jsonb_array_length(v.periods) = 1 AND v.periods->0->>'period_start' = '2026-11-12',
                     'periodo nuevo -> incidencia nueva: ' || coalesce(v.periods::text, 'null'));
  PERFORM pg_temp.ok((h->>'missing_periods')::int >= 1, 'resumen cuenta los periodos: ' || h::text);
  -- Conector en prueba o en pausa: no se vigila.
  UPDATE public.cl_feeds SET status = 'paused' WHERE id = f2;
  h := public.cl_housekeeping('2026-11-14 04:00+03');
  PERFORM pg_temp.ok(jsonb_array_length((pg_temp.inc(f2, 'missing_delivery')).periods) = 1, 'pausado: sin periodos nuevos');
  UPDATE public.cl_feeds SET status = 'active' WHERE id = f2;
END $$;

-- ================================================================ 2b. un periodo se avisa como no recibido UNA vez (ronda 1)
-- F3: diario, carrier CA (con correo), plan del 10/11 al 30/11.
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour) VALUES
  ('f0000000-0000-0000-0000-0000000000f3','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed Three','active','{1,2,3,4,5,6,7}',3);
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000f3','a0000000-0000-0000-0000-000000000001','P3','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-11-10','2026-11-30','active','f0000000-0000-0000-0000-0000000000f3');
DO $$
DECLARE
  f3 constant uuid := 'f0000000-0000-0000-0000-0000000000f3';
  h jsonb; v public.cl_incidents; d uuid; k int; v_day date;
BEGIN
  -- 13/11 10:00: vencidos 10, 11 y 12/11 -> una incidencia, un aviso por direccion (AM, DO, carrier) = 3 correos.
  h := public.cl_housekeeping('2026-11-13 10:00+03');
  v := pg_temp.inc(f3, 'missing_delivery');
  PERFORM pg_temp.ok(jsonb_array_length(v.periods) = 3 AND pg_temp.ne(f3, 'missing_delivery') = 3
                     AND (SELECT count(*) FROM public.cl_missing_notified WHERE feed_id = f3) = 3,
                     'tres periodos, tres correos: ' || coalesce(v.periods::text, 'null'));

  -- (a) llega el 10/11 (cierra la incidencia, R31) y despues se rechaza: el job no vuelve a decir "no recibido".
  d := pg_temp.dlv(f3, '2026-11-10', 100, 'pending_upload');
  UPDATE public.cl_deliveries SET status = 'received', received_at = now() WHERE id = d;
  PERFORM pg_temp.ok((pg_temp.inc(f3, 'missing_delivery')).id IS NULL, 'R31: cerrada al recibir');
  UPDATE public.cl_deliveries SET status = 'rejected', error = 'CL_BAD_CSV_HEADER', finished_at = now() WHERE id = d;
  PERFORM pg_temp.ok((pg_temp.inc(f3, 'delivery_rejected')).id IS NOT NULL, 'rechazo anotado');
  h := public.cl_housekeeping('2026-11-13 11:00+03');
  h := public.cl_housekeeping('2026-11-13 12:00+03');
  PERFORM pg_temp.ok((pg_temp.inc(f3, 'missing_delivery')).id IS NULL AND pg_temp.ne(f3, 'missing_delivery') = 3,
                     'recibida y rechazada: ningun segundo "no recibido": ' || h::text);

  -- (b) el carrier se pone al dia del mas antiguo al mas nuevo, con el job entre cada paso: cero correos nuevos.
  k := 101;
  FOREACH v_day IN ARRAY ARRAY['2026-11-10','2026-11-11','2026-11-12']::date[] LOOP
    d := pg_temp.dlv(f3, v_day, k, 'pending_upload'); k := k + 1;
    UPDATE public.cl_deliveries SET status = 'received', received_at = now() WHERE id = d;
    h := public.cl_housekeeping('2026-11-13 13:00+03');   -- en vuelo: se salta el conector
    UPDATE public.cl_deliveries SET status = 'processing' WHERE id = d;
    UPDATE public.cl_deliveries SET status = 'processed', finished_at = now() WHERE id = d;
    h := public.cl_housekeeping('2026-11-13 14:00+03');
    PERFORM pg_temp.ok((pg_temp.inc(f3, 'missing_delivery')).id IS NULL AND pg_temp.ne(f3, 'missing_delivery') = 3,
                       'al dia hasta ' || v_day || ': sin correos nuevos');
  END LOOP;
  PERFORM pg_temp.ok((SELECT status FROM public.cl_incidents WHERE feed_id = f3 AND incident_type = 'delivery_rejected') = 'resolved',
                     'el 10/11 procesado cierra el rechazo');

  -- Un periodo realmente nuevo tras el cierre automatico (13/11, vence el 14/11 09:00): exactamente un aviso por
  -- direccion, en una incidencia nueva; repetir el job no cambia nada.
  h := public.cl_housekeeping('2026-11-14 10:00+03');
  v := pg_temp.inc(f3, 'missing_delivery');
  PERFORM pg_temp.ok(v.id IS NOT NULL AND jsonb_array_length(v.periods) = 1 AND v.periods->0->>'period_start' = '2026-11-13'
                     AND (SELECT count(*) FROM public.cl_notifications n WHERE n.incident_id = v.id) = 3
                     AND pg_temp.nn(f3, 'missing_delivery') = 4 AND pg_temp.ne(f3, 'missing_delivery') = 6,
                     'periodo nuevo: un aviso: ' || coalesce(v.periods::text, 'null'));
  h := public.cl_housekeeping('2026-11-14 11:00+03');
  PERFORM pg_temp.ok(pg_temp.ne(f3, 'missing_delivery') = 6, 'repetido: igual');
  -- Que no siga molestando en las secciones siguientes.
  UPDATE public.cl_feeds SET status = 'paused' WHERE id = f3;

  -- Punto desconocido sin lugar (no se puede dar de alta) no impide el cierre de unknown_data (ronda 1).
  PERFORM public.cl_incident_record('a0000000-0000-0000-0000-000000000001', f3, NULL, 'unknown_data',
    '[{"key":"delivery:x","period_start":"2026-11-13","period_end":"2026-11-13","products":1,"points":1}]',
    '{"products":["PR"],"points":[{"place_ref":null,"mode_ref":null}]}');
  PERFORM pg_temp.ok((pg_temp.inc(f3, 'unknown_data')).id IS NOT NULL, 'unknown_data abierta');
  h := public.cl_housekeeping('2026-11-14 12:00+03');
  PERFORM pg_temp.ok((pg_temp.inc(f3, 'unknown_data')).id IS NULL, 'punto sin lugar: cerrada sola: ' || h::text);
END $$;

-- ================================================================ 2c. una entrega de prueba nunca cubre un periodo (tarea 6, ronda 2)
DO $$
DECLARE
  f9 constant uuid := 'f0000000-0000-0000-0000-0000000000e9';
  h jsonb; v public.cl_incidents;
BEGIN
  INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour) VALUES
    (f9, 'a0000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001', 'Feed Nine', 'active', '{1,2,3,4,5,6,7}', 3);
  INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id)
  VALUES ('90000000-0000-0000-0000-0000000000e9', 'a0000000-0000-0000-0000-000000000001', 'P9',
          'ca000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001', 10, '2026-11-10', '2026-11-30',
          'active', f9);
  -- Restos de pruebas del 10/11: una fallida y otra recibida. No cubren el periodo ni frenan al vigilante.
  PERFORM pg_temp.dlv(f9, '2026-11-10', 901, 'failed', true);
  PERFORM pg_temp.dlv(f9, '2026-11-10', 902, 'received', true);
  h := public.cl_housekeeping('2026-11-12 08:00+03');
  v := pg_temp.inc(f9, 'missing_delivery');
  PERFORM pg_temp.ok(v.id IS NOT NULL AND jsonb_array_length(v.periods) = 1 AND v.periods->0->>'period_start' = '2026-11-10',
                     'no recibida abierta pese a las entregas de prueba: ' || coalesce(v.periods::text, 'null') || ' ' || h::text);
  PERFORM pg_temp.ok(pg_temp.nn(f9, 'missing_delivery', 'account_manager') = 1, 'un aviso a la cuenta');
  h := public.cl_housekeeping('2026-11-12 08:30+03');
  PERFORM pg_temp.ok(pg_temp.nn(f9, 'missing_delivery', 'account_manager') = 1
                     AND jsonb_array_length((pg_temp.inc(f9, 'missing_delivery')).periods) = 1, 'repetido: un solo aviso');
  -- Limpieza: fuera el conector de esta seccion (las demas secciones no lo esperan).
  UPDATE public.cl_plans SET status = 'closed' WHERE id = '90000000-0000-0000-0000-0000000000e9';
  UPDATE public.cl_feeds SET status = 'paused' WHERE id = f9;
END $$;

-- ================================================================ 3. delivery_rejected
DO $$
DECLARE
  f1 constant uuid := 'f0000000-0000-0000-0000-0000000000f1';
  d uuid; v public.cl_incidents;
BEGIN
  d := pg_temp.dlv(f1, '2026-11-13', 10);
  UPDATE public.cl_deliveries SET status = 'rejected', error = 'CL_SHA256_MISMATCH', finished_at = now() WHERE id = d;
  v := pg_temp.inc(f1, 'delivery_rejected');
  PERFORM pg_temp.ok(v.id IS NOT NULL AND v.periods->0->>'period_start' = '2026-11-13' AND v.periods->0->>'error' = 'CL_SHA256_MISMATCH',
                     'abierta por huella distinta');
  PERFORM pg_temp.ok(pg_temp.nn(f1, 'delivery_rejected', 'account_manager') = 1 AND pg_temp.nn(f1, 'delivery_rejected', 'carrier') = 1,
                     'avisos a la cuenta y al carrier');
  -- Mismo periodo rechazado otra vez (3 fallos): no hay periodo nuevo, no hay aviso nuevo.
  d := pg_temp.dlv(f1, '2026-11-13', 11);
  UPDATE public.cl_deliveries SET status = 'processing' WHERE id = d;
  UPDATE public.cl_deliveries SET status = 'rejected', error = 'CL_RETRIES_EXHAUSTED', finished_at = now() WHERE id = d;
  PERFORM pg_temp.ok(pg_temp.nn(f1, 'delivery_rejected') = 2, 'mismo periodo: sin aviso nuevo');
  -- Sustituida: no es un rechazo del fichero.
  d := pg_temp.dlv(f1, '2026-11-14', 12, 'pending_upload');
  UPDATE public.cl_deliveries SET status = 'rejected', error = 'CL_SUPERSEDED', finished_at = now() WHERE id = d;
  PERFORM pg_temp.ok(jsonb_array_length((pg_temp.inc(f1, 'delivery_rejected')).periods) = 1, 'CL_SUPERSEDED no cuenta');
  -- Tras 3 fallos, otro periodo: se anade.
  d := pg_temp.dlv(f1, '2026-11-14', 13);
  UPDATE public.cl_deliveries SET status = 'rejected', error = 'CL_RETRIES_EXHAUSTED', finished_at = now() WHERE id = d;
  PERFORM pg_temp.ok(jsonb_array_length((pg_temp.inc(f1, 'delivery_rejected')).periods) = 2 AND pg_temp.nn(f1, 'delivery_rejected') = 4,
                     'reintentos agotados en otro periodo: anadido');
  -- Se procesa bien el 13/11: sigue abierta (falta el 14/11). Luego el 14/11: se cierra sola.
  d := pg_temp.dlv(f1, '2026-11-13', 14);
  UPDATE public.cl_deliveries SET status = 'processing' WHERE id = d;
  UPDATE public.cl_deliveries SET status = 'processed', finished_at = now() WHERE id = d;
  PERFORM pg_temp.ok((pg_temp.inc(f1, 'delivery_rejected')).id IS NOT NULL, 'falta un periodo: sigue abierta');
  d := pg_temp.dlv(f1, '2026-11-14', 15);
  UPDATE public.cl_deliveries SET status = 'processing' WHERE id = d;
  UPDATE public.cl_deliveries SET status = 'processed', finished_at = now() WHERE id = d;
  SELECT * INTO v FROM public.cl_incidents WHERE id = v.id;
  PERFORM pg_temp.ok(v.status = 'resolved' AND v.closed_how = 'auto', 'todos sus periodos procesados: cerrada sola');
END $$;

-- ================================================================ 4. high_rejection y 5. unknown_data
DO $$
DECLARE
  f1 constant uuid := 'f0000000-0000-0000-0000-0000000000f1';
  a1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  d uuid; v public.cl_incidents; h jsonb;
BEGIN
  -- 15/11 con > 20 % de rechazados y datos desconocidos (las alertas las escribe finish antes del final).
  d := pg_temp.dlv(f1, '2026-11-15', 20);
  UPDATE public.cl_deliveries SET status = 'processing' WHERE id = d;
  INSERT INTO public.cl_alerts (account_id, delivery_id, alert_type, severity, details) VALUES
    (a1, d, 'rejected_ratio', 'medium', jsonb_build_object('rejected', 30, 'shipments', 100, 'ratio', 0.3, 'reasons', '{"no_end":30}'::jsonb)),
    (a1, d, 'unknown_product', 'medium', '{"values":["ZZ"]}'),
    (a1, d, 'unknown_reading_point', 'medium', '{"points":[{"place_ref":"XX","mode_ref":null}]}');
  UPDATE public.cl_deliveries SET status = 'processed', finished_at = now() WHERE id = d;
  v := pg_temp.inc(f1, 'high_rejection');
  PERFORM pg_temp.ok(v.id IS NOT NULL AND (v.periods->0->>'rejected')::int = 30 AND (v.periods->0->>'shipments')::int = 100,
                     'high_rejection abierta: ' || coalesce(v.periods::text, 'null'));
  PERFORM pg_temp.ok(pg_temp.nn(f1, 'high_rejection', 'carrier') = 1, 'aviso al carrier');
  v := pg_temp.inc(f1, 'unknown_data');
  PERFORM pg_temp.ok(v.id IS NOT NULL AND v.details->'products' = '["ZZ"]'::jsonb
                     AND v.details->'points' = '[{"place_ref":"XX","mode_ref":null}]'::jsonb
                     AND (v.periods->0->>'products')::int = 1 AND (v.periods->0->>'points')::int = 1,
                     'unknown_data abierta: ' || coalesce(v::text, 'null'));
  PERFORM pg_temp.ok(pg_temp.nn(f1, 'unknown_data', 'account_manager') = 1 AND pg_temp.nn(f1, 'unknown_data', 'carrier') = 0,
                     'unknown_data: solo la cuenta (lo arregla ONEMS)');

  -- 16/11 con los mismos desconocidos y bajo el umbral: high_rejection se cierra; unknown_data sin nada nuevo.
  d := pg_temp.dlv(f1, '2026-11-16', 21);
  UPDATE public.cl_deliveries SET status = 'processing' WHERE id = d;
  INSERT INTO public.cl_alerts (account_id, delivery_id, alert_type, severity, details) VALUES
    (a1, d, 'unknown_product', 'medium', '{"values":["ZZ"]}');
  UPDATE public.cl_deliveries SET status = 'processed', finished_at = now() WHERE id = d;
  PERFORM pg_temp.ok((pg_temp.inc(f1, 'high_rejection')).id IS NULL
                     AND (SELECT closed_how FROM public.cl_incidents WHERE feed_id = f1 AND incident_type = 'high_rejection') = 'auto',
                     'siguiente entrega bajo el umbral: high_rejection cerrada sola');
  PERFORM pg_temp.ok(jsonb_array_length((pg_temp.inc(f1, 'unknown_data')).periods) = 1 AND pg_temp.nn(f1, 'unknown_data') = 1,
                     'mismos valores: sin aviso nuevo');
  -- 17/11 con un producto nuevo: se anade.
  d := pg_temp.dlv(f1, '2026-11-17', 22);
  UPDATE public.cl_deliveries SET status = 'processing' WHERE id = d;
  INSERT INTO public.cl_alerts (account_id, delivery_id, alert_type, severity, details) VALUES
    (a1, d, 'unknown_product', 'medium', '{"values":["ZZ","YY"]}');
  UPDATE public.cl_deliveries SET status = 'processed', finished_at = now() WHERE id = d;
  v := pg_temp.inc(f1, 'unknown_data');
  PERFORM pg_temp.ok(jsonb_array_length(v.periods) = 2 AND (v.periods->1->>'products')::int = 1
                     AND v.details->'products' @> '["ZZ","YY"]'::jsonb AND pg_temp.nn(f1, 'unknown_data') = 2,
                     'valor nuevo: anadido con un aviso');

  -- Se cierra sola cuando todo esta dado de alta (cl_housekeeping).
  h := public.cl_housekeeping('2026-11-17 12:00+03');
  PERFORM pg_temp.ok((pg_temp.inc(f1, 'unknown_data')).id IS NOT NULL, 'sin dar de alta: sigue abierta');
  INSERT INTO public.products (account_id, carrier_id, code, description, standard_delivery_hours) VALUES
    (a1, 'ca000000-0000-0000-0000-000000000001', 'ZZ', 'Z', 48);
  INSERT INTO public.cl_value_mappings (account_id, carrier_id, kind, carrier_value, onems_value) VALUES
    (a1, 'ca000000-0000-0000-0000-000000000001', 'product', 'YY', 'PR');
  h := public.cl_housekeeping('2026-11-17 12:00+03');
  PERFORM pg_temp.ok((pg_temp.inc(f1, 'unknown_data')).id IS NOT NULL, 'falta el punto: sigue abierta');
  INSERT INTO public.readers (account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
    (a1, NULL, 'XX', 'Entry', 'carrier_scan', 'ca000000-0000-0000-0000-000000000001', 'XX', NULL, 'none');
  h := public.cl_housekeeping('2026-11-17 12:00+03');
  PERFORM pg_temp.ok((pg_temp.inc(f1, 'unknown_data')).id IS NULL AND (h->>'unknown_closed')::int = 1
                     AND (SELECT closed_how FROM public.cl_incidents WHERE feed_id = f1 AND incident_type = 'unknown_data') = 'auto',
                     'todo dado de alta: cerrada sola: ' || h::text);
END $$;

-- ================================================================ 6. quota_unfilled (D27) y solo cierre a mano
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned, samples_obtained) VALUES
  ('91000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000f1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,46,'2026-11-09','2026-11-15',3,1),
  ('91000000-0000-0000-0000-0000000000f2','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000f1','c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000001',2026,46,'2026-11-09','2026-11-15',2,0);
DO $$
DECLARE
  f1 constant uuid := 'f0000000-0000-0000-0000-0000000000f1';
  q1 constant uuid := '91000000-0000-0000-0000-0000000000f1';
  q2 constant uuid := '91000000-0000-0000-0000-0000000000f2';
  h jsonb; v public.cl_incidents; d uuid;
BEGIN
  -- 17/11: solo 2 dias tras el fin de la semana -> sigue pending.
  h := public.cl_housekeeping('2026-11-17 23:00+03');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plan_quotas WHERE id = q1) = 'pending', 'antes de 3 dias: pending');
  -- 18/11: 3 dias y la entrega del 15/11 vencida (16/11 09:00) -> se liquida con lo que hay (sin rama v3 'pending').
  h := public.cl_housekeeping('2026-11-18 10:00+03');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plan_quotas WHERE id = q1) = 'unfilled'
                     AND (SELECT status FROM public.cl_plan_quotas WHERE id = q2) = 'unfilled'
                     AND (h->>'late_weeks_settled')::int = 2, 'D27: semanas liquidadas: ' || h::text);
  v := pg_temp.inc(f1, 'quota_unfilled');
  PERFORM pg_temp.ok(v.id IS NOT NULL AND v.plan_id = '90000000-0000-0000-0000-0000000000f1' AND jsonb_array_length(v.periods) = 2
                     AND (SELECT sum((e->>'missing')::int) FROM jsonb_array_elements(v.periods) e) = 4,
                     'quota_unfilled con las dos semanas: ' || coalesce(v.periods::text, 'null'));
  PERFORM pg_temp.ok(pg_temp.nn(f1, 'quota_unfilled', 'carrier') = 0 AND pg_temp.nn(f1, 'quota_unfilled', 'account_manager') = 2,
                     'quota_unfilled: solo la cuenta, un aviso por semana');
  -- Ni el job ni una entrega la cierran.
  h := public.cl_housekeeping('2026-11-19 10:00+03');
  d := pg_temp.dlv(f1, '2026-11-18', 30);
  UPDATE public.cl_deliveries SET status = 'processing' WHERE id = d;
  UPDATE public.cl_deliveries SET status = 'processed', finished_at = now() WHERE id = d;
  PERFORM pg_temp.ok((pg_temp.inc(f1, 'quota_unfilled')).id = v.id, 'quota_unfilled no se cierra sola');
  -- Una cuota de un conector en prueba no se liquida por D27.
  UPDATE public.cl_feeds SET status = 'testing' WHERE id = 'f0000000-0000-0000-0000-0000000000f2';
  INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned, samples_obtained) VALUES
    ('91000000-0000-0000-0000-0000000000f3','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000f2','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,46,'2026-11-09','2026-11-15',3,0);
  h := public.cl_housekeeping('2026-11-20 10:00+03');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plan_quotas WHERE id = '91000000-0000-0000-0000-0000000000f3') = 'pending',
                     'conector en prueba: sin D27');
END $$;

-- ================================================================ 7. cola de avisos
DO $$
DECLARE
  f1 constant uuid := 'f0000000-0000-0000-0000-0000000000f1';
  -- Reloj de la cola: despues de todo lo encolado (los disparadores encolan con now()).
  t0 constant timestamptz := now() + interval '1 day';
  j jsonb; it jsonb; v_id uuid; r text; n int;
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises('SELECT public.cl_notify_claim(''bad token!'')') LIKE '22023:CL_BAD_REQUEST%', 'token validado');
  j := public.cl_notify_claim('tok-aaaa-1111', 100, 300, t0);
  PERFORM pg_temp.ok(jsonb_array_length(j) > 0, 'hay avisos pendientes');
  -- Contenido: AM + DO de la cuenta (no el UPU del fixture), idioma de la cuenta, sin ids ni codigos internos.
  -- Un correo por direccion (ronda 1): cada aviso lleva una sola direccion; AM y DO por separado.
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(j) x WHERE jsonb_array_length(x->'to') <> 1), 'una direccion por aviso');
  PERFORM pg_temp.ok((SELECT jsonb_agg(DISTINCT x->'to'->>0) FROM jsonb_array_elements(j) x
                       WHERE x->>'recipient_kind' = 'account_manager' AND x->>'incident_type' = 'quota_unfilled')
                     = '["am@t.l","do@t.l"]'::jsonb, 'destinatarios de la cuenta: AM y DO');
  SELECT x INTO it FROM jsonb_array_elements(j) x WHERE x->>'recipient_kind' = 'account_manager' AND x->>'incident_type' = 'quota_unfilled' LIMIT 1;
  PERFORM pg_temp.ok(it->>'language' = 'fr' AND it->>'connector' = 'Feed One' AND (it->'periods'->0->>'missing')::int > 0, 'datos del aviso: ' || it::text);
  PERFORM pg_temp.ok(j::text NOT LIKE '%quota_id%' AND j::text NOT LIKE '%"key"%' AND j::text NOT LIKE '%CL_%'
                     AND j::text NOT LIKE '%delivery:%' AND j::text NOT LIKE '%actor@t.l%', 'sin ids ni codigos ni otros correos');
  SELECT x INTO it FROM jsonb_array_elements(j) x WHERE x->>'recipient_kind' = 'carrier' LIMIT 1;
  PERFORM pg_temp.ok(it->'to' = '["ops@carrier.example"]'::jsonb, 'correo del maestro de carriers: ' || coalesce((it->'to')::text, 'null'));
  PERFORM pg_temp.ok((SELECT bool_and(status = 'sending' AND attempts = 1 AND lease_token = 'tok-aaaa-1111')
                        FROM public.cl_notifications WHERE id IN (SELECT (x->>'notification_id')::uuid FROM jsonb_array_elements(j) x)),
                     'reclamados con arriendo');
  -- Con el arriendo vivo nadie mas los toma.
  PERFORM pg_temp.ok(jsonb_array_length(public.cl_notify_claim('tok-bbbb-2222', 100, 300, t0 + interval '1 minute')) = 0, 'arriendo vivo');

  v_id := (it->>'notification_id')::uuid;
  -- Enviado: no se vuelve a reclamar.
  PERFORM pg_temp.ok(public.cl_notify_result(v_id, 'tok-aaaa-1111', true, NULL, false, 're_123-abc', t0) = 'sent', 'sent');
  PERFORM pg_temp.ok(public.cl_notify_result(v_id, 'tok-aaaa-1111', true, NULL, false, NULL, t0) = 'lost', 'doble resultado: lost');
  PERFORM pg_temp.ok((SELECT provider_id FROM public.cl_notifications WHERE id = v_id) = 're_123-abc', 'id del proveedor');

  -- Arriendo caducado (la funcion murio sin contestar): se reclama otra vez (intento 2) y el token viejo ya no vale.
  j := public.cl_notify_claim('tok-cccc-3333', 100, 300, t0 + interval '10 minutes');
  PERFORM pg_temp.ok(NOT (j @> jsonb_build_array(jsonb_build_object('notification_id', v_id))), 'el enviado no vuelve');
  it := j->0;
  v_id := (it->>'notification_id')::uuid;
  PERFORM pg_temp.ok((SELECT attempts FROM public.cl_notifications WHERE id = v_id) = 2, 're-reclamado: intento 2');
  PERFORM pg_temp.ok(public.cl_notify_result(v_id, 'tok-aaaa-1111', true) = 'lost', 'token viejo: lost');
  -- Fallo temporal con texto libre: pending con espera y codigo generico.
  r := public.cl_notify_result(v_id, 'tok-cccc-3333', false, 'boom: key re_secret', false, NULL, t0 + interval '10 minutes');
  PERFORM pg_temp.ok(r = 'pending' AND (SELECT last_error = 'CL_SEND_ERROR' AND next_attempt_at = t0 + interval '20 minutes'
                                          FROM public.cl_notifications WHERE id = v_id), 'reintento con espera: ' || r);
  PERFORM pg_temp.ok(NOT (public.cl_notify_claim('tok-dddd-4444', 100, 300, t0 + interval '11 minutes')
                          @> jsonb_build_array(jsonb_build_object('notification_id', v_id))), 'antes de la espera no se toma');
  -- Fallo definitivo (p. ej. 422 del proveedor): failed.
  UPDATE public.cl_notifications SET status = 'pending', lease_token = NULL, lease_until = NULL WHERE id = v_id;
  j := public.cl_notify_claim('tok-eeee-5555', 100, 300, t0 + interval '30 minutes');
  r := public.cl_notify_result(v_id, 'tok-eeee-5555', false, 'RESEND_422', true, NULL, t0);
  PERFORM pg_temp.ok(r = 'failed' AND (SELECT last_error FROM public.cl_notifications WHERE id = v_id) = 'RESEND_422',
                     'definitivo: failed: ' || r || ' ' || (SELECT row_to_json(zz)::text FROM public.cl_notifications zz WHERE zz.id = v_id));
  -- 5 intentos con el arriendo caducado: failed.
  UPDATE public.cl_notifications SET attempts = 5 WHERE status = 'sending';
  j := public.cl_notify_claim('tok-ffff-6666', 100, 300, t0 + interval '2 hours');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_notifications WHERE attempts >= 5 AND status IN ('sending','pending')),
                     '5 intentos: failed');
  -- Sin destinatarios (A1 sin AM ni DO): skipped, no se envia.
  DELETE FROM public.account_user_role WHERE account_id = 'a0000000-0000-0000-0000-000000000001'
     AND role IN ('account_manager','do_coordinator');
  PERFORM public.cl_incident_record('a0000000-0000-0000-0000-000000000001', f1, NULL, 'missing_delivery',
                                    '[{"key":"x/y","period_start":"2026-11-25","period_end":"2026-11-25"}]', NULL, t0);
  j := public.cl_notify_claim('tok-gggg-7777', 100, 300, t0 + interval '3 hours');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(j) x WHERE x->>'recipient_kind' = 'account_manager'
                                   AND x->>'incident_type' = 'missing_delivery'), 'sin destinatarios: no sale');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_notifications WHERE status = 'skipped' AND last_error = 'CL_NO_RECIPIENT'
                               AND recipient_email IS NULL AND recipient_kind = 'account_manager'), 'skipped sin direccion');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(j) x WHERE x->>'recipient_kind' = 'carrier'
                               AND x->>'incident_type' = 'missing_delivery'), 'el carrier si');
  INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
    ('a0000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000091','account_manager'),
    ('a0000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000092','do_coordinator');
  -- Sin secretos de Vault, el kick no llama a nadie.
  PERFORM pg_temp.ok(public.cl_notify_kick(t0 + interval '3 hours') IS FALSE, 'kick sin secretos: no llama');
END $$;

-- ================================================================ 8. pantalla: permisos y aislamiento
-- Incidencia de A2 (otra cuenta).
SELECT public.cl_incident_record('a0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-0000000000f9', NULL,
                                 'missing_delivery', '[{"key":"a","period_start":"2026-11-10","period_end":"2026-11-10"}]');
SELECT set_config('t.foreign', (SELECT id::text FROM public.cl_incidents WHERE account_id = 'a0000000-0000-0000-0000-000000000002'), true);
SET ROLE authenticated;
DO $$
DECLARE
  a1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  a2 constant uuid := 'a0000000-0000-0000-0000-000000000002';
  fid uuid := current_setting('t.foreign')::uuid;
  j jsonb; v_id uuid; e1 text; e2 text; e3 text; e4 text;
BEGIN
  -- DO (solo View): lista y detalle, sin cambios.
  PERFORM pg_temp.as_user('92000000-0000-0000-0000-000000000092', 'authenticated');
  j := public.cl_incidents_list(a1);
  PERFORM pg_temp.ok((j->>'total')::int >= 5 AND (j->>'limit')::int = 100, 'lista DO: ' || (j->>'total'));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(j->'items') x WHERE x->>'feed_id' = 'f0000000-0000-0000-0000-0000000000f9'),
                     'sin las de A2');
  PERFORM pg_temp.ok((public.cl_incidents_list(a1, 'resolved')->>'total')::int >= 3
                     AND (public.cl_incidents_list(a1, NULL, 'quota_unfilled')->>'total')::int = 1
                     AND (public.cl_incidents_list(a1, 'unresolved', NULL, 'f0000000-0000-0000-0000-0000000000f2')->>'total')::int = 1
                     AND (public.cl_incidents_list(a1, NULL, NULL, NULL, 5000)->>'limit')::int = 1000
                     AND jsonb_array_length(public.cl_incidents_list(a1, NULL, NULL, NULL, 1, 1)->'items') = 1, 'filtros y paginas');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_incidents_list(%L, ''bogus'')', a1)) LIKE '22023:CL_BAD_REQUEST%', 'filtro invalido');
  SELECT (x->>'id')::uuid INTO v_id FROM jsonb_array_elements(public.cl_incidents_list(a1, NULL, 'quota_unfilled')->'items') x;
  j := public.cl_incident_get(v_id);
  PERFORM pg_temp.ok(j->>'incident_type' = 'quota_unfilled' AND j->>'plan_name' = 'P1' AND jsonb_array_length(j->'notifications') = 4
                     AND j::text NOT LIKE '%@%' AND NOT (j->>'carrier_notified')::boolean, 'detalle sin correos: ' || j::text);
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_incidents) >= 5 AND NOT EXISTS (SELECT 1 FROM public.cl_incidents WHERE account_id = a2),
                     'RLS: solo su cuenta');
  e1 := pg_temp.raises(format('SELECT public.cl_incident_update(%L, ''in_progress'')', v_id));
  PERFORM pg_temp.ok(e1 = '42501:CL_FORBIDDEN', 'View no edita: ' || coalesce(e1, 'ok'));

  -- AM (Edit): estado, responsable, nota; reglas.
  PERFORM pg_temp.as_user('91000000-0000-0000-0000-000000000091', 'authenticated');
  j := public.cl_incident_update(v_id, 'in_progress', '92000000-0000-0000-0000-000000000092', 'Revisar cuotas');
  PERFORM pg_temp.ok(j->>'status' = 'in_progress' AND j->>'assignee_name' = 'Dora DO' AND j->>'notes' = 'Revisar cuotas', 'actualizada: ' || j::text);
  j := public.cl_incident_update(v_id, NULL, NULL, '', true);
  PERFORM pg_temp.ok(j->>'status' = 'in_progress' AND j->'assignee_id' = 'null'::jsonb AND j->'notes' = 'null'::jsonb, 'quitar responsable y nota');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_incident_update(%L, ''resolved'')', v_id)) LIKE '22023:CL_BAD_REQUEST%',
                     'resolved solo por cerrar');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_incident_update(%L, NULL, %L)', v_id, '98000000-0000-0000-0000-000000000098'))
                     LIKE '22023:CL_BAD_REQUEST%', 'responsable de otra cuenta');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_incident_update(%L, NULL, NULL, %L)', v_id, repeat('x', 4001)))
                     LIKE '22023:CL_BAD_REQUEST%', 'nota demasiado larga');
  -- quota_unfilled: solo a mano.
  j := public.cl_incident_close(v_id);
  PERFORM pg_temp.ok(j->>'status' = 'resolved' AND j->>'closed_how' = 'manual', 'quota_unfilled cerrada a mano');
  e1 := pg_temp.raises(format('SELECT public.cl_incident_update(%L, ''open'')', v_id));
  PERFORM pg_temp.ok(e1 = '22023:CL_INCIDENT_CLOSED', 'resuelta no se edita: ' || coalesce(e1, 'ok'));

  -- Ajena, inexistente y NULL: el mismo 42501.
  e1 := pg_temp.raises(format('SELECT public.cl_incident_get(%L)', fid));
  e2 := pg_temp.raises(format('SELECT public.cl_incident_get(%L)', gen_random_uuid()));
  e3 := pg_temp.raises('SELECT public.cl_incident_get(NULL)');
  e4 := pg_temp.raises(format('SELECT public.cl_incident_close(%L)', fid));
  PERFORM pg_temp.ok(e1 = '42501:CL_FORBIDDEN' AND e2 = e1 AND e3 = e1 AND e4 = e1, 'mismo error: ' || coalesce(e1, 'ok') || ' ' || coalesce(e2, 'ok'));
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_incident_update(%L, ''in_progress'')', fid)) = '42501:CL_FORBIDDEN', 'update ajena');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_incidents_list(%L)', a2)) = '42501:CL_FORBIDDEN', 'lista de otra cuenta');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_incidents WHERE id = fid) IS NULL, 'la de A2 ni se ve');
  -- Sin derecho cl_incidents (PM; el UPU del fixture tampoco lo tiene en A1): nada.
  PERFORM pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_incidents_list(%L)', a1)) = '42501:CL_FORBIDDEN', 'PM sin derecho');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_incident_get(%L)', v_id)) = '42501:CL_FORBIDDEN', 'PM detalle');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_incidents) = 0, 'PM: RLS sin filas');
  PERFORM pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_incidents_list(%L)', a1)) = '42501:CL_FORBIDDEN', 'UPU de A1 sin el permiso');
  -- Usuario de A2 no ve las de A1.
  PERFORM pg_temp.as_user('98000000-0000-0000-0000-000000000098', 'authenticated');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_incident_get(%L)', v_id)) = '42501:CL_FORBIDDEN', 'A2 no ve A1');
END $$;
RESET ROLE;
SET ROLE anon;
DO $$ BEGIN
  PERFORM pg_temp.ok(pg_temp.raises('SELECT public.cl_incidents_list(''a0000000-0000-0000-0000-000000000001'')') LIKE '42501:%', 'anon');
END $$;
RESET ROLE;

ROLLBACK;
