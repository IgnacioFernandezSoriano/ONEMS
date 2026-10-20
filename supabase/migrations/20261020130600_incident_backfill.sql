-- Puesta al dia de incidencias de indisponibilidad existentes (ver spec 2026-10-20, seccion 7).
--   (1) Cada baja activa y vigente se trata como nueva: se ejecuta el motor una vez, SIN avisos al
--       panelista (onems.suppress_notifications = on, local a esta transaccion, dentro del mismo DO).
--   (2) Las bajas canceladas o ya pasadas que siguen en 'new' pasan a 'resolved'.
--   (3) Autocomprobacion: ninguna baja activa vigente puede quedar en 'new'.
-- Sobre una BD vacia no hace nada.
--
-- EXCEPCION (decision del responsable, 2026-10-20): la cuenta KENYA (c4fe92f1-7673-41ae-9ed9-4b82d198be08) NO se procesa:
-- sus bajas (Nancy Weru, Petet Lokui Lokaale) se dejan tal cual y el plan de KENYA no se toca.
-- Se podran procesar mas tarde con: select public.resolve_unavailability_incident('<id de la baja>');
DO $$
DECLARE r record; v integer;
  v_prev text := COALESCE(current_setting('onems.in_incident_engine', true), '');
BEGIN
  PERFORM set_config('onems.suppress_notifications', 'on', true);
  FOR r IN SELECT id FROM public.panelist_unavailability
            WHERE status = 'active' AND end_date >= current_date
              AND account_id <> 'c4fe92f1-7673-41ae-9ed9-4b82d198be08'::uuid
            ORDER BY start_date LOOP
    BEGIN
      -- Misma convencion que los triggers: guarda de re-entrada activa mientras corre el motor.
      PERFORM set_config('onems.in_incident_engine', 'on', true);
      v := public.resolve_unavailability_incident(r.id);
      PERFORM set_config('onems.in_incident_engine', v_prev, true);
      RAISE NOTICE 'baja %: % lineas nuevas', r.id, v;
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('onems.in_incident_engine', v_prev, true);
      RAISE WARNING 'puesta al dia fallo para %: %', r.id, SQLERRM;
    END;
  END LOOP;
END $$;

UPDATE public.panelist_unavailability
   SET incident_status = 'resolved', resolved_at = COALESCE(resolved_at, updated_at)
 WHERE incident_status = 'new' AND (status = 'cancelled' OR end_date < current_date);

DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM public.panelist_unavailability
   WHERE incident_status = 'new' AND status = 'active' AND end_date >= current_date
     AND account_id <> 'c4fe92f1-7673-41ae-9ed9-4b82d198be08'::uuid;
  IF n > 0 THEN
    RAISE EXCEPTION 'puesta al dia incompleta: % bajas activas vigentes siguen en new', n;
  END IF;
END $$;
