-- Informe de operacion: GPS por panelista y ciudades con referencia GPS dudosa (spec 2026-11-17 §7).
-- Fixture: P1 en N1 / City1 (centro A con coordenadas); P4 en N4 / City2 (sin centro con coordenadas).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
UPDATE public.accounts SET timezone = 'UTC' WHERE id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.postal_centers (id, account_id, code, name, city_id, latitude, longitude) VALUES
  ('dd000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000001','PCA','Centro A',
   'c1000000-0000-0000-0000-000000000001', -1.28000, 36.82000),
  ('dd000000-0000-0000-0000-00000000000c','a0000000-0000-0000-0000-000000000001','PCC','Centro C',
   'c2000000-0000-0000-0000-000000000002', NULL, NULL);
-- Posiciones de P1 en City1: mediana de ok/far = 900 m (la low_accuracy de 5000 m no cuenta)
INSERT INTO public.declaration_location (id, account_id, panelist_id, captured_at, received_at, accuracy_m,
    nearest_postal_center_id, distance_m, status) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
   '2027-03-10 10:00+00','2027-03-10 10:00+00', 20, 'dd000000-0000-0000-0000-00000000000a', 400, 'ok'),
  ('f1000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
   '2027-03-10 11:00+00','2027-03-10 11:00+00', 20, 'dd000000-0000-0000-0000-00000000000a', 900, 'far'),
  ('f1000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
   '2027-03-11 11:00+00','2027-03-11 11:00+00', 20, 'dd000000-0000-0000-0000-00000000000a', 1500, 'far'),
  ('f1000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
   '2027-03-11 12:00+00','2027-03-11 12:00+00', 900, 'dd000000-0000-0000-0000-00000000000a', 5000, 'low_accuracy');
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id,
    fecha_programada, status, tag_id, sent_at, received_at, sent_gps_status, received_gps_status) VALUES
  -- D1: enviado por P1 con GPS ok
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10','sent','11111111',
   '2027-03-10 10:00+00', NULL, 'ok', NULL),
  -- D2: recibido por P1 lejos (lo envio P4 antes del GPS: NULL no cuenta para P4)
  ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b4000000-0000-0000-0000-000000000004','b1000000-0000-0000-0000-000000000001','2027-03-08','received','22222222',
   '2027-03-08 10:00+00', '2027-03-10 11:00+00', NULL, 'far'),
  -- D3: enviado por P1 sin posicion
  ('d3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11','sent','33333333',
   '2027-03-11 10:00+00', NULL, 'no_location', NULL),
  -- D4: enviado por P1 antes del GPS (NULL): no cuenta
  ('d4000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11','sent','44444444',
   '2027-03-11 09:00+00', NULL, NULL, NULL),
  -- D5: enviado por P1 fuera del periodo: no cuenta
  ('d5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-01','sent','55555555',
   '2027-03-01 09:00+00', NULL, 'no_answer', NULL);
-- Permiso de P1: primero denegado, luego concedido (vale la ultima); P2: denegado
INSERT INTO public.panelist_location_consent (account_id, panelist_id, decision, decided_at) VALUES
  ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','denied','2027-03-01 08:00+00'),
  ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','granted','2027-03-02 08:00+00'),
  ('a0000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002','denied','2027-03-02 08:00+00');

DO $$
DECLARE r jsonb; g jsonb; ref jsonb;
BEGIN
  r := ops_report._data('a0000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12');
  SELECT p->'gps' INTO g FROM jsonb_array_elements(r->'panelists') p WHERE p->>'code' = 'P1';
  PERFORM pg_temp.fail_if(g IS NULL, 'P1 sin gps: ' || (r->'panelists')::text);
  PERFORM pg_temp.fail_if(g <> '{"total":3,"ok":1,"far":1,"low_accuracy":0,"no_reference":0,"no_location":1,
      "gps_unavailable":0,"no_consent":0,"no_answer":0,"consent":"granted"}'::jsonb, 'P1 gps: ' || g::text);

  SELECT p->'gps' INTO g FROM jsonb_array_elements(r->'panelists') p WHERE p->>'code' = 'P2';
  PERFORM pg_temp.fail_if((g->>'total')::int <> 0 OR g->>'consent' <> 'denied', 'P2 gps: ' || g::text);
  SELECT p->'gps' INTO g FROM jsonb_array_elements(r->'panelists') p WHERE p->>'code' = 'P4';
  PERFORM pg_temp.fail_if((g->>'total')::int <> 0 OR g ? 'consent' AND g->>'consent' IS NOT NULL, 'P4 gps (NULL no cuenta): ' || g::text);

  ref := r->'config'->'gps_reference';
  PERFORM pg_temp.fail_if(ref IS NULL, 'sin config.gps_reference: ' || (r->'config')::text);
  PERFORM pg_temp.fail_if(NOT ref @> '[{"city":"City1","reason":"median_far","median_m":900,"n":3}]'::jsonb,
      'City1 mediana 900: ' || ref::text);
  PERFORM pg_temp.fail_if(NOT ref @> '[{"city":"City2","reason":"no_coords"}]'::jsonb, 'City2 sin coordenadas: ' || ref::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(ref) <> 2, 'gps_reference solo 2: ' || ref::text);

  -- con mediana <= 500 m City1 ya no sale
  UPDATE public.declaration_location SET distance_m = 300 WHERE id IN
    ('f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003');
  r := ops_report._data('a0000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12');
  ref := r->'config'->'gps_reference';
  PERFORM pg_temp.fail_if(ref @> '[{"city":"City1"}]'::jsonb, 'City1 con mediana 300 no debe salir: ' || ref::text);

  -- posiciones fuera del periodo no cuentan para la mediana
  UPDATE public.declaration_location SET distance_m = 2000 WHERE id IN
    ('f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003');
  r := ops_report._data('a0000000-0000-0000-0000-000000000001', '2027-03-15', '2027-03-19');
  ref := r->'config'->'gps_reference';
  PERFORM pg_temp.fail_if(ref @> '[{"city":"City1"}]'::jsonb, 'fuera del periodo: ' || ref::text);
  SELECT p->'gps' INTO g FROM jsonb_array_elements(r->'panelists') p WHERE p->>'code' = 'P1';
  PERFORM pg_temp.fail_if((g->>'total')::int <> 0, 'P1 fuera del periodo: ' || g::text);
END $$;
ROLLBACK;
