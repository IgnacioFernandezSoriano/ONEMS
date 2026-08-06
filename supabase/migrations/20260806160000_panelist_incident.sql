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
