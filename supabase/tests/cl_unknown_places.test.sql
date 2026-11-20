-- Carrier Link, revision final I3 (20261121100200_cl_unknown_places.sql): cl_unknown_places agrega en el servidor las
-- lecturas sin punto de lectura de un carrier. Autorizacion, aislamiento por cuenta, filtro por carrier, ventana de
-- dias, lugar vacio/NULL ignorado, lugar y modo recortados, orden y grants. Todo en BEGIN ... ROLLBACK.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.raises(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ':' || SQLERRM; END $$;

-- Resultado de la funcion como texto estable: 'lugar|modo|n;...' en el orden devuelto.
CREATE OR REPLACE FUNCTION pg_temp.up(p_account uuid, p_carrier uuid, p_days integer DEFAULT 90) RETURNS text
LANGUAGE sql AS $$
  SELECT coalesce(string_agg(u.place_ref || '|' || coalesce(u.mode_ref, '<NULL>') || '|' || u.readings, ';'), '')
    FROM public.cl_unknown_places(p_account, p_carrier, p_days) u
$$;

BEGIN;
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- A1: carrier 1 (fixture) y carrier 3; A2: carrier 2. Un plan, una demanda y un lote por carrier.
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','C3','Carrier3'),
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000003','P3','Prod3',48),
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','P2','Prod2',48);
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status) VALUES
  ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed 1','active'),
  ('f0000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000003','Feed 3','active'),
  ('f0000000-0000-0000-0000-0000000000b2','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','Feed 2','active');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','P1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',2,'2026-10-19','2026-10-25','active','f0000000-0000-0000-0000-0000000000a1'),
  ('90000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-000000000001','P3','ca000000-0000-0000-0000-000000000003','cb000000-0000-0000-0000-000000000003',2,'2026-10-19','2026-10-25','active','f0000000-0000-0000-0000-0000000000a3'),
  ('90000000-0000-0000-0000-0000000000b2','a0000000-0000-0000-0000-000000000002','P2','ca000000-0000-0000-0000-000000000002','cb000000-0000-0000-0000-000000000002',2,'2026-10-19','2026-10-25','active','f0000000-0000-0000-0000-0000000000b2');
INSERT INTO public.cl_demands (id, account_id, plan_id, feed_id, random_seed, payload) VALUES
  ('d0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','f0000000-0000-0000-0000-0000000000a1','s','{}'),
  ('d0000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a3','f0000000-0000-0000-0000-0000000000a3','s','{}'),
  ('d0000000-0000-0000-0000-0000000000b2','a0000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-0000000000b2','f0000000-0000-0000-0000-0000000000b2','s','{}');
INSERT INTO public.cl_batches (id, account_id, demand_id, connector_batch_id, status) VALUES
  ('ba000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-0000000000a1','B1','validated'),
  ('ba000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-0000000000a3','B3','validated'),
  ('ba000000-0000-0000-0000-0000000000b2','a0000000-0000-0000-0000-000000000002','d0000000-0000-0000-0000-0000000000b2','B2','validated');
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001');
INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
  ('ad000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','HAS','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','HAS','ADM','origin');

INSERT INTO public.cl_batch_scans (account_id, batch_id, place_ref, mode_ref, reader_id, scan_at, status, reject_reason)
SELECT 'a0000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-0000000000a1', v.place, v.mode, v.reader::uuid,
       now() - make_interval(days => v.ago), 'rejected', 'unknown_reading_point'
  FROM (VALUES
    ('NBO', 'ADM', NULL, 1), (' NBO ', 'ADM ', NULL, 2), ('NBO', 'ADM', NULL, 3),     -- NBO|ADM x3 (recortados)
    ('XYZ', '', NULL, 1), ('XYZ', NULL, NULL, 1),                                     -- modo vacio = NULL: XYZ x2
    ('MBA', 'DLV', NULL, 5),                                                          -- MBA|DLV x1
    (NULL, 'ADM', NULL, 1), ('', 'ADM', NULL, 1), ('   ', 'ADM', NULL, 1),            -- sin lugar: fuera
    ('OLD', 'ADM', NULL, 200),                                                        -- fuera de 90 dias
    ('HAS', 'ADM', 'ad000000-0000-0000-0000-000000000001', 1)                         -- tiene lector: fuera
  ) v(place, mode, reader, ago);
-- Carrier 3 de A1 y carrier 2 de A2: no deben salir en la consulta del carrier 1.
INSERT INTO public.cl_batch_scans (account_id, batch_id, place_ref, mode_ref, scan_at, status, reject_reason) VALUES
  ('a0000000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-0000000000a3','C3P','ADM', now(),'rejected','unknown_reading_point'),
  ('a0000000-0000-0000-0000-000000000002','ba000000-0000-0000-0000-0000000000b2','A2P','ADM', now(),'rejected','unknown_reading_point');

