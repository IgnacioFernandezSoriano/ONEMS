# Plan de Implementación Técnica - Network Diagnostics Dashboard

**Fecha Actualización:** 9 de febrero de 2026  
**Proyecto:** ONEMS V3 - Módulo de Diagnóstico de Red  
**Fase Actual:** Frontend/UI Development - Sprint 4

---

## 📊 ESTADO ACTUAL DEL PROYECTO

### ✅ Sprint 3: Postal Centers Module (COMPLETADO)

**Fecha:** 9 de febrero de 2026  
**Duración:** 1 sesión completa  
**Estado:** ✅ 100% Completado

**Funcionalidades Implementadas:**

1. **Postal Centers CRUD**
   - ✅ Creación, edición, eliminación de centros postales
   - ✅ Campos: code, name, description, is_active
   - ✅ Calculation Mode: Natural Days vs Working Days
   - ✅ Herencia de calculation_mode desde Account Config
   - ✅ UI condicional: oculta horarios/festivos en modo Natural Days

2. **Weekly Schedule Management**
   - ✅ Calendario lunes-domingo con horarios por día
   - ✅ Herencia desde Account Config
   - ✅ Override por día: working_day, opening_hour, cutoff_time
   - ✅ Badges "Inherited" para días que usan configuración de cuenta
   - ✅ Persistencia con UPSERT
   - ✅ Carga de horarios existentes al editar centro

3. **Holidays Management (Non-Working Days)**
   - ✅ Dos niveles: Account-level (heredados) + Center-specific (locales)
   - ✅ Visual distinction con badges
   - ✅ CRUD de festivos específicos del centro
   - ✅ Base de datos: postal_center_id = NULL para cuenta

4. **Readers Module Enhancement**
   - ✅ Mixed Reader Gap hereda de Account Config
   - ✅ Placeholder muestra valor heredado
   - ✅ Hint azul cuando NULL
   - ✅ Campo solo visible para lectores tipo "Mixed"

**Base de Datos Creada:**
- ✅ `postal_centers` - Centros postales
- ✅ `readers` - Lectores RFID
- ✅ `weekly_schedule` - Horarios semanales
- ✅ `non_working_days` - Días festivos
- ✅ RLS policies configuradas
- ✅ Migración aplicada: `20260209100000_network_diagnostics_module.sql`

**Componentes Frontend:**
- ✅ `PostalCentersList.tsx` - Lista con búsqueda y filtros
- ✅ `PostalCenterForm.tsx` - Formulario con herencia
- ✅ `ReaderForm.tsx` - Formulario de lectores

**Hooks:**
- ✅ `usePostalCenters.ts` - CRUD, weekly schedule, holidays
- ✅ `useAccountConfig.ts` - Configuración de cuenta

**Traducciones:**
- ✅ 4 idiomas: en, es, fr, ar
- ✅ Keys: postal_centers.*, readers.*, common.*

**Build:**
- ✅ `onems-build-sprint3-final.zip` (1.9MB)
- ✅ Listo para deploy en Netlify

**Commits:**
- ✅ 12 commits pusheados a GitHub
- ✅ Último: `cfbf788` - docs: Update PROJECT_STATE.md

---

## 🎯 PRÓXIMO SPRINT: Sprint 4 - Readers Module Enhancement

### Objetivo
Completar módulo de Lectores con lista, asignación a centros y monitoreo de estado.

### Duración Estimada
3-4 horas

### Funcionalidades a Implementar

#### 1. Readers List View
- [ ] Tabla con todos los lectores del account
- [ ] Columnas: Reader ID, Name, Type, Postal Center, Gap (Mixed only), Status
- [ ] Filtros:
  - [ ] Por centro postal (dropdown)
  - [ ] Por tipo: Entry/Exit/Mixed (chips)
  - [ ] Por estado: Active/Inactive (toggle)
- [ ] Búsqueda por reader_id o nombre
- [ ] Acciones: [Edit], [Delete], [View Details]
- [ ] Paginación (25 lectores por página)

