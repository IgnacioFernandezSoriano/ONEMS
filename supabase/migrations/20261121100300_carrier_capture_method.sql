-- Forma de captura por carrier (Carrier Link, tarea 8; aprobado por el responsable el 20/11).
-- carriers.capture_method dice como se capturan las muestras de cada carrier:
--   'panelists'    -> solo panelistas (lo de siempre; generador E2E)
--   'carrier_link' -> solo escaneos del carrier (generador, conectores y puntos de lectura de Carrier Link)
--   'both'         -> las dos cosas
-- Por defecto 'panelists': las cuentas que no usan Carrier Link (Kenya, Senegal) no cambian.
-- Relleno inicial: un carrier que ya tiene datos de Carrier Link (cl_plans, cl_feeds o puntos de lectura
-- carrier_scan sin borrar) pasa a 'both' si ademas tiene allocation plans de panelistas, o a 'carrier_link' si no.
-- Solo toca filas que siguen en 'panelists' (respeta una eleccion previa); se puede volver a aplicar sin efecto.
-- RLS: sin cambios; la columna queda cubierta por las politicas actuales de carriers.

ALTER TABLE public.carriers
  ADD COLUMN IF NOT EXISTS capture_method text NOT NULL DEFAULT 'panelists'
    CONSTRAINT carriers_capture_method_check CHECK (capture_method IN ('panelists', 'carrier_link', 'both'));

COMMENT ON COLUMN public.carriers.capture_method IS
  'Forma de captura: panelists (panelistas), carrier_link (escaneos del carrier) o both. Filtra los carriers que ofrece cada generador.';

UPDATE public.carriers c
   SET capture_method = CASE
         WHEN EXISTS (SELECT 1 FROM public.allocation_plans ap WHERE ap.carrier_id = c.id) THEN 'both'
         ELSE 'carrier_link'
       END
 WHERE c.capture_method = 'panelists'
   AND (EXISTS (SELECT 1 FROM public.cl_plans p WHERE p.carrier_id = c.id)
        OR EXISTS (SELECT 1 FROM public.cl_feeds f WHERE f.carrier_id = c.id)
        OR EXISTS (SELECT 1 FROM public.readers r
                    WHERE r.carrier_id = c.id AND r.capture_source = 'carrier_scan' AND r.deleted_at IS NULL));
