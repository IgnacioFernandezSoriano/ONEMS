-- Carrier Link fase 0, tarea 3: tablas cl_* (plan, captura, muestra), RLS por opcion de acceso,
-- FK api_keys.feed_id, api_key_issue validado y reset de cuentas.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.raises(p_sql text) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN false; EXCEPTION WHEN OTHERS THEN RETURN true; END $$;

CREATE OR REPLACE FUNCTION pg_temp.sqlstate_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE; END $$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Usuarios: 93 AM A1, 94 UPU AM A1, 95 APM A1, 91 sin rol, 92 UPU AM A2, 97 superadmin.
INSERT INTO auth.users (id, email) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l'),
  ('94000000-0000-0000-0000-000000000094','upu@t.l'),
  ('95000000-0000-0000-0000-000000000095','apm@t.l'),
  ('91000000-0000-0000-0000-000000000091','x@t.l'),
  ('92000000-0000-0000-0000-000000000092','upu2@t.l'),
  ('97000000-0000-0000-0000-000000000097','super@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001'),
  ('94000000-0000-0000-0000-000000000094','upu@t.l','UPU','user','a0000000-0000-0000-0000-000000000001'),
  ('95000000-0000-0000-0000-000000000095','apm@t.l','APM','user','a0000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-000000000091','x@t.l','X','user','a0000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-000000000092','upu2@t.l','UPU2','user','a0000000-0000-0000-0000-000000000002'),
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000093','account_manager'),
  ('a0000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000094','upu_account_manager'),
  ('a0000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000095','allocation_plan_manager'),
  ('a0000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000092','upu_account_manager');

INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','PR2','Prod2',48);

-- Filas de A1 y de A2 en cada tabla (como postgres, account_id explicito).
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name) VALUES
  ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1'),
  ('f0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','Feed A2');
INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','item_id','barcode'),
  ('a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','item_id','barcode');
INSERT INTO public.cl_value_mappings (account_id, carrier_id, kind, carrier_value, onems_value) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','EXP','PR'),
  ('a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','product','EXP','PR2');
INSERT INTO public.cl_extra_fields (account_id, carrier_id, carrier_field) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','weight'),
  ('a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','weight');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','Plan A1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2027-03-01','2027-03-31'),
  ('90000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000002','Plan A2','ca000000-0000-0000-0000-000000000002','cb000000-0000-0000-0000-000000000002',10,'2027-03-01','2027-03-31');
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2027,10,'2027-03-08','2027-03-14',5);
INSERT INTO public.cl_demands (id, account_id, plan_id, feed_id, random_seed, payload) VALUES
  ('92000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','f0000000-0000-0000-0000-0000000000a1','seed1','{}'),
  ('92000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-0000000000a2','f0000000-0000-0000-0000-0000000000a2','seed2','{}');
INSERT INTO public.cl_batches (id, account_id, demand_id, connector_batch_id, status) VALUES
  ('93000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-0000000000a1','B1','received'),
  ('93000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-0000000000a2','B1','received');
INSERT INTO public.cl_batch_scans (account_id, batch_id, stratum_id, item_id, status) VALUES
  ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-0000000000a1','91000000-0000-0000-0000-0000000000a1','I1','valid'),
  ('a0000000-0000-0000-0000-000000000002','93000000-0000-0000-0000-0000000000a2',NULL,'I1','valid');
INSERT INTO public.cl_sampling_runs (account_id, demand_id, batch_id, stratum_id) VALUES
  ('a0000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-0000000000a1','93000000-0000-0000-0000-0000000000a1','91000000-0000-0000-0000-0000000000a1');
INSERT INTO public.cl_alerts (account_id, plan_id, batch_id, alert_type, severity) VALUES
  ('a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','93000000-0000-0000-0000-0000000000a1','x','low'),
  ('a0000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-0000000000a2','93000000-0000-0000-0000-0000000000a2','x','low');
