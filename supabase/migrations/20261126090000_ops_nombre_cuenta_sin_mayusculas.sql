-- Agente de operaciones / bot de gestores: el nombre de la cuenta se compara sin distinguir mayúsculas ni
-- espacios de los extremos.
--
-- Por qué: el 24/11 la cuenta "KENYA" pasó a llamarse "Kenya" en ONEMS. El bot de gestores guarda el
-- nombre de la cuenta elegida y la base lo buscaba EXACTO ("a.name = p_account"): dejó de encontrarla y el
-- bot respondía "Ahora no puedo comprobar tu acceso". Con este cambio "KENYA", "Kenya" y " kenya " son la
-- misma cuenta. Si dos cuentas activas coinciden así (no pasa hoy), las funciones siguen fallando como
-- antes ("cardinality <> 1"): nunca se elige una al azar.
--
-- Las listas que devuelve la base (ops_manager_accounts, ops_manager_lookup) dan el nombre sin espacios en
-- los extremos ("Tunisia " -> "Tunisia"); el bot reenvía ese nombre y se encuentra igual.
--
-- Solo cambia la comparación del nombre; el resto del cuerpo es el vivo en prod el 2026-11-26.

-- ---------- ops_case._account ----------
CREATE OR REPLACE FUNCTION ops_case._account(p_name text, p_prefix text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_ids uuid[];
BEGIN
  IF p_name IS NULL THEN RETURN NULL; END IF;
  v_ids := ARRAY(SELECT a.id FROM public.accounts a
                  WHERE lower(btrim(a.name)) = lower(btrim(p_name)) AND a.status = 'active');
  IF cardinality(v_ids) <> 1 THEN
    RAISE EXCEPTION '%: cuenta no encontrada', p_prefix;
  END IF;
  RETURN v_ids[1];
END $function$;

-- ---------- ops_case._actor ----------
CREATE OR REPLACE FUNCTION ops_case._actor(p_token text, p_account text, p_actor_email text, p_prefix text, p_require_enabled boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_ids uuid[]; v_email text;
BEGIN
  IF ops_test._caller(p_token) = 'owner' THEN
    RETURN ops_case._account(p_account, p_prefix);
  END IF;
  v_ids := ARRAY(SELECT a.id FROM public.accounts a
                  WHERE lower(btrim(a.name)) = lower(btrim(p_account)) AND a.status = 'active');
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
END $function$;

-- ---------- ops_fix._account ----------
CREATE OR REPLACE FUNCTION ops_fix._account(p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_ids uuid[];
BEGIN
  v_ids := ARRAY(SELECT a.id FROM public.accounts a WHERE lower(btrim(a.name)) = lower(btrim(p_name)));
  IF cardinality(v_ids) <> 1 THEN
    RAISE EXCEPTION 'ops_fix: la cuenta "%" no existe o no es unica', p_name;
  END IF;
  RETURN v_ids[1];
END $function$;

-- ---------- ops_case_account_enabled ----------
CREATE OR REPLACE FUNCTION public.ops_case_account_enabled(p_token text, p_account text, p_actor_email text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_ids uuid[];
BEGIN
  IF ops_test._caller(p_token) = 'manager' THEN
    PERFORM ops_case._actor(p_token, p_account, p_actor_email, 'ops_case', false);
  END IF;
  v_ids := ARRAY(SELECT a.id FROM public.accounts a
                  WHERE lower(btrim(a.name)) = lower(btrim(p_account)) AND a.status = 'active');
  IF cardinality(v_ids) <> 1 THEN RETURN false; END IF;
  RETURN public.case_analysis_allowed(v_ids[1]);
END $function$;

-- ---------- ops_report_data (antes SELECT INTO: con dos coincidencias habría cogido una cualquiera) ----------
CREATE OR REPLACE FUNCTION public.ops_report_data(p_token text, p_account text, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_ids uuid[];
BEGIN
  PERFORM ops_test._check(p_token);
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from OR p_to - p_from > 31 THEN
    RAISE EXCEPTION 'ops_report: periodo no valido';
  END IF;
  v_ids := ARRAY(SELECT a.id FROM public.accounts a
                  WHERE lower(btrim(a.name)) = lower(btrim(p_account)) AND a.status = 'active');
  IF cardinality(v_ids) <> 1 THEN RAISE EXCEPTION 'ops_report: cuenta no encontrada'; END IF;
  RETURN ops_report._data(v_ids[1], p_from, p_to);
END $function$;

-- ---------- ops_manager_accounts ----------
CREATE OR REPLACE FUNCTION public.ops_manager_accounts(p_token text, p_exclude text[] DEFAULT '{}'::text[])
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  PERFORM ops_test._caller(p_token);
  RETURN ARRAY(SELECT btrim(a.name) FROM public.accounts a
                WHERE a.status = 'active' AND a.name IS NOT NULL AND btrim(a.name) <> ''
                  AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(p_exclude, '{}')) x
                                   WHERE lower(btrim(x)) = lower(btrim(a.name)))
                ORDER BY btrim(a.name));
END $function$;

-- ---------- ops_manager_lookup ----------
CREATE OR REPLACE FUNCTION public.ops_manager_lookup(p_token text, p_email text, p_exclude text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_email text; v_super boolean; v_accounts jsonb;
BEGIN
  PERFORM ops_test._caller(p_token);
  v_email := lower(btrim(COALESCE(p_email, '')));
  IF v_email = '' THEN
    RETURN jsonb_build_object('superadmin', false, 'accounts', '[]'::jsonb);
  END IF;

  v_super := EXISTS (SELECT 1 FROM public.profiles p
                      WHERE lower(btrim(p.email)) = v_email AND p.role = 'superadmin'
                        AND COALESCE(p.status, 'active') = 'active');

  SELECT COALESCE(jsonb_agg(jsonb_build_object('account', q.name, 'language', q.lang, 'role', q.role) ORDER BY q.name), '[]'::jsonb)
    INTO v_accounts
    FROM (SELECT btrim(a.name) AS name, a.default_language AS lang,
                 CASE WHEN lower(btrim(a.email_panelist_manager)) = v_email THEN 'panelist_manager'
                      WHEN lower(btrim(a.email_account_manager)) = v_email THEN 'account_manager'
                      ELSE 'allocation_plan_manager' END AS role
            FROM public.accounts a
           WHERE a.status = 'active'
             AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(p_exclude, '{}')) x
                              WHERE lower(btrim(x)) = lower(btrim(a.name)))
             AND v_email IN (lower(btrim(a.email_panelist_manager)), lower(btrim(a.email_account_manager)),
                             lower(btrim(a.email_allocation_plan_manager)))) q;

  RETURN jsonb_build_object('superadmin', v_super, 'accounts', v_accounts);
END $function$;

-- ---------- ops_messages_sent (solo la lista de exclusión) ----------
CREATE OR REPLACE FUNCTION public.ops_messages_sent(p_token text, p_since timestamp with time zone, p_exclude text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_out jsonb;
BEGIN
  PERFORM ops_test._check(p_token);
  IF p_since IS NULL OR p_since > now() OR p_since < now() - interval '7 days' THEN
    RAISE EXCEPTION 'ops_report: periodo no valido';
  END IF;

  WITH acc AS (
    SELECT a.id FROM public.accounts a
     WHERE NOT EXISTS (SELECT 1 FROM unnest(COALESCE(p_exclude, '{}'::text[])) x
                        WHERE lower(btrim(x)) = lower(btrim(a.name)))),
  n AS (
    SELECT pn.kind, pn.status, count(*) AS n
      FROM public.panelist_notification pn
     WHERE pn.account_id IN (SELECT id FROM acc)
       AND pn.status IN ('sent', 'failed')
       AND COALESCE(pn.sent_at, pn.created_at) >= p_since
     GROUP BY 1, 2),
  m AS (
    SELECT im.author, im.status, count(*) AS n
      FROM public.incident_message im
     WHERE im.account_id IN (SELECT id FROM acc)
       AND im.direction = 'outbound'
       AND im.status IN ('sent', 'failed')
       AND COALESCE(im.sent_at, im.created_at) >= p_since
     GROUP BY 1, 2),
  stuck AS (
    SELECT (SELECT count(*) FROM public.panelist_notification pn
             WHERE pn.account_id IN (SELECT id FROM acc) AND pn.status = 'pending_send'
               AND pn.created_at >= p_since
               AND COALESCE(pn.send_after, pn.created_at) < now() - interval '1 hour')
         + (SELECT count(*) FROM public.incident_message im
             WHERE im.account_id IN (SELECT id FROM acc) AND im.direction = 'outbound'
               AND im.status = 'pending_send' AND im.created_at >= p_since
               AND im.created_at < now() - interval '1 hour') AS n)
  SELECT jsonb_build_object(
    'notifications', COALESCE((SELECT jsonb_agg(jsonb_build_object('kind', n.kind, 'status', n.status, 'n', n.n)
                                                ORDER BY n.kind, n.status) FROM n), '[]'::jsonb),
    'incident_messages', COALESCE((SELECT jsonb_agg(jsonb_build_object('author', m.author, 'status', m.status, 'n', m.n)
                                                    ORDER BY m.author, m.status) FROM m), '[]'::jsonb),
    'stuck', (SELECT stuck.n FROM stuck))
    INTO v_out;
  RETURN v_out;
END $function$;
