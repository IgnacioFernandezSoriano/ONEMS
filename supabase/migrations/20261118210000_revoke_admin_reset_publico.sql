-- EMERGENCIA 18/11/2026: funciones de reset ejecutables sin sesión.
-- admin_reset_account_data(p_account_identifier) es SECURITY DEFINER, no comprueba quién llama y borra todos los
-- datos de la cuenta indicada (por nombre o id). Tenía EXECUTE para PUBLIC/anon/authenticated: cualquiera con la
-- clave pública de la web podía vaciar cualquier país. Lo mismo las de reset de DEMO2.
-- Ni la web, ni las edge functions, ni n8n las llaman (verificado en el repo): se quita EXECUTE a todos salvo
-- service_role (y el dueño postgres). Sin cambio de cuerpo.
REVOKE ALL ON FUNCTION public.admin_reset_account_data(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_reset_account_data_backup(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_reset_demo2() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_reset_and_seed_demo2() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reset_account_data(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_reset_account_data_backup(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_reset_demo2() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_reset_and_seed_demo2() TO service_role;