#### 2. Reader Assignment to Postal Centers
- [ ] Dropdown en ReaderForm para seleccionar centro postal
- [ ] Validación: un reader solo puede estar en un centro
- [ ] Actualización de `postal_center_id` en tabla `readers`
- [ ] Mostrar centro asignado en lista de lectores

#### 3. Reader Status Monitoring (Opcional)
- [ ] Indicador de último evento recibido
- [ ] Estados:
  - Active: eventos en últimas 24h (verde)
  - Inactive: sin eventos 24h-7d (amarillo)
  - Offline: sin eventos >7d (rojo)
- [ ] Query a `rfid_intermediate_db` para último evento
- [ ] Badge de estado en lista

#### 4. Bulk Operations (Opcional)
- [ ] Checkbox para selección múltiple
- [ ] Acciones bulk:
  - [ ] Activar/desactivar múltiples lectores
  - [ ] Cambiar centro postal de múltiples lectores
  - [ ] Eliminar múltiples lectores (con confirmación)

### Archivos a Crear/Modificar

**Crear:**
- `src/components/postal-centers/ReadersList.tsx`
- `src/components/postal-centers/ReaderStatusBadge.tsx` (opcional)

**Modificar:**
- `src/components/postal-centers/ReaderForm.tsx` (agregar dropdown de centro)
- `src/hooks/usePostalCenters.ts` (agregar queries de estado)
- `public/locales/*.csv` (traducciones)

### Queries SQL Necesarias

**Lista de Lectores con Centro:**
```sql
SELECT r.*, pc.name as postal_center_name
FROM readers r
LEFT JOIN postal_centers pc ON r.postal_center_id = pc.id
WHERE r.account_id = $1
ORDER BY r.name
```

**Último Evento por Lector (Status):**
```sql
SELECT reader_id, MAX(event_time) as last_event
FROM rfid_intermediate_db
WHERE account_id = $1
GROUP BY reader_id
```

### Testing Checklist
- [ ] Crear lector sin centro asignado
- [ ] Crear lector con centro asignado
- [ ] Editar lector y cambiar centro
- [ ] Filtrar por centro postal
- [ ] Filtrar por tipo (Entry/Exit/Mixed)
- [ ] Filtrar por estado (Active/Inactive)
- [ ] Búsqueda por reader_id
- [ ] Verificar estado de lectores (opcional)
- [ ] Bulk operations (opcional)

---

## 📋 PLAN DE IMPLEMENTACIÓN FUTURO

### Sprint 5: Dashboard Principal - Estructura Base (2-3 días)

**Objetivo:** Crear página principal del dashboard con tabs y filtros globales

#### Tareas:
1. **Estructura Base**
   - [ ] Crear página `/diagnostics/network` con routing
   - [ ] Implementar sistema de tabs (4 tabs, 2 activos inicialmente)
   - [ ] Crear componente `DiagnosticsFilters` con 4 filtros:
     - Date Range (preset: Today, 24h, 7d, 30d, Custom)
     - Reader IDs (multi-select)
     - Severity (chips: Critical, High, Medium, Low)
     - Route Status (All, Complete, Incomplete)
   - [ ] Crear hook `useDiagnosticsFilters` para gestionar estado
   - [ ] Agregar navegación en menú lateral de ONEMS V2

2. **KPIs Globales**
   - [ ] Crear hook `useGlobalKPIs` con queries para 5 KPIs:
     - On-Time Rate
     - Avg. Transit Time
     - Active Anomalies
     - Routes Processed
     - Network Efficiency
   - [ ] Implementar cálculo de tendencias (vs período anterior)
   - [ ] Crear componente `GlobalKPIs` con 5 tarjetas KPI
   - [ ] Agregar colores dinámicos según umbrales
   - [ ] Implementar tooltips explicativos
   - [ ] Sparklines (mini-gráficos 7 días) en KPIs

