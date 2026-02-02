-- ============================================================================
-- SCRIPT: Verificar esquema de tablas en Supabase
-- ============================================================================
-- Ejecuta estos queries en Supabase SQL Editor para obtener los nombres
-- exactos de columnas antes de crear E2E DB

-- ============================================================================
-- 1. Verificar estructura de tabla 'shipments' o 'one_db'
-- ============================================================================

-- Opción A: Si la tabla se llama 'shipments'
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'shipments'
ORDER BY ordinal_position;

-- Opción B: Si la tabla se llama 'one_db'
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'one_db'
ORDER BY ordinal_position;

-- ============================================================================
-- 2. Verificar estructura de tabla 'cities'
-- ============================================================================
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'cities'
ORDER BY ordinal_position;

-- ============================================================================
-- 3. Verificar estructura de tabla 'regions'
-- ============================================================================
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'regions'
ORDER BY ordinal_position;

-- ============================================================================
-- 4. Verificar estructura de tabla 'carriers'
-- ============================================================================
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'carriers'
ORDER BY ordinal_position;

-- ============================================================================
-- 5. Verificar estructura de tabla 'products'
-- ============================================================================
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'products'
ORDER BY ordinal_position;

-- ============================================================================
-- 6. Verificar estructura de tabla 'delivery_standards'
-- ============================================================================
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'delivery_standards'
ORDER BY ordinal_position;

-- ============================================================================
-- 7. Listar TODAS las tablas en el esquema public
-- ============================================================================
SELECT 
  table_name,
  table_type
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- ============================================================================
-- 8. Ver un ejemplo de datos de shipments/one_db
-- ============================================================================

-- Opción A: shipments
SELECT * FROM public.shipments LIMIT 1;

-- Opción B: one_db
SELECT * FROM public.one_db LIMIT 1;

-- ============================================================================
-- INSTRUCCIONES:
-- ============================================================================
-- 1. Ejecuta cada query en Supabase SQL Editor
-- 2. Copia los resultados (especialmente nombres de columnas)
-- 3. Comparte los resultados para que pueda crear los scripts correctos
-- ============================================================================
