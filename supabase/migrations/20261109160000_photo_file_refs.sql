-- 2026-11-09: referencia de Telegram (file_id) de las fotos de etiqueta, sin guardar la imagen.
--
-- Las fotos se quedan en Telegram; aqui solo se apunta su file_id (texto corto) para poder recuperar
-- la foto original si hace falta revisar una etiqueta (lectura dudosa, "no encontrada", etc.).
-- Hasta ahora la unica copia de esa referencia estaba en el historial de ejecuciones de n8n, que caduca.
--
--   allocation_plan_details.send_photo_file_id     foto con la que se registro el envio
--   allocation_plan_details.receive_photo_file_id  foto con la que se declaro la recepcion
--   receipt_case.photo_file_id                     foto del ultimo intento de recepcion de ese caso
--
-- bot_receive_parcel(text, text, text): igual que la de 2 argumentos (no se toca) y ademas apunta la foto.

ALTER TABLE public.allocation_plan_details
  ADD COLUMN IF NOT EXISTS send_photo_file_id text,
  ADD COLUMN IF NOT EXISTS receive_photo_file_id text;

ALTER TABLE public.receipt_case
  ADD COLUMN IF NOT EXISTS photo_file_id text;

COMMENT ON COLUMN public.allocation_plan_details.send_photo_file_id IS
  'Telegram file_id de la foto de la etiqueta con la que se registro el envio (la imagen sigue en Telegram).';
COMMENT ON COLUMN public.allocation_plan_details.receive_photo_file_id IS
  'Telegram file_id de la foto de la etiqueta con la que se declaro la recepcion (la imagen sigue en Telegram).';
COMMENT ON COLUMN public.receipt_case.photo_file_id IS
  'Telegram file_id de la foto del ultimo intento de recepcion de este caso, para revisarla despues.';

CREATE OR REPLACE FUNCTION public.bot_receive_parcel(p_telegram_id text, p_tag_raw text, p_photo_file_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb;
  v_file text := NULLIF(btrim(COALESCE(p_photo_file_id, '')), '');
BEGIN
  r := public.bot_receive_parcel(p_telegram_id, p_tag_raw);

  IF v_file IS NOT NULL THEN
    -- Fail-open: apuntar la foto nunca puede romper ni deshacer la recepcion.
    BEGIN
      IF (r->>'case_id') IS NOT NULL THEN
        UPDATE public.receipt_case SET photo_file_id = v_file WHERE id = (r->>'case_id')::uuid;
      END IF;

      IF COALESCE((r->>'registered')::boolean, false) AND (r->>'tag') IS NOT NULL THEN
        UPDATE public.allocation_plan_details d
           SET receive_photo_file_id = v_file
         WHERE d.id = (
           SELECT x.id
             FROM public.allocation_plan_details x
             JOIN public.panelists pa ON pa.account_id = x.account_id AND btrim(pa.telegram_id) = btrim(p_telegram_id)
            WHERE x.tag_id = r->>'tag' AND x.status = 'received'
            ORDER BY x.received_at DESC NULLS LAST
            LIMIT 1);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'bot_receive_parcel: no se pudo apuntar la foto: %', SQLERRM;
    END;
  END IF;

  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.bot_receive_parcel(text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bot_receive_parcel(text, text, text) TO service_role;
