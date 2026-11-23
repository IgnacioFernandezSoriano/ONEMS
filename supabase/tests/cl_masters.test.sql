-- Carrier Link fase 0, tarea 1: campos nuevos en maestros (readers, delivery_standards, one_db) y opciones de acceso cl_*.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

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

-- Centro con ciudad (PC1) y centro sin ciudad (PC0); un lector rfid existente.
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001');
INSERT INTO public.postal_centers (id, account_id, code, name, city) VALUES
  ('d1000000-0000-0000-0000-0000000000c0','a0000000-0000-0000-0000-000000000001','PC0','Center 0','Nowhere');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2');
INSERT INTO public.readers (id, account_id, postal_center_id, reader_id, name, type) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','LPI1','R1','Mixed');

-- 1. Lector existente: valores por defecto.
DO $$ BEGIN
  PERFORM pg_temp.fail_if((SELECT capture_source FROM public.readers WHERE id = 'f1000000-0000-0000-0000-000000000001') IS DISTINCT FROM 'rfid', 'capture_source por defecto');
  PERFORM pg_temp.fail_if((SELECT e2e_role FROM public.readers WHERE id = 'f1000000-0000-0000-0000-000000000001') IS DISTINCT FROM 'none', 'e2e_role por defecto');
END $$;

-- 2. Generación de reader_id y unicidad del punto.
INSERT INTO public.readers (account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref)
VALUES ('a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','P1','Entry','carrier_scan',
        'ca000000-0000-0000-0000-000000000001','NBO','AIR');
DO $$ BEGIN
  PERFORM pg_temp.fail_if((SELECT reader_id FROM public.readers WHERE name = 'P1') IS DISTINCT FROM 'CL:acc:CA:NBO:AIR',
    'reader_id generado: ' || coalesce((SELECT reader_id FROM public.readers WHERE name = 'P1'), 'NULL'));
  -- mismo carrier, lugar y modo
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.readers (account_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref)
    VALUES ('a0000000-0000-0000-0000-000000000001','P1b','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','AIR')$q$), 'duplicado con modo pasa');
  -- mismo lugar, modo distinto
  PERFORM pg_temp.fail_if(pg_temp.raises($q$INSERT INTO public.readers (account_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref)
    VALUES ('a0000000-0000-0000-0000-000000000001','P1c','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','ROAD')$q$), 'modo distinto falla');
  -- modo NULL dos veces
  INSERT INTO public.readers (account_id, name, type, capture_source, carrier_id, carrier_place_ref)
  VALUES ('a0000000-0000-0000-0000-000000000001','P2','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA');
  PERFORM pg_temp.fail_if((SELECT reader_id FROM public.readers WHERE name = 'P2') IS DISTINCT FROM 'CL:acc:CA:MBA', 'reader_id sin modo');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.readers (account_id, name, type, capture_source, carrier_id, carrier_place_ref)
    VALUES ('a0000000-0000-0000-0000-000000000001','P2b','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA')$q$), 'modo NULL dos veces pasa');
  -- reader_id explícito se respeta
  INSERT INTO public.readers (account_id, reader_id, name, type, capture_source, carrier_id, carrier_place_ref)
  VALUES ('a0000000-0000-0000-0000-000000000001','CUSTOM1','P3','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','KIS');
  PERFORM pg_temp.fail_if((SELECT reader_id FROM public.readers WHERE name = 'P3') IS DISTINCT FROM 'CL:acc:CA:KIS', 'reader_id explícito se ignora');
  UPDATE public.readers SET carrier_place_ref = 'KIS2', reader_id = 'HAND' WHERE name = 'P3';
  PERFORM pg_temp.fail_if((SELECT reader_id FROM public.readers WHERE name = 'P3') IS DISTINCT FROM 'CL:acc:CA:KIS2', 'update regenera reader_id');
  PERFORM pg_temp.fail_if(pg_temp.sqlstate_of($q$INSERT INTO public.readers (account_id, reader_id, name, type)
    VALUES ('a0000000-0000-0000-0000-000000000001','CL:acc:CA:FAKE','F','Entry')$q$) IS DISTINCT FROM '23514', 'rfid con CL:');
