# Plan Lógico de Implementación: Pipeline EPCIS

**Versión:** 1.0
**Fecha:** 2026-02-14

## 1. Objetivo

Implementar de forma incremental y ordenada el pipeline completo de procesamiento de datos EPCIS, desde la ingesta hasta la visualización, asegurando que cada fase se construya sobre una base sólida y validada.

## 2. Estrategia de Implementación

La estrategia se basa en un enfoque **bottom-up**, comenzando por la capa de datos y subiendo progresivamente hacia la lógica de negocio, las APIs y finalmente la interfaz de usuario. Cada fase debe ser validada con datos de prueba antes de pasar a la siguiente.

```mermaid
gantt
    title Plan de Implementación del Pipeline EPCIS
    dateFormat  YYYY-MM-DD
    axisFormat  %m-%d

    section Backend
        Fase 1: Estructura de Datos :done, b1, 2026-02-14, 1d
        Fase 2: Consolidación Avanzada :b2, after b1, 2d
        Fase 3: Construcción de Segmentos :b3, after b2, 2d
        Fase 4: Agregación de Rutas :b4, after b3, 1d
        Fase 5: APIs :b5, after b4, 2d

    section Frontend
        Fase 6: Pantalla de Monitorización :f1, after b5, 3d
        Fase 7: Pantalla de Análisis de Rutas :f2, after f1, 3d

    section Pruebas y Despliegue
        Validación E2E :t1, after f2, 2d
        Despliegue :t2, after t1, 1d
```

---

## 3. Fases Detalladas del Plan

### **FASE 1: Estructura de Datos (Backend)**

**Objetivo:** Asegurar que el esquema de la base de datos soporte todos los requerimientos del pipeline.

| Tarea | Descripción | Estado Actual | Artefactos |
| :--- | :--- | :--- | :--- |
| **1.1. Validar Consolidación Básica** | Ejecutar el script `SIMPLE_LPI_MIGRATION.sql` para confirmar que la consolidación con LPI y ONE DB funciona. | ❌ Pendiente | `SIMPLE_LPI_MIGRATION.sql` |
| **1.2. Añadir Campos Faltantes** | Añadir `carrier_id`, `product_id`, `origin/destination_city_name` a `processed_events`. | ❌ Pendiente | Nueva migración SQL |
| **1.3. Añadir Campos de Tiempo Dual** | Añadir `natural_time` y `working_time` a `journey_segments`. | ✅ Completado | `20260214_add_dual_time_tracking.sql` |
| **1.4. Crear Tabla `journey_paths`** | Crear la nueva tabla para almacenar las rutas agregadas. | ❌ Pendiente | Nueva migración SQL |

**Criterio de Aceptación:** Todas las migraciones SQL se ejecutan sin errores y el esquema de la base de datos está completo.

---

### **FASE 2: Consolidación Avanzada (Backend)**

**Objetivo:** Actualizar la función de consolidación para que enriquezca los eventos con todos los datos de negocio necesarios.

| Tarea | Descripción | Estado Actual | Artefactos |
| :--- | :--- | :--- | :--- |
| **2.1. Integrar Lookup en ONE DB** | Modificar `consolidate_rfid_events()` para que busque en `one_db` por `tag_id`. | ❌ Pendiente | `consolidate_rfid_events.sql` |
| **2.2. Propagar Datos a `processed_events`** | Asegurar que los datos de `one_db` (carrier, product, origin, destination) se inserten correctamente en `processed_events`. | ❌ Pendiente | `consolidate_rfid_events.sql` |
| **2.3. Unificar Lógica LPI** | Asegurar que se utiliza la versión más reciente de la función que trabaja con LPI de forma nativa. | ⚠️ Parcial | `consolidate_rfid_events.sql` |

**Criterio de Aceptación:** La función `consolidate_rfid_events()` enriquece un evento raw con todos los datos de `one_db` y lo inserta correctamente en `processed_events`.

---

### **FASE 3: Construcción de Segmentos (Backend)**

**Objetivo:** Implementar la lógica completa para construir segmentos de viaje a partir de los eventos procesados.

| Tarea | Descripción | Estado Actual | Artefactos |
| :--- | :--- | :--- | :--- |
| **3.1. Crear/Actualizar `build_journey_segments()`** | Crear o modificar la función que procesa `processed_events` y crea `journey_segments`. | ⚠️ Parcial | `build_journey_segments.sql` |
| **3.2. Propagar Campos Completos** | Asegurar que `carrier_id`, `product_id`, `origin/destination` se propaguen a `journey_segments`. | ❌ Pendiente | `build_journey_segments.sql` |
| **3.3. Implementar Cálculo de Tiempo Dual** | Calcular y guardar `natural_time` y `working_time` para `time_in_center` y `transit_time`. | ❌ Pendiente | `build_journey_segments.sql` |
| **3.4. Integrar Lookup de SLA** | Buscar el SLA correspondiente en `delivery_standards` y calcular `sla_compliance`. | ❌ Pendiente | `build_journey_segments.sql` |

