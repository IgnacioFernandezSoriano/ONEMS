-- GPS al declarar: el historico de permisos de ubicacion es evidencia legal y debe sobrevivir al borrado del
-- panelista (y de la cuenta). Forward-only sobre 20261117150000_gps_declaracion.sql y 20261117151000_gps_ask_once.sql.
-- 1) panelist_location_consent.panelist_id / account_id pasan a NULLables; sus FKs pasan de ON DELETE CASCADE a
--    ON DELETE SET NULL (al borrar el panelista la fila queda con panelist_id NULL, no se pierde).
-- 2) Columnas instantanea panelist_code / panelist_name (quien era, aunque ya no exista); backfill desde panelists.
-- 3) gps_record_consent: mismo cuerpo que 20261117151000, solo guarda ademas la instantanea. Mismos permisos.
-- 4) pg_cron 'gps-purge-coordinates' pasa de mensual a diario (03:00 UTC): el borrado a los 12 meses es al dia.
-- gps_current_consent no cambia (busca por panelist_id).

-- 1. NULLables + FKs ON DELETE SET NULL
ALTER TABLE public.panelist_location_consent ALTER COLUMN panelist_id DROP NOT NULL;
ALTER TABLE public.panelist_location_consent ALTER COLUMN account_id DROP NOT NULL;

ALTER TABLE public.panelist_location_consent DROP CONSTRAINT IF EXISTS plc_panelist_fkey;
ALTER TABLE public.panelist_location_consent
  ADD CONSTRAINT plc_panelist_fkey FOREIGN KEY (panelist_id) REFERENCES public.panelists(id) ON DELETE SET NULL;
ALTER TABLE public.panelist_location_consent DROP CONSTRAINT IF EXISTS plc_account_fkey;
ALTER TABLE public.panelist_location_consent
  ADD CONSTRAINT plc_account_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE SET NULL;

-- 2. Instantanea del panelista + backfill
ALTER TABLE public.panelist_location_consent ADD COLUMN IF NOT EXISTS panelist_code text;
ALTER TABLE public.panelist_location_consent ADD COLUMN IF NOT EXISTS panelist_name text;

UPDATE public.panelist_location_consent c
   SET panelist_code = p.panelist_code, panelist_name = p.name
  FROM public.panelists p
 WHERE p.id = c.panelist_id
   AND (c.panelist_code IS NULL OR c.panelist_name IS NULL);

-- 3. gps_record_consent (cuerpo de 20261117151000 + instantanea)
CREATE OR REPLACE FUNCTION public.gps_record_consent(
  p_panelist_id uuid, p_decision text, p_language text, p_text_version text, p_text text, p_message_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_p panelists; v_prev text; v_id uuid; v_inc uuid; v panelist_context; v_need_location boolean;
BEGIN
  IF p_decision IS NULL OR p_decision NOT IN ('granted','denied') THEN RAISE EXCEPTION 'invalid decision'; END IF;
  SELECT * INTO v_p FROM panelists WHERE id = p_panelist_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'panelist not found'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('gps_consent:' || p_panelist_id::text));
  v_prev := public.gps_current_consent(p_panelist_id);

  INSERT INTO panelist_location_consent (account_id, panelist_id, telegram_id, decision, language,
                                         consent_text_version, consent_text, telegram_message_id, source,
                                         panelist_code, panelist_name)
  VALUES (v_p.account_id, p_panelist_id, v_p.telegram_id, p_decision, p_language,
          p_text_version, p_text, p_message_id, 'bot',
          v_p.panelist_code, v_p.name)
  RETURNING id INTO v_id;

  IF p_decision = 'denied' AND v_prev IS DISTINCT FROM 'denied' THEN
    v_inc := public.insert_panelist_incident_auto(p_panelist_id, 'gps_location',
      '📍 Panelist did not accept sharing their location when declaring',
      '{"reason":"consent_denied"}'::jsonb, NULL, 'open');
  END IF;

  v := public.gps_get_visit(p_panelist_id, v_p.telegram_id);
  v_need_location := p_decision = 'granted' AND (public.gps_visit_location(v.context_data)).id IS NULL
                     AND NOT COALESCE((v.context_data->>'gps_unavailable')::boolean, false);
  -- 2026-11-17 (ask once): el bot manda el teclado de ubicacion justo despues del "Acepto": cuenta como la peticion
  -- de la visita, para que el siguiente "Confirmar..." de esa visita no la repita.
  IF v_need_location THEN
    UPDATE panelist_context SET context_data = context_data || '{"location_asked": true}'::jsonb WHERE id = v.id;
  END IF;
  RETURN jsonb_build_object('consent_id', v_id, 'decision', p_decision, 'incident_id', v_inc,
    'need_location', v_need_location);
END; $$;

REVOKE ALL ON FUNCTION public.gps_record_consent(uuid,text,text,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gps_record_consent(uuid,text,text,text,text,text) TO service_role;

-- 4. pg_cron: borrado de coordenadas DIARIO (03:00 UTC; idempotente)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'gps-purge-coordinates') THEN
    PERFORM cron.unschedule('gps-purge-coordinates');
  END IF;
  PERFORM cron.schedule('gps-purge-coordinates', '0 3 * * *', 'SELECT public.gps_purge_coordinates()');
END $$;