**Archivos a Crear:**
```
src/
├── pages/diagnostics/
│   └── NetworkDiagnostics.tsx
├── components/diagnostics/
│   ├── GlobalKPIs.tsx
│   └── DiagnosticsFilters.tsx
├── hooks/diagnostics/
│   ├── useGlobalKPIs.ts
│   └── useDiagnosticsFilters.ts
└── types/
    └── diagnostics.ts
```

---

### Sprint 6: Tab Overview (2 días)

**Objetivo:** Implementar tab Overview con gráficos y tabla de actividad reciente

#### Tareas:
1. **Gráficos de Overview**
   - [ ] Crear hook `useDiagnosisAnomalies` para fetch de anomalías
   - [ ] Implementar `AnomalyTrendChart` (stacked area chart)
     - Eje X: días
     - Eje Y: cantidad de anomalías
     - Stacks: por tipo de anomalía
   - [ ] Implementar `SeverityDistributionChart` (donut chart)
     - Distribución de anomalías por severidad
     - Colores: Critical (rojo), High (naranja), Medium (amarillo), Low (azul)

2. **Tabla de Actividad Reciente**
   - [ ] Crear `RecentActivityTable` con últimas 15 rutas
   - [ ] Columnas: Tag ID, Start Time, Duration, Readers, Events, Anomalies, Status
   - [ ] Click en fila → navega a Routes & Tracking (Sprint 8)

3. **Interactividad**
   - [ ] Click en gráfico de tendencia → filtra tabla por día
   - [ ] Click en donut chart → filtra por severidad
   - [ ] Hover en gráficos → tooltip con detalles

**Archivos a Crear:**
```
src/components/diagnostics/
├── tabs/
│   └── OverviewTab.tsx
├── charts/
│   ├── AnomalyTrendChart.tsx
│   └── SeverityDistributionChart.tsx
└── tables/
    └── RecentActivityTable.tsx
```

---

### Sprint 7: Tab Anomalies (2-3 días)

**Objetivo:** Implementar tab Anomalies con heatmap, gráficos y tabla interactiva

#### Tareas:
1. **Gráficos de Anomalías**
   - [ ] Implementar `TypeSeverityMatrix` (heatmap)
     - Eje X: Tipo de anomalía
     - Eje Y: Severidad
     - Color: cantidad de anomalías
   - [ ] Implementar `AnomaliesByReaderChart` (horizontal bar chart)
     - Top 10 lectores con más anomalías
     - Colores por severidad

2. **Tabla de Anomalías**
   - [ ] Crear `AnomalyListTable` con paginación (25 filas/página)
   - [ ] Columnas: Tag ID, Type, Severity, Reader, Detected At, Status, Actions
   - [ ] Ordenamiento por severidad (Critical → Low) y fecha
   - [ ] Filtros aplicados desde DiagnosticsFilters

3. **Acciones de Resolución**
   - [ ] Botón [View] → abre modal con detalles de anomalía
   - [ ] Botón [Resolve] → marca anomalía como resuelta
   - [ ] Crear hook `useResolveAnomaly` para actualizar DB
   - [ ] Checkbox para selección múltiple
   - [ ] Botón "Resolve Selected" para bulk actions
   - [ ] Confirmación antes de resolver múltiples

4. **Modal de Detalle**
   - [ ] Mostrar información completa de la anomalía
   - [ ] Mostrar ruta asociada (si existe)
   - [ ] Mostrar metadata (JSON expandible)
   - [ ] Botón para marcar como resuelta desde modal

**Archivos a Crear:**
```
src/components/diagnostics/
├── tabs/
│   └── AnomaliesTab.tsx
├── charts/
│   ├── TypeSeverityMatrix.tsx
│   └── AnomaliesByReaderChart.tsx
├── tables/
│   └── AnomalyListTable.tsx
└── modals/
    └── AnomalyDetailModal.tsx
src/hooks/diagnostics/
└── useResolveAnomaly.ts
```

---

### Sprint 8: Tab Performance (Post-MVP, 2 días)

**Objetivo:** Análisis de performance por segmentos y lectores

