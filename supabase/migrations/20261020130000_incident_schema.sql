-- Incidencias de indisponibilidad: esquema de estado/resolucion automatica + cola de avisos.

-- (1) Datos: 'confirmed' pasa a 'manager_resolved' (ANTES de cambiar el CHECK).
UPDATE public.panelist_reassignment_proposal SET status='manager_resolved' WHERE status='confirmed';

-- (2) CHECKs ampliados.
ALTER TABLE public.panelist_reassignment_proposal
  DROP CONSTRAINT prp_status_check,
  ADD CONSTRAINT prp_status_check CHECK (status IN ('pending','auto_resolved','manager_resolved','info','dismissed'));
ALTER TABLE public.panelist_reassignment_proposal
  DROP CONSTRAINT prp_final_action_check,
  ADD CONSTRAINT prp_final_action_check CHECK (final_action IS NULL OR final_action IN ('reroute','shift_date','cancel','manual','none'));

-- (3) Columnas nuevas.
ALTER TABLE public.panelist_unavailability
  ADD COLUMN incident_status text NOT NULL DEFAULT 'new',
  ADD COLUMN auto_summary text,
  ADD COLUMN final_resolution text,
  ADD COLUMN resolved_at timestamptz;
ALTER TABLE public.panelist_unavailability
  ADD CONSTRAINT panelist_unavailability_incident_status_check
  CHECK (incident_status IN ('new','auto_resolved','pending_manager','resolved'));
ALTER TABLE public.panelist_reassignment_proposal
  ADD COLUMN resolution_note text,
  ADD COLUMN applied_at timestamptz;
ALTER TABLE public.allocation_plan_details
  ADD COLUMN original_fecha_programada date;

-- (4) Cola de avisos al panelista.
CREATE TABLE public.panelist_notification (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  panelist_id uuid NOT NULL REFERENCES public.panelists(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('unavailability_received','plan_change_this_week')),
  payload jsonb NOT NULL DEFAULT '{}',
  status text NOT NULL DEFAULT 'pending_send' CHECK (status IN ('pending_send','sent','failed')),
  error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz
);
CREATE INDEX idx_pn_pending ON public.panelist_notification (created_at) WHERE status = 'pending_send';
ALTER TABLE public.panelist_notification ENABLE ROW LEVEL SECURITY;
CREATE POLICY panelist_notification_select ON public.panelist_notification
  FOR SELECT TO authenticated
  USING (account_id = public.current_user_account_id() OR public.is_superadmin());
GRANT SELECT ON public.panelist_notification TO authenticated;

-- (5) Relleno de incident_status para bajas existentes (review_status no se toca).
UPDATE public.panelist_unavailability u
   SET incident_status = 'resolved', resolved_at = u.updated_at
 WHERE u.status = 'cancelled' OR u.review_status = 'reviewed';
UPDATE public.panelist_unavailability u
   SET incident_status = 'pending_manager'
 WHERE u.incident_status = 'new'
   AND u.review_status = 'pending_review'
   AND EXISTS (SELECT 1 FROM public.panelist_reassignment_proposal p WHERE p.unavailability_id = u.id);

