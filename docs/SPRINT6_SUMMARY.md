# Sprint 6: Diagnosis DB Schema Complete

**Fecha:** 10 de febrero de 2026  
**Duración:** 3-4 horas  
**Estado:** ✅ COMPLETADO

---

## 🎯 Objetivo

Implementar el esquema completo de la base de datos de diagnóstico (Diagnosis DB) que almacenará todos los datos procesados del módulo de cálculo, e implementar soft delete en tablas de configuración existentes para preservar datos históricos.

---

## 📊 Alcance Completado

### Parte 1: Soft Delete Implementation

Se implementó soft delete en las tablas de configuración existentes para evitar pérdida de datos históricos cuando se eliminan centros postales, lectores o SLAs.

**Tablas actualizadas:**
- `postal_centers` - Centros postales
- `readers` - Lectores RFID
- `slas` - Service Level Agreements

**Cambios realizados:**
1. **Migración SQL:**
   - Agregada columna `deleted_at TIMESTAMPTZ` a las 3 tablas
   - Creados índices parciales para optimizar filtrado (`WHERE deleted_at IS NULL`)
   - Actualizadas políticas RLS para filtrar registros eliminados automáticamente

2. **Tipos TypeScript:**
   - Agregado campo `deleted_at?: string | null` a interfaces:
     - `PostalCenter`
     - `Reader`
     - `SLA`

3. **Hooks actualizados:**
   - `usePostalCenters.ts`:
     - `fetchAll()`: Filtra por `deleted_at IS NULL`
     - `deletePostalCenter()`: Hace UPDATE con timestamp en lugar de DELETE
     - `deleteReader()`: Hace UPDATE con timestamp en lugar de DELETE
   
   - `useSLAs.ts`:
     - `fetchAll()`: Filtra postal centers por `deleted_at IS NULL`
     - `deleteSLA()`: Hace UPDATE con timestamp en lugar de DELETE
     - `deleteMultiple()`: Hace UPDATE con timestamp en lugar de DELETE

**Beneficios:**
- ✅ Preservación de datos históricos
- ✅ Auditoría completa
- ✅ Reportes históricos no se rompen
- ✅ Posibilidad de "restaurar" registros eliminados en el futuro

---

### Parte 2: Diagnosis DB Tables

Se crearon 4 tablas nuevas para almacenar datos procesados del módulo de diagnóstico.

---

#### Tabla 1: `processed_events`

**Propósito:** Almacenar eventos RFID consolidados después de procesamiento desde RFID Intermediate DB.

**Campos principales:**
- `id` - BIGSERIAL PRIMARY KEY
- `account_id` - UUID (multi-tenancy)
- `tag_id` - TEXT (identificador de la muestra)
- `reader_id` - UUID REFERENCES readers (ON DELETE RESTRICT)
- `postal_center_id` - UUID REFERENCES postal_centers (ON DELETE RESTRICT)
- `event_type` - TEXT CHECK ('entry', 'exit')
- `timestamp` - TIMESTAMPTZ (hora real del evento)
- `analysis_datetime` - TIMESTAMPTZ (hora ajustada considerando cut-off y festivos)
- `is_consolidated` - BOOLEAN (si ya fue procesado en journey_segments)
- `raw_event_count` - INTEGER (número de eventos raw consolidados)

**Campos snapshot (para reportes históricos):**
- `postal_center_code_snapshot` - TEXT
- `postal_center_name_snapshot` - TEXT
- `reader_id_snapshot` - TEXT
- `reader_type_snapshot` - TEXT ('Entry', 'Exit', 'Mixed')

**Índices:**
- `idx_processed_events_account` - (account_id)
- `idx_processed_events_tag_id` - (tag_id)
- `idx_processed_events_tag_timestamp` - (tag_id, timestamp)
- `idx_processed_events_postal_center` - (postal_center_id)
- `idx_processed_events_reader` - (reader_id)
- `idx_processed_events_timestamp` - (timestamp)
- `idx_processed_events_analysis_datetime` - (analysis_datetime)
- `idx_processed_events_unconsolidated` - (account_id, is_consolidated) WHERE is_consolidated = false

**Políticas RLS:** ✅ Implementadas (SELECT, INSERT, UPDATE, DELETE)

---

#### Tabla 2: `journey_segments`

**Propósito:** Almacenar segmentos calculados de tiempo (operational y distribution).

