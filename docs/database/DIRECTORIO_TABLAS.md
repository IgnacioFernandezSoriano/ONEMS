# Directorio de Tablas — ONEMS (Supabase `onems-dev`)

> **Propósito:** Mapa de conocimiento de las **60 tablas** del esquema `public`, agrupadas por proceso de negocio, para entender para qué sirve cada una.
> **Proyecto:** `onems-dev` (`sehbnpgzqljrsqimwyuz`, eu-central-2) · PostgreSQL 17.6
> **Generado:** 2026-06-09 · A partir de los comentarios de tabla, las claves foráneas reales y el código de las Edge Functions.

## Conceptos transversales

- **Multi-tenancy:** Casi todas las tablas cuelgan de `accounts` mediante `account_id`. Cada cuenta = una organización con datos aislados (RLS).
- **Trazabilidad:** Muchas tablas tienen `created_by` / `updated_by` → `profiles` (usuario), y timestamps.
- **Dos jerarquías maestras:**
  - **Topología de red:** `regions` → `cities` → `nodes`
  - **Catálogo logístico:** `carriers` → `products` → `materials`

---

## 1. Núcleo: Cuentas, usuarios y API

Identidad, multi-tenancy y acceso externo.

| Tabla | Para qué sirve |
|---|---|
| `accounts` | **Tabla raíz.** Cuentas de inquilinos (multi-tenancy). Todo lo demás referencia `account_id`. |
| `profiles` | Perfil extendido del usuario, ligado a `auth.users`. Guarda `role` y `account_id`. Superadmin → `account_id` NULL. |
| `account_config` | Configuración global por cuenta para el módulo de diagnóstico. |
| `api_keys` | Claves API (hasheadas) para integraciones externas (p.ej. n8n). Estados: active/revoked/expired. |
| `api_usage_log` | Auditoría de cada llamada hecha con una API key (endpoint, método, status, IP, tiempo de respuesta). |

---

## 2. Topología de red (geografía y nodos)

Estructura física donde se mueven los envíos. Jerarquía: **Región → Ciudad → Nodo**.

| Tabla | Para qué sirve |
|---|---|
| `regions` | Regiones geográficas (nivel superior). Único: `(account_id, code)`. |
| `cities` | Ciudades dentro de regiones. Incluye lat/long. Único: `(region_id, code)`. |
| `nodes` | Nodos de red (almacenes, centros de distribución, puntos de acceso). Tipos: core/edge/access. `auto_id` con formato `REGION-CITY-NNN`. |
| `node_balancing_history` | Historial de operaciones de balanceo de carga entre nodos de una ciudad. |
| `delivery_standards` | Estándares de entrega entre pares de ciudades: horas estándar, tasa de éxito, distancia km. Usado para optimización de rutas. |

---

## 3. Catálogo logístico (transportistas, productos, materiales)

Qué se distribuye. Jerarquía: **Transportista → Producto → Material**.

| Tabla | Para qué sirve |
|---|---|
| `carriers` | Transportistas / proveedores de envío (nivel superior). Único: `(account_id, code)`. |
| `products` | Productos/servicios que ofrece cada transportista. Tiene `standard_delivery_hours`. Único: `(carrier_id, code)`. |
| `materials` | Materiales individuales asociados a un producto (nivel más bajo). Único: `(product_id, code)`. |
| `material_catalog` | **Catálogo maestro** de materiales reutilizables, independiente de productos concretos. |
| `product_materials` | Tabla de unión N:M producto ↔ material de catálogo, con `quantity` requerida por unidad. |

---

## 4. Centros postales e infraestructura RFID

Centros físicos donde se leen los tags y su configuración operativa.

