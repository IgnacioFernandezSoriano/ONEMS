-- Motor de reasignación por baja de panelista (subsistema B) — esquema.
-- Forward-only. NO toca el baseline.

-- 1) Tabla de propuestas (una fila por muestra afectada por una baja)
CREATE TABLE public.panelist_reassignment_proposal (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  unavailability_id uuid NOT NULL,
  allocation_plan_detail_id uuid NOT NULL,
  affected_role text NOT NULL,
  sample_status_at_detection text,
  suggested_action text NOT NULL,
  suggested_target_node_id uuid,
  suggested_date date,
  suggested_reason text,
  final_action text,
  final_target_node_id uuid,
  final_date date,
  status text NOT NULL DEFAULT 'pending',
  confirmed_by uuid,
  confirmed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT panelist_reassignment_proposal_pkey PRIMARY KEY (id),
  CONSTRAINT prp_affected_role_check CHECK (affected_role IN ('origin','destination')),
  CONSTRAINT prp_suggested_action_check CHECK (suggested_action IN ('reroute','shift_date','cancel','none')),
  CONSTRAINT prp_final_action_check CHECK (final_action IS NULL OR final_action IN ('reroute','shift_date','cancel','manual')),
  CONSTRAINT prp_status_check CHECK (status IN ('pending','confirmed','dismissed')),
  CONSTRAINT prp_unavailability_fkey FOREIGN KEY (unavailability_id)
    REFERENCES public.panelist_unavailability(id) ON DELETE CASCADE,
  CONSTRAINT prp_detail_fkey FOREIGN KEY (allocation_plan_detail_id)
    REFERENCES public.allocation_plan_details(id) ON DELETE CASCADE,
  CONSTRAINT prp_target_node_fkey FOREIGN KEY (suggested_target_node_id)
    REFERENCES public.nodes(id),
  CONSTRAINT prp_final_node_fkey FOREIGN KEY (final_target_node_id)
    REFERENCES public.nodes(id),
  CONSTRAINT prp_confirmed_by_fkey FOREIGN KEY (confirmed_by)
    REFERENCES public.profiles(id)
);

CREATE INDEX idx_prp_account ON public.panelist_reassignment_proposal(account_id);
CREATE INDEX idx_prp_unavailability ON public.panelist_reassignment_proposal(unavailability_id);
CREATE INDEX idx_prp_detail ON public.panelist_reassignment_proposal(allocation_plan_detail_id);
CREATE INDEX idx_prp_account_status ON public.panelist_reassignment_proposal(account_id, status);

-- 2) RLS por account_id (+ superadmin ve todo, como el resto del proyecto)
ALTER TABLE public.panelist_reassignment_proposal ENABLE ROW LEVEL SECURITY;

CREATE POLICY prp_select ON public.panelist_reassignment_proposal
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY prp_insert ON public.panelist_reassignment_proposal
  FOR INSERT WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY prp_update ON public.panelist_reassignment_proposal
  FOR UPDATE USING (account_id = current_user_account_id() OR is_superadmin())
  WITH CHECK (account_id = current_user_account_id() OR is_superadmin());

GRANT SELECT, INSERT, UPDATE ON public.panelist_reassignment_proposal TO authenticated;

-- 3) Flag de revisión del caso (alarma / "dado por estudiado" del subsistema C)
ALTER TABLE public.panelist_unavailability
  ADD COLUMN review_status text NOT NULL DEFAULT 'pending_review';
ALTER TABLE public.panelist_unavailability
  ADD CONSTRAINT panelist_unavailability_review_status_check
  CHECK (review_status IN ('pending_review','reviewed'));

-- 4) Desactivar la reasignación automática: pasamos a modelo propuesta+confirmación.
--    La FUNCIÓN reassign_on_unavailability() se conserva (no se borra) por si hiciera
--    falta rollback; solo se quita el trigger que la disparaba.
DROP TRIGGER IF EXISTS reassign_on_unavailability_trigger ON public.panelist_unavailability;
