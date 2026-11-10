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