| Tabla | Para qué sirve |
|---|---|
| `postal_centers` | Centros postales con configuración operativa y de cálculo. |
| `postal_center_carriers` | Unión N:M: qué transportistas operan en cada centro postal. |
| `readers` | Lectores RFID instalados en centros postales. |
| `reader_location_history` | Historial de asignación de lectores a centros (permite lectores móviles/temporales). |
| `non_working_days` | Días no laborables (festivos). `postal_center_id` NULL = festivo a nivel de cuenta. |
| `weekly_schedule` | Horarios semanales. `postal_center_id` NULL = horario a nivel de cuenta. |

---

## 5. Panelistas

Personas (conductores/personal de entrega) asignadas a nodos que manejan los envíos.

| Tabla | Para qué sirve |
|---|---|
| `panelists` | Panelistas asignados a un nodo/ciudad. Datos de contacto y dirección. |
| `panelist_unavailability` | Períodos de indisponibilidad (vacaciones, baja, entrenamiento). Usado en planificación. |
| `panelist_context` | Contexto adicional asociado a panelistas. |
| `panelist_material_stocks` | Stock de materiales que tiene cada panelista. |

---

## 6. Planificación de asignaciones (Allocation Plans)

Núcleo de planificación de envíos. **Flujo: borrador → aplicado (histórico).**

| Tabla | Para qué sirve |
|---|---|
| `generated_allocation_plans` | Planes **generados (borradores)**. Estados: draft/pending/applied. |
| `generated_allocation_plan_details` | Detalle de cada envío programado del borrador (origen/destino, fecha, semana/mes/año). |
| `allocation_plans` | Planes **aplicados/confirmados (histórico)**. Estados: active/completed/archived. Campo clave: `applied_date`. |
| `allocation_plan_details` | Detalle de envíos reales con seguimiento de estado: pending/sent/delivered/cancelled. Soporta reasignación de nodos. |
| `material_requirements_periods` | Necesidades de material calculadas a partir de los planes para periodos concretos. |
| `shipment_incident` | Incidencias asociadas a un envío concreto (`parcel_id` → `allocation_plan_details`) y panelista. |

> **Flujo de aplicación:** al "aplicar" un plan, `generated_allocation_plan_details` se copia a `allocation_plan_details`, y el plan generado pasa a `status=applied`.

---

## 7. Gestión de stock / inventario

Control de existencias de materiales (preparado para flujo de compras y envíos).

| Tabla | Para qué sirve |
|---|---|
| `material_stocks` | Stock de materiales en el almacén del regulador. |
| `material_movements` | Historial de movimientos de stock (auditoría). |
| `stock_settings` | Configuración del sistema de control de stock por cuenta. |
| `stock_alerts` | Alertas de stock (p.ej. por debajo de mínimo). |
| `material_shipments` | Envíos de materiales a panelistas *(preparada para futuro)*. |
| `material_shipment_items` | Líneas de cada envío de material a panelistas. |
| `purchase_orders` | Órdenes de compra de materiales *(preparada para futuro)*. |
| `purchase_order_items` | Líneas de cada orden de compra. |

---

## 8. Ingesta y diagnóstico RFID (Network Diagnostics)

> **Este es el pipeline central de medición.** Lo confirma la Edge Function `process-rfid-events`:
> `rfid_intermediate_db` (eventos crudos) → agrupa por `tag_id` → deduplica y parte rutas → genera `diagnosis_routes`, `diagnosis_time_metrics` y `diagnosis_anomalies`.

| Tabla | Para qué sirve |
|---|---|
| `rfid_intermediate_db` | **Entrada del pipeline.** Eventos EPCIS crudos ingeridos (`tag_id`, `reader_id`, `read_local_date_time`, `processed_at`). La función `generate-epcis-data` los puede generar para pruebas. |
| `rfid_events_raw` | Eventos RFID crudos (variante con FK a carrier/product). |
| `audit_raw_reads` | Log de auditoría de lecturas crudas consolidadas (RLS activo). |
| `processed_events` | Eventos RFID **consolidados** tras procesar la DB intermedia. Enlaza a centro postal, lector, carrier, product. |
| `diagnosis_routes` | **Ruta reconstruida** por tag: inicio/fin, duración total, secuencia de lectores, nº de eventos, completa o no. |
| `diagnosis_time_metrics` | Métricas de tiempo por segmento (lector→lector): duración, esperado, retraso. |
| `diagnosis_anomalies` | Anomalías detectadas: `missing_reading`, `excessive_delay`, `duplicate_reading`, `out_of_sequence` (severidad low→critical). |

