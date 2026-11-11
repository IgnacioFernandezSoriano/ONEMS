-- Bot de analisis para managers (Tarea 1): rol Allocation Plan Manager, busqueda por correo
-- (ops_manager_lookup), puerta por cuenta (ops_case_account_enabled) y control de cuenta (p_account) en
-- ops_case_find_panelists / _data / _send / _note y ops_fix_r4_preview / _apply / _undo.
-- Cuenta 1 = 'Acc' (a...01), cuenta 2 = 'Acc2' (a...02) del fixture incident_city.
\set ON_ERROR_STOP on
SET client_min_messages = error;
CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;
-- Ejecuta un SQL y devuelve el mensaje de error ('' si no falla).
CREATE OR REPLACE FUNCTION pg_temp.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  EXECUTE p_sql;
  RETURN '';
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v = MESSAGE_TEXT;
  RETURN v;
END $$;

BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
INSERT INTO ops_test.secret(token_sha256) VALUES (encode(extensions.digest('t0ken-de-prueba','sha256'),'hex'));
UPDATE public.panelists SET name = 'Arbe Tester', telegram_id = '1001' WHERE panelist_code = 'P1';
UPDATE public.accounts SET default_language = 'fr' WHERE id = 'a0000000-0000-0000-0000-000000000002';
-- panelista de la cuenta 2 (mismo nombre de pila que uno de la cuenta 1)
INSERT INTO public.regions (id, account_id, name, code) VALUES ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','City9','C9');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES ('b9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','c3000000-0000-0000-0000-000000000003','N9');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language, telegram_id) VALUES
  ('e9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','P9','Arbe Otro','p9@t.l','9','b9000000-0000-0000-0000-000000000009','active','en','9009');
-- caso R4 de la cuenta 1 (como en ops_fix_r4) e incidencia de la cuenta 1
INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit, success_percentage) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',6,'hours',90);
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id, sent_at,
                                            origin_panelist_id, origin_panelist_name, destination_panelist_id, destination_panelist_name) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002',
   '2026-10-27','sent','00011844','2026-10-30 09:00+00','e1000000-0000-0000-0000-000000000001','Pan1','e2000000-0000-0000-0000-000000000002','Pan2');
INSERT INTO public.receipt_case (id, account_id, panelist_id, telegram_id, tag_raw, tag_norm, detail_id, reason, status, attempts, first_attempt_at, last_attempt_at)
VALUES ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000004','4004',
        '11844','00011844',NULL,'other_city_tag','needs_decision',2,'2026-11-02 10:00+00','2026-11-03 10:00+00');
INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status, description) VALUES
  ('f3000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','other','open','x');
-- registro R4 de la cuenta 1 (solo para comprobar la cuenta en undo)
INSERT INTO ops_fix.log (id, kind, account_id, target, before, after)
VALUES (990001, 'r4', 'a0000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', '{}', '{}');
-- superadmin
INSERT INTO auth.users (id, email) VALUES ('97000000-0000-0000-0000-000000000097','boss@x.org');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('97000000-0000-0000-0000-000000000097','Boss@X.org','Boss','superadmin',NULL);

-- ===== columna nueva y formato =====
DO $$
BEGIN
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                                       AND table_name = 'accounts' AND column_name = 'email_allocation_plan_manager'), 'columna nueva');
  PERFORM pg_temp.fail_if(pg_temp.err($q$UPDATE public.accounts SET email_allocation_plan_manager = 'sin-arroba' WHERE name = 'Acc'$q$)
                          NOT LIKE '%accounts_email_allocation_plan_manager_format%', 'formato malo aceptado');
END $$;

-- ===== ops_manager_lookup =====
UPDATE public.accounts SET email_panelist_manager = 'Pm@X.org', email_allocation_plan_manager = 'apm@x.org'
 WHERE id = 'a0000000-0000-0000-0000-000000000001';
