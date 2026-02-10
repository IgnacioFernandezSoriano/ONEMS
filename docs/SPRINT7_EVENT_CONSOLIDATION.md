# Sprint 7: Event Consolidation Module

**Estado:** ✅ Completado  
**Fecha:** 10 de febrero de 2026  
**Módulo:** Diagnóstico de Red - Consolidación de Eventos RFID

---

## Resumen Ejecutivo

El Sprint 7 implementa el **Módulo de Consolidación de Eventos RFID**, que procesa lecturas RFID sin procesar (raw events) y las consolida en eventos de entrada/salida únicos para cada etiqueta en cada centro postal. El sistema detecta automáticamente anomalías como salidas faltantes, lectores desconocidos y problemas de calidad de datos.

### Características Principales

- ✅ Procesamiento automático de eventos RFID sin procesar
- ✅ Consolidación inteligente según tipo de lector (Entry/Exit/Mixed)
- ✅ Detección de gaps de 30 minutos en lectores mixtos
- ✅ Cálculo de `analysis_datetime` para modo Working Days
- ✅ Detección automática de anomalías (Missing Exit, Unknown Reader, Data Quality)
- ✅ Estimación de timestamps de salida faltantes usando SLAs
- ✅ Auditoría completa de eventos procesados
- ✅ Dashboard UI con métricas y tabla de incidencias
- ✅ Ejecución manual de consolidación desde UI

---

## Arquitectura del Sistema

### Base de Datos

#### Nuevas Tablas

**1. `rfid_events_raw`**
```sql
CREATE TABLE rfid_events_raw (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  event_id TEXT NOT NULL,
  read_local_datetime TIMESTAMP NOT NULL,
  reader_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  is_processed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(account_id, event_id)
);
```

**2. `audit_raw_reads`**
```sql
CREATE TABLE audit_raw_reads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  processed_event_id UUID NOT NULL REFERENCES processed_events(id) ON DELETE CASCADE,
  event_id TEXT NOT NULL,
  read_local_datetime TIMESTAMP NOT NULL,
  reader_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  is_first_read BOOLEAN NOT NULL,
  archived_at TIMESTAMP DEFAULT NOW()
);
```

#### Funciones SQL (7 funciones principales)

1. **`get_reader_info(p_account_id, p_reader_id)`**
   - Obtiene información del lector y centro postal
   - Retorna: reader_type, postal_center_id, postal_center_name, postal_center_code

2. **`calculate_next_working_datetime(p_timestamp, p_postal_center_id)`**
   - Calcula el próximo datetime hábil excluyendo feriados y horarios no laborables
   - Usado para ajustar `analysis_datetime` en modo Working Days

3. **`consolidate_entry_reader_events(p_account_id, p_reader_id, p_reader_info, p_calculation_mode)`**
   - Consolida eventos de lectores tipo Entry
   - Toma el MIN(read_local_datetime) como timestamp de entrada
   - Aplica `analysis_datetime` si está en modo working_days

4. **`consolidate_exit_reader_events(p_account_id, p_reader_id, p_reader_info, p_calculation_mode)`**
   - Consolida eventos de lectores tipo Exit
   - Toma el MAX(read_local_datetime) como timestamp de salida
   - NO aplica ajuste de `analysis_datetime`

5. **`consolidate_mixed_reader_events(p_account_id, p_reader_id, p_reader_info, p_calculation_mode)`**
   - Consolida eventos de lectores tipo Mixed
   - Detecta gaps > 30 minutos entre lecturas consecutivas
   - Genera evento Entry (primera lectura antes del gap) y Exit (última lectura después del gap)
   - Aplica `analysis_datetime` solo a eventos de entrada en modo working_days

6. **`detect_missing_exit_and_estimate(p_account_id)`**
   - Detecta etiquetas con entrada pero sin salida en el mismo centro postal
   - Estima timestamp de salida usando `expected_time` del SLA
   - Crea incidencia tipo "missing_exit"
   - Marca evento de salida estimado con `is_estimated = TRUE`

7. **`consolidate_rfid_events(p_account_id)`**
   - Función principal que orquesta todo el proceso
   - Pasos:
     1. Obtener modo de cálculo (natural_days / working_days)
     2. Procesar lectores Entry
     3. Procesar lectores Exit
     4. Procesar lectores Mixed
     5. Detectar y estimar salidas faltantes
     6. Archivar eventos procesados en `audit_raw_reads`
     7. Eliminar eventos procesados de `rfid_events_raw`
     8. Registrar log en `processing_logs`
   - Retorna: events_processed, incidents_detected, execution_time_ms

---

## Edge Function

**Ubicación:** `supabase/functions/consolidate-rfid-events/index.ts`

