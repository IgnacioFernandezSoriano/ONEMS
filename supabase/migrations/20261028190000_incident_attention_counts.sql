-- Contador del menu "Incidencias": un solo numero por item con las incidencias en las que el manager tiene que
-- actuar, de la cuenta seleccionada (superadmin) o de la propia cuenta (resto de perfiles).
--   Reportadas: nuevas (abiertas y aun no abiertas por el manager) o con respuestas del panelista sin leer.
--   Bajas: pendientes de decision del manager o con respuestas del panelista sin leer.

ALTER TABLE public.panelist_incident ADD COLUMN IF NOT EXISTS manager_seen_at timestamptz;
COMMENT ON COLUMN public.panelist_incident.manager_seen_at IS
  'Primera vez que un manager abrio la incidencia. NULL + status open = nueva (cuenta en el menu).';

-- Las que ya no estan en 'open' ya las trato alguien: no son nuevas. Las 'open' existentes cuentan hasta abrirlas.
UPDATE public.panelist_incident
   SET manager_seen_at = coalesce(resolved_at, updated_at, created_at)
 WHERE manager_seen_at IS NULL AND status <> 'open';

CREATE OR REPLACE FUNCTION public.mark_panelist_incident_seen(p_incident_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_account uuid; v_n int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT account_id INTO v_account FROM panelist_incident WHERE id = p_incident_id;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM assert_same_account(v_account);
  UPDATE panelist_incident SET manager_seen_at = now()
   WHERE id = p_incident_id AND manager_seen_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END; $function$;

-- p_account_id solo lo usa el superadmin (NULL = todas las cuentas); el resto ve siempre su cuenta.
CREATE OR REPLACE FUNCTION public.incident_attention_counts(p_account_id uuid DEFAULT NULL)
RETURNS TABLE(reported integer, unavailability integer)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH scope AS (
    SELECT CASE WHEN is_superadmin() THEN p_account_id ELSE current_user_account_id() END AS acc,
           is_superadmin() AS su
     WHERE auth.uid() IS NOT NULL
  ), unread AS (
    SELECT DISTINCT m.incident_kind, m.incident_id
      FROM incident_message m, scope s
     WHERE m.direction = 'inbound' AND m.read_at IS NULL
       AND NOT (m.meta ?| array['callback','report_flow']) AND coalesce(m.meta->>'kind','') NOT LIKE 'material%'
       AND (m.account_id = s.acc OR (s.acc IS NULL AND s.su))
  )
  SELECT
    (SELECT count(*)::int FROM panelist_incident i, scope s
      WHERE (i.account_id = s.acc OR (s.acc IS NULL AND s.su))
        AND ((i.status = 'open' AND i.manager_seen_at IS NULL)
             OR EXISTS (SELECT 1 FROM unread u WHERE u.incident_kind = 'reported' AND u.incident_id = i.id))),
    (SELECT count(*)::int FROM panelist_unavailability pu, scope s
      WHERE (pu.account_id = s.acc OR (s.acc IS NULL AND s.su))
        AND (pu.incident_status = 'pending_manager'
             OR EXISTS (SELECT 1 FROM unread u WHERE u.incident_kind = 'unavailability' AND u.incident_id = pu.id)));
$function$;

REVOKE ALL ON FUNCTION public.mark_panelist_incident_seen(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_panelist_incident_seen(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.incident_attention_counts(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.incident_attention_counts(uuid) TO authenticated, service_role;
