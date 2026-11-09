-- ============================================================
-- Informe de operación por cuenta (agente de operaciones) — 2026-11-09
-- ============================================================
-- Solo lectura. El agente la llama los lunes, miércoles y viernes con la clave pública (anon) y su
-- token (el mismo de ops_test_checks: hash en ops_test.secret). Devuelve, para UNA cuenta, todo lo que
-- necesita el correo: contactos, material, ciudades que no reciben, panelistas sin nodo, análisis por
-- panelista, bajas pendientes, revisión de configuración y lecturas RFID del estudio por oficina.
-- Todo se filtra por account_id: nunca mezcla cuentas. No escribe nada.
-- Playbook: panelist_n8n/ops-agent/playbook/informe-semanal-panelistas.md
-- ============================================================

CREATE SCHEMA IF NOT EXISTS ops_report;
REVOKE ALL ON SCHEMA ops_report FROM PUBLIC, anon, authenticated;

-- Días de baja activos (uno por fila) de los panelistas de la cuenta.
CREATE OR REPLACE FUNCTION ops_report._data(p_account uuid, p_from date, p_to date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_tz text; v_today date; v_out jsonb;
BEGIN
  SELECT a.timezone INTO v_tz FROM public.accounts a WHERE a.id = p_account;
  IF v_tz IS NULL THEN RAISE EXCEPTION 'ops_report: cuenta no encontrada'; END IF;
  v_today := (now() AT TIME ZONE v_tz)::date;

  WITH
  pp AS (  -- panelistas activos de la cuenta
    SELECT p.id, p.panelist_code AS code, p.name, p.email, p.mobile, p.node_id, p.city_id, p.telegram_id,
           p.language, p.created_at, p.address_city, n.auto_id AS node, c.name AS city, c.id AS node_city_id,
           COALESCE((SELECT e.pobox_enabled FROM public.effective_city_policy(c.id) e), false) AS pobox
      FROM public.panelists p
      LEFT JOIN public.nodes n ON n.id = p.node_id
      LEFT JOIN public.cities c ON c.id = n.city_id
     WHERE p.account_id = p_account AND p.status = 'active'),
  wd AS (SELECT g::date AS d FROM generate_series(p_from, p_to, interval '1 day') g WHERE extract(isodow FROM g) < 6),
  unav AS (SELECT u.panelist_id, g::date AS d, u.review_status
             FROM public.panelist_unavailability u
             CROSS JOIN LATERAL generate_series(u.start_date, u.end_date, interval '1 day') g
            WHERE u.account_id = p_account AND u.status = 'active'),
  apd AS (SELECT d.*, (d.sent_at AT TIME ZONE v_tz) AS sent_l, (d.received_at AT TIME ZONE v_tz) AS recv_l
            FROM public.allocation_plan_details d WHERE d.account_id = p_account),
  act AS (
    SELECT pp.id AS pid, a.sent_l::date AS d FROM pp JOIN apd a ON a.origin_node_id = pp.node_id WHERE a.sent_at IS NOT NULL
    UNION SELECT pp.id, a.recv_l::date FROM pp JOIN apd a ON a.destination_node_id = pp.node_id WHERE a.received_at IS NOT NULL
    UNION SELECT r.panelist_id, (r.last_attempt_at AT TIME ZONE v_tz)::date FROM public.receipt_case r WHERE r.account_id = p_account
    UNION SELECT i.panelist_id, (i.reported_at AT TIME ZONE v_tz)::date FROM public.panelist_incident i WHERE i.account_id = p_account
    UNION SELECT m.panelist_id, (m.created_at AT TIME ZONE v_tz)::date FROM public.incident_message m
           WHERE m.account_id = p_account AND m.direction = 'inbound'),
  prog AS (SELECT a.origin_node_id AS node_id, a.fecha_programada AS f, a.sent_l::date AS s
             FROM apd a WHERE a.fecha_programada BETWEEN p_from AND p_to AND a.status <> 'cancelled'),
  pan AS (
    SELECT pp.*,
      (SELECT count(*) FROM prog WHERE prog.node_id = pp.node_id) AS scheduled,
      (SELECT count(*) FROM prog WHERE prog.node_id = pp.node_id AND prog.s = prog.f) AS on_time,
      (SELECT count(*) FROM prog WHERE prog.node_id = pp.node_id AND prog.s > prog.f) AS late,
      (SELECT max(prog.s - prog.f) FROM prog WHERE prog.node_id = pp.node_id AND prog.s > prog.f) AS max_late_days,
      (SELECT count(*) FROM prog WHERE prog.node_id = pp.node_id AND prog.s < prog.f) AS early,
      (SELECT count(*) FROM prog WHERE prog.node_id = pp.node_id AND prog.s IS NULL) AS unsent,
      (SELECT count(*) FROM apd a WHERE a.origin_node_id = pp.node_id AND a.fecha_programada < v_today
                                    AND a.status IN ('pending','notified')) AS unsent_total,
      (SELECT count(*) FROM apd a WHERE a.origin_node_id = pp.node_id AND a.sent_l::date BETWEEN p_from AND p_to
                                    AND (extract(hour FROM a.sent_l) < 7 OR extract(hour FROM a.sent_l) >= 19)) AS odd_hour,
      (SELECT count(*) FROM apd a WHERE a.origin_node_id = pp.node_id AND a.sent_l::date BETWEEN p_from AND p_to
                                    AND extract(isodow FROM a.sent_l) > 5) AS weekend,
      (SELECT count(*) FROM (SELECT date_trunc('minute', a.sent_at) AS m FROM apd a
                              WHERE a.origin_node_id = pp.node_id AND a.sent_l::date BETWEEN p_from AND p_to
                              GROUP BY 1 HAVING count(*) >= 2 AND count(DISTINCT a.fecha_programada) >= 2) x) AS bursts,
      (SELECT count(*) FROM public.receipt_case r WHERE r.culprit_panelist_id = pp.id AND r.reason = 'pobox_absent_no_visit') AS pobox_no_visit,
      (SELECT COALESCE(jsonb_object_agg(x.reason, x.n), '{}'::jsonb) FROM (
         SELECT r.reason, count(*) AS n FROM public.receipt_case r JOIN apd a ON a.id = r.detail_id
          WHERE a.origin_node_id = pp.node_id AND r.reason NOT IN ('ok','ok_same_city') GROUP BY 1) x) AS sent_problems,
      (SELECT count(*) FROM public.receipt_case r WHERE r.culprit_panelist_id = pp.id AND r.culprit_role = 'sender') AS sender_fault,
      (SELECT COALESCE(jsonb_object_agg(x.k, x.n), '{}'::jsonb) FROM (
         SELECT r.reason || CASE WHEN r.status IN ('pending','needs_decision') THEN ':open' ELSE '' END AS k, count(*) AS n
           FROM public.receipt_case r WHERE r.panelist_id = pp.id
            AND r.reason NOT IN ('ok','ok_same_city','ok_typo_fixed') GROUP BY 1) x) AS recv_problems,
      (SELECT count(*) FROM public.panelist_incident i WHERE i.panelist_id = pp.id AND i.category = 'unreadable_label_receipt') AS unreadable,
      (SELECT count(*) FROM apd a WHERE a.destination_node_id = pp.node_id AND a.received_at IS NOT NULL) AS received_total,
      (SELECT count(*) FROM apd a WHERE a.destination_node_id = pp.node_id AND a.status = 'sent' AND a.sent_at < now() - interval '7 days') AS waiting_7d,
      (SELECT min(a.sent_l)::date FROM apd a WHERE a.destination_node_id = pp.node_id AND a.status = 'sent') AS oldest_waiting,
      (SELECT count(*) FROM apd a WHERE a.origin_node_id = pp.node_id AND a.sent_at IS NOT NULL) AS sent_total,
      (SELECT max(a.sent_l)::date FROM apd a WHERE a.origin_node_id = pp.node_id) AS last_sent,
      (SELECT COALESCE(jsonb_agg(to_char(wd.d,'YYYY-MM-DD') ORDER BY wd.d), '[]'::jsonb) FROM wd
        WHERE wd.d >= (pp.created_at AT TIME ZONE v_tz)::date
          AND NOT EXISTS (SELECT 1 FROM act WHERE act.pid = pp.id AND act.d = wd.d)
          AND NOT EXISTS (SELECT 1 FROM unav WHERE unav.panelist_id = pp.id AND unav.d = wd.d)) AS inactive_days,
      (SELECT max(act.d) FROM act WHERE act.pid = pp.id) AS last_activity,
      (SELECT count(DISTINCT unav.d) FROM unav WHERE unav.panelist_id = pp.id AND unav.review_status = 'reviewed'
          AND date_trunc('month', unav.d) = date_trunc('month', v_today::timestamp) AND extract(isodow FROM unav.d) < 6) AS leave_month_ok,
      (SELECT count(DISTINCT unav.d) FROM unav WHERE unav.panelist_id = pp.id AND unav.review_status <> 'reviewed'
          AND date_trunc('month', unav.d) = date_trunc('month', v_today::timestamp) AND extract(isodow FROM unav.d) < 6) AS leave_month_pending,
      (SELECT count(DISTINCT unav.d) FROM unav WHERE unav.panelist_id = pp.id AND unav.review_status = 'reviewed'
          AND extract(year FROM unav.d) = extract(year FROM v_today) AND extract(isodow FROM unav.d) < 6) AS leave_year_ok,
      (SELECT count(DISTINCT unav.d) FROM unav WHERE unav.panelist_id = pp.id AND unav.review_status <> 'reviewed'
          AND extract(year FROM unav.d) = extract(year FROM v_today) AND extract(isodow FROM unav.d) < 6) AS leave_year_pending,
      (SELECT count(*) FROM public.material_hold h WHERE h.panelist_id = pp.id AND h.released_at IS NULL) AS held
    FROM pp),
  pcs AS (  -- oficinas: cartas del estudio que debieron pasar por su lector y cuántas leyó
    SELECT pc.id, pc.name, pc.city_id,
           (SELECT COALESCE(jsonb_agg(r.reader_id ORDER BY r.reader_id), '[]'::jsonb) FROM public.readers r
             WHERE r.postal_center_id = pc.id AND r.deleted_at IS NULL AND r.is_active) AS readers
      FROM public.postal_centers pc WHERE pc.account_id = p_account AND pc.deleted_at IS NULL AND pc.is_active),
  trips AS (SELECT a.tag_id, a.sent_l, a.recv_l, a.sent_at, no.city_id AS oc, nd.city_id AS dc
              FROM apd a JOIN public.nodes no ON no.id = a.origin_node_id JOIN public.nodes nd ON nd.id = a.destination_node_id
             WHERE a.sent_at IS NOT NULL),
  reads AS (SELECT DISTINCT r.postal_center_id AS pc, e.tag_id FROM public.rfid_events_raw e
              JOIN public.readers r ON r.reader_id = e.reader_id AND r.account_id = p_account
             WHERE e.account_id = p_account)
  SELECT jsonb_build_object(
    'account', (SELECT jsonb_build_object('name', a.name, 'timezone', a.timezone, 'language', a.default_language,
                  'today', v_today, 'from', p_from, 'to', p_to,
                  'contacts', jsonb_build_object('account_manager', a.email_account_manager,
                     'panelist_manager', a.email_panelist_manager, 'materials_supplier', a.email_materials_supplier,
                     'do_coordinator', a.email_do_coordinator, 'upu_account_manager', a.email_upu_account_manager))
                  FROM public.accounts a WHERE a.id = p_account),
    'material', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'code', pp.code, 'name', pp.name, 'email', pp.email, 'mobile', pp.mobile, 'city', btrim(pp.city), 'node', pp.node,
                   'missing', (SELECT jsonb_agg(jsonb_build_object('name', m->>'name', 'quantity', m->'quantity', 'unit', m->>'unit'))
                                 FROM jsonb_array_elements(COALESCE(i.payload->'materials', '[]'::jsonb)) m),
                   'reported', (i.reported_at AT TIME ZONE v_tz)::date, 'seen', i.manager_seen_at IS NOT NULL,
                   'shipment_status', (SELECT s.status FROM public.material_shipments s WHERE s.id = i.linked_material_shipment_id),
                   'held', (SELECT count(*) FROM public.material_hold h WHERE h.panelist_id = i.panelist_id AND h.released_at IS NULL),
                   'held_since', (SELECT min(h.held_since AT TIME ZONE v_tz)::date FROM public.material_hold h
                                   WHERE h.panelist_id = i.panelist_id AND h.released_at IS NULL)) ORDER BY i.reported_at), '[]'::jsonb)
                   FROM public.panelist_incident i JOIN pp ON pp.id = i.panelist_id
                  WHERE i.account_id = p_account AND i.category = 'missing_materials' AND i.status = 'open'),
    'panelists', (SELECT COALESCE(jsonb_agg(to_jsonb(pan) - 'id' - 'node_id' - 'city_id' - 'node_city_id' - 'telegram_id'
                                              - 'created_at' || jsonb_build_object('created', (pan.created_at AT TIME ZONE v_tz)::date,
                                                 'city', btrim(pan.city), 'has_telegram', pan.telegram_id IS NOT NULL,
                                                 'city_mismatch', pan.node_id IS NOT NULL AND pan.city_id IS DISTINCT FROM pan.node_city_id)
                                   ORDER BY pan.code), '[]'::jsonb) FROM pan),
    'pending_leave', (SELECT COALESCE(jsonb_agg(jsonb_build_object('code', pp.code, 'name', pp.name, 'start', u.start_date,
                        'end', u.end_date, 'requested', (u.created_at AT TIME ZONE v_tz)::date) ORDER BY u.start_date, pp.code), '[]'::jsonb)
                        FROM public.panelist_unavailability u JOIN pp ON pp.id = u.panelist_id
                       WHERE u.status = 'active' AND u.review_status <> 'reviewed' AND u.end_date >= v_today),
    'free_nodes', (SELECT COALESCE(jsonb_agg(jsonb_build_object('node', n.auto_id, 'city', btrim(c.name)) ORDER BY n.auto_id), '[]'::jsonb)
                     FROM public.nodes n JOIN public.cities c ON c.id = n.city_id
                    WHERE n.account_id = p_account AND n.status = 'active'
                      AND NOT EXISTS (SELECT 1 FROM pp WHERE pp.node_id = n.id)),
    'rfid_study', (SELECT COALESCE(jsonb_agg(jsonb_build_object('postal_center', pcs.name, 'readers', pcs.readers,
        'out', (SELECT count(*) FROM trips t WHERE t.oc = pcs.city_id AND t.sent_l::date BETWEEN p_from AND p_to),
        'out_read', (SELECT count(*) FROM trips t WHERE t.oc = pcs.city_id AND t.sent_l::date BETWEEN p_from AND p_to
                       AND EXISTS (SELECT 1 FROM reads WHERE reads.pc = pcs.id AND reads.tag_id = t.tag_id)),
        'in', (SELECT count(*) FROM trips t WHERE t.dc = pcs.city_id AND t.recv_l::date BETWEEN p_from AND p_to),
        'in_read', (SELECT count(*) FROM trips t WHERE t.dc = pcs.city_id AND t.recv_l::date BETWEEN p_from AND p_to
                       AND EXISTS (SELECT 1 FROM reads WHERE reads.pc = pcs.id AND reads.tag_id = t.tag_id)),
        'out_total', (SELECT count(*) FROM trips t WHERE t.oc = pcs.city_id),
        'out_total_read', (SELECT count(*) FROM trips t WHERE t.oc = pcs.city_id
                       AND EXISTS (SELECT 1 FROM reads WHERE reads.pc = pcs.id AND reads.tag_id = t.tag_id)))
        ORDER BY pcs.name), '[]'::jsonb) FROM pcs),
    'config', jsonb_build_object(
      'sla_count', (SELECT count(*) FROM public.slas s WHERE s.account_id = p_account)
                 + (SELECT count(*) FROM public.sla_definitions s WHERE s.account_id = p_account),
      'lanes', (WITH l AS (SELECT DISTINCT ap.product_id, no.city_id AS oc, nd.city_id AS dc
                             FROM apd a JOIN public.allocation_plans ap ON ap.id = a.plan_id
                             JOIN public.nodes no ON no.id = a.origin_node_id JOIN public.nodes nd ON nd.id = a.destination_node_id
                            WHERE a.status <> 'cancelled'),
                     m AS (SELECT * FROM l WHERE NOT EXISTS (SELECT 1 FROM public.delivery_standards s
                             WHERE s.product_id = l.product_id AND s.origin_city_id = l.oc AND s.destination_city_id = l.dc))
                SELECT jsonb_build_object('total', (SELECT count(*) FROM l), 'missing', (SELECT count(*) FROM m),
                  'cities', (SELECT COALESCE(jsonb_agg(x.c ORDER BY x.n DESC), '[]'::jsonb) FROM (
                     SELECT btrim(c.name) AS c, count(*) AS n FROM m JOIN public.cities c ON c.id IN (m.oc, m.dc)
                      GROUP BY 1 HAVING count(*) >= 10) x))),
      'pc_total', (SELECT count(*) FROM pcs),
      'pc_no_hours', (SELECT count(*) FROM public.postal_centers p WHERE p.account_id = p_account AND p.deleted_at IS NULL
                         AND (p.opening_hour IS NULL OR p.working_hours_end IS NULL)),
      'pc_no_city', (SELECT COALESCE(jsonb_agg(p.name ORDER BY p.name), '[]'::jsonb) FROM public.postal_centers p
                      WHERE p.account_id = p_account AND p.deleted_at IS NULL AND p.city_id IS NULL),
      'city_no_pc', (SELECT COALESCE(jsonb_agg(btrim(c.name) ORDER BY c.name), '[]'::jsonb) FROM public.cities c
                      WHERE c.account_id = p_account AND EXISTS (SELECT 1 FROM public.nodes n WHERE n.city_id = c.id)
                        AND NOT EXISTS (SELECT 1 FROM public.postal_centers p WHERE p.city_id = c.id AND p.deleted_at IS NULL)),
      'city_spaces', (SELECT COALESCE(jsonb_agg(btrim(c.name) ORDER BY c.name), '[]'::jsonb) FROM public.cities c
                       WHERE c.account_id = p_account AND c.name <> btrim(c.name)),
      'panelists_total', (SELECT count(*) FROM pp WHERE pp.node_id IS NOT NULL),
      'panelists_with_stock', (SELECT count(DISTINCT s.panelist_id) FROM public.panelist_material_stocks s JOIN pp ON pp.id = s.panelist_id),
      'blocking_materials', (SELECT count(*) FROM public.material_catalog m WHERE m.account_id = p_account AND m.is_blocking),
      'held_total', (SELECT count(*) FROM public.material_hold h WHERE h.account_id = p_account AND h.released_at IS NULL),
      'product_desc_mismatch', (SELECT COALESCE(jsonb_agg(p.code ORDER BY p.code), '[]'::jsonb) FROM public.products p
                                 WHERE p.account_id = p_account AND p.status = 'active' AND (
                                   (p.code ILIKE '%express%' AND p.description ILIKE '%economy%')
                                OR (p.code ILIKE '%economy%' AND p.description ILIKE '%express%')
                                OR (p.code ILIKE '%standard%' AND (p.description ILIKE '%express%' OR p.description ILIKE '%economy%')))),
      'account_country', (SELECT a.country_code FROM public.accounts a WHERE a.id = p_account),
      'account_admin_email', (SELECT a.admin_email IS NOT NULL FROM public.accounts a WHERE a.id = p_account),
      'pobox_no_shares', (SELECT c.pobox_enabled AND jsonb_array_length(COALESCE(c.pobox_product_shares, '[]'::jsonb)) = 0
                            FROM public.account_config c WHERE c.account_id = p_account),
      'dup_mobile', (SELECT COALESCE(jsonb_agg(x.codes), '[]'::jsonb) FROM (
                       SELECT jsonb_agg(pp.code ORDER BY pp.code) AS codes FROM pp WHERE COALESCE(pp.mobile,'') <> ''
                        GROUP BY regexp_replace(pp.mobile, '\D', '', 'g') HAVING count(*) > 1) x),
      'dup_email', (SELECT COALESCE(jsonb_agg(x.codes), '[]'::jsonb) FROM (
                       SELECT jsonb_agg(pp.code ORDER BY pp.code) AS codes FROM pp WHERE COALESCE(pp.email,'') <> ''
                        GROUP BY lower(pp.email) HAVING count(*) > 1) x)),
    'readers', (SELECT COALESCE(jsonb_agg(jsonb_build_object('lpi', r.reader_id, 'name', r.name, 'postal_center', pc.name)
                  ORDER BY r.reader_id), '[]'::jsonb)
                  FROM public.readers r LEFT JOIN public.postal_centers pc ON pc.id = r.postal_center_id
                 WHERE r.account_id = p_account AND r.deleted_at IS NULL AND r.is_active),
    'has_schedule', EXISTS (SELECT 1 FROM apd a WHERE a.status <> 'cancelled' AND a.fecha_programada <= p_to)
  ) INTO v_out;
  RETURN v_out;
END $$;

-- Pública (anon + token): el agente pasa el nombre de la cuenta tal como sale en accounts.name.
CREATE OR REPLACE FUNCTION public.ops_report_data(p_token text, p_account text, p_from date, p_to date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id uuid;
BEGIN
  PERFORM ops_test._check(p_token);
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from OR p_to - p_from > 31 THEN
    RAISE EXCEPTION 'ops_report: periodo no valido';
  END IF;
  SELECT a.id INTO v_id FROM public.accounts a WHERE a.name = p_account AND a.status = 'active';
  IF v_id IS NULL THEN RAISE EXCEPTION 'ops_report: cuenta no encontrada'; END IF;
  RETURN ops_report._data(v_id, p_from, p_to);
END $$;

-- Lista de cuentas activas (solo nombre e idioma): el agente decide cuáles excluir (config.yaml).
CREATE OR REPLACE FUNCTION public.ops_report_accounts(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM ops_test._check(p_token);
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', a.name, 'language', a.default_language) ORDER BY a.name), '[]'::jsonb)
            FROM public.accounts a WHERE a.status = 'active');
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ops_report FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_report_data(text, text, date, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_report_accounts(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_report_data(text, text, date, date) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_report_accounts(text) TO anon;
