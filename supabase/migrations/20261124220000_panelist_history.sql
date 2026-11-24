-- Historial del panelista (spec docs/superpowers/specs/2026-11-24-historial-panelista-design.md, 24/11).
--  * panelist_note: notas del gestor sobre un panelista (solo por las funciones de abajo).
--  * panelist_history: todo lo que ha pasado con el panelista, ordenado por fecha, + cabecera y cifras.
--  * panelist_note_add / panelist_note_delete.
-- Ver = has_access(cuenta, 'panelists', 'view'); escribir = 'edit' (decision de Ignacio 24/11). Solo authenticated.
-- Nunca coordenadas en la respuesta; nunca datos de otra cuenta.

CREATE TABLE IF NOT EXISTS public.panelist_note (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id  uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  panelist_id uuid NOT NULL REFERENCES public.panelists(id) ON DELETE CASCADE,
  body        text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 2000),
  created_by  uuid NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS panelist_note_panelist_idx ON public.panelist_note (panelist_id, created_at DESC);
ALTER TABLE public.panelist_note ENABLE ROW LEVEL SECURITY;   -- sin politicas: solo por las funciones
REVOKE ALL ON public.panelist_note FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------------ historial
CREATE OR REPLACE FUNCTION public.panelist_history(p_panelist_id uuid, p_before timestamptz DEFAULT NULL,
                                                   p_before_id uuid DEFAULT NULL, p_limit int DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_p panelists; v_tz text; v_today date;
  v_lim int := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_uid uuid := auth.uid(); v_super boolean := public.is_superadmin();
  v_rows jsonb; v_n int; v_last jsonb; v_head jsonb; v_stats jsonb;
BEGIN
  SELECT * INTO v_p FROM panelists WHERE id = p_panelist_id;
  IF NOT FOUND OR NOT public.has_access(v_p.account_id, 'panelists', 'view') THEN
    RAISE EXCEPTION 'not allowed' USING ERRCODE = '42501';
  END IF;
  SELECT a.timezone INTO v_tz FROM accounts a WHERE a.id = v_p.account_id;
  v_today := (now() AT TIME ZONE COALESCE(v_tz, 'UTC'))::date;

  WITH ev AS (
    SELECT n.id, n.created_at AS at, 'note'::text AS type, NULL::text AS subtype, NULL::text AS status,
           jsonb_build_object('body', n.body, 'author', COALESCE(pr.full_name, pr.email),
                              'can_delete', (n.created_by = v_uid OR v_super)) AS data,
           NULL::jsonb AS link
      FROM panelist_note n LEFT JOIN profiles pr ON pr.id = n.created_by
     WHERE n.panelist_id = p_panelist_id AND n.account_id = v_p.account_id
    UNION ALL
    SELECT i.id, COALESCE(i.reported_at, i.created_at),
           CASE WHEN i.category = 'gps_location' AND i.payload->>'reason' = 'wrong_place' THEN 'gps' ELSE 'incident' END,
           i.category, i.status,
           CASE WHEN i.category = 'gps_location' AND i.payload->>'reason' = 'wrong_place'
                THEN jsonb_build_object('place_kind', i.payload->>'place_kind')
                ELSE jsonb_build_object('category', i.category, 'description', left(i.description, 200)) END,
           jsonb_build_object('screen', 'reported', 'id', i.id)
      FROM panelist_incident i
     WHERE i.panelist_id = p_panelist_id AND i.account_id = v_p.account_id
    UNION ALL
    SELECT r.id, COALESCE(r.first_attempt_at, r.created_at), 'receipt', r.reason, r.status,
           jsonb_build_object('reason', r.reason, 'tag', COALESCE(r.tag_norm, r.tag_raw),
                              'role', CASE WHEN r.panelist_id = p_panelist_id THEN 'receiver' ELSE 'sender' END),
           jsonb_build_object('screen', 'receipts', 'id', r.id)
      FROM receipt_case r
     WHERE r.account_id = v_p.account_id AND r.reason NOT IN ('ok', 'ok_same_city')
       AND (r.panelist_id = p_panelist_id OR (r.culprit_panelist_id = p_panelist_id AND r.culprit_role = 'sender'))
    UNION ALL
    SELECT u.id, u.created_at, 'leave', u.reason::text, u.status::text,
           jsonb_build_object('start', u.start_date, 'end', u.end_date, 'reason', u.reason,
                              'review_status', u.review_status),
           jsonb_build_object('screen', 'availability', 'id', u.id)
      FROM panelist_unavailability u
     WHERE u.panelist_id = p_panelist_id AND u.account_id = v_p.account_id
    UNION ALL
    SELECT nt.id, nt.created_at, 'notice', NULL, NULL, jsonb_build_object('body', nt.payload->>'body'), NULL
      FROM panelist_notification nt
     WHERE nt.panelist_id = p_panelist_id AND nt.account_id = v_p.account_id AND nt.kind = 'manager_notice'
    UNION ALL
    -- referencias de apartado/casa: nunca las coordenadas
    SELECT l.id, l.created_at, 'gps_ref', l.kind, CASE WHEN l.active THEN 'active' ELSE 'inactive' END,
           jsonb_build_object('kind', l.kind, 'source', l.source, 'needs_review', l.needs_review,
                              'review_reason', l.review_reason),
           NULL
      FROM panelist_location_reference l
     WHERE l.panelist_id = p_panelist_id AND l.account_id = v_p.account_id AND (l.active OR l.source = 'declined')
  ), page AS (
    SELECT * FROM ev
     WHERE p_before IS NULL
        OR (p_before_id IS NULL AND ev.at < p_before)
        OR (p_before_id IS NOT NULL AND (ev.at, ev.id) < (p_before, p_before_id))
     ORDER BY ev.at DESC, ev.id DESC
     LIMIT v_lim + 1
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', page.id, 'at', page.at, 'type', page.type, 'subtype', page.subtype,
                                               'status', page.status, 'data', page.data, 'link', page.link)
                            ORDER BY page.at DESC, page.id DESC), '[]'::jsonb)
    INTO v_rows FROM page;

  v_n := jsonb_array_length(v_rows);
  IF v_n > v_lim THEN
    v_rows := v_rows - v_lim;                         -- quita el de sobra (indice v_lim, base 0)
    v_last := v_rows -> (v_lim - 1);
  END IF;

  SELECT jsonb_build_object('id', v_p.id, 'code', v_p.panelist_code, 'name', v_p.name, 'mobile', v_p.mobile,
           'city', btrim(c.name), 'node', n.auto_id,
           'pobox', COALESCE((SELECT e.pobox_enabled FROM public.effective_city_policy(c.id) e), false),
           'created', (v_p.created_at AT TIME ZONE COALESCE(v_tz, 'UTC'))::date, 'status', v_p.status,
           'language', v_p.language)
    INTO v_head
    FROM (SELECT 1) one LEFT JOIN nodes n ON n.id = v_p.node_id LEFT JOIN cities c ON c.id = n.city_id;

  v_stats := jsonb_build_object(
    'sent_30d', (SELECT count(*) FROM allocation_plan_details d
                  WHERE d.account_id = v_p.account_id AND d.sent_at > now() - interval '30 days'
                    AND (d.origin_panelist_id = v_p.id OR (d.origin_panelist_id IS NULL AND d.origin_node_id = v_p.node_id))),
    'scheduled_30d', (SELECT count(*) FROM allocation_plan_details d
                       WHERE d.account_id = v_p.account_id AND d.origin_node_id = v_p.node_id
                         AND d.status <> 'cancelled' AND d.fecha_programada BETWEEN v_today - 30 AND v_today),
    'receipt_problems_30d', (SELECT count(*) FROM receipt_case r
                              WHERE r.account_id = v_p.account_id AND r.panelist_id = v_p.id
                                AND r.reason NOT LIKE 'ok%' AND COALESCE(r.first_attempt_at, r.created_at) > now() - interval '30 days'),
    'gps_said_no_30d', (SELECT count(*) FROM panelist_incident i
                         WHERE i.account_id = v_p.account_id AND i.panelist_id = v_p.id AND i.category = 'gps_location'
                           AND i.payload->>'reason' = 'wrong_place' AND i.reported_at > now() - interval '30 days'),
    'leave_days_year', (SELECT COALESCE(sum(LEAST(u.end_date, make_date(extract(year FROM v_today)::int, 12, 31))
                                           - GREATEST(u.start_date, make_date(extract(year FROM v_today)::int, 1, 1)) + 1), 0)
                          FROM panelist_unavailability u
                         WHERE u.account_id = v_p.account_id AND u.panelist_id = v_p.id AND u.status = 'active'
                           AND u.end_date >= make_date(extract(year FROM v_today)::int, 1, 1)
                           AND u.start_date <= make_date(extract(year FROM v_today)::int, 12, 31)),
    'pobox_ref', EXISTS (SELECT 1 FROM panelist_location_reference l WHERE l.panelist_id = v_p.id AND l.kind = 'pobox' AND l.active),
    'home_ref', EXISTS (SELECT 1 FROM panelist_location_reference l WHERE l.panelist_id = v_p.id AND l.kind = 'home' AND l.active),
    'ref_needs_review', EXISTS (SELECT 1 FROM panelist_location_reference l
                                 WHERE l.panelist_id = v_p.id AND l.active AND l.needs_review));

  RETURN jsonb_build_object(
    'panelist', v_head, 'stats', v_stats, 'events', v_rows,
    'next', CASE WHEN v_last IS NULL THEN 'null'::jsonb
                 ELSE jsonb_build_object('before', v_last->'at', 'before_id', v_last->'id') END,
    'can_write', public.has_access(v_p.account_id, 'panelists', 'edit'));
