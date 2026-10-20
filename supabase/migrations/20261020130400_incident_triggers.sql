-- Incidencias de indisponibilidad: triggers.
--   (1) panelist_unavailability: alta/activacion -> motor (resolve_unavailability_incident);
--       cancelacion (active -> otro) -> revierte lo aplicado por el motor y por el manager, descarta
--       pendientes y cierra la incidencia ('resolved', final_resolution 'unavailability_cancelled').
--       Sustituye a tg_generate_proposals_on_unavailability (llamaba al motor viejo, ya borrado).
--   (2) allocation_plan_details: triggers de SENTENCIA (INSERT / UPDATE con tablas de transicion) que
--       re-ejecutan el motor, una vez por baja, para las bajas activas y vigentes tocadas por las filas.
--       Se ignoran las filas cuyo reassigned_at cambia (resoluciones del motor/manager y reversiones, que
--       lo cambian en el mismo UPDATE que la fecha/nodo) y los UPDATE que no tocan fecha/origen/destino.
-- Guarda de re-entrada: mientras un trigger de este fichero ejecuta el motor o una reversion, fija
-- onems.in_incident_engine='on' (local a la transaccion); con ella activa ambos triggers no hacen nada.
-- Best-effort: nada de esto puede bloquear un INSERT/UPDATE del plan ni de la baja (EXCEPTION -> WARNING).

-- (0) Trigger y funcion viejos fuera.
DROP TRIGGER IF EXISTS generate_proposals_on_unavailability_trigger ON public.panelist_unavailability;
DROP FUNCTION IF EXISTS public.tg_generate_proposals_on_unavailability();

-- (1) Alta / cancelacion de baja (por fila).
CREATE OR REPLACE FUNCTION public.tg_unavailability_incident()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prev text := COALESCE(current_setting('onems.in_incident_engine', true), '');
  r record;
  v_d record;
  v_role_node uuid;
  v_orig_node uuid;
  v_restore_node boolean;
  v_restore_date boolean;
  v_uncancel boolean;
  v_new_date date;
  v_pan_id uuid;
  v_pan_name text;
  v_notified uuid[] := '{}';