END $$;

-- 3. Forma del punto.
DO $$ BEGIN
  -- carrier de otra cuenta (CB es de A2) -> check_violation
  PERFORM pg_temp.fail_if(pg_temp.sqlstate_of($q$INSERT INTO public.readers (account_id, name, type, capture_source, carrier_id, carrier_place_ref)
    VALUES ('a0000000-0000-0000-0000-000000000001','XC','Entry','carrier_scan','ca000000-0000-0000-0000-000000000002','XC1')$q$)
    IS DISTINCT FROM '23514', 'carrier de otra cuenta');
  -- modo en blanco -> NULL, sin ':' final
  INSERT INTO public.readers (account_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref)
  VALUES ('a0000000-0000-0000-0000-000000000001','BL','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','BLK','  ');
  PERFORM pg_temp.fail_if((SELECT reader_id FROM public.readers WHERE name = 'BL') IS DISTINCT FROM 'CL:acc:CA:BLK', 'modo blanco');
  PERFORM pg_temp.fail_if((SELECT carrier_mode_ref FROM public.readers WHERE name = 'BL') IS NOT NULL, 'modo blanco no es NULL');
  UPDATE public.readers SET carrier_mode_ref = ' ' WHERE name = 'BL';
  PERFORM pg_temp.fail_if((SELECT carrier_mode_ref FROM public.readers WHERE name = 'BL') IS NOT NULL
                          OR (SELECT reader_id FROM public.readers WHERE name = 'BL') <> 'CL:acc:CA:BLK', 'update modo blanco');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.readers (account_id, name, type, capture_source, carrier_id, carrier_place_ref)
    VALUES ('a0000000-0000-0000-0000-000000000001','M','Mixed','carrier_scan','ca000000-0000-0000-0000-000000000001','XXX')$q$), 'carrier_scan Mixed pasa');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.readers (account_id, reader_id, name, type, carrier_id)
    VALUES ('a0000000-0000-0000-0000-000000000001','RF2','X','Entry','ca000000-0000-0000-0000-000000000001')$q$), 'rfid con carrier_id pasa');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.readers (account_id, name, type, capture_source, carrier_place_ref)
    VALUES ('a0000000-0000-0000-0000-000000000001','N','Entry','carrier_scan','YYY')$q$), 'carrier_scan sin carrier pasa');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.readers (account_id, reader_id, name, type, e2e_role)
    VALUES ('a0000000-0000-0000-0000-000000000001','RF3','X','Entry','origin')$q$), 'rfid con e2e_role pasa');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.readers (account_id, reader_id, name, type, capture_source)
    VALUES ('a0000000-0000-0000-0000-000000000001','RF4','X','Entry','otro')$q$), 'capture_source invalido pasa');
END $$;

-- 4. e2e_role exige centro con ciudad.
DO $$ BEGIN
  PERFORM pg_temp.fail_if(pg_temp.sqlstate_of($q$INSERT INTO public.readers (account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, e2e_role)
    VALUES ('a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c0','O','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','ZZ1','origin')$q$)
    IS DISTINCT FROM '23514', 'e2e_role origin en centro sin ciudad');
  PERFORM pg_temp.fail_if(pg_temp.sqlstate_of($q$INSERT INTO public.readers (account_id, name, type, capture_source, carrier_id, carrier_place_ref, e2e_role)
    VALUES ('a0000000-0000-0000-0000-000000000001','O2','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','ZZ2','destination')$q$)
    IS DISTINCT FROM '23514', 'e2e_role sin centro');
  PERFORM pg_temp.fail_if(pg_temp.sqlstate_of($q$INSERT INTO public.readers (account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, e2e_role)
    VALUES ('a0000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-0000000000c1','O4','Entry','carrier_scan','ca000000-0000-0000-0000-000000000002','ZZ4','origin')$q$)
    IS DISTINCT FROM '23514', 'e2e_role con centro de otra cuenta');
  INSERT INTO public.readers (account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, e2e_role)
  VALUES ('a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','O3','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','ZZ3','both');
  -- UPDATE a un centro sin ciudad tambien falla
  PERFORM pg_temp.fail_if(pg_temp.sqlstate_of($q$UPDATE public.readers SET postal_center_id = 'd1000000-0000-0000-0000-0000000000c0' WHERE name = 'O3'$q$)
    IS DISTINCT FROM '23514', 'update a centro sin ciudad');
