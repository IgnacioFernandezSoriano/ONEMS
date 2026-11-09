-- Incidencias de baja: resolucion 100 % automatica, la incidencia solo informa.
-- Spec: docs/superpowers/specs/2026-11-09-incidencias-baja-solo-informativas-design.md (modifica a la del
-- 2026-10-20, incidencias-indisponibilidad-resolucion-automatica).
--
-- Antes el motor resolvia solo una parte de las muestras afectadas y dejaba el resto 'pending' para que el
-- manager confirmara o anulara («Pending manager decision»). Ahora el motor decide siempre:
--   pasos 1 y 2 como hasta ahora (retrasar dentro del mes / otro nodo de la ciudad dentro del mes);
--   paso 3: si no cabe en el mes, se APLICA la propuesta de incident_suggest (primera fecha laborable
--           posterior sin saturar, en el mismo nodo o en otro de la ciudad, hasta 8 semanas);
--   paso 4: si no hay hueco en esas 8 semanas, se anula la muestra.
-- Ninguna linea queda 'pending'. Si el motor falla en una muestra, su linea pasa a informativa
-- ('engine_error', con el mensaje en resolution_note) y el resto sigue.
--
-- Contenido:
--   1. incident_resolve_pending_lines (nueva): cierra las lineas 'pending' de una baja (pasos 3 y 4).
--   2. resolve_unavailability_incident: re-emitida desde la definicion viva (igual a 20261105180000) con dos
--      cambios: el paso (a) ya no borra lineas de muestras anuladas, y al final llama a (1). Se quita el
--      bloque que guardaba la propuesta para el manager: ahora la calcula y la aplica (1).
--   3. incident_recompute_status: re-emitida (igual a 20261020130200); nunca devuelve 'pending_manager'.
-- El valor 'pending_manager' sigue valiendo en los datos antiguos; simplemente deja de producirse.

