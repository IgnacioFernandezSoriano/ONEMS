-- Incidencias reportadas por el panelista (vía Telegram/n8n). Forward-only. NO toca baseline.

CREATE TABLE public.panelist_incident (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  panelist_id uuid NOT NULL,
  category text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  description text,
  photo_url text,
  allocation_plan_detail_id uuid,
  linked_unavailability_id uuid,
  payload jsonb,
  resolution_note text,
  reply_to_panelist text,
  reply_status text NOT NULL DEFAULT 'none',
  reply_sent_at timestamptz,
  created_via text NOT NULL DEFAULT 'telegram',
  reported_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolved_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT panelist_incident_pkey PRIMARY KEY (id),
  CONSTRAINT pi_category_check CHECK (category IN (
    'missing_materials','unreadable_label_receipt','parcel_damaged','parcel_returned',
    'how_to_send','unavailability_request','tag_photo_problem','contact_data_change','other')),
  CONSTRAINT pi_status_check CHECK (status IN ('open','in_progress','resolved','dismissed')),
  CONSTRAINT pi_reply_status_check CHECK (reply_status IN ('none','pending_send','sent')),
  CONSTRAINT pi_panelist_fkey FOREIGN KEY (panelist_id) REFERENCES public.panelists(id) ON DELETE CASCADE,
  CONSTRAINT pi_detail_fkey FOREIGN KEY (allocation_plan_detail_id) REFERENCES public.allocation_plan_details(id) ON DELETE SET NULL,
  CONSTRAINT pi_unavailability_fkey FOREIGN KEY (linked_unavailability_id) REFERENCES public.panelist_unavailability(id) ON DELETE SET NULL,
  CONSTRAINT pi_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES public.profiles(id)
);

CREATE INDEX idx_pi_account_status ON public.panelist_incident(account_id, status);
CREATE INDEX idx_pi_panelist ON public.panelist_incident(panelist_id);
CREATE INDEX idx_pi_detail ON public.panelist_incident(allocation_plan_detail_id);
CREATE INDEX idx_pi_reply_pending ON public.panelist_incident(account_id) WHERE reply_status = 'pending_send';

ALTER TABLE public.panelist_incident ENABLE ROW LEVEL SECURITY;

CREATE POLICY pi_select ON public.panelist_incident
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY pi_insert ON public.panelist_incident
  FOR INSERT WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY pi_update ON public.panelist_incident
  FOR UPDATE USING (account_id = current_user_account_id() OR is_superadmin())
  WITH CHECK (account_id = current_user_account_id() OR is_superadmin());

GRANT SELECT, INSERT, UPDATE ON public.panelist_incident TO authenticated;

-- Bucket privado para fotos adjuntas (n8n sube con service-role; la app genera signed URLs).
-- Guard: el Postgres portable local para tests no tiene el schema `storage`; en prod sí existe.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'storage') THEN
    INSERT INTO storage.buckets (id, name, public)
    VALUES ('incident-photos', 'incident-photos', false)
    ON CONFLICT (id) DO NOTHING;
  END IF;
END $$;

-- ===========================================================================
-- RPCs de acción para incidencias reportadas por el panelista (Task 2)
-- ===========================================================================