END $$;

-- 5. Columnas de delivery_standards y one_db.
DO $$ BEGIN
  PERFORM pg_temp.fail_if((SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'delivery_standards'
     AND column_name IN ('cl_first_mile_time','cl_last_mile_time')) <> 2, 'columnas delivery_standards');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'one_db'
     AND column_name IN ('source','cl_sample_id','carrier_id','equivalence_hours','equivalence_days','measured_total_hours',
                         'measured_total_days','measured_business_hours','measured_business_days')) <> 9, 'columnas one_db');
END $$;
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR9','Prod9',48);
INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time)
VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000009',
        'c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',24);
DO $$ BEGIN
  PERFORM pg_temp.fail_if((SELECT cl_first_mile_time FROM public.delivery_standards LIMIT 1) <> 0, 'cl_first_mile_time por defecto');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$UPDATE public.delivery_standards SET cl_last_mile_time = -1$q$), 'cl_last_mile_time negativo pasa');
END $$;

-- 6. Opciones de acceso: 5 + 5 + 4 + 4 por cuenta; plantilla.
DO $$
BEGIN
  -- 6 = las 5 de esta migracion + cl_incidents (20261124100300, fuera de la plantilla: solo DEMO2).
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.access_option WHERE key LIKE 'cl\_%') <> 6, 'opciones cl_');
  PERFORM pg_temp.fail_if((SELECT sort FROM public.access_option WHERE key = 'cl_monitor') <> 156, 'sort cl_monitor');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.accounts a
     WHERE (SELECT count(*) FROM public.account_access x WHERE x.account_id = a.id AND x.role = 'account_manager' AND x.option LIKE 'cl\_%') <> 5), 'AM 5');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.accounts a
     WHERE (SELECT count(*) FROM public.account_access x WHERE x.account_id = a.id AND x.role = 'upu_account_manager' AND x.option LIKE 'cl\_%') <> 5), 'UPU 5');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.accounts a
     WHERE (SELECT count(*) FROM public.account_access x WHERE x.account_id = a.id AND x.role = 'allocation_plan_manager' AND x.option LIKE 'cl\_%') <> 4), 'APM 4');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.accounts a
     WHERE (SELECT count(*) FROM public.account_access x WHERE x.account_id = a.id AND x.role = 'do_coordinator' AND x.option LIKE 'cl\_%') <> 4), 'DO 4');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.account_access WHERE role IN ('panelist_manager','materials_supplier') AND option LIKE 'cl\_%'), 'PM/MS sin cl_');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.access_template WHERE role = 'no_role' AND option LIKE 'cl\_%'), 'no_role sin cl_');
  PERFORM pg_temp.fail_if((SELECT level FROM public.account_access WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'allocation_plan_manager' AND option = 'cl_reading_points') IS DISTINCT FROM 'view', 'APM reading_points view');
  PERFORM pg_temp.fail_if((SELECT level FROM public.account_access WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'do_coordinator' AND option = 'cl_reading_points') IS DISTINCT FROM 'edit', 'DO reading_points edit');
  PERFORM pg_temp.fail_if((SELECT level FROM public.account_access WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'do_coordinator' AND option = 'cl_plans') IS DISTINCT FROM 'view', 'DO plans view');
  PERFORM pg_temp.fail_if((SELECT level FROM public.account_access WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'account_manager' AND option = 'cl_samples') IS DISTINCT FROM 'view', 'AM samples view');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.account_access WHERE role = 'allocation_plan_manager' AND option = 'cl_connectors'), 'APM sin connectors');
  -- cuenta nueva: la copia de plantilla (trigger existente) incluye cl_
  INSERT INTO public.accounts (id, name, slug) VALUES ('a0000000-0000-0000-0000-000000000003','Acc3','acc3');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.account_access WHERE account_id = 'a0000000-0000-0000-0000-000000000003' AND option LIKE 'cl\_%') <> 18, 'cuenta nueva cl_');
