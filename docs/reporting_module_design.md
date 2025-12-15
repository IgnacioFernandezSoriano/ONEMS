# Módulo de Reporting E2E - ONE MS
## Diseño y Especificaciones Técnicas

**Versión:** 1.0  
**Fecha:** 2025-12-11  
**Basado en:** Especificaciones de informes regulatorios v2

---

## 1. Resumen Ejecutivo

El módulo de Reporting E2E proporciona al regulador postal una herramienta integral para supervisar la calidad del servicio postal universal mediante mediciones end-to-end. El sistema transforma datos masivos de la tabla `one_db` en inteligencia accionable a través de cuatro vistas interconectadas que siguen una **pirámide de investigación**: visión panorámica → verificación de cumplimiento → diagnóstico granular → análisis de caso individual.

---

## 2. Arquitectura del Sistema de Reporting

### 2.1. Fuente de Datos Principal

**Tabla:** `one_db` (ya implementada)

**Campos clave disponibles:**
- `tag_id` - Identificador único del envío
- `account_id` - Tenant (operador postal)
- `plan_name` - Plan de medición
- `carrier_name` - Transportista
- `product_name` - Producto postal
- `origin_city_name` - Ciudad origen
- `destination_city_name` - Ciudad destino
- `sent_at` - Fecha/hora de envío
- `received_at` - Fecha/hora de recepción
- `total_transit_days` - Días totales de tránsito
- `business_transit_days` - Días hábiles de tránsito
- `on_time_delivery` - Cumplimiento (boolean)
- `source_data_snapshot` - JSONB con datos originales completos

### 2.2. Datos Complementarios Necesarios

**Delivery Standards (Tiempos Estándar):**
- Tabla: `products`
- Campo: `standard_delivery_hours` + `time_unit`
- Uso: Calcular % de cumplimiento y clasificar retrasos

**Clasificación de Rutas:**
- Origen: `cities` → tipo de ciudad (Capital/Mayor/Menor)
- Destino: `cities` → tipo de ciudad
- Uso: Análisis por clasificación de destino

**Información Geográfica:**
- Tabla: `cities`
- Campos: `name`, `region_id` (si existe), coordenadas (si existen)
- Uso: Agrupación por regiones/departamentos

---

## 3. Las 4 Vistas del Sistema de Reporting

### Vista 1: Dashboard de Desempeño General
**Objetivo:** Visión panorámica del estado del servicio postal

**Componentes:**

1. **KPIs Principales (Cards superiores)**
   - % Cumplimiento General
   - Promedio Días Hábiles
   - Total Envíos Medidos
   - Tendencia vs Mes Anterior (↑↓)

2. **Gráfico de Líneas Dual (Temporal Integrado)**
   - Eje X: Tiempo (semanal/mensual/trimestral)
   - Eje Y izquierdo: % Cumplimiento (línea azul)
   - Eje Y derecho: Promedio Días Hábiles (línea naranja)
   - **Reemplaza el mapa regional del documento original**

3. **Distribución por Carrier/Producto**
   - Gráfico de barras horizontales
   - Top 5 carriers por volumen
   - % cumplimiento por cada uno

4. **Filtros Globales**
   - Rango de fechas
   - Carrier
   - Producto
   - Tipo de ruta (Capital-Capital, Capital-Menor, etc.)

**Pregunta que responde:** *"¿Está mejorando el desempeño general a lo largo del tiempo?"*

---

### Vista 2: Informe de Cumplimiento Normativo
**Objetivo:** Verificación legal de cumplimiento de estándares

**Componentes:**

1. **Tabla de Cumplimiento por Clasificación**
   - Columnas:
     - Clasificación (Capital-Capital, Capital-Mayor, etc.)
     - Cantidad de Envíos
     - % Cumplimiento
     - Promedio Días Hábiles
     - Máximo Días Registrado
     - Tendencia (↑↓ vs período anterior)
   - **Filas clicables** → navega a Vista 3 filtrando por esa clasificación

2. **Indicadores de Alerta**
   - Clasificaciones con cumplimiento < 85% (rojo)
   - Clasificaciones con cumplimiento 85-95% (amarillo)
   - Clasificaciones con cumplimiento > 95% (verde)

3. **Comparativa con Estándar Legal**
   - Gráfico de barras comparando:
     - Tiempo estándar legal (D+X)
     - Tiempo promedio real
   - Por clasificación de ruta

**Pregunta que responde:** *"¿Está el operador cumpliendo con los estándares legales?"*

---

### Vista 3: Desglose por Localidad (Diagnóstico Granular)
**Objetivo:** Identificar focos problemáticos geográficos

**Componentes:**

1. **Tabla Interactiva de Localidades**
   - Columnas:
     - Localidad (ciudad destino)
     - Clasificación (Capital/Mayor/Menor)
     - Cantidad de Envíos
     - % Cumplimiento
     - Promedio Días Hábiles
     - Máximo Días Registrado
   - **Ordenable por cualquier columna**
   - **Búsqueda por nombre de localidad**
   - **Filas clicables** → navega a Vista 4 mostrando envíos a esa localidad

