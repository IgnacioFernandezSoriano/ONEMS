-- Incidencias de indisponibilidad: motor de resolucion automatica (sustituye a generate_reassignment_proposals).
-- Orden por muestra afectada: (1) retrasar en el mismo nodo dentro del mes, (2) otro nodo de la ciudad sin
-- saturar en la misma fecha, (2b) otro nodo en otra fecha laborable del mes (mas cercana primero); si nada,
-- la linea queda 'pending' con la mejor propuesta para el manager (incident_suggest).
-- Siempre aditivo e idempotente: no toca lineas auto_resolved/manager_resolved/info; retira las 'pending'
-- que ya no aplican; crea lineas solo para muestras sin linea en ese rol.
-- Los cambios del plan y los avisos los hacen incident_apply_change/incident_apply_cancel (Tarea 3).

-- (0) Motor viejo fuera. El trigger tg_generate_proposals_on_unavailability aun lo llama (lo sustituye la
--     Tarea 6); su EXCEPTION WHEN OTHERS lo convierte en WARNING.
DROP FUNCTION IF EXISTS public.generate_reassignment_proposals(uuid);

-- (1) Nodo alternativo para una muestra: incident_find_node + nunca el nodo del otro extremo de la muestra
--     (evita origen = destino al reencaminar una muestra intra-ciudad). Interna.
CREATE OR REPLACE FUNCTION public.incident_find_node_for_sample(
  p_city_id uuid, p_exclude_node_id uuid, p_other_end_node_id uuid, p_date date,
  p_reference_load numeric, p_deviation_percent numeric)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT n.id
    FROM nodes n
    JOIN cities c ON c.id = n.city_id AND c.account_id = n.account_id
   WHERE n.city_id = p_city_id
     AND n.id IS DISTINCT FROM p_exclude_node_id
     AND n.id IS DISTINCT FROM p_other_end_node_id
     AND COALESCE(n.status, 'active') = 'active'
     AND incident_node_fits(n.id, p_date, p_reference_load, p_deviation_percent)
   ORDER BY incident_node_week_load(n.id, p_date) ASC, n.auto_id ASC
   LIMIT 1;
$$;

-- (2) Propuesta para el manager (solo lectura).
--     Dias candidatos: lunes..viernes, > corte, >= hoy. Corte = LEAST(fin de baja, fin del mes de la muestra):
--     el motor ya agoto el mes de la muestra; fuera de el se ofrecen tambien otros nodos aunque la baja siga.
--     Sin semana: desde el dia siguiente al corte hasta fecha + 56 dias (8 semanas). Con semana: solo esa
--     semana (se normaliza a su lunes), sin limite de horizonte (lo elige el manager).
--     Por dia: mismo nodo si cabe; si no, el nodo menos cargado de la ciudad. Primer dia con opcion gana.
CREATE OR REPLACE FUNCTION public.incident_suggest(
  p_proposal_id uuid,
  p_week_start date DEFAULT NULL,
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
  v_end date;
  v_node uuid;
  v_other uuid;
  v_city uuid;
  v_cutoff date;
  v_from date;
  v_to date;
  v_day date;
  v_pick uuid;
  v_load integer;
BEGIN
  SELECT * INTO v_prop FROM panelist_reassignment_proposal WHERE id = p_proposal_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('found', false); END IF;

  -- Guarda multi-tenant: service role / triggers (auth.uid() NULL) y superadmin pasan.
  IF auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND v_prop.account_id IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = auth.uid()) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;

  SELECT * INTO v_d FROM allocation_plan_details WHERE id = v_prop.allocation_plan_detail_id;
  IF NOT FOUND OR v_d.fecha_programada IS NULL THEN RETURN jsonb_build_object('found', false); END IF;
  SELECT u.end_date INTO v_end FROM panelist_unavailability u WHERE u.id = v_prop.unavailability_id;

  IF v_prop.affected_role = 'origin' THEN
    v_node := v_d.origin_node_id;  v_other := v_d.destination_node_id;
  ELSE
    v_node := v_d.destination_node_id;  v_other := v_d.origin_node_id;
  END IF;
  SELECT n.city_id INTO v_city FROM nodes n WHERE n.id = v_node;

  v_cutoff := LEAST(COALESCE(v_end, v_d.fecha_programada),
                    (date_trunc('month', v_d.fecha_programada) + interval '1 month - 1 day')::date);
  IF p_week_start IS NULL THEN
    v_from := GREATEST(v_cutoff + 1, current_date);
    v_to := v_d.fecha_programada + 56;
  ELSE
    v_from := GREATEST(incident_week_start(p_week_start), v_cutoff + 1, current_date);
    v_to := incident_week_start(p_week_start) + 4;
  END IF;

  FOR v_day IN
    SELECT g::date FROM generate_series(v_from, v_to, interval '1 day') g
     WHERE extract(isodow FROM g) BETWEEN 1 AND 5
     ORDER BY g
  LOOP
    IF incident_node_fits(v_node, v_day, v_ref, v_dev) THEN
      v_pick := v_node;
    ELSE
      v_pick := incident_find_node_for_sample(v_city, v_node, v_other, v_day, v_ref, v_dev);
    END IF;
    IF v_pick IS NOT NULL THEN
      v_load := incident_node_week_load(v_pick, v_day) + 1;
      RETURN jsonb_build_object(
        'found', true,
        'date', v_day,
        'node_id', v_pick,
        'node_code', (SELECT n.auto_id FROM nodes n WHERE n.id = v_pick),
        'load_after', v_load,
        -- Mismos cortes que rpc_get_node_load_by_period, aplicados a la carga semanal.
        'saturation_level', CASE
           WHEN v_load > v_ref * (1 + 1.5 * v_dev / 100) THEN 'saturated'
           WHEN v_load > v_ref * (1 + v_dev / 100) THEN 'high'
           ELSE 'normal' END);
    END IF;
  END LOOP;

  RETURN jsonb_build_object('found', false);
