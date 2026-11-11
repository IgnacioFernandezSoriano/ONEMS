-- ============================================================
-- Bot de analisis para los managers de cada cuenta — 2026-11-11, Tarea 1
-- ============================================================
-- Spec: docs/superpowers/specs/2026-11-11-bot-analisis-managers-design.md (§4, §9, §9b).
--   1. Rol nuevo en la ficha de la cuenta: accounts.email_allocation_plan_manager (mismo CHECK de formato
--      que los demas roles, patron de 20261109120000_account_contact_roles.sql).
--   2. ops_manager_lookup: dado un correo, si es superadmin de ONEMS y en que cuentas activas tiene un rol
--      que da acceso al bot (panelist_manager, account_manager, allocation_plan_manager).
--   3. ops_case_account_enabled: la puerta case_analysis_allowed de una cuenta (por nombre).
--   4. p_account text DEFAULT NULL (accounts.name) en ops_case_find_panelists, ops_case_data, ops_case_send,
--      ops_case_note y ops_fix_r4_preview/_apply/_undo. Si viene, find solo busca en esa cuenta y el resto
--      falla con "ops_case: otra cuenta" / "ops_fix: otra cuenta" si el objeto es de otra. Si es NULL, todo
--      se comporta como antes (bot de Ignacio, que llama con parametros con nombre sin p_account).
--      Cambiar la lista de parametros crea una sobrecarga: se borra la firma vieja y se crea la nueva.
--   5. Segundo token para el bot de managers (revision de seguridad, cerrado por defecto):
--      * ops_test.secret gana la columna role ('owner' = token de siempre, bot de Ignacio; 'manager' = bot de
--        managers). Las filas existentes quedan como 'owner'.
--      * ops_test._check ahora acepta SOLO el token 'owner': todas las funciones del agente que ya lo usan
--        (ops_test_*, ops_report_*, ops_fix_r1-r3, ops_case_claim/finish, ...) rechazan el token de managers
--        sin tocarlas, y cualquier funcion nueva que use _check tambien.
--      * ops_test._caller(p_token) -> 'owner' | 'manager' (mismo error que _check si el token no vale). Solo lo
--        usan las funciones que el bot de managers puede llamar: ops_manager_lookup y las que llevan p_account.
--      * Con el token 'manager', esas funciones exigen p_account (una cuenta activa; si no, "<prefijo>: falta
--        cuenta") y p_actor_email (nuevo ultimo parametro, DEFAULT NULL): el correo debe tener uno de los tres
--        roles en ESA cuenta o ser de un perfil superadmin; si no, "<prefijo>: sin permiso en esa cuenta".
--        Ademas la cuenta debe tener el analisis habilitado (case_analysis_allowed), si no "<prefijo>: cuenta
--        no habilitada" (ops_case_account_enabled no falla por eso: devuelve false).
--        Con el token 'owner', p_account y p_actor_email siguen siendo opcionales (comportamiento de hoy).
--      * Alta del token de managers (en el servidor, NUNCA en el repo): generar el token, guardarlo en el .env
--        del bot y, en el editor SQL de Supabase (rol postgres), ejecutar
--          SELECT ops_test.set_manager_token_hash('<sha256 en hex del token>');
--        (sustituye el hash anterior de managers; no toca el del bot de Ignacio). En PowerShell el hash sale de
--        [BitConverter]::ToString((New-Object Security.Cryptography.SHA256Managed).ComputeHash(
--          [Text.Encoding]::UTF8.GetBytes('<token>'))).Replace('-','').ToLower()
-- Funciones con token: anon + ops_test._check / _caller, SECURITY DEFINER, search_path ''. Forward-only.
-- ============================================================

-- ---------- 5. Token de managers ----------
ALTER TABLE ops_test.secret ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'owner';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'ops_test.secret'::regclass AND conname = 'secret_role_check') THEN
    ALTER TABLE ops_test.secret ADD CONSTRAINT secret_role_check CHECK (role IN ('owner', 'manager'));
  END IF;
END $$;

-- Quien llama: 'owner' o 'manager'. Si el hash estuviera con los dos roles, gana 'owner' (no deberia pasar).
CREATE OR REPLACE FUNCTION ops_test._caller(p_token text)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_role text;
BEGIN
  IF p_token IS NOT NULL THEN
    SELECT s.role INTO v_role FROM ops_test.secret s
     WHERE s.token_sha256 = encode(extensions.digest(p_token, 'sha256'), 'hex')
     ORDER BY (s.role = 'owner') DESC LIMIT 1;
  END IF;
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'ops_test: token no valido';
  END IF;
  RETURN v_role;