DO $$
DECLARE r jsonb; t text := 't0ken-de-prueba';
BEGIN
  -- panelist manager de la cuenta 1 (mayusculas y espacios dan igual)
  r := public.ops_manager_lookup(t, '  pm@x.ORG ');
  PERFORM pg_temp.fail_if((r->>'superadmin')::bool, 'pm no es superadmin: ' || r::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'accounts') <> 1, 'pm 1 cuenta: ' || r::text);
  PERFORM pg_temp.fail_if(r->'accounts'->0->>'account' <> 'Acc' OR r->'accounts'->0->>'role' <> 'panelist_manager'
                          OR r->'accounts'->0->>'language' <> 'en', 'pm campos: ' || r::text);
  -- allocation plan manager
  r := public.ops_manager_lookup(t, 'APM@x.org');
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'accounts') <> 1 OR r->'accounts'->0->>'role' <> 'allocation_plan_manager',
                          'apm: ' || r::text);
  -- el mismo correo tambien en la cuenta 2 (como account manager) -> dos cuentas
  UPDATE public.accounts SET email_account_manager = 'pm@x.org' WHERE id = 'a0000000-0000-0000-0000-000000000002';
  r := public.ops_manager_lookup(t, 'pm@x.org');
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'accounts') <> 2, 'pm 2 cuentas: ' || r::text);
  PERFORM pg_temp.fail_if(NOT r->'accounts' @> '[{"account":"Acc2","role":"account_manager","language":"fr"}]'::jsonb, 'pm cuenta 2: ' || r::text);
  -- la cuenta 2 excluida (cuenta de prueba) -> una
  r := public.ops_manager_lookup(t, 'pm@x.org', ARRAY['Acc2']);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'accounts') <> 1 OR r->'accounts'->0->>'account' <> 'Acc', 'exclude: ' || r::text);
  -- cuenta inactiva -> fuera
  UPDATE public.accounts SET status = 'inactive' WHERE id = 'a0000000-0000-0000-0000-000000000002';
  r := public.ops_manager_lookup(t, 'pm@x.org');
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'accounts') <> 1, 'inactiva: ' || r::text);
  UPDATE public.accounts SET status = 'active' WHERE id = 'a0000000-0000-0000-0000-000000000002';
  -- superadmin
  r := public.ops_manager_lookup(t, ' BOSS@x.org');
  PERFORM pg_temp.fail_if(NOT (r->>'superadmin')::bool OR jsonb_array_length(r->'accounts') <> 0, 'superadmin: ' || r::text);
  -- desconocido y vacio
  r := public.ops_manager_lookup(t, 'nadie@x.org');
  PERFORM pg_temp.fail_if((r->>'superadmin')::bool OR jsonb_array_length(r->'accounts') <> 0, 'desconocido: ' || r::text);
  r := public.ops_manager_lookup(t, NULL);
  PERFORM pg_temp.fail_if((r->>'superadmin')::bool OR jsonb_array_length(r->'accounts') <> 0, 'null: ' || r::text);
  -- token malo
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_manager_lookup('malo', 'pm@x.org')$q$) NOT LIKE 'ops_test: token no valido%', 'token lookup');
END $$;

-- ===== ops_case_account_enabled =====
DO $$
DECLARE t text := 't0ken-de-prueba';
BEGIN
  PERFORM pg_temp.fail_if(public.ops_case_account_enabled(t, 'Acc'), 'Acc cerrada');
  UPDATE public.accounts SET name = 'DEMO2' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.fail_if(NOT public.ops_case_account_enabled(t, 'DEMO2'), 'DEMO2 abierta');
  PERFORM pg_temp.fail_if(public.ops_case_account_enabled(t, 'NoExiste'), 'inexistente');
  UPDATE public.accounts SET name = 'Acc' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_account_enabled('malo', 'Acc')$q$) NOT LIKE 'ops_test: token no valido%', 'token enabled');
END $$;

