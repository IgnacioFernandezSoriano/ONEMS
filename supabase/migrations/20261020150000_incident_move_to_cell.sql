-- Incidencias de indisponibilidad: arrastrar una muestra a una casilla (nodo x semana) en la pantalla del manager.
--   incident_suggest_cell -> interna: elige el dia de esa semana en ese nodo (solo lectura).
--   suggest_for_cell      -> envoltorio publico (guarda multi-tenant), para previsualizar al soltar.
--   apply_manager_move    -> aplica el movimiento (mismo patron que apply_manager_decision).
-- Y reequilibrio de cualquier muestra del plan (sin linea de incidencia):
--   incident_suggest_sample_move (interna) / suggest_for_sample_move / apply_sample_move.
-- Dias candidatos: lunes..viernes de la semana elegida, >= hoy, que quepan en el nodo (incident_node_fits ya
-- excluye los dias en que el panelista de ese nodo no esta disponible, incluida la propia baja).
-- Reparto: primero el dia con menos muestras no canceladas del nodo (origen o destino), luego el mas temprano.

-- (0a) Carga semanal de un nodo sin contar una muestra (la que se mueve: no debe contarse dos veces). Interna.
CREATE OR REPLACE FUNCTION public.incident_node_week_load_excl(p_node_id uuid, p_date date, p_exclude_detail_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::int
    FROM allocation_plan_details a
   WHERE (a.origin_node_id = p_node_id OR a.destination_node_id = p_node_id)
     AND a.fecha_programada BETWEEN incident_week_start(p_date) AND incident_week_start(p_date) + 6
     AND a.status <> 'cancelled'
     AND a.id IS DISTINCT FROM p_exclude_detail_id;
$$;

-- (0b) Dia de la semana elegida para un nodo (compartido por las dos propuestas). Interna.
--      Mismo criterio que incident_node_fits (panelista disponible + carga semanal + 1 <= umbral), pero sin contar
--      la muestra que se mueve (p_exclude_detail_id).
CREATE OR REPLACE FUNCTION public.incident_pick_day_in_week(
  p_node_id uuid, p_week_start date, p_reference_load numeric, p_deviation_percent numeric,
  p_other_end_node_id uuid DEFAULT NULL, p_exclude_detail_id uuid DEFAULT NULL)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT g::date
    FROM generate_series(incident_week_start(p_week_start), incident_week_start(p_week_start) + 4, interval '1 day') g
   WHERE p_node_id IS NOT NULL AND p_week_start IS NOT NULL
     AND g::date >= current_date
     AND COALESCE(is_node_available(p_node_id, g::date), false)
     AND incident_node_week_load_excl(p_node_id, g::date, p_exclude_detail_id) + 1
         <= incident_saturation_threshold(p_reference_load, p_deviation_percent)
     -- Otro extremo de la muestra: solo disponibilidad (su carga no cambia). Sin panelista activo no bloquea.
     AND (p_other_end_node_id IS NULL
          OR NOT EXISTS (SELECT 1 FROM panelists p WHERE p.node_id = p_other_end_node_id AND p.status = 'active')
          OR COALESCE(is_node_available(p_other_end_node_id, g::date), false))
   ORDER BY (SELECT count(*) FROM allocation_plan_details a
              WHERE (a.origin_node_id = p_node_id OR a.destination_node_id = p_node_id)
                AND a.fecha_programada = g::date
                AND a.status <> 'cancelled'
                AND a.id IS DISTINCT FROM p_exclude_detail_id) ASC,
            g ASC
   LIMIT 1;
$$;

-- (1) Propuesta para una casilla. Motivos de found:false, en este orden:
--     not_found, not_pending, sample_not_movable, other_city, inactive_node, other_end, no_day.
CREATE OR REPLACE FUNCTION public.incident_suggest_cell(
  p_proposal_id uuid,
  p_node_id uuid,
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
  v_ref numeric := COALESCE(p_reference_load, 6);
  v_dev numeric := COALESCE(p_deviation_percent, 20);
  v_prop record;
  v_d record;
  v_node uuid;
  v_other uuid;
  v_city uuid;
  v_tgt_city uuid;
  v_tgt_account uuid;
  v_tgt_status text;
  v_day date;
  v_load integer;
BEGIN
  SELECT * INTO v_prop FROM panelist_reassignment_proposal WHERE id = p_proposal_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('found', false, 'reason', 'not_found'); END IF;

  -- Guarda multi-tenant: service role / triggers (auth.uid() NULL) y superadmin pasan.
  IF auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND v_prop.account_id IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = auth.uid()) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;

  IF v_prop.status <> 'pending' THEN RETURN jsonb_build_object('found', false, 'reason', 'not_pending'); END IF;

  SELECT * INTO v_d FROM allocation_plan_details WHERE id = v_prop.allocation_plan_detail_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('found', false, 'reason', 'not_found'); END IF;
  IF v_d.status NOT IN ('pending','notified') THEN
    RETURN jsonb_build_object('found', false, 'reason', 'sample_not_movable');
  END IF;

  IF v_prop.affected_role = 'origin' THEN
    v_node := v_d.origin_node_id;  v_other := v_d.destination_node_id;
  ELSE
    v_node := v_d.destination_node_id;  v_other := v_d.origin_node_id;
  END IF;

  -- Nunca a otra cuenta ni a otra ciudad (la del nodo actual de la muestra en el lado afectado).
  SELECT n.city_id INTO v_city FROM nodes n WHERE n.id = v_node;
  SELECT n.city_id, n.account_id, COALESCE(n.status, 'active') INTO v_tgt_city, v_tgt_account, v_tgt_status
    FROM nodes n WHERE n.id = p_node_id;
  IF v_tgt_account IS DISTINCT FROM v_d.account_id OR v_tgt_city IS NULL OR v_tgt_city IS DISTINCT FROM v_city THEN
    RETURN jsonb_build_object('found', false, 'reason', 'other_city');
  END IF;
  IF v_tgt_status <> 'active' THEN RETURN jsonb_build_object('found', false, 'reason', 'inactive_node'); END IF;

  -- Origen = destino no tiene sentido.
  IF p_node_id = v_other THEN RETURN jsonb_build_object('found', false, 'reason', 'other_end'); END IF;

  -- La muestra que se mueve no cuenta en la carga del destino (evita contarla dos veces en su propia semana).
  v_day := incident_pick_day_in_week(p_node_id, p_week_start, v_ref, v_dev, v_other, v_d.id);
  IF v_day IS NULL THEN RETURN jsonb_build_object('found', false, 'reason', 'no_day'); END IF;

  v_load := incident_node_week_load_excl(p_node_id, v_day, v_d.id) + 1;
  RETURN jsonb_build_object(
    'found', true,
    'date', v_day,
    'node_id', p_node_id,
    'node_code', (SELECT n.auto_id FROM nodes n WHERE n.id = p_node_id),
    'load_after', v_load,
    -- Mismos cortes que incident_suggest (rpc_get_node_load_by_period aplicado a la carga semanal).
    'saturation_level', CASE
       WHEN v_load > v_ref * (1 + 1.5 * v_dev / 100) THEN 'saturated'
       WHEN v_load > v_ref * (1 + v_dev / 100) THEN 'high'
       ELSE 'normal' END,
    'same_node', p_node_id = v_node);
END;
$$;

-- (2) suggest_for_cell: envoltorio publico con la misma guarda que suggest_for_week.
CREATE OR REPLACE FUNCTION public.suggest_for_cell(
  p_proposal_id uuid,
  p_node_id uuid,
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
  RETURN incident_suggest_cell(p_proposal_id, p_node_id, p_week_start, p_reference_load, p_deviation_percent);
END;
$$;

-- (3) apply_manager_move: mover la muestra de una linea pendiente a la casilla (nodo x semana).
CREATE OR REPLACE FUNCTION public.apply_manager_move(
  p_proposal_id uuid,
  p_node_id uuid,
  p_week_start date,
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
  v_s jsonb;
  v_date date;
  v_same boolean;
  v_status text;
  v_final record;
BEGIN
  IF p_node_id IS NULL OR p_week_start IS NULL THEN RAISE EXCEPTION 'Node and week required'; END IF;

  -- Bloquea la linea: dos soltadas simultaneas se serializan y la segunda ve 'manager_resolved'.
  SELECT * INTO v_prop FROM panelist_reassignment_proposal WHERE id = p_proposal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proposal % not found', p_proposal_id; END IF;

  -- Guarda multi-tenant antes de revelar nada del estado.
  IF auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND v_prop.account_id IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = auth.uid()) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;

  IF v_prop.status <> 'pending' THEN
    RAISE EXCEPTION 'Proposal % already %', p_proposal_id, v_prop.status;
  END IF;

  v_s := incident_suggest_cell(p_proposal_id, p_node_id, p_week_start, p_reference_load, p_deviation_percent);
  IF NOT COALESCE((v_s->>'found')::boolean, false) THEN
    RAISE EXCEPTION 'Cannot move: %', v_s->>'reason';
  END IF;
  v_date := (v_s->>'date')::date;
  v_same := (v_s->>'same_node')::boolean;

  SELECT * INTO v_d FROM allocation_plan_details WHERE id = v_prop.allocation_plan_detail_id;
  IF v_same AND v_date IS NOT DISTINCT FROM v_d.fecha_programada THEN
    RAISE EXCEPTION 'Nothing to change';
  END IF;

  -- Mismo nodo: solo cambia la fecha. Otro nodo: reencamina (y la fecha si difiere).
  PERFORM incident_apply_change(p_proposal_id, v_date, CASE WHEN v_same THEN NULL ELSE p_node_id END, 'manager');

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

-- (4) Reequilibrio: mover CUALQUIER muestra del plan desde la casilla (p_from_node_id x semana) a otra.
--     Lado a cambiar: aquel en que la muestra tiene hoy p_from_node_id (origen primero). Motivos de found:false,
--     en este orden: not_found, not_in_cell, sample_not_movable, has_incident_line (alguna linea pendiente, de cualquier lado:
--     la web debe usar apply_manager_move), other_city, inactive_node, other_end, no_day. Interna.
CREATE OR REPLACE FUNCTION public.incident_suggest_sample_move(
  p_detail_id uuid,
  p_from_node_id uuid,
  p_to_node_id uuid,
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
  v_ref numeric := COALESCE(p_reference_load, 6);
  v_dev numeric := COALESCE(p_deviation_percent, 20);
  v_d record;
  v_side text;
  v_other uuid;
  v_city uuid;
  v_tgt_city uuid;
  v_tgt_account uuid;
  v_tgt_status text;
  v_day date;
  v_load integer;
BEGIN
  SELECT * INTO v_d FROM allocation_plan_details WHERE id = p_detail_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('found', false, 'reason', 'not_found'); END IF;

  -- Guarda multi-tenant: service role / triggers (auth.uid() NULL) y superadmin pasan.
  IF auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND v_d.account_id IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = auth.uid()) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;

  IF p_from_node_id IS NOT NULL AND v_d.origin_node_id = p_from_node_id THEN
    v_side := 'origin';  v_other := v_d.destination_node_id;
  ELSIF p_from_node_id IS NOT NULL AND v_d.destination_node_id = p_from_node_id THEN
    v_side := 'destination';  v_other := v_d.origin_node_id;
  ELSE
    RETURN jsonb_build_object('found', false, 'reason', 'not_in_cell');
  END IF;

  IF v_d.status NOT IN ('pending','notified') THEN
    RETURN jsonb_build_object('found', false, 'reason', 'sample_not_movable');
  END IF;

  -- Cualquier linea pendiente (de cualquier lado): mover la muestra la dejaria obsoleta.
  IF EXISTS (SELECT 1 FROM panelist_reassignment_proposal pr
              WHERE pr.allocation_plan_detail_id = v_d.id AND pr.status = 'pending') THEN
    RETURN jsonb_build_object('found', false, 'reason', 'has_incident_line');
  END IF;

  -- Nunca a otra cuenta ni a otra ciudad (la del nodo de la casilla de origen).
  SELECT n.city_id INTO v_city FROM nodes n WHERE n.id = p_from_node_id;
  SELECT n.city_id, n.account_id, COALESCE(n.status, 'active') INTO v_tgt_city, v_tgt_account, v_tgt_status
    FROM nodes n WHERE n.id = p_to_node_id;
  IF v_tgt_account IS DISTINCT FROM v_d.account_id OR v_tgt_city IS NULL OR v_tgt_city IS DISTINCT FROM v_city THEN
    RETURN jsonb_build_object('found', false, 'reason', 'other_city');
  END IF;
  IF v_tgt_status <> 'active' THEN RETURN jsonb_build_object('found', false, 'reason', 'inactive_node'); END IF;

  IF p_to_node_id = v_other THEN RETURN jsonb_build_object('found', false, 'reason', 'other_end'); END IF;

  v_day := incident_pick_day_in_week(p_to_node_id, p_week_start, v_ref, v_dev, v_other, v_d.id);
  IF v_day IS NULL THEN RETURN jsonb_build_object('found', false, 'reason', 'no_day'); END IF;

  v_load := incident_node_week_load_excl(p_to_node_id, v_day, v_d.id) + 1;
  RETURN jsonb_build_object(
    'found', true,
    'date', v_day,
    'node_id', p_to_node_id,
    'node_code', (SELECT n.auto_id FROM nodes n WHERE n.id = p_to_node_id),
    'load_after', v_load,
    'saturation_level', CASE
       WHEN v_load > v_ref * (1 + 1.5 * v_dev / 100) THEN 'saturated'
       WHEN v_load > v_ref * (1 + v_dev / 100) THEN 'high'
       ELSE 'normal' END,
    'same_node', p_to_node_id = p_from_node_id,
    'side', v_side);
END;
$$;

-- (5) suggest_for_sample_move: envoltorio publico (guarda por la cuenta de la muestra).
CREATE OR REPLACE FUNCTION public.suggest_for_sample_move(
  p_detail_id uuid,
  p_from_node_id uuid,
  p_to_node_id uuid,
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
  SELECT account_id INTO v_account FROM allocation_plan_details WHERE id = p_detail_id;
  IF FOUND AND auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND v_account IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = auth.uid()) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;
  RETURN incident_suggest_sample_move(p_detail_id, p_from_node_id, p_to_node_id, p_week_start,
                                      p_reference_load, p_deviation_percent);
END;
$$;

-- (5b) Avisos de un cambio a los panelistas de antes y despues (generaliza incident_enqueue_revert de
--      20261020130400). recipient_role relativo al estado nuevo: 'sender'/'receiver' si sigue en la muestra;
--      'former_sender'/'former_receiver' si ya no. Un aviso por panelista (gana el papel del estado nuevo).
--      Solo si la fecha antigua o la nueva cae en la semana actual; respeta onems.suppress_notifications.
--      Panelistas siempre de la cuenta de la muestra. Interna.
CREATE OR REPLACE FUNCTION public.incident_enqueue_change_full(
  p_detail_id uuid, p_change text, p_old_date date, p_old_origin_node_id uuid, p_old_destination_node_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_start date := date_trunc('week', current_date)::date;
  v_d record;
  v_dest record;
  v_payload jsonb;
  v_count integer := 0;
  r record;
BEGIN
  IF p_change IS NULL OR p_change NOT IN ('shift_date','reroute_origin','reroute_destination','cancel','revert') THEN
    RAISE EXCEPTION 'Unknown plan change %', p_change;
  END IF;
  IF COALESCE(current_setting('onems.suppress_notifications', true), '') = 'on' THEN RETURN 0; END IF;

  SELECT a.id, a.account_id, a.fecha_programada, a.origin_node_id, a.destination_node_id,
         no.auto_id AS origin_code, nd.auto_id AS destination_code,
         pr.description AS product_description, ca.name AS carrier_name
    INTO v_d
    FROM allocation_plan_details a
    JOIN nodes no ON no.id = a.origin_node_id
    JOIN nodes nd ON nd.id = a.destination_node_id
    LEFT JOIN allocation_plans ap ON ap.id = a.plan_id
    LEFT JOIN products pr ON pr.id = ap.product_id
    LEFT JOIN carriers ca ON ca.id = ap.carrier_id
   WHERE a.id = p_detail_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  IF NOT (COALESCE(p_old_date BETWEEN v_week_start AND v_week_start + 6, false)
          OR COALESCE(v_d.fecha_programada BETWEEN v_week_start AND v_week_start + 6, false)) THEN
    RETURN 0;
  END IF;

  SELECT p.id, p.name, p.address_line1, p.address_line2, p.postal_code, p.address_city
    INTO v_dest FROM panelists p
   WHERE p.id = incident_node_panelist(v_d.destination_node_id, v_d.account_id) AND p.account_id = v_d.account_id;

  v_payload := jsonb_build_object(
    'detail_id', v_d.id,
    'change', p_change,
    'old_date', p_old_date,
    'new_date', v_d.fecha_programada,
    'scheduled_date', v_d.fecha_programada,
    'origin_node_code', v_d.origin_code,
    'destination_node_code', v_d.destination_code,
    'origin_panelist_name', (SELECT p.name FROM panelists p
                               WHERE p.id = incident_node_panelist(v_d.origin_node_id, v_d.account_id)
                                 AND p.account_id = v_d.account_id),
    'destination_panelist_name', v_dest.name,
    'destination_address', jsonb_build_object(
      'address_line1', v_dest.address_line1,
      'address_line2', v_dest.address_line2,
      'postal_code', v_dest.postal_code,
      'city', v_dest.address_city),
    'product_description', v_d.product_description,
    'carrier_name', v_d.carrier_name);

  FOR r IN
    SELECT DISTINCT ON (x.panelist_id) x.panelist_id, x.role
      FROM (
        SELECT incident_node_panelist(v_d.origin_node_id, v_d.account_id) AS panelist_id,
               'sender'::text AS role, 1 AS prio
        UNION ALL
        SELECT incident_node_panelist(v_d.destination_node_id, v_d.account_id),
               'receiver', 2
        UNION ALL
        SELECT incident_node_panelist(p_old_origin_node_id, v_d.account_id),
               'former_sender', 3
        UNION ALL
        SELECT incident_node_panelist(p_old_destination_node_id, v_d.account_id),
               'former_receiver', 4) x
      JOIN panelists p ON p.id = x.panelist_id AND p.account_id = v_d.account_id
     WHERE x.panelist_id IS NOT NULL
     ORDER BY x.panelist_id, x.prio
  LOOP
    INSERT INTO panelist_notification (account_id, panelist_id, kind, payload)
    VALUES (v_d.account_id, r.panelist_id, 'plan_change_this_week', v_payload || jsonb_build_object('recipient_role', r.role));
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- (5c) incident_enqueue_revert pasa a ser un envoltorio fino (misma firma y comportamiento).
CREATE OR REPLACE FUNCTION public.incident_enqueue_revert(
  p_detail_id uuid, p_old_date date, p_old_origin_node_id uuid, p_old_destination_node_id uuid)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT incident_enqueue_change_full(p_detail_id, 'revert', p_old_date, p_old_origin_node_id, p_old_destination_node_id);
$$;

-- (6) apply_sample_move: aplica el reequilibrio en UNA sola sentencia (mismas columnas que incident_apply_change;
--     reassigned_at cambia en el mismo UPDATE, asi el trigger de refresco por cambio de plan lo ignora).
CREATE OR REPLACE FUNCTION public.apply_sample_move(
  p_detail_id uuid,
  p_from_node_id uuid,
  p_to_node_id uuid,
  p_week_start date,
  p_reference_load numeric DEFAULT 6,
  p_deviation_percent numeric DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_d record;
  v_s jsonb;
  v_date date;
  v_same boolean;
  v_side text;
  v_date_changed boolean;
  v_new_origin boolean;
  v_new_dest boolean;
  v_pan_id uuid;
  v_pan_name text;
BEGIN
  IF p_from_node_id IS NULL OR p_to_node_id IS NULL OR p_week_start IS NULL THEN
    RAISE EXCEPTION 'Nodes and week required';
  END IF;

  -- Bloquea la muestra: dos soltadas simultaneas se serializan.
  SELECT * INTO v_d FROM allocation_plan_details WHERE id = p_detail_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sample % not found', p_detail_id; END IF;

  -- Guarda multi-tenant antes de revelar nada del estado.
  IF v_actor IS NOT NULL AND NOT is_superadmin()
     AND v_d.account_id IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = v_actor) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;

  v_s := incident_suggest_sample_move(p_detail_id, p_from_node_id, p_to_node_id, p_week_start,
                                      p_reference_load, p_deviation_percent);
  IF NOT COALESCE((v_s->>'found')::boolean, false) THEN
    RAISE EXCEPTION 'Cannot move: %', v_s->>'reason';
  END IF;
  v_date := (v_s->>'date')::date;
  v_same := (v_s->>'same_node')::boolean;
  v_side := v_s->>'side';
  v_date_changed := v_date IS DISTINCT FROM v_d.fecha_programada;
  IF v_same AND NOT v_date_changed THEN RAISE EXCEPTION 'Nothing to change'; END IF;

  v_new_origin := NOT v_same AND v_side = 'origin';
  v_new_dest := NOT v_same AND v_side = 'destination';
  IF NOT v_same THEN
    SELECT p.id, p.name INTO v_pan_id, v_pan_name FROM panelists p
     WHERE p.id = incident_node_panelist(p_to_node_id, v_d.account_id) AND p.account_id = v_d.account_id;
  END IF;

  UPDATE allocation_plan_details
     SET original_origin_node_id = CASE WHEN v_new_origin
           THEN COALESCE(original_origin_node_id, origin_node_id) ELSE original_origin_node_id END,
         origin_node_id = CASE WHEN v_new_origin THEN p_to_node_id ELSE origin_node_id END,
         origin_panelist_name = CASE WHEN v_new_origin THEN v_pan_name ELSE origin_panelist_name END,
         origin_panelist_id = CASE WHEN v_new_origin AND origin_panelist_id IS NOT NULL
           THEN v_pan_id ELSE origin_panelist_id END,
         original_destination_node_id = CASE WHEN v_new_dest
           THEN COALESCE(original_destination_node_id, destination_node_id) ELSE original_destination_node_id END,
         destination_node_id = CASE WHEN v_new_dest THEN p_to_node_id ELSE destination_node_id END,
         destination_panelist_name = CASE WHEN v_new_dest THEN v_pan_name ELSE destination_panelist_name END,
         destination_panelist_id = CASE WHEN v_new_dest AND destination_panelist_id IS NOT NULL
           THEN v_pan_id ELSE destination_panelist_id END,
         original_fecha_programada = CASE WHEN v_date_changed
           THEN COALESCE(original_fecha_programada, fecha_programada) ELSE original_fecha_programada END,
         fecha_programada = v_date,
         status = CASE WHEN status = 'notified' THEN 'pending' ELSE status END,
         -- Una muestra ya movida por una baja conserva ese motivo.
         reassignment_reason = CASE WHEN reassignment_reason = 'panelist_unavailable'
           THEN reassignment_reason ELSE 'rebalancing' END,
         reassigned_at = now(),
         reassigned_by = v_actor,
         updated_at = now()
   WHERE id = v_d.id;

  -- Avisos a los panelistas de antes y despues (incluido el que deja la muestra: former_sender/former_receiver).
  -- v_d conserva el estado previo al UPDATE.
  PERFORM incident_enqueue_change_full(
    v_d.id,
    CASE WHEN v_same THEN 'shift_date' WHEN v_side = 'origin' THEN 'reroute_origin' ELSE 'reroute_destination' END,
    v_d.fecha_programada, v_d.origin_node_id, v_d.destination_node_id);

  RETURN jsonb_build_object('ok', true, 'date', v_date, 'node_id', p_to_node_id, 'side', v_side);
END;
$$;

-- (7) Permisos. Internas (incident_pick_day_in_week, incident_suggest_cell, incident_suggest_sample_move): no
--     ejecutables por anon/authenticated. Las dos propuestas internas llevan GRANT a service_role, igual que
--     incident_suggest; el helper de dia no (como incident_find_shift_date). La web usa los envoltorios.
REVOKE ALL ON FUNCTION public.incident_node_week_load_excl(uuid, date, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_pick_day_in_week(uuid, date, numeric, numeric, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_enqueue_change_full(uuid, text, date, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_enqueue_revert(uuid, date, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_suggest_cell(uuid, uuid, date, numeric, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.incident_suggest_cell(uuid, uuid, date, numeric, numeric) TO service_role;
REVOKE ALL ON FUNCTION public.incident_suggest_sample_move(uuid, uuid, uuid, date, numeric, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.incident_suggest_sample_move(uuid, uuid, uuid, date, numeric, numeric) TO service_role;
REVOKE ALL ON FUNCTION public.suggest_for_sample_move(uuid, uuid, uuid, date, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.suggest_for_sample_move(uuid, uuid, uuid, date, numeric, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_sample_move(uuid, uuid, uuid, date, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_sample_move(uuid, uuid, uuid, date, numeric, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.suggest_for_cell(uuid, uuid, date, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.suggest_for_cell(uuid, uuid, date, numeric, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_manager_move(uuid, uuid, date, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_manager_move(uuid, uuid, date, numeric, numeric) TO authenticated, service_role;