-- (6) Compatibilidad con el frontend viejo: apply_reassignment_proposal cierra en 'manager_resolved'.
CREATE OR REPLACE FUNCTION public.apply_reassignment_proposal(
  p_proposal_id uuid,
  p_final_action text,
  p_final_target_node_id uuid DEFAULT NULL,
  p_final_date date DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prop record;
  v_actor uuid := auth.uid();
  v_actor_account uuid;
BEGIN
  SELECT * INTO v_prop FROM panelist_reassignment_proposal WHERE id = p_proposal_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proposal % not found', p_proposal_id; END IF;
  IF v_prop.status <> 'pending' THEN
    RAISE EXCEPTION 'Proposal % already %', p_proposal_id, v_prop.status;
  END IF;

  -- Guarda multi-tenant: el actor debe ser superadmin o de la misma cuenta.
  IF NOT is_superadmin() THEN
    SELECT account_id INTO v_actor_account FROM profiles WHERE id = v_actor;
    IF v_actor_account IS DISTINCT FROM v_prop.account_id THEN
      RAISE EXCEPTION 'Cross-tenant access denied';
    END IF;
  END IF;

  -- Propuestas informativas (recepción ya salida): solo se descartan, sin tocar el plan.
  IF v_prop.suggested_action = 'none' OR p_final_action = 'none' THEN
    UPDATE panelist_reassignment_proposal
      SET status='dismissed', final_action=NULL, confirmed_by=v_actor, confirmed_at=now(), updated_at=now()
      WHERE id = p_proposal_id;
    RETURN;
  END IF;

  IF p_final_action = 'reroute' THEN
    IF p_final_target_node_id IS NULL THEN RAISE EXCEPTION 'reroute requires target node'; END IF;
    IF v_prop.affected_role = 'origin' THEN
      UPDATE allocation_plan_details
        SET original_origin_node_id = COALESCE(original_origin_node_id, origin_node_id),
            origin_node_id = p_final_target_node_id,
            reassignment_reason='panelist_unavailable', reassigned_at=now(), reassigned_by=v_actor, updated_at=now()
        WHERE id = v_prop.allocation_plan_detail_id;
    ELSE
      UPDATE allocation_plan_details
        SET original_destination_node_id = COALESCE(original_destination_node_id, destination_node_id),
            destination_node_id = p_final_target_node_id,
            reassignment_reason='panelist_unavailable', reassigned_at=now(), reassigned_by=v_actor, updated_at=now()
        WHERE id = v_prop.allocation_plan_detail_id;
    END IF;

  ELSIF p_final_action = 'shift_date' THEN
    IF p_final_date IS NULL THEN RAISE EXCEPTION 'shift_date requires date'; END IF;
    UPDATE allocation_plan_details
      SET fecha_programada = p_final_date,
          reassignment_reason='panelist_unavailable', reassigned_at=now(), reassigned_by=v_actor, updated_at=now()
      WHERE id = v_prop.allocation_plan_detail_id;

  ELSIF p_final_action = 'cancel' THEN
    UPDATE allocation_plan_details
      SET status='cancelled',
          reassignment_reason='panelist_unavailable', reassigned_at=now(), reassigned_by=v_actor, updated_at=now()
      WHERE id = v_prop.allocation_plan_detail_id;

  ELSIF p_final_action = 'manual' THEN
    -- El manager edita a mano nodo (según rol) y/o fecha del mismo registro.
    UPDATE allocation_plan_details
      SET original_origin_node_id = CASE
            WHEN v_prop.affected_role='origin' AND p_final_target_node_id IS NOT NULL
            THEN COALESCE(original_origin_node_id, origin_node_id) ELSE original_origin_node_id END,
          origin_node_id = CASE
            WHEN v_prop.affected_role='origin' AND p_final_target_node_id IS NOT NULL
            THEN p_final_target_node_id ELSE origin_node_id END,
          original_destination_node_id = CASE
            WHEN v_prop.affected_role='destination' AND p_final_target_node_id IS NOT NULL
            THEN COALESCE(original_destination_node_id, destination_node_id) ELSE original_destination_node_id END,
          destination_node_id = CASE
            WHEN v_prop.affected_role='destination' AND p_final_target_node_id IS NOT NULL
            THEN p_final_target_node_id ELSE destination_node_id END,
          fecha_programada = COALESCE(p_final_date, fecha_programada),
          reassignment_reason='manual', reassigned_at=now(), reassigned_by=v_actor, updated_at=now()
      WHERE id = v_prop.allocation_plan_detail_id;
  ELSE
    RAISE EXCEPTION 'Unknown final_action %', p_final_action;
  END IF;

  UPDATE panelist_reassignment_proposal
    SET status='manager_resolved', final_action=p_final_action,
        final_target_node_id=p_final_target_node_id, final_date=p_final_date,
        confirmed_by=v_actor, confirmed_at=now(), updated_at=now()
    WHERE id = p_proposal_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_reassignment_proposal(uuid, text, uuid, date) TO authenticated;
