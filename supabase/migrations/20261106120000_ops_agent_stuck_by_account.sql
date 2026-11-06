-- ============================================================
-- Agente de operaciones, fase 3: conversaciones atascadas por cuenta — 2026-11-06
-- ============================================================
-- Requiere 20261106090000_ops_agent_fixes.sql.
--
-- Primera lectura real (6/11): 14 panelistas "atascados", 4 de ellos con el bot esperando de verdad su
-- respuesta a una incidencia (pending_incident_reply) y el resto restos viejos. Decision del responsable:
--   * pending_incident_reply no cuenta como atasco y R1 nunca lo borra (su respuesta debe ir a la incidencia);
--   * el aviso sale en UNA linea por cuenta (stuck_context: [{account, panelists:[...], since}]);
--   * R1 pasa a ser por cuenta: borra solo las filas viejas (> 24 h, no pending_incident_reply) de los
--     panelistas atascados de esa cuenta; las recientes no, porque pueden estar usandose ahora.
-- Un panelista cuyo telegram usa tambien otro panelista sale en el aviso pero R1 no lo toca (panelist_context
-- no lleva cuenta) y la vista previa lo devuelve en "skipped".
-- R1 cambia de argumento (codigo de panelista -> nombre de cuenta) con los mismos tipos: DROP + CREATE.
-- ============================================================

-- Filas atascadas: panelista activo, fila de hace mas de 24 h que no es una espera de respuesta a incidencia.
CREATE OR REPLACE FUNCTION ops_fix._stuck_rows()
RETURNS TABLE (account_id uuid, account text, panelist text, telegram_id text, ctx_id bigint,
               context_type text, created_at timestamptz, shared boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p.account_id, a.name, p.panelist_code, p.telegram_id, x.id, x.context_type, x.created_at,
         EXISTS (SELECT 1 FROM public.panelists o WHERE o.telegram_id = p.telegram_id AND o.id <> p.id)
    FROM public.panelists p
    JOIN public.accounts a ON a.id = p.account_id
    JOIN public.panelist_context x ON x.telegram_id = p.telegram_id
   WHERE p.status = 'active' AND p.telegram_id IS NOT NULL AND btrim(p.telegram_id) <> ''
     AND x.context_type IS DISTINCT FROM 'pending_incident_reply'
     AND x.created_at < now() - interval '24 hours';
$$;

-- Lo que ensena la vista previa de R1 (y lo que apply compara con p_expected->'contexts').
CREATE OR REPLACE FUNCTION ops_fix._r1_account_contexts(p_account uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE((SELECT jsonb_agg(jsonb_build_object('panelist', s.panelist, 'context_type', s.context_type,
                                                       'created_at', s.created_at)
                                    ORDER BY s.panelist, s.created_at, s.ctx_id)
                     FROM ops_fix._stuck_rows() s WHERE s.account_id = p_account AND NOT s.shared), '[]'::jsonb);
$$;

DROP FUNCTION IF EXISTS public.ops_fix_r1_preview(text, text);
DROP FUNCTION IF EXISTS public.ops_fix_r1_apply(text, text, jsonb);
DROP FUNCTION IF EXISTS ops_fix._r1_panelist(text);
DROP FUNCTION IF EXISTS ops_fix._r1_contexts(text);

CREATE FUNCTION public.ops_fix_r1_preview(p_token text, p_account text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_acc uuid;
BEGIN
  PERFORM ops_test._check(p_token);
  v_acc := ops_fix._account(p_account);
  RETURN jsonb_build_object(
    'account', p_account,
    'panelists', COALESCE((SELECT jsonb_agg(DISTINCT s.panelist) FROM ops_fix._stuck_rows() s
                            WHERE s.account_id = v_acc AND NOT s.shared), '[]'::jsonb),
    'skipped', COALESCE((SELECT jsonb_agg(DISTINCT s.panelist) FROM ops_fix._stuck_rows() s
                          WHERE s.account_id = v_acc AND s.shared), '[]'::jsonb),
    'contexts', ops_fix._r1_account_contexts(v_acc));
END $$;

CREATE FUNCTION public.ops_fix_r1_apply(p_token text, p_account text, p_expected jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_acc uuid; v_ids bigint[]; v_before jsonb; v_n int; v_log bigint;
BEGIN
  PERFORM ops_test._check(p_token);
  v_acc := ops_fix._account(p_account);
  v_ids := ARRAY(SELECT s.ctx_id FROM ops_fix._stuck_rows() s WHERE s.account_id = v_acc AND NOT s.shared);
  PERFORM 1 FROM public.panelist_context x WHERE x.id = ANY (v_ids) FOR UPDATE;
  IF ops_fix._r1_account_contexts(v_acc) IS DISTINCT FROM p_expected->'contexts' THEN
    RAISE EXCEPTION 'ops_fix: ha cambiado desde la propuesta';
  END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(x.*) ORDER BY x.id), '[]'::jsonb) INTO v_before
    FROM public.panelist_context x WHERE x.id = ANY (v_ids);
  DELETE FROM public.panelist_context x WHERE x.id = ANY (v_ids);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  INSERT INTO ops_fix.log (kind, account_id, target, before, after)
  VALUES ('r1', v_acc, p_account, v_before, '[]'::jsonb)
  RETURNING id INTO v_log;
  RETURN jsonb_build_object('log_id', v_log, 'deleted', v_n);
END $$;

-- ---------- ops_test_checks: stuck_context por cuenta ----------
-- pobox_no_send, no_receipts y panelist_no_node quedan exactamente igual que en 20261106090000.
CREATE OR REPLACE FUNCTION public.ops_test_checks(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_pobox jsonb; v_recv jsonb; v_nonode jsonb; v_stuck jsonb;
BEGIN
  PERFORM ops_test._check(p_token);

  SELECT COALESCE(jsonb_agg(jsonb_build_object('account', x.account, 'city', btrim(x.city), 'node', x.node,
                                               'day', x.day::text) ORDER BY x.account, x.city), '[]'::jsonb)
    INTO v_pobox
    FROM ops_fix._pobox_no_send() x;

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

  SELECT COALESCE(jsonb_agg(jsonb_build_object('account', a.name, 'panelist', p.panelist_code, 'city', btrim(c.name))
                            ORDER BY a.name, p.panelist_code), '[]'::jsonb)
    INTO v_nonode
    FROM public.panelists p
    JOIN public.accounts a ON a.id = p.account_id
    LEFT JOIN public.cities c ON c.id = p.city_id AND c.account_id = p.account_id
   WHERE p.status = 'active' AND p.node_id IS NULL
     AND p.telegram_id IS NOT NULL AND btrim(p.telegram_id) <> '';

  SELECT COALESCE(jsonb_agg(jsonb_build_object('account', s.account, 'panelists', s.panelists,
                                               'since', to_char(s.since AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI"Z"'))
                            ORDER BY s.account), '[]'::jsonb)
    INTO v_stuck
    FROM (SELECT r.account, jsonb_agg(DISTINCT r.panelist) AS panelists, min(r.created_at) AS since
            FROM ops_fix._stuck_rows() r
           GROUP BY r.account) s;

  RETURN jsonb_build_object('pobox_no_send', v_pobox, 'no_receipts', v_recv,
                            'panelist_no_node', v_nonode, 'stuck_context', v_stuck);
END $$;

-- ---------- permisos ----------
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ops_fix FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_fix_r1_preview(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_fix_r1_apply(text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_fix_r1_preview(text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_fix_r1_apply(text, text, jsonb) TO anon;
REVOKE ALL ON FUNCTION public.ops_test_checks(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_test_checks(text) TO anon;
