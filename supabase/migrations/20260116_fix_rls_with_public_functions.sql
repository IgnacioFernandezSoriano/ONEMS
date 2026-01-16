-- ============================================
-- SOLUCIÓN DEFINITIVA: FUNCIONES RLS EN PUBLIC
-- ============================================
-- Fecha: 2026-01-16
-- Descripción: No tenemos permisos para crear funciones en schema auth,
--              así que creamos funciones equivalentes en public y
--              actualizamos todas las políticas RLS para usarlas.
-- ============================================

-- ============================================
-- PASO 1: CREAR FUNCIONES EN PUBLIC SCHEMA
-- ============================================

-- Obtiene el account_id del usuario actual
CREATE OR REPLACE FUNCTION public.get_user_account_id()
RETURNS UUID AS $$
  SELECT account_id FROM public.profiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Verifica si el usuario es superadmin
CREATE OR REPLACE FUNCTION public.is_user_superadmin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND role = 'superadmin'
  )
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ============================================
-- PASO 2: ACTUALIZAR POLÍTICAS DE ACCOUNTS
-- ============================================

-- Eliminar políticas antiguas
DROP POLICY IF EXISTS "Superadmin manages all accounts" ON accounts;
DROP POLICY IF EXISTS "Users view their own account" ON accounts;

-- Recrear con nuevas funciones
CREATE POLICY "Superadmin manages all accounts"
  ON accounts FOR ALL
  USING (public.is_user_superadmin())
  WITH CHECK (public.is_user_superadmin());

CREATE POLICY "Users view their own account"
  ON accounts FOR SELECT
  USING (id = public.get_user_account_id());

-- ============================================
-- PASO 3: ACTUALIZAR POLÍTICAS DE PROFILES
-- ============================================

-- Eliminar políticas antiguas
DROP POLICY IF EXISTS "Superadmin manages all profiles" ON profiles;

-- Recrear con nuevas funciones
CREATE POLICY "Superadmin manages all profiles"
  ON profiles FOR ALL
  USING (public.is_user_superadmin())
  WITH CHECK (public.is_user_superadmin());

-- ============================================
-- PASO 4: ACTUALIZAR TRIGGER DE ACCOUNT_ID
-- ============================================

-- Actualizar función del trigger para usar la nueva función
CREATE OR REPLACE FUNCTION set_account_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.account_id IS NULL THEN
    NEW.account_id := public.get_user_account_id();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- VERIFICACIÓN
-- ============================================

-- Comentarios para documentar
COMMENT ON FUNCTION public.get_user_account_id() IS 
  'Obtiene el account_id del usuario autenticado (reemplazo de auth.user_account_id)';

COMMENT ON FUNCTION public.is_user_superadmin() IS 
  'Verifica si el usuario autenticado es superadmin (reemplazo de auth.is_superadmin)';

-- ============================================
-- NOTA IMPORTANTE
-- ============================================
-- Estas funciones reemplazan auth.user_account_id() y auth.is_superadmin()
-- que no podemos crear debido a permisos en el schema auth.
-- 
-- Las políticas RLS de las siguientes tablas ahora usan estas funciones:
-- - accounts ✓
-- - profiles ✓
-- 
-- IMPORTANTE: Si hay otras tablas con políticas RLS que usen las funciones
-- antiguas (auth.*), necesitarán ser actualizadas también.
