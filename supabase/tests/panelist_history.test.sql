-- Historial del panelista (spec 2026-11-24-historial-panelista-design.md): panelist_history, panelist_note_add,
-- panelist_note_delete. Ver = 'panelists' view; escribir = 'panelists' edit; nunca otra cuenta; sin coordenadas.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

-- true si la sentencia lanza excepcion
CREATE OR REPLACE FUNCTION pg_temp.raises(p_sql text) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN false;
EXCEPTION WHEN OTHERS THEN
  RETURN true;
END $$;

-- usuarios extra: 97 superadmin, 91 materials_supplier A1, 92 allocation_plan_manager A1.
-- (Fixture: 99 = upu_account_manager A1, 98 = upu_account_manager A2.)
CREATE OR REPLACE FUNCTION pg_temp.users() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    ('97000000-0000-0000-0000-000000000097','super@t.l'),
    ('91000000-0000-0000-0000-000000000091','ms@t.l'),
    ('92000000-0000-0000-0000-000000000092','apm@t.l');
  INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
    ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL),
    ('91000000-0000-0000-0000-000000000091','ms@t.l','MS','user','a0000000-0000-0000-0000-000000000001'),
    ('92000000-0000-0000-0000-000000000092','apm@t.l','APM','user','a0000000-0000-0000-0000-000000000001');
  INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
    ('a0000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000091','materials_supplier'),
    ('a0000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000092','allocation_plan_manager');
END $$;

-- ===== todo lo de P1, permisos y privacidad =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.users();
INSERT INTO public.panelist_note (id, account_id, panelist_id, body, created_by, created_at) VALUES
  ('a1000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
   'Le llame', '99000000-0000-0000-0000-000000000099', '2027-03-20 10:00+00');
INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status, description, payload, reported_at) VALUES
  ('a2000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
   'parcel_damaged','open','Roto','{}'::jsonb,'2027-03-19 10:00+00'),
  ('a3000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
   'gps_location','auto_resolved','GPS','{"reason":"wrong_place","place_kind":"pobox"}'::jsonb,'2027-03-18 10:00+00');
INSERT INTO public.receipt_case (id, account_id, panelist_id, telegram_id, tag_raw, tag_norm, reason, status, first_attempt_at, last_attempt_at) VALUES
  ('a4000000-0000-0000-0000-0000000000a4','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','1',
   '12345678','12345678','not_found','pending','2027-03-17 10:00+00','2027-03-17 10:00+00'),
  ('a5000000-0000-0000-0000-0000000000a5','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','1',
   '87654321','87654321','ok','fixed','2027-03-16 12:00+00','2027-03-16 12:00+00');
INSERT INTO public.receipt_case (id, account_id, panelist_id, telegram_id, tag_raw, tag_norm, reason, status, culprit_panelist_id, culprit_role,
    first_attempt_at, last_attempt_at) VALUES
  ('a6000000-0000-0000-0000-0000000000a6','a0000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002','2',
   '11112222','11112222','ok_typo_fixed','fixed','e1000000-0000-0000-0000-000000000001','sender',
   '2027-03-16 10:00+00','2027-03-16 10:00+00');
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status, created_at) VALUES
  ('a7000000-0000-0000-0000-0000000000a7','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
   '2027-03-22','2027-03-24','sick_leave','active','2027-03-15 10:00+00');
INSERT INTO public.panelist_notification (id, account_id, panelist_id, kind, payload, created_at) VALUES
  ('a8000000-0000-0000-0000-0000000000a8','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
   'manager_notice','{"body":"Ve al apartado"}'::jsonb,'2027-03-14 10:00+00');
INSERT INTO public.panelist_location_reference (id, account_id, panelist_id, kind, latitude, longitude, captured_at, source,
    needs_review, review_reason, active, created_at) VALUES
  ('a9000000-0000-0000-0000-0000000000a9','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
   'pobox', -1.28123, 36.82456, '2027-03-13 10:00+00','declaration', true, 'pobox_far_from_postal_center', true,
   '2027-03-13 10:00+00');

