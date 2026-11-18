-- is_superadmin() leía "profiles" sin esquema y sin search_path propio: llamada desde funciones con
-- search_path vacío (plan_action_* / plan_undo_*, 20261118) fallaba con 'relation "profiles" does not exist'
-- (superadmin borrando o deshaciendo en Allocation Plans sobre una cuenta que no es la suya).
-- Mismo arreglo que ya tiene current_user_account_id(): search_path fijo y tabla cualificada. Sin cambio de permisos.
CREATE OR REPLACE FUNCTION public.is_superadmin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'superadmin'
  )
$function$;
