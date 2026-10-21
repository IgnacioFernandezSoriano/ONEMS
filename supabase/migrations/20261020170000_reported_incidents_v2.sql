-- Incidencias reportadas por el panelista, v2. Forward-only. NO toca el baseline.
-- Cada seccion la anade una tarea del plan; ver docs/superpowers/plans/ (incidencias reportadas v2, plan 1 BD).

-- ===== 1) Estado auto_resolved + razon 'materials' =====
-- auto_resolved: incidencia cerrada automaticamente por el sistema (sin accion del manager).
ALTER TABLE public.panelist_incident DROP CONSTRAINT pi_status_check;
ALTER TABLE public.panelist_incident ADD CONSTRAINT pi_status_check
  CHECK (status IN ('open','in_progress','resolved','dismissed','auto_resolved'));

-- Igual que la version de 20260806160000, pero admite tambien reason='materials'
-- (el CHECK de panelist_unavailability.reason ya la permite desde 20260807100000).
CREATE OR REPLACE FUNCTION public.create_unavailability_from_incident(
  p_incident_id uuid, p_start date, p_end date, p_reason text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid; v_panelist uuid; v_new uuid;
BEGIN
  SELECT account_id, panelist_id INTO v_account, v_panelist
    FROM panelist_incident WHERE id = p_incident_id;
  PERFORM assert_same_account(v_account);
  IF p_start IS NULL OR p_end IS NULL OR p_end < p_start THEN
    RAISE EXCEPTION 'invalid date range'; END IF;
  -- panelist_unavailability.reason es NOT NULL con CHECK IN
  -- ('vacation','sick_leave','personal','training','other','materials'); si el llamador no
  -- pasa un valor valido, usamos 'other' para no romper la constraint.
  INSERT INTO panelist_unavailability (account_id, panelist_id, start_date, end_date, reason, status)
  VALUES (
    v_account, v_panelist, p_start, p_end,
    CASE WHEN p_reason IN ('vacation','sick_leave','personal','training','other','materials')
         THEN p_reason ELSE 'other' END,
    'active')
  RETURNING id INTO v_new;  -- el trigger generate_proposals_on_unavailability_trigger dispara el motor
  UPDATE panelist_incident SET linked_unavailability_id = v_new, status = 'in_progress', updated_at = now()
  WHERE id = p_incident_id;
  RETURN v_new;
END; $$;

-- ===== 2) update_panelist_contact ampliada y validada =====
-- Implementacion unica de 9 parametros. Lleva nombre propio (_v2) para que una llamada
-- posicional de 4 argumentos no sea ambigua con la firma antigua (uuid,text,text,text).
-- NULL o '' = no tocar. Si auth.uid() IS NULL (n8n / service-role) se ignora p_telegram_id.
CREATE OR REPLACE FUNCTION public.update_panelist_contact_v2(
  p_panelist_id uuid, p_telegram_id text DEFAULT NULL,
  p_phone text DEFAULT NULL, p_language text DEFAULT NULL,
  p_email text DEFAULT NULL, p_address_line1 text DEFAULT NULL,
  p_address_line2 text DEFAULT NULL, p_address_city text DEFAULT NULL,
  p_address_country text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_account uuid;
  v_tg text      := NULLIF(btrim(p_telegram_id), '');
  v_phone text   := NULLIF(btrim(p_phone), '');
  v_lang text    := NULLIF(btrim(p_language), '');
  v_email text   := NULLIF(btrim(p_email), '');
  v_line1 text   := NULLIF(btrim(p_address_line1), '');
  v_line2 text   := NULLIF(btrim(p_address_line2), '');
  v_city text    := NULLIF(btrim(p_address_city), '');
  v_country text := NULLIF(btrim(p_address_country), '');
BEGIN
  SELECT account_id INTO v_account FROM panelists WHERE id = p_panelist_id;
  PERFORM assert_same_account(v_account);
  IF v_email IS NOT NULL AND v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'invalid email'; END IF;
  IF v_phone IS NOT NULL AND v_phone !~ '^[0-9+ ]{7,20}$' THEN
    RAISE EXCEPTION 'invalid phone'; END IF;
  IF v_lang IS NOT NULL AND v_lang NOT IN ('en','es','fr','ar') THEN
    RAISE EXCEPTION 'invalid language'; END IF;
  UPDATE panelists SET
    telegram_id = CASE WHEN auth.uid() IS NULL THEN telegram_id ELSE COALESCE(v_tg, telegram_id) END,
    mobile = COALESCE(v_phone, mobile),
    language = COALESCE(v_lang, language),
    email = COALESCE(v_email, email),
    address_line1 = COALESCE(v_line1, address_line1),
    address_line2 = COALESCE(v_line2, address_line2),
    address_city = COALESCE(v_city, address_city),
    address_country = COALESCE(v_country, address_country),
    updated_at = now()
  WHERE id = p_panelist_id;
END; $$;

-- Firma antigua: se mantiene (el frontend actual la usa) y delega en la nueva.
CREATE OR REPLACE FUNCTION public.update_panelist_contact(
  p_panelist_id uuid, p_telegram_id text DEFAULT NULL,
  p_phone text DEFAULT NULL, p_language text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.update_panelist_contact_v2(p_panelist_id, p_telegram_id, p_phone, p_language);
END; $$;

REVOKE ALL ON FUNCTION public.update_panelist_contact_v2(uuid,text,text,text,text,text,text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_panelist_contact(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_panelist_contact_v2(uuid,text,text,text,text,text,text,text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_panelist_contact(uuid,text,text,text) TO authenticated, service_role;
