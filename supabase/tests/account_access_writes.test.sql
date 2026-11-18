-- Fase 3: la base exige Edit para escribir (20261119100200_account_access_writes.sql + ..._balance.sql).
--   View en una opción -> la RLS no deja escribir (0 filas / error de política); Edit -> sí.
--   Rol legacy 'admin' sin Edit en la matriz -> ya no escribe (las políticas por rol se han sustituido).
--   Edit en A1 no permite escribir A2 aunque también tenga rol en A2 (se escribe solo en la cuenta activa).
--   Superadmin escribe en cualquier cuenta. service_role y llamadas sin sesión (auth.uid() NULL) pasan.
--   Funciones SECURITY DEFINER: plan_action_delete exige allocation_plans:edit; rpc_set_working_day
--   load_balancing o account_working_days; receipt_mgr_check usa la matriz y no el rol legacy.
-- Se ejecuta como postgres y cambia de rol (SET ROLE) para que la RLS actúe. Todo en una transacción.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

-- Filas afectadas por una sentencia (0 si la RLS las filtra).
CREATE OR REPLACE FUNCTION pg_temp.rows(p_sql text) RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  EXECUTE p_sql;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

-- true si la sentencia lanza excepción
CREATE OR REPLACE FUNCTION pg_temp.raises(p_sql text) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN false;
EXCEPTION WHEN OTHERS THEN
  RETURN true;
