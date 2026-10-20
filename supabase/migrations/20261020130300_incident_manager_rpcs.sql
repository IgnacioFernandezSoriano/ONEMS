-- Incidencias de indisponibilidad: RPCs del manager.
--   suggest_for_week        -> propuesta para una semana elegida (solo lectura).
--   apply_manager_decision  -> aceptar la propuesta / semana elegida / anular la muestra.
--   set_incident_resolution -> texto libre de resolucion de la incidencia.
-- Guarda multi-tenant en las tres: superadmin, service role (auth.uid() NULL) o misma cuenta.
-- Ademas: apply_reassignment_proposal (legacy) valida que el nodo destino sea de la misma cuenta y ciudad.

-- (1) suggest_for_week: envoltorio de incident_suggest (que ya lleva la guarda multi-tenant).
CREATE OR REPLACE FUNCTION public.suggest_for_week(
  p_proposal_id uuid,
  p_week_start date,
  p_reference_load numeric DEFAULT 6,
  p_deviation_percent numeric DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM panelist_reassignment_proposal WHERE id = p_proposal_id;
  IF FOUND AND auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND v_account IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = auth.uid()) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;
  RETURN incident_suggest(p_proposal_id, p_week_start, p_reference_load, p_deviation_percent);
END;
$$;

-- (2) apply_manager_decision.
CREATE OR REPLACE FUNCTION public.apply_manager_decision(
  p_proposal_id uuid,
  p_decision text,
  p_week_start date DEFAULT NULL,
  p_reference_load numeric DEFAULT 6,
  p_deviation_percent numeric DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prop record;
  v_d record;
  v_cur_node uuid;
  v_action text;
  v_date date;
  v_node uuid;
  v_s jsonb;
  v_status text;
  v_final record;
BEGIN
  IF p_decision IS NULL OR p_decision NOT IN ('accept','week','cancel') THEN
    RAISE EXCEPTION 'Unknown decision %', p_decision;
  END IF;

  -- Bloquea la linea: dos clics simultaneos se serializan y el segundo ve 'manager_resolved'.
  SELECT * INTO v_prop FROM panelist_reassignment_proposal WHERE id = p_proposal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proposal % not found', p_proposal_id; END IF;

  IF auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND v_prop.account_id IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = auth.uid()) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;

  IF v_prop.status <> 'pending' THEN
    RAISE EXCEPTION 'Proposal % already %', p_proposal_id, v_prop.status;
  END IF;

  SELECT * INTO v_d FROM allocation_plan_details WHERE id = v_prop.allocation_plan_detail_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sample % not found', v_prop.allocation_plan_detail_id; END IF;
  v_cur_node := CASE WHEN v_prop.affected_role = 'origin' THEN v_d.origin_node_id ELSE v_d.destination_node_id END;

  IF p_decision = 'cancel' THEN
    v_action := 'cancel';
  ELSIF p_decision = 'accept' THEN
    v_action := v_prop.suggested_action;
    v_date := v_prop.suggested_date;
    v_node := v_prop.suggested_target_node_id;
  ELSE
    IF p_week_start IS NULL THEN RAISE EXCEPTION 'Week start required'; END IF;
    v_s := incident_suggest(p_proposal_id, p_week_start, p_reference_load, p_deviation_percent);
    IF NOT COALESCE((v_s->>'found')::boolean, false) THEN
      RAISE EXCEPTION 'No slot in week %', p_week_start;
    END IF;
    v_action := 'change';
    v_date := (v_s->>'date')::date;
    v_node := (v_s->>'node_id')::uuid;
  END IF;

  IF v_action = 'cancel' THEN
    PERFORM incident_apply_cancel(p_proposal_id, 'manager');
  ELSE
    -- Solo se reencamina si el nodo propuesto difiere del actual de la muestra en ese rol.
    IF v_node IS NOT DISTINCT FROM v_cur_node THEN v_node := NULL; END IF;
    IF v_date IS NULL AND v_node IS NULL THEN
      RAISE EXCEPTION 'Proposal has no actionable suggestion';
    END IF;
    PERFORM incident_apply_change(p_proposal_id, v_date, v_node, 'manager');
  END IF;

  v_status := incident_recompute_status(v_prop.unavailability_id);

  SELECT final_action, final_date, final_target_node_id INTO v_final
    FROM panelist_reassignment_proposal WHERE id = p_proposal_id;

  RETURN jsonb_build_object(
    'ok', true,
    'incident_status', v_status,
    'final_action', v_final.final_action,
    'final_date', v_final.final_date,
    'final_target_node_id', v_final.final_target_node_id);
