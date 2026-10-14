-- Motor de reasignación (B) — aplicar al confirmar. Muta el plan SOLO aquí.
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
    SET status='confirmed', final_action=p_final_action,
        final_target_node_id=p_final_target_node_id, final_date=p_final_date,
        confirmed_by=v_actor, confirmed_at=now(), updated_at=now()
    WHERE id = p_proposal_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_reassignment_proposals_bulk(p_unavailability_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_applied integer := 0;
BEGIN
  FOR r IN
    SELECT id, suggested_action, suggested_target_node_id, suggested_date
    FROM panelist_reassignment_proposal
    WHERE unavailability_id = p_unavailability_id AND status = 'pending'
  LOOP
    PERFORM apply_reassignment_proposal(r.id, r.suggested_action, r.suggested_target_node_id, r.suggested_date);
    v_applied := v_applied + 1;
  END LOOP;
  RETURN v_applied;
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_reassignment_proposal(uuid, text, uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_reassignment_proposals_bulk(uuid) TO authenticated;