-- ===== control de cuenta =====
DO $$
DECLARE r jsonb; t text := 't0ken-de-prueba'; v_id uuid;
  v_arbe uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  -- find: sin cuenta, las dos; con cuenta 2, solo la suya; con cuenta 1, solo la suya
  r := public.ops_case_find_panelists(t, 'Arbe', NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 2, 'find sin cuenta 2: ' || r::text);
  r := public.ops_case_find_panelists(t, 'Arbe', NULL, 'Acc2');
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> 'P9', 'find cuenta 2: ' || r::text);
  r := public.ops_case_find_panelists(t, 'Arbe Tester', NULL, 'Acc2');
  -- (desde 20261111110000 sale «Arbe Otro», parecido de SU cuenta; nunca el de la cuenta 1)
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM jsonb_array_elements(r) e WHERE e->>'account' <> 'Acc2')
                          OR EXISTS (SELECT 1 FROM jsonb_array_elements(r) e WHERE (e->>'by_name')::boolean),
                          'find cuenta 2 no ve la 1: ' || r::text);
  r := public.ops_case_find_panelists(t, NULL, '00011844', 'Acc2');
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 0, 'find etiqueta cuenta 2: ' || r::text);
  r := public.ops_case_find_panelists(p_token => t, p_name => 'Arbe', p_tag => NULL, p_account => 'Acc');
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> 'P1', 'find cuenta 1: ' || r::text);
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_find_panelists('t0ken-de-prueba', 'Arbe', NULL, 'NoExiste')$q$)
                          <> 'ops_case: cuenta no encontrada', 'find cuenta inexistente');

  -- data
  PERFORM pg_temp.fail_if(pg_temp.err(format($q$SELECT public.ops_case_data('t0ken-de-prueba', %L, '00011844', p_account => 'Acc2')$q$, v_arbe))
                          <> 'ops_case: otra cuenta', 'data otra cuenta');
  r := public.ops_case_data(t, v_arbe, '00011844', p_account => 'Acc');
  PERFORM pg_temp.fail_if(r->'panelist'->>'code' <> 'P1', 'data misma cuenta: ' || r::text);
  r := public.ops_case_data(t, v_arbe, '00011844');
  PERFORM pg_temp.fail_if(r->'panelist'->>'code' <> 'P1', 'data sin cuenta: ' || r::text);

  -- send (con y sin incidencia)
  PERFORM pg_temp.fail_if(pg_temp.err(format($q$SELECT public.ops_case_send('t0ken-de-prueba', 'reported', 'f3000000-0000-0000-0000-000000000001', %L, 'hi', 'k1', 'Acc2')$q$, v_arbe))
                          <> 'ops_case: otra cuenta', 'send otra cuenta');
  PERFORM pg_temp.fail_if(pg_temp.err(format($q$SELECT public.ops_case_send('t0ken-de-prueba', NULL, NULL, %L, 'hi', 'k2', 'Acc2')$q$, v_arbe))
                          <> 'ops_case: otra cuenta', 'send aviso otra cuenta');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.incident_message WHERE meta->>'case_draft_key' IN ('k1','k2')) <> 0
                          OR (SELECT count(*) FROM public.panelist_notification WHERE payload->>'case_draft_key' IN ('k1','k2')) <> 0,
                          'send otra cuenta no escribe');
  v_id := public.ops_case_send(t, 'reported', 'f3000000-0000-0000-0000-000000000001', v_arbe, 'hi', 'k3', 'Acc');
  PERFORM pg_temp.fail_if(v_id IS NULL, 'send misma cuenta');
  -- una draft_key ya enviada no se devuelve a otra cuenta
  PERFORM pg_temp.fail_if(pg_temp.err(format($q$SELECT public.ops_case_send('t0ken-de-prueba', 'reported', 'f3000000-0000-0000-0000-000000000001', %L, 'hi', 'k3', 'Acc2')$q$, v_arbe))
                          <> 'ops_case: otra cuenta', 'send dedupe otra cuenta');

  -- note
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_note('t0ken-de-prueba', 'reported', 'f3000000-0000-0000-0000-000000000001', 'nota', 'Acc2')$q$)
                          <> 'ops_case: otra cuenta', 'note otra cuenta');
  PERFORM pg_temp.fail_if(public.ops_case_note(t, 'reported', 'f3000000-0000-0000-0000-000000000001', 'nota', 'Acc') IS NULL, 'note misma cuenta');

  -- R4
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_fix_r4_preview('t0ken-de-prueba', 'f1000000-0000-0000-0000-000000000001', 'Acc2')$q$)
                          <> 'ops_fix: otra cuenta', 'preview otra cuenta');
  r := public.ops_fix_r4_preview(t, 'f1000000-0000-0000-0000-000000000001', 'Acc');
  PERFORM pg_temp.fail_if(NOT (r->>'applicable')::bool, 'preview misma cuenta: ' || r::text);
  PERFORM pg_temp.fail_if(pg_temp.err(format($q$SELECT public.ops_fix_r4_apply('t0ken-de-prueba', 'f1000000-0000-0000-0000-000000000001', %L::jsonb, 'Acc2')$q$, r))
                          <> 'ops_fix: otra cuenta', 'apply otra cuenta');
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case WHERE id = 'f1000000-0000-0000-0000-000000000001') <> 'needs_decision', 'apply otra cuenta no toca');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_fix_r4_undo('t0ken-de-prueba', 990001, 'Acc2')$q$)
                          <> 'ops_fix: otra cuenta', 'undo otra cuenta');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_fix_r4_preview('t0ken-de-prueba', 'f1000000-0000-0000-0000-000000000001', 'NoExiste')$q$)
                          <> 'ops_fix: cuenta no encontrada', 'preview cuenta inexistente');
