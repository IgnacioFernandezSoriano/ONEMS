-- ============================================================
-- Agente de analisis de casos (agente de operaciones) — 2026-11-10, Tarea 2
-- ============================================================
-- Solo lectura. El agente las llama con la clave publica (anon) y su token (ops_test._check, hash en
-- ops_test.secret). Una sola llamada devuelve todo lo de UN caso (una etiqueta que fue mal): plan, norma de
-- entrega del producto, realidad, casos de recepcion, incidencias, bajas y conversacion de los implicados.
-- La cuenta sale del panelista; nunca se mezclan cuentas. Errores para el agente: prefijo "ops_case:".
-- Forward-only. NO toca el baseline.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS ops_case;
REVOKE ALL ON SCHEMA ops_case FROM PUBLIC, anon, authenticated;

-- Ficha de un panelista (para origen/destino): null si no hay panelista.
CREATE OR REPLACE FUNCTION ops_case._party(p_id uuid, p_account uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object('panelist_id', p.id, 'code', p.panelist_code, 'name', p.name, 'language', p.language,
                            'city', btrim(c.name), 'node', n.auto_id)
    FROM public.panelists p
    LEFT JOIN public.nodes n ON n.id = p.node_id
    LEFT JOIN public.cities c ON c.id = n.city_id
   WHERE p.id = p_id AND p.account_id = p_account;
$$;

-- Panelista de un lado de la linea: el del detalle; si falta, el activo del nodo (el de menor codigo).
CREATE OR REPLACE FUNCTION ops_case._side(p_panelist uuid, p_node uuid, p_account uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE((SELECT p.id FROM public.panelists p WHERE p.id = p_panelist AND p.account_id = p_account),
           (SELECT p.id FROM public.panelists p
             WHERE p.node_id = p_node AND p.account_id = p_account AND p.status = 'active'
             ORDER BY p.panelist_code LIMIT 1));
$$;

-- ===== Buscar panelistas por nombre y/o etiqueta (todas las cuentas: el agente no sabe la cuenta) =====
CREATE OR REPLACE FUNCTION ops_case._find(p_name text, p_tag text)
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
     WHERE p.status = 'active'),
  sel AS (SELECT * FROM cand
           WHERE CASE WHEN EXISTS (SELECT 1 FROM cand c2 WHERE c2.by_name) THEN by_name ELSE by_tag END
           ORDER BY (by_name AND by_tag) DESC, by_name DESC, panelist_code LIMIT 10)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('panelist_id', s.id, 'code', s.panelist_code, 'name', s.name,
           'account', s.account, 'city', s.city, 'by_name', s.by_name, 'by_tag', s.by_tag)
           ORDER BY (s.by_name AND s.by_tag) DESC, s.by_name DESC, s.panelist_code), '[]'::jsonb)
    INTO v_out FROM sel s;
  RETURN v_out;
END $$;

