-- ============================================
-- CORRECCIÓN DE POLÍTICAS RLS PARA GESTIÓN DE USUARIOS
-- ============================================
-- Fecha: 2026-01-02
-- Descripción: Corrige recursión infinita en políticas RLS
-- Usa función auxiliar para evitar consultas recursivas a profiles
-- ============================================

-- Eliminar políticas anteriores que causan recursión
DROP POLICY IF EXISTS "Superadmin full access" ON profiles;
DROP POLICY IF EXISTS "Admin view account profiles" ON profiles;
DROP POLICY IF EXISTS "Admin create users only" ON profiles;
DROP POLICY IF EXISTS "Admin update users only" ON profiles;
DROP POLICY IF EXISTS "Admin deactivate users only" ON profiles;
DROP POLICY IF EXISTS "Users view own profile" ON profiles;
DROP POLICY IF EXISTS "Users update own profile" ON profiles;

-- ============================================
-- FUNCIÓN AUXILIAR PARA OBTENER ROL SIN RLS
-- ============================================

-- Crear o reemplazar función que obtiene el rol del usuario actual
-- Esta función se ejecuta con privilegios de SECURITY DEFINER para evitar RLS
CREATE OR REPLACE FUNCTION auth.get_user_role()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_role TEXT;
BEGIN
  SELECT role INTO user_role
  FROM public.profiles
  WHERE id = auth.uid();
  
  RETURN user_role;
END;
$$;

-- Crear o reemplazar función que obtiene el account_id del usuario actual
CREATE OR REPLACE FUNCTION auth.get_user_account_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_account_id UUID;
BEGIN
  SELECT account_id INTO user_account_id
  FROM public.profiles
  WHERE id = auth.uid();
  
  RETURN user_account_id;
END;
$$;

-- ============================================
-- POLÍTICAS PARA SUPERADMIN
-- ============================================

-- POLÍTICA 1: Superadmin tiene acceso completo a todos los perfiles
CREATE POLICY "Superadmin full access"
  ON profiles FOR ALL
  USING (auth.get_user_role() = 'superadmin')
  WITH CHECK (auth.get_user_role() = 'superadmin');

-- ============================================
-- POLÍTICAS PARA ADMIN
-- ============================================

-- POLÍTICA 2: Admin puede VER todos los perfiles de su cuenta
CREATE POLICY "Admin view account profiles"
  ON profiles FOR SELECT
  USING (
    auth.get_user_role() = 'admin'
    AND profiles.account_id = auth.get_user_account_id()
  );

-- POLÍTICA 3: Admin puede CREAR solo usuarios (role='user') de su cuenta
CREATE POLICY "Admin create users only"
  ON profiles FOR INSERT
  WITH CHECK (
    auth.get_user_role() = 'admin'
    AND profiles.role = 'user'
    AND profiles.account_id = auth.get_user_account_id()
  );

-- POLÍTICA 4: Admin puede ACTUALIZAR solo usuarios (role='user') de su cuenta
CREATE POLICY "Admin update users only"
  ON profiles FOR UPDATE
  USING (
    auth.get_user_role() = 'admin'
    AND profiles.account_id = auth.get_user_account_id()
    AND profiles.role = 'user'
  )
  WITH CHECK (
    auth.get_user_role() = 'admin'
    AND profiles.account_id = auth.get_user_account_id()
    AND profiles.role = 'user'
  );

-- POLÍTICA 5: Admin puede DESACTIVAR usuarios (role='user') de su cuenta
CREATE POLICY "Admin deactivate users only"
  ON profiles FOR DELETE
  USING (
    auth.get_user_role() = 'admin'
    AND profiles.account_id = auth.get_user_account_id()
    AND profiles.role = 'user'
  );

-- ============================================
-- POLÍTICAS PARA USUARIOS REGULARES
-- ============================================

-- POLÍTICA 6: Usuarios pueden ver su propio perfil
CREATE POLICY "Users view own profile"
  ON profiles FOR SELECT
  USING (id = auth.uid());

-- POLÍTICA 7: Usuarios pueden actualizar su propio perfil (nombre, idioma, etc.)
-- Nota: El cambio de contraseña se hace via Supabase Auth, no via profiles
CREATE POLICY "Users update own profile"
  ON profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- ============================================
-- COMENTARIOS Y DOCUMENTACIÓN
-- ============================================

COMMENT ON FUNCTION auth.get_user_role() IS 
  'Obtiene el rol del usuario autenticado sin pasar por RLS para evitar recursión infinita';

COMMENT ON FUNCTION auth.get_user_account_id() IS 
  'Obtiene el account_id del usuario autenticado sin pasar por RLS';

COMMENT ON POLICY "Superadmin full access" ON profiles IS 
  'Superadmin tiene acceso completo a todos los perfiles para gestión global';

COMMENT ON POLICY "Admin view account profiles" ON profiles IS 
  'Admin puede ver todos los perfiles de su cuenta (admins y users)';

COMMENT ON POLICY "Admin create users only" ON profiles IS 
  'Admin solo puede crear usuarios con role=user de su propia cuenta';

COMMENT ON POLICY "Admin update users only" ON profiles IS 
  'Admin solo puede actualizar usuarios con role=user de su cuenta, no puede modificar admins';

COMMENT ON POLICY "Admin deactivate users only" ON profiles IS 
  'Admin solo puede desactivar usuarios con role=user de su cuenta';

COMMENT ON POLICY "Users view own profile" ON profiles IS 
  'Usuarios regulares pueden ver su propio perfil';

COMMENT ON POLICY "Users update own profile" ON profiles IS 
  'Usuarios regulares pueden actualizar campos de su propio perfil (nombre, idioma preferido)';
