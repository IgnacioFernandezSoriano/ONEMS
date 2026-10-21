-- Incidencias reportadas por el panelista, v2. Forward-only. NO toca el baseline.
-- Cada seccion la anade una tarea del plan; ver docs/superpowers/plans/ (incidencias reportadas v2, plan 1 BD).

-- ===== 1) Estado auto_resolved + razon 'materials' =====
-- auto_resolved: incidencia cerrada automaticamente por el sistema (sin accion del manager).
ALTER TABLE public.panelist_incident DROP CONSTRAINT pi_status_check;
ALTER TABLE public.panelist_incident ADD CONSTRAINT pi_status_check
  CHECK (status IN ('open','in_progress','resolved','dismissed','auto_resolved'));

-- Igual que la version de 20260806160000, pero admite tambien reason='materials'
-- (el CHECK de panelist_unavailability.reason ya la permite desde 20260807100000).
CREATE OR REPLACE FUNCTION public.create_unavailability_from_incident(
  p_incident_id uuid, p_start date, p_end date, p_reason text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid; v_panelist uuid; v_new uuid;
BEGIN
  SELECT account_id, panelist_id INTO v_account, v_panelist
    FROM panelist_incident WHERE id = p_incident_id;
  PERFORM assert_same_account(v_account);
  IF p_start IS NULL OR p_end IS NULL OR p_end < p_start THEN
    RAISE EXCEPTION 'invalid date range'; END IF;
  -- panelist_unavailability.reason es NOT NULL con CHECK IN
  -- ('vacation','sick_leave','personal','training','other','materials'); si el llamador no
  -- pasa un valor valido, usamos 'other' para no romper la constraint.
  INSERT INTO panelist_unavailability (account_id, panelist_id, start_date, end_date, reason, status)
  VALUES (
    v_account, v_panelist, p_start, p_end,
    CASE WHEN p_reason IN ('vacation','sick_leave','personal','training','other','materials')
         THEN p_reason ELSE 'other' END,
    'active')
  RETURNING id INTO v_new;  -- el trigger generate_proposals_on_unavailability_trigger dispara el motor
  UPDATE panelist_incident SET linked_unavailability_id = v_new, status = 'in_progress', updated_at = now()
  WHERE id = p_incident_id;
  RETURN v_new;
END; $$;
