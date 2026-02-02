-- ============================================================================
-- E2E DB - Base de Datos de Agregación Semanal
-- ============================================================================
-- Este script crea las tablas de E2E DB para reportes rápidos y escalables
-- 
-- IMPORTANTE: Este script usa los nombres de columnas REALES de las tablas
-- existentes (origin_city_name, destination_city_name, etc.)
--
-- Tablas fuente:
-- - one_db: Datos detallados de shipments
-- - cities: Catálogo de ciudades
-- - regions: Catálogo de regiones
-- - carriers: Catálogo de carriers
-- - products: Catálogo de productos
-- - delivery_standards: Estándares de entrega
-- ============================================================================

-- ============================================================================
-- TABLA PRINCIPAL: weekly_routes
-- ============================================================================
-- Agregación semanal por ruta (carrier-product-origen-destino)
-- Esta es la tabla core de E2E DB

CREATE TABLE IF NOT EXISTS public.weekly_routes (
  -- Primary Key
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Temporal
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  week_number INTEGER NOT NULL, -- ISO week number (1-53)
  year INTEGER NOT NULL,
  
  -- Account (RLS)
  account_id UUID NOT NULL,
  
  -- Dimensiones: Carrier
  carrier_name TEXT NOT NULL,
  
  -- Dimensiones: Product
  product_name TEXT NOT NULL,
  
  -- Dimensiones: Origin City (nombres, no IDs)
  origin_city_name TEXT NOT NULL,
  origin_region_name TEXT,
  
  -- Dimensiones: Destination City (nombres, no IDs)
  destination_city_name TEXT NOT NULL,
  destination_region_name TEXT,
  
  -- Métricas de Volumen
  total_shipments INTEGER NOT NULL DEFAULT 0,
  compliant_shipments INTEGER NOT NULL DEFAULT 0,
  warning_shipments INTEGER NOT NULL DEFAULT 0,
  critical_shipments INTEGER NOT NULL DEFAULT 0,
  
  -- Métricas de Compliance (%)
  compliance_percentage DECIMAL(5,2) NOT NULL DEFAULT 0,
  standard_percentage DECIMAL(5,2) DEFAULT 0,
  deviation_percentage DECIMAL(5,2) DEFAULT 0,
  
  -- Métricas de Tiempo (días)
  avg_business_days DECIMAL(8,3) DEFAULT 0,
  min_business_days DECIMAL(8,3) DEFAULT 0,
  max_business_days DECIMAL(8,3) DEFAULT 0,
  
  -- Distribución de Días (percentiles)
  business_days_p50 DECIMAL(8,3), -- Mediana
  business_days_p75 DECIMAL(8,3),
  business_days_p85 DECIMAL(8,3),
  business_days_p90 DECIMAL(8,3),
  business_days_p95 DECIMAL(8,3),
  
  -- J+K Metrics (si aplica)
  jk_standard_days DECIMAL(8,3),
  jk_actual_days DECIMAL(8,3),
  jk_deviation_days DECIMAL(8,3),
  
  -- Thresholds (de delivery_standards)
  warning_threshold DECIMAL(5,2),
  critical_threshold DECIMAL(5,2),
  
  -- Status
  route_status TEXT NOT NULL DEFAULT 'compliant', -- 'compliant' | 'warning' | 'critical'
  
  -- Metadata
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  etl_version TEXT DEFAULT '1.0',
  
  -- Constraints
  CONSTRAINT valid_week_dates CHECK (week_end_date > week_start_date),
  CONSTRAINT valid_shipments CHECK (total_shipments >= 0),
  CONSTRAINT valid_compliance_sum CHECK (
    compliant_shipments + warning_shipments + critical_shipments = total_shipments
  ),
  CONSTRAINT valid_route_status CHECK (route_status IN ('compliant', 'warning', 'critical'))
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_weekly_routes_account_date 
  ON public.weekly_routes(account_id, week_start_date DESC);

CREATE INDEX IF NOT EXISTS idx_weekly_routes_carrier 
  ON public.weekly_routes(carrier_name, week_start_date DESC);

CREATE INDEX IF NOT EXISTS idx_weekly_routes_product 
  ON public.weekly_routes(product_name, week_start_date DESC);

CREATE INDEX IF NOT EXISTS idx_weekly_routes_origin 
  ON public.weekly_routes(origin_city_name, week_start_date DESC);

CREATE INDEX IF NOT EXISTS idx_weekly_routes_destination 
  ON public.weekly_routes(destination_city_name, week_start_date DESC);

CREATE INDEX IF NOT EXISTS idx_weekly_routes_status 
  ON public.weekly_routes(route_status, week_start_date DESC);

-- Índice compuesto para filtros comunes
CREATE INDEX IF NOT EXISTS idx_weekly_routes_common_filters 
  ON public.weekly_routes(
    account_id, 
    week_start_date DESC, 
    carrier_name, 
    origin_city_name, 
    destination_city_name
  );

-- RLS Policies
ALTER TABLE public.weekly_routes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own account weekly routes"
  ON public.weekly_routes
  FOR SELECT
  USING (
    account_id IN (
      SELECT account_id 
      FROM user_accounts 
      WHERE user_id = auth.uid()
    )
  );

-- ============================================================================
-- TABLA: weekly_carriers
-- ============================================================================
-- Agregación semanal por carrier

CREATE TABLE IF NOT EXISTS public.weekly_carriers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL,
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  carrier_name TEXT NOT NULL,
  
  -- Métricas agregadas
  total_routes INTEGER NOT NULL DEFAULT 0,
  total_shipments INTEGER NOT NULL DEFAULT 0,
  compliant_shipments INTEGER NOT NULL DEFAULT 0,
  compliance_percentage DECIMAL(5,2) NOT NULL DEFAULT 0,
  avg_business_days DECIMAL(8,3) DEFAULT 0,
  
  -- Breakdown por status
  compliant_routes INTEGER NOT NULL DEFAULT 0,
  warning_routes INTEGER NOT NULL DEFAULT 0,
  critical_routes INTEGER NOT NULL DEFAULT 0,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT unique_weekly_carrier UNIQUE (account_id, week_start_date, carrier_name)
);

