-- ============================================================================
-- Disparar el motor de propuestas de reasignación (subsistema B/C) desde la BD
-- ----------------------------------------------------------------------------
-- Contexto: hasta ahora `generate_reassignment_proposals` sólo se invocaba desde
-- el frontend (hook usePanelistUnavailability -> edge function propose-reassignments).
-- Cualquier alta que NO pase por la app (n8n/Telegram, SQL directo) se quedaba sin
-- propuestas y, por tanto, sin incidentes para el manager.
--
-- Esta migración:
--   1) Crea un trigger AFTER INSERT/UPDATE que llama al motor para cualquier vía
--      de inserción (app, n8n, SQL). Best-effort: si el motor falla, la baja se
--      guarda igual (sólo se registra un WARNING), replicando el comportamiento
--      del frontend.
--   2) Desactiva el trigger legacy `reassign_on_unavailability_trigger`, que movía
--      muestras en silencio (sin propuestas ni revisión del manager) y entraría en
--      conflicto con el flujo de incidentes.
-- ============================================================================

-- 1) Función wrapper del trigger --------------------------------------------------
CREATE OR REPLACE FUNCTION public.tg_generate_proposals_on_unavailability()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
  END IF;
  RETURN NEW;
END;
$$;

-- 2) Trigger ----------------------------------------------------------------------
DROP TRIGGER IF EXISTS generate_proposals_on_unavailability_trigger ON public.panelist_unavailability;
CREATE TRIGGER generate_proposals_on_unavailability_trigger
  AFTER INSERT OR UPDATE ON public.panelist_unavailability
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_generate_proposals_on_unavailability();

-- 3) Desactivar el motor legacy de reasignación silenciosa ------------------------
--    (la función se conserva por historial; sólo se retira su trigger)
DROP TRIGGER IF EXISTS reassign_on_unavailability_trigger ON public.panelist_unavailability;