2. **Visualización Alternativa al Mapa:**
   - **Opción A: Treemap Jerárquico**
     - Bloques proporcionales al volumen de envíos
     - Color según % cumplimiento (verde → amarillo → rojo)
     - Agrupados por región/departamento
   
   - **Opción B: Heatmap Tabular**
     - Filas: Ciudades origen
     - Columnas: Ciudades destino
     - Color de celda: % cumplimiento de esa ruta
     - Intensidad: volumen de envíos

3. **Columnas Adicionales de Contexto**
   - Cantidad de Envíos (robustez estadística)
   - Promedio Días Hábiles
   - Máximo Días Registrado

**Pregunta que responde:** *"¿Qué localidades tienen problemas sistemáticos?"*

---

### Vista 4: Trazabilidad de Envío Individual
**Objetivo:** Análisis forense de casos específicos

**Componentes:**

1. **Información del Envío**
   - Tag ID
   - Plan de medición
   - Carrier / Producto
   - Origen → Destino
   - Tiempo estándar vs tiempo real

2. **Línea de Tiempo Visual Horizontal**
   - Puntos en la línea:
     - Fecha programada
     - Fecha de envío (sent_at)
     - Fecha de recepción (received_at)
   - Segmentos coloreados:
     - Verde: dentro del estándar
     - Rojo: retraso
   - Tooltip al pasar el ratón: detalles de cada evento

3. **Tabla de Eventos (del source_data_snapshot)**
   - Fecha/Hora
   - Evento (descripción legible)
   - Ubicación (nodo/ciudad)
   - Duración desde evento anterior
   - Información adicional (panelista, etc.)

4. **Cálculo Automático de Tiempos de Tránsito**
   - Duración total
   - Duración por fase (si hay eventos intermedios)
   - Identificación de cuellos de botella

**Pregunta que responde:** *"¿Por qué este envío específico se retrasó?"*

---

## 4. Flujo de Navegación (Pirámide de Investigación)

```
Vista 1: Dashboard General
    ↓ (click en período/carrier)
Vista 2: Informe de Cumplimiento
    ↓ (click en clasificación con problema)
Vista 3: Desglose por Localidad
    ↓ (click en localidad específica)
Vista 4: Trazabilidad Individual
```

**Lógica:** Comenzar amplio → identificar anomalías → profundizar en causas → analizar casos específicos.

---

## 5. Requerimientos Técnicos

### 5.1. Vistas SQL Necesarias

**Vista 1: `v_reporting_general_performance`**
```sql
-- Agregación temporal de KPIs generales
-- GROUP BY: date_trunc('week/month', sent_at), carrier_name, product_name
-- Métricas: COUNT(*), AVG(business_transit_days), 
--           SUM(CASE WHEN on_time_delivery THEN 1 ELSE 0 END)::float / COUNT(*)
```

**Vista 2: `v_reporting_compliance_by_classification`**
```sql
-- Agregación por clasificación de ruta (origen-destino)
-- JOIN con cities para obtener tipo de ciudad
-- GROUP BY: route_classification
-- Métricas: cumplimiento, promedio, máximo, cantidad
```

**Vista 3: `v_reporting_by_locality`**
```sql
-- Agregación por ciudad destino
-- GROUP BY: destination_city_name, city_classification
-- Métricas: cumplimiento, promedio, máximo, cantidad
-- Ordenable y filtrable
```

**Vista 4: `v_reporting_individual_tracking`**
```sql
-- Detalle completo de un envío específico
-- WHERE: tag_id = ?
-- Incluye: todos los campos + source_data_snapshot expandido
```

### 5.2. Funciones SQL Auxiliares

**Función: `classify_route(origin_city_id, destination_city_id)`**
- Retorna: 'Capital-Capital', 'Capital-Mayor', 'Mayor-Menor', etc.
- Uso: Clasificar rutas para análisis

**Función: `calculate_compliance_percentage(account_id, date_from, date_to, filters)`**
- Retorna: % de cumplimiento
- Uso: KPIs dinámicos

### 5.3. Campos Adicionales Necesarios en `cities`

**Campo:** `city_type` (ENUM: 'capital', 'major', 'minor')
- **Propósito:** Clasificar rutas para análisis de cumplimiento
- **Migración necesaria:** Sí

**Campo:** `region_name` o `region_id`
- **Propósito:** Agrupación geográfica para visualizaciones
- **Migración necesaria:** Sí (si no existe)

---

## 6. Pantalla de Configuración de Cuenta (Superadmin)

**¿Es necesaria?** **SÍ**

**Propósito:**
- Definir clasificación de ciudades (Capital/Mayor/Menor) por cuenta
- Configurar regiones/departamentos personalizados
- Establecer umbrales de alerta personalizados (ej. 85% vs 90%)
- Definir períodos de reporte (semanal, mensual, trimestral)

**Ubicación:** Settings → Account Configuration (solo superadmin)

**Campos:**
- `compliance_threshold_warning` (default: 85%)
- `compliance_threshold_critical` (default: 75%)
- `default_report_period` (week/month/quarter)
- Tabla de clasificación de ciudades por cuenta

