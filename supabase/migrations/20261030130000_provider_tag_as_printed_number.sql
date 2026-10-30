-- Etiqueta RFID del proveedor = prefijo fijo + numero impreso.
-- A partir de ahora la clave de etiqueta en ONEMS es el numero impreso normalizado a 8 digitos
-- (misma regla normalize_tag que aplica a lo que registra el panelista en one_db).
-- Antes se guardaba la cadena completa del proveedor (G.1UPU.01000FFFF00010521), que nunca
-- coincidia con one_db y dejaba todos los eventos como "etiqueta desconocida".
--
-- Cambia: normalize_provider_tag (unica puerta de entrada de las lecturas del proveedor).
-- Hereda sin tocar: resolve_provider_reads -> rfid_events_raw -> consolidate_rfid_events ->
-- processed_events -> journeys / journey_segments / incidents.
-- Backfill: filas historicas con el formato largo pasan al nuevo formato.

CREATE OR REPLACE FUNCTION public.normalize_provider_tag(p_raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v text;
BEGIN
  IF p_raw IS NULL THEN
    RETURN NULL;
  END IF;
  v := upper(trim(p_raw));
  IF v = '' THEN
    RETURN NULL;
  END IF;

  -- Formato UPU del proveedor: prefijo fijo + numero impreso en la etiqueta.
  -- Se devuelve solo el numero impreso, normalizado a 8 digitos (regla normalize_tag).
  IF v ~ '^G\.1UPU\.01000FFFF[0-9]+$' THEN
    RETURN public.normalize_tag(substring(v from '[0-9]+$'));
  END IF;

  -- Cualquier otro formato: no decodificable (queda como tag_decode_failed, visible en monitoring).
  RETURN NULL;
END $function$;

COMMENT ON FUNCTION public.normalize_provider_tag(text) IS
  'Convierte la etiqueta del proveedor (G.1UPU.01000FFFF + numero impreso) en la clave de 8 digitos que usa one_db. NULL si el formato no es el esperado.';

-- Backfill de filas historicas con el formato largo (solo las que encajan en el patron).
UPDATE public.rfid_provider_reads
   SET tag_id_normalized = public.normalize_provider_tag(tag_id_raw)
 WHERE tag_id_raw ~ '^G\.1UPU\.01000FFFF[0-9]+$'
   AND tag_id_normalized IS DISTINCT FROM public.normalize_provider_tag(tag_id_raw);

UPDATE public.rfid_events_raw
   SET tag_id = public.normalize_provider_tag(tag_id)
 WHERE tag_id ~ '^G\.1UPU\.01000FFFF[0-9]+$';

UPDATE public.processed_events
   SET tag_id = public.normalize_provider_tag(tag_id)
 WHERE tag_id ~ '^G\.1UPU\.01000FFFF[0-9]+$';

UPDATE public.journey_segments
   SET tag_id = public.normalize_provider_tag(tag_id)
 WHERE tag_id ~ '^G\.1UPU\.01000FFFF[0-9]+$';

UPDATE public.incidents
   SET tag_id = public.normalize_provider_tag(tag_id)
 WHERE tag_id ~ '^G\.1UPU\.01000FFFF[0-9]+$';

-- journeys tiene UNIQUE (account_id, tag_id): solo se renombra si no existe ya la clave corta.
UPDATE public.journeys j
   SET tag_id = public.normalize_provider_tag(j.tag_id)
 WHERE j.tag_id ~ '^G\.1UPU\.01000FFFF[0-9]+$'
   AND NOT EXISTS (
     SELECT 1 FROM public.journeys x
      WHERE x.account_id = j.account_id
        AND x.tag_id = public.normalize_provider_tag(j.tag_id)
   );
