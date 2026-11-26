-- Agente de analisis de casos R5, tarea 1: paquete ampliado en ops_case._data.
-- Anade al paquete: details[].cancellation_reason, near_tags (etiquetas parecidas por tecleo), expected_for_panelist
-- (envios que el panelista deberia estar esperando) y sender_series (serie reciente de los remitentes implicados).
-- Base: definicion VIVA de ops_case._data (leida de prod el 2026-11-26). Mismos GRANT/REVOKE que la viva
-- (solo el propietario; la llama public.ops_case_data, SECURITY DEFINER).

SET lock_timeout = '5s';

-- Tipo de diferencia entre dos etiquetas normalizadas: 'one_digit' (una cifra distinta, misma longitud),
-- 'swap' (dos cifras adyacentes intercambiadas) o NULL (iguales, longitud distinta, no numericas u otra diferencia).
-- Misma logica cifra a cifra que public.receipt_typo_candidates.
CREATE OR REPLACE FUNCTION ops_case._typo_kind(p_a text, p_b text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE WHEN p_a ~ '^[0-9]+$' AND p_b ~ '^[0-9]+$' AND length(p_a) = length(p_b) AND p_a <> p_b THEN
           (SELECT CASE WHEN count(*) = 1 THEN 'one_digit'
                        WHEN count(*) = 2 AND max(g.i) - min(g.i) = 1
                             AND substr(p_a, min(g.i), 1) = substr(p_b, max(g.i), 1)
                             AND substr(p_a, max(g.i), 1) = substr(p_b, min(g.i), 1) THEN 'swap'
                   END
              FROM generate_series(1, length(p_a)) g(i)
             WHERE substr(p_a, g.i, 1) <> substr(p_b, g.i, 1))
         END;
$$;

CREATE OR REPLACE FUNCTION ops_case._data(p_panelist uuid, p_tag text, p_kind text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_acc uuid; v_tz text; v_today date; v_norm text; v_pan record;
  v_details jsonb; v_detail_ids uuid[]; v_involved uuid[];
  v_anchor jsonb := NULL; v_owner_acc uuid; v_aid uuid;
  v_pnode uuid; v_pcity uuid;
  v_near jsonb; v_near_senders uuid[]; v_expected jsonb; v_exp_senders uuid[]; v_series jsonb;
BEGIN
  SELECT p.account_id INTO v_acc FROM public.panelists p WHERE p.id = p_panelist;
  IF v_acc IS NULL THEN RAISE EXCEPTION 'ops_case: panelista no encontrado'; END IF;
  SELECT a.timezone INTO v_tz FROM public.accounts a WHERE a.id = v_acc;
  v_today := (now() AT TIME ZONE COALESCE(v_tz, 'UTC'))::date;
  v_norm := CASE WHEN btrim(COALESCE(p_tag, '')) = '' THEN NULL ELSE public.normalize_tag(p_tag) END;

  -- Nodo y ciudad del panelista (la ciudad del nodo; si no tiene nodo, la propia del panelista).
  SELECT p.node_id, COALESCE(n.city_id, p.city_id) INTO v_pnode, v_pcity
    FROM public.panelists p LEFT JOIN public.nodes n ON n.id = p.node_id WHERE p.id = p_panelist;

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
      'sent_at', d.sent_at, 'received_at', d.received_at, 'cancellation_reason', d.cancellation_reason,
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

  -- Etiquetas parecidas (una cifra distinta o dos adyacentes intercambiadas), de la cuenta; maximo 20, misma ciudad primero.
  v_near := '[]'::jsonb; v_near_senders := '{}';
  IF v_norm IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'tag', q.tag_id, 'kind', q.kind, 'status', q.status, 'cancellation_reason', q.cancellation_reason,
             'scheduled', q.fecha_programada, 'sent_at', q.sent_at, 'received_at', q.received_at,
             'origin_code', op.panelist_code, 'origin_name', op.name,
             'destination_code', dp.panelist_code, 'destination_name', dp.name,
             'destination_city', btrim(c.name), 'same_city', q.same_city)
             ORDER BY q.same_city DESC, q.sent_at, q.tag_id), '[]'::jsonb),
           COALESCE(array_agg(DISTINCT q.osid) FILTER (WHERE q.same_city AND q.osid IS NOT NULL), '{}')
      INTO v_near, v_near_senders
      FROM (SELECT x.*, ops_case._typo_kind(public.normalize_tag(x.tag_id), v_norm) AS kind,
                   (v_pcity IS NOT NULL AND n.city_id = v_pcity) AS same_city,
                   n.city_id AS dcity,
                   ops_case._side(x.origin_panelist_id, x.origin_node_id, v_acc) AS osid,
                   ops_case._side(x.destination_panelist_id, x.destination_node_id, v_acc) AS dsid
              FROM public.allocation_plan_details x
              LEFT JOIN public.nodes n ON n.id = x.destination_node_id
             WHERE x.account_id = v_acc AND x.tag_id IS NOT NULL
               AND ops_case._typo_kind(public.normalize_tag(x.tag_id), v_norm) IS NOT NULL
             ORDER BY (v_pcity IS NOT NULL AND n.city_id = v_pcity) DESC, x.sent_at, x.tag_id
             LIMIT 20) q
      LEFT JOIN public.panelists op ON op.id = q.osid AND op.account_id = v_acc
      LEFT JOIN public.panelists dp ON dp.id = q.dsid AND dp.account_id = v_acc
      LEFT JOIN public.cities c ON c.id = q.dcity;
  END IF;

  -- Envios que el panelista deberia estar esperando: destino = su nodo (o su ciudad si no tiene nodo), enviados o
  -- anulados por plazo sin recepcion, de los ultimos 45 dias; maximo 30.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'tag', q.tag_id, 'status', q.status, 'cancellation_reason', q.cancellation_reason, 'sent_at', q.sent_at,
           'origin_code', op.panelist_code, 'origin_name', op.name) ORDER BY q.sent_at, q.tag_id), '[]'::jsonb),
         COALESCE(array_agg(DISTINCT q.osid) FILTER (WHERE q.osid IS NOT NULL), '{}')
    INTO v_expected, v_exp_senders
    FROM (SELECT x.*, ops_case._side(x.origin_panelist_id, x.origin_node_id, v_acc) AS osid
            FROM public.allocation_plan_details x
            LEFT JOIN public.nodes n ON n.id = x.destination_node_id
           WHERE x.account_id = v_acc AND x.sent_at IS NOT NULL AND x.sent_at >= now() - interval '45 days'
             AND (x.status = 'sent' OR (x.status = 'cancelled' AND x.cancellation_reason = 'not_received_timeout'
                                        AND x.received_at IS NULL))
             AND ((v_pnode IS NOT NULL AND x.destination_node_id = v_pnode)
                  OR (v_pnode IS NULL AND v_pcity IS NOT NULL AND n.city_id = v_pcity))
           ORDER BY x.sent_at DESC, x.tag_id LIMIT 30) q
    LEFT JOIN public.panelists op ON op.id = q.osid AND op.account_id = v_acc;

  -- Serie de cada remitente implicado (maximo 5, los de envio mas reciente; 30 etiquetas de los ultimos 45 dias).
  SELECT COALESCE(jsonb_agg(jsonb_build_object('origin_code', sp.panelist_code, 'origin_name', sp.name, 'tags', s.tags)
                            ORDER BY s.last_sent DESC), '[]'::jsonb)
    INTO v_series
    FROM (SELECT sd.sender,
                 (SELECT max(y.sent_at) FROM public.allocation_plan_details y
                   WHERE y.account_id = v_acc AND y.sent_at >= now() - interval '45 days'
                     AND ops_case._side(y.origin_panelist_id, y.origin_node_id, v_acc) = sd.sender) AS last_sent,
                 (SELECT COALESCE(jsonb_agg(jsonb_build_object('tag', z.tag_id, 'sent_at', z.sent_at, 'status', z.status,
                                                               'destination_code', zp.panelist_code) ORDER BY z.sent_at, z.tag_id), '[]'::jsonb)
                    FROM (SELECT y.* FROM public.allocation_plan_details y
                           WHERE y.account_id = v_acc AND y.sent_at IS NOT NULL AND y.sent_at >= now() - interval '45 days'
                             AND ops_case._side(y.origin_panelist_id, y.origin_node_id, v_acc) = sd.sender
                           ORDER BY y.sent_at DESC, y.tag_id LIMIT 30) z
                    LEFT JOIN public.panelists zp ON zp.account_id = v_acc
                         AND zp.id = ops_case._side(z.destination_panelist_id, z.destination_node_id, v_acc)) AS tags
            FROM (SELECT DISTINCT u AS sender FROM unnest(v_near_senders || v_exp_senders) u) sd
           ORDER BY 2 DESC NULLS LAST LIMIT 5) s
    JOIN public.panelists sp ON sp.id = s.sender AND sp.account_id = v_acc;

  -- Implicados: el panelista + origen y destino de las lineas + remitentes de etiquetas parecidas de su ciudad.
  SELECT COALESCE(array_agg(DISTINCT x), '{}') INTO v_involved FROM (
    SELECT p_panelist AS x
    UNION SELECT ops_case._side(d.origin_panelist_id, d.origin_node_id, v_acc) FROM public.allocation_plan_details d WHERE d.id = ANY (v_detail_ids)
    UNION SELECT ops_case._side(d.destination_panelist_id, d.destination_node_id, v_acc) FROM public.allocation_plan_details d WHERE d.id = ANY (v_detail_ids)
    UNION SELECT unnest(v_near_senders)) q
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
    'near_tags', v_near,
    'expected_for_panelist', v_expected,
    'sender_series', v_series,
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
END $function$;

REVOKE ALL ON FUNCTION ops_case._typo_kind(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ops_case._data(uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;