### Journeys (capa agregada de trayectos)

| Tabla | Para qué sirve |
|---|---|
| `journeys` | Trayectos completos reconstruidos por tag con métricas agregadas. |
| `journey_segments` | Segmentos calculados: operativos (dentro de un centro) y de distribución (entre centros). Enlaza eventos de entrada/salida y SLA. |
| `journey_paths` | Datos agregados de rendimiento por ruta para análisis. |

### SLAs e incidencias

| Tabla | Para qué sirve |
|---|---|
| `slas` | SLAs de diagnóstico de red: tiempos esperados para rutas operativas (Entrada→Salida en centro) y de distribución (entre centros). |
| `sla_definitions` | Definiciones de SLA entre pares de centros postales. |
| `incidents` | Anomalías, problemas de calidad de datos y violaciones de SLA detectadas (enlaza a evento, segmento, lector, centro). |
| `reporting_config` | Configuración del módulo de reporting por cuenta (umbrales, preferencias). |

---

## 9. Calidad postal end-to-end

| Tabla | Para qué sirve |
|---|---|
| `one_db` | Registros **validados** de medición de calidad postal para analítica end-to-end. Enlaza a `allocation_plan_details`. (Expuesta vía la Edge Function `onedb-api`.) |

---

## 10. Integración n8n

Tablas de staging para flujos de automatización en n8n (agente UPU).

| Tabla | Para qué sirve |
|---|---|
| `n8n_upu_agent` | Datos del agente UPU gestionados desde n8n. |
| `n8n_upu_incident` | Incidencias capturadas vía n8n. |
| `n8n_upu_timeoff` | Ausencias/time-off vía n8n. |

---

## 11. Datos de demostración

| Tabla | Para qué sirve |
|---|---|
| `demo2_seed_data` | Datos semilla de DEMO2 para reseteo automático del entorno de demo. |

---

## Edge Functions (contexto del pipeline)

| Función | Qué hace | Tablas que toca |
|---|---|---|
| `process-rfid-events` | Consolida eventos RFID por tag, deduplica, parte rutas (gap >24h), calcula métricas y detecta anomalías. | lee `rfid_intermediate_db`; escribe `diagnosis_routes`, `diagnosis_time_metrics`, `diagnosis_anomalies` |
| `generate-epcis-data` | Genera eventos EPCIS sintéticos para pruebas (solo admin/superadmin). | inserta en `rfid_intermediate_db` |
| `onedb-api` | API externa sobre los datos de calidad postal. | `one_db` (+ auth vía `api_keys`) |
| `admin-reset-password` | Reseteo administrativo de contraseñas de usuarios. | `auth.users` / `profiles` |

---

## Mapa de dependencias (resumen)

```
accounts (raíz)
├── profiles ── (created_by/updated_by en casi todas)
├── regions → cities → nodes → panelists
├── carriers → products → materials
│              └── product_materials ← material_catalog
├── postal_centers → readers → processed_events
│       └── slas / sla_definitions / journey_segments
├── generated_allocation_plans → generated_allocation_plan_details
│       └── (al aplicar) → allocation_plans → allocation_plan_details → one_db
└── rfid_intermediate_db → [process-rfid-events] → diagnosis_routes
                                                  → diagnosis_time_metrics
                                                  → diagnosis_anomalies
```

---

*Documento generado por inspección directa de la base de datos vía MCP. Para regenerarlo, volver a consultar `pg_class` (comentarios) + claves foráneas + Edge Functions.*
