-- Carrier Link, revision final I1: un punto de lectura dado de baja (baja logica) no se puede volver a insertar
-- (readers_account_id_reader_id_key incluye los borrados), asi que la web lo reactiva con un UPDATE de la fila borrada
-- (filtrado por id + capture_source). Comprueba, como usuario con Edit en cl_reading_points y con RLS, que:
--   * reinsertar el mismo carrier/lugar/modo da 23505 (el motivo del arreglo);
--   * el UPDATE de reactivacion pasa por readers_cl_check_city, readers_cl_defaults y reader_location_change_trigger
--     sin error, conserva el reader_id y deja la fila activa con los datos nuevos;
--   * reactivar con un punto activo igual, o editar otro punto hacia el lugar/modo de uno borrado, da 23505.
-- Todo en BEGIN ... ROLLBACK.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.state(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN 'ok'; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE; END $$;

BEGIN;
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','PC2','Center 2','City2','c2000000-0000-0000-0000-000000000002');

-- 99 = upu_account_manager de A1 (Edit en cl_reading_points).
SET ROLE authenticated;
SELECT pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');

INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
  ('ad000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','NBO','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','ADM','origin'),
  ('ad000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','MBA','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA',NULL,'origin');
SELECT set_config('t.rid', (SELECT reader_id FROM public.readers WHERE id = 'ad000000-0000-0000-0000-000000000001'), true);

-- Baja logica (como remove() de la web).
UPDATE public.readers SET deleted_at = now(), is_active = false, updated_at = now()
 WHERE id = 'ad000000-0000-0000-0000-000000000001' AND capture_source = 'carrier_scan';

-- 1. Reinsertar el mismo punto: 23505.
SELECT pg_temp.ok(pg_temp.state($q$
  INSERT INTO public.readers (account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role)
  VALUES ('a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000c2','NBO again','Exit','carrier_scan',
          'ca000000-0000-0000-0000-000000000001','NBO','ADM','destination')$q$) = '23505', 'reinsertar un punto borrado da 23505');

-- 2. Editar otro punto hacia el lugar/modo del borrado: 23505.
SELECT pg_temp.ok(pg_temp.state($q$
  UPDATE public.readers SET carrier_place_ref = 'NBO', carrier_mode_ref = 'ADM'
   WHERE id = 'ad000000-0000-0000-0000-000000000002' AND capture_source = 'carrier_scan'$q$) = '23505',
  'editar hacia el lugar/modo de un borrado da 23505');

-- 3. Reactivacion (lo que hace create() de la web): mismos campos que reviveReadingPointFields.
SELECT pg_temp.ok(pg_temp.state($q$
  UPDATE public.readers
     SET carrier_id = 'ca000000-0000-0000-0000-000000000001', carrier_place_ref = 'NBO', carrier_mode_ref = 'ADM',
         postal_center_id = 'd2000000-0000-0000-0000-0000000000c2', e2e_role = 'destination', type = 'Exit',
         name = 'NBO again', deleted_at = NULL, is_active = true, updated_at = now()
   WHERE id = 'ad000000-0000-0000-0000-000000000001' AND capture_source = 'carrier_scan' AND deleted_at IS NOT NULL$q$) = 'ok',
  'la reactivacion pasa los triggers de readers');
SELECT pg_temp.ok((SELECT deleted_at IS NULL AND is_active AND reader_id = current_setting('t.rid')
                          AND postal_center_id = 'd2000000-0000-0000-0000-0000000000c2' AND e2e_role = 'destination'
                          AND name = 'NBO again'
                     FROM public.readers WHERE id = 'ad000000-0000-0000-0000-000000000001'),
                  'fila reactivada con los datos nuevos y el mismo reader_id');
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*) FROM public.reader_location_history
                    WHERE reader_id = 'ad000000-0000-0000-0000-000000000001'
                      AND postal_center_id = 'd2000000-0000-0000-0000-0000000000c2' AND unassigned_at IS NULL) = 1,
                  'reader_location_change_trigger registra el nuevo centro');
SET ROLE authenticated;
SELECT pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');

-- 4. Reactivar un borrado cuando ya hay un punto activo igual: 23505 (readers_cl_point_key).
UPDATE public.readers SET deleted_at = now(), is_active = false, updated_at = now()
 WHERE id = 'ad000000-0000-0000-0000-000000000002' AND capture_source = 'carrier_scan';
INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
  ('ad000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','MBA 2','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA2',NULL,'origin');
SELECT pg_temp.ok(pg_temp.state($q$
  UPDATE public.readers SET carrier_place_ref = 'MBA2', deleted_at = NULL, is_active = true
   WHERE id = 'ad000000-0000-0000-0000-000000000002' AND capture_source = 'carrier_scan' AND deleted_at IS NOT NULL$q$) = '23505',
  'reactivar sobre un punto activo igual da 23505');

-- 5. Otra cuenta no ve ni reactiva el borrado de A1 (RLS): 0 filas.
SELECT pg_temp.as_user('98000000-0000-0000-0000-000000000098', 'authenticated');
SELECT pg_temp.ok((SELECT count(*) FROM public.readers WHERE id = 'ad000000-0000-0000-0000-000000000002') = 0,
                  'A2 no ve el punto borrado de A1');
RESET ROLE;
ROLLBACK;
\echo cl_reading_point_revive OK
