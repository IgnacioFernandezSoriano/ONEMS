-- ============================================
-- ACTUALIZACIÓN DE POLÍTICAS RLS PARA GESTIÓN DE USUARIOS
-- ============================================
-- Fecha: 2026-01-02
-- Descripción: Actualiza políticas para que:
--   - Superadmin solo pueda crear admins (no otros superadmins)
--   - Admin solo pueda crear/gestionar users de su cuenta (no admins)
--   - Usuarios puedan cambiar su propia contraseña
-- ============================================

-- Eliminar políticas existentes
DROP POLICY IF EXISTS "Superadmin manages all profiles" ON profiles;
DROP POLICY IF EXISTS "Admins manage their account users" ON profiles;

-- ============================================
-- POLÍTICAS PARA SUPERADMIN
-- ============================================

-- POLÍTICA 1: Superadmin tiene acceso completo a todos los perfiles
CREATE POLICY "Superadmin full access"
  ON profiles FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'superadmin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'superadmin'
    )
  );

-- ============================================
-- POLÍTICAS PARA ADMIN
-- ============================================

-- POLÍTICA 2: Admin puede VER todos los perfiles de su cuenta
CREATE POLICY "Admin view account profiles"
  ON profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() 
      AND p.role = 'admin'
      AND p.account_id = profiles.account_id
    )
  );

-- POLÍTICA 3: Admin puede CREAR solo usuarios (role='user') de su cuenta
CREATE POLICY "Admin create users only"
  ON profiles FOR INSERT
  WITH CHECK (
    -- El que crea debe ser admin
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
    AND
    -- El nuevo usuario debe ser rol 'user'
    profiles.role = 'user'
    AND
    -- El nuevo usuario debe ser de la misma cuenta que el admin
    profiles.account_id = (
      SELECT account_id FROM profiles WHERE id = auth.uid()
    )
  );

-- POLÍTICA 4: Admin puede ACTUALIZAR solo usuarios (role='user') de su cuenta
CREATE POLICY "Admin update users only"
  ON profiles FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() 
      AND p.role = 'admin'
      AND p.account_id = profiles.account_id
    )
    AND profiles.role = 'user'
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() 
      AND p.role = 'admin'
      AND p.account_id = profiles.account_id
    )
    AND profiles.role = 'user'
  );

-- POLÍTICA 5: Admin puede DESACTIVAR usuarios (role='user') de su cuenta
CREATE POLICY "Admin deactivate users only"
  ON profiles FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() 
      AND p.role = 'admin'
      AND p.account_id = profiles.account_id
    )
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
