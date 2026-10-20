-- El superadmin (profiles.account_id NULL) no podia LEER panelist_unavailability: solo existian politicas de
-- SELECT por cuenta, y si para insert/update/delete. Sin esto la bandeja de incidencias le sale vacia.
-- Mismo criterio que panelist_notification / panelist_reassignment_proposal (is_superadmin()).
CREATE POLICY superadmin_select_panelist_unavailability ON public.panelist_unavailability
  FOR SELECT TO authenticated
  USING (public.is_superadmin());