---

## 7. Integración con IA (Fase Futura - NO IMPLEMENTAR AHORA)

### 7.1. Capacidades Potenciales

**Detección de Anomalías:**
- Identificar patrones inusuales (ej. retraso súbito en una ruta específica)
- Alertas automáticas cuando métricas caen fuera de rangos históricos

**Análisis de Tendencias:**
- Predicción de cumplimiento futuro basado en datos históricos
- Identificación de estacionalidad (ej. diciembre siempre tiene más retrasos)

**Consejos de Mejora:**
- "El 60% de los retrasos ocurren en la ruta Madrid-Barcelona los viernes"
- "Aumentar capacidad en el nodo X reduciría retrasos en un 20%"

**Generación Automática de Informes:**
- Resumen ejecutivo en lenguaje natural
- Comparativas automáticas con períodos anteriores

### 7.2. Implementación Técnica Sugerida

**API a utilizar:** OpenAI GPT-4 o Manus AI API

**Enfoque:**
1. Crear endpoint `/api/reporting/ai-insights`
2. Pasar datos agregados + contexto histórico
3. Prompt estructurado para análisis específico
4. Retornar insights en formato JSON
5. Mostrar en panel lateral del dashboard

**Enriquecimiento de informes:**
- Sección "Insights de IA" en cada vista
- Explicaciones automáticas de métricas
- Recomendaciones accionables

**Ejemplo de prompt:**
```
Analiza estos datos de calidad postal:
- Cumplimiento actual: 87%
- Cumplimiento mes anterior: 92%
- Ruta más problemática: Madrid-Barcelona (65% cumplimiento)
- Volumen: 10,000 envíos

Proporciona:
1. Diagnóstico de la caída de 5 puntos
2. Análisis de la ruta problemática
3. 3 recomendaciones accionables
```

---

## 8. Orden Lógico de Implementación

### Fase 1: Estructura de Datos (Semana 1)
1. Migración: Agregar `city_type` a tabla `cities`
2. Migración: Agregar `region_name` a tabla `cities`
3. Crear función `classify_route()`
4. Crear vistas SQL (v_reporting_*)
5. Poblar clasificación de ciudades para cuenta DEMO2

### Fase 2: Vista 1 - Dashboard General (Semana 2)
1. Crear componente `ReportingDashboard.tsx`
2. Hook `useReportingGeneral.ts`
3. Gráfico de líneas dual (Chart.js/Recharts)
4. KPIs cards
5. Filtros globales

### Fase 3: Vista 2 - Cumplimiento Normativo (Semana 3)
1. Crear componente `ComplianceReport.tsx`
2. Hook `useComplianceData.ts`
3. Tabla interactiva con indicadores de alerta
4. Gráfico comparativo con estándar legal
5. Navegación a Vista 3

### Fase 4: Vista 3 - Desglose por Localidad (Semana 4)
1. Crear componente `LocalityBreakdown.tsx`
2. Hook `useLocalityData.ts`
3. Tabla ordenable y buscable
4. Treemap o Heatmap (elegir una opción)
5. Navegación a Vista 4

### Fase 5: Vista 4 - Trazabilidad Individual (Semana 5)
1. Crear componente `ShipmentTracking.tsx`
2. Hook `useShipmentDetails.ts`
3. Línea de tiempo visual
4. Tabla de eventos
5. Cálculo automático de tiempos

### Fase 6: Configuración de Cuenta (Semana 6)
1. Crear pantalla superadmin
2. CRUD de clasificación de ciudades
3. Configuración de umbrales
4. Validación y persistencia

### Fase 7: Integración y Testing (Semana 7)
1. Flujo de navegación completo
2. Testing con datos reales
3. Optimización de queries
4. Documentación de usuario

---

## 9. Beneficios para el Regulador

### 9.1. Mayor Capacidad de Fiscalización
- Supervisar el 100% de los envíos, no solo una muestra
- Datos verificables y trazables

### 9.2. Decisiones Basadas en Evidencia
- Todas las acciones (sanciones, recomendaciones) respaldadas por datos
- Informes reproducibles y auditables

### 9.3. Eficiencia Operativa
- Reducir tiempo de identificación de problemas
- Flujo de investigación intuitivo (pirámide)

### 9.4. Legitimidad y Transparencia
- Informes objetivos y publicables
- Demostrar calidad del servicio postal a la ciudadanía

### 9.5. Mejora Continua
- Evaluar impacto de intervenciones regulatorias
- Ajustar estrategia en consecuencia

---

## 10. Próximos Pasos

1. **Revisar y aprobar este diseño**
2. **Decidir sobre visualización alternativa al mapa** (Treemap vs Heatmap)
3. **Confirmar estructura de regiones/departamentos** (¿existe ya en la BD?)
4. **Iniciar Fase 1: Migraciones de base de datos**
5. **Definir paleta de colores y diseño UI** (seguir diseño actual de ONE MS)

---

**Documento preparado por:** Manus AI  
**Para:** ONE MS - Módulo de Reporting E2E  
**Próxima revisión:** Tras aprobación del usuario
