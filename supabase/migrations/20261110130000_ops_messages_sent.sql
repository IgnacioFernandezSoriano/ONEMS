-- ============================================================
-- Mensajes automáticos enviados (agente de operaciones, mensaje de la mañana) — 2026-11-10
-- ============================================================
-- Solo lectura. El agente la llama cada mañana con la clave pública (anon) y su token (el mismo de
-- ops_test_checks: hash en ops_test.secret). Devuelve recuentos de lo que el sistema mandó a los
-- panelistas desde p_since, de TODAS las cuentas salvo las de prueba (p_exclude, por nombre de cuenta;
-- el agente pasa report.excluded_accounts de su config.yaml):
--   - panelist_notification por tipo (kind) y estado (sent / failed);
--   - incident_message de salida (outbound) por autor (bot / manager / system) y estado (sent / failed).
-- Solo cuenta: no devuelve textos, nombres ni datos de panelistas. No escribe nada.
-- ============================================================

CREATE OR REPLACE FUNCTION public.ops_messages_sent(p_token text, p_since timestamptz, p_exclude text[] DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_out jsonb;
BEGIN
  PERFORM ops_test._check(p_token);
  IF p_since IS NULL OR p_since > now() OR p_since < now() - interval '7 days' THEN
    RAISE EXCEPTION 'ops_report: periodo no valido';
  END IF;

  WITH acc AS (
    SELECT a.id FROM public.accounts a
     WHERE NOT (a.name = ANY (COALESCE(p_exclude, '{}'::text[])))),
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
     GROUP BY 1, 2)
  SELECT jsonb_build_object(
    'notifications', COALESCE((SELECT jsonb_agg(jsonb_build_object('kind', n.kind, 'status', n.status, 'n', n.n)
                                                ORDER BY n.kind, n.status) FROM n), '[]'::jsonb),
    'incident_messages', COALESCE((SELECT jsonb_agg(jsonb_build_object('author', m.author, 'status', m.status, 'n', m.n)
                                                    ORDER BY m.author, m.status) FROM m), '[]'::jsonb))
    INTO v_out;
  RETURN v_out;
END $$;

REVOKE ALL ON FUNCTION public.ops_messages_sent(text, timestamptz, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_messages_sent(text, timestamptz, text[]) TO anon;