CREATE INDEX IF NOT EXISTS idx_weekly_carriers_account_date 
  ON public.weekly_carriers(account_id, week_start_date DESC);

ALTER TABLE public.weekly_carriers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own account weekly carriers"
  ON public.weekly_carriers
  FOR SELECT
  USING (
    account_id IN (
      SELECT account_id 
      FROM user_accounts 
      WHERE user_id = auth.uid()
    )
  );

-- ============================================================================
-- TABLA: weekly_products
-- ============================================================================
-- Agregación semanal por producto

CREATE TABLE IF NOT EXISTS public.weekly_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL,
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  product_name TEXT NOT NULL,
  
  -- Métricas agregadas
  total_routes INTEGER NOT NULL DEFAULT 0,
  total_shipments INTEGER NOT NULL DEFAULT 0,
  compliant_shipments INTEGER NOT NULL DEFAULT 0,
  compliance_percentage DECIMAL(5,2) NOT NULL DEFAULT 0,
  avg_business_days DECIMAL(8,3) DEFAULT 0,
  
  -- Breakdown por status
  compliant_routes INTEGER NOT NULL DEFAULT 0,
  warning_routes INTEGER NOT NULL DEFAULT 0,
  critical_routes INTEGER NOT NULL DEFAULT 0,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT unique_weekly_product UNIQUE (account_id, week_start_date, product_name)
);

CREATE INDEX IF NOT EXISTS idx_weekly_products_account_date 
  ON public.weekly_products(account_id, week_start_date DESC);

ALTER TABLE public.weekly_products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own account weekly products"
  ON public.weekly_products
  FOR SELECT
  USING (
    account_id IN (
      SELECT account_id 
      FROM user_accounts 
      WHERE user_id = auth.uid()
    )
  );

-- ============================================================================
-- TABLA: weekly_cities
-- ============================================================================
-- Agregación semanal por ciudad y dirección (inbound/outbound)

CREATE TABLE IF NOT EXISTS public.weekly_cities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL,
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  city_name TEXT NOT NULL,
  region_name TEXT,
  direction TEXT NOT NULL, -- 'inbound' | 'outbound'
  
  -- Métricas agregadas
  total_routes INTEGER NOT NULL DEFAULT 0,
  total_shipments INTEGER NOT NULL DEFAULT 0,
  compliant_shipments INTEGER NOT NULL DEFAULT 0,
  compliance_percentage DECIMAL(5,2) NOT NULL DEFAULT 0,
  avg_business_days DECIMAL(8,3) DEFAULT 0,
  
  -- Breakdown por status
  compliant_routes INTEGER NOT NULL DEFAULT 0,
  warning_routes INTEGER NOT NULL DEFAULT 0,
  critical_routes INTEGER NOT NULL DEFAULT 0,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT unique_weekly_city UNIQUE (account_id, week_start_date, city_name, direction),
  CONSTRAINT valid_direction CHECK (direction IN ('inbound', 'outbound'))
);

CREATE INDEX IF NOT EXISTS idx_weekly_cities_account_date 
  ON public.weekly_cities(account_id, week_start_date DESC);

CREATE INDEX IF NOT EXISTS idx_weekly_cities_direction 
  ON public.weekly_cities(city_name, direction, week_start_date DESC);

ALTER TABLE public.weekly_cities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own account weekly cities"
  ON public.weekly_cities
  FOR SELECT
  USING (
    account_id IN (
      SELECT account_id 
      FROM user_accounts 
      WHERE user_id = auth.uid()
    )
  );

-- ============================================================================
-- TABLA: weekly_regions
-- ============================================================================
-- Agregación semanal por región y dirección (inbound/outbound)