-- 96 panelist_manager de A1 (sin acceso a Carrier Link por defecto), 97 superadmin. 99 = UPU AM de A1, 98 = de A2.
INSERT INTO auth.users (id, email) VALUES
  ('96000000-0000-0000-0000-000000000096','pm@t.l'),
  ('97000000-0000-0000-0000-000000000097','super@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('96000000-0000-0000-0000-000000000096','pm@t.l','PM','user','a0000000-0000-0000-0000-000000000001'),
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000096','panelist_manager');

-- 1. Definicion y grants.
DO $$
DECLARE f regprocedure := 'public.cl_unknown_places(uuid,uuid,integer)'::regprocedure;
BEGIN
  PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = f), 'SECURITY DEFINER');
  PERFORM pg_temp.ok((SELECT proconfig @> ARRAY['search_path=public, extensions'] FROM pg_proc WHERE oid = f), 'search_path fijado');
  PERFORM pg_temp.ok(NOT has_function_privilege('anon', f, 'EXECUTE'), 'anon sin EXECUTE');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', f, 'EXECUTE'), 'authenticated con EXECUTE');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'cl_batch_scans_unknown_place_idx'), 'indice parcial creado');
END $$;

-- 2. Usuario con View en cl_reading_points de A1: agregados correctos del carrier 1.
SET ROLE authenticated;
SELECT pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');
SELECT pg_temp.ok(pg_temp.up('a0000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001')
                  = 'NBO|ADM|3;XYZ|<NULL>|2;MBA|DLV|1',
                  'carrier 1 de A1: ' || pg_temp.up('a0000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001'));
-- Ventana de dias: con 365 aparece OLD; con 2 solo lo de 1-2 dias.
SELECT pg_temp.ok(pg_temp.up('a0000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001', 365)
                  = 'NBO|ADM|3;XYZ|<NULL>|2;MBA|DLV|1;OLD|ADM|1', 'ventana de 365 dias');
SELECT pg_temp.ok(pg_temp.up('a0000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001', 2)
                  = 'NBO|ADM|2;XYZ|<NULL>|2', 'ventana de 2 dias: '
                  || pg_temp.up('a0000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001', 2));
-- Filtro por carrier: el carrier 3 solo ve lo suyo.
SELECT pg_temp.ok(pg_temp.up('a0000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000003') = 'C3P|ADM|1', 'carrier 3 de A1');
-- Cuenta ajena: el mismo 42501 que una cuenta inexistente.
SELECT pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.cl_unknown_places('a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002')$q$)
                  = '42501:CL_FORBIDDEN', 'cuenta ajena -> 42501');
SELECT pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.cl_unknown_places('a0000000-0000-0000-0000-00000000ffff','ca000000-0000-0000-0000-000000000002')$q$)
                  = '42501:CL_FORBIDDEN', 'cuenta inexistente -> 42501');
SELECT pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.cl_unknown_places(NULL,'ca000000-0000-0000-0000-000000000001')$q$)
                  = '42501:CL_FORBIDDEN', 'cuenta NULL -> 42501');

-- 3. Usuario de A2 pidiendo A1: 42501.
SELECT pg_temp.as_user('98000000-0000-0000-0000-000000000098', 'authenticated');
SELECT pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.cl_unknown_places('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001')$q$)
                  = '42501:CL_FORBIDDEN', 'usuario de A2 sobre A1 -> 42501');
SELECT pg_temp.ok(pg_temp.up('a0000000-0000-0000-0000-000000000002', 'ca000000-0000-0000-0000-000000000002') = 'A2P|ADM|1', 'A2 ve lo suyo');

-- 4. Sin View en cl_reading_points ni cl_monitor: 42501; con View solo en cl_monitor: permitido.
SELECT pg_temp.as_user('96000000-0000-0000-0000-000000000096', 'authenticated');
SELECT pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.cl_unknown_places('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001')$q$)
                  = '42501:CL_FORBIDDEN', 'sin derecho -> 42501');
RESET ROLE;
INSERT INTO public.account_access (account_id, role, option, level) VALUES
  ('a0000000-0000-0000-0000-000000000001','panelist_manager','cl_monitor','view')
ON CONFLICT (account_id, role, option) DO UPDATE SET level = EXCLUDED.level;
SET ROLE authenticated;
SELECT pg_temp.as_user('96000000-0000-0000-0000-000000000096', 'authenticated');
SELECT pg_temp.ok(pg_temp.up('a0000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001')
                  = 'NBO|ADM|3;XYZ|<NULL>|2;MBA|DLV|1', 'View en cl_monitor basta');

-- 5. Superadmin: cualquier cuenta; carrier de otra cuenta sobre A1 -> nada.
SELECT pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
SELECT pg_temp.ok(pg_temp.up('a0000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001')
                  = 'NBO|ADM|3;XYZ|<NULL>|2;MBA|DLV|1', 'superadmin sobre A1');
SELECT pg_temp.ok(pg_temp.up('a0000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000002') = '',
                  'carrier de A2 sobre la cuenta A1 -> vacio');
SELECT pg_temp.ok(pg_temp.up('a0000000-0000-0000-0000-000000000002', 'ca000000-0000-0000-0000-000000000002') = 'A2P|ADM|1', 'superadmin sobre A2');

-- 6. anon: sin EXECUTE.
SET ROLE anon;
SELECT pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.cl_unknown_places('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001')$q$)
                  LIKE '42501:%', 'anon -> 42501');
RESET ROLE;
ROLLBACK;
\echo cl_unknown_places OK
