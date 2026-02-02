# Arquitectura E2E DB - Base de Datos de Agregación Semanal

## Concepto General

**E2E DB** (End-to-End Database) es una base de datos separada que contiene datos **pre-agregados semanalmente** para reportes rápidos y escalables.

### Arquitectura de Dos Bases de Datos

```
┌─────────────────────────────────────────────────────────────┐
│                        ONEMS SYSTEM                          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────┐        ┌──────────────────────┐  │
│  │     ONE DB           │        │      E2E DB          │  │
│  │  (Datos Detallados)  │        │  (Datos Agregados)   │  │
│  ├──────────────────────┤        ├──────────────────────┤  │
│  │                      │        │                      │  │
│  │ • shipments          │───ETL──│ • weekly_routes      │  │
│  │ • material_shipments │  │     │ • weekly_carriers    │  │
│  │ • tracking_events    │  │     │ • weekly_products    │  │
│  │ • raw_data           │  │     │ • weekly_cities      │  │
│  │                      │  │     │ • weekly_regions     │  │
│  │ NUNCA SE BORRA       │  │     │                      │  │
│  │ (Histórico completo) │  │     │ SOLO LECTURA         │  │
│  │                      │  │     │ (Reportes rápidos)   │  │
│  └──────────────────────┘  │     └──────────────────────┘  │
│                             │                                │
│                             │                                │
│                             ↓                                │
│                    ┌─────────────────┐                      │
│                    │  ETL SEMANAL    │                      │
│                    │  (Edge Function)│                      │
│                    │                 │                      │
│                    │ • Corre lunes   │                      │
│                    │ • Agrega semana │                      │
│                    │ • Calcula KPIs  │                      │
│                    └─────────────────┘                      │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Principios de Diseño

### 1. **ONE DB: Fuente de Verdad**
- Contiene TODOS los datos detallados (shipments individuales)
- NUNCA se borra
- Se usa para:
  - Auditorías detalladas
  - Drill-down de reportes
  - Análisis forense
  - Compliance detallado

### 2. **E2E DB: Performance**
- Contiene datos PRE-AGREGADOS por semana
- Se regenera semanalmente desde ONE DB
- Se usa para:
  - Reportes ejecutivos
  - Dashboards
  - Análisis de tendencias
  - Comparaciones históricas

### 3. **Separación de Responsabilidades**
- **ONE DB**: Escritura intensiva (inserts de shipments)
- **E2E DB**: Lectura intensiva (consultas de reportes)

---

## Estructura de E2E DB

### Tabla Principal: `weekly_routes`

```sql
CREATE TABLE e2e_db.weekly_routes (
  -- Primary Key
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Temporal
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  week_number INTEGER NOT NULL, -- ISO week number
  year INTEGER NOT NULL,
  
  -- Dimensiones (IDs mantienen referencia a ONE DB)
  account_id UUID NOT NULL,
  carrier_id UUID NOT NULL,
  carrier_name TEXT NOT NULL,
  product_id UUID NOT NULL,
  product_code TEXT NOT NULL,
  product_description TEXT NOT NULL,
  origin_city_id UUID NOT NULL,
  origin_city_name TEXT NOT NULL,
  origin_region_id UUID NOT NULL,
  origin_region_name TEXT NOT NULL,
  destination_city_id UUID NOT NULL,
  destination_city_name TEXT NOT NULL,
  destination_region_id UUID NOT NULL,
  destination_region_name TEXT NOT NULL,
  
  -- Métricas de Volumen
  total_shipments INTEGER NOT NULL DEFAULT 0,
  compliant_shipments INTEGER NOT NULL DEFAULT 0,
  warning_shipments INTEGER NOT NULL DEFAULT 0,
  critical_shipments INTEGER NOT NULL DEFAULT 0,
  
  -- Métricas de Compliance (%)
  compliance_percentage DECIMAL(5,2) NOT NULL,
  standard_percentage DECIMAL(5,2) NOT NULL,
  deviation_percentage DECIMAL(5,2) NOT NULL,
  
  -- Métricas de Tiempo (días)
  jk_standard_days DECIMAL(8,3) NOT NULL,
  jk_actual_days DECIMAL(8,3) NOT NULL,
  jk_deviation_days DECIMAL(8,3) NOT NULL,
  avg_business_days DECIMAL(8,3) NOT NULL,
  min_business_days DECIMAL(8,3) NOT NULL,
  max_business_days DECIMAL(8,3) NOT NULL,
  
  -- Distribución de Días (para percentiles)
  business_days_p10 DECIMAL(8,3),
  business_days_p25 DECIMAL(8,3),
  business_days_p50 DECIMAL(8,3), -- Mediana
  business_days_p75 DECIMAL(8,3),
  business_days_p85 DECIMAL(8,3),
  business_days_p90 DECIMAL(8,3),
  business_days_p95 DECIMAL(8,3),
  business_days_p99 DECIMAL(8,3),
  
  -- Thresholds (de delivery_standards)
  warning_threshold DECIMAL(5,2),
  critical_threshold DECIMAL(5,2),
  threshold_type TEXT, -- 'relative' | 'absolute'
  
  -- Status
  route_status TEXT NOT NULL, -- 'compliant' | 'warning' | 'critical'
  
  -- Metadata
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  etl_version TEXT DEFAULT '1.0',
  
  -- Constraints
  CONSTRAINT unique_weekly_route UNIQUE (
    account_id, 
    week_start_date, 
    carrier_id, 
    product_id, 
    origin_city_id, 
    destination_city_id
  ),
  CONSTRAINT valid_week_dates CHECK (week_end_date > week_start_date),
  CONSTRAINT valid_shipments CHECK (total_shipments >= 0),
  CONSTRAINT valid_compliance CHECK (
    compliant_shipments + warning_shipments + critical_shipments = total_shipments
  )
);
```

### Índices para Performance

```sql
-- Índice principal por cuenta y fecha
CREATE INDEX idx_weekly_routes_account_date 
  ON e2e_db.weekly_routes(account_id, week_start_date DESC);