END $$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
-- En Supabase anon/authenticated tienen USAGE en public; el shim local no lo da.
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Actores (todos con cuenta activa A1 salvo el superadmin):
--   SA 97 superadmin
--   LA 96 rol legacy 'admin' de A1 SIN roles en la matriz (columna no_role: solo vistas de reporting)
--   VW 95 do_coordinator de A1, con View en panelists, allocation_plans y carriers
--   ED 94 panelist_manager de A1 (panelists:edit) + Edit en allocation_plans, carriers y receipts;
--         también panelist_manager en A2 (para probar que no escribe A2 desde A1)
INSERT INTO auth.users (id, email) VALUES
  ('97000000-0000-0000-0000-000000000097','super@t.l'),
  ('96000000-0000-0000-0000-000000000096','legacy@t.l'),
  ('95000000-0000-0000-0000-000000000095','view@t.l'),
  ('94000000-0000-0000-0000-000000000094','edit@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL),
  ('96000000-0000-0000-0000-000000000096','legacy@t.l','Legacy','admin','a0000000-0000-0000-0000-000000000001'),
  ('95000000-0000-0000-0000-000000000095','view@t.l','View','user','a0000000-0000-0000-0000-000000000001'),
  ('94000000-0000-0000-0000-000000000094','edit@t.l','Edit','user','a0000000-0000-0000-0000-000000000001');
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000095','do_coordinator'),
  ('a0000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000094','panelist_manager'),
  ('a0000000-0000-0000-0000-000000000002','94000000-0000-0000-0000-000000000094','panelist_manager');
INSERT INTO public.account_access (account_id, role, option, level) VALUES
  ('a0000000-0000-0000-0000-000000000001','do_coordinator','panelists','view'),
  ('a0000000-0000-0000-0000-000000000001','do_coordinator','allocation_plans','view'),
  ('a0000000-0000-0000-0000-000000000001','do_coordinator','carriers','view'),
  ('a0000000-0000-0000-0000-000000000001','panelist_manager','allocation_plans','edit'),
  ('a0000000-0000-0000-0000-000000000001','panelist_manager','carriers','edit'),
  ('a0000000-0000-0000-0000-000000000001','panelist_manager','receipts','edit'),
  ('a0000000-0000-0000-0000-000000000002','panelist_manager','carriers','edit')
ON CONFLICT (account_id, role, option) DO UPDATE SET level = EXCLUDED.level;

-- Datos: panelista y transportista en A2; envíos D1..D3 en A1; centro y lector en A1.
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, status, language) VALUES
  ('e5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000002','P5','Pan5','p5@t.l','5','active','en');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2');
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id,
    fecha_programada, status) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10','pending'),
  ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11','pending'),
  ('d3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b2000000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-000000000004','2027-03-12','pending');
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001');
INSERT INTO public.readers (id, account_id, postal_center_id, reader_id, name, type) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','LPI1','R1','Mixed');
INSERT INTO public.account_config (account_id)
SELECT 'a0000000-0000-0000-0000-000000000001'
 WHERE NOT EXISTS (SELECT 1 FROM public.account_config WHERE account_id = 'a0000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------- catálogo
DO $$
DECLARE n int;
BEGIN
  -- Las 5 funciones de mantenimiento entre cuentas ya no las ejecuta authenticated (sí service_role).
  SELECT count(*) INTO n FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.proname = ANY (ARRAY['balance_node_load_matrix','cleanup_processed_rfid_events',
                                'process_all_accounts_pipeline','process_rfid_pipeline','resolve_provider_reads'])
     AND (has_function_privilege('authenticated', p.oid, 'EXECUTE')
          OR has_function_privilege('anon', p.oid, 'EXECUTE')
          OR NOT has_function_privilege('service_role', p.oid, 'EXECUTE'));
  PERFORM pg_temp.fail_if(n <> 0, 'EXECUTE de mantenimiento: ' || n);
  -- Ninguna política de escritura basada en el rol legacy queda en las tablas tocadas.
  SELECT count(*) INTO n FROM pg_policies
   WHERE schemaname = 'public' AND cmd <> 'SELECT'
     AND tablename IN ('carriers','products','regions','cities','nodes','material_catalog','postal_centers',
                       'readers','account_config','weekly_schedule','non_working_days','delivery_standards',
                       'product_materials')
     AND (coalesce(qual, '') || coalesce(with_check, '')) ~ '(current_user_role\(\)|superuser|profiles\.role)';
  PERFORM pg_temp.fail_if(n <> 0, 'políticas por rol legacy: ' || n);
  -- profiles: de escritura solo quedan las de superadmin, la del propio perfil y las de users:edit.
  SELECT count(*) INTO n FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'profiles' AND cmd <> 'SELECT'
     AND policyname NOT IN ('profile_delete_superadmin','profile_insert_superadmin','profiles_update_superadmin',
                            'profiles_update_own','profiles_insert_users_edit','profiles_update_users_edit',
                            'profiles_delete_users_edit');
  PERFORM pg_temp.fail_if(n <> 0, 'políticas de escritura en profiles: ' || n);
END $$;

-- ---------------------------------------------------------------- VW: View no escribe
SET ROLE authenticated;
SELECT pg_temp.as_user('95000000-0000-0000-0000-000000000095', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.panelists SET name = 'x' WHERE id = 'e1000000-0000-0000-0000-000000000001'$q$) <> 0,
    'View en panelists actualiza');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.panelists (account_id, panelist_code, name, email, mobile, status, language)
    VALUES ('a0000000-0000-0000-0000-000000000001','PV','V','v@t.l','9','active','en')$q$), 'View en panelists inserta');
  PERFORM pg_temp.fail_if(pg_temp.rows($q$DELETE FROM public.panelists WHERE id = 'e1000000-0000-0000-0000-000000000001'$q$) <> 0,
    'View en panelists borra');
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.carriers SET name = 'x' WHERE id = 'ca000000-0000-0000-0000-000000000001'$q$) <> 0,
    'View en carriers actualiza');
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.allocation_plan_details SET status = 'cancelled' WHERE id = 'd1000000-0000-0000-0000-000000000001'$q$) <> 0,
    'View en allocation_plans actualiza envíos');
  -- plan_action_delete (SECURITY DEFINER) con View en allocation_plans: excepción, y el envío sigue.
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.plan_action_delete(ARRAY['d1000000-0000-0000-0000-000000000001'::uuid], '{}')$q$),
    'plan_action_delete con View');
  -- Sí puede lo que su rol tiene en Edit (do_coordinator: readers_management, account_working_days).
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.readers SET name = 'R1b' WHERE id = 'f1000000-0000-0000-0000-000000000001'$q$) <> 1,
    'do_coordinator no actualiza lectores');
  PERFORM public.rpc_set_working_day('a0000000-0000-0000-0000-000000000001', 6, true);
