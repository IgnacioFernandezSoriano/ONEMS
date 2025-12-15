# Migraciones SQL - Módulo de Reporting E2E

## Migración 020: Agregar clasificación de ciudades y regiones

```sql
-- Migration 020: Add city classification and regions for reporting
-- Date: 2025-12-11
-- Purpose: Enable route classification and regional analysis in reporting module

-- Add city_type column for classification (Capital, Major, Minor)
ALTER TABLE cities 
ADD COLUMN city_type TEXT CHECK (city_type IN ('capital', 'major', 'minor'));

-- Add region_name for geographical grouping
ALTER TABLE cities 
ADD COLUMN region_name TEXT;

-- Create index for faster filtering
CREATE INDEX IF NOT EXISTS idx_cities_type ON cities(city_type) WHERE city_type IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cities_region ON cities(region_name) WHERE region_name IS NOT NULL;

-- Add comments
COMMENT ON COLUMN cities.city_type IS 'Classification of city for regulatory reporting: capital (national capital), major (regional capitals/large cities), minor (small cities/towns)';
COMMENT ON COLUMN cities.region_name IS 'Region or department name for geographical grouping in reports';
```

---

## Migración 021: Función para clasificar rutas

```sql
-- Migration 021: Create route classification function
-- Date: 2025-12-11
-- Purpose: Classify routes based on origin and destination city types

CREATE OR REPLACE FUNCTION classify_route(
  p_origin_city_id UUID,
  p_destination_city_id UUID
) RETURNS TEXT AS $$
DECLARE
  v_origin_type TEXT;
  v_destination_type TEXT;
BEGIN
  -- Get origin city type
  SELECT city_type INTO v_origin_type
  FROM cities
  WHERE id = p_origin_city_id;
  
  -- Get destination city type
  SELECT city_type INTO v_destination_type
  FROM cities
  WHERE id = p_destination_city_id;
  
  -- Handle NULL cases
  IF v_origin_type IS NULL OR v_destination_type IS NULL THEN
    RETURN 'unclassified';
  END IF;
  
  -- Return classification
  RETURN v_origin_type || '-' || v_destination_type;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION classify_route IS 'Classifies a route based on origin and destination city types. Returns format: "capital-major", "major-minor", etc.';
```

---

## Migración 022: Vista de desempeño general

```sql
-- Migration 022: Create general performance reporting view
-- Date: 2025-12-11
-- Purpose: Aggregated metrics for dashboard general view

CREATE OR REPLACE VIEW v_reporting_general_performance AS
SELECT 
  account_id,
  date_trunc('week', sent_at) as period_week,
  date_trunc('month', sent_at) as period_month,
  carrier_name,
  product_name,
  
  -- Volume metrics
  COUNT(*) as total_shipments,
  
  -- Compliance metrics
  SUM(CASE WHEN on_time_delivery THEN 1 ELSE 0 END) as compliant_shipments,
  ROUND(
    (SUM(CASE WHEN on_time_delivery THEN 1 ELSE 0 END)::numeric / COUNT(*)) * 100, 
    2
  ) as compliance_percentage,
  
  -- Transit time metrics
  ROUND(AVG(business_transit_days), 2) as avg_business_days,
  ROUND(AVG(total_transit_days), 2) as avg_total_days,
  MAX(total_transit_days) as max_transit_days,
  MIN(total_transit_days) as min_transit_days,
  
  -- Timestamps
  MIN(sent_at) as period_start,
  MAX(received_at) as period_end
  
FROM one_db
GROUP BY 
  account_id,
  date_trunc('week', sent_at),
  date_trunc('month', sent_at),
  carrier_name,
  product_name;

COMMENT ON VIEW v_reporting_general_performance IS 'Aggregated performance metrics by period, carrier, and product for dashboard general view';

-- Create indexes on base table for performance
CREATE INDEX IF NOT EXISTS idx_one_db_sent_at ON one_db(sent_at);
CREATE INDEX IF NOT EXISTS idx_one_db_account_carrier ON one_db(account_id, carrier_name);
```

---

## Migración 023: Vista de cumplimiento por clasificación