-- Índice por ruta (origen-destino)
CREATE INDEX idx_weekly_routes_route 
  ON e2e_db.weekly_routes(origin_city_id, destination_city_id);

-- Índice por carrier
CREATE INDEX idx_weekly_routes_carrier 
  ON e2e_db.weekly_routes(carrier_id, week_start_date DESC);

-- Índice por producto
CREATE INDEX idx_weekly_routes_product 
  ON e2e_db.weekly_routes(product_id, week_start_date DESC);

-- Índice por región origen
CREATE INDEX idx_weekly_routes_origin_region 
  ON e2e_db.weekly_routes(origin_region_id, week_start_date DESC);

-- Índice por región destino
CREATE INDEX idx_weekly_routes_destination_region 
  ON e2e_db.weekly_routes(destination_region_id, week_start_date DESC);

-- Índice por status
CREATE INDEX idx_weekly_routes_status 
  ON e2e_db.weekly_routes(route_status, week_start_date DESC);

-- Índice compuesto para filtros comunes
CREATE INDEX idx_weekly_routes_common_filters 
  ON e2e_db.weekly_routes(
    account_id, 
    week_start_date DESC, 
    carrier_id, 
    origin_city_id, 
    destination_city_id
  );
```

---

## Tablas Agregadas Adicionales

### `weekly_carriers` - Agregación por Carrier

```sql
CREATE TABLE e2e_db.weekly_carriers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL,
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  carrier_id UUID NOT NULL,
  carrier_name TEXT NOT NULL,
  
  -- Métricas agregadas
  total_routes INTEGER NOT NULL,
  total_shipments INTEGER NOT NULL,
  compliant_shipments INTEGER NOT NULL,
  compliance_percentage DECIMAL(5,2) NOT NULL,
  jk_standard_days DECIMAL(8,3) NOT NULL,
  jk_actual_days DECIMAL(8,3) NOT NULL,
  jk_deviation_days DECIMAL(8,3) NOT NULL,
  
  -- Breakdown por status
  compliant_routes INTEGER NOT NULL,
  warning_routes INTEGER NOT NULL,
  critical_routes INTEGER NOT NULL,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT unique_weekly_carrier UNIQUE (account_id, week_start_date, carrier_id)
);

CREATE INDEX idx_weekly_carriers_account_date 
  ON e2e_db.weekly_carriers(account_id, week_start_date DESC);