**Campos principales:**
- `id` - BIGSERIAL PRIMARY KEY
- `account_id` - UUID
- `tag_id` - TEXT
- `segment_type` - TEXT CHECK ('operational', 'distribution')
- `postal_center_id` - UUID (para operational)
- `from_postal_center_id` - UUID (para distribution)
- `to_postal_center_id` - UUID (para distribution)
- `entry_event_id` - BIGINT REFERENCES processed_events
- `exit_event_id` - BIGINT REFERENCES processed_events
- `entry_timestamp` - TIMESTAMPTZ
- `exit_timestamp` - TIMESTAMPTZ
- `entry_analysis_datetime` - TIMESTAMPTZ
- `exit_analysis_datetime` - TIMESTAMPTZ

**Tiempos calculados (en minutos):**
- `actual_time_minutes` - INTEGER (diferencia de tiempo raw)
- `adjusted_time_minutes` - INTEGER (tiempo excluyendo horas no laborables)
- `pre_operational_wait_minutes` - INTEGER (tiempo de espera antes de procesamiento)

**Comparación con SLA:**
- `sla_id` - UUID REFERENCES slas (ON DELETE SET NULL)
- `expected_time_minutes` - INTEGER (del SLA en momento del cálculo)
- `sla_compliance` - TEXT CHECK ('on_time', 'warning', 'critical', 'violated', 'no_sla')

**Campos snapshot:**
- `postal_center_code_snapshot`, `postal_center_name_snapshot`
- `from_postal_center_code_snapshot`, `from_postal_center_name_snapshot`
- `to_postal_center_code_snapshot`, `to_postal_center_name_snapshot`

**Constraints:**
- Validación de campos según `segment_type`
- Validación de timestamps (exit >= entry)
- Validación de tiempos (>= 0)

**Índices:**
- `idx_journey_segments_account` - (account_id)
- `idx_journey_segments_tag_id` - (tag_id)
- `idx_journey_segments_segment_type` - (account_id, segment_type)
- `idx_journey_segments_operational` - (account_id, postal_center_id) WHERE segment_type = 'operational'
- `idx_journey_segments_distribution` - (account_id, from_postal_center_id, to_postal_center_id) WHERE segment_type = 'distribution'
- `idx_journey_segments_sla` - (sla_id) WHERE sla_id IS NOT NULL
- `idx_journey_segments_compliance` - (account_id, sla_compliance)
- `idx_journey_segments_entry_timestamp` - (entry_timestamp)

**Políticas RLS:** ✅ Implementadas

---

#### Tabla 3: `incidents`

**Propósito:** Registrar anomalías detectadas automáticamente y problemas de calidad de datos.

**Campos principales:**
- `id` - BIGSERIAL PRIMARY KEY
- `account_id` - UUID
- `incident_type` - TEXT CHECK (8 tipos)
- `severity` - TEXT CHECK ('low', 'medium', 'high', 'critical')
- `tag_id` - TEXT
- `postal_center_id` - UUID (ON DELETE SET NULL)
- `reader_id` - UUID (ON DELETE SET NULL)
- `event_id` - BIGINT REFERENCES processed_events
- `segment_id` - BIGINT REFERENCES journey_segments
- `description` - TEXT
- `metadata` - JSONB (contexto adicional)

**Tipos de incidentes:**
1. `exit_before_entry` - Salida registrada antes de entrada
2. `missing_entry` - Falta evento de entrada
3. `missing_exit` - Falta evento de salida
4. `sla_violation` - Violación de SLA
5. `stuck_sample` - Muestra sin movimiento por tiempo prolongado
6. `missroute` - Ruta no esperada
7. `duplicate_event` - Evento duplicado
8. `invalid_sequence` - Secuencia inválida de eventos

**Resolución:**
- `is_resolved` - BOOLEAN
- `resolved_at` - TIMESTAMPTZ
- `resolved_by` - UUID REFERENCES auth.users
- `resolution_notes` - TEXT

**Índices:**
- `idx_incidents_account` - (account_id)
- `idx_incidents_tag_id` - (tag_id)
- `idx_incidents_type` - (account_id, incident_type)
- `idx_incidents_severity` - (account_id, severity)
- `idx_incidents_postal_center` - (postal_center_id)
- `idx_incidents_unresolved` - (account_id, is_resolved) WHERE is_resolved = false
- `idx_incidents_detected_at` - (detected_at)

**Políticas RLS:** ✅ Implementadas

---

#### Tabla 4: `journeys`

**Propósito:** Almacenar journeys completos reconstruidos para cada tag con métricas agregadas.

