-- Roles y derechos por cuenta: miembros de una cuenta para la pestaña "Roles y accesos".
-- Spec: docs/superpowers/specs/2026-11-18-roles-derechos-cuenta-design.md
--
-- La RLS de profiles solo deja leer otros perfiles a un 'admin' de su cuenta activa o al superadmin.
-- Un Account Manager / UPU account manager con profiles.role = 'user' (los usuarios nuevos lo serán)
-- no vería a sus usuarios, ni nadie vería el correo de quien tiene rol aquí pero otra cuenta activa.
--
-- Acceso: solo quien puede gestionar la pestaña de ESA cuenta (can_manage_account_access: AM o UPU AM
-- de la cuenta, o superadmin). Es el único consumidor y así un miembro sin rol de gestión no obtiene
-- la lista de correos de sus compañeros. Para cualquier otra cuenta: conjunto vacío (nunca error que
-- revele si existe).

-- Perfiles cuya cuenta activa es p_account_id + usuarios con algún rol en ella, con sus roles allí.
-- Excluye superadmins.
CREATE OR REPLACE FUNCTION public.account_members(p_account_id uuid)
 RETURNS TABLE(user_id uuid, email text, full_name text, active_here boolean, roles text[], provisional boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $$
  SELECT p.id,
         p.email::text,
         p.full_name::text,
         (p.account_id IS NOT DISTINCT FROM p_account_id),
         coalesce(array_agg(r.role ORDER BY r.role) FILTER (WHERE r.role IS NOT NULL), ARRAY[]::text[]),
         coalesce(bool_or(r.provisional), false)
    FROM public.profiles p
    LEFT JOIN public.account_user_role r ON r.user_id = p.id AND r.account_id = p_account_id
   WHERE auth.uid() IS NOT NULL
     AND public.can_manage_account_access(p_account_id)
     AND p.role IS DISTINCT FROM 'superadmin'
     AND (p.account_id = p_account_id
          OR EXISTS (SELECT 1 FROM public.account_user_role x
                      WHERE x.user_id = p.id AND x.account_id = p_account_id))
   GROUP BY p.id, p.email, p.full_name, p.account_id
   ORDER BY p.email
$$;

-- Correo de los autores (changed_by) y de los usuarios citados (detail->>'user_id') en el registro de
-- cambios de ESA cuenta. Mismo acceso. Incluye superadmins que hayan cambiado algo en la cuenta.
CREATE OR REPLACE FUNCTION public.account_log_people(p_account_id uuid)
 RETURNS TABLE(user_id uuid, email text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $$
  SELECT p.id, p.email::text
    FROM public.profiles p
   WHERE auth.uid() IS NOT NULL
     AND public.can_manage_account_access(p_account_id)
     AND p.id IN (SELECT l.changed_by FROM public.account_access_log l
                   WHERE l.account_id = p_account_id AND l.changed_by IS NOT NULL
                  UNION
                  SELECT (l.detail->>'user_id')::uuid FROM public.account_access_log l
                   WHERE l.account_id = p_account_id
                     AND l.detail->>'user_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
$$;

REVOKE ALL ON FUNCTION public.account_members(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.account_log_people(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.account_members(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.account_log_people(uuid) TO authenticated, service_role;