END $$;

-- 7. Escritura de lectores con cl_reading_points sin readers_management.
INSERT INTO auth.users (id, email) VALUES
  ('94000000-0000-0000-0000-000000000094','do@t.l'),
  ('93000000-0000-0000-0000-000000000093','apm@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('94000000-0000-0000-0000-000000000094','do@t.l','DO','user','a0000000-0000-0000-0000-000000000001'),
  ('93000000-0000-0000-0000-000000000093','apm@t.l','APM','user','a0000000-0000-0000-0000-000000000001');
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000094','do_coordinator'),
  ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000093','allocation_plan_manager');
-- DO sin readers_management ni postal_centers; solo cl_reading_points edit.
DELETE FROM public.account_access WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'do_coordinator'
   AND option IN ('readers_management','postal_centers');

SET ROLE authenticated;
SELECT pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
DO $$ BEGIN
  PERFORM pg_temp.fail_if(pg_temp.raises($q$INSERT INTO public.readers (account_id, name, type, capture_source, carrier_id, carrier_place_ref)
    VALUES ('a0000000-0000-0000-0000-000000000001','DOP','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','DOP')$q$),
    'DO con cl_reading_points edit no inserta punto');
  UPDATE public.readers SET name = 'DOP2' WHERE name = 'DOP';
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.readers WHERE name = 'DOP2'), 'DO no actualiza punto');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.readers (account_id, reader_id, name, type)
    VALUES ('a0000000-0000-0000-0000-000000000001','RFX','X','Entry')$q$), 'DO inserta lector rfid');
  UPDATE public.readers SET name = 'hack' WHERE id = 'f1000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.fail_if((SELECT name FROM public.readers WHERE id = 'f1000000-0000-0000-0000-000000000001') <> 'R1', 'DO actualiza lector rfid');
  PERFORM pg_temp.raises($q$UPDATE public.readers SET capture_source = 'carrier_scan', carrier_id = 'ca000000-0000-0000-0000-000000000001',
    carrier_place_ref = 'HJK', type = 'Entry' WHERE id = 'f1000000-0000-0000-0000-000000000001'$q$);
  PERFORM pg_temp.fail_if((SELECT capture_source FROM public.readers WHERE id = 'f1000000-0000-0000-0000-000000000001') <> 'rfid', 'rfid convertido en punto');
  PERFORM pg_temp.raises($q$UPDATE public.readers SET capture_source = 'rfid', carrier_id = NULL, carrier_place_ref = NULL, reader_id = 'ZED' WHERE name = 'DOP2'$q$);
  PERFORM pg_temp.fail_if((SELECT capture_source FROM public.readers WHERE name = 'DOP2') <> 'carrier_scan', 'punto convertido en rfid');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.postal_centers (account_id, code, name, city)
    VALUES ('a0000000-0000-0000-0000-000000000001','PCX','X','X')$q$), 'DO inserta centro');
  UPDATE public.postal_centers SET name = 'hack' WHERE id = 'd1000000-0000-0000-0000-0000000000c1';
  PERFORM pg_temp.fail_if((SELECT name FROM public.postal_centers WHERE id = 'd1000000-0000-0000-0000-0000000000c1') <> 'Center 1', 'DO actualiza centro');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.readers (account_id, name, type, capture_source, carrier_id, carrier_place_ref)
    VALUES ('a0000000-0000-0000-0000-000000000002','DOX','Entry','carrier_scan','ca000000-0000-0000-0000-000000000002','DOX')$q$),
    'DO inserta en otra cuenta');
END $$;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$ BEGIN
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.readers (account_id, name, type, capture_source, carrier_id, carrier_place_ref)
    VALUES ('a0000000-0000-0000-0000-000000000001','APMP','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','APMP')$q$),
    'APM (view) inserta punto');
END $$;
RESET ROLE;

ROLLBACK;
\echo 'cl_masters: OK'