**Criterio de Aceptación:** La función `build_journey_segments()` genera correctamente los segmentos operacionales y de tránsito con todos los campos de tiempo y SLA calculados.

---

### **FASE 4: Agregación de Rutas (Backend)**

**Objetivo:** Crear la capa de agregación para análisis de rendimiento.

| Tarea | Descripción | Estado Actual | Artefactos |
| :--- | :--- | :--- | :--- |
| **4.1. Crear `aggregate_journey_paths()`** | Crear la nueva función que agrupa `journey_segments` por `path_signature`. | ❌ Pendiente | `aggregate_journey_paths.sql` |
| **4.2. Calcular Métricas Agregadas** | Calcular `total_tags`, `avg_time`, `compliance_rate` para cada ruta única. | ❌ Pendiente | `aggregate_journey_paths.sql` |
| **4.3. Poblar `journey_paths`** | Insertar los resultados agregados en la tabla `journey_paths`. | ❌ Pendiente | `aggregate_journey_paths.sql` |

**Criterio de Aceptación:** La función `aggregate_journey_paths()` genera un resumen preciso de las rutas y su rendimiento en la tabla `journey_paths`.

---

### **FASE 5: APIs (Backend)**

**Objetivo:** Exponer la lógica del pipeline y los datos agregados a través de endpoints seguros y eficientes.

| Tarea | Descripción | Estado Actual | Artefactos |
| :--- | :--- | :--- | :--- |
| **5.1. Implementar API de Ingesta** | Crear el endpoint `POST /api/epcis/events` para recibir datos del sistema externo. | ❌ Pendiente | `api/epcis.ts` |
| **5.2. Implementar API de Consulta de Rutas** | Crear el endpoint `GET /api/journey-paths` para que el frontend consulte las rutas agregadas. | ❌ Pendiente | `api/journeys.ts` |
| **5.3. Implementar APIs de Ejecución Manual** | Crear las funciones RPC (`run_consolidation_phase`, etc.) para la pantalla de monitorización. | ❌ Pendiente | `rpc/pipeline.sql` |

**Criterio de Aceptación:** Los endpoints de la API responden correctamente, con la autenticación y autorización adecuadas, y devuelven los datos en el formato esperado.

---

### **FASE 6: Pantalla de Monitorización (Frontend)**

**Objetivo:** Proporcionar una interfaz para monitorizar y controlar el pipeline.

| Tarea | Descripción | Estado Actual | Artefactos |
| :--- | :--- | :--- | :--- |
| **6.1. Crear Componente `PipelineMonitor`** | Desarrollar la nueva página en `/diagnosis/pipeline-monitor`. | ❌ Pendiente | `PipelineMonitor.tsx` |
| **6.2. Implementar Vista de Fases** | Crear las tarjetas de estado para cada una de las 4 fases. | ❌ Pendiente | `PhaseCard.tsx` |
| **6.3. Implementar Log de Ejecución** | Añadir la consola de logs en tiempo real. | ❌ Pendiente | `ExecutionLog.tsx` |
| **6.4. Conectar con APIs de Ejecución** | Vincular los botones "Run Now" a las funciones RPC del backend. | ❌ Pendiente | `PipelineMonitor.tsx` |
| **6.5. Añadir a Navegación** | Incluir un enlace a la nueva pantalla en el menú de Diagnóstico. | ❌ Pendiente | `Sidebar.tsx` |

**Criterio de Aceptación:** La pantalla de monitorización muestra el estado correcto del pipeline, permite la ejecución manual de cada fase y proporciona feedback claro al usuario.

---

### **FASE 7: Pantalla de Análisis de Rutas (Frontend)**

**Objetivo:** Visualizar los datos de `journey_paths` para el análisis de rendimiento.

| Tarea | Descripción | Estado Actual | Artefactos |
| :--- | :--- | :--- | :--- |
| **7.1. Crear Componente `RouteAnalysis`** | Desarrollar la nueva página en `/diagnosis/route-analysis`. | ❌ Pendiente | `RouteAnalysis.tsx` |
| **7.2. Implementar Mapa de Flujos** | Integrar una librería de mapas (D3, Mapbox) para visualizar los flujos de rutas. | ❌ Pendiente | `FlowMap.tsx` |
| **7.3. Implementar Tabla de Rutas** | Crear la tabla colapsable que muestra las rutas y sus segmentos. | ❌ Pendiente | `RoutesTable.tsx` |
| **7.4. Conectar con API de Consulta** | Vincular los filtros de la página al endpoint `GET /api/journey-paths`. | ❌ Pendiente | `RouteAnalysis.tsx` |

**Criterio de Aceptación:** La pantalla de análisis muestra correctamente las rutas en el mapa y la tabla, y permite la interacción del usuario (hover, click) para explorar los datos.