END $$;
RESET ROLE;
DO $$ BEGIN
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE id = 'd1000000-0000-0000-0000-000000000001' AND status = 'pending'),
    'el envío D1 debía seguir pendiente');
  PERFORM pg_temp.fail_if((SELECT name FROM public.panelists WHERE id = 'e1000000-0000-0000-0000-000000000001') <> 'Pan1', 'P1 cambiado');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.weekly_schedule WHERE account_id = 'a0000000-0000-0000-0000-000000000001'
                                         AND postal_center_id IS NULL AND day_of_week = 6 AND is_working_day),
    'rpc_set_working_day con account_working_days:edit');
END $$;

-- ---------------------------------------------------------------- ED: Edit escribe, solo en la cuenta activa
SET ROLE authenticated;
SELECT pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
DO $$
DECLARE r jsonb;
BEGIN
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.panelists SET name = 'Pan1e' WHERE id = 'e1000000-0000-0000-0000-000000000001'$q$) <> 1,
    'Edit en panelists no actualiza');
  PERFORM pg_temp.fail_if(pg_temp.raises($q$INSERT INTO public.panelists (account_id, panelist_code, name, email, mobile, status, language)
    VALUES ('a0000000-0000-0000-0000-000000000001','PE','E','e@t.l','8','active','en')$q$), 'Edit en panelists no inserta');
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.carriers SET name = 'CarrierE' WHERE id = 'ca000000-0000-0000-0000-000000000001'$q$) <> 1,
    'Edit en carriers (sin rol legacy admin) no actualiza');
  -- A2: tiene rol (y carriers:edit) allí, pero su cuenta activa es A1 -> no escribe A2.
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.panelists SET name = 'x' WHERE id = 'e5000000-0000-0000-0000-000000000005'$q$) <> 0,
    'Edit en A1 actualiza A2');
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.carriers SET name = 'x' WHERE id = 'ca000000-0000-0000-0000-000000000002'$q$) <> 0,
    'Edit en A1 actualiza carriers de A2');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.panelists (account_id, panelist_code, name, email, mobile, status, language)
    VALUES ('a0000000-0000-0000-0000-000000000002','PX','X','x@t.l','7','active','en')$q$), 'Edit en A1 inserta en A2');
  -- panelist_manager no tiene readers_management ni postal_centers.
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.readers SET name = 'x' WHERE id = 'f1000000-0000-0000-0000-000000000001'$q$) <> 0,
    'panelist_manager actualiza lectores');
  -- Ni load_balancing ni account_working_days -> rpc_set_working_day rechazada.
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.rpc_set_working_day('a0000000-0000-0000-0000-000000000001', 0, true)$q$),
    'rpc_set_working_day sin derecho');
  -- plan_action_delete con allocation_plans:edit: borra.
  r := public.plan_action_delete(ARRAY['d1000000-0000-0000-0000-000000000001'::uuid], '{}');
  PERFORM pg_temp.fail_if((r->>'details')::int <> 1, 'plan_action_delete con Edit: ' || r::text);
  -- Escritura directa de envíos con allocation_plans:edit.
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.allocation_plan_details SET fecha_programada = '2027-03-13' WHERE id = 'd3000000-0000-0000-0000-000000000003'$q$) <> 1,
    'Edit en allocation_plans no actualiza envíos');
END $$;
RESET ROLE;
DO $$ BEGIN
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE id = 'd1000000-0000-0000-0000-000000000001'),
    'D1 no borrado');
  PERFORM pg_temp.fail_if((SELECT name FROM public.panelists WHERE id = 'e5000000-0000-0000-0000-000000000005') <> 'Pan5', 'P5 de A2 cambiado');
END $$;