DO $$
DECLARE r jsonb; ev jsonb; types text[]; ats timestamptz[];
  P constant text := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  -- UPU account manager de A1: ve todo y puede escribir
  PERFORM pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');
  r := public.panelist_history(P::uuid);
  ev := r->'events';
  SELECT array_agg(e->>'type' ORDER BY ord), array_agg((e->>'at')::timestamptz ORDER BY ord)
    INTO types, ats FROM jsonb_array_elements(ev) WITH ORDINALITY x(e, ord);
  PERFORM pg_temp.fail_if(types IS DISTINCT FROM
      ARRAY['note','incident','gps','receipt','receipt','leave','notice','gps_ref'], 'tipos y orden: ' || ev::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM unnest(ats) WITH ORDINALITY a(t, i)
                                   JOIN unnest(ats) WITH ORDINALITY b(t, j) ON j = i + 1 WHERE b.t > a.t), 'orden descendente');
  PERFORM pg_temp.fail_if(ev::text LIKE '%a5000000-0000-0000-0000-0000000000a5%', 'recepcion ok fuera');
  PERFORM pg_temp.fail_if(NOT ev @> '[{"type":"receipt","data":{"role":"sender"}}]'::jsonb
                          OR NOT ev @> '[{"type":"receipt","data":{"role":"receiver","reason":"not_found"}}]'::jsonb,
                          'receptor y remitente: ' || ev::text);
  PERFORM pg_temp.fail_if(NOT ev @> '[{"type":"gps","link":{"screen":"reported"}}]'::jsonb, 'wrong_place como gps');
  PERFORM pg_temp.fail_if(NOT ev @> '[{"type":"note","data":{"body":"Le llame","can_delete":true}}]'::jsonb, 'nota propia');
  PERFORM pg_temp.fail_if(NOT ev @> '[{"type":"leave","link":{"screen":"availability"}}]'::jsonb, 'baja con enlace');
  PERFORM pg_temp.fail_if((r->>'can_write')::boolean IS NOT TRUE, 'can_write UPU');
  PERFORM pg_temp.fail_if(r->'panelist'->>'code' <> 'P1' OR r->'panelist'->>'node' <> 'N1', 'cabecera: ' || (r->'panelist')::text);
  PERFORM pg_temp.fail_if((r->'stats'->>'pobox_ref')::boolean IS NOT TRUE OR (r->'stats'->>'ref_needs_review')::boolean IS NOT TRUE,
                          'stats referencias: ' || (r->'stats')::text);
  -- privacidad: nunca coordenadas
  PERFORM pg_temp.fail_if(r::text ~* 'latitude|longitude|36\.82456|-1\.28123', 'sin coordenadas');

  -- otra cuenta y proveedor de materiales: no
  PERFORM pg_temp.as_user('98000000-0000-0000-0000-000000000098', 'authenticated');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises(format('SELECT public.panelist_history(%L)', P)), 'otra cuenta');
  PERFORM pg_temp.as_user('91000000-0000-0000-0000-000000000091', 'authenticated');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises(format('SELECT public.panelist_history(%L)', P)), 'proveedor de materiales');

  -- allocation plan manager: ve, no escribe
  PERFORM pg_temp.as_user('92000000-0000-0000-0000-000000000092', 'authenticated');
  r := public.panelist_history(P::uuid);
  PERFORM pg_temp.fail_if((r->>'can_write')::boolean IS NOT FALSE, 'APM solo lectura');
  PERFORM pg_temp.fail_if(NOT (r->'events') @> '[{"type":"note","data":{"can_delete":false}}]'::jsonb, 'nota ajena sin borrar');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises(format('SELECT public.panelist_note_add(%L, %L)', P, 'hola')), 'APM no escribe');

  -- superadmin: ve
  PERFORM pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
  r := public.panelist_history(P::uuid);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'events') <> 8, 'superadmin ve todo');
END $$;
ROLLBACK;

