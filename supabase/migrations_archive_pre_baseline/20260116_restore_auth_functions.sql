-- ============================================
-- RESTAURAR FUNCIONES AUTH PARA RLS
-- ============================================
-- Fecha: 2026-01-16
-- Descripción: Restaura funciones auth.user_account_id() y auth.is_superadmin()
--              que fueron eliminadas accidentalmente, causando que RLS
--              no filtre correctamente por account_id
-- ============================================

-- Recrear funciones en schema auth
-- Estas funciones son usadas por políticas RLS en carriers, products, etc.

CREATE OR REPLACE FUNCTION auth.user_account_id()
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT account_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION auth.is_superadmin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND role = 'superadmin'
  );
$$;

-- Comentarios
COMMENT ON FUNCTION auth.user_account_id() IS 
  'Obtiene el account_id del usuario autenticado (usado por RLS en múltiples tablas)';

COMMENT ON FUNCTION auth.is_superadmin() IS 
  'Verifica si el usuario autenticado es superadmin (usado por RLS en múltiples tablas)';