END;
$$;

-- (3) Estado de la incidencia a partir de sus lineas. Interna (la llaman el motor y los RPC del manager).
CREATE OR REPLACE FUNCTION public.incident_recompute_status(p_unavailability_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c record;
  v_status text;
  v_summary text;
  v_review text;
BEGIN
  SELECT count(*) FILTER (WHERE status IN ('auto_resolved','manager_resolved') AND final_action = 'shift_date') AS n_shift,
         count(*) FILTER (WHERE status IN ('auto_resolved','manager_resolved') AND final_action = 'reroute') AS n_reroute,
         count(*) FILTER (WHERE status IN ('auto_resolved','manager_resolved') AND final_action = 'cancel') AS n_cancel,
         count(*) FILTER (WHERE status = 'info') AS n_info,
         count(*) FILTER (WHERE status = 'pending') AS n_pending,
         count(*) FILTER (WHERE status = 'manager_resolved') AS n_manager
    INTO c
    FROM panelist_reassignment_proposal
   WHERE unavailability_id = p_unavailability_id;

  v_status := CASE WHEN c.n_pending > 0 THEN 'pending_manager'
                   WHEN c.n_manager > 0 THEN 'resolved'
                   ELSE 'auto_resolved' END;
  v_summary := format('shift=%s;reroute=%s;cancel=%s;info=%s;pending=%s',
                      c.n_shift, c.n_reroute, c.n_cancel, c.n_info, c.n_pending);
  v_review := CASE WHEN v_status = 'pending_manager' THEN 'pending_review' ELSE 'reviewed' END;

  -- Solo escribe si algo cambia (no reescribe resolved_at en llamadas repetidas).
  UPDATE panelist_unavailability u
     SET incident_status = v_status,
         auto_summary = v_summary,
         review_status = v_review,
         resolved_at = CASE WHEN v_status = 'pending_manager' THEN NULL
                            WHEN u.incident_status = v_status AND u.resolved_at IS NOT NULL THEN u.resolved_at
                            ELSE now() END
   WHERE u.id = p_unavailability_id
     AND (u.incident_status IS DISTINCT FROM v_status
          OR u.auto_summary IS DISTINCT FROM v_summary
          OR u.review_status IS DISTINCT FROM v_review
          OR (v_status = 'pending_manager') <> (u.resolved_at IS NULL));

  RETURN v_status;
END;
$$;

-- (4) Motor. Devuelve el numero de lineas nuevas creadas.
CREATE OR REPLACE FUNCTION public.resolve_unavailability_incident(
  p_unavailability_id uuid,
  p_reference_load numeric DEFAULT 6,
  p_deviation_percent numeric DEFAULT 20)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ref numeric := COALESCE(p_reference_load, 6);
  v_dev numeric := COALESCE(p_deviation_percent, 20);
  v_u record;
  v_node uuid;
  v_city uuid;
  v_count integer := 0;
  r record;
  v_d record;
  v_role_node uuid;
  v_other uuid;
  v_date date;
  v_target uuid;
  v_day date;
  v_line uuid;
  v_applied boolean;
  v_s jsonb;
  v_found boolean;
  v_s_node uuid;
BEGIN
  SELECT * INTO v_u FROM panelist_unavailability WHERE id = p_unavailability_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  -- Guarda multi-tenant: service role / triggers (auth.uid() NULL) y superadmin pasan.
  IF auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND v_u.account_id IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = auth.uid()) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;

  IF v_u.status IS DISTINCT FROM 'active' THEN RETURN 0; END IF;

  -- Nodo del panelista de baja (solo si sigue activo: un panelista inactivo no atiende el nodo).
  SELECT p.node_id INTO v_node FROM panelists p WHERE p.id = v_u.panelist_id AND p.status = 'active';
  SELECT n.city_id INTO v_city FROM nodes n WHERE n.id = v_node;

  -- (a) Retirar lineas 'pending' que ya no aplican (muestra fuera de la baja, de otro nodo en ese rol,
  --     o que ya no es pending/notified). Las resueltas e informativas no se tocan.
  DELETE FROM panelist_reassignment_proposal pr
   USING allocation_plan_details a
   WHERE pr.unavailability_id = p_unavailability_id
     AND pr.status = 'pending'
     AND a.id = pr.allocation_plan_detail_id
     AND NOT COALESCE(
           v_node IS NOT NULL
           AND a.fecha_programada BETWEEN v_u.start_date AND v_u.end_date
           AND a.status IN ('pending','notified')
           AND (CASE WHEN pr.affected_role = 'origin' THEN a.origin_node_id ELSE a.destination_node_id END) = v_node,
           false);

  -- (b)+(c) Muestras afectadas sin linea en ese rol. Orden determinista: los cambios aplicados alteran el
  --     plan al momento y el reparto (por dias y por nodos) lee el estado real.
  IF v_node IS NOT NULL THEN
    FOR r IN
      SELECT q.id, q.role FROM (
        SELECT a.id, 'origin'::text AS role, a.fecha_programada
          FROM allocation_plan_details a
         WHERE a.origin_node_id = v_node
           AND a.account_id = v_u.account_id
           AND a.fecha_programada BETWEEN v_u.start_date AND v_u.end_date
           AND a.status IN ('pending','notified','sent','received')
        UNION ALL
        SELECT a.id, 'destination'::text, a.fecha_programada
          FROM allocation_plan_details a
         WHERE a.destination_node_id = v_node
           AND a.account_id = v_u.account_id
           AND a.fecha_programada BETWEEN v_u.start_date AND v_u.end_date
           AND a.status IN ('pending','notified','sent','received')) q
       WHERE NOT EXISTS (SELECT 1 FROM panelist_reassignment_proposal pr
                          WHERE pr.unavailability_id = p_unavailability_id
                            AND pr.allocation_plan_detail_id = q.id
                            AND pr.affected_role = q.role)
       ORDER BY q.fecha_programada, q.id, q.role DESC  -- origin antes que destination
    LOOP
      BEGIN
        -- Releer: una linea anterior de esta misma pasada puede haber movido la muestra.
        SELECT * INTO v_d FROM allocation_plan_details WHERE id = r.id AND account_id = v_u.account_id FOR UPDATE;
        IF NOT FOUND THEN CONTINUE; END IF;
        IF r.role = 'origin' THEN
          v_role_node := v_d.origin_node_id;  v_other := v_d.destination_node_id;
        ELSE
          v_role_node := v_d.destination_node_id;  v_other := v_d.origin_node_id;
        END IF;
        IF v_role_node IS DISTINCT FROM v_node
           OR NOT COALESCE(v_d.fecha_programada BETWEEN v_u.start_date AND v_u.end_date, false) THEN
          CONTINUE;
        END IF;

        -- Ya salida / recibida: informativa, no bloquea.
        IF v_d.status IN ('sent','received') THEN
          INSERT INTO panelist_reassignment_proposal
            (account_id, unavailability_id, allocation_plan_detail_id, affected_role, sample_status_at_detection,
             suggested_action, suggested_reason, status, final_action)
          VALUES (v_u.account_id, p_unavailability_id, v_d.id, r.role, v_d.status,
                  'none', CASE WHEN r.role = 'destination' AND v_d.status = 'sent' THEN 'in_transit' ELSE 'already_sent' END,
                  'info', 'none');
          v_count := v_count + 1;
          CONTINUE;
        END IF;
        -- cancelled / incident: sin linea.
        IF v_d.status NOT IN ('pending','notified') THEN CONTINUE; END IF;

        -- Paso 1: retrasar en el mismo nodo (nunca a una fecha pasada).
        v_target := NULL;
        v_date := incident_find_shift_date(v_node, GREATEST(v_u.end_date, current_date - 1),
                                           v_d.fecha_programada, v_ref, v_dev);
        IF v_date IS NULL THEN
          -- Paso 2: otro nodo de la ciudad, misma fecha.
          v_target := incident_find_node_for_sample(v_city, v_node, v_other, v_d.fecha_programada, v_ref, v_dev);
          IF v_target IS NULL THEN
            -- Paso 2b: otro nodo en otra fecha laborable del mes de la muestra, la mas cercana primero.
            FOR v_day IN
              SELECT g::date
                FROM generate_series(date_trunc('month', v_d.fecha_programada)::date,
                                     (date_trunc('month', v_d.fecha_programada) + interval '1 month - 1 day')::date,
                                     interval '1 day') g
               WHERE extract(isodow FROM g) BETWEEN 1 AND 5
                 AND g::date <> v_d.fecha_programada
                 AND g::date >= current_date
               ORDER BY abs(g::date - v_d.fecha_programada), g
            LOOP
              v_target := incident_find_node_for_sample(v_city, v_node, v_other, v_day, v_ref, v_dev);
              IF v_target IS NOT NULL THEN v_date := v_day; EXIT; END IF;
            END LOOP;
          END IF;
        END IF;

        -- La linea nace 'pending' con la decision del motor; incident_apply_change la pasa a auto_resolved.
        INSERT INTO panelist_reassignment_proposal
          (account_id, unavailability_id, allocation_plan_detail_id, affected_role, sample_status_at_detection,
           suggested_action, suggested_target_node_id, suggested_date, suggested_reason)
        VALUES (v_u.account_id, p_unavailability_id, v_d.id, r.role, v_d.status,
                CASE WHEN v_target IS NOT NULL THEN 'reroute' WHEN v_date IS NOT NULL THEN 'shift_date' ELSE 'cancel' END,
                v_target, v_date,
                CASE WHEN v_target IS NOT NULL THEN 'alt_node_same_city'
                     WHEN v_date IS NOT NULL THEN 'shift_same_month'
                     ELSE 'no_slot_8_weeks' END)
        RETURNING id INTO v_line;
        v_count := v_count + 1;

        v_applied := false;
        IF v_date IS NOT NULL OR v_target IS NOT NULL THEN
          BEGIN
            PERFORM incident_apply_change(v_line, v_date, v_target, 'auto');
            v_applied := true;
          EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'resolve_unavailability_incident: no se pudo aplicar la linea % (muestra %): %',
              v_line, v_d.id, SQLERRM;
          END;
        END IF;

        -- Sin solucion automatica: queda pendiente con la mejor propuesta para el manager.
        IF NOT v_applied THEN
          BEGIN
            v_s := incident_suggest(v_line, NULL, v_ref, v_dev);
            v_found := COALESCE((v_s->>'found')::boolean, false);
            v_s_node := CASE WHEN v_found THEN (v_s->>'node_id')::uuid END;
            UPDATE panelist_reassignment_proposal
               SET suggested_action = CASE WHEN NOT v_found THEN 'cancel'
                                           WHEN v_s_node = v_node THEN 'shift_date' ELSE 'reroute' END,
                   suggested_date = CASE WHEN v_found THEN (v_s->>'date')::date END,
                   suggested_target_node_id = CASE WHEN v_found AND v_s_node <> v_node THEN v_s_node END,
                   suggested_reason = CASE WHEN NOT v_found THEN 'no_slot_8_weeks'
                                           WHEN v_s_node = v_node THEN 'shift_later_week' ELSE 'alt_node_later_week' END,
                   updated_at = now()
             WHERE id = v_line;
          EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'resolve_unavailability_incident: sin propuesta para la linea %: %', v_line, SQLERRM;
          END;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'resolve_unavailability_incident: muestra % rol % omitida: %', r.id, r.role, SQLERRM;
      END;
    END LOOP;
  END IF;

  -- (d) Estado de la incidencia.
  PERFORM incident_recompute_status(p_unavailability_id);
  RETURN v_count;
END;
$$;

-- (5) Permisos.
REVOKE ALL ON FUNCTION public.incident_find_node_for_sample(uuid, uuid, uuid, date, numeric, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_recompute_status(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_suggest(uuid, date, numeric, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.incident_suggest(uuid, date, numeric, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.resolve_unavailability_incident(uuid, numeric, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_unavailability_incident(uuid, numeric, numeric) TO authenticated, service_role;