END $$;

-- ===== permisos =====
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.ops_manager_lookup(text,text,text[])',
    'public.ops_case_account_enabled(text,text,text)',
    'public.ops_case_find_panelists(text,text,text,text,text)',
    'public.ops_case_data(text,uuid,text,text,uuid,text,text)',
    'public.ops_case_send(text,text,uuid,uuid,text,text,text,text)',
    'public.ops_case_note(text,text,uuid,text,text,text)',
    'public.ops_fix_r4_preview(text,uuid,text,text)',
    'public.ops_fix_r4_apply(text,uuid,jsonb,text,text)',
    'public.ops_fix_r4_undo(text,bigint,text,text)'] LOOP
    PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', f, 'EXECUTE'), 'anon ' || f);
    PERFORM pg_temp.fail_if(has_function_privilege('authenticated', f, 'EXECUTE'), 'authenticated ' || f);
  END LOOP;
  -- sin sobrecargas viejas
  PERFORM pg_temp.fail_if((SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                            WHERE n.nspname = 'public' AND p.proname IN ('ops_case_find_panelists','ops_case_data','ops_case_send',
                                  'ops_case_note','ops_fix_r4_preview','ops_fix_r4_apply','ops_fix_r4_undo','ops_case_account_enabled')) <> 8, 'una firma por funcion');
END $$;

-- ===== dedupe de ops_case_send por cuenta (rama con incidencia) =====
INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status, description) VALUES
  ('f3000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','e9000000-0000-0000-0000-000000000009','other','open','y');
INSERT INTO public.incident_message (id, account_id, panelist_id, incident_kind, incident_id, direction, author, body, meta, status) VALUES
  ('f5000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','e9000000-0000-0000-0000-000000000009','reported',
   'f3000000-0000-0000-0000-000000000009','outbound','manager','de la cuenta 2','{"case_draft_key":"shared-key"}','pending_send');