```

### `weekly_products` - Agregación por Producto

```sql
CREATE TABLE e2e_db.weekly_products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL,
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  product_id UUID NOT NULL,
  product_code TEXT NOT NULL,
  product_description TEXT NOT NULL,
  
  -- Métricas agregadas
  total_routes INTEGER NOT NULL,
  total_shipments INTEGER NOT NULL,
  compliant_shipments INTEGER NOT NULL,
  compliance_percentage DECIMAL(5,2) NOT NULL,
  jk_standard_days DECIMAL(8,3) NOT NULL,
  jk_actual_days DECIMAL(8,3) NOT NULL,
  jk_deviation_days DECIMAL(8,3) NOT NULL,
  
  -- Breakdown por status
  compliant_routes INTEGER NOT NULL,
  warning_routes INTEGER NOT NULL,
  critical_routes INTEGER NOT NULL,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT unique_weekly_product UNIQUE (account_id, week_start_date, product_id)
);

CREATE INDEX idx_weekly_products_account_date 
  ON e2e_db.weekly_products(account_id, week_start_date DESC);
```

### `weekly_cities` - Agregación por Ciudad (Inbound/Outbound)

```sql
CREATE TABLE e2e_db.weekly_cities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL,
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  city_id UUID NOT NULL,
  city_name TEXT NOT NULL,
  region_id UUID NOT NULL,
  region_name TEXT NOT NULL,
  direction TEXT NOT NULL, -- 'inbound' | 'outbound'
  
  -- Métricas agregadas
  total_routes INTEGER NOT NULL,
  total_shipments INTEGER NOT NULL,
  compliant_shipments INTEGER NOT NULL,
  compliance_percentage DECIMAL(5,2) NOT NULL,
  jk_standard_days DECIMAL(8,3) NOT NULL,
  jk_actual_days DECIMAL(8,3) NOT NULL,
  jk_deviation_days DECIMAL(8,3) NOT NULL,
  
  -- Breakdown por status
  compliant_routes INTEGER NOT NULL,
  warning_routes INTEGER NOT NULL,
  critical_routes INTEGER NOT NULL,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT unique_weekly_city UNIQUE (account_id, week_start_date, city_id, direction)
);

CREATE INDEX idx_weekly_cities_account_date 
  ON e2e_db.weekly_cities(account_id, week_start_date DESC);

CREATE INDEX idx_weekly_cities_direction 
  ON e2e_db.weekly_cities(city_id, direction, week_start_date DESC);
```

### `weekly_regions` - Agregación por Región (Inbound/Outbound)

```sql
CREATE TABLE e2e_db.weekly_regions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL,
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  region_id UUID NOT NULL,
  region_name TEXT NOT NULL,
  direction TEXT NOT NULL, -- 'inbound' | 'outbound'
  
  -- Métricas agregadas
  total_cities INTEGER NOT NULL,
  total_routes INTEGER NOT NULL,
  total_shipments INTEGER NOT NULL,
  compliant_shipments INTEGER NOT NULL,
  compliance_percentage DECIMAL(5,2) NOT NULL,
  jk_standard_days DECIMAL(8,3) NOT NULL,
  jk_actual_days DECIMAL(8,3) NOT NULL,
  jk_deviation_days DECIMAL(8,3) NOT NULL,
  
  -- Breakdown por status
  compliant_routes INTEGER NOT NULL,
  warning_routes INTEGER NOT NULL,
  critical_routes INTEGER NOT NULL,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  CONSTRAINT unique_weekly_region UNIQUE (account_id, week_start_date, region_id, direction)
);

CREATE INDEX idx_weekly_regions_account_date 
  ON e2e_db.weekly_regions(account_id, week_start_date DESC);

CREATE INDEX idx_weekly_regions_direction 
  ON e2e_db.weekly_regions(region_id, direction, week_start_date DESC);
```

---

## Proceso ETL Semanal

### Flujo de Trabajo

```
1. Trigger: Cada lunes a las 2 AM
   ↓
2. Determinar semana a procesar (semana anterior completa)
   ↓
3. Extraer datos de ONE DB (shipments de esa semana)
   ↓
4. Transformar:
   - Agrupar por ruta (carrier-product-origin-destination)
   - Calcular métricas (compliance, J+K, percentiles)
   - Determinar status (compliant/warning/critical)
   ↓
5. Cargar en E2E DB:
   - weekly_routes (detalle por ruta)
   - weekly_carriers (agregado por carrier)
   - weekly_products (agregado por producto)
   - weekly_cities (agregado por ciudad + dirección)
   - weekly_regions (agregado por región + dirección)
   ↓
6. Validar:
   - Verificar totales coinciden
   - Verificar no hay gaps de semanas
   - Log de resultados
   ↓