INSERT INTO public.cl_samples (id, account_id, plan_id, quota_id, batch_id, carrier_id, product_id, item_id) VALUES
  ('94000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','91000000-0000-0000-0000-0000000000a1','93000000-0000-0000-0000-0000000000a1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001','ITEM1'),
  ('94000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-0000000000a2',NULL,'93000000-0000-0000-0000-0000000000a2','ca000000-0000-0000-0000-000000000002','cb000000-0000-0000-0000-000000000002','ITEM1');
INSERT INTO public.cl_sample_scans (account_id, sample_id, role, scan_at) VALUES
  ('a0000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-0000000000a1','start', now());

-- Tabla -> filas de A1 que ve su AM (A2 no tiene filas en 3 de ellas, da igual: se comprueba account_id).
CREATE TEMP TABLE cl_expect (t text, n1 int);
INSERT INTO cl_expect VALUES
  ('cl_feeds',1),('cl_field_mappings',1),('cl_value_mappings',1),('cl_extra_fields',1),
  ('cl_plans',1),('cl_plan_quotas',1),('cl_demands',1),('cl_batches',1),('cl_batch_scans',1),
  ('cl_sampling_runs',1),('cl_alerts',1),('cl_samples',1),('cl_sample_scans',1);
GRANT SELECT ON cl_expect TO authenticated, anon, service_role;

-- 1. RLS activo en todas y anon sin privilegios.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT t FROM cl_expect LOOP
    PERFORM pg_temp.ok((SELECT relrowsecurity FROM pg_class WHERE oid = ('public.' || r.t)::regclass), 'RLS activo en ' || r.t);
    PERFORM pg_temp.ok(NOT has_table_privilege('anon', 'public.' || r.t, 'SELECT'), 'anon sin SELECT en ' || r.t);
  END LOOP;
END $$;

-- 2. Usuario sin rol: 0 filas en todas, aunque existan.
SET ROLE authenticated;
SELECT pg_temp.as_user('91000000-0000-0000-0000-000000000091', 'authenticated');
DO $$
DECLARE r record; n int;
BEGIN
  FOR r IN SELECT t FROM cl_expect LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', r.t) INTO n;
    PERFORM pg_temp.ok(n = 0, 'sin rol ve 0 en ' || r.t || ' (ve ' || n || ')');
  END LOOP;
END $$;
RESET ROLE;

