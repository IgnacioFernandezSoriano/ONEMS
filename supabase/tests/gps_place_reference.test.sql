-- GPS fase 2, Task 1 (plan 2026-11-23-gps-fase2-pregunta-lugar): referencias de apartado/casa por panelista y
-- clasificacion contra la referencia. Centro A (City1) en (-1.28000, 36.82000); 0.0009 grados lat ~ 100 m.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.gps_fixture() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.panelists SET telegram_id = '1001' WHERE id = 'e1000000-0000-0000-0000-000000000001';
  UPDATE public.panelists SET telegram_id = '1004' WHERE id = 'e4000000-0000-0000-0000-000000000004';
  INSERT INTO public.postal_centers (id, account_id, code, name, city_id, latitude, longitude) VALUES
    ('dd000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000001','PCA','Centro A',
     'c1000000-0000-0000-0000-000000000001', -1.28000, 36.82000);
  PERFORM public.gps_record_consent('e1000000-0000-0000-0000-000000000001', 'granted', 'es', 'v3', 't', NULL);
END $$;

-- referencia activa a mano
CREATE OR REPLACE FUNCTION pg_temp.add_ref(p_kind text, p_lat numeric, p_lon numeric) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.panelist_location_reference (account_id, panelist_id, kind, latitude, longitude, captured_at, source)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001', p_kind, p_lat, p_lon, now(), 'declaration')
  RETURNING id;
$$;

-- caduca la visita actual del panelista (para empezar otra)
CREATE OR REPLACE FUNCTION pg_temp.new_visit() RETURNS void LANGUAGE sql AS $$
  UPDATE public.panelist_context SET created_at = created_at - interval '31 minutes'
   WHERE context_type = 'gps_visit' AND context_data->>'panelist_id' = 'e1000000-0000-0000-0000-000000000001';
  UPDATE public.declaration_location SET received_at = received_at - interval '31 minutes'
   WHERE panelist_id = 'e1000000-0000-0000-0000-000000000001';
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_pobox(p boolean) RETURNS void LANGUAGE sql AS $$
  UPDATE public.cities SET pobox_enabled = p WHERE id = 'c1000000-0000-0000-0000-000000000001';
$$;

-- ===== gps_place_kind =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE P constant uuid := 'e1000000-0000-0000-0000-000000000001'; P2 constant uuid := 'e2000000-0000-0000-0000-000000000002';
BEGIN
  -- kind_home_defecto: ni ciudad ni cuenta con POBOX
  PERFORM pg_temp.fail_if(public.gps_place_kind(P) <> 'home', 'sin politica -> home');
  -- kind_pobox_ciudad
  PERFORM pg_temp.set_pobox(true);
  PERFORM pg_temp.fail_if(public.gps_place_kind(P) <> 'pobox', 'ciudad POBOX -> pobox');
  PERFORM pg_temp.set_pobox(NULL);
  -- kind_pobox_cuenta (hereda de account_config) y panelista sin nodo (Review Focus 1)
  INSERT INTO public.account_config (account_id, pobox_enabled) VALUES ('a0000000-0000-0000-0000-000000000001', true)
  ON CONFLICT (account_id) DO UPDATE SET pobox_enabled = true;
  PERFORM pg_temp.fail_if(public.gps_place_kind(P) <> 'pobox', 'cuenta POBOX -> pobox');
  UPDATE public.panelists SET node_id = NULL WHERE id = P2;
  PERFORM pg_temp.fail_if(public.gps_place_kind(P2) <> 'pobox', 'sin nodo -> politica de la cuenta');
  UPDATE public.account_config SET pobox_enabled = false WHERE account_id = 'a0000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.fail_if(public.gps_place_kind(P2) <> 'home', 'sin nodo, cuenta sin POBOX -> home');
  PERFORM pg_temp.fail_if(public.gps_place_kind(gen_random_uuid()) <> 'home', 'panelista inexistente -> home, sin error');
END $$;
ROLLBACK;