END $$;

-- Solo el token 'owner' (bot de Ignacio). El de managers no vale aqui.
CREATE OR REPLACE FUNCTION ops_test._check(p_token text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_token IS NULL OR NOT EXISTS (
       SELECT 1 FROM ops_test.secret s
        WHERE s.role = 'owner' AND s.token_sha256 = encode(extensions.digest(p_token, 'sha256'), 'hex')) THEN
    RAISE EXCEPTION 'ops_test: token no valido';
  END IF;
END $$;

-- Alta/cambio del token de managers: se pasa el sha256 (hex) del token, nunca el token.
CREATE OR REPLACE FUNCTION ops_test.set_manager_token_hash(p_sha256 text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_sha256 IS NULL OR lower(btrim(p_sha256)) !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'ops_test: el hash debe ser sha256 en hex (64 caracteres)';
  END IF;
  IF EXISTS (SELECT 1 FROM ops_test.secret s WHERE s.role = 'owner' AND s.token_sha256 = lower(btrim(p_sha256))) THEN
    RAISE EXCEPTION 'ops_test: ese hash ya es el del bot de Ignacio';
  END IF;
  DELETE FROM ops_test.secret s WHERE s.role = 'manager';
  INSERT INTO ops_test.secret (token_sha256, role) VALUES (lower(btrim(p_sha256)), 'manager');
END $$;

-- ---------- 1. Rol Allocation Plan Manager ----------
ALTER TABLE public.accounts ADD COLUMN IF NOT EXISTS email_allocation_plan_manager text NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.accounts'::regclass AND conname = 'accounts_email_allocation_plan_manager_format') THEN
    ALTER TABLE public.accounts ADD CONSTRAINT accounts_email_allocation_plan_manager_format
      CHECK (email_allocation_plan_manager IS NULL OR email_allocation_plan_manager ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$') NOT VALID;
    ALTER TABLE public.accounts VALIDATE CONSTRAINT accounts_email_allocation_plan_manager_format;
  END IF;
END $$;

COMMENT ON COLUMN public.accounts.email_allocation_plan_manager IS
  'Allocation Plan Manager: gestiona los planes de envío de la cuenta. Da acceso al bot de análisis de casos.';

-- ---------- Cuenta por nombre (para p_account) ----------
-- NULL -> NULL (sin control). Si no hay exactamente una cuenta activa con ese nombre, error con el prefijo dado.
CREATE OR REPLACE FUNCTION ops_case._account(p_name text, p_prefix text)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_ids uuid[];
BEGIN
  IF p_name IS NULL THEN RETURN NULL; END IF;
  v_ids := ARRAY(SELECT a.id FROM public.accounts a WHERE a.name = p_name AND a.status = 'active');
  IF cardinality(v_ids) <> 1 THEN
    RAISE EXCEPTION '%: cuenta no encontrada', p_prefix;
  END IF;
  RETURN v_ids[1];
END $$;

-- Token + cuenta + quien actua. Devuelve la cuenta (uuid) o NULL (solo token 'owner' sin p_account).
--   owner:   p_account opcional (si viene, debe existir); p_actor_email no se mira.
--   manager: p_account obligatoria (una cuenta activa), p_actor_email con rol en esa cuenta o superadmin y,
--            salvo p_require_enabled = false (solo ops_case_account_enabled), la cuenta con el analisis
--            habilitado (case_analysis_allowed); si no, "<prefijo>: cuenta no habilitada". El permiso se mira
--            antes: quien no tiene permiso no sabe si la cuenta esta habilitada.
CREATE OR REPLACE FUNCTION ops_case._actor(p_token text, p_account text, p_actor_email text, p_prefix text,
                                           p_require_enabled boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_ids uuid[]; v_email text;
BEGIN
  IF ops_test._caller(p_token) = 'owner' THEN
    RETURN ops_case._account(p_account, p_prefix);
  END IF;
  v_ids := ARRAY(SELECT a.id FROM public.accounts a WHERE a.name = p_account AND a.status = 'active');
  IF p_account IS NULL OR cardinality(v_ids) <> 1 THEN
    RAISE EXCEPTION '%: falta cuenta', p_prefix;
  END IF;
  v_email := lower(btrim(COALESCE(p_actor_email, '')));
  IF v_email = '' OR NOT (
       EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = v_ids[1]
                 AND v_email IN (lower(btrim(a.email_panelist_manager)), lower(btrim(a.email_account_manager)),
                                 lower(btrim(a.email_allocation_plan_manager))))
       OR EXISTS (SELECT 1 FROM public.profiles p WHERE lower(btrim(p.email)) = v_email AND p.role = 'superadmin'
                    AND COALESCE(p.status, 'active') = 'active')) THEN
    RAISE EXCEPTION '%: sin permiso en esa cuenta', p_prefix;
  END IF;
  IF p_require_enabled AND NOT public.case_analysis_allowed(v_ids[1]) THEN
    RAISE EXCEPTION '%: cuenta no habilitada', p_prefix;
  END IF;
  RETURN v_ids[1];
END $$;

-- ---------- 2. Busqueda por correo ----------
-- Devuelve {superadmin: bool, accounts: [{account, language, role}]}: una entrada por cuenta (si el correo
-- tiene varios roles en la misma cuenta, el primero de panelist_manager, account_manager,
-- allocation_plan_manager). Solo cuentas activas y fuera de p_exclude. Correos sin distinguir mayusculas
-- ni espacios. El agente rechaza a quien no es superadmin y sale en mas de una cuenta.
CREATE OR REPLACE FUNCTION public.ops_manager_lookup(p_token text, p_email text, p_exclude text[] DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_email text; v_super boolean; v_accounts jsonb;
BEGIN
  PERFORM ops_test._caller(p_token);   -- owner o manager (el bot de managers la usa en el alta)
  v_email := lower(btrim(COALESCE(p_email, '')));
  IF v_email = '' THEN
    RETURN jsonb_build_object('superadmin', false, 'accounts', '[]'::jsonb);
  END IF;

  v_super := EXISTS (SELECT 1 FROM public.profiles p
                      WHERE lower(btrim(p.email)) = v_email AND p.role = 'superadmin'
                        AND COALESCE(p.status, 'active') = 'active');

  SELECT COALESCE(jsonb_agg(jsonb_build_object('account', q.name, 'language', q.lang, 'role', q.role) ORDER BY q.name), '[]'::jsonb)
    INTO v_accounts
    FROM (SELECT a.name, a.default_language AS lang,
                 CASE WHEN lower(btrim(a.email_panelist_manager)) = v_email THEN 'panelist_manager'
                      WHEN lower(btrim(a.email_account_manager)) = v_email THEN 'account_manager'
                      ELSE 'allocation_plan_manager' END AS role
            FROM public.accounts a
           WHERE a.status = 'active'
             AND NOT (a.name = ANY (COALESCE(p_exclude, '{}')))
             AND v_email IN (lower(btrim(a.email_panelist_manager)), lower(btrim(a.email_account_manager)),
                             lower(btrim(a.email_allocation_plan_manager)))) q;

  RETURN jsonb_build_object('superadmin', v_super, 'accounts', v_accounts);
END $$;

-- ---------- 3. Puerta de analisis por cuenta ----------
-- Con el token owner nunca falla por la cuenta: inexistente o inactiva = false.
CREATE OR REPLACE FUNCTION public.ops_case_account_enabled(p_token text, p_account text, p_actor_email text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_ids uuid[];
BEGIN
  -- token de managers: cuenta y correo comprobados (falla), la puerta no (la respuesta es el false);
  -- owner: nunca falla por la cuenta
  IF ops_test._caller(p_token) = 'manager' THEN
    PERFORM ops_case._actor(p_token, p_account, p_actor_email, 'ops_case', false);
  END IF;
  v_ids := ARRAY(SELECT a.id FROM public.accounts a WHERE a.name = p_account AND a.status = 'active');
  IF cardinality(v_ids) <> 1 THEN RETURN false; END IF;
  RETURN public.case_analysis_allowed(v_ids[1]);
END $$;

-- ---------- 4. Control de cuenta ----------
-- Buscar panelistas: igual que antes (20261110121000) + filtro opcional por cuenta.
DROP FUNCTION IF EXISTS public.ops_case_find_panelists(text, text, text);
DROP FUNCTION IF EXISTS ops_case._find(text, text);
CREATE FUNCTION ops_case._find(p_name text, p_tag text, p_account uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_words text[]; v_norm text; v_out jsonb;
BEGIN
  v_words := ARRAY(SELECT w FROM regexp_split_to_table(lower(btrim(COALESCE(p_name, ''))), '\s+') w WHERE length(w) >= 2);
  v_norm := CASE WHEN btrim(COALESCE(p_tag, '')) = '' THEN NULL ELSE public.normalize_tag(p_tag) END;

  -- La etiqueta se resuelve UNA vez: ids de panelistas que la tocan (origen/destino de la linea, con respaldo del
  -- nodo, o con un caso de recepcion de esa etiqueta).
  WITH tagged AS (
    SELECT d.id AS did, d.account_id, d.origin_panelist_id, d.destination_panelist_id, d.origin_node_id, d.destination_node_id
      FROM public.allocation_plan_details d
     WHERE v_norm IS NOT NULL AND d.tag_id IS NOT NULL AND public.normalize_tag(d.tag_id) = v_norm),
  tag_pan AS (
    SELECT t.origin_panelist_id AS pid FROM tagged t WHERE t.origin_panelist_id IS NOT NULL
    UNION SELECT t.destination_panelist_id FROM tagged t WHERE t.destination_panelist_id IS NOT NULL
    UNION SELECT p.id FROM tagged t JOIN public.panelists p ON p.account_id = t.account_id AND p.node_id = t.origin_node_id
           WHERE t.origin_panelist_id IS NULL
    UNION SELECT p.id FROM tagged t JOIN public.panelists p ON p.account_id = t.account_id AND p.node_id = t.destination_node_id
           WHERE t.destination_panelist_id IS NULL
    UNION SELECT r.panelist_id FROM public.receipt_case r WHERE v_norm IS NOT NULL AND r.tag_norm = v_norm),
  cand AS (
    SELECT p.id, p.panelist_code, p.name, a.name AS account, btrim(c.name) AS city,
           (cardinality(v_words) > 0 AND NOT EXISTS (
              SELECT 1 FROM unnest(v_words) w WHERE position(w IN lower(p.name)) = 0)) AS by_name,
           (p.id IN (SELECT pid FROM tag_pan)) AS by_tag
      FROM public.panelists p
      JOIN public.accounts a ON a.id = p.account_id
      LEFT JOIN public.nodes n ON n.id = p.node_id
      LEFT JOIN public.cities c ON c.id = n.city_id
     WHERE p.status = 'active' AND (p_account IS NULL OR p.account_id = p_account)),
  sel AS (SELECT * FROM cand
           WHERE CASE WHEN EXISTS (SELECT 1 FROM cand c2 WHERE c2.by_name) THEN by_name ELSE by_tag END
           ORDER BY (by_name AND by_tag) DESC, by_name DESC, panelist_code LIMIT 10)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('panelist_id', s.id, 'code', s.panelist_code, 'name', s.name,
           'account', s.account, 'city', s.city, 'by_name', s.by_name, 'by_tag', s.by_tag)
           ORDER BY (s.by_name AND s.by_tag) DESC, s.by_name DESC, s.panelist_code), '[]'::jsonb)
    INTO v_out FROM sel s;
  RETURN v_out;
END $$;

CREATE FUNCTION public.ops_case_find_panelists(p_token text, p_name text, p_tag text, p_account text DEFAULT NULL,
                                               p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN ops_case._find(p_name, p_tag, ops_case._actor(p_token, p_account, p_actor_email, 'ops_case'));
END $$;

-- Todo lo de un caso: el panelista (y con el, la incidencia, que _data compara) debe ser de la cuenta.
DROP FUNCTION IF EXISTS public.ops_case_data(text, uuid, text, text, uuid);
CREATE FUNCTION public.ops_case_data(p_token text, p_panelist_id uuid, p_tag text,
                                     p_incident_kind text DEFAULT NULL, p_incident_id uuid DEFAULT NULL,
                                     p_account text DEFAULT NULL, p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_acc uuid; v_pan_acc uuid;
BEGIN
  v_acc := ops_case._actor(p_token, p_account, p_actor_email, 'ops_case');
  IF v_acc IS NOT NULL THEN
    SELECT p.account_id INTO v_pan_acc FROM public.panelists p WHERE p.id = p_panelist_id;
    IF v_pan_acc IS NULL THEN RAISE EXCEPTION 'ops_case: panelista no encontrado'; END IF;
    IF v_pan_acc <> v_acc THEN RAISE EXCEPTION 'ops_case: otra cuenta'; END IF;
  END IF;
  RETURN ops_case._data(p_panelist_id, p_tag, p_incident_kind, p_incident_id);
END $$;

-- Nota interna: la incidencia debe ser de la cuenta.
DROP FUNCTION IF EXISTS public.ops_case_note(text, text, uuid, text);
CREATE FUNCTION public.ops_case_note(p_token text, p_incident_kind text, p_incident_id uuid, p_body text,
                                     p_account text DEFAULT NULL, p_actor_email text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_acc uuid; v_inc_acc uuid;
BEGIN
  v_acc := ops_case._actor(p_token, p_account, p_actor_email, 'ops_case');
  IF v_acc IS NOT NULL THEN
    SELECT o.account_id INTO v_inc_acc FROM public.incident_owner(p_incident_kind, p_incident_id) o;
    IF v_inc_acc IS NULL THEN RAISE EXCEPTION 'ops_case: incidencia no encontrada'; END IF;
    IF v_inc_acc <> v_acc THEN RAISE EXCEPTION 'ops_case: otra cuenta'; END IF;
  END IF;
  RETURN ops_case._note(p_incident_kind, p_incident_id, p_body);
END $$;

-- Envio al panelista: igual que antes + el panelista debe ser de la cuenta (antes del dedupe por draft_key,
-- para no devolver ids de otra cuenta).
DROP FUNCTION IF EXISTS public.ops_case_send(text, text, uuid, uuid, text, text);
CREATE FUNCTION public.ops_case_send(p_token text, p_incident_kind text, p_incident_id uuid,
    p_panelist_id uuid, p_body text, p_draft_key text, p_account text DEFAULT NULL,
    p_actor_email text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_pan_acc uuid; v_status text; v_tg text; v_inc_acc uuid; v_id uuid; v_acc uuid;
BEGIN
  v_acc := ops_case._actor(p_token, p_account, p_actor_email, 'ops_case');
  IF p_body IS NULL OR length(btrim(p_body)) < 1 OR length(p_body) > 900 THEN
    RAISE EXCEPTION 'ops_case: el texto debe tener entre 1 y 900 caracteres'; END IF;
  IF btrim(COALESCE(p_draft_key, '')) = '' THEN RAISE EXCEPTION 'ops_case: falta draft_key'; END IF;
  IF (p_incident_kind IS NULL) <> (p_incident_id IS NULL) THEN RAISE EXCEPTION 'ops_case: incidencia no valida'; END IF;
  SELECT pa.account_id, pa.status, pa.telegram_id INTO v_pan_acc, v_status, v_tg
    FROM public.panelists pa WHERE pa.id = p_panelist_id;
  IF v_pan_acc IS NULL THEN RAISE EXCEPTION 'ops_case: panelista no encontrado'; END IF;
  IF v_acc IS NOT NULL AND v_pan_acc <> v_acc THEN RAISE EXCEPTION 'ops_case: otra cuenta'; END IF;
  IF p_incident_id IS NOT NULL THEN
    SELECT o.account_id INTO v_inc_acc FROM public.incident_owner(p_incident_kind, p_incident_id) o;
    IF v_inc_acc IS NULL THEN RAISE EXCEPTION 'ops_case: incidencia no encontrada'; END IF;
    IF v_inc_acc <> v_pan_acc THEN RAISE EXCEPTION 'ops_case: otra cuenta'; END IF;
  END IF;
  -- una misma draft_key se envia una sola vez (reintentos y doble pulsacion). El dedupe es solo por clave
  -- (las claves llevan prefijo UUID) y va ANTES de las comprobaciones de estado: un reintento devuelve el id existente.
  PERFORM pg_advisory_xact_lock(hashtextextended('ops_case_send:' || p_draft_key, 0));
  IF p_incident_id IS NOT NULL THEN
    SELECT m.id INTO v_id FROM public.incident_message m
     WHERE m.account_id = v_pan_acc AND m.meta->>'case_draft_key' = p_draft_key;
  ELSE
    SELECT n.id INTO v_id FROM public.panelist_notification n
     WHERE n.account_id = v_pan_acc AND n.kind = 'manager_notice' AND n.payload->>'case_draft_key' = p_draft_key;
  END IF;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  IF v_status IS DISTINCT FROM 'active' OR btrim(COALESCE(v_tg, '')) !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'ops_case: el panelista no esta activo o no tiene Telegram'; END IF;
  IF p_incident_id IS NOT NULL THEN
    -- draft_key es unica en toda la tabla (incident_message_case_draft_key_uq): si ya la uso otra cuenta, error
    -- (nunca se devuelve el id ajeno).
    BEGIN
      INSERT INTO public.incident_message (account_id, panelist_id, incident_kind, incident_id, direction, author, body, meta, status)
      VALUES (v_pan_acc, p_panelist_id, p_incident_kind, p_incident_id, 'outbound', 'manager', p_body,
              jsonb_build_object('manager_user_id', NULL, 'via', 'ops_agent', 'case_draft_key', p_draft_key), 'pending_send')
      RETURNING id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'ops_case: draft_key ya usada';
    END;
  ELSE
    INSERT INTO public.panelist_notification (account_id, panelist_id, kind, payload, send_after)
    VALUES (v_pan_acc, p_panelist_id, 'manager_notice',
            jsonb_build_object('body', p_body, 'via', 'ops_agent', 'case_draft_key', p_draft_key), NULL)
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END $$;

-- R4: vista previa (20261110140000) + el caso debe ser de la cuenta.
DROP FUNCTION IF EXISTS public.ops_fix_r4_preview(text, uuid);
CREATE FUNCTION public.ops_fix_r4_preview(p_token text, p_case_id uuid, p_account text DEFAULT NULL,
                                          p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v jsonb; v_acc uuid; v_case_acc uuid;
BEGIN
  v_acc := ops_case._actor(p_token, p_account, p_actor_email, 'ops_fix');
  -- la cuenta del caso se mira ANTES de _r4_check: con otra cuenta no se evalua nada de sus datos
  IF v_acc IS NOT NULL THEN
    SELECT c.account_id INTO v_case_acc FROM public.receipt_case c WHERE c.id = p_case_id;
    IF v_case_acc IS NOT NULL AND v_case_acc <> v_acc THEN
      RAISE EXCEPTION 'ops_fix: otra cuenta';
    END IF;
  END IF;
  v := ops_fix._r4_check(p_case_id);
  IF v_acc IS NOT NULL AND (v->>'account_id')::uuid IS DISTINCT FROM v_acc THEN
    RAISE EXCEPTION 'ops_fix: otra cuenta';
  END IF;
  -- case_status se devuelve siempre: el agente distingue «aplicado» (fixed) de «cerrado por otra persona».
  RETURN v - 'account_id' - 'panelist_id' - 'new_node_id';
END $$;

-- R4: aplicar (20261110140000) + el caso debe ser de la cuenta (antes de bloquear nada mas).
DROP FUNCTION IF EXISTS public.ops_fix_r4_apply(text, uuid, jsonb);
CREATE FUNCTION public.ops_fix_r4_apply(p_token text, p_case_id uuid, p_expected jsonb, p_account text DEFAULT NULL,
                                        p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE c public.receipt_case; v jsonb; v_det uuid; v_exp_at timestamptz; v_before jsonb; v_after jsonb;
        v_n int; v_prev text; v_line jsonb; v_onedb uuid[]; v_log bigint; v_acc uuid;
BEGIN
  v_acc := ops_case._actor(p_token, p_account, p_actor_email, 'ops_fix');
  SELECT * INTO c FROM public.receipt_case x WHERE x.id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ops_fix: el caso % no existe', p_case_id;
  END IF;
  IF v_acc IS NOT NULL AND c.account_id IS DISTINCT FROM v_acc THEN
    RAISE EXCEPTION 'ops_fix: otra cuenta';
  END IF;
  IF c.tag_norm IS NOT NULL THEN
    PERFORM 1 FROM public.allocation_plan_details x
     WHERE x.account_id = c.account_id AND public.normalize_tag(x.tag_id) = c.tag_norm FOR UPDATE;
  END IF;

  v := ops_fix._r4_check(p_case_id);
  IF NOT (v->>'applicable')::boolean THEN
    RAISE EXCEPTION 'ops_fix: R4 no aplica: %', v->>'reason';
  END IF;
  BEGIN
    v_exp_at := (p_expected->>'received_at')::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    v_exp_at := NULL;
  END;
  IF (v->>'detail_id') IS DISTINCT FROM (p_expected->>'detail_id')
     OR (v->>'new_dest_code') IS DISTINCT FROM (p_expected->>'new_dest_code')
     OR (v->>'received_at')::timestamptz IS DISTINCT FROM v_exp_at THEN
    RAISE EXCEPTION 'ops_fix: ha cambiado desde la propuesta';
  END IF;

  v_det := (v->>'detail_id')::uuid;
  v_before := jsonb_build_object('line', ops_fix._r4_line(v_det), 'case', ops_fix._r4_case(p_case_id));

  -- La regla POBOX ya se evaluó en _r4_check; el disparador no debe volver a aplicarla.
  v_prev := current_setting('onems.skip_pobox_receipt_rule', true);
  PERFORM set_config('onems.skip_pobox_receipt_rule', 'on', true);
  -- transfer_to_one_db no fija search_path (usa nombres sin esquema): se le da 'public' solo durante la
  -- escritura; al salir de la función vuelve el search_path vacío de la cláusula SET.
  PERFORM set_config('search_path', 'public, extensions, pg_temp', true);
  UPDATE public.allocation_plan_details x
     SET original_destination_node_id = COALESCE(x.original_destination_node_id, x.destination_node_id),
         destination_node_id = (v->>'new_node_id')::uuid,
         destination_panelist_id = (v->>'panelist_id')::uuid,
         destination_panelist_name = (SELECT p.name FROM public.panelists p WHERE p.id = (v->>'panelist_id')::uuid),
         reassignment_reason = 'sender_wrong_address',
         reassigned_at = now(),
         reassigned_by = NULL,
         status = 'received',
         received_at = (v->>'received_at')::timestamptz
   WHERE x.id = v_det AND x.account_id = (v->>'account_id')::uuid AND x.status = 'sent' AND x.received_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM set_config('search_path', '', true);
  PERFORM set_config('onems.skip_pobox_receipt_rule', COALESCE(v_prev, ''), true);
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'ops_fix: la línea cambió mientras se aplicaba; no toco nada';
  END IF;

  -- Relectura: la línea recibida y su copia en ONE DB (la hace el disparador transfer_to_one_db).
  v_line := ops_fix._r4_line(v_det);
  v_onedb := ARRAY(SELECT o.id FROM public.one_db o WHERE o.allocation_detail_id = v_det);
  IF v_line->>'status' IS DISTINCT FROM 'received' OR (v_line->>'transferred_to_one_db_at') IS NULL
     OR cardinality(v_onedb) <> 1 THEN
    RAISE EXCEPTION 'ops_fix: la copia a ONE DB no se hizo (%); no toco nada',
      COALESCE(v_line->>'transfer_error_message', v_line->>'validation_errors', 'sin detalle');
  END IF;

  UPDATE public.receipt_case x
     SET status = 'fixed', resolved_at = now(), resolved_by = NULL,
         resolution_note = 'Redirigida al receptor real (error de dirección del remitente) — agente de operaciones'
   WHERE x.id = p_case_id;

  v_after := jsonb_build_object('line', v_line, 'case', ops_fix._r4_case(p_case_id), 'one_db_id', v_onedb[1]);
  INSERT INTO ops_fix.log (kind, account_id, target, before, after)
  VALUES ('r4', (v->>'account_id')::uuid, p_case_id::text, v_before, v_after)
  RETURNING id INTO v_log;
  RETURN jsonb_build_object('log_id', v_log, 'detail_id', v_det, 'new_dest_code', v->>'new_dest_code');
END $$;

-- R4: deshacer (20261110140000) + el registro debe ser de la cuenta.
DROP FUNCTION IF EXISTS public.ops_fix_r4_undo(text, bigint);
CREATE FUNCTION public.ops_fix_r4_undo(p_token text, p_log_id bigint, p_account text DEFAULT NULL,
                                       p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE l ops_fix.log; v_det uuid; v_case uuid; v_onedb uuid; v_n int; v_acc uuid;
BEGIN
  v_acc := ops_case._actor(p_token, p_account, p_actor_email, 'ops_fix');
  SELECT * INTO l FROM ops_fix.log x WHERE x.id = p_log_id FOR UPDATE;
  IF NOT FOUND OR l.kind <> 'r4' THEN
    RAISE EXCEPTION 'ops_fix: el registro % no es un arreglo R4', p_log_id;
  END IF;
  IF v_acc IS NOT NULL AND l.account_id IS DISTINCT FROM v_acc THEN
    RAISE EXCEPTION 'ops_fix: otra cuenta';
  END IF;
  IF l.undone_at IS NOT NULL THEN
    RAISE EXCEPTION 'ops_fix: el arreglo % ya se deshizo', p_log_id;
  END IF;
  IF l.applied_at <= now() - interval '24 hours' THEN
    RAISE EXCEPTION 'ops_fix: han pasado más de 24 h desde el arreglo %; no lo deshago', p_log_id;
  END IF;

  v_det := (l.after->'line'->>'id')::uuid;
  v_case := (l.after->'case'->>'id')::uuid;
  v_onedb := (l.after->>'one_db_id')::uuid;
  PERFORM 1 FROM public.allocation_plan_details x WHERE x.id = v_det AND x.account_id = l.account_id FOR UPDATE;
  PERFORM 1 FROM public.receipt_case x WHERE x.id = v_case AND x.account_id = l.account_id FOR UPDATE;
  PERFORM 1 FROM public.one_db o WHERE o.id = v_onedb FOR UPDATE;

  IF ops_fix._r4_line(v_det) IS DISTINCT FROM l.after->'line'
     OR ops_fix._r4_case(v_case) IS DISTINCT FROM l.after->'case'
     OR (l.after->'line'->>'account_id')::uuid IS DISTINCT FROM l.account_id
     OR (l.after->'case'->>'account_id')::uuid IS DISTINCT FROM l.account_id
     OR NOT EXISTS (SELECT 1 FROM public.one_db o
                     WHERE o.id = v_onedb AND o.allocation_detail_id = v_det AND o.account_id = l.account_id)
     OR (SELECT count(*) FROM public.one_db o WHERE o.allocation_detail_id = v_det) <> 1 THEN
    RAISE EXCEPTION 'ops_fix: cambió después del arreglo; no lo deshago';
  END IF;

  -- Como en apply: los disparadores de allocation_plan_details sin search_path propio ven 'public'.
  PERFORM set_config('search_path', 'public, extensions, pg_temp', true);
  DELETE FROM public.one_db o WHERE o.id = v_onedb AND o.allocation_detail_id = v_det;

  UPDATE public.allocation_plan_details x
     SET (status, received_at, destination_node_id, destination_panelist_id, destination_panelist_name,
          original_destination_node_id, reassignment_reason, reassigned_at, reassigned_by,
          origin_panelist_id, origin_panelist_name, transferred_to_one_db_at, validation_errors,
          transfer_error_message) =
         (SELECT r.status, r.received_at, r.destination_node_id, r.destination_panelist_id, r.destination_panelist_name,
                 r.original_destination_node_id, r.reassignment_reason, r.reassigned_at, r.reassigned_by,
                 r.origin_panelist_id, r.origin_panelist_name, r.transferred_to_one_db_at, r.validation_errors,
                 r.transfer_error_message
            FROM pg_catalog.jsonb_populate_record(NULL::public.allocation_plan_details, l.before->'line') r)
   WHERE x.id = v_det AND x.account_id = l.account_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM set_config('search_path', '', true);
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'ops_fix: cambió después del arreglo; no lo deshago';
  END IF;

  UPDATE public.receipt_case x
     SET (status, resolved_at, resolved_by, resolution_note) =
         (SELECT r.status, r.resolved_at, r.resolved_by, r.resolution_note
            FROM pg_catalog.jsonb_populate_record(NULL::public.receipt_case, l.before->'case') r)
   WHERE x.id = v_case AND x.account_id = l.account_id;

  UPDATE ops_fix.log x SET undone_at = now() WHERE x.id = l.id;
  RETURN jsonb_build_object('restored', true);
END $$;

-- ---------- permisos: solo anon (el agente con su token) ----------
REVOKE ALL ON FUNCTION ops_case._account(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ops_case._actor(text, text, text, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ops_test._caller(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ops_test._check(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ops_test.set_manager_token_hash(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ops_case._find(text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_manager_lookup(text, text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_case_account_enabled(text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_case_find_panelists(text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_case_data(text, uuid, text, text, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_case_note(text, text, uuid, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_case_send(text, text, uuid, uuid, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_fix_r4_preview(text, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_fix_r4_apply(text, uuid, jsonb, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_fix_r4_undo(text, bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_manager_lookup(text, text, text[]) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_case_account_enabled(text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_case_find_panelists(text, text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_case_data(text, uuid, text, text, uuid, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_case_note(text, text, uuid, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_case_send(text, text, uuid, uuid, text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_fix_r4_preview(text, uuid, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_fix_r4_apply(text, uuid, jsonb, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_fix_r4_undo(text, bigint, text, text) TO anon;
