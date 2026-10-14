-- ============================================================================
-- Deshacer el impacto de una baja cuando se CANCELA (o desactiva)
-- ----------------------------------------------------------------------------
-- Contexto: el trigger generate_proposals_on_unavailability_trigger sólo reaccionaba
-- al ACTIVARSE una baja (INSERT o UPDATE -> active). Al cancelar una baja
-- (status: active -> cancelled) no pasaba nada: las propuestas pendientes seguían
-- vivas (el badge/alarma de "Disponibilidad de panelistas" no se limpiaba) y las
-- acciones ya aplicadas al plan no se revertían.
--
-- Esta migración amplía la función del trigger para cubrir la desactivación
-- (active -> cualquier estado no-active). Al cancelar una baja:
--   1) Revierte los REROUTES ya confirmados: devuelve el nodo (origen/destino)
--      del registro del plan a su valor original (guardado en original_*_node_id
--      por el aplicador) y limpia los metadatos de reasignación.
--   2) Descarta todas las propuestas 'pending' de esa baja (ya no aplican; el
--      panelista vuelve a estar disponible) -> el badge se limpia.
--   3) Marca la baja como 'reviewed' SÓLO si no quedan acciones confirmadas
--      no-revertibles (shift_date / cancel ya aplicados, cuyo valor original no
--      se guardó). Si quedan, deja review_status='pending_review' para que el
--      manager las revise a mano (pero sin propuestas pendientes, el badge ya no
--      la cuenta).
--
-- Best-effort: si el deshacer falla, la cancelación de la baja se guarda igual
-- (sólo se registra un WARNING), igual que el flujo de generación.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.tg_generate_proposals_on_unavailability()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unrevertible integer := 0;
BEGIN
  -- ================= ACTIVACIÓN: generar propuestas =================
  -- Sólo bajas activas. En UPDATE, sólo cuando pasa a activa (evita recalcular en
  -- cambios irrelevantes como updated_at); el motor es idempotente de todos modos.
  IF NEW.status = 'active'
     AND (TG_OP = 'INSERT'
          OR (TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM 'active')) THEN
    BEGIN
      PERFORM public.generate_reassignment_proposals(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      -- Best-effort: la baja debe guardarse aunque el motor falle.
      RAISE WARNING 'generate_reassignment_proposals falló para baja %: %',
        NEW.id, SQLERRM;
    END;
    RETURN NEW;
  END IF;

  -- ================= DESACTIVACIÓN: deshacer impacto =================
  -- active -> cualquier estado no-active (cancelled, etc.). Sólo en UPDATE.
  IF TG_OP = 'UPDATE'
     AND OLD.status = 'active'
     AND NEW.status IS DISTINCT FROM 'active' THEN
    BEGIN
      -- 1) Revertir reroutes ya confirmados (origen).
      UPDATE allocation_plan_details apd
        SET origin_node_id = apd.original_origin_node_id,
            original_origin_node_id = NULL,
            reassignment_reason = NULL,
            reassigned_at = NULL,
            reassigned_by = NULL,
            updated_at = now()
      FROM panelist_reassignment_proposal p
      WHERE p.unavailability_id = NEW.id
        AND p.status = 'confirmed'
        AND p.affected_role = 'origin'
        AND p.allocation_plan_detail_id = apd.id
        AND apd.original_origin_node_id IS NOT NULL;

      -- 1b) Revertir reroutes ya confirmados (destino).
      UPDATE allocation_plan_details apd
        SET destination_node_id = apd.original_destination_node_id,
            original_destination_node_id = NULL,
            reassignment_reason = NULL,
            reassigned_at = NULL,
            reassigned_by = NULL,
            updated_at = now()
      FROM panelist_reassignment_proposal p
      WHERE p.unavailability_id = NEW.id
        AND p.status = 'confirmed'
        AND p.affected_role = 'destination'
        AND p.allocation_plan_detail_id = apd.id
        AND apd.original_destination_node_id IS NOT NULL;

      -- 2) Descartar las propuestas pendientes de esta baja (ya no aplican).
      UPDATE panelist_reassignment_proposal
        SET status = 'dismissed', updated_at = now()
      WHERE unavailability_id = NEW.id
        AND status = 'pending';

      -- 3) ¿Quedan acciones confirmadas NO revertibles (shift_date / cancel)?
      --    Su valor original no se guardó -> requieren revisión manual del manager.
      SELECT count(*) INTO v_unrevertible
      FROM panelist_reassignment_proposal
      WHERE unavailability_id = NEW.id
        AND status = 'confirmed'
        AND final_action IN ('shift_date', 'cancel');

      IF v_unrevertible = 0 THEN
        -- Nada pendiente de revisar: sacar la baja de la bandeja de incidencias.
        UPDATE panelist_unavailability
          SET review_status = 'reviewed'
        WHERE id = NEW.id
          AND review_status IS DISTINCT FROM 'reviewed';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Best-effort: la cancelación debe guardarse aunque el deshacer falle.
      RAISE WARNING 'deshacer impacto de baja % falló: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- El trigger ya existe (AFTER INSERT OR UPDATE) desde 20260806120000; no se recrea.

-- ============================================================================
-- Puesta al día ÚNICA del estado ya atascado
-- ----------------------------------------------------------------------------
-- Las bajas canceladas ANTES de esta migración no dispararon el deshacer (su
-- status ya no es 'active'). Aplicamos la misma lógica una sola vez a toda baja
-- no-activa que aún tenga propuestas pendientes o reroutes confirmados sin revertir.
-- ============================================================================
DO $$
DECLARE
  b record;
  v_unrevertible integer;
BEGIN
  FOR b IN
    SELECT u.id
    FROM panelist_unavailability u
    WHERE u.status <> 'active'
      AND EXISTS (
        SELECT 1 FROM panelist_reassignment_proposal p
        WHERE p.unavailability_id = u.id
          AND (p.status = 'pending'
               OR (p.status = 'confirmed' AND p.final_action = 'reroute')))
  LOOP
    UPDATE allocation_plan_details apd
      SET origin_node_id = apd.original_origin_node_id, original_origin_node_id = NULL,
          reassignment_reason = NULL, reassigned_at = NULL, reassigned_by = NULL, updated_at = now()
    FROM panelist_reassignment_proposal p
    WHERE p.unavailability_id = b.id AND p.status = 'confirmed' AND p.affected_role = 'origin'
      AND p.allocation_plan_detail_id = apd.id AND apd.original_origin_node_id IS NOT NULL;

    UPDATE allocation_plan_details apd
      SET destination_node_id = apd.original_destination_node_id, original_destination_node_id = NULL,
          reassignment_reason = NULL, reassigned_at = NULL, reassigned_by = NULL, updated_at = now()
    FROM panelist_reassignment_proposal p
    WHERE p.unavailability_id = b.id AND p.status = 'confirmed' AND p.affected_role = 'destination'
      AND p.allocation_plan_detail_id = apd.id AND apd.original_destination_node_id IS NOT NULL;

    UPDATE panelist_reassignment_proposal
      SET status = 'dismissed', updated_at = now()
    WHERE unavailability_id = b.id AND status = 'pending';

    SELECT count(*) INTO v_unrevertible
    FROM panelist_reassignment_proposal
    WHERE unavailability_id = b.id AND status = 'confirmed' AND final_action IN ('shift_date', 'cancel');

    IF v_unrevertible = 0 THEN
      UPDATE panelist_unavailability SET review_status = 'reviewed'
      WHERE id = b.id AND review_status IS DISTINCT FROM 'reviewed';
    END IF;
  END LOOP;
END $$;