-- 3. AM de A1: ve las de A1 y ninguna de A2.
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE r record; n int;
BEGIN
  FOR r IN SELECT t, n1 FROM cl_expect LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', r.t) INTO n;
    PERFORM pg_temp.ok(n = r.n1, 'AM ve ' || r.n1 || ' en ' || r.t || ' (ve ' || n || ')');
    EXECUTE format('SELECT count(*) FROM public.%I WHERE account_id <> %L', r.t, 'a0000000-0000-0000-0000-000000000001') INTO n;
    PERFORM pg_temp.ok(n = 0, 'AM no ve filas de A2 en ' || r.t);
  END LOOP;
  -- AM (Edit en cl_plans y cl_connectors): inserta en A1, no en A2.
  INSERT INTO public.cl_plans (account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date)
    VALUES ('a0000000-0000-0000-0000-000000000001','Nuevo','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',5,'2027-04-01','2027-04-30');
  INSERT INTO public.cl_feeds (account_id, carrier_id, name) VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Otro');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_plans (account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date)
    VALUES ('a0000000-0000-0000-0000-000000000002','X','ca000000-0000-0000-0000-000000000002','cb000000-0000-0000-0000-000000000002',5,'2027-04-01','2027-04-30')$q$),
    'AM no inserta en A2');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE plan_name = 'Nuevo') = 'draft', 'status por defecto draft');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_feeds WHERE name = 'Otro') = 'testing', 'status por defecto testing');
  -- cl_samples solo View para AM: no escribe. cl_monitor Edit: escribe alertas.
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_samples (account_id, item_id) VALUES ('a0000000-0000-0000-0000-000000000001','ZZ')$q$),
    'AM (View en cl_samples) no inserta muestras');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_alerts (account_id, alert_type, severity) VALUES ('a0000000-0000-0000-0000-000000000001','y','low')$q$),
    'AM no inserta alertas (solo funciones)');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_demands (account_id, plan_id, feed_id, random_seed, payload)
    VALUES ('a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','f0000000-0000-0000-0000-0000000000a1','s','{}')$q$),
    'AM no inserta demandas');
  PERFORM pg_temp.ok(pg_temp.raises($q$DELETE FROM public.cl_samples WHERE account_id = 'a0000000-0000-0000-0000-000000000001'$q$),
    'AM no borra muestras');
  PERFORM pg_temp.ok(pg_temp.raises($q$UPDATE public.cl_samples SET status = 'voided'$q$), 'AM no actualiza muestras');
  UPDATE public.cl_alerts SET status = 'acknowledged', acknowledged_by = auth.uid(), acknowledged_at = now()
   WHERE account_id = 'a0000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE status = 'acknowledged') = 1, 'AM actualiza cl_alerts.status');
  PERFORM pg_temp.ok(pg_temp.raises($q$UPDATE public.cl_alerts SET alert_type = 'z'$q$), 'AM no actualiza cl_alerts.alert_type');
  PERFORM pg_temp.ok(pg_temp.raises($q$DELETE FROM public.cl_alerts$q$), 'AM no borra alertas');
  -- referencias de otra cuenta
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$INSERT INTO public.cl_plans (account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date)
    VALUES ('a0000000-0000-0000-0000-000000000001','Y','ca000000-0000-0000-0000-000000000002','cb000000-0000-0000-0000-000000000001',5,'2027-04-01','2027-04-30')$q$) = '23514', 'plan con carrier de B');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$INSERT INTO public.cl_plans (account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date)
    VALUES ('a0000000-0000-0000-0000-000000000001','Y','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000002',5,'2027-04-01','2027-04-30')$q$) = '23514', 'plan con producto de B');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$INSERT INTO public.cl_plans (account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, feed_id)
    VALUES ('a0000000-0000-0000-0000-000000000001','Y','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',5,'2027-04-01','2027-04-30','f0000000-0000-0000-0000-0000000000a2')$q$) = '23514', 'plan con feed de B');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$INSERT INTO public.cl_value_mappings (account_id, carrier_id, kind, carrier_value, onems_value)
    VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000002','product','Q','PR')$q$) = '23514', 'mapeo con carrier de B');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_plans SET carrier_id = 'ca000000-0000-0000-0000-000000000002' WHERE plan_name = 'Nuevo'$q$) = '23514', 'UPDATE de carrier a B');
  DELETE FROM public.cl_feeds WHERE name = 'Otro';
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_feeds WHERE name = 'Otro'), 'AM borra su feed');
END $$;
RESET ROLE;

-- 4. APM de A1: Edit en cl_plans; sin acceso a cl_connectors; View en cl_samples y cl_monitor.
SET ROLE authenticated;
SELECT pg_temp.as_user('95000000-0000-0000-0000-000000000095', 'authenticated');
DO $$
DECLARE n int;
BEGIN
  INSERT INTO public.cl_plans (account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date)
    VALUES ('a0000000-0000-0000-0000-000000000001','Plan APM','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',5,'2027-05-01','2027-05-31');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_plan_quotas (account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned)
    VALUES ('a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000001',2027,10,'2027-03-08','2027-03-14',3)$q$),
    'APM no inserta cuotas (solo funciones)');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_feeds (account_id, carrier_id, name) VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','nope')$q$),
    'APM no inserta en cl_feeds');
  SELECT count(*) INTO n FROM public.cl_feeds;
  PERFORM pg_temp.ok(n = 0, 'APM no ve cl_feeds');
  SELECT count(*) INTO n FROM public.cl_samples;
  PERFORM pg_temp.ok(n = 1, 'APM ve cl_samples (View)');
  SELECT count(*) INTO n FROM public.cl_alerts;
  PERFORM pg_temp.ok(n >= 1, 'APM ve cl_alerts (View)');
  UPDATE public.cl_alerts SET status = 'dismissed';
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM pg_temp.ok(n = 0, 'APM (View en cl_monitor) no actualiza alertas');
  -- UPDATE sin permiso no cambia filas
  UPDATE public.cl_feeds SET name = 'hack';
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM pg_temp.ok(n = 0, 'APM no actualiza feeds');
END $$;
RESET ROLE;

