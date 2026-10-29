-- El superadmin no tiene account_id en su perfil, asi que la politica de lectura
-- de one_db (solo la cuenta propia) le devolvia 0 filas en la pantalla E2E DB.
-- Mismo patron que superadmin_select_allocation_plan_details y demas tablas.
DROP POLICY IF EXISTS superadmin_select_one_db ON public.one_db;
CREATE POLICY superadmin_select_one_db ON public.one_db
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.profiles
     WHERE profiles.id = auth.uid() AND profiles.role = 'superadmin'
  ));