BEGIN
  IF v_prev = 'on' THEN RETURN NULL; END IF;

  -- ===== Activacion: INSERT activa, o UPDATE que pasa a activa =====
  IF NEW.status = 'active' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'active') THEN
    BEGIN
      PERFORM set_config('onems.in_incident_engine', 'on', true);
      PERFORM resolve_unavailability_incident(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'tg_unavailability_incident: motor fallido para la baja %: %', NEW.id, SQLERRM;
    END;
    PERFORM set_config('onems.in_incident_engine', v_prev, true);
    RETURN NULL;
  END IF;

  -- ===== Desactivacion: active -> cualquier otro estado =====
  IF TG_OP = 'UPDATE' AND OLD.status = 'active' AND NEW.status IS DISTINCT FROM 'active' THEN
    BEGIN
      PERFORM set_config('onems.in_incident_engine', 'on', true);

      FOR r IN
        SELECT pr.id, pr.allocation_plan_detail_id, pr.affected_role, pr.final_action, pr.final_date
          FROM panelist_reassignment_proposal pr
         WHERE pr.unavailability_id = NEW.id
           AND pr.status IN ('auto_resolved','manager_resolved')
         ORDER BY pr.created_at, pr.id
      LOOP
        SELECT * INTO v_d FROM allocation_plan_details WHERE id = r.allocation_plan_detail_id FOR UPDATE;
        IF FOUND THEN
          v_role_node := CASE WHEN r.affected_role = 'origin' THEN v_d.origin_node_id ELSE v_d.destination_node_id END;
          v_orig_node := CASE WHEN r.affected_role = 'origin' THEN v_d.original_origin_node_id
                              ELSE v_d.original_destination_node_id END;
          -- Solo se revierte lo que no ha salido: una muestra ya enviada/recibida conserva el cambio ejecutado.
          v_restore_node := r.final_action = 'reroute' AND v_d.status IN ('pending','notified')
                            AND v_orig_node IS NOT NULL;
          v_restore_date := v_d.status IN ('pending','notified') AND v_d.original_fecha_programada IS NOT NULL
                            AND (r.final_action = 'shift_date'
                                 OR (r.final_action = 'reroute' AND r.final_date IS NOT NULL));
          v_uncancel := r.final_action = 'cancel' AND v_d.status = 'cancelled'
                        AND v_d.reassignment_reason = 'panelist_unavailable';

          IF v_restore_node OR v_restore_date OR v_uncancel THEN
            v_new_date := CASE WHEN v_restore_date THEN v_d.original_fecha_programada ELSE v_d.fecha_programada END;
            v_pan_id := NULL; v_pan_name := NULL;
            IF v_restore_node THEN
              SELECT g.panelist_id, g.panelist_name INTO v_pan_id, v_pan_name
                FROM get_panelist_for_node(v_orig_node, v_new_date) g;
            END IF;

            -- UNA sola sentencia: reassigned_at pasa a NULL junto con fecha/nodo, asi el trigger de refresco
            -- del plan ignora la reversion (y la guarda de re-entrada tambien la cubre).
            UPDATE allocation_plan_details
               SET origin_node_id = CASE WHEN v_restore_node AND r.affected_role = 'origin'
                                         THEN v_orig_node ELSE origin_node_id END,
                   original_origin_node_id = CASE WHEN v_restore_node AND r.affected_role = 'origin'
                                                  THEN NULL ELSE original_origin_node_id END,
                   origin_panelist_name = CASE WHEN v_restore_node AND r.affected_role = 'origin'
                                               THEN v_pan_name ELSE origin_panelist_name END,
                   origin_panelist_id = CASE WHEN v_restore_node AND r.affected_role = 'origin'
                                               AND origin_panelist_id IS NOT NULL
                                             THEN v_pan_id ELSE origin_panelist_id END,
                   destination_node_id = CASE WHEN v_restore_node AND r.affected_role <> 'origin'
                                              THEN v_orig_node ELSE destination_node_id END,
                   original_destination_node_id = CASE WHEN v_restore_node AND r.affected_role <> 'origin'
                                                       THEN NULL ELSE original_destination_node_id END,
                   destination_panelist_name = CASE WHEN v_restore_node AND r.affected_role <> 'origin'
                                                    THEN v_pan_name ELSE destination_panelist_name END,
                   destination_panelist_id = CASE WHEN v_restore_node AND r.affected_role <> 'origin'
                                                    AND destination_panelist_id IS NOT NULL
                                                  THEN v_pan_id ELSE destination_panelist_id END,
                   fecha_programada = v_new_date,
                   original_fecha_programada = CASE WHEN v_restore_date THEN NULL ELSE original_fecha_programada END,
                   status = CASE WHEN v_uncancel THEN 'pending' ELSE status END,
                   reassignment_reason = NULL,
                   reassigned_at = NULL,
                   reassigned_by = NULL,
                   updated_at = now()
             WHERE id = v_d.id;

            -- Aviso de vuelta atras (solo si alguna fecha cae en la semana actual; una vez por muestra).
            IF NOT v_d.id = ANY (v_notified) THEN
              PERFORM incident_enqueue_plan_change(v_d.id, 'revert', v_d.fecha_programada, v_new_date, NEW.panelist_id);
              v_notified := v_notified || v_d.id;
            END IF;
          END IF;
        END IF;

        UPDATE panelist_reassignment_proposal
           SET resolution_note = 'unavailability_cancelled', updated_at = now()
         WHERE id = r.id;
      END LOOP;

      -- Pendientes: ya no aplican.
      UPDATE panelist_reassignment_proposal
         SET status = 'dismissed', resolution_note = 'unavailability_cancelled', updated_at = now()
       WHERE unavailability_id = NEW.id AND status = 'pending';

      -- Incidencia cerrada (codigo; la UI lo traduce). No se duplica si ya estaba.
      UPDATE panelist_unavailability u
         SET incident_status = 'resolved',
             final_resolution = CASE
               WHEN COALESCE(u.final_resolution, '') LIKE '%unavailability_cancelled%' THEN u.final_resolution
               WHEN NULLIF(u.final_resolution, '') IS NULL THEN 'unavailability_cancelled'
               ELSE u.final_resolution || E'\n' || 'unavailability_cancelled' END,
             resolved_at = now(),
             review_status = 'reviewed'
       WHERE u.id = NEW.id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'tg_unavailability_incident: no se pudo revertir la baja %: %', NEW.id, SQLERRM;
    END;
    PERFORM set_config('onems.in_incident_engine', v_prev, true);
  END IF;

  RETURN NULL;
END;
$$;

CREATE TRIGGER generate_proposals_on_unavailability_trigger
  AFTER INSERT OR UPDATE ON public.panelist_unavailability
  FOR EACH ROW EXECUTE FUNCTION public.tg_unavailability_incident();

-- (2) Refresco por cambios del plan (por sentencia).
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
    -- Posiciones (nodo, fecha) tocadas -> bajas activas y vigentes del panelista de ese nodo que las cubren.
    -- Las bajas activas son pocas: se parte de ellas y se cruza con las posiciones (hash join).
    IF TG_OP = 'INSERT' THEN
      WITH pos AS (
        SELECT n.origin_node_id AS node_id, n.fecha_programada AS d FROM new_rows n
        UNION
        SELECT n.destination_node_id, n.fecha_programada FROM new_rows n)
      SELECT array_agg(DISTINCT u.id ORDER BY u.id) INTO v_ids
        FROM panelist_unavailability u
        JOIN panelists p ON p.id = u.panelist_id
        JOIN pos ON pos.node_id = p.node_id AND pos.d BETWEEN u.start_date AND u.end_date
       WHERE u.status = 'active' AND u.end_date >= current_date;
    ELSE
      -- Solo cambios de fecha/origen/destino que NO vienen de una resolucion (reassigned_at igual);
      -- se miran la posicion nueva (alta de linea) y la antigua (retirada de pendientes).
      WITH ch AS (
        SELECT o.origin_node_id AS o_o, o.destination_node_id AS o_d, o.fecha_programada AS o_f,
               n.origin_node_id AS n_o, n.destination_node_id AS n_d, n.fecha_programada AS n_f
          FROM old_rows o
          JOIN new_rows n ON n.id = o.id
         WHERE (o.fecha_programada IS DISTINCT FROM n.fecha_programada
                OR o.origin_node_id IS DISTINCT FROM n.origin_node_id
                OR o.destination_node_id IS DISTINCT FROM n.destination_node_id)
           AND o.reassigned_at IS NOT DISTINCT FROM n.reassigned_at),
      pos AS (
        SELECT n_o AS node_id, n_f AS d FROM ch
        UNION SELECT n_d, n_f FROM ch
        UNION SELECT o_o, o_f FROM ch
        UNION SELECT o_d, o_f FROM ch)
      SELECT array_agg(DISTINCT u.id ORDER BY u.id) INTO v_ids
        FROM panelist_unavailability u
        JOIN panelists p ON p.id = u.panelist_id
        JOIN pos ON pos.node_id = p.node_id AND pos.d BETWEEN u.start_date AND u.end_date
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

DROP TRIGGER IF EXISTS refresh_incidents_on_plan_insert ON public.allocation_plan_details;
CREATE TRIGGER refresh_incidents_on_plan_insert
  AFTER INSERT ON public.allocation_plan_details
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_refresh_incidents_on_plan_change();

DROP TRIGGER IF EXISTS refresh_incidents_on_plan_update ON public.allocation_plan_details;
CREATE TRIGGER refresh_incidents_on_plan_update
  AFTER UPDATE ON public.allocation_plan_details
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_refresh_incidents_on_plan_change();

-- (3) Permisos: funciones de trigger, nunca invocables directamente.
REVOKE ALL ON FUNCTION public.tg_unavailability_incident() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tg_refresh_incidents_on_plan_change() FROM PUBLIC, anon, authenticated;
