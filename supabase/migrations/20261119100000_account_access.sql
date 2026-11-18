-- Roles y derechos de acceso por cuenta (fase 1: datos y funciones).
-- Spec: docs/superpowers/specs/2026-11-18-roles-derechos-cuenta-design.md
--
-- Crea:
--   access_option      catálogo de las 28 opciones de menú (clave, grupo, orden)
--   access_template    plantilla global de derechos por rol (+ columna fija no_role = usuario sin rol)
--   account_access     matriz de cada cuenta (copia de la plantilla, editable por la cuenta)
--   account_user_role  roles de cada usuario en cada cuenta (un usuario puede estar en varias)
--   account_access_log registro de cambios
-- y las funciones que lee/escribe la web (todas validan dentro; nunca escritura directa en tablas).
--
-- Inerte hasta que el frontend lo use: no cambia permisos de nadie ni toca tablas existentes,
-- salvo prevent_account_id_change(), que ahora deja pasar el cambio de cuenta activa hecho por
-- set_active_account() (y gana search_path fijo).

-- ---------------------------------------------------------------- tablas
CREATE TABLE public.access_option (
  key        text PRIMARY KEY,
  menu_group text NOT NULL,
  sort       int  NOT NULL
);

CREATE TABLE public.access_template (
  role   text NOT NULL CHECK (role IN ('account_manager','panelist_manager','materials_supplier','do_coordinator',
                                      'upu_account_manager','allocation_plan_manager','no_role')),
  option text NOT NULL REFERENCES public.access_option(key) ON DELETE CASCADE,
  level  text NOT NULL CHECK (level IN ('edit','view')),
  PRIMARY KEY (role, option)
);

CREATE TABLE public.account_access (
  account_id uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  role       text NOT NULL CHECK (role IN ('account_manager','panelist_manager','materials_supplier','do_coordinator',
                                          'upu_account_manager','allocation_plan_manager')),
  option     text NOT NULL REFERENCES public.access_option(key) ON DELETE CASCADE,
  level      text NOT NULL CHECK (level IN ('edit','view')),
  PRIMARY KEY (account_id, role, option)
);

CREATE TABLE public.account_user_role (
  account_id  uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role        text NOT NULL CHECK (role IN ('account_manager','panelist_manager','materials_supplier','do_coordinator',
                                           'upu_account_manager','allocation_plan_manager')),
  provisional boolean NOT NULL DEFAULT false,
  PRIMARY KEY (account_id, user_id, role)
);
CREATE INDEX account_user_role_user_idx ON public.account_user_role (user_id, account_id);

