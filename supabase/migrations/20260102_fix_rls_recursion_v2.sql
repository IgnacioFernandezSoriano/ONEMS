-- ============================================
-- CORRECCIÓN DE RECURSIÓN INFINITA EN POLÍTICAS RLS
-- ============================================
-- Fecha: 2026-01-02
-- Descripción: Corrige recursión infinita en políticas RLS de profiles
-- Crea funciones helper en schema public con SECURITY DEFINER
-- ============================================

-- ============================================
-- PASO 1: ELIMINAR POLÍTICAS ANTIGUAS
-- ============================================

DROP POLICY IF EXISTS "Superadmin manages all profiles" ON profiles;
DROP POLICY IF EXISTS "Admins manage their account users" ON profiles;
DROP POLICY IF EXISTS "Users view their own profile" ON profiles;
DROP POLICY IF EXISTS "Superadmin full access" ON profiles;
DROP POLICY IF EXISTS "Admin view account profiles" ON profiles;
DROP POLICY IF EXISTS "Admin create users only" ON profiles;
DROP POLICY IF EXISTS "Admin update users only" ON profiles;
DROP POLICY IF EXISTS "Admin deactivate users only" ON profiles;
DROP POLICY IF EXISTS "Users view own profile" ON profiles;
DROP POLICY IF EXISTS "Users update own profile" ON profiles;

-- ============================================
-- PASO 2: REEMPLAZAR FUNCIONES HELPER
-- ============================================

-- Eliminar funciones antiguas que causan recursión
DROP FUNCTION IF EXISTS auth.is_superadmin();
DROP FUNCTION IF EXISTS auth.user_account_id();

-- Crear funciones en schema public (tenemos permisos aquí)
-- Estas funciones usan SECURITY DEFINER para bypassear RLS

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_user_account_id()
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT account_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;

-- ============================================
-- PASO 3: CREAR POLÍTICAS SIN RECURSIÓN
-- ============================================

-- POLÍTICA 1: Superadmin tiene acceso completo
CREATE POLICY "superadmin_full_access"
  ON profiles FOR ALL
  USING (public.current_user_role() = 'superadmin')
  WITH CHECK (public.current_user_role() = 'superadmin');

-- POLÍTICA 2: Admin puede VER perfiles de su cuenta
CREATE POLICY "admin_view_account_profiles"
  ON profiles FOR SELECT
  USING (
    public.current_user_role() = 'admin'
    AND profiles.account_id = public.current_user_account_id()
  );

-- POLÍTICA 3: Admin puede CREAR solo usuarios de su cuenta
CREATE POLICY "admin_create_users"
  ON profiles FOR INSERT
  WITH CHECK (
    public.current_user_role() = 'admin'
    AND profiles.role = 'user'
    AND profiles.account_id = public.current_user_account_id()
  );

-- POLÍTICA 4: Admin puede ACTUALIZAR solo usuarios de su cuenta
CREATE POLICY "admin_update_users"
  ON profiles FOR UPDATE
  USING (
    public.current_user_role() = 'admin'
    AND profiles.account_id = public.current_user_account_id()
    AND profiles.role = 'user'
  )
  WITH CHECK (
    public.current_user_role() = 'admin'
    AND profiles.account_id = public.current_user_account_id()
    AND profiles.role = 'user'
  );

-- POLÍTICA 5: Admin puede DESACTIVAR usuarios de su cuenta
CREATE POLICY "admin_delete_users"
  ON profiles FOR DELETE
  USING (
    public.current_user_role() = 'admin'
    AND profiles.account_id = public.current_user_account_id()
    AND profiles.role = 'user'
  );

-- POLÍTICA 6: Usuarios ven su propio perfil
CREATE POLICY "users_view_own_profile"
  ON profiles FOR SELECT
  USING (id = auth.uid());

-- POLÍTICA 7: Usuarios actualizan su propio perfil
CREATE POLICY "users_update_own_profile"
  ON profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- ============================================
-- PASO 4: COMENTARIOS
-- ============================================

COMMENT ON FUNCTION public.current_user_role() IS 
  'Obtiene el rol del usuario autenticado sin recursión RLS';

COMMENT ON FUNCTION public.current_user_account_id() IS 
  'Obtiene el account_id del usuario autenticado sin recursión RLS';

COMMENT ON POLICY "superadmin_full_access" ON profiles IS 
  'Superadmin tiene acceso completo a todos los perfiles';

COMMENT ON POLICY "admin_view_account_profiles" ON profiles IS 
  'Admin puede ver perfiles de su cuenta';

COMMENT ON POLICY "admin_create_users" ON profiles IS 
  'Admin solo puede crear usuarios (role=user) de su cuenta';

COMMENT ON POLICY "admin_update_users" ON profiles IS 
  'Admin solo puede actualizar usuarios de su cuenta';

COMMENT ON POLICY "admin_delete_users" ON profiles IS 
  'Admin solo puede desactivar usuarios de su cuenta';

COMMENT ON POLICY "users_view_own_profile" ON profiles IS 
  'Usuarios ven su propio perfil';

COMMENT ON POLICY "users_update_own_profile" ON profiles IS 
  'Usuarios actualizan su propio perfil';
