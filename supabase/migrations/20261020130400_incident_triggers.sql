-- Incidencias de indisponibilidad: triggers.
--   (1) panelist_unavailability: alta/activacion -> motor (resolve_unavailability_incident);
--       cancelacion (active -> otro) -> revierte lo aplicado por el motor y por el manager, descarta
--       pendientes y cierra la incidencia ('resolved', final_resolution 'unavailability_cancelled').
--       Sustituye a tg_generate_proposals_on_unavailability (llamaba al motor viejo, ya borrado).
--   (0b) panelist_unavailability: BEFORE trigger, el panelista debe ser de la cuenta de la baja.
--   (0c) resolve_unavailability_incident: solo muestras de la cuenta de la baja.
--   (0d) incident_enqueue_revert: avisos de reversion a panelistas de antes y despues.
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

-- (0b) Seguridad multi-tenant: el panelista de una baja debe ser de la cuenta de la baja (si no, el motor
--      escribiria en el plan de otra cuenta).
CREATE OR REPLACE FUNCTION public.tg_unavailability_check_panelist_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (SELECT p.account_id FROM panelists p WHERE p.id = NEW.panelist_id) IS DISTINCT FROM NEW.account_id THEN
    RAISE EXCEPTION 'Panelist does not belong to account';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS check_unavailability_panelist_account ON public.panelist_unavailability;
CREATE TRIGGER check_unavailability_panelist_account
  BEFORE INSERT OR UPDATE OF panelist_id, account_id ON public.panelist_unavailability
  FOR EACH ROW EXECUTE FUNCTION public.tg_unavailability_check_panelist_account();

-- (0c) Motor (Tarea 4, 20261020130200) con UN cambio minimo de seguridad: las muestras se seleccionan y se
--      releen solo de la cuenta de la baja (a.account_id = v_u.account_id). Resto identico.
--      Devuelve el numero de lineas nuevas creadas. Permisos sin cambios (CREATE OR REPLACE los conserva).
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


-- (0d) Aviso de reversion (cancelacion de baja). Se llama DESPUES del UPDATE de reversion, con el estado
--      previo (fecha y nodos). Destinatarios: panelistas activos de los nodos de origen/destino de antes y de
--      despues, sin excluir al de la baja (la baja se cancela: vuelve a actuar). recipient_role relativo al
--      estado nuevo: 'sender'/'receiver' si sigue en la muestra; 'former_sender'/'former_receiver' si ya no.
--      Solo si la fecha antigua o la nueva cae en la semana actual; respeta onems.suppress_notifications.
CREATE OR REPLACE FUNCTION public.incident_enqueue_revert(
  p_detail_id uuid, p_old_date date, p_old_origin_node_id uuid, p_old_destination_node_id uuid)
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
   WHERE p.id = (SELECT g.panelist_id FROM get_panelist_for_node(v_d.destination_node_id, v_d.fecha_programada) g);

  v_payload := jsonb_build_object(
    'detail_id', v_d.id,
    'change', 'revert',
    'old_date', p_old_date,
    'new_date', v_d.fecha_programada,
    'scheduled_date', v_d.fecha_programada,
    'origin_node_code', v_d.origin_code,
    'destination_node_code', v_d.destination_code,
    'origin_panelist_name', (SELECT g.panelist_name FROM get_panelist_for_node(v_d.origin_node_id, v_d.fecha_programada) g),
    'destination_panelist_name', v_dest.name,
    'destination_address', jsonb_build_object(
      'address_line1', v_dest.address_line1,
      'address_line2', v_dest.address_line2,
      'postal_code', v_dest.postal_code,
      'city', v_dest.address_city),
    'product_description', v_d.product_description,
    'carrier_name', v_d.carrier_name);

  -- Un aviso por panelista; si aparece en varios papeles, gana el del estado nuevo (orden de prioridad).
  FOR r IN
    SELECT DISTINCT ON (x.panelist_id) x.panelist_id, x.role
      FROM (
        SELECT (SELECT g.panelist_id FROM get_panelist_for_node(v_d.origin_node_id, v_d.fecha_programada) g) AS panelist_id,
               'sender'::text AS role, 1 AS prio
        UNION ALL
        SELECT (SELECT g.panelist_id FROM get_panelist_for_node(v_d.destination_node_id, v_d.fecha_programada) g),
               'receiver', 2
        UNION ALL
        SELECT (SELECT g.panelist_id FROM get_panelist_for_node(p_old_origin_node_id, p_old_date) g),
               'former_sender', 3
        UNION ALL
        SELECT (SELECT g.panelist_id FROM get_panelist_for_node(p_old_destination_node_id, p_old_date) g),
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
  -- Reactivar una baja cancelada NO esta soportado (spec 5.8: se cancela y se declara una nueva).
  IF TG_OP = 'UPDATE' AND OLD.status = 'active' AND NEW.status IS DISTINCT FROM 'active' THEN
    BEGIN
      PERFORM set_config('onems.in_incident_engine', 'on', true);

      FOR r IN
        SELECT pr.id, pr.allocation_plan_detail_id, pr.affected_role, pr.final_action, pr.final_date,
               pr.final_target_node_id
          FROM panelist_reassignment_proposal pr
         WHERE pr.unavailability_id = NEW.id
           AND pr.status IN ('auto_resolved','manager_resolved')
         ORDER BY pr.created_at, pr.id
      LOOP
        SELECT * INTO v_d FROM allocation_plan_details
         WHERE id = r.allocation_plan_detail_id AND account_id = NEW.account_id FOR UPDATE;
        IF FOUND THEN
          v_role_node := CASE WHEN r.affected_role = 'origin' THEN v_d.origin_node_id ELSE v_d.destination_node_id END;
          v_orig_node := CASE WHEN r.affected_role = 'origin' THEN v_d.original_origin_node_id
                              ELSE v_d.original_destination_node_id END;
          -- Solo se revierte lo que no ha salido (una muestra ya enviada/recibida conserva el cambio ejecutado)
          -- y solo si sigue como lo dejo la resolucion: una edicion manual posterior no se pisa.
          v_restore_node := r.final_action = 'reroute' AND v_d.status IN ('pending','notified')
                            AND v_orig_node IS NOT NULL
                            AND v_role_node IS NOT DISTINCT FROM r.final_target_node_id;
          v_restore_date := v_d.status IN ('pending','notified') AND v_d.original_fecha_programada IS NOT NULL
                            AND r.final_action IN ('shift_date','reroute')
                            AND r.final_date IS NOT NULL
                            AND v_d.fecha_programada = r.final_date;
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

            -- Aviso de vuelta atras (solo si alguna fecha cae en la semana actual; una vez por muestra) a los
            -- panelistas de antes y de despues de la reversion, incluido el de la baja (vuelve a actuar).
            IF NOT v_d.id = ANY (v_notified) THEN
              PERFORM incident_enqueue_revert(v_d.id, v_d.fecha_programada, v_d.origin_node_id, v_d.destination_node_id);
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
                OR o.destination_node_id IS DISTINCT FROM n.destination_node_id)
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
REVOKE ALL ON FUNCTION public.tg_unavailability_check_panelist_account() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_enqueue_revert(uuid, date, uuid, uuid) FROM PUBLIC, anon, authenticated;