-- ===== notas: validacion y borrado =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.users();
INSERT INTO auth.users (id, email) VALUES ('96000000-0000-0000-0000-000000000096','am@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('96000000-0000-0000-0000-000000000096','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001');
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000096','account_manager');
DO $$
DECLARE n uuid; n2 uuid; P constant text := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises(format('SELECT public.panelist_note_add(%L, %L)', P, '   ')), 'solo espacios');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises(format('SELECT public.panelist_note_add(%L, %L)', P, repeat('x', 2001))), '2001');
  n := public.panelist_note_add(P::uuid, '  Hablado por telefono  ');
  PERFORM pg_temp.fail_if((SELECT body FROM public.panelist_note WHERE id = n) <> 'Hablado por telefono', 'recorta espacios');
  PERFORM pg_temp.fail_if((SELECT created_by FROM public.panelist_note WHERE id = n) <> '99000000-0000-0000-0000-000000000099',
                          'autor');
  n2 := public.panelist_note_add(P::uuid, repeat('y', 2000));
  -- otro gestor no la borra
  PERFORM pg_temp.as_user('96000000-0000-0000-0000-000000000096', 'authenticated');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises(format('SELECT public.panelist_note_delete(%L)', n)), 'borrar ajena');
  -- el autor si
  PERFORM pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');
  PERFORM public.panelist_note_delete(n);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_note WHERE id = n), 'autor borra');
  -- superadmin tambien
  PERFORM pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
  PERFORM public.panelist_note_delete(n2);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_note WHERE id = n2), 'superadmin borra');
  -- otra cuenta no escribe en P1
  PERFORM pg_temp.as_user('98000000-0000-0000-0000-000000000098', 'authenticated');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises(format('SELECT public.panelist_note_add(%L, %L)', P, 'x')), 'otra cuenta escribe');
END $$;
ROLLBACK;

-- ===== paginacion con empate de fecha, panelista vacio sin nodo, permisos de ejecucion =====
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO public.panelist_note (id, account_id, panelist_id, body, created_by, created_at) VALUES
  ('b1000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','n1','99000000-0000-0000-0000-000000000099','2027-03-20 10:00+00'),
  ('b2000000-0000-0000-0000-0000000000b2','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','n2','99000000-0000-0000-0000-000000000099','2027-03-20 10:00+00'),
  ('b3000000-0000-0000-0000-0000000000b3','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','n3','99000000-0000-0000-0000-000000000099','2027-03-20 10:00+00');
UPDATE public.panelists SET node_id = NULL WHERE id = 'e4000000-0000-0000-0000-000000000004';
DO $$
DECLARE r1 jsonb; r2 jsonb; ids text[]; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');
  r1 := public.panelist_history(P, NULL, NULL, 2);
  PERFORM pg_temp.fail_if(jsonb_array_length(r1->'events') <> 2 OR r1->'next' IS NULL OR r1->'next' = 'null'::jsonb,
                          'pagina 1: ' || r1::text);
  r2 := public.panelist_history(P, (r1->'next'->>'before')::timestamptz, (r1->'next'->>'before_id')::uuid, 2);
  PERFORM pg_temp.fail_if(jsonb_array_length(r2->'events') <> 1, 'pagina 2: ' || r2::text);
  PERFORM pg_temp.fail_if(r2->'next' IS NOT NULL AND r2->'next' <> 'null'::jsonb, 'sin mas paginas: ' || r2::text);
  SELECT array_agg(DISTINCT e->>'id') INTO ids FROM (
    SELECT jsonb_array_elements(r1->'events') e UNION ALL SELECT jsonb_array_elements(r2->'events')) x;
  PERFORM pg_temp.fail_if(cardinality(ids) <> 3, 'sin repetir ni perder: ' || ids::text);

  -- panelista sin nodo ni actividad
  r1 := public.panelist_history('e4000000-0000-0000-0000-000000000004');
  PERFORM pg_temp.fail_if(r1->'events' <> '[]'::jsonb OR r1->'panelist'->>'node' IS NOT NULL, 'vacio: ' || r1::text);
  PERFORM pg_temp.fail_if((r1->'stats'->>'sent_30d')::int <> 0 OR (r1->'stats'->>'receipt_problems_30d')::int <> 0,
                          'stats a 0: ' || (r1->'stats')::text);
END $$;
-- solo authenticated ejecuta
DO $$ BEGIN
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.panelist_history(uuid,timestamptz,uuid,integer)', 'EXECUTE'), 'anon');
  PERFORM pg_temp.fail_if(has_function_privilege('service_role', 'public.panelist_note_add(uuid,text)', 'EXECUTE'), 'service_role');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('authenticated', 'public.panelist_note_delete(uuid)', 'EXECUTE'), 'authenticated');
END $$;
ROLLBACK;