-- 5. UPU AM de A2 no ve A1; superadmin ve todo.
SET ROLE authenticated;
SELECT pg_temp.as_user('92000000-0000-0000-0000-000000000092', 'authenticated');
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.cl_plans;
  PERFORM pg_temp.ok(n = 1, 'UPU A2 ve solo su plan');
  SELECT count(*) INTO n FROM public.cl_plans WHERE account_id = 'a0000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.ok(n = 0, 'UPU A2 no ve planes de A1');
END $$;
SELECT pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.cl_plans;
  PERFORM pg_temp.ok(n >= 3, 'superadmin ve todos los planes');
END $$;
RESET ROLE;

-- 6. anon: error.
SET ROLE anon;
SELECT pg_temp.as_user('', 'anon');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises('SELECT 1 FROM public.cl_plans'), 'anon no lee cl_plans');
  PERFORM pg_temp.ok(pg_temp.raises('SELECT 1 FROM public.cl_samples'), 'anon no lee cl_samples');
END $$;
RESET ROLE;

-- 6b. Ciudad de otra cuenta en una cuota (como postgres; el trigger vale para cualquiera).
INSERT INTO public.regions (id, account_id, name, code) VALUES ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','City3','C3');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$INSERT INTO public.cl_plan_quotas (account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned)
    VALUES ('a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000003',2027,11,'2027-03-15','2027-03-21',1)$q$) = '23514', 'cuota con ciudad de B');
END $$;

-- 7. Muestras: unicidad entre activas; vale si la anterior esta anulada; borrar muestra borra one_db.
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_samples (account_id, carrier_id, item_id)
    VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','ITEM1')$q$), 'dos activas con mismo item fallan');
  UPDATE public.cl_samples SET status = 'voided' WHERE id = '94000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.ok(NOT pg_temp.raises($q$INSERT INTO public.cl_samples (id, account_id, carrier_id, item_id)
    VALUES ('94000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','ITEM1')$q$),
    'pasa si la primera esta voided');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_samples (account_id, carrier_id, item_id, status)
    VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','ITEMX','otro')$q$), 'status invalido');
END $$;
INSERT INTO public.one_db (account_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name,
                           sent_at, received_at, total_transit_days, source_data_snapshot, source, cl_sample_id, carrier_id)
VALUES ('a0000000-0000-0000-0000-000000000001','ITEM1','P','Carrier','Prod','City1','City2', now() - interval '2 day', now(), 2, '{}',
        'carrier','94000000-0000-0000-0000-0000000000b1','ca000000-0000-0000-0000-000000000001');
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM public.one_db WHERE cl_sample_id = '94000000-0000-0000-0000-0000000000b1') = 1, 'one_db enlazada');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$DELETE FROM public.cl_samples WHERE id = '94000000-0000-0000-0000-0000000000b1'$q$) = '23503', 'borrar muestra con one_db: RESTRICT');
  DELETE FROM public.one_db WHERE cl_sample_id = '94000000-0000-0000-0000-0000000000b1';
  DELETE FROM public.cl_samples WHERE id = '94000000-0000-0000-0000-0000000000b1';
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_samples WHERE id = '94000000-0000-0000-0000-0000000000b1'), 'muestra borrada tras quitar one_db');
END $$;