#### Tareas:
1. **Heatmap de Segmentos**
   - [ ] Crear hook `useDiagnosisTimeMetrics` para fetch de métricas
   - [ ] Implementar heatmap From Reader × To Reader
   - [ ] Color según delay promedio
   - [ ] Tooltip con detalles: avg duration, expected, delay

2. **Ranking de Lectores**
   - [ ] Top 10 lectores más lentos
   - [ ] Top 10 lectores más rápidos
   - [ ] Tabla con: Reader, Avg Duration, Expected, Delay %

3. **Gráficos de Tendencia**
   - [ ] On-Time Rate trend (últimos 30 días)
   - [ ] Avg Transit Time trend (últimos 30 días)

**Archivos a Crear:**
```
src/components/diagnostics/
├── tabs/
│   └── PerformanceTab.tsx
└── charts/
    ├── SegmentHeatmap.tsx
    ├── ReaderRankingTable.tsx
    └── OnTimeRateTrendChart.tsx
```

---

### Sprint 9: Tab Routes & Tracking (Post-MVP, 2 días)

**Objetivo:** Búsqueda y visualización de rutas individuales

#### Tareas:
1. **Búsqueda de Rutas**
   - [ ] Input de búsqueda por tag_id
   - [ ] Autocompletado con últimas rutas
   - [ ] Filtros: Date Range, Status (Complete/Incomplete)

2. **Timeline Visual**
   - [ ] Timeline horizontal con eventos de la ruta
   - [ ] Nodos: lectores
   - [ ] Líneas: segmentos entre lectores
   - [ ] Color según delay (verde: on-time, rojo: delayed)
   - [ ] Tooltip con detalles de cada evento

3. **Detalles de Ruta**
   - [ ] Tabla con todos los eventos RFID
   - [ ] Columnas: Reader, Event Time, Duration from Previous
   - [ ] Anomalías asociadas (badges)
   - [ ] Botón "Export to CSV"

**Archivos a Crear:**
```
src/components/diagnostics/
├── tabs/
│   └── RoutesTrackingTab.tsx
├── RouteSearch.tsx
├── RouteTimeline.tsx
└── RouteDetailsTable.tsx
src/hooks/diagnostics/
└── useDiagnosisRoutes.ts
```

---

### Sprint 10: i18n, Testing y Deploy (1 día)

**Objetivo:** Traducciones, testing exhaustivo y deploy a producción

#### Tareas:
1. **Traducciones**
   - [ ] Agregar traducciones en `/public/locales/` (en, es, fr, ar)
   - [ ] Keys: diagnostics.*, anomalies.*, performance.*, routes.*
   - [ ] Verificar traducciones en todos los componentes

2. **Testing**
   - [ ] Probar con datos reales (379 rutas, 382 anomalías)
   - [ ] Verificar RLS policies (multi-tenant)
   - [ ] Testing de KPIs con diferentes períodos
   - [ ] Testing de filtros en todos los tabs
   - [ ] Testing de acciones de resolución
   - [ ] Testing de bulk operations
   - [ ] Testing responsive (desktop, tablet, mobile)
   - [ ] Testing en 4 idiomas

3. **Deploy**
   - [ ] Build de producción
   - [ ] Deploy a Netlify
   - [ ] Testing en producción
   - [ ] Verificar performance de queries SQL
   - [ ] Agregar índices si es necesario

---

## 🏗️ ARQUITECTURA DE COMPONENTES

### Estructura de Archivos Completa