```sql
-- Migration 023: Create compliance by route classification view
-- Date: 2025-12-11
-- Purpose: Compliance metrics grouped by route classification

CREATE OR REPLACE VIEW v_reporting_compliance_by_classification AS
WITH route_data AS (
  SELECT 
    odb.account_id,
    odb.tag_id,
    odb.carrier_name,
    odb.product_name,
    odb.origin_city_name,
    odb.destination_city_name,
    odb.sent_at,
    odb.received_at,
    odb.total_transit_days,
    odb.business_transit_days,
    odb.on_time_delivery,
    
    -- Get city IDs from allocation_plan_details via source_data_snapshot
    (odb.source_data_snapshot->>'origin_node_id')::uuid as origin_node_id,
    (odb.source_data_snapshot->>'destination_node_id')::uuid as destination_node_id
  FROM one_db odb
),
route_classified AS (
  SELECT 
    rd.*,
    oc.city_type as origin_type,
    dc.city_type as destination_type,
    COALESCE(
      oc.city_type || '-' || dc.city_type,
      'unclassified'
    ) as route_classification
  FROM route_data rd
  LEFT JOIN nodes on_node ON rd.origin_node_id = on_node.id
  LEFT JOIN cities oc ON on_node.city_id = oc.id
  LEFT JOIN nodes dn_node ON rd.destination_node_id = dn_node.id
  LEFT JOIN cities dc ON dn_node.city_id = dc.id
)
SELECT 
  account_id,
  route_classification,
  
  -- Volume metrics
  COUNT(*) as total_shipments,
  
  -- Compliance metrics
  SUM(CASE WHEN on_time_delivery THEN 1 ELSE 0 END) as compliant_shipments,
  ROUND(
    (SUM(CASE WHEN on_time_delivery THEN 1 ELSE 0 END)::numeric / COUNT(*)) * 100, 
    2
  ) as compliance_percentage,
  
  -- Transit time metrics
  ROUND(AVG(business_transit_days), 2) as avg_business_days,
  MAX(total_transit_days) as max_transit_days,
  
  -- Most common routes in this classification
  MODE() WITHIN GROUP (ORDER BY origin_city_name || ' → ' || destination_city_name) as most_common_route
  
FROM route_classified
GROUP BY account_id, route_classification;

COMMENT ON VIEW v_reporting_compliance_by_classification IS 'Compliance metrics grouped by route classification (capital-capital, major-minor, etc.)';
```

---

## Migración 024: Vista de desglose por localidad

```sql
-- Migration 024: Create locality breakdown view
-- Date: 2025-12-11
-- Purpose: Detailed metrics by destination city for granular analysis

CREATE OR REPLACE VIEW v_reporting_by_locality AS
WITH locality_data AS (
  SELECT 
    odb.account_id,
    odb.destination_city_name,
    odb.carrier_name,
    odb.product_name,
    odb.total_transit_days,
    odb.business_transit_days,
    odb.on_time_delivery,
    odb.sent_at,
    
    -- Get destination city info
    (odb.source_data_snapshot->>'destination_node_id')::uuid as destination_node_id
  FROM one_db odb
)
SELECT 
  ld.account_id,
  ld.destination_city_name as locality_name,
  c.city_type as locality_classification,
  c.region_name,
  
  -- Volume metrics
  COUNT(*) as total_shipments,
  
  -- Compliance metrics
  SUM(CASE WHEN ld.on_time_delivery THEN 1 ELSE 0 END) as compliant_shipments,
  ROUND(
    (SUM(CASE WHEN ld.on_time_delivery THEN 1 ELSE 0 END)::numeric / COUNT(*)) * 100, 
    2
  ) as compliance_percentage,
  
  -- Transit time metrics
  ROUND(AVG(ld.business_transit_days), 2) as avg_business_days,
  MAX(ld.total_transit_days) as max_transit_days,
  
  -- Temporal metrics
  MIN(ld.sent_at) as first_shipment_date,
  MAX(ld.sent_at) as last_shipment_date,
  
  -- Top carrier to this locality
  MODE() WITHIN GROUP (ORDER BY ld.carrier_name) as primary_carrier
  
FROM locality_data ld
LEFT JOIN nodes n ON ld.destination_node_id = n.id
LEFT JOIN cities c ON n.city_id = c.id
GROUP BY 
  ld.account_id,
  ld.destination_city_name,
  c.city_type,
  c.region_name;

COMMENT ON VIEW v_reporting_by_locality IS 'Detailed performance metrics by destination locality for granular geographic analysis';

-- Create index for faster locality lookups
CREATE INDEX IF NOT EXISTS idx_one_db_destination_city ON one_db(destination_city_name);
```