-- 8. Restricciones de forma.
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field)
    VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','item_id','otro')$q$), 'UNIQUE field_mappings');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field)
    VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','nope','otro')$q$), 'standard_field invalido');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_batches (account_id, demand_id, connector_batch_id, status)
    VALUES ('a0000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-0000000000a1','B1','received')$q$), 'UNIQUE batches');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_sampling_runs (account_id, demand_id, batch_id, stratum_id)
    VALUES ('a0000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-0000000000a1','93000000-0000-0000-0000-0000000000a1','91000000-0000-0000-0000-0000000000a1')$q$), 'UNIQUE sampling_runs');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_plan_quotas (account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned)
    VALUES ('a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2027,10,'2027-03-08','2027-03-14',1)$q$), 'UNIQUE quotas');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.cl_feeds (account_id, carrier_id, name, status) VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','n','zzz')$q$), 'status feed invalido');
  -- borrar un lote borra sus escaneos
  DELETE FROM public.cl_sample_scans;
  DELETE FROM public.cl_samples WHERE account_id = 'a0000000-0000-0000-0000-000000000001';
  DELETE FROM public.cl_sampling_runs;
  DELETE FROM public.cl_alerts WHERE account_id = 'a0000000-0000-0000-0000-000000000001';
  DELETE FROM public.cl_batches WHERE id = '93000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_batch_scans WHERE batch_id = '93000000-0000-0000-0000-0000000000a1'), 'borrar lote borra escaneos');
END $$;

-- 9. api_keys <-> cl_feeds.
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.api_keys (account_id, key_hash, scope, feed_id)
    VALUES ('a0000000-0000-0000-0000-000000000001', repeat('c',64), 'carrier_feed', NULL)$q$), 'carrier_feed sin feed viola CHECK');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.api_keys (account_id, key_hash, scope, feed_id)
    VALUES ('a0000000-0000-0000-0000-000000000001', repeat('d',64), 'onedb_read', 'f0000000-0000-0000-0000-0000000000a1')$q$), 'onedb_read con feed viola CHECK');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.api_keys (account_id, key_hash, scope, feed_id)
    VALUES ('a0000000-0000-0000-0000-000000000001', repeat('e',64), 'carrier_feed', 'f0000000-0000-0000-0000-00000000dead')$q$), 'feed inexistente viola FK');
  INSERT INTO public.api_keys (id, account_id, key_hash, scope, feed_id)
    VALUES ('b3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001', repeat('f',64), 'carrier_feed', 'f0000000-0000-0000-0000-0000000000a1');
END $$;
SET ROLE authenticated;
SELECT pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
DO $$
DECLARE i record;
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001','k','carrier_feed','f0000000-0000-0000-0000-0000000000a2')$q$),
    'carrier_feed con feed de otra cuenta falla');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001','k','carrier_feed')$q$),
    'carrier_feed sin feed falla');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001','k','carrier_feed','f0000000-0000-0000-0000-00000000dead')$q$),
    'carrier_feed con feed inexistente falla');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001','k','onedb_read','f0000000-0000-0000-0000-0000000000a1')$q$),
    'onedb_read con feed falla');
  SELECT * INTO i FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001','Feed A1 key','carrier_feed','f0000000-0000-0000-0000-0000000000a1');
  PERFORM pg_temp.ok(i.api_key LIKE 'onems\_%', 'UPU AM emite carrier_feed para feed propio');
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM public.api_keys WHERE feed_id = 'f0000000-0000-0000-0000-0000000000a1') = 2, 'dos claves del feed A1');
  DELETE FROM public.cl_demands WHERE feed_id = 'f0000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$DELETE FROM public.cl_feeds WHERE id = 'f0000000-0000-0000-0000-0000000000a1'$q$) = '23503', 'feed con claves: RESTRICT');
  DELETE FROM public.api_keys WHERE feed_id = 'f0000000-0000-0000-0000-0000000000a1';
  DELETE FROM public.cl_feeds WHERE id = 'f0000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_feeds WHERE id = 'f0000000-0000-0000-0000-0000000000a1'), 'feed borrado tras quitar claves');