### Funcionalidad

- Endpoint HTTP POST para ejecutar consolidación de eventos
- Autenticación mediante JWT de Supabase
- Obtiene `account_id` del perfil del usuario autenticado
- Invoca función SQL `consolidate_rfid_events(account_id)`
- Retorna métricas de procesamiento

### Uso

```typescript
POST /functions/v1/consolidate-rfid-events
Headers:
  Authorization: Bearer <JWT_TOKEN>
  Content-Type: application/json

Response:
{
  "success": true,
  "events_processed": 42,
  "incidents_detected": 2,
  "execution_time_ms": 1234
}
```

---

## Interfaz de Usuario

**Ruta:** `/diagnosis/event-consolidation`  
**Archivo:** `src/pages/diagnosis/EventConsolidation.tsx`

### Componentes

#### 1. Métricas Dashboard (Cards)
- **Eventos Pendientes:** Contador de eventos raw sin procesar
- **Incidencias Totales:** Total de anomalías detectadas
- **Última Consolidación:** Timestamp de la última ejecución

#### 2. Botón de Consolidación
- Ejecuta Edge Function para procesar eventos
- Deshabilitado si no hay eventos pendientes
- Muestra spinner durante procesamiento
- Toast con resultado (eventos procesados + incidencias detectadas)

#### 3. Tabla de Incidencias
- Columnas: Tag ID, Tipo, Centro Postal, Descripción, Detectado, Estado
- Badges de color según tipo y estado
- Ordenable por columnas
- Últimas 50 incidencias

### Traducciones

Todas las etiquetas están traducidas en 4 idiomas (en, es, fr, ar) en el archivo `public/locales/es.csv`.

---

## Lógica de Consolidación

### Tipos de Lectores

#### Entry Reader
- **Lógica:** MIN(read_local_datetime) de todas las lecturas del mismo tag_id
- **Tipo de evento:** `entry`
- **Analysis Datetime:** Ajustado en modo working_days

#### Exit Reader
- **Lógica:** MAX(read_local_datetime) de todas las lecturas del mismo tag_id
- **Tipo de evento:** `exit`
- **Analysis Datetime:** Sin ajuste (mismo que event_timestamp)

#### Mixed Reader
- **Lógica:** 
  1. Ordenar lecturas por timestamp
  2. Calcular gaps entre lecturas consecutivas
  3. Encontrar el gap máximo
  4. Si gap > 30 minutos:
     - Entry: Primera lectura antes del gap
     - Exit: Última lectura después del gap
  5. Si gap ≤ 30 minutos:
     - Entry: MIN(read_local_datetime)
     - Exit: MAX(read_local_datetime)
- **Tipos de evento:** `entry` + `exit`
- **Analysis Datetime:** Solo ajustado para entry en modo working_days

### Detección de Anomalías

#### Missing Exit
- **Condición:** Existe entrada pero no salida para el mismo tag_id en el mismo postal_center_id
- **Acción:** 
  - Crear incidencia tipo "missing_exit"
  - Estimar timestamp de salida: entry_timestamp + SLA.expected_time
  - Insertar evento de salida con `is_estimated = TRUE`

#### Unknown Reader
- **Condición:** reader_id no existe en tabla `readers`
- **Acción:** Crear incidencia tipo "unknown_reader"

#### Data Quality
- **Condición:** Lecturas duplicadas, timestamps fuera de rango, etc.
- **Acción:** Crear incidencia tipo "data_quality"

### Auditoría

Para cada evento consolidado:
1. Archivar en `audit_raw_reads`:
   - Primera lectura (is_first_read = TRUE)
   - Última lectura (is_first_read = FALSE)
2. Eliminar todas las lecturas raw de `rfid_events_raw`
3. Registrar en `processing_logs`:
   - process_type: 'consolidation'
   - records_processed: cantidad de eventos
   - execution_time_ms: duración

---

## Datos de Prueba

**Archivo:** `SPRINT7_TEST_RAW_EVENTS.sql`

### Contenido
- 42 eventos raw para 5 etiquetas diferentes
- Escenarios cubiertos:
  1. Journey con Mixed Reader (NY Hub Central)
  2. Journey con Entry + Exit separados (NY Hub Central)
  3. Journey con Mixed Reader (LA Hub Downtown)
  4. Journey con Entry + Exit (Baltimore Regional)
  5. Journey con Entry + Exit (Sacramento Regional)

