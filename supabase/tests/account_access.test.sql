-- Roles y derechos por cuenta (20261119100000_account_access.sql).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
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
-- Superadmin, usuario PM+MS (U1 del fixture, cuenta A1), AM de A1, usuario sin rol de A1,
-- usuario con roles en A1 y A2, y A3 (cuenta sin relación).
INSERT INTO public.accounts (id, name, slug) VALUES ('a0000000-0000-0000-0000-000000000003','Acc3','acc3');
INSERT INTO auth.users (id, email) VALUES
  ('97000000-0000-0000-0000-000000000097','super@t.l'),
  ('96000000-0000-0000-0000-000000000096','am@t.l'),
  ('95000000-0000-0000-0000-000000000095','norole@t.l'),
  ('94000000-0000-0000-0000-000000000094','multi@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL),
  ('96000000-0000-0000-0000-000000000096','am@t.l','AM','admin','a0000000-0000-0000-0000-000000000001'),
  ('95000000-0000-0000-0000-000000000095','norole@t.l','NoRole','user','a0000000-0000-0000-0000-000000000001'),
  ('94000000-0000-0000-0000-000000000094','multi@t.l','Multi','user','a0000000-0000-0000-0000-000000000001');
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','99000000-0000-0000-0000-000000000099','panelist_manager'),
  ('a0000000-0000-0000-0000-000000000001','99000000-0000-0000-0000-000000000099','materials_supplier'),
  ('a0000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000096','account_manager'),
  ('a0000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000094','panelist_manager'),
  ('a0000000-0000-0000-0000-000000000002','94000000-0000-0000-0000-000000000094','do_coordinator');

DO $$
DECLARE n int; b boolean;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  A2 constant uuid := 'a0000000-0000-0000-0000-000000000002';
  U1 constant text := '99000000-0000-0000-0000-000000000099';
  SA constant text := '97000000-0000-0000-0000-000000000097';
  AM constant text := '96000000-0000-0000-0000-000000000096';
  NR constant text := '95000000-0000-0000-0000-000000000095';
  MU constant text := '94000000-0000-0000-0000-000000000094';
BEGIN
  -- Plantilla: 28 opciones; 7 columnas (6 roles + no_role).
  SELECT count(*) INTO n FROM public.access_option;
  PERFORM pg_temp.fail_if(n <> 28, 'opciones: ' || n);
  SELECT count(DISTINCT role) INTO n FROM public.access_template;
  PERFORM pg_temp.fail_if(n <> 7, 'roles plantilla: ' || n);
  SELECT count(*) INTO n FROM public.access_template WHERE role = 'no_role';
  PERFORM pg_temp.fail_if(n <> 5, 'no_role plantilla: ' || n);
  -- Cuenta nueva (fixture): copia de los 6 roles, sin no_role.
  SELECT count(DISTINCT role) INTO n FROM public.account_access WHERE account_id = A2;
  PERFORM pg_temp.fail_if(n <> 6, 'roles copiados A2: ' || n);
  SELECT count(*) INTO n FROM public.account_access WHERE account_id = A2 AND role = 'no_role';
  PERFORM pg_temp.fail_if(n <> 0, 'no_role copiado');
  SELECT count(*) INTO n FROM public.account_access WHERE account_id = A2;
  PERFORM pg_temp.fail_if(n <> (SELECT count(*) FROM public.access_template WHERE role <> 'no_role'), 'copia completa: ' || n);
  -- Celdas de muestra de la plantilla.
  PERFORM pg_temp.fail_if((SELECT level FROM public.access_template WHERE role='account_manager' AND option='users') <> 'edit', 'AM users (20261119100170)');
  PERFORM pg_temp.fail_if((SELECT level FROM public.access_template WHERE role='upu_account_manager' AND option='users') <> 'edit', 'UPU users');
  PERFORM pg_temp.fail_if((SELECT level FROM public.access_template WHERE role='materials_supplier' AND option='panelist_availability') <> 'view', 'MS availability');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.access_template WHERE role='panelist_manager' AND option='carriers'), 'PM carriers');

  -- PM + MS: suma de roles, gana el mayor.
  PERFORM pg_temp.as_user(U1, 'authenticated');
  PERFORM pg_temp.fail_if(NOT public.has_access(A1, 'stock_management', 'edit'), 'PM+MS stock edit');
  PERFORM pg_temp.fail_if(NOT public.has_access(A1, 'stock_management', 'view'), 'PM+MS stock view');
  PERFORM pg_temp.fail_if(public.has_access(A1, 'carriers', 'view'), 'PM+MS carriers view');
  PERFORM pg_temp.fail_if(public.has_access(A2, 'stock_management', 'view'), 'PM+MS en otra cuenta');
  PERFORM pg_temp.fail_if(public.can_manage_account_access(A1), 'PM no gestiona');

  -- Sin rol: 5 vistas de reporting, sin dashboard.
  PERFORM pg_temp.as_user(NR, 'authenticated');
  SELECT count(*) INTO n FROM public.my_access(A1);
  PERFORM pg_temp.fail_if(n <> 5, 'sin rol filas: ' || n);
  SELECT count(*) INTO n FROM public.my_access(A1)
   WHERE level = 'view' AND option IN ('territory_equity','compliance','route_analysis','segment_analysis','help_center');
  PERFORM pg_temp.fail_if(n <> 5, 'sin rol opciones: ' || n);
  PERFORM pg_temp.fail_if(public.has_access(A1, 'dashboard', 'view'), 'sin rol dashboard');
  SELECT count(*) INTO n FROM public.my_access(A2);
  PERFORM pg_temp.fail_if(n <> 0, 'sin rol, otra cuenta: ' || n);

  -- Superadmin con A2 elegida: todo edit.
  PERFORM pg_temp.as_user(SA, 'authenticated');
  PERFORM pg_temp.fail_if(NOT public.has_access(A2, 'users', 'edit'), 'super users edit');
  SELECT count(*) INTO n FROM public.my_access(A2) WHERE level = 'edit';
  PERFORM pg_temp.fail_if(n <> 28, 'super my_access: ' || n);
  PERFORM pg_temp.fail_if(NOT public.can_manage_account_access(A2), 'super gestiona');

  -- AM de A1: cambia su matriz y queda log; sobre A2 rechazado.
  PERFORM pg_temp.as_user(AM, 'authenticated');
  PERFORM pg_temp.fail_if(NOT public.can_manage_account_access(A1), 'AM gestiona A1');
  PERFORM pg_temp.fail_if(public.can_manage_account_access(A2), 'AM no gestiona A2');
  PERFORM public.account_access_set(A1, 'panelist_manager', 'carriers', 'view');
  PERFORM pg_temp.fail_if((SELECT level FROM public.account_access WHERE account_id=A1 AND role='panelist_manager' AND option='carriers') <> 'view', 'set aplicado');
  SELECT count(*) INTO n FROM public.account_access_log WHERE account_id = A1 AND kind = 'access_set'
     AND changed_by = AM::uuid;
  PERFORM pg_temp.fail_if(n <> 1, 'log set: ' || n);
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_access_set('a0000000-0000-0000-0000-000000000002','panelist_manager','carriers','view')$q$), 'AM sobre A2');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_access_set('a0000000-0000-0000-0000-000000000001','no_role','carriers','view')$q$), 'no_role no editable');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_access_set('a0000000-0000-0000-0000-000000000001','panelist_manager','bogus','view')$q$), 'opción inexistente');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_access_set('a0000000-0000-0000-0000-000000000001','panelist_manager','carriers','admin')$q$), 'nivel inválido');
  -- PM de vuelta a View en carriers: U1 ahora lo ve.
  PERFORM pg_temp.as_user(U1, 'authenticated');
  PERFORM pg_temp.fail_if(NOT public.has_access(A1, 'carriers', 'view'), 'PM ve carriers tras set');
  PERFORM pg_temp.fail_if(public.has_access(A1, 'carriers', 'edit'), 'view no es edit');
  -- PM no puede cambiar la matriz ni roles.
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_access_set('a0000000-0000-0000-0000-000000000001','panelist_manager','carriers','edit')$q$), 'PM set');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_access_reset('a0000000-0000-0000-0000-000000000001')$q$), 'PM reset');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_user_role_set('a0000000-0000-0000-0000-000000000001','99000000-0000-0000-0000-000000000099','account_manager',true)$q$), 'PM se hace AM');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_contacts_set('a0000000-0000-0000-0000-000000000001','{"email_account_manager":"x@y.z"}')$q$), 'PM contactos');

  -- AM se quita todos los derechos de la matriz: sigue gestionando.
  PERFORM pg_temp.as_user(AM, 'authenticated');
  PERFORM public.account_access_set(A1, 'account_manager', o.key, NULL) FROM public.access_option o;
  SELECT count(*) INTO n FROM public.my_access(A1);
  PERFORM pg_temp.fail_if(n <> 0, 'AM sin derechos: ' || n);
  PERFORM pg_temp.fail_if(NOT public.can_manage_account_access(A1), 'AM sigue gestionando');
  -- Volver a la plantilla.
  PERFORM public.account_access_reset(A1);
  PERFORM pg_temp.fail_if(NOT public.has_access(A1, 'topology', 'edit'), 'reset restaura');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.account_access WHERE account_id=A1 AND role='panelist_manager' AND option='carriers'), 'reset quita cambio');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.account_access_log WHERE account_id=A1 AND kind='access_reset'), 'log reset');

  -- AM asigna/quita roles a usuarios de su cuenta (provisional pasa a false).
  UPDATE public.account_user_role SET provisional = true WHERE user_id = AM::uuid;
  PERFORM public.account_user_role_set(A1, AM::uuid, 'account_manager', true);
  PERFORM pg_temp.fail_if((SELECT provisional FROM public.account_user_role WHERE user_id=AM::uuid AND account_id=A1 AND role='account_manager'), 'provisional false');
  PERFORM public.account_user_role_set(A1, NR::uuid, 'do_coordinator', true);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.account_user_role WHERE user_id=NR::uuid AND role='do_coordinator'), 'rol asignado');
  PERFORM public.account_user_role_set(A1, NR::uuid, 'do_coordinator', false);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.account_user_role WHERE user_id=NR::uuid), 'rol quitado');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.account_access_log WHERE account_id=A1 AND kind='user_role_set'), 'log rol');
  -- Quitar un rol que no tiene: sin cambio y sin log.
  SELECT count(*) INTO n FROM public.account_access_log WHERE account_id=A1 AND kind='user_role_set';
  PERFORM public.account_user_role_set(A1, NR::uuid, 'materials_supplier', false);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.account_access_log WHERE account_id=A1 AND kind='user_role_set') <> n, 'log sin cambio');
  -- El AM no puede quitarse su último rol de editor.
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_user_role_set('a0000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000096','account_manager',false)$q$), 'AM se quita último rol editor');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.account_user_role WHERE user_id=AM::uuid AND account_id=A1 AND role='account_manager'), 'AM conserva rol');
  -- Con otro rol de editor (UPU), sí puede quitarse el de AM; y entonces no el de UPU.
  PERFORM public.account_user_role_set(A1, AM::uuid, 'upu_account_manager', true);
  PERFORM public.account_user_role_set(A1, AM::uuid, 'account_manager', false);
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_user_role_set('a0000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000096','upu_account_manager',false)$q$), 'UPU se quita último rol editor');
  PERFORM public.account_user_role_set(A1, AM::uuid, 'account_manager', true);
  PERFORM public.account_user_role_set(A1, AM::uuid, 'upu_account_manager', false);
  PERFORM pg_temp.fail_if(NOT public.can_manage_account_access(A1), 'AM sigue editor');
  -- Usuario de otra cuenta (98 en A2): no se le asigna desde A1.
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_user_role_set('a0000000-0000-0000-0000-000000000001','98000000-0000-0000-0000-000000000098','panelist_manager',true)$q$), 'usuario ajeno');
  -- Solo el superadmin añade por correo.
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_user_role_add_by_email('a0000000-0000-0000-0000-000000000001','actor2@t.l','panelist_manager')$q$), 'AM add_by_email');
  -- Contactos: solo las columnas presentes; queda log.
  UPDATE public.accounts SET email_do_coordinator = 'do@t.l' WHERE id = A1;
  PERFORM public.account_contacts_set(A1, '{"email_account_manager":"am@t.l","email_panelist_manager":""}'::jsonb);
  PERFORM pg_temp.fail_if((SELECT email_account_manager FROM public.accounts WHERE id=A1) <> 'am@t.l', 'contacto AM');
  PERFORM pg_temp.fail_if((SELECT email_panelist_manager FROM public.accounts WHERE id=A1) IS NOT NULL, 'contacto vacío = null');
  PERFORM pg_temp.fail_if((SELECT email_do_coordinator FROM public.accounts WHERE id=A1) IS DISTINCT FROM 'do@t.l', 'contacto ausente intacto');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.account_access_log WHERE account_id=A1 AND kind='contacts_set'), 'log contactos');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_contacts_set('a0000000-0000-0000-0000-000000000002','{"email_account_manager":"x@y.z"}')$q$), 'AM contactos A2');

  -- Superadmin añade por correo a un usuario de otra cuenta.
  PERFORM pg_temp.as_user(SA, 'authenticated');
  PERFORM public.account_user_role_add_by_email(A1, 'ACTOR2@t.l', 'panelist_manager');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.account_user_role WHERE account_id=A1 AND user_id='98000000-0000-0000-0000-000000000098'), 'add_by_email');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.account_user_role_add_by_email('a0000000-0000-0000-0000-000000000001','nobody@t.l','panelist_manager')$q$), 'correo inexistente');

  -- Usuario con roles en A1 y A2: cambia de cuenta activa.
  PERFORM pg_temp.as_user(MU, 'authenticated');
  SELECT count(*) INTO n FROM public.my_accounts();
  PERFORM pg_temp.fail_if(n <> 2, 'my_accounts: ' || n);
  PERFORM public.set_active_account(A2);
  PERFORM pg_temp.fail_if((SELECT account_id FROM public.profiles WHERE id = MU::uuid) <> A2, 'cuenta activa A2');
  PERFORM pg_temp.fail_if(public.current_user_account_id() <> A2, 'current_user_account_id A2');
  PERFORM pg_temp.fail_if(NOT public.has_access(A2, 'postal_centers', 'edit'), 'DO en A2');
  PERFORM public.set_active_account(A1);
  PERFORM pg_temp.fail_if((SELECT account_id FROM public.profiles WHERE id = MU::uuid) <> A1, 'vuelta a A1');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.set_active_account('a0000000-0000-0000-0000-000000000003')$q$), 'cuenta sin rol');
  -- El veto general del trigger sigue: un UPDATE directo de account_id falla.
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$UPDATE public.profiles SET account_id='a0000000-0000-0000-0000-000000000002' WHERE id='94000000-0000-0000-0000-000000000094'$q$), 'update directo');
  -- Un admin (AM de A1) con solo do_coordinator en A2 no se lleva su admin a A2.
  INSERT INTO public.account_user_role (account_id, user_id, role) VALUES (A2, AM::uuid, 'do_coordinator');
  PERFORM pg_temp.as_user(AM, 'authenticated');
  PERFORM pg_temp.fail_if(NOT pg_temp.raises($q$SELECT public.set_active_account('a0000000-0000-0000-0000-000000000002')$q$), 'admin cambia a cuenta sin ser editor');
  PERFORM pg_temp.fail_if((SELECT account_id FROM public.profiles WHERE id = AM::uuid) <> A1, 'admin sigue en A1');
  -- Siendo editor en A2 (UPU), sí.
  INSERT INTO public.account_user_role (account_id, user_id, role) VALUES (A2, AM::uuid, 'upu_account_manager');
  PERFORM public.set_active_account(A2);
  PERFORM pg_temp.fail_if((SELECT account_id FROM public.profiles WHERE id = AM::uuid) <> A2, 'admin editor cambia a A2');
  -- Usuario sin roles: my_accounts = su cuenta.
  PERFORM pg_temp.as_user(NR, 'authenticated');
  SELECT count(*) INTO n FROM public.my_accounts();
  PERFORM pg_temp.fail_if(n <> 1, 'my_accounts sin rol: ' || n);

  -- Sin sesión: nada.
  PERFORM pg_temp.as_user(NULL, NULL);
  SELECT count(*) INTO n FROM public.my_access(A1);
  PERFORM pg_temp.fail_if(n <> 0, 'anon my_access: ' || n);
  PERFORM pg_temp.fail_if(public.has_access(A1, 'help_center', 'view'), 'anon has_access');