-- ===== 1. incident_resolve_pending_lines =====
-- Por cada linea 'pending' de la baja (orden fecha_programada, id), cada una en su propio subbloque:
--   * la muestra ya no esta pending/notified:
--       cancelled      -> linea 'info', motivo 'handled_by_other_incident' (otra baja ya la anulo);
--       sent/received  -> linea 'info', motivo 'already_sent' / 'in_transit' (misma regla del paso (b));
--       otro estado    -> error controlado -> linea 'info' 'engine_error' (la muestra no se toca);
--   * si no, incident_suggest: con hueco se aplica ('shift_later_week' si es el mismo nodo,
--     'alt_node_later_week' si es otro); sin hueco se anula ('no_slot_8_weeks');
--   * si algo falla: linea 'info', 'engine_error', resolution_note = mensaje, y un WARNING.
-- Devuelve cuantas lineas ha cerrado.
CREATE OR REPLACE FUNCTION public.incident_resolve_pending_lines(
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
  v_account uuid;
  v_count integer := 0;
  r record;
  v_d record;
  v_role_node uuid;
  v_s jsonb;
  v_date date;
  v_s_node uuid;
  v_same boolean;
BEGIN
  SELECT u.account_id INTO v_account FROM panelist_unavailability u WHERE u.id = p_unavailability_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  -- Guarda multi-tenant: service role / triggers (auth.uid() NULL) y superadmin pasan.
  IF auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND v_account IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = auth.uid()) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;

  FOR r IN
    SELECT pr.id, pr.affected_role, pr.allocation_plan_detail_id
      FROM panelist_reassignment_proposal pr
      JOIN allocation_plan_details a ON a.id = pr.allocation_plan_detail_id
     WHERE pr.unavailability_id = p_unavailability_id
       AND pr.status = 'pending'
     ORDER BY a.fecha_programada, pr.id
  LOOP
    BEGIN
      -- Releer: una linea anterior de esta pasada puede haber movido o anulado la muestra.
      SELECT * INTO v_d FROM allocation_plan_details WHERE id = r.allocation_plan_detail_id FOR UPDATE;

      IF v_d.status = 'cancelled' THEN
        -- Ya anulada (por otra baja o a mano): no hay nada que hacer, solo se informa.
        UPDATE panelist_reassignment_proposal
           SET status = 'info', final_action = 'none', suggested_reason = 'handled_by_other_incident',
               updated_at = now()
         WHERE id = r.id;
      ELSIF v_d.status IN ('sent','received') THEN
        -- Ya salida / recibida: nunca se toca (misma regla que el paso (b) del motor).
        UPDATE panelist_reassignment_proposal
           SET status = 'info', final_action = 'none',
               suggested_reason = CASE WHEN r.affected_role = 'destination' AND v_d.status = 'sent'
                                       THEN 'in_transit' ELSE 'already_sent' END,
               updated_at = now()
         WHERE id = r.id;
      ELSIF v_d.status NOT IN ('pending','notified') THEN
        RAISE EXCEPTION 'Sample % is % and cannot be resolved', v_d.id, v_d.status;
      ELSE
        v_s := incident_suggest(r.id, NULL, v_ref, v_dev);
        IF COALESCE((v_s->>'found')::boolean, false) THEN
          -- Paso 3: primera fecha laborable posterior con sitio. "Mismo nodo" = el nodo de la muestra en el
          -- rol afectado, que es el de la baja (si no lo fuera, el paso (a) ya habria retirado la linea).
          v_date := (v_s->>'date')::date;
          v_s_node := (v_s->>'node_id')::uuid;
          v_role_node := CASE WHEN r.affected_role = 'origin' THEN v_d.origin_node_id ELSE v_d.destination_node_id END;
          v_same := v_s_node = v_role_node;
          UPDATE panelist_reassignment_proposal
             SET suggested_action = CASE WHEN v_same THEN 'shift_date' ELSE 'reroute' END,
                 suggested_date = v_date,
                 suggested_target_node_id = CASE WHEN v_same THEN NULL ELSE v_s_node END,
                 suggested_reason = CASE WHEN v_same THEN 'shift_later_week' ELSE 'alt_node_later_week' END,
                 updated_at = now()
           WHERE id = r.id;
          PERFORM incident_apply_change(r.id, v_date, CASE WHEN v_same THEN NULL ELSE v_s_node END, 'auto');
        ELSE
          -- Paso 4: sin hueco en 8 semanas -> se anula.
          UPDATE panelist_reassignment_proposal
             SET suggested_action = 'cancel', suggested_date = NULL, suggested_target_node_id = NULL,
                 suggested_reason = 'no_slot_8_weeks', updated_at = now()
           WHERE id = r.id;
          PERFORM incident_apply_cancel(r.id, 'auto');
        END IF;
      END IF;
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      -- El subbloque ya se ha deshecho (la muestra queda como estaba); la linea se cierra como informativa.
      RAISE WARNING 'incident_resolve_pending_lines: linea % (muestra %): %', r.id, r.allocation_plan_detail_id, SQLERRM;
      UPDATE panelist_reassignment_proposal
         SET status = 'info', final_action = 'none', suggested_reason = 'engine_error',
             resolution_note = SQLERRM, updated_at = now()
       WHERE id = r.id;
      v_count := v_count + 1;
    END;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.incident_resolve_pending_lines(uuid, numeric, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.incident_resolve_pending_lines(uuid, numeric, numeric) TO service_role;

-- ===== 2. resolve_unavailability_incident (permisos sin cambios: CREATE OR REPLACE los conserva) =====
CREATE OR REPLACE FUNCTION public.resolve_unavailability_incident(p_unavailability_id uuid, p_reference_load numeric DEFAULT 6, p_deviation_percent numeric DEFAULT 20)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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
  --     2026-11-09: las de muestras ANULADAS no se borran: las cierra incident_resolve_pending_lines como
  --     informativas ('handled_by_other_incident'), para que la incidencia diga que otra baja ya la anulo.
  DELETE FROM panelist_reassignment_proposal pr
   USING allocation_plan_details a
   WHERE pr.unavailability_id = p_unavailability_id
     AND pr.status = 'pending'
     AND a.id = pr.allocation_plan_detail_id
     AND a.status IS DISTINCT FROM 'cancelled'
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
        -- Si los pasos 1/2 no encuentran sitio (o falla al aplicar), sigue 'pending' un instante: la cierra
        -- incident_resolve_pending_lines al final (pasos 3 y 4: otra semana o anular).
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

        IF v_date IS NOT NULL OR v_target IS NOT NULL THEN
          BEGIN
            PERFORM incident_apply_change(v_line, v_date, v_target, 'auto');
          EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'resolve_unavailability_incident: no se pudo aplicar la linea % (muestra %): %',
              v_line, v_d.id, SQLERRM;
          END;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'resolve_unavailability_incident: muestra % rol % omitida: %', r.id, r.role, SQLERRM;
      END;
    END LOOP;
  END IF;

  -- (c2) 2026-11-09: ninguna linea queda pendiente. Las que siguen 'pending' (sin sitio en el mes, o lineas
  --      viejas del motor anterior) se resuelven ya: otra semana (incident_suggest) o se anulan.
  PERFORM incident_resolve_pending_lines(p_unavailability_id, v_ref, v_dev);

  -- (d) Estado de la incidencia.
  PERFORM incident_recompute_status(p_unavailability_id);
  RETURN v_count;
END;
$$;

-- ===== 3. incident_recompute_status (permisos sin cambios: CREATE OR REPLACE los conserva) =====
CREATE OR REPLACE FUNCTION public.incident_recompute_status(p_unavailability_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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

  -- 2026-11-09: nunca 'pending_manager' (el motor ya no deja pendientes). Una linea 'pending' residual no
  -- cambia el estado, pero sigue contando en el resumen como pending=.
  v_status := CASE WHEN c.n_manager > 0 THEN 'resolved' ELSE 'auto_resolved' END;
  v_summary := format('shift=%s;reroute=%s;cancel=%s;info=%s;pending=%s',
                      c.n_shift, c.n_reroute, c.n_cancel, c.n_info, c.n_pending);
  v_review := 'reviewed';

  -- Solo escribe si algo cambia (no reescribe resolved_at en llamadas repetidas).
  UPDATE panelist_unavailability u
     SET incident_status = v_status,
         auto_summary = v_summary,
         review_status = v_review,
         resolved_at = CASE WHEN u.incident_status = v_status AND u.resolved_at IS NOT NULL THEN u.resolved_at
                            ELSE now() END
   WHERE u.id = p_unavailability_id
     AND (u.incident_status IS DISTINCT FROM v_status
          OR u.auto_summary IS DISTINCT FROM v_summary
          OR u.review_status IS DISTINCT FROM v_review
          OR u.resolved_at IS NULL);

  RETURN v_status;
END;
$$;