-- ===== Todo lo de un caso =====
CREATE OR REPLACE FUNCTION ops_case._data(p_panelist uuid, p_tag text, p_kind text, p_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_acc uuid; v_tz text; v_today date; v_norm text; v_pan record;
  v_details jsonb; v_detail_ids uuid[]; v_involved uuid[];
  v_anchor jsonb := NULL; v_owner_acc uuid; v_aid uuid;
BEGIN
  SELECT p.account_id INTO v_acc FROM public.panelists p WHERE p.id = p_panelist;
  IF v_acc IS NULL THEN RAISE EXCEPTION 'ops_case: panelista no encontrado'; END IF;
  SELECT a.timezone INTO v_tz FROM public.accounts a WHERE a.id = v_acc;
  v_today := (now() AT TIME ZONE COALESCE(v_tz, 'UTC'))::date;
  v_norm := CASE WHEN btrim(COALESCE(p_tag, '')) = '' THEN NULL ELSE public.normalize_tag(p_tag) END;

  IF (p_kind IS NULL) <> (p_id IS NULL) THEN RAISE EXCEPTION 'ops_case: incidencia no valida'; END IF;
  IF p_id IS NOT NULL THEN
    SELECT o.account_id INTO v_owner_acc FROM public.incident_owner(p_kind, p_id) o;
    IF v_owner_acc IS NULL THEN RAISE EXCEPTION 'ops_case: incidencia no encontrada'; END IF;
    IF v_owner_acc <> v_acc THEN RAISE EXCEPTION 'ops_case: otra cuenta'; END IF;
    v_anchor := jsonb_build_object('kind', p_kind, 'id', p_id);
  END IF;

  -- Lineas del plan con esa etiqueta (y su norma de entrega: carrier + producto del plan, ciudades de origen y destino).
  IF v_norm IS NOT NULL THEN
    SELECT COALESCE(array_agg(d.id), '{}') INTO v_detail_ids FROM public.allocation_plan_details d
     WHERE d.account_id = v_acc AND d.tag_id IS NOT NULL AND public.normalize_tag(d.tag_id) = v_norm;
  ELSE
    v_detail_ids := '{}';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', d.id, 'tag', d.tag_id, 'status', d.status, 'scheduled', d.fecha_programada,
      'sent_at', d.sent_at, 'received_at', d.received_at,
      'origin', ops_case._party(ops_case._side(d.origin_panelist_id, d.origin_node_id, v_acc), v_acc),
      'destination', ops_case._party(ops_case._side(d.destination_panelist_id, d.destination_node_id, v_acc), v_acc),
      'carrier', ca.name, 'product', pr.description, 'product_code', pr.code,
      'standards', (SELECT COALESCE(jsonb_agg(jsonb_build_object('standard_time', s.standard_time, 'time_unit', s.time_unit,
                                                                  'success_percentage', s.success_percentage)
                                              ORDER BY s.standard_time), '[]'::jsonb)
                      FROM public.delivery_standards s
                     WHERE s.account_id = v_acc AND s.carrier_id = ap.carrier_id AND s.product_id = ap.product_id
                       AND s.origin_city_id = no.city_id AND s.destination_city_id = nd.city_id)
    ) ORDER BY d.fecha_programada, d.id), '[]'::jsonb)
    INTO v_details
    FROM public.allocation_plan_details d
    LEFT JOIN public.allocation_plans ap ON ap.id = d.plan_id AND ap.account_id = v_acc
    LEFT JOIN public.carriers ca ON ca.id = ap.carrier_id AND ca.account_id = v_acc
    LEFT JOIN public.products pr ON pr.id = ap.product_id AND pr.account_id = v_acc
    LEFT JOIN public.nodes no ON no.id = d.origin_node_id
    LEFT JOIN public.nodes nd ON nd.id = d.destination_node_id
   WHERE d.id = ANY (v_detail_ids);

  -- Implicados: el panelista + origen y destino de las lineas.
  SELECT COALESCE(array_agg(DISTINCT x), '{}') INTO v_involved FROM (
    SELECT p_panelist AS x
    UNION SELECT ops_case._side(d.origin_panelist_id, d.origin_node_id, v_acc) FROM public.allocation_plan_details d WHERE d.id = ANY (v_detail_ids)
    UNION SELECT ops_case._side(d.destination_panelist_id, d.destination_node_id, v_acc) FROM public.allocation_plan_details d WHERE d.id = ANY (v_detail_ids)) q
   WHERE x IS NOT NULL;

  -- Ancla por defecto: caso de recepcion abierto del panelista con la etiqueta; luego incidencia abierta ligada a la linea.
  IF v_anchor IS NULL THEN
    SELECT r.id INTO v_aid FROM public.receipt_case r
     WHERE r.account_id = v_acc AND r.panelist_id = p_panelist AND v_norm IS NOT NULL AND r.tag_norm = v_norm
       AND r.status IN ('pending', 'needs_decision')
     ORDER BY r.last_attempt_at DESC LIMIT 1;
    IF v_aid IS NOT NULL THEN
      v_anchor := jsonb_build_object('kind', 'receipt', 'id', v_aid);
    ELSE
      SELECT i.id INTO v_aid FROM public.panelist_incident i
       WHERE i.account_id = v_acc AND i.status IN ('open', 'in_progress') AND i.allocation_plan_detail_id = ANY (v_detail_ids)
       ORDER BY i.reported_at DESC LIMIT 1;
      IF v_aid IS NOT NULL THEN v_anchor := jsonb_build_object('kind', 'reported', 'id', v_aid); END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'account', (SELECT jsonb_build_object('name', a.name, 'language', a.default_language, 'timezone', a.timezone)
                  FROM public.accounts a WHERE a.id = v_acc),
    'panelist', (SELECT jsonb_build_object('id', p.id, 'code', p.panelist_code, 'name', p.name, 'language', p.language,
                         'city', btrim(c.name), 'node', n.auto_id, 'has_telegram', btrim(COALESCE(p.telegram_id, '')) <> '')
                   FROM public.panelists p
                   LEFT JOIN public.nodes n ON n.id = p.node_id
                   LEFT JOIN public.cities c ON c.id = n.city_id
                  WHERE p.id = p_panelist),
    'details', v_details,
    'siblings', (SELECT COALESCE(jsonb_agg(jsonb_build_object('tag', s.tag_id, 'scheduled', s.fecha_programada,
                           'sent_at', s.sent_at, 'received_at', s.received_at, 'status', s.status,
                           'destination_code', dp.panelist_code, 'destination_name', dp.name)
                           ORDER BY s.fecha_programada, s.tag_id), '[]'::jsonb)
                   FROM (SELECT x.* FROM public.allocation_plan_details x
                          WHERE x.account_id = v_acc AND NOT (x.id = ANY (v_detail_ids))
                            AND EXISTS (SELECT 1 FROM public.allocation_plan_details d WHERE d.id = ANY (v_detail_ids) AND d.origin_node_id = x.origin_node_id
                                          AND date_trunc('month', d.fecha_programada) = date_trunc('month', x.fecha_programada))
                          ORDER BY x.fecha_programada, x.tag_id LIMIT 30) s
                   LEFT JOIN public.panelists dp ON dp.account_id = v_acc AND dp.id = ops_case._side(s.destination_panelist_id, s.destination_node_id, v_acc)),
    'receipt_cases', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', q.id, 'tag_raw', q.tag_raw, 'tag_norm', q.tag_norm,
                           'reason', q.reason, 'status', q.status, 'attempts', q.attempts,
                           'first_attempt_at', q.first_attempt_at, 'last_attempt_at', q.last_attempt_at,
                           'panelist_code', pp.panelist_code, 'culprit_role', q.culprit_role)
                           ORDER BY q.last_attempt_at DESC), '[]'::jsonb)
                        FROM (SELECT r.* FROM public.receipt_case r
                               WHERE r.account_id = v_acc
                                 AND ((v_norm IS NOT NULL AND r.tag_norm = v_norm)
                                      OR (r.panelist_id = p_panelist AND r.last_attempt_at >= now() - interval '30 days'))
                               ORDER BY r.last_attempt_at DESC LIMIT 20) q
                        LEFT JOIN public.panelists pp ON pp.id = q.panelist_id AND pp.account_id = v_acc),
    'incidents', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', q.id, 'panelist_code', pp.panelist_code,
                           'category', q.category, 'status', q.status, 'reported_at', q.reported_at,
                           'description', q.description) ORDER BY q.reported_at DESC), '[]'::jsonb)
                    FROM (SELECT i.* FROM public.panelist_incident i
                           WHERE i.account_id = v_acc AND i.panelist_id = ANY (v_involved)
                             AND i.reported_at >= now() - interval '30 days'
                           ORDER BY i.reported_at DESC LIMIT 20) q
                    JOIN public.panelists pp ON pp.id = q.panelist_id AND pp.account_id = v_acc),
    'unavailability', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', u.id, 'panelist_code', pp.panelist_code,
                           'start_date', u.start_date, 'end_date', u.end_date, 'reason', u.reason,
                           'review_status', u.review_status) ORDER BY u.start_date), '[]'::jsonb)
                         FROM public.panelist_unavailability u
                         JOIN public.panelists pp ON pp.id = u.panelist_id AND pp.account_id = v_acc
                        WHERE u.account_id = v_acc AND u.status = 'active' AND u.panelist_id = ANY (v_involved)
                          AND u.start_date <= v_today + 30 AND u.end_date >= v_today - 30),
    'messages', (SELECT COALESCE(jsonb_agg(jsonb_build_object('incident_kind', q.incident_kind, 'incident_id', q.incident_id,
                           'panelist_code', pp.panelist_code, 'direction', q.direction, 'author', q.author,
                           'body', q.body, 'created_at', q.created_at) ORDER BY q.created_at DESC), '[]'::jsonb)
                   FROM (SELECT m.* FROM public.incident_message m
                          WHERE m.account_id = v_acc AND m.panelist_id = ANY (v_involved)
                          ORDER BY m.created_at DESC LIMIT 20) q
                   JOIN public.panelists pp ON pp.id = q.panelist_id AND pp.account_id = v_acc),
    'anchor', v_anchor
  );