END $$;

-- RLS: un usuario autenticado solo lee las filas de sus cuentas.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('95000000-0000-0000-0000-000000000095', 'authenticated');
DO $$
DECLARE n int;
BEGIN
  SELECT count(DISTINCT account_id) INTO n FROM public.account_access;
  PERFORM pg_temp.fail_if(n <> 1, 'RLS account_access: ' || n);
  SELECT count(*) INTO n FROM public.account_user_role WHERE account_id <> 'a0000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.fail_if(n <> 0, 'RLS account_user_role: ' || n);
  SELECT count(*) INTO n FROM public.access_template;
  PERFORM pg_temp.fail_if(n = 0, 'plantilla legible');
END $$;
SELECT pg_temp.fail_if(NOT pg_temp.raises($q$INSERT INTO public.account_user_role (account_id, user_id, role) VALUES ('a0000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000095','account_manager')$q$), 'insert directo');
SELECT pg_temp.fail_if(NOT pg_temp.raises($q$UPDATE public.account_access SET level='edit'$q$) AND
  EXISTS (SELECT 1 FROM public.account_access WHERE level <> 'edit'), 'update directo matriz');
RESET ROLE;
ROLLBACK;

-- Permisos: anon sin EXECUTE en ninguna función nueva; authenticated en las de la web.
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.my_access(uuid)', 'public.has_access(uuid, text, text)', 'public.can_manage_account_access(uuid)',
    'public.account_access_set(uuid, text, text, text)', 'public.account_access_reset(uuid)',
    'public.account_user_role_set(uuid, uuid, text, boolean)', 'public.account_user_role_add_by_email(uuid, text, text)',
    'public.set_active_account(uuid)', 'public.my_accounts()', 'public.account_contacts_set(uuid, jsonb)'] LOOP
    PERFORM pg_temp.fail_if(has_function_privilege('anon', f, 'EXECUTE'), 'anon ' || f);
    PERFORM pg_temp.fail_if(NOT has_function_privilege('authenticated', f, 'EXECUTE'), 'authenticated ' || f);
    PERFORM pg_temp.fail_if(NOT has_function_privilege('service_role', f, 'EXECUTE'), 'service_role ' || f);
  END LOOP;
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.is_account_member(uuid)', 'EXECUTE'), 'anon is_account_member');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.account_access_copy_template()', 'EXECUTE'), 'anon trigger fn');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.account_access_copy_template()', 'EXECUTE'), 'auth trigger fn');
END $$;
\echo 'account_access: OK'