END;
$$;

-- (3) set_incident_resolution.
CREATE OR REPLACE FUNCTION public.set_incident_resolution(p_unavailability_id uuid, p_text text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM panelist_unavailability WHERE id = p_unavailability_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unavailability % not found', p_unavailability_id; END IF;
  IF auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND v_account IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = auth.uid()) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;

  UPDATE panelist_unavailability
     SET final_resolution = p_text,
         updated_by = auth.uid(),
         updated_at = now()
   WHERE id = p_unavailability_id;
END;
$$;

-- (4) Arreglo de seguridad en la RPC legacy: el nodo destino debe ser de la misma cuenta que la propuesta
--     y de la misma ciudad que el nodo actual de la muestra en el lado afectado. Resto idéntico.
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
  v_cur_node uuid;
  v_cur_city uuid;
  v_tgt_city uuid;
  v_tgt_account uuid;
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
    PERFORM incident_recompute_status(v_prop.unavailability_id);
    RETURN;
  END IF;

  -- Nodo destino: misma cuenta que la propuesta y misma ciudad que el nodo actual de la muestra.
  IF p_final_target_node_id IS NOT NULL THEN
    SELECT CASE WHEN v_prop.affected_role = 'origin' THEN a.origin_node_id ELSE a.destination_node_id END
      INTO v_cur_node FROM allocation_plan_details a WHERE a.id = v_prop.allocation_plan_detail_id;
    SELECT n.city_id INTO v_cur_city FROM nodes n WHERE n.id = v_cur_node;
    SELECT n.city_id, n.account_id INTO v_tgt_city, v_tgt_account FROM nodes n WHERE n.id = p_final_target_node_id;
    IF v_tgt_account IS DISTINCT FROM v_prop.account_id
       OR v_tgt_city IS NULL OR v_tgt_city IS DISTINCT FROM v_cur_city THEN
      RAISE EXCEPTION 'Target node not allowed';
    END IF;
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
      SET original_fecha_programada = COALESCE(original_fecha_programada, fecha_programada),
          fecha_programada = p_final_date,
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
          original_fecha_programada = CASE
            WHEN p_final_date IS NOT NULL AND p_final_date IS DISTINCT FROM fecha_programada
            THEN COALESCE(original_fecha_programada, fecha_programada) ELSE original_fecha_programada END,
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

  -- El estado de la incidencia se recalcula (si no, se quedaria en pending_manager).
  PERFORM incident_recompute_status(v_prop.unavailability_id);
END;
$$;

-- (5) Permisos.
REVOKE ALL ON FUNCTION public.suggest_for_week(uuid, date, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.suggest_for_week(uuid, date, numeric, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_manager_decision(uuid, text, date, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_manager_decision(uuid, text, date, numeric, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.set_incident_resolution(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_incident_resolution(uuid, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_reassignment_proposal(uuid, text, uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_reassignment_proposal(uuid, text, uuid, date) TO authenticated, service_role;
-- Endurecimiento (heredadas): el bulk ya no lo llama nadie; list_reroute_candidates sigue para la web (plan 2).
REVOKE ALL ON FUNCTION public.apply_reassignment_proposals_bulk(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.list_reroute_candidates(uuid, text) FROM PUBLIC, anon;