**Campos principales:**
- `id` - BIGSERIAL PRIMARY KEY
- `account_id` - UUID
- `tag_id` - TEXT (UNIQUE por account)
- `origin_city_id` - UUID REFERENCES cities (ON DELETE SET NULL)
- `destination_city_id` - UUID REFERENCES cities (ON DELETE SET NULL)
- `origin_city_name` - TEXT
- `destination_city_name` - TEXT

**Ruta del journey:**
- `route_path` - JSONB (array de objetos con center_id, code, name, entry_time, exit_time)
- `total_centers_visited` - INTEGER

**Tiempos calculados (en minutos):**
- `total_actual_time_minutes` - INTEGER
- `total_adjusted_time_minutes` - INTEGER
- `total_operational_time_minutes` - INTEGER (suma de segmentos operational)
- `total_distribution_time_minutes` - INTEGER (suma de segmentos distribution)
- `total_pre_operational_wait_minutes` - INTEGER

**Estado del journey:**
- `journey_status` - TEXT CHECK ('in_progress', 'completed', 'anomalous', 'stuck')
- `is_missroute` - BOOLEAN
- `missroute_reason` - TEXT

**Timestamps:**
- `first_event_timestamp` - TIMESTAMPTZ
- `last_event_timestamp` - TIMESTAMPTZ

**Resumen de SLA:**
- `total_sla_violations` - INTEGER
- `total_segments` - INTEGER
- `on_time_segments` - INTEGER

**Índices:**
- `idx_journeys_account` - (account_id)
- `idx_journeys_tag_id` - (tag_id)
- `idx_journeys_status` - (account_id, journey_status)
- `idx_journeys_origin_dest` - (account_id, origin_city_id, destination_city_id)
- `idx_journeys_missroute` - (account_id, is_missroute) WHERE is_missroute = true
- `idx_journeys_first_event` - (first_event_timestamp)
- `idx_journeys_last_event` - (last_event_timestamp)

**Políticas RLS:** ✅ Implementadas

---

## 📁 Archivos Creados/Modificados

### Nuevos Archivos

1. **`supabase/migrations/20260210000000_diagnosis_db_schema.sql`** (485 líneas)
   - Parte 1: Soft delete en tablas existentes
   - Parte 2: Creación de 4 tablas de Diagnosis DB
   - Índices optimizados
   - Políticas RLS completas

2. **`src/lib/types_diagnosis.ts`** (400+ líneas)
   - Tipos para `ProcessedEvent`, `JourneySegment`, `Incident`, `Journey`
   - Tipos con detalles (joins)
   - Form data types
   - Filter types
   - Utility types (TimeCalculation, SLAPerformance, JourneyStatistics)

### Archivos Modificados

3. **`src/lib/types_postal_centers.ts`**
   - Agregado `deleted_at?: string | null` a `PostalCenter` y `Reader`

4. **`src/lib/types_slas.ts`**
   - Agregado `deleted_at: string | null` a `SLA`

5. **`src/hooks/usePostalCenters.ts`**
   - `fetchAll()`: Filtra por `deleted_at IS NULL`
   - `deletePostalCenter()`: Soft delete
   - `deleteReader()`: Soft delete

6. **`src/hooks/useSLAs.ts`**
   - `fetchAll()`: Filtra postal centers por `deleted_at IS NULL`
   - `deleteSLA()`: Soft delete
   - `deleteMultiple()`: Soft delete

---

## 🔗 Relaciones entre Tablas

```
processed_events
  ├─> readers (reader_id)
  ├─> postal_centers (postal_center_id)
  └─> journey_segments (entry_event_id, exit_event_id)

journey_segments
  ├─> processed_events (entry_event_id, exit_event_id)
  ├─> postal_centers (postal_center_id, from_postal_center_id, to_postal_center_id)
  ├─> slas (sla_id)
  └─> incidents (segment_id)

incidents
  ├─> postal_centers (postal_center_id)
  ├─> readers (reader_id)
  ├─> processed_events (event_id)
  ├─> journey_segments (segment_id)
  └─> auth.users (resolved_by)

journeys
  ├─> cities (origin_city_id, destination_city_id)
  └─> [journey_segments via tag_id]
```

---

## 🔐 Seguridad (RLS)

Todas las tablas tienen Row Level Security (RLS) habilitado con políticas que:

1. **SELECT:** Permite acceso a registros de la propia cuenta o si es superadmin
2. **INSERT:** Solo permite insertar con el account_id del usuario actual
3. **UPDATE:** Solo permite actualizar registros de la propia cuenta
4. **DELETE:** Solo permite eliminar registros de la propia cuenta