7. Notificar:
   - Email a admin si hay errores
   - Dashboard de status ETL
```

### Ventanas de Tiempo

```
Semana ISO: Lunes a Domingo

Ejemplo:
- Hoy: Lunes 2 Feb 2026
- Semana a procesar: 26 Ene - 1 Feb 2026
- Datos en ONE DB: shipments con sent_at entre esas fechas
- Resultado: Registros en E2E DB con week_start_date = 2026-01-26
```

---

## Adaptación de Hooks de Reportes

### Estrategia Híbrida

```typescript
// Hook adaptado para usar E2E DB o ONE DB según el caso

export function useTerritoryEquityData(
  accountId: string | undefined,
  filters?: TerritoryEquityFilters
) {
  // Determinar si usar E2E DB o ONE DB
  const useE2EDB = shouldUseE2EDB(filters)
  
  if (useE2EDB) {
    // Consultar E2E DB (rápido)
    return useTerritoryEquityFromE2E(accountId, filters)
  } else {
    // Consultar ONE DB (actual, pero más lento)
    return useTerritoryEquityFromOneDB(accountId, filters)
  }
}

function shouldUseE2EDB(filters?: TerritoryEquityFilters): boolean {
  if (!filters?.endDate) return false
  
  const endDate = new Date(filters.endDate)
  const today = new Date()
  const weekAgo = new Date(today)
  weekAgo.setDate(weekAgo.getDate() - 7)
  
  // Si el filtro termina hace más de 1 semana, usar E2E DB
  return endDate < weekAgo
}
```

### Consulta a E2E DB (Ejemplo)

```typescript
async function useTerritoryEquityFromE2E(
  accountId: string,
  filters: TerritoryEquityFilters
) {
  // Consultar weekly_routes (ya agregado)
  const { data: weeklyRoutes } = await supabase
    .from('weekly_routes')
    .select('*')
    .eq('account_id', accountId)
    .gte('week_start_date', filters.startDate)
    .lte('week_end_date', filters.endDate)
  
  // Agrupar por ciudad (inbound/outbound)
  const cityData = groupRoutesByCity(weeklyRoutes, filters)
  
  // Consultar weekly_regions
  const { data: weeklyRegions } = await supabase
    .from('weekly_regions')
    .select('*')
    .eq('account_id', accountId)
    .gte('week_start_date', filters.startDate)
    .lte('week_end_date', filters.endDate)
  
  return {
    cityData,
    regionData: weeklyRegions,
    metrics: calculateMetrics(cityData),
    loading: false,
    error: null,
  }
}
```

---

## Beneficios de Esta Arquitectura

### 1. **Escalabilidad Ilimitada**
- E2E DB crece linealmente (52 semanas/año)
- ONE DB crece con cada shipment, pero no afecta reportes

### 2. **Performance Predecible**
- Reportes siempre rápidos (<1 segundo)
- No importa cuántos años de histórico

### 3. **Auditoría Completa**
- ONE DB mantiene todos los detalles
- Drill-down siempre disponible

### 4. **Costo Optimizado**
- Menos queries a base de datos
- Queries más simples
- Menor uso de CPU/memoria

### 5. **Análisis Histórico**
- Comparaciones año a año triviales
- Tendencias a largo plazo fáciles
- Data warehouse ready

---

## Implementación Recomendada

### Fase 1: Crear E2E DB (1 día)
1. Crear esquema `e2e_db` en Supabase
2. Crear tablas con índices
3. Configurar RLS policies

### Fase 2: Implementar ETL (2 días)
1. Crear Edge Function de agregación
2. Configurar pg_cron para ejecución semanal
3. Implementar validaciones y logging

### Fase 3: Backfill Histórico (1 día)
1. Procesar semanas históricas desde ONE DB
2. Validar consistencia de datos

### Fase 4: Adaptar Hooks (2 días)
1. Implementar lógica híbrida (E2E vs ONE DB)
2. Modificar hooks de reportes
3. Mantener fallback a ONE DB

### Fase 5: Testing y Deploy (1 día)
1. Comparar resultados E2E vs ONE DB
2. Verificar performance
3. Deploy a producción

**Tiempo total: 7 días**

---

## Próximos Pasos

1. ¿Aprobar esta arquitectura?
2. ¿Crear las tablas en Supabase?
3. ¿Implementar Edge Function de ETL?
4. ¿Adaptar hooks de reportes?