DO $$
DECLARE v_id uuid; v_err text;
BEGIN
  -- la clave ya usada por la cuenta 2: nunca devuelve su id (la clave es unica en la tabla -> error claro)
  BEGIN
    v_id := public.ops_case_send('t0ken-de-prueba', 'reported', 'f3000000-0000-0000-0000-000000000001',
                                 'e1000000-0000-0000-0000-000000000001', 'hi', 'shared-key', 'Acc');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
  END;
  PERFORM pg_temp.fail_if(v_id = 'f5000000-0000-0000-0000-000000000009', 'dedupe devuelve el id de otra cuenta');
  PERFORM pg_temp.fail_if(v_err IS DISTINCT FROM 'ops_case: draft_key ya usada', 'clave de otra cuenta: ' || COALESCE(v_err, v_id::text));
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.incident_message WHERE meta->>'case_draft_key' = 'shared-key') <> 1,
                          'clave de otra cuenta no escribe');
  -- clave propia: inserta en la cuenta propia y el reintento devuelve el mismo id
  v_id := public.ops_case_send('t0ken-de-prueba', 'reported', 'f3000000-0000-0000-0000-000000000001',
                               'e1000000-0000-0000-0000-000000000001', 'hi', 'own-key', 'Acc');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.incident_message WHERE id = v_id
                            AND account_id = 'a0000000-0000-0000-0000-000000000001' AND meta->>'case_draft_key' = 'own-key'),
                          'clave propia inserta');
  PERFORM pg_temp.fail_if(public.ops_case_send('t0ken-de-prueba', 'reported', 'f3000000-0000-0000-0000-000000000001',
                               'e1000000-0000-0000-0000-000000000001', 'hi', 'own-key', 'Acc') <> v_id, 'dedupe propia');
END $$;