END $$;

-- 10. Reset de cuenta borra cl_* y puntos de lectura de transportista.
INSERT INTO public.readers (account_id, name, type, capture_source, carrier_id, carrier_place_ref)
  VALUES ('a0000000-0000-0000-0000-000000000001','P1','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO');
INSERT INTO public.readers (account_id, reader_id, name, type) VALUES ('a0000000-0000-0000-0000-000000000001','RFID1','R1','Mixed');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name) VALUES
  ('f0000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','F3');
INSERT INTO public.cl_samples (account_id, carrier_id, item_id, start_reader_id)
  VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','ITEM9', (SELECT id FROM public.readers WHERE name = 'P1'));
INSERT INTO public.api_keys (account_id, key_hash, scope, feed_id)
  VALUES ('a0000000-0000-0000-0000-000000000001', repeat('9',64), 'carrier_feed', 'f0000000-0000-0000-0000-0000000000a3');
INSERT INTO public.one_db (account_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name,
                           sent_at, received_at, total_transit_days, source_data_snapshot, source, cl_sample_id, carrier_id)
VALUES ('a0000000-0000-0000-0000-000000000001','ITEM9','P','Carrier','Prod','City1','City2', now() - interval '2 day', now(), 2, '{}',
        'carrier',(SELECT id FROM public.cl_samples WHERE item_id = 'ITEM9'),'ca000000-0000-0000-0000-000000000001');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.admin_reset_account_data('a0000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.ok((r->>'success')::boolean, 'admin_reset_account_data ok: ' || r::text);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_plans WHERE account_id = 'a0000000-0000-0000-0000-000000000001'), 'reset borra cl_plans');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_samples WHERE account_id = 'a0000000-0000-0000-0000-000000000001'), 'reset borra cl_samples');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_feeds WHERE account_id = 'a0000000-0000-0000-0000-000000000001'), 'reset borra cl_feeds');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.readers WHERE capture_source = 'carrier_scan' AND account_id = 'a0000000-0000-0000-0000-000000000001'), 'reset borra puntos carrier_scan');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.readers WHERE reader_id = 'RFID1'), 'reset conserva lectores RFID');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_plans WHERE account_id = 'a0000000-0000-0000-0000-000000000002'), 'reset no toca A2');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.api_keys WHERE feed_id = 'f0000000-0000-0000-0000-0000000000a3'), 'reset borra claves de feeds');
  PERFORM pg_temp.ok(pg_get_functiondef('public.admin_reset_demo2()'::regprocedure) LIKE '%cl_samples%', 'admin_reset_demo2 borra cl_*');
  PERFORM pg_temp.ok((SELECT proconfig FROM pg_proc WHERE oid = 'public.admin_reset_demo2()'::regprocedure) @> ARRAY['search_path=public','row_security=off'], 'admin_reset_demo2 conserva su config');
  PERFORM pg_temp.ok((SELECT proconfig FROM pg_proc WHERE oid = 'public.admin_reset_account_data(text)'::regprocedure) @> ARRAY['search_path=public'], 'admin_reset_account_data search_path');
  PERFORM pg_temp.ok((SELECT proconfig FROM pg_proc WHERE oid = 'public.admin_reset_and_seed_demo2()'::regprocedure) @> ARRAY['search_path=public'], 'admin_reset_and_seed_demo2 search_path');
  PERFORM pg_temp.ok(pg_get_functiondef('public.admin_reset_and_seed_demo2()'::regprocedure) LIKE '%cl_samples%', 'admin_reset_and_seed_demo2 borra cl_*');
END $$;

ROLLBACK;
\echo OK cl_tables