-- Guarda cross-tenant reutilizable: lanza si el actor no puede tocar esa cuenta.
CREATE OR REPLACE FUNCTION public.assert_same_account(p_account_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_account_id IS NULL THEN RAISE EXCEPTION 'account not found'; END IF;
  IF auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND (SELECT account_id FROM profiles WHERE id = auth.uid()) IS DISTINCT FROM p_account_id THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;
END; $$;

-- Resolver / actualizar estado + respuesta al panelista.
CREATE OR REPLACE FUNCTION public.resolve_panelist_incident(
  p_incident_id uuid, p_status text,
  p_resolution_note text DEFAULT NULL, p_reply_text text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM panelist_incident WHERE id = p_incident_id;
  PERFORM assert_same_account(v_account);
  IF p_status NOT IN ('open','in_progress','resolved','dismissed') THEN
    RAISE EXCEPTION 'invalid status %', p_status; END IF;
  UPDATE panelist_incident SET
    status = p_status,
    resolution_note = COALESCE(p_resolution_note, resolution_note),
    reply_to_panelist = COALESCE(p_reply_text, reply_to_panelist),
    reply_status = CASE WHEN p_reply_text IS NOT NULL THEN 'pending_send' ELSE reply_status END,
    resolved_by = CASE WHEN p_status IN ('resolved','dismissed') THEN auth.uid() ELSE resolved_by END,
    resolved_at = CASE WHEN p_status IN ('resolved','dismissed') THEN now() ELSE resolved_at END,
    updated_at = now()
  WHERE id = p_incident_id;
END; $$;

-- Registrar recepción a mano (etiqueta ilegible / problema de foto).
-- NOTA: el trigger baseline trigger_transfer_to_one_db / transfer_to_one_db() se dispara
-- en todo UPDATE que ponga status='received', y su guarda es
-- `NEW.transferred_to_one_db_at IS NULL` (baseline linea 7272). Las incidencias que usan
-- esta RPC (etiqueta ilegible, foto de tag con problema) son precisamente los casos con
-- datos incompletos (sent_at/tag_id/origin-destination panelist faltantes), asi que si se
-- deja correr el trigger este intenta `UPDATE ... SET status='invalid'`, que viola
-- allocation_plan_details_status_check ('invalid' no es un valor permitido) y aborta el RPC.
-- Seteando transferred_to_one_db_at = now() en el mismo UPDATE se cumple la guarda del
-- trigger (queda en NOT NULL) y el trigger no entra en su rama de validacion/transferencia;
-- el detalle igual queda status='received' (es una recepcion real). No tocar el trigger
-- baseline: ese bug (usar 'invalid' sin que este en el CHECK) se rastrea aparte.
CREATE OR REPLACE FUNCTION public.mark_detail_received_manual(p_detail_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM allocation_plan_details WHERE id = p_detail_id;
  PERFORM assert_same_account(v_account);
  UPDATE allocation_plan_details
  SET status = 'received', received_at = now(), transferred_to_one_db_at = now(), updated_at = now()
  WHERE id = p_detail_id;
END; $$;

-- Invalidar muestra (paquete roto).
-- NOTA: allocation_plan_details_status_check (baseline linea 997) permite
-- ('pending','notified','sent','received','cancelled','incident'); NO incluye 'invalid'
-- (aunque un trigger existente en baseline lo usa, lo que violaria la constraint).
-- Se usa 'incident' como marcador valido de "muestra invalidada / con problema".
CREATE OR REPLACE FUNCTION public.invalidate_detail(p_detail_id uuid, p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM allocation_plan_details WHERE id = p_detail_id;
  PERFORM assert_same_account(v_account);
  UPDATE allocation_plan_details SET status = 'incident', updated_at = now() WHERE id = p_detail_id;
END; $$;

-- Reprogramar fecha (devuelto al remitente).
CREATE OR REPLACE FUNCTION public.reschedule_detail(p_detail_id uuid, p_new_date date)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM allocation_plan_details WHERE id = p_detail_id;
  PERFORM assert_same_account(v_account);
  IF p_new_date IS NULL THEN RAISE EXCEPTION 'new date required'; END IF;
  UPDATE allocation_plan_details SET fecha_programada = p_new_date, updated_at = now() WHERE id = p_detail_id;
END; $$;

-- Cancelar muestra.
CREATE OR REPLACE FUNCTION public.cancel_detail(p_detail_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM allocation_plan_details WHERE id = p_detail_id;
  PERFORM assert_same_account(v_account);
  UPDATE allocation_plan_details SET status = 'cancelled', updated_at = now() WHERE id = p_detail_id;
END; $$;

-- Actualizar datos de contacto del panelista (solo los no-nulos).
-- NOTA: la columna de telefono en panelists es `mobile` (no `phone`). El parametro
-- se mantiene como p_phone para que coincida con la llamada del hook (Task 3),
-- pero se asigna a la columna `mobile`.
CREATE OR REPLACE FUNCTION public.update_panelist_contact(
  p_panelist_id uuid, p_telegram_id text DEFAULT NULL,
  p_phone text DEFAULT NULL, p_language text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM panelists WHERE id = p_panelist_id;
  PERFORM assert_same_account(v_account);
  UPDATE panelists SET
    telegram_id = COALESCE(p_telegram_id, telegram_id),
    mobile = COALESCE(p_phone, mobile),
    language = COALESCE(p_language, language),
    updated_at = now()
  WHERE id = p_panelist_id;
END; $$;

-- Crear baja desde una incidencia (peticion de baja) -> el trigger genera propuestas.
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
  -- ('vacation','sick_leave','personal','training','other'); si el llamador no
  -- pasa un valor valido, usamos 'other' para no romper la constraint.
  INSERT INTO panelist_unavailability (account_id, panelist_id, start_date, end_date, reason, status)
  VALUES (
    v_account, v_panelist, p_start, p_end,
    CASE WHEN p_reason IN ('vacation','sick_leave','personal','training','other')
         THEN p_reason ELSE 'other' END,
    'active')
  RETURNING id INTO v_new;  -- el trigger generate_proposals_on_unavailability_trigger dispara el motor
  UPDATE panelist_incident SET linked_unavailability_id = v_new, status = 'in_progress', updated_at = now()
  WHERE id = p_incident_id;
  RETURN v_new;
END; $$;

GRANT EXECUTE ON FUNCTION public.resolve_panelist_incident(uuid,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_detail_received_manual(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_detail(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reschedule_detail(uuid,date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_panelist_contact(uuid,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_unavailability_from_incident(uuid,date,date,text) TO authenticated;
