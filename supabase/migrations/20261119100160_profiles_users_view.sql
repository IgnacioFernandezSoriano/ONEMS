-- Quien tiene derecho 'users' (view o edit) en su cuenta activa ve los perfiles de esa cuenta.
-- Aditiva: las políticas SELECT de profiles son PERMISSIVE (se suman con OR); no cambia ni quita
-- ninguna existente (profile_select_own / _admin / _superadmin). Sin recursión: current_user_account_id(),
-- has_access() y my_access() son SECURITY DEFINER con search_path fijo, y leen profiles sin pasar por RLS.
CREATE POLICY "profile_select_users_access" ON public.profiles
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (account_id = public.current_user_account_id()
         AND public.has_access(account_id, 'users', 'view'));