```
src/
├── pages/
│   └── diagnostics/
│       └── NetworkDiagnostics.tsx          # Página principal
├── components/
│   └── diagnostics/
│       ├── GlobalKPIs.tsx                  # 5 KPIs superiores
│       ├── DiagnosticsFilters.tsx          # Filtros globales
│       ├── tabs/
│       │   ├── OverviewTab.tsx             # Tab 1 (MVP)
│       │   ├── AnomaliesTab.tsx            # Tab 2 (MVP)
│       │   ├── PerformanceTab.tsx          # Tab 3 (post-MVP)
│       │   └── RoutesTrackingTab.tsx       # Tab 4 (post-MVP)
│       ├── charts/
│       │   ├── AnomalyTrendChart.tsx       # Tendencia de anomalías
│       │   ├── SeverityDistributionChart.tsx # Donut chart
│       │   ├── OnTimeRateTrendChart.tsx    # On-Time Rate
│       │   ├── TypeSeverityMatrix.tsx      # Heatmap
│       │   ├── AnomaliesByReaderChart.tsx  # Bar chart
│       │   ├── SegmentHeatmap.tsx          # Heatmap de segmentos
│       │   └── ReaderRankingTable.tsx      # Ranking de lectores
│       ├── tables/
│       │   ├── RecentActivityTable.tsx     # Últimas 15 rutas
│       │   ├── AnomalyListTable.tsx        # Anomalías con acciones
│       │   └── RouteDetailsTable.tsx       # Detalles de ruta
│       ├── modals/
│       │   └── AnomalyDetailModal.tsx      # Detalle de anomalía
│       ├── RouteSearch.tsx                 # Búsqueda de rutas
│       └── RouteTimeline.tsx               # Timeline visual
├── hooks/
│   └── diagnostics/
│       ├── useGlobalKPIs.ts                # 5 KPIs globales
│       ├── useDiagnosisRoutes.ts           # Fetch diagnosis_routes
│       ├── useDiagnosisAnomalies.ts        # Fetch diagnosis_anomalies
│       ├── useDiagnosisTimeMetrics.ts      # Fetch diagnosis_time_metrics
│       ├── useResolveAnomaly.ts            # Marcar como resuelta
│       └── useDiagnosticsFilters.ts        # Gestión de filtros
└── types/
    └── diagnostics.ts                      # TypeScript types
```

---

## 🔧 DECISIONES TÉCNICAS

### Librería de Gráficos
**Decisión:** Usar **Recharts** (ya usado en ONEMS V2)  
**Justificación:** Consistencia con el proyecto existente, bien documentado, responsive

### Gestión de Estado de Filtros
**Decisión:** Context API + Custom Hook `useDiagnosticsFilters`  
**Justificación:** Los filtros son compartidos por todos los tabs, evita prop drilling

### Formato de Fechas
**Decisión:** Usar **date-fns** para formateo y cálculos  
**Justificación:** Ya usado en ONEMS V2, soporta i18n

### Paginación de Tablas
**Decisión:** Paginación del lado del cliente para MVP, server-side post-MVP  
**Justificación:** Con 382 anomalías, paginación cliente es suficiente. Optimizar después si crece.

### Tooltips
**Decisión:** Usar **react-tooltip** o componente nativo de Tailwind  
**Justificación:** Ligero, accesible, fácil de implementar

---

## 📊 QUERIES SQL CLAVE

### KPI 1: On-Time Rate
```sql
SELECT ROUND(
  COUNT(*) FILTER (WHERE r.id NOT IN (
    SELECT DISTINCT route_id FROM diagnosis_anomalies
    WHERE anomaly_type = 'excessive_delay'
  )) * 100.0 / NULLIF(COUNT(*), 0), 1
) FROM diagnosis_routes r
WHERE r.account_id = $1
  AND r.route_start_time BETWEEN $date_from AND $date_to
```

### KPI 2: Avg. Transit Time
```sql
SELECT ROUND(AVG(total_duration_hours), 1)
FROM diagnosis_routes
WHERE account_id = $1
  AND is_complete = true
  AND route_start_time BETWEEN $date_from AND $date_to
```

### KPI 3: Active Anomalies
```sql
SELECT COUNT(*)
FROM diagnosis_anomalies
WHERE account_id = $1
  AND resolved = false
  AND detected_at BETWEEN $date_from AND $date_to
```

### KPI 4: Routes Processed
```sql
SELECT COUNT(*)
FROM diagnosis_routes
WHERE account_id = $1
  AND route_start_time BETWEEN $date_from AND $date_to
```

