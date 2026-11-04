-- Errores de recepcion: RPCs de la pantalla del admin (resumen, tendencia, reincidentes, casos, decisiones y avisos).
-- Spec: docs/superpowers/specs/2026-11-04-errores-recepcion-design.md. Tarea 3 del plan.
--
-- Todo es ADITIVO (funciones nuevas). Todas SECURITY DEFINER SET search_path = public, con el control de cuenta de
-- rpc_deferred_samples_summary (auth.uid() nulo = service_role/SQL directo) y ademas rol admin/superadmin.
-- Las RPCs que reciben un caso o un panelista derivan la cuenta de la fila y aplican el mismo control.
-- Zona horaria: COALESCE(accounts.timezone, 'UTC').

-- Si una tabla esta ocupada, mejor fallar a los 5 s que dejar en cola a todas las consultas detras del cerrojo.
SET lock_timeout = '5s';

-- ============================================================================================================
-- 0. Control de acceso comun (solo se llama desde las RPCs de abajo, que corren como propietario)
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.receipt_mgr_check(p_account_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_account uuid;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin() THEN
    SELECT p.role, p.account_id INTO v_role, v_account FROM public.profiles p WHERE p.id = auth.uid();
    IF v_role IS DISTINCT FROM 'admin' OR p_account_id IS DISTINCT FROM v_account THEN
      RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
    END IF;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS receipt_case_detail_idx ON public.receipt_case (detail_id);

-- ============================================================================================================
-- 1. Resumen de un dia
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.rpc_receipt_day_summary(p_account_id uuid, p_date date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tz text;
  v_ok int;
  v_att int;
  v_fixed int;
  v_comp int;
  v_pend int;
  v_dec int;
  v_inf int;
  v_by jsonb;
BEGIN
  PERFORM public.receipt_mgr_check(p_account_id);
  SELECT COALESCE(a.timezone, 'UTC') INTO v_tz FROM public.accounts a WHERE a.id = p_account_id;
  v_tz := COALESCE(v_tz, 'UTC');

  -- Recibidos ese dia local sin ningun caso (a la primera).
  SELECT count(*) INTO v_ok
    FROM public.allocation_plan_details x
   WHERE x.account_id = p_account_id AND x.status = 'received'
     AND x.received_at >= (p_date::timestamp AT TIME ZONE v_tz) AND x.received_at < ((p_date + 1)::timestamp AT TIME ZONE v_tz)
     AND NOT EXISTS (SELECT 1 FROM public.receipt_case rc WHERE rc.detail_id = x.id AND rc.status IN ('fixed', 'compensated'));

  SELECT COALESCE(sum(rc.attempts), 0),
         count(*) FILTER (WHERE rc.status = 'fixed'),
         count(*) FILTER (WHERE rc.status = 'compensated'),
         count(*) FILTER (WHERE rc.status = 'pending'),
         count(*) FILTER (WHERE rc.status = 'needs_decision'),
         count(*) FILTER (WHERE rc.status = 'informative')
    INTO v_att, v_fixed, v_comp, v_pend, v_dec, v_inf
    FROM public.receipt_case rc
   WHERE rc.account_id = p_account_id
     AND rc.first_attempt_at >= (p_date::timestamp AT TIME ZONE v_tz) AND rc.first_attempt_at < ((p_date + 1)::timestamp AT TIME ZONE v_tz);

  SELECT COALESCE(jsonb_object_agg(r.reason, r.n), '{}'::jsonb) INTO v_by
    FROM (SELECT rc.reason, count(*)::int AS n
            FROM public.receipt_case rc
           WHERE rc.account_id = p_account_id
             AND rc.first_attempt_at >= (p_date::timestamp AT TIME ZONE v_tz) AND rc.first_attempt_at < ((p_date + 1)::timestamp AT TIME ZONE v_tz)
           GROUP BY rc.reason) r;

  RETURN jsonb_build_object(
    'attempts', v_ok + v_att,
    'ok_first_time', v_ok,
    'fixed', v_fixed,
    'compensated', v_comp,
    'pending', v_pend,
    'needs_decision', v_dec,
    'informative', v_inf,
    'by_reason', v_by);
END;
$$;

-- ============================================================================================================
-- 2. Tendencia diaria
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.rpc_receipt_trend(p_account_id uuid, p_days int DEFAULT 30)
RETURNS TABLE(day date, ok_first_time int, fixed int, compensated int, open int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_tz text;
  v_days int := GREATEST(1, LEAST(COALESCE(p_days, 30), 366));
  v_today date;
BEGIN
  PERFORM public.receipt_mgr_check(p_account_id);
  SELECT COALESCE(a.timezone, 'UTC') INTO v_tz FROM public.accounts a WHERE a.id = p_account_id;
  v_tz := COALESCE(v_tz, 'UTC');
  v_today := (now() AT TIME ZONE v_tz)::date;

  RETURN QUERY
  WITH days AS (
    SELECT g::date AS d FROM generate_series(v_today - (v_days - 1), v_today, interval '1 day') g
  ),
  okc AS (
    SELECT (x.received_at AT TIME ZONE v_tz)::date AS d, count(*)::int AS n
      FROM public.allocation_plan_details x
     WHERE x.account_id = p_account_id AND x.status = 'received'
       AND x.received_at >= (v_today - (v_days - 1))::timestamp AT TIME ZONE v_tz - interval '1 day'
       AND NOT EXISTS (SELECT 1 FROM public.receipt_case rc WHERE rc.detail_id = x.id AND rc.status IN ('fixed', 'compensated'))
     GROUP BY 1
  ),
  cs AS (
    SELECT (rc.first_attempt_at AT TIME ZONE v_tz)::date AS d,
           count(*) FILTER (WHERE rc.status = 'fixed')::int AS f,
           count(*) FILTER (WHERE rc.status = 'compensated')::int AS c,
           count(*) FILTER (WHERE rc.status IN ('pending', 'needs_decision'))::int AS o
      FROM public.receipt_case rc
     WHERE rc.account_id = p_account_id
       AND rc.first_attempt_at >= (v_today - (v_days - 1))::timestamp AT TIME ZONE v_tz - interval '1 day'
     GROUP BY 1
  )
  SELECT days.d, COALESCE(okc.n, 0), COALESCE(cs.f, 0), COALESCE(cs.c, 0), COALESCE(cs.o, 0)
    FROM days
    LEFT JOIN okc ON okc.d = days.d
    LEFT JOIN cs ON cs.d = days.d
   ORDER BY days.d;
END;
$$;

-- ============================================================================================================
-- 3. Panelistas reincidentes (culpables de casos en los ultimos 30 dias)
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.rpc_receipt_repeat_panelists(p_account_id uuid)
RETURNS TABLE(panelist_id uuid, name text, panelist_code text, language text, fails_7d int, fails_30d int,
              top_reason text, last_notice_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.receipt_mgr_check(p_account_id);
  RETURN QUERY
  WITH f AS (
    SELECT rc.culprit_panelist_id AS pid,
           (count(*) FILTER (WHERE rc.first_attempt_at >= now() - interval '7 days'))::int AS f7,
           count(*)::int AS f30
      FROM public.receipt_case rc
     WHERE rc.account_id = p_account_id AND rc.culprit_panelist_id IS NOT NULL
       AND rc.status <> 'discarded'
       AND rc.first_attempt_at >= now() - interval '30 days'
     GROUP BY rc.culprit_panelist_id
  ),
  tr AS (
    SELECT DISTINCT ON (z.pid) z.pid, z.reason
      FROM (SELECT rc.culprit_panelist_id AS pid, rc.reason, count(*) AS c
              FROM public.receipt_case rc
             WHERE rc.account_id = p_account_id AND rc.culprit_panelist_id IS NOT NULL
               AND rc.status <> 'discarded'
               AND rc.first_attempt_at >= now() - interval '30 days'
             GROUP BY rc.culprit_panelist_id, rc.reason) z
     ORDER BY z.pid, z.c DESC, z.reason
  ),
  ln AS (
    SELECT n.panelist_id AS pid, max(n.sent_at) AS last_at
      FROM public.panelist_notification n
     WHERE n.account_id = p_account_id AND n.kind IN ('manager_notice', 'receipt_reminder') AND n.status = 'sent'
     GROUP BY n.panelist_id
  )
  SELECT p.id, p.name::text, p.panelist_code::text, p.language::text, f.f7, f.f30, tr.reason, ln.last_at
    FROM f
    JOIN public.panelists p ON p.id = f.pid AND p.account_id = p_account_id
    LEFT JOIN tr ON tr.pid = f.pid
    LEFT JOIN ln ON ln.pid = f.pid
   WHERE f.f30 > 0
   ORDER BY f.f7 DESC, f.f30 DESC, p.name;
END;
$$;

-- ============================================================================================================
-- 4. Lista de casos
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.rpc_receipt_cases(p_account_id uuid, p_status text DEFAULT NULL, p_date date DEFAULT NULL)
RETURNS TABLE(id uuid, panelist_name text, tag_raw text, tag_norm text, reason text, status text, attempts int,
              first_attempt_at timestamptz, detail_id uuid, culprit_name text, culprit_role text,
              resolved_by_name text, resolved_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_tz text;
BEGIN
  PERFORM public.receipt_mgr_check(p_account_id);
  SELECT COALESCE(a.timezone, 'UTC') INTO v_tz FROM public.accounts a WHERE a.id = p_account_id;
  v_tz := COALESCE(v_tz, 'UTC');

  RETURN QUERY
  SELECT rc.id, pa.name::text, rc.tag_raw, rc.tag_norm, rc.reason, rc.status, rc.attempts, rc.first_attempt_at,
         rc.detail_id, cu.name::text, rc.culprit_role, pr.full_name::text, rc.resolved_at
    FROM public.receipt_case rc
    LEFT JOIN public.panelists pa ON pa.id = rc.panelist_id
    LEFT JOIN public.panelists cu ON cu.id = rc.culprit_panelist_id
    LEFT JOIN public.profiles pr ON pr.id = rc.resolved_by
   WHERE rc.account_id = p_account_id
     AND (p_status IS NULL OR rc.status = p_status)
     AND (p_date IS NULL OR (rc.first_attempt_at >= (p_date::timestamp AT TIME ZONE v_tz) AND rc.first_attempt_at < ((p_date + 1)::timestamp AT TIME ZONE v_tz)))
   ORDER BY rc.first_attempt_at DESC, rc.id
   LIMIT 500;
END;
$$;

-- ============================================================================================================
-- 5. Arreglar un caso eligiendo el envio correcto
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.rpc_receipt_case_fix(p_case_id uuid, p_detail_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c public.receipt_case%ROWTYPE;
  d public.allocation_plan_details%ROWTYPE;
  v_recv_node uuid;
  v_recv_name text;
  v_recv_city uuid;
  v_dest_city uuid;
  v_typo boolean := false;
  v_moved boolean := false;
  v_orig_tag text;
  v_res text;
  v_outcome text;
  v_role text;
  v_culprit uuid;
BEGIN
  SELECT * INTO c FROM public.receipt_case WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Caso no encontrado' USING ERRCODE = '22023';
  END IF;
  PERFORM public.receipt_mgr_check(c.account_id);
  IF c.status NOT IN ('needs_decision', 'pending') THEN
    RAISE EXCEPTION 'El caso ya esta cerrado (%)', c.status USING ERRCODE = '22023';
  END IF;

  SELECT * INTO d FROM public.allocation_plan_details x
   WHERE x.id = p_detail_id AND x.account_id = c.account_id FOR UPDATE;
  IF NOT FOUND OR d.status <> 'sent' THEN
    RAISE EXCEPTION 'El envio no existe en esta cuenta o no esta en estado sent' USING ERRCODE = '22023';
  END IF;
  -- Un envio declarado despues del primer intento no puede ser la carta recibida: arreglar nunca anula.
  IF d.sent_at IS NOT NULL AND d.sent_at > c.first_attempt_at THEN
    RAISE EXCEPTION 'El envio se declaro despues de la recepcion (%)', d.sent_at USING ERRCODE = '22023';
  END IF;

  SELECT pa.node_id, pa.name INTO v_recv_node, v_recv_name
    FROM public.panelists pa WHERE pa.id = c.panelist_id AND pa.account_id = c.account_id;
  IF c.panelist_id IS NULL OR v_recv_node IS NULL THEN
    RAISE EXCEPTION 'El caso no tiene un panelista receptor con nodo' USING ERRCODE = '22023';
  END IF;

  SELECT n.city_id INTO v_recv_city FROM public.nodes n WHERE n.id = v_recv_node;
  SELECT n.city_id INTO v_dest_city FROM public.nodes n WHERE n.id = d.destination_node_id;
  IF v_recv_city IS DISTINCT FROM v_dest_city THEN
    RAISE EXCEPTION 'El destino del envio es de otra ciudad que la del receptor' USING ERRCODE = '22023';
  END IF;

  -- Etiqueta: la que declaro el panelista pasa a ser la del envio.
  IF c.tag_norm IS NOT NULL AND d.tag_id IS DISTINCT FROM c.tag_norm THEN
    IF EXISTS (SELECT 1 FROM public.allocation_plan_details x
                WHERE x.account_id = c.account_id AND x.tag_id = c.tag_norm AND x.id <> d.id) THEN
      RAISE EXCEPTION 'Otro envio de la cuenta ya tiene la etiqueta %', c.tag_norm USING ERRCODE = '22023';
    END IF;
    UPDATE public.allocation_plan_details
       SET tag_id = c.tag_norm, idtag = COALESCE(NULLIF(btrim(COALESCE(c.tag_raw, '')), ''), c.tag_norm)
     WHERE id = d.id AND status = 'sent';
    v_typo := true;
    v_orig_tag := d.tag_id;   -- la etiqueta que declaro el remitente
  END IF;
  -- Misma ciudad, otro nodo: el destino pasa al nodo del receptor.
  IF d.destination_node_id <> v_recv_node THEN
    UPDATE public.allocation_plan_details
       SET original_destination_node_id = COALESCE(original_destination_node_id, destination_node_id),
           destination_node_id = v_recv_node,
           destination_panelist_id = c.panelist_id,
           destination_panelist_name = v_recv_name
     WHERE id = d.id AND status = 'sent';
    v_moved := true;
  END IF;

  -- La recepcion cuenta desde el primer intento (y la regla POBOX se evalua con esa fecha).
  v_res := public.register_receipt_with_rules(d.id, c.first_attempt_at, c.panelist_id);
  v_outcome := CASE WHEN v_res <> 'ok' THEN v_res
                    WHEN v_typo THEN 'ok_typo_fixed'
                    WHEN v_moved THEN 'ok_same_city'
                    ELSE 'ok' END;

  SELECT k.culprit_role, k.culprit_panelist_id INTO v_role, v_culprit
    FROM public.receipt_outcome_culprit(v_outcome, d.id, c.panelist_id) k;

  UPDATE public.receipt_case
     SET reason = v_outcome,
         status = public.receipt_outcome_status(v_outcome),
         detail_id = d.id,
         culprit_role = v_role,
         culprit_panelist_id = v_culprit,
         original_tag = COALESCE(v_orig_tag, original_tag),
         resolved_at = now(),
         resolved_by = auth.uid()
   WHERE id = c.id;

  BEGIN
    PERFORM public.enqueue_receipt_reminder(c.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'rpc_receipt_case_fix: no se pudo encolar el recordatorio del caso %: %', c.id, SQLERRM;
  END;

  RETURN v_outcome;
END;
$$;

-- ============================================================================================================
-- 6. Cerrar un caso sin arreglo
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.rpc_receipt_case_close(p_case_id uuid, p_note text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c public.receipt_case%ROWTYPE;
  v_dstatus text;
  v_status text := 'discarded';
BEGIN
  SELECT * INTO c FROM public.receipt_case WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Caso no encontrado' USING ERRCODE = '22023';
  END IF;
  PERFORM public.receipt_mgr_check(c.account_id);
  IF c.status NOT IN ('needs_decision', 'pending') THEN
    RAISE EXCEPTION 'El caso ya esta cerrado (%)', c.status USING ERRCODE = '22023';
  END IF;

  IF c.detail_id IS NOT NULL THEN
    SELECT x.status INTO v_dstatus FROM public.allocation_plan_details x
     WHERE x.id = c.detail_id AND x.account_id = c.account_id;
    IF v_dstatus IN ('sent', 'pending', 'notified') THEN
      IF public.cancel_detail_for_compensation(c.detail_id, 'receipt_before_sent') THEN
        v_status := 'compensated';
      END IF;
    END IF;
  END IF;

  UPDATE public.receipt_case
     SET status = v_status,
         resolution_note = p_note,
         resolved_at = now(),
         resolved_by = auth.uid()
   WHERE id = c.id;
END;
$$;

-- ============================================================================================================
-- 7. Avisos del manager
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.rpc_send_panelist_notice(p_panelist_id uuid, p_body text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account uuid;
  v_status text;
  v_tg text;
  v_id uuid;
BEGIN
  SELECT pa.account_id, pa.status, pa.telegram_id INTO v_account, v_status, v_tg
    FROM public.panelists pa WHERE pa.id = p_panelist_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Panelista no encontrado' USING ERRCODE = '22023';
  END IF;
  PERFORM public.receipt_mgr_check(v_account);
  IF v_status IS DISTINCT FROM 'active' OR btrim(COALESCE(v_tg, '')) !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'El panelista no esta activo o no tiene Telegram' USING ERRCODE = '22023';
  END IF;
  IF p_body IS NULL OR length(btrim(p_body)) < 1 OR length(p_body) > 3000 THEN
    RAISE EXCEPTION 'El texto del aviso debe tener entre 1 y 3000 caracteres' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.panelist_notification (account_id, panelist_id, kind, payload, send_after)
  VALUES (v_account, p_panelist_id, 'manager_notice',
          jsonb_build_object('body', p_body, 'author_user_id', auth.uid()), NULL)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_broadcast_notice(p_account_id uuid, p_bodies jsonb)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bid uuid := gen_random_uuid();
  v_n int;
  k text;
BEGIN
  PERFORM public.receipt_mgr_check(p_account_id);
  IF p_bodies IS NULL OR jsonb_typeof(p_bodies) <> 'object'
     OR COALESCE(length(btrim(p_bodies->>'en')), 0) < 1 THEN
    RAISE EXCEPTION 'Falta el texto en ingles (en)' USING ERRCODE = '22023';
  END IF;
  FOR k IN SELECT jsonb_object_keys(p_bodies) LOOP
    IF jsonb_typeof(p_bodies->k) <> 'string' OR length(p_bodies->>k) > 3000 THEN
      RAISE EXCEPTION 'El texto "%" debe ser una cadena de hasta 3000 caracteres', k USING ERRCODE = '22023';
    END IF;
  END LOOP;

  INSERT INTO public.panelist_notification (account_id, panelist_id, kind, payload, send_after)
  SELECT p.account_id, p.id, 'broadcast',
         jsonb_build_object('body', COALESCE(NULLIF(btrim(p_bodies->>COALESCE(p.language, 'en')), ''), p_bodies->>'en'),
                            'broadcast_id', v_bid, 'body_en', p_bodies->>'en', 'author_user_id', auth.uid()),
         NULL
    FROM public.panelists p
   WHERE p.account_id = p_account_id AND p.status = 'active' AND btrim(p.telegram_id) ~ '^[0-9]+$';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_broadcast_recipients(p_account_id uuid)
RETURNS TABLE(language text, n int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.receipt_mgr_check(p_account_id);
  RETURN QUERY
  SELECT COALESCE(p.language, 'en')::text, count(*)::int
    FROM public.panelists p
   WHERE p.account_id = p_account_id AND p.status = 'active' AND btrim(p.telegram_id) ~ '^[0-9]+$'
   GROUP BY COALESCE(p.language, 'en')
   ORDER BY 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_broadcast_history(p_account_id uuid)
RETURNS TABLE(broadcast_id uuid, created_at timestamptz, body_en text, total int, sent int, failed int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.receipt_mgr_check(p_account_id);
  RETURN QUERY
  SELECT (n.payload->>'broadcast_id')::uuid,
         min(n.created_at),
         max(n.payload->>'body_en'),
         count(*)::int,
         (count(*) FILTER (WHERE n.status = 'sent'))::int,
         (count(*) FILTER (WHERE n.status = 'failed'))::int
    FROM public.panelist_notification n
   WHERE n.account_id = p_account_id AND n.kind = 'broadcast' AND n.payload ? 'broadcast_id'
   GROUP BY n.payload->>'broadcast_id'
   ORDER BY min(n.created_at) DESC;
END;
$$;

-- ============================================================================================================
-- 8. Permisos: authenticated (pantalla) y service_role; nadie anonimo. receipt_mgr_check solo interno.
-- ============================================================================================================
REVOKE EXECUTE ON FUNCTION public.receipt_mgr_check(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.receipt_mgr_check(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_receipt_day_summary(uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_receipt_trend(uuid, int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_receipt_repeat_panelists(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_receipt_cases(uuid, text, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_receipt_case_fix(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_receipt_case_close(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_send_panelist_notice(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_broadcast_notice(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_broadcast_recipients(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rpc_broadcast_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_receipt_day_summary(uuid, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_receipt_trend(uuid, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_receipt_repeat_panelists(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_receipt_cases(uuid, text, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_receipt_case_fix(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_receipt_case_close(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_send_panelist_notice(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_broadcast_notice(uuid, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_broadcast_recipients(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_broadcast_history(uuid) TO authenticated, service_role;
