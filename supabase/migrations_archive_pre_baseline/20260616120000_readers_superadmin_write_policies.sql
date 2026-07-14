-- =====================================================
-- readers: allow superadmin to write (INSERT/UPDATE/DELETE) for ANY account.
-- A superadmin has no own account_id, so the existing *_own_account write
-- policies (account_id = current_user_account_id()) never pass -> creating a
-- reader from the Readers Management screen failed with
-- "new row violates row-level security policy for table readers".
-- This mirrors the existing read policy `readers_select_superadmin`.
-- =====================================================

DROP POLICY IF EXISTS readers_insert_superadmin ON public.readers;
CREATE POLICY readers_insert_superadmin ON public.readers
  FOR INSERT TO authenticated
  WITH CHECK (current_user_role() = 'superadmin');

DROP POLICY IF EXISTS readers_update_superadmin ON public.readers;
CREATE POLICY readers_update_superadmin ON public.readers
  FOR UPDATE TO authenticated
  USING (current_user_role() = 'superadmin')
  WITH CHECK (current_user_role() = 'superadmin');

DROP POLICY IF EXISTS readers_delete_superadmin ON public.readers;
CREATE POLICY readers_delete_superadmin ON public.readers
  FOR DELETE TO authenticated
  USING (current_user_role() = 'superadmin');