CREATE TABLE public.account_access_log (
  id         bigserial PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  changed_by uuid,
  changed_at timestamptz NOT NULL DEFAULT now(),
  kind       text NOT NULL,
  detail     jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX account_access_log_account_idx ON public.account_access_log (account_id, changed_at DESC);

-- ---------------------------------------------------------------- catálogo y plantilla (literal del spec)
INSERT INTO public.access_option (key, menu_group, sort) VALUES
  ('dashboard',             'dashboard',       10),
  ('topology',              'e2e_setup',       20),
  ('carriers',              'e2e_setup',       30),
  ('panelists',             'e2e_setup',       40),
  ('e2e_sla',               'e2e_setup',       50),
  ('allocation_generator',  'e2e_allocation',  60),
  ('load_balancing',        'e2e_allocation',  70),
  ('allocation_plans',      'e2e_allocation',  80),
  ('material_requirements', 'e2e_materials',   90),
  ('stock_management',      'e2e_materials',  100),
  ('material_catalog',      'e2e_materials',  110),
  ('territory_equity',      'e2e_reporting',  120),
  ('compliance',            'e2e_reporting',  130),
  ('e2e_db',                'e2e_database',   140),
  ('e2e_db_api',            'e2e_database',   150),
  ('postal_centers',        'rfid_setup',     160),
  ('readers_management',    'rfid_setup',     170),
  ('segment_sla',           'rfid_setup',     180),
  ('route_analysis',        'rfid_reporting', 190),
  ('segment_analysis',      'rfid_reporting', 200),
  ('epcis_api',             'rfid_database',  210),
  ('rfid_events_db',        'rfid_database',  220),
  ('reported_incidents',    'incidents',      230),
  ('panelist_availability', 'incidents',      240),
  ('receipts',              'incidents',      250),
  ('users',                 'administration', 260),
  ('account_working_days',  'administration', 270),
  ('help_center',           'help',           280);

-- Columnas: AM, PM, MS, DO, UPU, APM, SR (E = edit, V = view, '' = sin acceso).
WITH m(option, am, pm, ms, dco, upu, apm, sr) AS (VALUES
  ('dashboard',             'V','V','V','V','V','V',''),
  ('topology',              'E','V','', '', 'E','E',''),
  ('carriers',              'E','', '', '', 'E','E',''),
  ('panelists',             'E','E','', '', 'E','V',''),
  ('e2e_sla',               'E','', '', '', 'E','E',''),
  ('allocation_generator',  'E','', '', '', 'E','E',''),
  ('load_balancing',        'E','', '', '', 'E','E',''),
  ('allocation_plans',      'E','', '', '', 'E','E',''),
  ('material_requirements', 'E','', 'E','', 'E','V',''),
  ('stock_management',      'E','V','E','', 'E','V',''),
  ('material_catalog',      'E','', 'E','', 'E','V',''),
  ('territory_equity',      'V','', '', '', 'V','V','V'),
  ('compliance',            'V','', '', '', 'V','V','V'),
  ('e2e_db',                'E','', '', '', 'E','V',''),
  ('e2e_db_api',            'E','', '', '', 'E','V',''),
  ('postal_centers',        'E','', '', 'E','E','V',''),
  ('readers_management',    'E','', '', 'E','E','V',''),
  ('segment_sla',           'E','', '', 'E','E','V',''),
  ('route_analysis',        'V','', '', 'V','V','V','V'),
  ('segment_analysis',      'V','', '', 'V','V','V','V'),
  ('epcis_api',             'E','', '', '', 'E','V',''),
  ('rfid_events_db',        'E','', '', '', 'E','V',''),
  ('reported_incidents',    'E','E','E','', 'E','E',''),
  ('panelist_availability', 'E','E','V','', 'E','V',''),
  ('receipts',              'E','', '', '', 'E','E',''),
  ('users',                 'V','', '', '', 'E','', ''),
  ('account_working_days',  'E','', '', 'E','E','E',''),
  ('help_center',           'V','V','V','V','V','V','V')
), cells(role, option, c) AS (
  SELECT 'account_manager', option, am FROM m UNION ALL
  SELECT 'panelist_manager', option, pm FROM m UNION ALL
  SELECT 'materials_supplier', option, ms FROM m UNION ALL
  SELECT 'do_coordinator', option, dco FROM m UNION ALL
  SELECT 'upu_account_manager', option, upu FROM m UNION ALL
  SELECT 'allocation_plan_manager', option, apm FROM m UNION ALL
  SELECT 'no_role', option, sr FROM m
)
INSERT INTO public.access_template (role, option, level)
SELECT role, option, CASE c WHEN 'E' THEN 'edit' ELSE 'view' END
FROM cells WHERE c <> '';

-- ---------------------------------------------------------------- helpers internos
-- Miembro de la cuenta: su cuenta activa, o tiene algún rol en ella, o superadmin.
-- SECURITY DEFINER para que las políticas de account_user_role no se llamen a sí mismas.
CREATE OR REPLACE FUNCTION public.is_account_member(p_account_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL AND p_account_id IS NOT NULL AND (
       public.is_superadmin()
    OR p_account_id = public.current_user_account_id()
    OR EXISTS (SELECT 1 FROM public.account_user_role r
                WHERE r.account_id = p_account_id AND r.user_id = auth.uid()))
$$;

CREATE OR REPLACE FUNCTION public.account_access_require_manager(p_account_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  IF NOT public.can_manage_account_access(p_account_id) THEN
    RAISE EXCEPTION 'Forbidden account' USING ERRCODE = '42501';
  END IF;
END $$;

-- ---------------------------------------------------------------- lectura de derechos
-- Derechos efectivos del usuario conectado en p_account_id (la cuenta elegida en la web).
--   superadmin: las 28 opciones en edit, sea cual sea la cuenta.
--   con roles en la cuenta: máximo por opción de account_access de sus roles (edit > view).
--   sin roles pero miembro (su cuenta activa): columna no_role de la plantilla.
--   resto (anon, otra cuenta): nada.
CREATE OR REPLACE FUNCTION public.my_access(p_account_id uuid)
 RETURNS TABLE(option text, level text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;
  IF public.is_superadmin() THEN
    RETURN QUERY SELECT o.key, 'edit'::text FROM public.access_option o ORDER BY o.sort;
    RETURN;
  END IF;
  IF p_account_id IS NULL THEN
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM public.account_user_role r WHERE r.account_id = p_account_id AND r.user_id = v_uid) THEN
    RETURN QUERY
      SELECT a.option, CASE WHEN bool_or(a.level = 'edit') THEN 'edit' ELSE 'view' END
        FROM public.account_access a
        JOIN public.account_user_role r ON r.account_id = a.account_id AND r.role = a.role
        JOIN public.access_option o ON o.key = a.option
       WHERE a.account_id = p_account_id AND r.user_id = v_uid
       GROUP BY a.option, o.sort
       ORDER BY o.sort;
    RETURN;
  END IF;
  IF p_account_id = public.current_user_account_id() THEN
    RETURN QUERY
      SELECT t.option, t.level
        FROM public.access_template t JOIN public.access_option o ON o.key = t.option
       WHERE t.role = 'no_role'
       ORDER BY o.sort;
  END IF;
END $$;

-- 'view' se cumple con edit o view; 'edit' solo con edit.
-- OJO fase 3: my_access/has_access devuelven vacío/false con JWT de service_role (no hay auth.uid()).
-- Toda política o función que los use debe exceptuar explícitamente auth.role() = 'service_role'
-- (bot n8n, crons) para no bloquearlo.
CREATE OR REPLACE FUNCTION public.has_access(p_account_id uuid, p_option text, p_level text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.my_access(p_account_id) m
     WHERE m.option = p_option
       AND (m.level = 'edit' OR (p_level = 'view' AND m.level = 'view'))
  )
$$;

-- Editores de la pestaña: fijo, no depende de la matriz (nadie se quita la capacidad de corregir).
CREATE OR REPLACE FUNCTION public.can_manage_account_access(p_account_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL AND p_account_id IS NOT NULL AND (
       public.is_superadmin()
    OR EXISTS (SELECT 1 FROM public.account_user_role r
                WHERE r.account_id = p_account_id AND r.user_id = auth.uid()
                  AND r.role IN ('account_manager','upu_account_manager')))
$$;

-- ---------------------------------------------------------------- escrituras (todas dejan log)
-- p_level NULL = quitar el derecho.
CREATE OR REPLACE FUNCTION public.account_access_set(p_account_id uuid, p_role text, p_option text, p_level text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE v_before text;
BEGIN
  PERFORM public.account_access_require_manager(p_account_id);
  IF p_role IS NULL OR p_role NOT IN ('account_manager','panelist_manager','materials_supplier','do_coordinator',
                                      'upu_account_manager','allocation_plan_manager') THEN
    RAISE EXCEPTION 'Invalid role: %', p_role USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.access_option o WHERE o.key = p_option) THEN
    RAISE EXCEPTION 'Invalid option: %', p_option USING ERRCODE = '22023';
  END IF;
  IF p_level IS NOT NULL AND p_level NOT IN ('edit','view') THEN
    RAISE EXCEPTION 'Invalid level: %', p_level USING ERRCODE = '22023';
  END IF;

  SELECT a.level INTO v_before FROM public.account_access a
   WHERE a.account_id = p_account_id AND a.role = p_role AND a.option = p_option;
  IF v_before IS NOT DISTINCT FROM p_level THEN
    RETURN;
  END IF;

  IF p_level IS NULL THEN
    DELETE FROM public.account_access a
     WHERE a.account_id = p_account_id AND a.role = p_role AND a.option = p_option;
  ELSE
    INSERT INTO public.account_access (account_id, role, option, level)
    VALUES (p_account_id, p_role, p_option, p_level)
    ON CONFLICT (account_id, role, option) DO UPDATE SET level = EXCLUDED.level;
  END IF;

  INSERT INTO public.account_access_log (account_id, changed_by, kind, detail)
  VALUES (p_account_id, auth.uid(), 'access_set',
          jsonb_build_object('role', p_role, 'option', p_option, 'before', v_before, 'after', p_level));
END $$;

-- Volver a la plantilla (sin no_role).
CREATE OR REPLACE FUNCTION public.account_access_reset(p_account_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE v_before jsonb;
BEGIN
  PERFORM public.account_access_require_manager(p_account_id);
  SELECT coalesce(jsonb_agg(jsonb_build_object('role', a.role, 'option', a.option, 'level', a.level)
                            ORDER BY a.role, a.option), '[]'::jsonb)
    INTO v_before FROM public.account_access a WHERE a.account_id = p_account_id;
  DELETE FROM public.account_access a WHERE a.account_id = p_account_id;
  INSERT INTO public.account_access (account_id, role, option, level)
  SELECT p_account_id, t.role, t.option, t.level FROM public.access_template t WHERE t.role <> 'no_role';
  INSERT INTO public.account_access_log (account_id, changed_by, kind, detail)
  VALUES (p_account_id, auth.uid(), 'access_reset', jsonb_build_object('before', v_before));
END $$;

-- Activa/quita un rol a un usuario que ya es de la cuenta (cuenta activa o algún rol en ella).
-- Al activar, provisional = false (confirma el rol provisional de la activación).
CREATE OR REPLACE FUNCTION public.account_user_role_set(p_account_id uuid, p_user_id uuid, p_role text, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE v_existed boolean;
BEGIN
  PERFORM public.account_access_require_manager(p_account_id);
  IF p_role IS NULL OR p_role NOT IN ('account_manager','panelist_manager','materials_supplier','do_coordinator',
                                      'upu_account_manager','allocation_plan_manager') THEN
    RAISE EXCEPTION 'Invalid role: %', p_role USING ERRCODE = '22023';
  END IF;
  IF p_enabled IS NULL THEN
    RAISE EXCEPTION 'p_enabled is required' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = p_user_id AND p.account_id = p_account_id)
     AND NOT EXISTS (SELECT 1 FROM public.account_user_role r WHERE r.user_id = p_user_id AND r.account_id = p_account_id) THEN
    RAISE EXCEPTION 'User is not a member of this account' USING ERRCODE = '42501';
  END IF;

  v_existed := EXISTS (SELECT 1 FROM public.account_user_role r
                        WHERE r.account_id = p_account_id AND r.user_id = p_user_id AND r.role = p_role);
  -- Sin cambio real (quitar un rol que no tiene): no se toca nada ni se deja log.
  IF NOT p_enabled AND NOT v_existed THEN
    RETURN;
  END IF;
  -- Un editor de la pestaña no puede quitarse su último rol de editor (anti-objetivo del spec).
  IF NOT p_enabled AND p_user_id = auth.uid() AND NOT public.is_superadmin()
     AND p_role IN ('account_manager','upu_account_manager')
     AND NOT EXISTS (SELECT 1 FROM public.account_user_role r
                      WHERE r.account_id = p_account_id AND r.user_id = p_user_id
                        AND r.role IN ('account_manager','upu_account_manager') AND r.role <> p_role) THEN
    RAISE EXCEPTION 'Cannot remove your last editor role in this account' USING ERRCODE = '42501';
  END IF;
  IF p_enabled THEN
    INSERT INTO public.account_user_role (account_id, user_id, role, provisional)
    VALUES (p_account_id, p_user_id, p_role, false)
    ON CONFLICT (account_id, user_id, role) DO UPDATE SET provisional = false;
  ELSE
    DELETE FROM public.account_user_role r
     WHERE r.account_id = p_account_id AND r.user_id = p_user_id AND r.role = p_role;
  END IF;

  INSERT INTO public.account_access_log (account_id, changed_by, kind, detail)
  VALUES (p_account_id, auth.uid(), 'user_role_set',
          jsonb_build_object('user_id', p_user_id, 'role', p_role, 'enabled', p_enabled, 'existed', v_existed));
END $$;

-- Solo superadmin: añade a la cuenta (con un rol) a un usuario existente, normalmente de otra cuenta.
CREATE OR REPLACE FUNCTION public.account_user_role_add_by_email(p_account_id uuid, p_email text, p_role text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE v_user uuid; v_user_role text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_superadmin() THEN
    RAISE EXCEPTION 'Only superadmin' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = p_account_id) THEN
    RAISE EXCEPTION 'Account not found' USING ERRCODE = '22023';
  END IF;
  IF p_role IS NULL OR p_role NOT IN ('account_manager','panelist_manager','materials_supplier','do_coordinator',
                                      'upu_account_manager','allocation_plan_manager') THEN
    RAISE EXCEPTION 'Invalid role: %', p_role USING ERRCODE = '22023';
  END IF;
  SELECT p.id, p.role INTO v_user, v_user_role FROM public.profiles p
   WHERE lower(p.email) = lower(trim(p_email)) LIMIT 1;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'User not found: %', p_email USING ERRCODE = '22023';
  END IF;
  IF v_user_role = 'superadmin' THEN
    RAISE EXCEPTION 'Superadmin does not take account roles' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.account_user_role (account_id, user_id, role, provisional)
  VALUES (p_account_id, v_user, p_role, false)
  ON CONFLICT (account_id, user_id, role) DO UPDATE SET provisional = false;

  INSERT INTO public.account_access_log (account_id, changed_by, kind, detail)
  VALUES (p_account_id, auth.uid(), 'user_role_add_by_email',
          jsonb_build_object('user_id', v_user, 'email', p_email, 'role', p_role));
  RETURN v_user;
END $$;

-- Cambia la cuenta activa (profiles.account_id) a otra en la que el usuario tiene rol.
-- Así las políticas RLS basadas en current_user_account_id() siguen igual.
-- Superadmin: no aplica (su cuenta es NULL por check_account_role; elige cuenta en la web) -> excepción.
-- No deja log en account_access_log: no cambia la configuración de acceso de la cuenta.
CREATE OR REPLACE FUNCTION public.set_active_account(p_account_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.is_superadmin() THEN
    RAISE EXCEPTION 'Superadmin has no active account' USING ERRCODE = '22023';
  END IF;
  IF p_account_id IS NULL
     OR (NOT EXISTS (SELECT 1 FROM public.account_user_role r WHERE r.user_id = v_uid AND r.account_id = p_account_id)
         AND p_account_id IS DISTINCT FROM public.current_user_account_id()) THEN
    RAISE EXCEPTION 'Forbidden account' USING ERRCODE = '42501';
  END IF;
  IF p_account_id = public.current_user_account_id() THEN
    RETURN;
  END IF;
  -- Hasta la fase 3 las políticas RLS heredadas dan privilegios de admin por
  -- current_user_role() = 'admin' AND account_id = current_user_account_id(). Un admin no puede llevarse
  -- ese poder a otra cuenta salvo que allí sea editor (account_manager o upu_account_manager).
  IF EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = v_uid AND p.role = 'admin')
     AND NOT EXISTS (SELECT 1 FROM public.account_user_role r
                      WHERE r.user_id = v_uid AND r.account_id = p_account_id
                        AND r.role IN ('account_manager','upu_account_manager')) THEN
    RAISE EXCEPTION 'Admin can only switch to accounts where they are account manager or UPU account manager'
      USING ERRCODE = '42501';
  END IF;
  -- Permiso de un solo uso (local a la transacción) para el veto de prevent_account_id_change().
  PERFORM set_config('onems.active_account_switch', v_uid::text, true);
  UPDATE public.profiles SET account_id = p_account_id WHERE id = v_uid;
  PERFORM set_config('onems.active_account_switch', '', true);
END $$;

-- Cuentas del usuario: su cuenta activa + las cuentas donde tiene rol. Superadmin: todas.
CREATE OR REPLACE FUNCTION public.my_accounts()
 RETURNS TABLE(account_id uuid, name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $$
  SELECT a.id, a.name
    FROM public.accounts a
   WHERE auth.uid() IS NOT NULL
     AND (public.is_superadmin()
          OR a.id = public.current_user_account_id()
          OR EXISTS (SELECT 1 FROM public.account_user_role r WHERE r.account_id = a.id AND r.user_id = auth.uid()))
   ORDER BY a.name
$$;

-- Contactos (los 6 correos de accounts.email_*): solo se actualizan las claves presentes en p_contacts.
-- Cadena vacía = sin contacto (NULL). Claves desconocidas se ignoran.
CREATE OR REPLACE FUNCTION public.account_contacts_set(p_account_id uuid, p_contacts jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE v_before jsonb; v_before_sent jsonb;
  k_cols constant text[] := ARRAY['email_account_manager','email_panelist_manager','email_materials_supplier',
                                  'email_do_coordinator','email_upu_account_manager','email_allocation_plan_manager'];
BEGIN
  PERFORM public.account_access_require_manager(p_account_id);
  IF p_contacts IS NULL OR jsonb_typeof(p_contacts) <> 'object' THEN
    RAISE EXCEPTION 'p_contacts must be a json object' USING ERRCODE = '22023';
  END IF;

  SELECT jsonb_build_object(
           'email_account_manager', a.email_account_manager, 'email_panelist_manager', a.email_panelist_manager,
           'email_materials_supplier', a.email_materials_supplier, 'email_do_coordinator', a.email_do_coordinator,
           'email_upu_account_manager', a.email_upu_account_manager,
           'email_allocation_plan_manager', a.email_allocation_plan_manager)
    INTO v_before FROM public.accounts a WHERE a.id = p_account_id;
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'Account not found' USING ERRCODE = '22023';
  END IF;

  UPDATE public.accounts a SET
    email_account_manager = CASE WHEN p_contacts ? 'email_account_manager'
      THEN nullif(trim(p_contacts->>'email_account_manager'), '') ELSE a.email_account_manager END,
    email_panelist_manager = CASE WHEN p_contacts ? 'email_panelist_manager'
      THEN nullif(trim(p_contacts->>'email_panelist_manager'), '') ELSE a.email_panelist_manager END,
    email_materials_supplier = CASE WHEN p_contacts ? 'email_materials_supplier'
      THEN nullif(trim(p_contacts->>'email_materials_supplier'), '') ELSE a.email_materials_supplier END,
    email_do_coordinator = CASE WHEN p_contacts ? 'email_do_coordinator'
      THEN nullif(trim(p_contacts->>'email_do_coordinator'), '') ELSE a.email_do_coordinator END,
    email_upu_account_manager = CASE WHEN p_contacts ? 'email_upu_account_manager'
      THEN nullif(trim(p_contacts->>'email_upu_account_manager'), '') ELSE a.email_upu_account_manager END,
    email_allocation_plan_manager = CASE WHEN p_contacts ? 'email_allocation_plan_manager'
      THEN nullif(trim(p_contacts->>'email_allocation_plan_manager'), '') ELSE a.email_allocation_plan_manager END,
    updated_at = now()
  WHERE a.id = p_account_id;

  SELECT jsonb_object_agg(k, v_before->k) INTO v_before_sent FROM unnest(k_cols) k WHERE p_contacts ? k;
  INSERT INTO public.account_access_log (account_id, changed_by, kind, detail)
  VALUES (p_account_id, auth.uid(), 'contacts_set',
          jsonb_build_object('before', coalesce(v_before_sent, '{}'::jsonb),
                             'after', (SELECT coalesce(jsonb_object_agg(k, nullif(trim(p_contacts->>k), '')), '{}'::jsonb)
                                         FROM unnest(k_cols) k WHERE p_contacts ? k)));
END $$;

-- ---------------------------------------------------------------- cuentas nuevas y existentes
CREATE OR REPLACE FUNCTION public.account_access_copy_template()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
BEGIN
  INSERT INTO public.account_access (account_id, role, option, level)
  SELECT NEW.id, t.role, t.option, t.level FROM public.access_template t WHERE t.role <> 'no_role'
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END $$;

CREATE TRIGGER accounts_copy_access_template
  AFTER INSERT ON public.accounts
  FOR EACH ROW EXECUTE FUNCTION public.account_access_copy_template();

INSERT INTO public.account_access (account_id, role, option, level)
SELECT a.id, t.role, t.option, t.level
  FROM public.accounts a CROSS JOIN public.access_template t
 WHERE t.role <> 'no_role'
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------- veto de cambio de cuenta
-- Igual que 20260715120000 + search_path fijo + permiso puntual de set_active_account()
-- (GUC local a la transacción con el id del propio usuario; la API no puede fijar GUCs).
CREATE OR REPLACE FUNCTION public.prevent_account_id_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = public
AS $function$
BEGIN
  IF TG_TABLE_NAME = 'profiles' THEN
    IF OLD.role IS DISTINCT FROM NEW.role THEN
      RETURN NEW;
    END IF;
    IF public.is_user_superadmin() THEN
      RETURN NEW;
    END IF;
    IF OLD.account_id IS DISTINCT FROM NEW.account_id
       AND NEW.id::text = coalesce(current_setting('onems.active_account_switch', true), '')
       AND EXISTS (SELECT 1 FROM public.account_user_role r
                    WHERE r.user_id = NEW.id AND r.account_id = NEW.account_id) THEN
      RETURN NEW;
    END IF;
  END IF;

  IF OLD.account_id IS DISTINCT FROM NEW.account_id THEN
    RAISE EXCEPTION 'account_id cannot be changed after creation';
  END IF;

  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------- RLS y permisos
ALTER TABLE public.access_option      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_template    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_access     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_user_role  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_access_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY access_option_select ON public.access_option FOR SELECT TO authenticated USING (true);
CREATE POLICY access_template_select ON public.access_template FOR SELECT TO authenticated USING (true);
CREATE POLICY account_access_select ON public.account_access FOR SELECT TO authenticated
  USING (public.is_account_member(account_id));
CREATE POLICY account_user_role_select ON public.account_user_role FOR SELECT TO authenticated
  USING (public.is_account_member(account_id));
CREATE POLICY account_access_log_select ON public.account_access_log FOR SELECT TO authenticated
  USING (public.is_account_member(account_id));

REVOKE ALL ON public.access_option, public.access_template, public.account_access,
              public.account_user_role, public.account_access_log FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.access_option, public.access_template, public.account_access,
                public.account_user_role, public.account_access_log TO authenticated;
GRANT ALL ON public.access_option, public.access_template, public.account_access,
             public.account_user_role, public.account_access_log TO service_role;
REVOKE ALL ON SEQUENCE public.account_access_log_id_seq FROM PUBLIC, anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.account_access_log_id_seq TO service_role;

REVOKE ALL ON FUNCTION public.is_account_member(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.account_access_require_manager(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_access_copy_template() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.my_access(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.has_access(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_manage_account_access(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.account_access_set(uuid, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.account_access_reset(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.account_user_role_set(uuid, uuid, text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.account_user_role_add_by_email(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_active_account(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.my_accounts() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.account_contacts_set(uuid, jsonb) FROM PUBLIC, anon;

-- is_account_member: la usan las políticas RLS (se evalúan con el rol del que consulta).
GRANT EXECUTE ON FUNCTION public.is_account_member(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.my_access(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_access(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_account_access(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.account_access_set(uuid, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.account_access_reset(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.account_user_role_set(uuid, uuid, text, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.account_user_role_add_by_email(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_active_account(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.my_accounts() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.account_contacts_set(uuid, jsonb) TO authenticated, service_role;