### KPI 5: Network Efficiency
```sql
SELECT ROUND(
  COUNT(*) FILTER (WHERE r.id NOT IN (
    SELECT DISTINCT route_id FROM diagnosis_anomalies
    WHERE route_id IS NOT NULL
  )) * 100.0 / NULLIF(COUNT(*), 0), 1
) FROM diagnosis_routes r
WHERE r.account_id = $1
  AND r.route_start_time BETWEEN $date_from AND $date_to
```

### Anomaly Trend (Tab Overview)
```sql
SELECT DATE_TRUNC('day', detected_at) as day,
       anomaly_type,
       COUNT(*) as count
FROM diagnosis_anomalies
WHERE account_id = $1
  AND detected_at BETWEEN $date_from AND $date_to
GROUP BY day, anomaly_type
ORDER BY day
```

### Severity Distribution (Tab Overview)
```sql
SELECT severity, COUNT(*) as count
FROM diagnosis_anomalies
WHERE account_id = $1
  AND resolved = false
  AND detected_at BETWEEN $date_from AND $date_to
GROUP BY severity
```

### Recent Activity Table (Tab Overview)
```sql
SELECT id, tag_id, route_start_time, route_end_time,
       total_duration_hours, reader_sequence, event_count,
       is_complete,
       (SELECT COUNT(*) FROM diagnosis_anomalies a WHERE a.route_id = r.id) as anomaly_count,
       (SELECT MAX(severity) FROM diagnosis_anomalies a WHERE a.route_id = r.id) as max_severity
FROM diagnosis_routes r
WHERE account_id = $1
  AND route_start_time BETWEEN $date_from AND $date_to
ORDER BY route_start_time DESC
LIMIT 15
```

### Anomaly List (Tab Anomalies)
```sql
SELECT id, route_id, tag_id, anomaly_type, severity,
       description, reader_id, detected_at, resolved, metadata
FROM diagnosis_anomalies
WHERE account_id = $1
  AND detected_at BETWEEN $date_from AND $date_to
  AND ($reader_id IS NULL OR reader_id = $reader_id)
  AND severity = ANY($severities)
ORDER BY
  CASE severity
    WHEN 'critical' THEN 1
    WHEN 'high' THEN 2
    WHEN 'medium' THEN 3
    WHEN 'low' THEN 4
  END,
  detected_at DESC
LIMIT $limit OFFSET $offset
```

---

## 📅 CRONOGRAMA ESTIMADO

| Sprint | Duración | Entregable | Estado |
|--------|----------|------------|--------|
| **Sprint 3: Postal Centers** | 1 sesión | CRUD + Weekly Schedule + Holidays | ✅ Completado |
| **Sprint 4: Readers Enhancement** | 3-4 horas | Lista + Asignación + Monitoreo | ⏳ Próximo |
| **Sprint 5: Dashboard Base** | 2-3 días | Página + Tabs + Filtros + KPIs | ⏳ Pendiente |
| **Sprint 6: Tab Overview** | 2 días | Gráficos + Tabla de actividad | ⏳ Pendiente |
| **Sprint 7: Tab Anomalies** | 2-3 días | Tabla interactiva + Acciones | ⏳ Pendiente |
| **Sprint 8: Tab Performance** | 2 días | Heatmap + Ranking de lectores | ⏳ Post-MVP |
| **Sprint 9: Tab Routes & Tracking** | 2 días | Búsqueda + Timeline visual | ⏳ Post-MVP |
| **Sprint 10: i18n y Testing** | 1 día | Dashboard MVP completo | ⏳ Pendiente |
| **Total MVP** | ~10-12 días | Dashboard funcional en producción | 🔄 En progreso |
| **Total Completo** | ~14-16 días | Dashboard completo con 4 tabs | ⏳ Pendiente |

---