-- ===== POBOX sin referencia: contra la oficina; una sola pregunta por visita =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
SELECT pg_temp.set_pobox(true);
DO $$
DECLARE r jsonb; c record; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_save_location(P, '1001', -1.28360, 36.82000, NULL, now(), 'm1');   -- ~400 m
  PERFORM pg_temp.fail_if(r->>'status' <> 'far' OR ((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT TRUE OR r->>'place_kind' <> 'pobox',
                          'pobox_sin_ref_lejos: ' || r::text);
  SELECT * INTO c FROM public.declaration_location WHERE id = (r->>'location_id')::uuid;
  PERFORM pg_temp.fail_if(c.ref_kind <> 'postal_center' OR c.reference_id IS NOT NULL OR c.ref_distance_m <> c.distance_m,
                          'ref_kind postal_center: ' || row_to_json(c)::text);
  r := public.gps_save_location(P, '1001', -1.28360, 36.82000, NULL, now(), 'm2');
  PERFORM pg_temp.fail_if((r->>'ask_place')::boolean IS NOT FALSE, 'misma visita: sigue pendiente pero no se pregunta dos veces ' || r::text);
  PERFORM pg_temp.new_visit();
  r := public.gps_save_location(P, '1001', -1.28180, 36.82000, NULL, now(), 'm3');   -- ~200 m
  PERFORM pg_temp.fail_if(r->>'status' <> 'ok' OR ((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT FALSE, 'pobox_sin_ref_cerca: ' || r::text);
END $$;
ROLLBACK;

-- ===== POBOX con referencia propia =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
SELECT pg_temp.set_pobox(true);
DO $$
DECLARE r jsonb; c record; ref uuid; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  ref := pg_temp.add_ref('pobox', -1.29800, 36.82000);                              -- ~2 km de la oficina
  PERFORM pg_temp.fail_if((public.gps_active_reference(P, 'pobox')).id IS DISTINCT FROM ref, 'gps_active_reference');
  PERFORM pg_temp.fail_if((public.gps_active_reference(P, 'home')).id IS NOT NULL, 'sin home');
  r := public.gps_save_location(P, '1001', -1.29710, 36.82000, NULL, now(), 'm1');   -- ~100 m de la referencia
  PERFORM pg_temp.fail_if(r->>'status' <> 'ok' OR ((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT FALSE, 'pobox_con_ref: ' || r::text);
  SELECT * INTO c FROM public.declaration_location WHERE id = (r->>'location_id')::uuid;
  PERFORM pg_temp.fail_if(c.ref_kind <> 'pobox' OR c.reference_id <> ref OR c.ref_distance_m NOT BETWEEN 90 AND 110
                          OR c.distance_m < 1800, 'columnas con referencia: ' || row_to_json(c)::text);
  -- una_activa (Review Focus 4)
  BEGIN
    PERFORM pg_temp.add_ref('pobox', -1.0, 36.0);
    RAISE EXCEPTION 'FAIL: dos referencias pobox activas';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;
ROLLBACK;

-- ===== Sin POBOX: casa =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; c record; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  -- home_sin_ref: no_reference y pregunta en cada visita nueva
  r := public.gps_save_location(P, '1001', -1.28000, 36.82000, NULL, now(), 'm1');
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_reference' OR ((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT TRUE OR r->>'place_kind' <> 'home',
                          'home_sin_ref: ' || r::text);
  SELECT * INTO c FROM public.declaration_location WHERE id = (r->>'location_id')::uuid;
  PERFORM pg_temp.fail_if(c.ref_kind IS NOT NULL OR c.ref_distance_m IS NOT NULL OR c.distance_m IS NULL,
                          'home sin ref: sin ref_kind, distancia a oficina conservada: ' || row_to_json(c)::text);
  PERFORM pg_temp.new_visit();
  r := public.gps_save_location(P, '1001', -1.28000, 36.82000, NULL, now(), 'm2');
  PERFORM pg_temp.fail_if(((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT TRUE, 'home_sin_ref otra visita: ' || r::text);

  -- home_declinada
  PERFORM pg_temp.new_visit();
  INSERT INTO public.panelist_location_reference (account_id, panelist_id, kind, captured_at, source, active)
  VALUES ('a0000000-0000-0000-0000-000000000001', P, 'home', now(), 'declined', false);
  r := public.gps_save_location(P, '1001', -1.28000, 36.82000, NULL, now(), 'm3');
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_reference' OR ((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT FALSE, 'home_declinada: ' || r::text);

  -- home_con_ref_lejos / cerca
  PERFORM pg_temp.new_visit();
  PERFORM pg_temp.add_ref('home', -1.25000, 36.82000);
  r := public.gps_save_location(P, '1001', -1.25360, 36.82000, NULL, now(), 'm4');   -- ~400 m de casa
  PERFORM pg_temp.fail_if(r->>'status' <> 'far' OR ((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT TRUE, 'home_con_ref_lejos: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT ref_kind FROM public.declaration_location WHERE id = (r->>'location_id')::uuid) <> 'home', 'ref_kind home');
  PERFORM pg_temp.new_visit();
  r := public.gps_save_location(P, '1001', -1.25090, 36.82000, NULL, now(), 'm5');   -- ~100 m de casa
  PERFORM pg_temp.fail_if(r->>'status' <> 'ok' OR ((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT FALSE, 'home_con_ref_cerca: ' || r::text);
END $$;
ROLLBACK;

-- ===== RLS: otra cuenta no ve las referencias (Review Focus 5) =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
SELECT pg_temp.add_ref('home', -1.25000, 36.82000);
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT set_config('request.jwt.claim.sub', '98000000-0000-0000-0000-000000000098', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_location_reference) <> 0, 'cuenta 2 no ve referencias de la cuenta 1');
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000099', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_location_reference) <> 1, 'cuenta 1 ve su referencia');
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$ BEGIN
  BEGIN
    PERFORM count(*) FROM public.panelist_location_reference;
    RAISE EXCEPTION 'FAIL: anon lee referencias';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
ROLLBACK;