END $$;

-- ===== Publicas (anon + token) =====
CREATE OR REPLACE FUNCTION public.ops_case_find_panelists(p_token text, p_name text, p_tag text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM ops_test._check(p_token);
  RETURN ops_case._find(p_name, p_tag);
END $$;

CREATE OR REPLACE FUNCTION public.ops_case_data(p_token text, p_panelist_id uuid, p_tag text,
                                                p_incident_kind text DEFAULT NULL, p_incident_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM ops_test._check(p_token);
  RETURN ops_case._data(p_panelist_id, p_tag, p_incident_kind, p_incident_id);
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ops_case FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_case_find_panelists(text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_case_data(text, uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_case_find_panelists(text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_case_data(text, uuid, text, text, uuid) TO anon;

-- ============================================================
-- Tarea 3: cola de peticiones desde ONEMS + envio y notas del agente
-- ============================================================
CREATE TABLE public.case_analysis_request (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  requested_by  uuid,
  incident_kind text NOT NULL CHECK (incident_kind IN ('reported','unavailability','receipt')),
  incident_id   uuid NOT NULL,
  status        text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','done','failed')),
  result        jsonb,
  error         text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  started_at    timestamptz,
  finished_at   timestamptz
);
CREATE INDEX case_analysis_request_queue_idx ON public.case_analysis_request (created_at) WHERE status = 'queued';
CREATE INDEX case_analysis_request_incident_idx ON public.case_analysis_request (incident_kind, incident_id, created_at DESC);
ALTER TABLE public.case_analysis_request ENABLE ROW LEVEL SECURITY;
CREATE POLICY case_analysis_request_select ON public.case_analysis_request
  FOR SELECT TO authenticated
  USING (public.is_superadmin()
          OR (incident_kind <> 'receipt' AND account_id = public.current_user_account_id())
          OR (incident_kind = 'receipt' AND EXISTS (SELECT 1 FROM public.profiles pr
                WHERE pr.id = auth.uid() AND pr.role = 'admin' AND pr.account_id = case_analysis_request.account_id)));
REVOKE ALL ON public.case_analysis_request FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.case_analysis_request TO authenticated;

-- ===== Puerta por cuenta =====
-- Cuentas con análisis de casos desde ONEMS. Ampliar = migración nueva aprobada por Ignacio (igual que case.send_accounts del agente).
CREATE OR REPLACE FUNCTION public.case_analysis_allowed(p_account uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_allowed text[] := ARRAY['DEMO2'];
BEGIN
  IF p_account IS NULL THEN RETURN false; END IF;
  IF '*' = ANY (v_allowed) THEN RETURN true; END IF;
  RETURN EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = p_account AND a.name = ANY (v_allowed));
END $$;
REVOKE ALL ON FUNCTION public.case_analysis_allowed(uuid) FROM PUBLIC, anon, authenticated;

-- La pantalla la consulta una vez para mostrar u ocultar el análisis (la cuenta del propio usuario).
CREATE OR REPLACE FUNCTION public.case_analysis_enabled()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.case_analysis_allowed(public.current_user_account_id());
$$;
REVOKE ALL ON FUNCTION public.case_analysis_enabled() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.case_analysis_enabled() TO authenticated;

-- ===== ONEMS (authenticated): pedir y consultar =====
CREATE OR REPLACE FUNCTION public.request_case_analysis(p_incident_kind text, p_incident_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_account uuid; v_id uuid;
BEGIN
  IF p_incident_kind IS NULL OR p_incident_kind NOT IN ('reported','unavailability','receipt') THEN
    RAISE EXCEPTION 'invalid incident kind'; END IF;
  SELECT o.account_id INTO v_account FROM public.incident_owner(p_incident_kind, p_incident_id) o;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM public.assert_same_account(v_account);
  IF p_incident_kind = 'receipt' THEN PERFORM public.receipt_mgr_check(v_account); END IF;
  IF NOT public.case_analysis_allowed(v_account) THEN
    RAISE EXCEPTION 'case analysis not enabled for this account' USING ERRCODE = '42501'; END IF;
  -- evita dos peticiones a la vez para la misma incidencia
  PERFORM pg_advisory_xact_lock(hashtextextended(p_incident_kind || ':' || p_incident_id::text, 0));
  SELECT r.id INTO v_id FROM public.case_analysis_request r
   WHERE r.incident_kind = p_incident_kind AND r.incident_id = p_incident_id
     AND r.status IN ('queued','running') AND r.created_at > now() - interval '10 minutes'
   ORDER BY r.created_at DESC LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO public.case_analysis_request (account_id, requested_by, incident_kind, incident_id)
  VALUES (v_account, auth.uid(), p_incident_kind, p_incident_id) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.case_analysis_status(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE r public.case_analysis_request;
BEGIN
  SELECT * INTO r FROM public.case_analysis_request WHERE id = p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'request not found'; END IF;
  PERFORM public.assert_same_account(r.account_id);
  IF r.incident_kind = 'receipt' THEN PERFORM public.receipt_mgr_check(r.account_id); END IF;
  -- UPDATE condicionado: nunca pisa una peticion que acaba de terminar
  UPDATE public.case_analysis_request SET status = 'failed', error = 'agent_timeout', finished_at = now()
   WHERE id = r.id AND status IN ('queued','running') AND created_at < now() - interval '10 minutes';
  SELECT * INTO r FROM public.case_analysis_request WHERE id = p_request_id;
  RETURN jsonb_build_object('status', r.status, 'result', r.result, 'error', r.error);
END $$;

-- ===== Agente (anon + token) =====
CREATE OR REPLACE FUNCTION public.ops_case_claim(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE r public.case_analysis_request; v_panelist uuid; v_tag text;
BEGIN
  PERFORM ops_test._check(p_token);
  -- caducan las peticiones sin atender (agente caido) y las abandonadas en running
  UPDATE public.case_analysis_request SET status = 'failed', error = 'agent_timeout', finished_at = now()
   WHERE status IN ('queued','running') AND created_at < now() - interval '10 minutes';
  -- retencion: las terminadas se borran a los 30 dias (misma regla que el agente)
  DELETE FROM public.case_analysis_request
   WHERE status IN ('done','failed') AND created_at < now() - interval '30 days';
  -- solo se reclama lo que tiene al menos 2 minutos antes de caducar (a los 10)
  SELECT * INTO r FROM public.case_analysis_request
   WHERE status = 'queued' AND created_at > now() - interval '8 minutes'
   ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
  UPDATE public.case_analysis_request SET status = 'running', started_at = now() WHERE id = r.id;
  SELECT o.panelist_id INTO v_panelist FROM public.incident_owner(r.incident_kind, r.incident_id) o;
  v_tag := CASE r.incident_kind
    WHEN 'receipt' THEN (SELECT c.tag_norm FROM public.receipt_case c WHERE c.id = r.incident_id)
    WHEN 'reported' THEN (SELECT public.normalize_tag(d.tag_id) FROM public.panelist_incident i
                            JOIN public.allocation_plan_details d ON d.id = i.allocation_plan_detail_id
                           WHERE i.id = r.incident_id AND d.tag_id IS NOT NULL)
    ELSE NULL END;
  RETURN jsonb_build_object('request_id', r.id,
    'account', (SELECT a.name FROM public.accounts a WHERE a.id = r.account_id),
    'incident_kind', r.incident_kind, 'incident_id', r.incident_id,
    'panelist_id', v_panelist, 'tag', v_tag);
END $$;

-- Inserta una nota interna del sistema en la incidencia (cuenta y panelista salen de la incidencia).
CREATE OR REPLACE FUNCTION ops_case._note(p_kind text, p_id uuid, p_body text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_account uuid; v_panelist uuid; v_new uuid;
BEGIN
  IF p_body IS NULL OR btrim(p_body) = '' THEN RAISE EXCEPTION 'ops_case: texto vacio'; END IF;
  SELECT o.account_id, o.panelist_id INTO v_account, v_panelist FROM public.incident_owner(p_kind, p_id) o;
  IF v_account IS NULL OR v_panelist IS NULL THEN RAISE EXCEPTION 'ops_case: incidencia no encontrada'; END IF;
  INSERT INTO public.incident_message (account_id, panelist_id, incident_kind, incident_id, direction, author, body, status)
  VALUES (v_account, v_panelist, p_kind, p_id, 'internal', 'system', p_body, 'sent') RETURNING id INTO v_new;
  RETURN v_new;
END $$;

CREATE OR REPLACE FUNCTION public.ops_case_finish(p_token text, p_request_id uuid, p_result jsonb, p_note text, p_error text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE r public.case_analysis_request;
BEGIN
  PERFORM ops_test._check(p_token);
  SELECT * INTO r FROM public.case_analysis_request WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ops_case: peticion no encontrada'; END IF;
  -- solo se cierra una peticion viva: un reintento o un cierre tardio no hace nada
  IF r.status NOT IN ('queued','running') THEN RETURN; END IF;
  UPDATE public.case_analysis_request
     SET status = CASE WHEN COALESCE(btrim(p_error), '') <> '' THEN 'failed' ELSE 'done' END,
         result = p_result, error = NULLIF(btrim(COALESCE(p_error, '')), ''), finished_at = now()
   WHERE id = r.id;
  -- sin panelista en la incidencia no hay donde colgar la nota: se omite
  IF btrim(COALESCE(p_note, '')) <> ''
     AND (SELECT o.panelist_id FROM public.incident_owner(r.incident_kind, r.incident_id) o) IS NOT NULL THEN
    PERFORM ops_case._note(r.incident_kind, r.incident_id, p_note);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.ops_case_note(p_token text, p_incident_kind text, p_incident_id uuid, p_body text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM ops_test._check(p_token);
  RETURN ops_case._note(p_incident_kind, p_incident_id, p_body);
END $$;

CREATE OR REPLACE FUNCTION public.ops_case_send(p_token text, p_incident_kind text, p_incident_id uuid,
    p_panelist_id uuid, p_body text, p_draft_key text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_pan_acc uuid; v_status text; v_tg text; v_inc_acc uuid; v_id uuid;
BEGIN
  PERFORM ops_test._check(p_token);
  IF p_body IS NULL OR length(btrim(p_body)) < 1 OR length(p_body) > 900 THEN
    RAISE EXCEPTION 'ops_case: el texto debe tener entre 1 y 900 caracteres'; END IF;
  IF btrim(COALESCE(p_draft_key, '')) = '' THEN RAISE EXCEPTION 'ops_case: falta draft_key'; END IF;
  IF (p_incident_kind IS NULL) <> (p_incident_id IS NULL) THEN RAISE EXCEPTION 'ops_case: incidencia no valida'; END IF;
  SELECT pa.account_id, pa.status, pa.telegram_id INTO v_pan_acc, v_status, v_tg
    FROM public.panelists pa WHERE pa.id = p_panelist_id;
  IF v_pan_acc IS NULL THEN RAISE EXCEPTION 'ops_case: panelista no encontrado'; END IF;
  IF p_incident_id IS NOT NULL THEN
    SELECT o.account_id INTO v_inc_acc FROM public.incident_owner(p_incident_kind, p_incident_id) o;
    IF v_inc_acc IS NULL THEN RAISE EXCEPTION 'ops_case: incidencia no encontrada'; END IF;
    IF v_inc_acc <> v_pan_acc THEN RAISE EXCEPTION 'ops_case: otra cuenta'; END IF;
  END IF;
  -- una misma draft_key se envia una sola vez (reintentos y doble pulsacion). El dedupe es solo por clave
  -- (las claves llevan prefijo UUID) y va ANTES de las comprobaciones de estado: un reintento devuelve el id existente.
  PERFORM pg_advisory_xact_lock(hashtextextended('ops_case_send:' || p_draft_key, 0));
  IF p_incident_id IS NOT NULL THEN
    SELECT m.id INTO v_id FROM public.incident_message m WHERE m.meta->>'case_draft_key' = p_draft_key;
  ELSE
    SELECT n.id INTO v_id FROM public.panelist_notification n
     WHERE n.account_id = v_pan_acc AND n.kind = 'manager_notice' AND n.payload->>'case_draft_key' = p_draft_key;
  END IF;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  IF v_status IS DISTINCT FROM 'active' OR btrim(COALESCE(v_tg, '')) !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'ops_case: el panelista no esta activo o no tiene Telegram'; END IF;
  IF p_incident_id IS NOT NULL THEN
    INSERT INTO public.incident_message (account_id, panelist_id, incident_kind, incident_id, direction, author, body, meta, status)
    VALUES (v_pan_acc, p_panelist_id, p_incident_kind, p_incident_id, 'outbound', 'manager', p_body,
            jsonb_build_object('manager_user_id', NULL, 'via', 'ops_agent', 'case_draft_key', p_draft_key), 'pending_send')
    RETURNING id INTO v_id;
  ELSE
    INSERT INTO public.panelist_notification (account_id, panelist_id, kind, payload, send_after)
    VALUES (v_pan_acc, p_panelist_id, 'manager_notice',
            jsonb_build_object('body', p_body, 'via', 'ops_agent', 'case_draft_key', p_draft_key), NULL)
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ops_case FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.request_case_analysis(text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.case_analysis_status(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_case_claim(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_case_finish(text, uuid, jsonb, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_case_note(text, text, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_case_send(text, text, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.request_case_analysis(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.case_analysis_status(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ops_case_claim(text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_case_finish(text, uuid, jsonb, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_case_note(text, text, uuid, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_case_send(text, text, uuid, uuid, text, text) TO anon;

-- ===== send_case_message con la misma puerta (solo lo usa el panel de análisis) =====
CREATE OR REPLACE FUNCTION public.send_case_message(
  p_incident_kind text, p_incident_id uuid, p_panelist_id uuid, p_body text, p_draft_key text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid; v_new uuid;
BEGIN
  IF p_incident_kind NOT IN ('reported','unavailability','receipt') THEN
    RAISE EXCEPTION 'invalid incident kind'; END IF;
  SELECT o.account_id INTO v_account FROM public.incident_owner(p_incident_kind, p_incident_id) o;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM assert_same_account(v_account);
  -- la pantalla de errores de recepcion es solo para admins de la cuenta
  IF p_incident_kind = 'receipt' THEN PERFORM public.receipt_mgr_check(v_account); END IF;
  IF NOT public.case_analysis_allowed(v_account) THEN
    RAISE EXCEPTION 'case analysis not enabled for this account' USING ERRCODE = '42501'; END IF;
  IF p_panelist_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM panelists WHERE id = p_panelist_id AND account_id = v_account) THEN
    RAISE EXCEPTION 'Cross-tenant access denied'; END IF;
  IF NULLIF(btrim(p_body), '') IS NULL THEN RAISE EXCEPTION 'empty message'; END IF;
  -- mismo limite que rpc_send_manager_notice y el textarea
  IF length(p_body) > 3000 THEN RAISE EXCEPTION 'message too long'; END IF;
  -- misma regla que ops_case_send: panelista activo con id de Telegram numerico
  IF NOT EXISTS (SELECT 1 FROM panelists WHERE id = p_panelist_id AND status = 'active') THEN
    RAISE EXCEPTION 'panelist not active'; END IF;
  IF NOT EXISTS (SELECT 1 FROM panelists WHERE id = p_panelist_id AND btrim(COALESCE(telegram_id, '')) ~ '^[0-9]+$') THEN
    RAISE EXCEPTION 'panelist has no telegram'; END IF;
  INSERT INTO incident_message (account_id, panelist_id, incident_kind, incident_id,
                                direction, author, body, meta, status)
  VALUES (v_account, p_panelist_id, p_incident_kind, p_incident_id,
          'outbound', 'manager', btrim(p_body),
          jsonb_build_object('manager_user_id', auth.uid(), 'case_draft_key', p_draft_key), 'pending_send')
  RETURNING id INTO v_new;
  RETURN v_new;
END; $$;
REVOKE ALL ON FUNCTION public.send_case_message(text,uuid,uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_case_message(text,uuid,uuid,text,text) TO authenticated;
