-- Motor de reasignación (B) — cambia suggested_reason de frases en español a CÓDIGOS
-- estables, para que la pantalla (subsistema C) los traduzca a los 4 idiomas.
-- Idéntica a la versión previa salvo los 6 literales de suggested_reason.
CREATE OR REPLACE FUNCTION public.generate_reassignment_proposals(p_unavailability_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_id uuid;
  v_panelist_id uuid;
  v_node_id uuid;
  v_city_id uuid;
  v_start date;
  v_end date;
  v_count integer := 0;
  r record;
  v_target_node uuid;
  v_shift_date date;
BEGIN
  -- Cargar la baja (solo si está activa)
  SELECT account_id, panelist_id, start_date, end_date
    INTO v_account_id, v_panelist_id, v_start, v_end
  FROM panelist_unavailability
  WHERE id = p_unavailability_id AND status = 'active';
  IF NOT FOUND THEN RETURN 0; END IF;

  SELECT node_id INTO v_node_id FROM panelists WHERE id = v_panelist_id;
  IF v_node_id IS NULL THEN RETURN 0; END IF;
  SELECT city_id INTO v_city_id FROM nodes WHERE id = v_node_id;

  -- Guarda multi-tenant: un usuario autenticado solo puede generar propuestas
  -- para su propia cuenta. El path service-role (edge function) tiene auth.uid()
  -- NULL y se permite; superadmin también.
  IF auth.uid() IS NOT NULL AND NOT is_superadmin() THEN
    DECLARE v_actor_account uuid;
    BEGIN
      SELECT account_id INTO v_actor_account FROM profiles WHERE id = auth.uid();
      IF v_actor_account IS DISTINCT FROM v_account_id THEN
        RAISE EXCEPTION 'Cross-tenant access denied';
      END IF;
    END;
  END IF;

  -- Idempotencia: borrar solo las propuestas 'pending' de esta baja; respetar confirmed/dismissed
  DELETE FROM panelist_reassignment_proposal
  WHERE unavailability_id = p_unavailability_id AND status = 'pending';

  -- ================= ENVÍOS (panelista = origen) =================
  FOR r IN
    SELECT apd.id, apd.fecha_programada, apd.status
    FROM allocation_plan_details apd
    WHERE apd.origin_node_id = v_node_id
      AND apd.fecha_programada BETWEEN v_start AND v_end
      AND apd.status NOT IN ('received','cancelled','invalid')
      AND NOT EXISTS (
        SELECT 1 FROM panelist_reassignment_proposal p
        WHERE p.unavailability_id = p_unavailability_id
          AND p.allocation_plan_detail_id = apd.id
          AND p.affected_role = 'origin'
          AND p.status IN ('confirmed','dismissed'))
  LOOP
    -- Nivel a: reencaminar a otro nodo de la misma ciudad con panelista disponible ese día.
    SELECT n.id INTO v_target_node
    FROM nodes n
    WHERE n.city_id = v_city_id
      AND n.id <> v_node_id
      AND is_node_available(n.id, r.fecha_programada)
    ORDER BY (SELECT count(*) FROM allocation_plan_details a2
              WHERE a2.origin_node_id = n.id AND a2.fecha_programada = r.fecha_programada) ASC, n.id
    LIMIT 1;

    IF v_target_node IS NOT NULL THEN
      INSERT INTO panelist_reassignment_proposal
        (account_id, unavailability_id, allocation_plan_detail_id, affected_role,
         sample_status_at_detection, suggested_action, suggested_target_node_id, suggested_reason)
      VALUES (v_account_id, p_unavailability_id, r.id, 'origin', r.status, 'reroute', v_target_node,
              'alt_node_same_city');
      v_count := v_count + 1; CONTINUE;
    END IF;

    -- Nivel b: desplazar a una fecha del mismo mes, fuera de la baja, con el nodo disponible.
    SELECT d::date INTO v_shift_date
    FROM generate_series(date_trunc('month', r.fecha_programada)::date,
                         (date_trunc('month', r.fecha_programada) + interval '1 month - 1 day')::date,
                         interval '1 day') AS d
    WHERE d::date NOT BETWEEN v_start AND v_end
      AND is_node_available(v_node_id, d::date)
    ORDER BY abs(d::date - r.fecha_programada), d::date
    LIMIT 1;

    IF v_shift_date IS NOT NULL THEN
      INSERT INTO panelist_reassignment_proposal
        (account_id, unavailability_id, allocation_plan_detail_id, affected_role,
         sample_status_at_detection, suggested_action, suggested_date, suggested_reason)
      VALUES (v_account_id, p_unavailability_id, r.id, 'origin', r.status, 'shift_date', v_shift_date,
              'shift_same_month');
      v_count := v_count + 1; CONTINUE;
    END IF;

    -- Nivel c: cancelar
    INSERT INTO panelist_reassignment_proposal
      (account_id, unavailability_id, allocation_plan_detail_id, affected_role,
       sample_status_at_detection, suggested_action, suggested_reason)
    VALUES (v_account_id, p_unavailability_id, r.id, 'origin', r.status, 'cancel',
            'no_alt_no_date');
    v_count := v_count + 1;
  END LOOP;

  -- ================= RECEPCIONES (panelista = destino) =================
  FOR r IN
    SELECT apd.id, apd.fecha_programada, apd.status
    FROM allocation_plan_details apd
    WHERE apd.destination_node_id = v_node_id
      AND apd.fecha_programada BETWEEN v_start AND v_end
      AND apd.status NOT IN ('received','cancelled','invalid')
      AND NOT EXISTS (
        SELECT 1 FROM panelist_reassignment_proposal p
        WHERE p.unavailability_id = p_unavailability_id
          AND p.allocation_plan_detail_id = apd.id
          AND p.affected_role = 'destination'
          AND p.status IN ('confirmed','dismissed'))
  LOOP
    IF r.status IN ('pending','notified') THEN
      -- No ha salido: reencaminar el destino a otro nodo con panelista disponible.
      SELECT n.id INTO v_target_node
      FROM nodes n
      WHERE n.city_id = v_city_id AND n.id <> v_node_id
        AND is_node_available(n.id, r.fecha_programada)
      ORDER BY n.id LIMIT 1;

      IF v_target_node IS NOT NULL THEN
        INSERT INTO panelist_reassignment_proposal
          (account_id, unavailability_id, allocation_plan_detail_id, affected_role,
           sample_status_at_detection, suggested_action, suggested_target_node_id, suggested_reason)
        VALUES (v_account_id, p_unavailability_id, r.id, 'destination', r.status, 'reroute', v_target_node,
                'reroute_reception');
        v_count := v_count + 1; CONTINUE;
      END IF;

      INSERT INTO panelist_reassignment_proposal
        (account_id, unavailability_id, allocation_plan_detail_id, affected_role,
         sample_status_at_detection, suggested_action, suggested_reason)
      VALUES (v_account_id, p_unavailability_id, r.id, 'destination', r.status, 'cancel',
              'no_alt_reception');
      v_count := v_count + 1;
    ELSE
      -- Ya salió (sent+): informativa, sin acción sobre el plan.
      INSERT INTO panelist_reassignment_proposal
        (account_id, unavailability_id, allocation_plan_detail_id, affected_role,
         sample_status_at_detection, suggested_action, suggested_reason)
      VALUES (v_account_id, p_unavailability_id, r.id, 'destination', r.status, 'none',
              'in_transit');
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_reassignment_proposals(uuid) TO authenticated;