## ⚠️ RIESGOS Y MITIGACIÓN

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|--------------|---------|------------|
| Queries SQL lentas con muchos datos | Media | Alto | Agregar índices en DB, paginación server-side |
| Cálculos de KPIs incorrectos | Media | Alto | Testing exhaustivo con datos reales, validación manual |
| Gráficos no responsive | Baja | Medio | Usar Recharts con ResponsiveContainer |
| RLS policies no funcionan correctamente | Baja | Crítico | Testing con múltiples cuentas antes de deploy |
| Traducciones incompletas | Media | Bajo | Usar claves en inglés como fallback |

---

## 📚 COMPONENTES REUTILIZABLES DE ONEMS V2

### Componentes Disponibles
- `KPICard` : Tarjeta para mostrar métricas clave
- `ReportFilters` : Componente de filtros colapsable
- `PageHeader` : Encabezado de página con título y descripción
- `Button` : Botones con estados de carga
- `Table` : Tabla con paginación y ordenamiento
- `Modal` : Modal para detalles de anomalía
- `Badge` : Badge para severidad/estado
- `Tooltip` : Tooltip para información adicional

### Componentes a Crear
- `GlobalKPIs` : Sección de 5 KPIs superiores (nuevo)
- `DiagnosticsFilters` : Filtros específicos para diagnóstico (nuevo)
- Todos los gráficos (nuevos, usando Recharts)
- Tablas específicas de diagnóstico (nuevos)

---

## ✅ TESTING Y VALIDACIÓN

### Casos de Prueba MVP

#### 1. KPIs Globales
- [ ] Verificar cálculos correctos con datos reales
- [ ] Verificar colores dinámicos según umbrales
- [ ] Verificar tendencias vs período anterior
- [ ] Verificar tooltips informativos

#### 2. Filtros
- [ ] Verificar que filtros se aplican a todos los tabs
- [ ] Verificar presets de fecha (Today, 24h, 7d, 30d)
- [ ] Verificar filtro por reader (multi-select)
- [ ] Verificar filtro por severity (chips toggle)
- [ ] Verificar filtro por route status (segmented control)

#### 3. Tab Overview
- [ ] Verificar gráfico de tendencia de anomalías
- [ ] Verificar gráfico de distribución por severidad
- [ ] Verificar tabla de últimas 15 rutas
- [ ] Verificar click en gráfico → filtra tabla
- [ ] Verificar click en fila → navega a Routes & Tracking

#### 4. Tab Anomalies
- [ ] Verificar heatmap Type × Severity
- [ ] Verificar gráfico Anomalies by Reader
- [ ] Verificar tabla paginada (25 filas/página)
- [ ] Verificar acción [View] → abre modal
- [ ] Verificar acción [Resolve] → actualiza DB
- [ ] Verificar bulk actions (Resolve Selected)

#### 5. Multi-tenant (RLS)
- [ ] Verificar que cada cuenta ve solo sus datos
- [ ] Verificar que superadmin ve todos los datos

#### 6. i18n
- [ ] Verificar traducciones en inglés
- [ ] Verificar traducciones en español
- [ ] Verificar traducciones en francés
- [ ] Verificar traducciones en árabe (RTL)

---

## 🎯 PRÓXIMOS PASOS INMEDIATOS

### Para Sprint 4 (Próxima Sesión):

1. **Crear ReadersList.tsx**
   - Tabla con todos los lectores
   - Filtros por centro, tipo, estado
   - Búsqueda por reader_id
   - Acciones: Edit, Delete, View

2. **Modificar ReaderForm.tsx**
   - Agregar dropdown de centro postal
   - Validación de asignación única

3. **Actualizar usePostalCenters.ts**
   - Query para lista de lectores con centro
   - Query para último evento (status)
   - Bulk operations

4. **Traducciones**
   - Agregar keys para readers list
   - Status badges
   - Bulk actions

5. **Testing**
   - CRUD completo de lectores
   - Asignación a centros
   - Filtros y búsqueda
   - Bulk operations

---

**Fin del documento. Actualizado al final de Sprint 3 - 9 de febrero de 2026**