-- ===== token de managers (cerrado por defecto) =====
-- Puerta de analisis abierta para las dos cuentas del test (se deshace con el ROLLBACK).
CREATE OR REPLACE FUNCTION public.case_analysis_allowed(p_account uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = p_account AND a.name IN ('Acc', 'Acc2'));
$$;
SELECT ops_test.set_manager_token_hash(encode(extensions.digest('t0ken-managers','sha256'),'hex'));
DO $$
DECLARE r jsonb; m text := 't0ken-managers'; v_arbe uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM pg_temp.fail_if(ops_test._caller('t0ken-de-prueba') <> 'owner' OR ops_test._caller(m) <> 'manager', '_caller');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT ops_test._caller('malo')$q$) NOT LIKE 'ops_test: token no valido%', '_caller malo');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT ops_test.set_manager_token_hash('xyz')$q$) NOT LIKE 'ops_test:%', 'hash malo');
  -- sin cuenta
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_find_panelists('t0ken-managers', 'Arbe', NULL)$q$)
                          <> 'ops_case: falta cuenta', 'manager find sin cuenta');
  PERFORM pg_temp.fail_if(pg_temp.err(format($q$SELECT public.ops_case_data('t0ken-managers', %L, NULL)$q$, v_arbe))
                          <> 'ops_case: falta cuenta', 'manager data sin cuenta');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_fix_r4_preview('t0ken-managers', 'f1000000-0000-0000-0000-000000000001')$q$)
                          <> 'ops_fix: falta cuenta', 'manager preview sin cuenta');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_fix_r4_undo('t0ken-managers', 990001)$q$)
                          <> 'ops_fix: falta cuenta', 'manager undo sin cuenta');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_account_enabled('t0ken-managers', 'NoExiste', 'boss@x.org')$q$)
                          <> 'ops_case: falta cuenta', 'manager enabled cuenta inexistente');
  -- sin correo / correo sin rol / correo con rol en OTRA cuenta (apm solo es de Acc)
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_find_panelists('t0ken-managers', 'Arbe', NULL, 'Acc')$q$)
                          <> 'ops_case: sin permiso en esa cuenta', 'manager sin correo');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_find_panelists('t0ken-managers', 'Arbe', NULL, 'Acc', 'nadie@x.org')$q$)
                          <> 'ops_case: sin permiso en esa cuenta', 'manager correo malo');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_find_panelists('t0ken-managers', 'Arbe', NULL, 'Acc2', 'apm@x.org')$q$)
                          <> 'ops_case: sin permiso en esa cuenta', 'manager rol de otra cuenta');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_send('t0ken-managers', NULL, NULL, 'e9000000-0000-0000-0000-000000000009', 'hi', 'm1', 'Acc2', 'apm@x.org')$q$)
                          <> 'ops_case: sin permiso en esa cuenta', 'manager send rol de otra cuenta');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_fix_r4_preview('t0ken-managers', 'f1000000-0000-0000-0000-000000000001', 'Acc', 'nadie@x.org')$q$)
                          <> 'ops_fix: sin permiso en esa cuenta', 'manager preview correo malo');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_account_enabled('t0ken-managers', 'Acc', 'nadie@x.org')$q$)
                          <> 'ops_case: sin permiso en esa cuenta', 'manager enabled correo malo');
  -- correo con rol en su cuenta (mayusculas/espacios): permitido, y solo ve su cuenta
  r := public.ops_case_find_panelists(m, 'Arbe', NULL, 'Acc', ' APM@x.org ');
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> 'P1', 'manager find propia: ' || r::text);
  r := public.ops_case_data(m, v_arbe, '00011844', p_account => 'Acc', p_actor_email => 'apm@x.org');
  PERFORM pg_temp.fail_if(r->'panelist'->>'code' <> 'P1', 'manager data propia');
  PERFORM pg_temp.fail_if(pg_temp.err(format($q$SELECT public.ops_case_data('t0ken-managers', %L, NULL, p_account => 'Acc2', p_actor_email => 'pm@x.org')$q$, v_arbe))
                          <> 'ops_case: otra cuenta', 'manager data panelista de otra cuenta');
  PERFORM pg_temp.fail_if(NOT public.ops_case_account_enabled(m, 'Acc', 'apm@x.org'), 'manager enabled Acc abierta');
  -- caso R4 de la cuenta 1 pedido desde la cuenta 2 (superadmin)
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_fix_r4_preview('t0ken-managers', 'f1000000-0000-0000-0000-000000000001', 'Acc2', 'boss@x.org')$q$)
                          <> 'ops_fix: otra cuenta', 'manager preview otra cuenta');
  r := public.ops_fix_r4_preview(m, 'f1000000-0000-0000-0000-000000000001', 'Acc', 'pm@x.org');
  PERFORM pg_temp.fail_if(NOT (r->>'applicable')::bool, 'manager preview propia');
  -- superadmin: cualquier cuenta
  r := public.ops_case_find_panelists(m, 'Arbe', NULL, 'Acc2', 'Boss@x.org');
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> 'P9', 'superadmin Acc2: ' || r::text);
  r := public.ops_case_find_panelists(m, 'Arbe', NULL, 'Acc', 'boss@x.org');
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> 'P1', 'superadmin Acc: ' || r::text);
  PERFORM pg_temp.fail_if(public.ops_case_note(m, 'reported', 'f3000000-0000-0000-0000-000000000001', 'nota sa', 'Acc', 'boss@x.org') IS NULL, 'superadmin note');
  -- lookup: el bot de managers la puede usar
  r := public.ops_manager_lookup(m, 'apm@x.org');
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'accounts') <> 1, 'manager lookup');
  -- funciones solo del bot de Ignacio: rechazan el token de managers
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_claim('t0ken-managers')$q$) NOT LIKE 'ops_test: token no valido%', 'manager claim');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_finish('t0ken-managers', gen_random_uuid(), NULL, NULL, NULL)$q$) NOT LIKE 'ops_test: token no valido%', 'manager finish');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_report_data('t0ken-managers', 'Acc', current_date - 1, current_date)$q$) NOT LIKE 'ops_test: token no valido%', 'manager report_data');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_report_accounts('t0ken-managers')$q$) NOT LIKE 'ops_test: token no valido%', 'manager report_accounts');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_test_status('t0ken-managers')$q$) NOT LIKE 'ops_test: token no valido%', 'manager test_status');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_fix_r1_preview('t0ken-managers', 'Acc')$q$) NOT LIKE 'ops_test: token no valido%', 'manager r1');
  -- owner sigue igual: sin cuenta ni correo
  r := public.ops_case_find_panelists('t0ken-de-prueba', 'Arbe', NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 2, 'owner sin cuenta');
  -- set_manager_token_hash sustituye el anterior y no toca el owner
  PERFORM ops_test.set_manager_token_hash(encode(extensions.digest('otro-managers','sha256'),'hex'));
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT ops_test._caller('t0ken-managers')$q$) NOT LIKE 'ops_test: token no valido%', 'hash viejo de managers sigue');
  PERFORM pg_temp.fail_if(ops_test._caller('t0ken-de-prueba') <> 'owner', 'owner intacto');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'ops_test.set_manager_token_hash(text)', 'EXECUTE')
                          OR has_function_privilege('authenticated', 'ops_test.set_manager_token_hash(text)', 'EXECUTE'), 'set hash privado');
