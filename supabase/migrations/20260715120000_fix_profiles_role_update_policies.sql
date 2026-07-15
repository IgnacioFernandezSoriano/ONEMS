-- Cambio de rol en `public.profiles`: reglas explícitas y sin agujeros.
--
-- Problema 1 (seguridad): sobre `profiles` convivían 6 políticas de UPDATE más
-- 2 FOR ALL. Las políticas PERMISSIVE se suman con OR, así que bastaba con que
-- una dejara pasar. `users_update_own_profile` tenía WITH CHECK (id = auth.uid())
-- sin ninguna cláusula sobre `role`, de modo que cualquier usuario autenticado
-- podía auto-promocionarse a superadmin. Aquí se borran todas y se dejan tres.
--
-- Problema 2 (funcional): degradar a un superadmin era imposible. La restricción
-- `check_account_role` exige que un superadmin tenga account_id NULL y que el
-- resto de roles tengan cuenta, pero el trigger `prevent_account_id_change`
-- sólo dejaba pasar un cambio de cuenta cuando NEW.role = 'superadmin'. Bajar de
-- superadmin a admin (NULL -> cuenta) reventaba siempre; y `transferUser`
-- (mover un usuario normal de cuenta, siendo superadmin) también.
--
-- Reglas objetivo:
--   superadmin -> cualquier cambio de rol, en cualquier cuenta.
--   admin      -> sólo entre 'admin' y 'user', y sólo dentro de su cuenta.
--   user       -> ningún cambio de rol (sí puede editar sus propios datos).

BEGIN;

-- 1. Fuera todas las políticas de UPDATE solapadas.
DROP POLICY IF EXISTS "Users update their own profile" ON public.profiles;
DROP POLICY IF EXISTS "admin_update_users"            ON public.profiles;
DROP POLICY IF EXISTS "profile_update_admin"          ON public.profiles;
DROP POLICY IF EXISTS "profile_update_own"            ON public.profiles;
DROP POLICY IF EXISTS "profile_update_superadmin"     ON public.profiles;
DROP POLICY IF EXISTS "users_update_own_profile"      ON public.profiles;

-- Las dos FOR ALL también otorgaban UPDATE. SELECT / INSERT / DELETE del
-- superadmin siguen cubiertos por profile_select_superadmin,
-- profile_insert_superadmin y profile_delete_superadmin, que se quedan.
DROP POLICY IF EXISTS "superadmin_full_access"        ON public.profiles;
DROP POLICY IF EXISTS "Superadmin manages all profiles" ON public.profiles;

-- 2. Las tres reglas.

CREATE POLICY "profiles_update_superadmin" ON public.profiles
  FOR UPDATE TO authenticated
  USING      (current_user_role() = 'superadmin')
  WITH CHECK (current_user_role() = 'superadmin');

-- USING = filas que puede tocar (las de su cuenta, nunca un superadmin).
-- WITH CHECK = resultado admitido: el rol final sólo puede ser admin o user y
-- la fila no puede salir de su cuenta.
CREATE POLICY "profiles_update_admin" ON public.profiles
  FOR UPDATE TO authenticated
  USING (
    current_user_role() = 'admin'
    AND account_id = current_user_account_id()
    AND role <> 'superadmin'
  )
  WITH CHECK (
    current_user_role() = 'admin'
    AND account_id = current_user_account_id()
    AND role IN ('admin', 'user')
  );

-- Cualquiera puede editar su propia ficha, pero `role` y `account_id` tienen que
-- quedar como estaban. current_user_role() es STABLE y lee el snapshot previo al
-- UPDATE, así que devuelve el rol viejo y la comparación detecta el intento.
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE TO authenticated
  USING      (id = auth.uid())
  WITH CHECK (
    id = auth.uid()
    AND role = current_user_role()
    AND account_id IS NOT DISTINCT FROM current_user_account_id()
  );

-- 3. El trigger deja de bloquear los movimientos de cuenta legítimos.
CREATE OR REPLACE FUNCTION public.prevent_account_id_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Solo la tabla `profiles` tiene columna `role` por fila.
  -- Se accede a NEW.role únicamente dentro de esta rama para que en el resto
  -- de tablas (sin columna role) nunca se evalúe y no falle en runtime.
  IF TG_TABLE_NAME = 'profiles' THEN
    -- Un cambio de rol arrastra la cuenta por `check_account_role`: subir a
    -- superadmin obliga a vaciarla y bajar de superadmin obliga a asignarla.
    IF OLD.role IS DISTINCT FROM NEW.role THEN
      RETURN NEW;
    END IF;
    -- Mover un perfil de cuenta sin tocar el rol es una transferencia, y sólo
    -- la puede hacer un superadmin. Quién es el actor lo verifica RLS; esto
    -- únicamente levanta el veto general del trigger.
    IF is_user_superadmin() THEN
      RETURN NEW;
    END IF;
  END IF;

  IF OLD.account_id IS DISTINCT FROM NEW.account_id THEN
    RAISE EXCEPTION 'account_id cannot be changed after creation';
  END IF;

  RETURN NEW;
END;
$function$;

COMMIT;
