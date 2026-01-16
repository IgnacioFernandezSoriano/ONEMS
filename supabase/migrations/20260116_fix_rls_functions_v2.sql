-- ============================================
-- SOLUCIÓN DEFINITIVA: RECREAR FUNCIONES RLS
-- ============================================
-- Fecha: 2026-01-16
-- Descripción: Las funciones auth.user_account_id() y auth.is_superadmin()
--              fueron eliminadas por error, causando que RLS no filtre por cuenta.
--              Esta migración las recrea en el esquema correcto.
-- ============================================

-- IMPORTANTE: Estas funciones YA EXISTEN en el esquema original (001_initial_schema.sql)
-- pero fueron eliminadas en 20260102_fix_rls_recursion_v2.sql
-- Necesitamos recrearlas EXACTAMENTE como estaban

-- ============================================
-- RECREAR FUNCIONES (sintaxis original)
-- ============================================

-- Obtiene el account_id del usuario actual
CREATE OR REPLACE FUNCTION auth.user_account_id()
RETURNS UUID AS $$
  SELECT account_id FROM profiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Verifica si el usuario es superadmin
CREATE OR REPLACE FUNCTION auth.is_superadmin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() AND role = 'superadmin'
  )
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ============================================
-- NOTA IMPORTANTE
-- ============================================
-- Estas funciones usan SECURITY DEFINER para bypassear RLS
-- Son necesarias para que las políticas RLS de TODAS las tablas funcionen:
-- - accounts
-- - carriers
-- - products  
-- - regions
-- - cities
-- - nodes
-- - panelists
-- - allocation_plans
-- - material_catalog
-- - etc.
