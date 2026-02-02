-- ============================================================================
-- FIX: Error "Could not find the table 'public.material_shipments'"
-- ============================================================================
-- Este error ocurre cuando hay referencias a una tabla que no existe
-- Posibles causas:
-- 1. RLS Policy que referencia la tabla
-- 2. Trigger que referencia la tabla
-- 3. Vista que referencia la tabla
-- 4. Foreign key constraint

-- ============================================================================
-- PASO 1: Verificar si la tabla existe
-- ============================================================================
SELECT 
  schemaname, 
  tablename 
FROM pg_tables 
WHERE tablename = 'material_shipments';

-- Si no existe, necesitamos crearla O eliminar las referencias

-- ============================================================================
-- PASO 2: Buscar RLS policies que referencian material_shipments
-- ============================================================================
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE qual::text LIKE '%material_shipments%'
   OR with_check::text LIKE '%material_shipments%';

-- ============================================================================
-- PASO 3: Buscar triggers que referencian material_shipments
-- ============================================================================
SELECT 
  trigger_schema,
  trigger_name,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE action_statement LIKE '%material_shipments%';

-- ============================================================================
-- PASO 4: Buscar vistas que referencian material_shipments
-- ============================================================================
SELECT 
  table_schema,
  table_name,
  view_definition
FROM information_schema.views
WHERE view_definition LIKE '%material_shipments%';

-- ============================================================================
-- PASO 5: Buscar foreign keys que referencian material_shipments
-- ============================================================================
SELECT
  tc.table_schema, 
  tc.constraint_name, 
  tc.table_name, 
  kcu.column_name,
  ccu.table_schema AS foreign_table_schema,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name 
FROM information_schema.table_constraints AS tc 
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY' 
  AND (ccu.table_name = 'material_shipments' OR tc.table_name = 'material_shipments');

-- ============================================================================
-- SOLUCIÓN TEMPORAL: Crear tabla material_shipments si no existe
-- ============================================================================
-- Esta es una solución temporal para evitar el error
-- Deberás decidir si realmente necesitas esta tabla o si debes eliminar las referencias

CREATE TABLE IF NOT EXISTS public.material_shipments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  
  -- Shipment info
  shipment_date DATE NOT NULL,
  origin_city_id UUID REFERENCES cities(id),
  destination_city_id UUID REFERENCES cities(id),
  
  -- Material info
  material_id UUID REFERENCES material_catalog(id),
  quantity INTEGER NOT NULL DEFAULT 0,
  
  -- Tracking
  status TEXT DEFAULT 'pending',
  
  -- Timestamps
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_material_shipments_account ON public.material_shipments(account_id);
CREATE INDEX IF NOT EXISTS idx_material_shipments_date ON public.material_shipments(shipment_date);
CREATE INDEX IF NOT EXISTS idx_material_shipments_origin ON public.material_shipments(origin_city_id);
CREATE INDEX IF NOT EXISTS idx_material_shipments_destination ON public.material_shipments(destination_city_id);

-- RLS
ALTER TABLE public.material_shipments ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see their own account's data
CREATE POLICY "Users can view own account material shipments"
  ON public.material_shipments
  FOR SELECT
  USING (
    account_id IN (
      SELECT account_id 
      FROM user_accounts 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert own account material shipments"
  ON public.material_shipments
  FOR INSERT
  WITH CHECK (
    account_id IN (
      SELECT account_id 
      FROM user_accounts 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update own account material shipments"
  ON public.material_shipments
  FOR UPDATE
  USING (
    account_id IN (
      SELECT account_id 
      FROM user_accounts 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can delete own account material shipments"
  ON public.material_shipments
  FOR DELETE
  USING (
    account_id IN (
      SELECT account_id 
      FROM user_accounts 
      WHERE user_id = auth.uid()
    )
  );

-- ============================================================================
-- ALTERNATIVA: Si NO necesitas la tabla, elimina las referencias
-- ============================================================================
-- Ejecuta los queries de los PASOS 2-5 para encontrar las referencias
-- Luego elimina cada una manualmente

-- Ejemplo para eliminar un RLS policy:
-- DROP POLICY IF EXISTS "policy_name" ON table_name;

-- Ejemplo para eliminar un trigger:
-- DROP TRIGGER IF EXISTS trigger_name ON table_name;

-- Ejemplo para eliminar una vista:
-- DROP VIEW IF EXISTS view_name;

-- Ejemplo para eliminar un foreign key:
-- ALTER TABLE table_name DROP CONSTRAINT constraint_name;