### Ejecución
```sql
-- Ejecutar en Supabase SQL Editor
\i SPRINT7_TEST_RAW_EVENTS.sql

-- Verificar eventos insertados
SELECT COUNT(*) FROM rfid_events_raw WHERE is_processed = FALSE;

-- Ejecutar consolidación
SELECT * FROM consolidate_rfid_events('f4d823d2-93e6-4755-9a89-9da87e7fa86e');

-- Verificar eventos consolidados
SELECT * FROM processed_events WHERE created_at > NOW() - INTERVAL '1 hour';

-- Verificar incidencias
SELECT * FROM incidents WHERE detected_at > NOW() - INTERVAL '1 hour';
```

---

## Integración con Módulos Existentes

### SLAs Configuration (Sprint 5)
- Utiliza `expected_time` para estimar salidas faltantes
- Consulta SLAs por `origin_postal_center_id` y `destination_postal_center_id`

### Postal Centers
- Obtiene información del centro postal asociado a cada lector
- Usa `postal_center_id` para cálculos de working_days

### Account Configuration
- Lee `calculation_mode` (natural_days / working_days) desde `account_configuration`
- Aplica lógica de `analysis_datetime` según configuración

---

## Seguridad (RLS Policies)

Todas las tablas tienen políticas RLS habilitadas:

```sql
-- rfid_events_raw
CREATE POLICY "Users can view raw events from their account"
  ON rfid_events_raw FOR SELECT
  USING (account_id = auth.uid_account_id());

CREATE POLICY "Users can insert raw events to their account"
  ON rfid_events_raw FOR INSERT
  WITH CHECK (account_id = auth.uid_account_id());

-- audit_raw_reads
CREATE POLICY "Users can view audit from their account"
  ON audit_raw_reads FOR SELECT
  USING (account_id = auth.uid_account_id());
```

---

## Pruebas Realizadas

### 1. Prueba de Consolidación Entry Reader
- ✅ Múltiples lecturas del mismo tag_id se consolidan en un solo evento
- ✅ Timestamp = MIN(read_local_datetime)
- ✅ Analysis_datetime ajustado en modo working_days

### 2. Prueba de Consolidación Exit Reader
- ✅ Múltiples lecturas del mismo tag_id se consolidan en un solo evento
- ✅ Timestamp = MAX(read_local_datetime)
- ✅ Analysis_datetime = event_timestamp (sin ajuste)

### 3. Prueba de Consolidación Mixed Reader
- ✅ Gap > 30 min detectado correctamente
- ✅ Genera evento Entry (primera lectura antes del gap)
- ✅ Genera evento Exit (última lectura después del gap)
- ✅ Analysis_datetime ajustado solo para entry

### 4. Prueba de Detección Missing Exit
- ✅ Detecta entrada sin salida
- ✅ Crea incidencia tipo "missing_exit"
- ✅ Estima timestamp de salida usando SLA
- ✅ Marca evento estimado con is_estimated = TRUE

### 5. Prueba de Auditoría
- ✅ Primera y última lectura archivadas en audit_raw_reads
- ✅ Eventos raw eliminados de rfid_events_raw
- ✅ Log registrado en processing_logs

---

## Archivos Creados/Modificados

### Base de Datos
- ✅ `SPRINT7_MIGRATION_TABLES.sql` - Tablas rfid_events_raw y audit_raw_reads
- ✅ `SPRINT7_MIGRATION_FUNCTIONS_FIXED.sql` - 7 funciones SQL (27KB)
- ✅ `SPRINT7_TEST_RAW_EVENTS.sql` - Datos de prueba (42 eventos)

### Backend
- ✅ `supabase/functions/consolidate-rfid-events/index.ts` - Edge Function

### Frontend
- ✅ `src/pages/diagnosis/EventConsolidation.tsx` - Página UI
- ✅ `src/App.tsx` - Ruta agregada
- ✅ `src/components/layout/Sidebar.tsx` - Menú agregado
- ✅ `public/locales/es.csv` - Traducciones agregadas

### Documentación
- ✅ `docs/SPRINT7_EVENT_CONSOLIDATION.md` - Este documento

---

## Próximos Pasos (Sprint 8)

1. **Automatización de Consolidación**
   - Trigger automático cada X minutos
   - Configuración de frecuencia por cuenta

2. **Visualización de Métricas**
   - Gráficos de tendencias de incidencias
   - Dashboard de calidad de datos RFID

3. **Resolución de Incidencias**
   - UI para marcar incidencias como resueltas
   - Comentarios y seguimiento

4. **Notificaciones**
   - Alertas cuando se detectan anomalías críticas
   - Email/SMS para Missing Exit

5. **Exportación de Reportes**
   - CSV/Excel de incidencias
   - Reporte de calidad de datos RFID

---

## Contacto

**Equipo de Desarrollo:** ONEMS V3  
**Sprint:** 7  
**Fecha de Finalización:** 10 de febrero de 2026