CREATE TABLE IF NOT EXISTS public.weekly_regions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL,
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  region_name TEXT NOT NULL,
  direction TEXT NOT NULL, -- 'inbound' | 'outbound'
  
  -- Métricas agregadas
  total_cities INTEGER NOT NULL DEFAULT 0,
  total_routes INTEGER NOT NULL DEFAULT 0,
  total_shipments INTEGER NOT NULL DEFAULT 0,
  compliant_shipments INTEGER NOT NULL DEFAULT 0,
  compliance_percentage DECIMAL(5,2) NOT NULL DEFAULT 0,
  avg_business_days DECIMAL(8,3) DEFAULT 0,
  
  -- Breakdown por status
  compliant_routes INTEGER NOT NULL DEFAULT 0,
  warning_routes INTEGER NOT NULL DEFAULT 0,
  critical_routes INTEGER NOT NULL DEFAULT 0,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT unique_weekly_region UNIQUE (account_id, week_start_date, region_name, direction),
  CONSTRAINT valid_region_direction CHECK (direction IN ('inbound', 'outbound'))
);

CREATE INDEX IF NOT EXISTS idx_weekly_regions_account_date 
  ON public.weekly_regions(account_id, week_start_date DESC);

CREATE INDEX IF NOT EXISTS idx_weekly_regions_direction 
  ON public.weekly_regions(region_name, direction, week_start_date DESC);

ALTER TABLE public.weekly_regions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own account weekly regions"
  ON public.weekly_regions
  FOR SELECT
  USING (
    account_id IN (
      SELECT account_id 
      FROM user_accounts 
      WHERE user_id = auth.uid()
    )
  );

-- ============================================================================
-- TABLA: etl_log
-- ============================================================================
-- Log de ejecuciones del proceso ETL

CREATE TABLE IF NOT EXISTS public.etl_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  execution_start TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  execution_end TIMESTAMP WITH TIME ZONE,
  status TEXT NOT NULL DEFAULT 'running', -- 'running' | 'success' | 'error'
  records_processed INTEGER DEFAULT 0,
  routes_created INTEGER DEFAULT 0,
  error_message TEXT,
  etl_version TEXT DEFAULT '1.0',
  
  CONSTRAINT valid_etl_status CHECK (status IN ('running', 'success', 'error'))
);

CREATE INDEX IF NOT EXISTS idx_etl_log_date 
  ON public.etl_log(week_start_date DESC);

CREATE INDEX IF NOT EXISTS idx_etl_log_status 
  ON public.etl_log(status, execution_start DESC);

-- ============================================================================
-- FUNCIONES AUXILIARES
-- ============================================================================

-- Función para calcular percentil
CREATE OR REPLACE FUNCTION percentile_cont(percentile DOUBLE PRECISION, values DECIMAL[])
RETURNS DECIMAL AS $$
DECLARE
  sorted_values DECIMAL[];
  index_pos DOUBLE PRECISION;
  lower_index INTEGER;
  upper_index INTEGER;
BEGIN
  -- Ordenar valores
  sorted_values := ARRAY(SELECT unnest(values) ORDER BY 1);
  
  -- Calcular posición del percentil
  index_pos := percentile * (array_length(sorted_values, 1) - 1) + 1;
  lower_index := FLOOR(index_pos)::INTEGER;
  upper_index := CEIL(index_pos)::INTEGER;
  
  -- Interpolación lineal
  IF lower_index = upper_index THEN
    RETURN sorted_values[lower_index];
  ELSE
    RETURN sorted_values[lower_index] + 
           (sorted_values[upper_index] - sorted_values[lower_index]) * 
           (index_pos - lower_index);
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- GRANTS (si es necesario)
-- ============================================================================

-- Dar permisos a usuarios autenticados
GRANT SELECT ON public.weekly_routes TO authenticated;
GRANT SELECT ON public.weekly_carriers TO authenticated;
GRANT SELECT ON public.weekly_products TO authenticated;
GRANT SELECT ON public.weekly_cities TO authenticated;
GRANT SELECT ON public.weekly_regions TO authenticated;
GRANT SELECT ON public.etl_log TO authenticated;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

-- Verificar que las tablas se crearon correctamente
SELECT 
  table_name,
  (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = t.table_name) as column_count
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_name LIKE 'weekly_%'
ORDER BY table_name;

-- ============================================================================
-- NOTAS IMPORTANTES
-- ============================================================================
-- 
-- 1. Este script usa gen_random_uuid() en lugar de uuid_generate_v4()
--    (compatible con Supabase por defecto)
--
-- 2. Los nombres de columnas coinciden con los usados en el código:
--    - origin_city_name (no origin_city_id)
--    - destination_city_name (no destination_city_id)
--    - carrier_name (no carrier_id)
--    - product_name (no product_id)
--
-- 3. Las tablas NO tienen foreign keys a ONE DB para mantener independencia
--
-- 4. RLS está habilitado y configurado para multi-tenant por account_id
--
-- 5. Próximo paso: Crear Edge Function para ETL semanal
--
-- ============================================================================