**Función utilizada:** `public.current_user_account_id()`

---

## 🚀 Deployment Instructions

### 1. Aplicar Migración SQL

```bash
# Opción A: Desde Supabase SQL Editor
# Copiar contenido de: supabase/migrations/20260210000000_diagnosis_db_schema.sql
# Pegar en SQL Editor y ejecutar

# Opción B: Desde CLI (si está configurado)
supabase db push
```

### 2. Verificar Tablas Creadas

```sql
-- Verificar que las tablas existen
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN ('processed_events', 'journey_segments', 'incidents', 'journeys');

-- Verificar que soft delete está implementado
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name IN ('postal_centers', 'readers', 'slas') 
  AND column_name = 'deleted_at';
```

### 3. Testing Soft Delete

```sql
-- Test 1: Soft delete de postal center
UPDATE postal_centers 
SET deleted_at = NOW() 
WHERE code = 'TEST_CENTER';

-- Test 2: Verificar que no aparece en queries normales
SELECT * FROM postal_centers WHERE deleted_at IS NULL;

-- Test 3: Restaurar (opcional)
UPDATE postal_centers 
SET deleted_at = NULL 
WHERE code = 'TEST_CENTER';
```

---

## 📋 Próximos Pasos

### Sprint 7: Event Consolidation Module (4-5 horas)

**Objetivo:** Implementar módulo de consolidación de eventos RFID raw.

**Tareas:**
1. Crear función de consolidación de eventos duplicados
2. Implementar lógica de Mixed readers (separación entry/exit)
3. Calcular `analysis_datetime` considerando cut-off y festivos
4. Poblar tabla `processed_events`
5. Crear job/trigger para procesamiento automático

### Sprint 8: Journey Reconstruction Module (3-4 horas)

**Objetivo:** Reconstruir journeys completos desde eventos procesados.

**Tareas:**
1. Implementar algoritmo de reconstrucción de journeys
2. Calcular segmentos operational y distribution
3. Calcular tiempos ajustados (excluyendo horas no laborables)
4. Comparar con SLAs y determinar compliance
5. Poblar tablas `journey_segments` y `journeys`

### Sprint 9: Incident Detection Module (2-3 horas)

**Objetivo:** Detectar anomalías automáticamente.

**Tareas:**
1. Implementar detección de exit_before_entry
2. Implementar detección de missing_entry/missing_exit
3. Implementar detección de stuck_sample
4. Implementar detección de missroute
5. Poblar tabla `incidents`

---

## ✅ Testing Checklist

### Soft Delete
- [ ] Eliminar postal center y verificar que no aparece en listado
- [ ] Verificar que readers del centro eliminado no aparecen
- [ ] Verificar que SLAs del centro eliminado no aparecen
- [ ] Verificar que datos históricos en diagnosis DB se mantienen intactos

### Diagnosis DB
- [ ] Verificar que las 4 tablas se crearon correctamente
- [ ] Verificar que todos los índices existen
- [ ] Verificar que políticas RLS funcionan (test con diferentes cuentas)
- [ ] Verificar constraints (intentar insertar datos inválidos)

---

## 📊 Métricas del Sprint

- **Tablas creadas:** 4 (processed_events, journey_segments, incidents, journeys)
- **Tablas modificadas:** 3 (postal_centers, readers, slas)
- **Líneas de SQL:** 485
- **Líneas de TypeScript:** 600+
- **Índices creados:** 30+
- **Políticas RLS:** 16 (4 por tabla × 4 tablas)
- **Constraints:** 15+
- **Foreign keys:** 20+

---

## 🎉 Estado del Proyecto

**Progreso General:** 55% (6/11 sprints completados)

**Sprints Completados:**
- ✅ Sprint 1-2: Infraestructura Base
- ✅ Sprint 3: Postal Centers Module
- ✅ Sprint 4: Readers Module Enhancement
- ✅ Sprint 5: Sites SLA Configuration
- ✅ Sprint 6: Diagnosis DB Schema Complete

**Próximos Sprints:**
- ⏳ Sprint 7: Event Consolidation (4-5h)
- ⏳ Sprint 8: Journey Reconstruction (3-4h)
- ⏳ Sprint 9: Incident Detection (2-3h)
- ⏳ Sprint 10: Integration & Orchestration (2-3h)
- ⏳ Sprint 11: Testing & Simulation (2h)

---

**Fecha de completación:** 10 de febrero de 2026  
**Próximo sprint:** Sprint 7 - Event Consolidation Module