-- ---------------------------------------------------------------- LA: rol legacy admin sin matriz
SET ROLE authenticated;
SELECT pg_temp.as_user('96000000-0000-0000-0000-000000000096', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.carriers SET name = 'x' WHERE id = 'ca000000-0000-0000-0000-000000000001'$q$) <> 0,
    'legacy admin actualiza carriers');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.regions (account_id, name, code)
    VALUES ('a0000000-0000-0000-0000-000000000001','R','RX')$q$), 'legacy admin inserta regions');
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.panelists SET name = 'x' WHERE id = 'e2000000-0000-0000-0000-000000000002'$q$) <> 0,
    'legacy admin actualiza panelists');
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.readers SET name = 'x' WHERE id = 'f1000000-0000-0000-0000-000000000001'$q$) <> 0,
    'legacy admin actualiza readers');
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.account_config SET updated_at = now() WHERE account_id = 'a0000000-0000-0000-0000-000000000001'$q$) <> 0,
    'legacy admin actualiza account_config');
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.profiles SET full_name = 'x' WHERE id = '99000000-0000-0000-0000-000000000099'$q$) <> 0,
    'legacy admin actualiza profiles');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.plan_action_delete(ARRAY['d2000000-0000-0000-0000-000000000002'::uuid], '{}')$q$),
    'legacy admin plan_action_delete');
  -- Su propio perfil sí (idioma, etc.: profiles_update_own).
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.profiles SET full_name = 'Legacy2' WHERE id = '96000000-0000-0000-0000-000000000096'$q$) <> 1,
    'legacy admin no actualiza su perfil');
END $$;
RESET ROLE;

-- receipt_mgr_check (sin EXECUTE para authenticated: se prueba como dueño con el JWT del usuario).
SELECT pg_temp.as_user('96000000-0000-0000-0000-000000000096', 'authenticated');
DO $$ BEGIN
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.receipt_mgr_check('a0000000-0000-0000-0000-000000000001')$q$),
    'receipt_mgr_check deja al admin legacy sin matriz');
END $$;
SELECT pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
DO $$ BEGIN
  PERFORM public.receipt_mgr_check('a0000000-0000-0000-0000-000000000001');
  PERFORM public.require_edit('a0000000-0000-0000-0000-000000000001', 'receipts');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.receipt_mgr_check('a0000000-0000-0000-0000-000000000002')$q$),
    'receipt_mgr_check en otra cuenta');
END $$;
SELECT pg_temp.as_user('95000000-0000-0000-0000-000000000095', 'authenticated');
DO $$ BEGIN
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.receipt_mgr_check('a0000000-0000-0000-0000-000000000001')$q$),
    'receipt_mgr_check sin receipts');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.cancel_detail('d2000000-0000-0000-0000-000000000002')$q$),
    'cancel_detail sin reported_incidents:edit');
END $$;

-- ---------------------------------------------------------------- SA: cualquier cuenta
SET ROLE authenticated;
SELECT pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
DO $$ BEGIN
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.panelists SET name = 'Pan5s' WHERE id = 'e5000000-0000-0000-0000-000000000005'$q$) <> 1,
    'superadmin no actualiza A2');
  PERFORM pg_temp.fail_if(pg_temp.raises($q$INSERT INTO public.carriers (account_id, code, name)
    VALUES ('a0000000-0000-0000-0000-000000000002','CS','CarrierS')$q$), 'superadmin no inserta en A2');
  PERFORM public.rpc_set_working_day('a0000000-0000-0000-0000-000000000002', 5, false);
END $$;
RESET ROLE;

-- ---------------------------------------------------------------- service_role y sin sesión
SET ROLE service_role;
SELECT pg_temp.as_user(NULL, 'service_role');
DO $$ BEGIN
  PERFORM pg_temp.fail_if(pg_temp.rows($q$UPDATE public.panelists SET name = 'Pan2s' WHERE id = 'e2000000-0000-0000-0000-000000000002'$q$) <> 1,
    'service_role no actualiza');
  PERFORM public.rpc_set_working_day('a0000000-0000-0000-0000-000000000001', 0, false);
END $$;
RESET ROLE;
SELECT pg_temp.as_user(NULL, NULL);
DO $$ BEGIN
  -- n8n / pg_cron / ops_*: auth.uid() NULL pasa las guardas.
  PERFORM public.rpc_set_working_day('a0000000-0000-0000-0000-000000000001', 0, true);
  PERFORM public.cancel_detail('d2000000-0000-0000-0000-000000000002');
  PERFORM public.require_edit('a0000000-0000-0000-0000-000000000001', 'carriers');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = 'd2000000-0000-0000-0000-000000000002') <> 'cancelled',
    'cancel_detail sin sesión');
END $$;

ROLLBACK;
\echo 'account_access_writes: OK'
