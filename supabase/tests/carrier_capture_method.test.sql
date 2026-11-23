-- Forma de captura por carrier (20261121100300_carrier_capture_method.sql): columna carriers.capture_method
-- ('panelists' | 'carrier_link' | 'both', por defecto 'panelists'), CHECK, y relleno inicial: un carrier con datos de
-- Carrier Link (cl_plans, cl_feeds o puntos de lectura carrier_scan vivos) pasa a 'both' si ademas tiene allocation
-- plans de panelistas, o a 'carrier_link' si no; el resto se queda en 'panelists'. El relleno se prueba volviendo a
-- aplicar la migracion (es idempotente) sobre datos de prueba. Las politicas RLS de carriers no cambian.
-- Todo en BEGIN ... ROLLBACK.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.raises(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE; END $$;

CREATE OR REPLACE FUNCTION pg_temp.cm(p_id uuid) RETURNS text LANGUAGE sql AS $$
  SELECT capture_method FROM public.carriers WHERE id = p_id
$$;

BEGIN;
\ir fixtures/incident_city.sql

-- 1. Definicion: columna NOT NULL con defecto 'panelists' y CHECK; las politicas de carriers no la usan.
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT is_nullable = 'NO' AND column_default LIKE '''panelists''%'
                        FROM information_schema.columns
                       WHERE table_schema = 'public' AND table_name = 'carriers' AND column_name = 'capture_method'),
                     'capture_method NOT NULL DEFAULT panelists');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'carriers'
                                   AND (coalesce(qual, '') || coalesce(with_check, '')) LIKE '%capture_method%'),
                     'ninguna politica de carriers depende de capture_method');
END $$;

-- 2. Defecto y CHECK.
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-0000000000d0','a0000000-0000-0000-0000-000000000001','D0','Defecto');
SELECT pg_temp.ok(pg_temp.cm('ca000000-0000-0000-0000-0000000000d0') = 'panelists', 'defecto panelists');
SELECT pg_temp.ok(pg_temp.raises($q$UPDATE public.carriers SET capture_method = 'otro' WHERE id = 'ca000000-0000-0000-0000-0000000000d0'$q$)
                  = '23514', 'CHECK rechaza un valor desconocido');
SELECT pg_temp.ok(pg_temp.raises($q$UPDATE public.carriers SET capture_method = NULL WHERE id = 'ca000000-0000-0000-0000-0000000000d0'$q$)
                  = '23502', 'NOT NULL');
UPDATE public.carriers SET capture_method = 'both' WHERE id = 'ca000000-0000-0000-0000-0000000000d0';
SELECT pg_temp.ok(pg_temp.cm('ca000000-0000-0000-0000-0000000000d0') = 'both', 'both aceptado');

-- 3. Relleno. Carriers de prueba (todos nacen 'panelists'):
--   ca..01 (fixture): solo allocation plans                       -> panelists
--   ca..b1: allocation plan + cl_plan                             -> both
--   ca..c1: solo cl_feed                                          -> carrier_link
--   ca..c2: solo punto de lectura carrier_scan vivo               -> carrier_link
--   ca..e1: allocation plan + punto carrier_scan BORRADO          -> panelists
--   ca..e2: nada                                                  -> panelists
--   ca..e3: eleccion previa 'carrier_link' + cl_feed + allocation plan -> se respeta (el relleno solo toca 'panelists')
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','B1','Ambos'),
  ('ca000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','C1','SoloFeed'),
  ('ca000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','C2','SoloLector'),
  ('ca000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-000000000001','E1','LectorBorrado'),
  ('ca000000-0000-0000-0000-0000000000e2','a0000000-0000-0000-0000-000000000001','E2','Nada'),
  ('ca000000-0000-0000-0000-0000000000e3','a0000000-0000-0000-0000-000000000001','E3','Elegido');
UPDATE public.carriers SET capture_method = 'carrier_link' WHERE id = 'ca000000-0000-0000-0000-0000000000e3';
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-0000000000b1','PB1','P',48),
  ('cb000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-0000000000e1','PE1','P',48),
  ('cb000000-0000-0000-0000-0000000000e3','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-0000000000e3','PE3','P',48);
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('cc000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','AB1','ca000000-0000-0000-0000-0000000000b1','cb000000-0000-0000-0000-0000000000b1',1,'2027-03-01','2027-03-31'),
  ('cc000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-000000000001','AE1','ca000000-0000-0000-0000-0000000000e1','cb000000-0000-0000-0000-0000000000e1',1,'2027-03-01','2027-03-31'),
  ('cc000000-0000-0000-0000-0000000000e3','a0000000-0000-0000-0000-000000000001','AE3','ca000000-0000-0000-0000-0000000000e3','cb000000-0000-0000-0000-0000000000e3',1,'2027-03-01','2027-03-31');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('90000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','CLB1','ca000000-0000-0000-0000-0000000000b1','cb000000-0000-0000-0000-0000000000b1',1,'2027-03-01','2027-03-07');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name) VALUES
  ('f0000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-0000000000c1','Feed C1'),
  ('f0000000-0000-0000-0000-0000000000e3','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-0000000000e3','Feed E3');
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001');
INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role, deleted_at) VALUES
  ('ad000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','RC2','Entry','carrier_scan','ca000000-0000-0000-0000-0000000000c2','NBO','ADM','origin',NULL),
  ('ad000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','RE1','Entry','carrier_scan','ca000000-0000-0000-0000-0000000000e1','MBA','ADM','origin',now());

\ir ../migrations/20261121100300_carrier_capture_method.sql

SELECT pg_temp.ok(pg_temp.cm('ca000000-0000-0000-0000-000000000001') = 'panelists', 'solo panelistas -> panelists');
SELECT pg_temp.ok(pg_temp.cm('ca000000-0000-0000-0000-0000000000b1') = 'both', 'panelistas + cl_plan -> both');
SELECT pg_temp.ok(pg_temp.cm('ca000000-0000-0000-0000-0000000000c1') = 'carrier_link', 'solo cl_feed -> carrier_link');
SELECT pg_temp.ok(pg_temp.cm('ca000000-0000-0000-0000-0000000000c2') = 'carrier_link', 'solo lector carrier_scan -> carrier_link');
SELECT pg_temp.ok(pg_temp.cm('ca000000-0000-0000-0000-0000000000e1') = 'panelists', 'lector borrado no cuenta -> panelists');
SELECT pg_temp.ok(pg_temp.cm('ca000000-0000-0000-0000-0000000000e2') = 'panelists', 'sin datos -> panelists');
SELECT pg_temp.ok(pg_temp.cm('ca000000-0000-0000-0000-0000000000e3') = 'carrier_link', 'eleccion previa respetada');
SELECT pg_temp.ok(pg_temp.cm('ca000000-0000-0000-0000-0000000000d0') = 'both', 'eleccion previa both respetada');

ROLLBACK;
\echo carrier_capture_method: OK
