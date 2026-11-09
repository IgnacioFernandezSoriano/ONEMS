-- Incidencias de baja: dos arreglos (casos revisados 2026-11-05, Nairobi City Square).
--
-- 1. Si una muestra con linea pendiente sale (el bot la marca enviada o recibida), el motor se vuelve a
--    ejecutar: la linea pendiente se retira y nace informativa ('already_sent' / 'in_transit'). Antes se
--    quedaba en «Pending your decision» y Confirm/Void daban "Sample ... is sent and cannot be cancelled".
-- 2. Una recepcion programada el ULTIMO dia de la baja no se toca: la carta sale ese dia y llega cuando el
--    panelista ya ha vuelto. Linea informativa 'back_before_arrival' (antes proponia anularla).
--
-- Se re-emiten resolve_unavailability_incident (20261020130200) y tg_refresh_incidents_on_plan_change
-- (20261020130400) con solo esos cambios. Permisos sin cambios (CREATE OR REPLACE los conserva).

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
           AND (CASE WHEN pr.affected_role = 'origin' THEN a.origin_node_id ELSE a.destination_node_id END) = v_node
           -- recepcion el ultimo dia de la baja: pasa a informativa en (b)
           AND NOT (pr.affected_role = 'destination' AND a.fecha_programada >= v_u.end_date),
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

        -- Recepcion el ultimo dia de la baja: la carta sale ese dia y llega cuando el panelista ya ha vuelto.
        -- No hay nada que cambiar (caso Nairobi City Square, 2026-11-05).
        IF r.role = 'destination' AND v_d.fecha_programada >= v_u.end_date THEN
          INSERT INTO panelist_reassignment_proposal
            (account_id, unavailability_id, allocation_plan_detail_id, affected_role, sample_status_at_detection,
             suggested_action, suggested_reason, status, final_action)
          VALUES (v_u.account_id, p_unavailability_id, v_d.id, r.role, v_d.status,
                  'none', 'back_before_arrival', 'info', 'none');
          v_count := v_count + 1;
          CONTINUE;
        END IF;

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

CREATE OR REPLACE FUNCTION public.tg_refresh_incidents_on_plan_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prev text := COALESCE(current_setting('onems.in_incident_engine', true), '');
  v_ids uuid[];
  v_id uuid;
BEGIN
  IF v_prev = 'on' THEN RETURN NULL; END IF;
  BEGIN
    -- Camino rapido: sin bajas activas y vigentes no hay nada que recalcular (dentro del bloque protegido).
    IF NOT EXISTS (SELECT 1 FROM panelist_unavailability WHERE status = 'active' AND end_date >= current_date) THEN
      RETURN NULL;
    END IF;

    -- Posiciones (nodo, fecha) tocadas -> bajas activas y vigentes del panelista de ese nodo que las cubren.
    -- Las bajas activas son pocas: se parte de ellas y se cruza con las posiciones (hash join).
    IF TG_OP = 'INSERT' THEN
      WITH pos AS (
        SELECT n.account_id, n.origin_node_id AS node_id, n.fecha_programada AS d FROM new_rows n
        UNION
        SELECT n.account_id, n.destination_node_id, n.fecha_programada FROM new_rows n)
      SELECT array_agg(DISTINCT u.id ORDER BY u.id) INTO v_ids
        FROM panelist_unavailability u
        JOIN panelists p ON p.id = u.panelist_id AND p.account_id = u.account_id
        JOIN pos ON pos.account_id = u.account_id AND pos.node_id = p.node_id
                AND pos.d BETWEEN u.start_date AND u.end_date
       WHERE u.status = 'active' AND u.end_date >= current_date;
    ELSE
      -- Solo cambios de fecha/origen/destino que NO vienen de una resolucion (reassigned_at igual);
      -- se miran la posicion nueva (alta de linea) y la antigua (retirada de pendientes).
      WITH ch AS (
        SELECT o.account_id AS o_a, n.account_id AS n_a,
               o.origin_node_id AS o_o, o.destination_node_id AS o_d, o.fecha_programada AS o_f,
               n.origin_node_id AS n_o, n.destination_node_id AS n_d, n.fecha_programada AS n_f
          FROM old_rows o
          JOIN new_rows n ON n.id = o.id
         WHERE (o.fecha_programada IS DISTINCT FROM n.fecha_programada
                OR o.origin_node_id IS DISTINCT FROM n.origin_node_id
                OR o.destination_node_id IS DISTINCT FROM n.destination_node_id
                -- la muestra sale (la envia o la recibe el bot): sus lineas pendientes pasan a informativas.
                -- pending -> notified NO cuenta (ocurre en masa cada dia y no cambia nada).
                OR (o.status IN ('pending','notified') AND n.status IN ('sent','received')))
           AND o.reassigned_at IS NOT DISTINCT FROM n.reassigned_at),
      pos AS (
        SELECT n_a AS account_id, n_o AS node_id, n_f AS d FROM ch
        UNION SELECT n_a, n_d, n_f FROM ch
        UNION SELECT o_a, o_o, o_f FROM ch
        UNION SELECT o_a, o_d, o_f FROM ch)
      SELECT array_agg(DISTINCT u.id ORDER BY u.id) INTO v_ids
        FROM panelist_unavailability u
        JOIN panelists p ON p.id = u.panelist_id AND p.account_id = u.account_id
        JOIN pos ON pos.account_id = u.account_id AND pos.node_id = p.node_id
                AND pos.d BETWEEN u.start_date AND u.end_date
       WHERE u.status = 'active' AND u.end_date >= current_date;
    END IF;

    IF v_ids IS NOT NULL THEN
      FOREACH v_id IN ARRAY v_ids LOOP
        BEGIN
          PERFORM set_config('onems.in_incident_engine', 'on', true);
          PERFORM resolve_unavailability_incident(v_id);
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'tg_refresh_incidents_on_plan_change: motor fallido para la baja %: %', v_id, SQLERRM;
        END;
        PERFORM set_config('onems.in_incident_engine', v_prev, true);
      END LOOP;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'tg_refresh_incidents_on_plan_change: refresco omitido: %', SQLERRM;
  END;
  PERFORM set_config('onems.in_incident_engine', v_prev, true);
  RETURN NULL;
END;
$$;
