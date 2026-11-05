-- Avisos de operativa para el informe diario del agente (2026-11-05). Solo lectura.
-- Requiere 20261105160000_ops_agent_test_fixtures.sql (esquema ops_test y token del agente).
--
-- ops_test_checks(token) devuelve:
--   pobox_no_send: nodos de ciudades POBOX (un solo nodo activo, como la regla de recepcion) con panelista activo
--                  y no de baja, SIN ningun envio programado el proximo dia laborable de su cuenta. Ese dia no se
--                  podra comprobar si fue al apartado (regla del usuario: cada panelista POBOX envia cada dia).
--   no_receipts:   ciudades destino con >= 3 cartas enviadas hace mas de 5 dias y aun sin recibir, y ninguna
--                  recepcion en los ultimos 7 dias (caso Nyeri, 5/11).
-- Solo nombres de cuenta, ciudad y nodo: ningun dato personal de panelistas.

CREATE OR REPLACE FUNCTION public.ops_test_checks(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_pobox jsonb; v_recv jsonb;
BEGIN
  PERFORM ops_test._check(p_token);

  WITH acc AS (
    SELECT a.id, a.name,
           (SELECT g::date FROM generate_series((now() AT TIME ZONE COALESCE(a.timezone, 'UTC'))::date + 1,
                                               (now() AT TIME ZONE COALESCE(a.timezone, 'UTC'))::date + 14,
                                               interval '1 day') g
             WHERE public.is_account_working_day(a.id, g::date) ORDER BY g LIMIT 1) AS d
      FROM public.accounts a),
  nod AS (
    SELECT acc.name AS account, c.name AS city, n.auto_id AS node, n.id AS node_id, acc.d
      FROM public.nodes n
      JOIN public.cities c ON c.id = n.city_id
      JOIN acc ON acc.id = n.account_id
     WHERE n.status = 'active' AND acc.d IS NOT NULL
       AND COALESCE((SELECT e.pobox_enabled FROM public.effective_city_policy(c.id) e), false)
       AND (SELECT count(*) FROM public.nodes n2 WHERE n2.city_id = c.id AND n2.status = 'active') = 1
       AND EXISTS (SELECT 1 FROM public.panelists p WHERE p.node_id = n.id AND p.status = 'active'
                     AND NOT EXISTS (SELECT 1 FROM public.panelist_unavailability u
                                      WHERE u.panelist_id = p.id AND u.status = 'active'
                                        AND acc.d BETWEEN u.start_date AND u.end_date)))
  SELECT COALESCE(jsonb_agg(jsonb_build_object('account', nod.account, 'city', btrim(nod.city), 'node', nod.node,
                                               'day', nod.d::text) ORDER BY nod.account, nod.city), '[]'::jsonb)
    INTO v_pobox
    FROM nod
   WHERE NOT EXISTS (SELECT 1 FROM public.allocation_plan_details x
                      WHERE x.origin_node_id = nod.node_id AND x.fecha_programada = nod.d AND x.status <> 'cancelled');

  WITH w AS (
    SELECT a.name AS account, c.id AS city_id, c.name AS city, count(*) AS waiting, min(d.sent_at) AS oldest,
           max(a.timezone) AS tz
      FROM public.allocation_plan_details d
      JOIN public.nodes n ON n.id = d.destination_node_id
      JOIN public.cities c ON c.id = n.city_id
      JOIN public.accounts a ON a.id = d.account_id
     WHERE d.status = 'sent' AND d.sent_at < now() - interval '5 days' AND d.sent_at > now() - interval '30 days'
     GROUP BY a.name, c.id, c.name
    HAVING count(*) >= 3)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('account', w.account, 'city', btrim(w.city), 'waiting', w.waiting,
                                               'oldest', ((w.oldest AT TIME ZONE COALESCE(w.tz, 'UTC'))::date)::text)
                            ORDER BY w.account, w.waiting DESC), '[]'::jsonb)
    INTO v_recv
    FROM w
   WHERE NOT EXISTS (SELECT 1 FROM public.allocation_plan_details r
                       JOIN public.nodes rn ON rn.id = r.destination_node_id
                      WHERE rn.city_id = w.city_id AND r.received_at > now() - interval '7 days');

  RETURN jsonb_build_object('pobox_no_send', v_pobox, 'no_receipts', v_recv);
END $$;

REVOKE ALL ON FUNCTION public.ops_test_checks(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_test_checks(text) TO anon;