---

## Migración 025: Vista de trazabilidad individual

```sql
-- Migration 025: Create individual shipment tracking view
-- Date: 2025-12-11
-- Purpose: Complete details of individual shipments for forensic analysis

CREATE OR REPLACE VIEW v_reporting_individual_tracking AS
SELECT 
  odb.id,
  odb.account_id,
  odb.tag_id,
  odb.plan_name,
  odb.carrier_name,
  odb.product_name,
  
  -- Route information
  odb.origin_city_name,
  odb.destination_city_name,
  
  -- Timestamps
  odb.sent_at,
  odb.received_at,
  
  -- Transit metrics
  odb.total_transit_days,
  odb.business_transit_days,
  odb.on_time_delivery,
  
  -- Standard time (from product)
  p.standard_delivery_hours,
  p.time_unit,
  
  -- Calculate expected delivery time
  CASE 
    WHEN p.time_unit = 'hours' THEN
      odb.sent_at + (p.standard_delivery_hours * INTERVAL '1 hour')
    WHEN p.time_unit = 'days' THEN
      odb.sent_at + (p.standard_delivery_hours * INTERVAL '1 day')
    ELSE
      odb.sent_at + (p.standard_delivery_hours * INTERVAL '1 hour')
  END as expected_delivery_at,
  
  -- Delay calculation
  EXTRACT(EPOCH FROM (odb.received_at - 
    CASE 
      WHEN p.time_unit = 'hours' THEN
        odb.sent_at + (p.standard_delivery_hours * INTERVAL '1 hour')
      WHEN p.time_unit = 'days' THEN
        odb.sent_at + (p.standard_delivery_hours * INTERVAL '1 day')
      ELSE
        odb.sent_at + (p.standard_delivery_hours * INTERVAL '1 hour')
    END
  )) / 3600 as delay_hours,
  
  -- Complete source data
  odb.source_data_snapshot,
  
  -- Audit info
  odb.created_at as transferred_at
  
FROM one_db odb
LEFT JOIN allocation_plan_details apd ON odb.allocation_detail_id = apd.id
LEFT JOIN allocation_plans ap ON apd.plan_id = ap.id
LEFT JOIN products p ON ap.product_id = p.id;

COMMENT ON VIEW v_reporting_individual_tracking IS 'Complete shipment details including timeline, delays, and source data for individual tracking';
```

---

## Migración 026: Tabla de configuración de reporting por cuenta

```sql
-- Migration 026: Create reporting configuration table
-- Date: 2025-12-11
-- Purpose: Store account-specific reporting configurations

CREATE TABLE IF NOT EXISTS reporting_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  
  -- Compliance thresholds
  compliance_threshold_warning INTEGER DEFAULT 85 CHECK (compliance_threshold_warning BETWEEN 0 AND 100),
  compliance_threshold_critical INTEGER DEFAULT 75 CHECK (compliance_threshold_critical BETWEEN 0 AND 100),
  
  -- Default report settings
  default_report_period TEXT DEFAULT 'month' CHECK (default_report_period IN ('week', 'month', 'quarter')),
  
  -- Regional grouping preference
  use_regional_grouping BOOLEAN DEFAULT true,
  
  -- Visualization preferences
  preferred_map_alternative TEXT DEFAULT 'treemap' CHECK (preferred_map_alternative IN ('treemap', 'heatmap')),
  
  -- Audit
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by UUID REFERENCES auth.users(id),
  
  -- Unique constraint
  CONSTRAINT reporting_config_unique_account UNIQUE(account_id)
);

-- Enable RLS
ALTER TABLE reporting_config ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY reporting_config_select_policy ON reporting_config
  FOR SELECT
  USING (
    account_id IN (
      SELECT account_id 
      FROM profiles 
      WHERE id = auth.uid()
    )
  );

CREATE POLICY reporting_config_update_policy ON reporting_config
  FOR UPDATE
  USING (
    account_id IN (
      SELECT account_id 
      FROM profiles 
      WHERE id = auth.uid() AND role = 'superadmin'
    )
  );

-- Create index
CREATE INDEX IF NOT EXISTS idx_reporting_config_account ON reporting_config(account_id);

-- Add comment
COMMENT ON TABLE reporting_config IS 'Account-specific configuration for reporting module (thresholds, preferences, etc.)';

-- Insert default config for existing accounts
INSERT INTO reporting_config (account_id)
SELECT id FROM accounts
ON CONFLICT (account_id) DO NOTHING;
```