END; $$;

-- ------------------------------------------------------------------ notas
CREATE OR REPLACE FUNCTION public.panelist_note_add(p_panelist_id uuid, p_body text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_acc uuid; v_body text := btrim(p_body); v_id uuid;
BEGIN
  SELECT account_id INTO v_acc FROM panelists WHERE id = p_panelist_id;
  IF v_acc IS NULL OR auth.uid() IS NULL OR NOT public.has_access(v_acc, 'panelists', 'edit') THEN
    RAISE EXCEPTION 'not allowed' USING ERRCODE = '42501';
  END IF;
  IF v_body IS NULL OR length(v_body) < 1 OR length(v_body) > 2000 THEN
    RAISE EXCEPTION 'note must have 1-2000 characters' USING ERRCODE = '22023';
  END IF;
  INSERT INTO panelist_note (account_id, panelist_id, body, created_by)
  VALUES (v_acc, p_panelist_id, v_body, auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.panelist_note_delete(p_note_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_by uuid;
BEGIN
  SELECT created_by INTO v_by FROM panelist_note WHERE id = p_note_id;
  IF v_by IS NULL OR auth.uid() IS NULL OR NOT (v_by = auth.uid() OR public.is_superadmin()) THEN
    RAISE EXCEPTION 'not allowed' USING ERRCODE = '42501';
  END IF;
  DELETE FROM panelist_note WHERE id = p_note_id;
END; $$;

REVOKE ALL ON FUNCTION public.panelist_history(uuid, timestamptz, uuid, int) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.panelist_note_add(uuid, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.panelist_note_delete(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.panelist_history(uuid, timestamptz, uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.panelist_note_add(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.panelist_note_delete(uuid) TO authenticated;