END $$;

-- ===== cuenta sin analisis habilitado: el manager no entra; el owner si =====
SELECT ops_test.set_manager_token_hash(encode(extensions.digest('t0ken-managers','sha256'),'hex'));
CREATE OR REPLACE FUNCTION public.case_analysis_allowed(p_account uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = p_account AND a.name = 'Acc');
$$;
DO $$
DECLARE r jsonb; m text := 't0ken-managers';
BEGIN
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_find_panelists('t0ken-managers', 'Arbe', NULL, 'Acc2', 'boss@x.org')$q$)
                          <> 'ops_case: cuenta no habilitada', 'manager find cuenta cerrada');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_send('t0ken-managers', NULL, NULL, 'e9000000-0000-0000-0000-000000000009', 'hi', 'm9', 'Acc2', 'pm@x.org')$q$)
                          <> 'ops_case: cuenta no habilitada', 'manager send cuenta cerrada');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_fix_r4_undo('t0ken-managers', 990001, 'Acc2', 'boss@x.org')$q$)
                          <> 'ops_fix: cuenta no habilitada', 'manager undo cuenta cerrada');
  -- un correo sin permiso no se entera de si la cuenta esta habilitada
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_find_panelists('t0ken-managers', 'Arbe', NULL, 'Acc2', 'nadie@x.org')$q$)
                          <> 'ops_case: sin permiso en esa cuenta', 'sin permiso antes que habilitada');
  -- account_enabled no falla: dice false
  PERFORM pg_temp.fail_if(public.ops_case_account_enabled(m, 'Acc2', 'boss@x.org'), 'manager enabled Acc2 cerrada');
  PERFORM pg_temp.fail_if(NOT public.ops_case_account_enabled(m, 'Acc', 'apm@x.org'), 'manager enabled Acc abierta 2');
  -- owner sin cambios
  r := public.ops_case_find_panelists('t0ken-de-prueba', 'Arbe', NULL, 'Acc2');
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> 'P9', 'owner en cuenta cerrada: ' || r::text);
END $$;

-- ===== preview: la cuenta del caso se mira ANTES de _r4_check =====
CREATE OR REPLACE FUNCTION public.case_analysis_allowed(p_account uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$ SELECT true; $$;
CREATE OR REPLACE FUNCTION ops_fix._r4_check(p_case_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN RAISE EXCEPTION 'boom: _r4_check no deberia ejecutarse'; END $$;
DO $$
BEGIN
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_fix_r4_preview('t0ken-managers', 'f1000000-0000-0000-0000-000000000001', 'Acc2', 'boss@x.org')$q$)
                          <> 'ops_fix: otra cuenta', 'preview no mira la cuenta antes de _r4_check');
END $$;

ROLLBACK;