---

## Migración 027: Función para calcular % de cumplimiento dinámico

```sql
-- Migration 027: Create dynamic compliance calculation function
-- Date: 2025-12-11
-- Purpose: Calculate compliance percentage with flexible filters

CREATE OR REPLACE FUNCTION calculate_compliance_percentage(
  p_account_id UUID,
  p_date_from TIMESTAMPTZ DEFAULT NULL,
  p_date_to TIMESTAMPTZ DEFAULT NULL,
  p_carrier_name TEXT DEFAULT NULL,
  p_product_name TEXT DEFAULT NULL,
  p_route_classification TEXT DEFAULT NULL
) RETURNS NUMERIC AS $$
DECLARE
  v_compliance_pct NUMERIC;
BEGIN
  SELECT 
    ROUND(
      (SUM(CASE WHEN on_time_delivery THEN 1 ELSE 0 END)::numeric / COUNT(*)) * 100, 
      2
    )
  INTO v_compliance_pct
  FROM one_db
  WHERE account_id = p_account_id
    AND (p_date_from IS NULL OR sent_at >= p_date_from)
    AND (p_date_to IS NULL OR sent_at <= p_date_to)
    AND (p_carrier_name IS NULL OR carrier_name = p_carrier_name)
    AND (p_product_name IS NULL OR product_name = p_product_name);
  
  RETURN COALESCE(v_compliance_pct, 0);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION calculate_compliance_percentage IS 'Calculates compliance percentage for a given account with optional filters (date range, carrier, product)';
```

---

## Script de Inicialización: Clasificar ciudades existentes

```sql
-- Initialization script: Classify existing cities for DEMO2 account
-- Run after migrations 020-027

-- Classify Madrid as capital
UPDATE cities 
SET 
  city_type = 'capital',
  region_name = 'Comunidad de Madrid'
WHERE name = 'Madrid' 
  AND account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';

-- Classify Barcelona as major
UPDATE cities 
SET 
  city_type = 'major',
  region_name = 'Cataluña'
WHERE name = 'Barcelona' 
  AND account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';

-- Verify classification
SELECT 
  name,
  city_type,
  region_name
FROM cities
WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
ORDER BY name;
```

---

## Orden de Ejecución

1. **Migración 020** - Agregar columnas a cities
2. **Migración 021** - Función classify_route
3. **Migración 022** - Vista v_reporting_general_performance
4. **Migración 023** - Vista v_reporting_compliance_by_classification
5. **Migración 024** - Vista v_reporting_by_locality
6. **Migración 025** - Vista v_reporting_individual_tracking
7. **Migración 026** - Tabla reporting_config
8. **Migración 027** - Función calculate_compliance_percentage
9. **Script de inicialización** - Clasificar ciudades existentes

---

## Testing de Vistas

```sql
-- Test Vista 1: General Performance
SELECT * FROM v_reporting_general_performance
WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
ORDER BY period_week DESC
LIMIT 10;

-- Test Vista 2: Compliance by Classification
SELECT * FROM v_reporting_compliance_by_classification
WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
ORDER BY compliance_percentage ASC;

-- Test Vista 3: By Locality
SELECT * FROM v_reporting_by_locality
WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
ORDER BY total_shipments DESC
LIMIT 20;

-- Test Vista 4: Individual Tracking
SELECT * FROM v_reporting_individual_tracking
WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
  AND tag_id = 'TAG-0001';

-- Test Función de Cumplimiento
SELECT calculate_compliance_percentage(
  'f4d823d2-93e6-4755-9a89-9da87e7fa86e'::uuid,
  '2025-12-01'::timestamptz,
  '2025-12-31'::timestamptz
) as compliance_december_2025;
```
