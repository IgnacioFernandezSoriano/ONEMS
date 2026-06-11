# ETL de la "RFID Events Database" — Documento Técnico

> **Qué es esto:** descripción técnica completa y actualizada del proceso ETL que **carga, transforma y agrega** las lecturas RFID en ONEMS, desde su origen hasta las tablas finales de análisis.
> **Tabla central:** `rfid_events_raw` (la UI la muestra como **"RFID Events Database"**, menú `menu.rfid_events_database`).
> **Proyecto:** Supabase `onems-dev` (`sehbnpgzqljrsqimwyuz`, eu-central-2) · PostgreSQL 17.6
> **Generado:** 2026-06-10 · A partir del código real de las funciones SQL, las Edge Functions, el cron (`cron.job`) y el frontend.
> **Documento complementario:** [ETL_RFID_MANUAL_USUARIO.md](ETL_RFID_MANUAL_USUARIO.md) (manual de usuario master).

---

## 1. Visión general

El ETL convierte **lecturas RFID en crudo** (un tag leído por un lector en un instante) en **trayectos medibles y rutas agregadas** con cumplimiento de SLA. Se ejecuta **automáticamente cada 15 minutos** mediante un cron de Postgres (`pg_cron`), procesando todas las cuentas (multi-tenant).

```
                                  ┌─────────────────────────────────────────────┐
   FUENTES DE DATOS               │            PIPELINE ETL (cron 15 min)        │           SALIDA
 ───────────────────              └─────────────────────────────────────────────┘      ──────────────

  API externa (RFID provider)
  REST rpc_ingest_epcis_events   ┌──────────────┐  Fase 1   ┌─────────────────┐  Fase 2   ┌──────────────────┐
  Generadores demo (.mjs/.py) ──▶│ rfid_events_ │ ────────▶ │ processed_events│ ────────▶ │ journey_segments │
                                 │ raw          │ consolidar│ (enriquecido)   │reconstruir│ (segmentos)      │
                                 │ "RFID Events │           └─────────────────┘ trayectos └──────────────────┘
                                 │  Database"   │                                                  │
                                 └──────────────┘                                          Fase 3 │ ensamblar
                                        │                                                          ▼
                                        │ archive_raw_events                            ┌──────────────────┐
                                        ▼                                               │     journeys     │
                                 ┌──────────────┐                                       │ (1 por tag)      │
                                 │audit_raw_reads│                                      └──────────────────┘
                                 └──────────────┘                                                  │
                                                                                          Fase 4 │ agregar
                                  Incidencias (tags/lectores                                       ▼
                                  desconocidos, etc.) ──▶ incidents             ┌──────────────────┐
                                                                                │   journey_paths  │
                                                                                │ (1 por ruta única)│
                                                                                └──────────────────┘
```

> ⚠️ **Existen dos arquitecturas RFID en la base de datos.** La **productiva y actual** es la descrita arriba (`rfid_events_raw → processed_events → journey_segments → journeys / journey_paths`, vía funciones SQL + cron). Hay además una **vía paralela/heredada** basada en la tabla `rfid_intermediate_db` y la Edge Function `process-rfid-events`, que produce las tablas `diagnosis_*`. Ver [§8](#8-vía-heredada-edge-functions-y-rfid_intermediate_db).

---

## 2. Fuentes de datos (de dónde salen los datos)

Todo entra por la tabla **`rfid_events_raw`**. Hoy hay tres orígenes posibles:

| # | Origen | Mecanismo | Estado |
|---|---|---|---|
| 1 | **Proveedor RFID externo (AWS)** | Edge Function `rfid-provider-poll` (cron 30 min) hace **polling incremental** (cursor) → landing `rfid_provider_reads` → `resolve_provider_reads()` normaliza tag y resuelve cuenta → `rfid_events_raw`. Encadena el ETL tras capturar. | **Implementado** (ver `docs/superpowers/specs/2026-06-11-rfid-aws-ingestion-design.md`). Bypassa la `rpc_ingest_epcis_events` heredada (§7 #1). |
| 2 | **API REST de ingesta** | `POST /rest/v1/rpc/rpc_ingest_epcis_events` con `Authorization: Bearer <JWT>`. | Implementada (con salvedades, ver [§7](#7-observaciones-e-inconsistencias-a-verificar)) |
| 3 | **Generadores de datos demo** | Scripts `generate_*_demo.mjs` y `scripts/generate_synthetic_events.py` insertan lotes directamente. | Solo entornos demo/test |

### 2.1. Contrato del registro de origen (proveedor externo)

Cada lectura del proveedor tiene esta forma (ver requisitos de integración):

```json
{
  "id":        "1a66a44f-c905-4ac4-a8b0-3d1811ef86f0",
  "location":  "Brazil | Aparecida de Goiânia | CTCE Goiania | GO",
  "readerId":  "J11DBRA02100000319",
  "tagId":     "urn:oid:1.0.15961.14.B.A00122245737",
  "timestamp": "2024-05-07T09:53:06.238-03:00"
}
```

- `id` (UUID): identificador único → usado para **idempotencia/de-duplicación** en el polling.
- `readerId`: se almacena como **LPI** (identificador lógico del lector físico), clave de cruce con `readers.reader_id`.
- `tagId`: EPC del paquete → clave de cruce con `one_db.tag_id`.
- `timestamp`: hora local con offset → se guarda como `TIMESTAMPTZ`.

Modelo de polling acordado: incremental con *high-water mark*, idempotente por `id`, con backfill inicial. (Detalle y preguntas abiertas al proveedor: spec de requisitos de integración.)

### 2.2. Contrato de la API REST de ingesta

```http
POST /rest/v1/rpc/rpc_ingest_epcis_events
Content-Type: application/json
Authorization: Bearer YOUR_JWT_TOKEN

{
  "p_events": [
    {
      "TagId": "30B1D226A8240000B000650C",
      "ReaderId": "J11DBRA02100000319",
      "ReadLocalDateTime": "2024-05-07T09:53:06.238-03:30"
    }
  ]
}
```

Función `rpc_ingest_epcis_events(p_events jsonb)`: itera el array e inserta cada evento en `rfid_events_raw` con `is_processed = FALSE`, devolviendo `{success, inserted, failed}`. **Ver salvedades en [§7](#7-observaciones-e-inconsistencias-a-verificar).**

---

## 3. Tablas del pipeline

### 3.1. `rfid_events_raw` — la "RFID Events Database" (entrada)

Lecturas en crudo, sin transformar. Es la **fuente de verdad** y el punto de carga.

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid | PK (`gen_random_uuid()`) |
| `account_id` | uuid | Cuenta propietaria (multi-tenant) |
| `event_id` | text | **NOT NULL, sin default** → quien inserta debe aportarlo |
| `read_local_datetime` | timestamptz | Hora local de la lectura |
| `reader_id` | text | **LPI** del lector |
| `tag_id` | text | EPC del paquete |
| `is_processed` | bool | Flag de control del ETL (default `false`) |
| `created_at` | timestamptz | `now()` |
| `carrier_id`, `product_id` | uuid | Opcionales (enriquecimiento temprano) |

### 3.2. Tablas de salida / intermedias

| Tabla | Rol en el ETL | Generada por |
|---|---|---|
| `processed_events` | **Intermedia.** Eventos consolidados (entry/exit) y enriquecidos con lector, centro, carrier, producto y origen/destino (snapshots). | `consolidate_rfid_events` |
| `journey_segments` | **Intermedia.** Segmentos del trayecto: *operacionales* (dentro de un centro) y de *distribución* (entre centros), con tiempos y cumplimiento SLA. | `reconstruct_journeys` (cron) / `build_journey_segments` (manual) |
| `journeys` | **Final por tag.** Un registro por tag con su `route_path` (JSONB), tiempos totales, nº de centros, estado del trayecto y violaciones de SLA. | `assemble_journeys` |
| `journey_paths` | **Final agregada por ruta.** Una fila por ruta única (firma de ciudades) con medias, desviaciones, tiempo esperado, `compliance_rate` y `% real`. Alimenta dashboards. | `aggregate_journey_paths` |
| `audit_raw_reads` | **Auditoría.** Resumen archivado de lecturas crudas (min/max/conteo) antes de borrarlas de `rfid_events_raw`. | `archive_raw_events` |
| `incidents` | **Calidad/diagnóstico.** Anomalías detectadas durante la consolidación (`unknown_reader`, `unknown_tag`, …). | `consolidate_rfid_events` |

---

## 4. Orquestación y cron

### 4.1. El cron job

```sql
-- En cron.job:
jobid   = 3
jobname = 'rfid-pipeline-every-15min'
schedule= '*/15 * * * *'              -- cada 15 minutos
command = 'SELECT process_all_accounts_pipeline()'
active  = true
```

### 4.2. `process_all_accounts_pipeline()` — orquestador global
`SECURITY DEFINER`. Recorre **todas** las cuentas de `accounts` y, por cada una:

1. Ejecuta `process_rfid_pipeline(account_id)` (fases 1–3) acumulando métricas.
2. Ejecuta `aggregate_journey_paths(account_id)` (fase 4).
3. Aísla errores por cuenta con `EXCEPTION WHEN OTHERS` → si una cuenta falla, registra el error y **continúa** con la siguiente.

Devuelve una fila por cuenta: `events_consolidated, incidents_created, segments_created, events_processed, paths_created, total_execution_time_ms, success, error_message`.

### 4.3. `process_rfid_pipeline(p_account_id)` — pipeline por cuenta
`SECURITY DEFINER`. Tres fases secuenciales, cada una con su propio manejo de error (si una falla, corta y devuelve el error de esa fase):

| Fase | Función llamada | Entrada → Salida |
|---|---|---|
| **1. consolidation** | `consolidate_rfid_events(account)` | `rfid_events_raw` → `processed_events` |
| **2. reconstruction** | `reconstruct_journeys(account)` | `processed_events` → `journey_segments` |
| **3. assembly** | `assemble_journeys(account)` | `journey_segments` → `journeys` |

Devuelve una fila por fase + una fila `summary`.

---

## 5. Lógica de cada fase

### 5.1. Fase 1 — Consolidación: `consolidate_rfid_events(p_account_id)`

Transforma múltiples lecturas crudas de un mismo `(tag, lector)` en **un único evento consolidado** `entry`/`exit`, enriquecido.

**Configuración leída de `accounts`:** `calculation_mode` (default `natural_days`) y `gap_threshold_minutes` (default `30`).

**Por cada combinación distinta `(tag_id, reader_id)` con `is_processed = FALSE`:**

1. **Lookup lector (por LPI)** en `readers JOIN postal_centers` → obtiene `reader_uuid`, `type` (`Entry`/`Exit`/`Mixed`), `mixed_reader_gap_minutes`, y datos del centro (id, nombre, código, ciudad, `calculation_mode`).
   - Si el lector **no existe** → crea incidencia `unknown_reader` (severidad `low`), marca las lecturas como procesadas y **salta** (`CONTINUE`).
2. **Lookup envío (por tag)** en `one_db` → `carrier_name`, `product_name`, `origin_city_name`, `destination_city_name`.
   - Si el tag **no está en `one_db`** → crea incidencia `unknown_tag` (severidad `medium`), marca procesadas y **salta**.
3. **Resolución de nombres a IDs:** `carrier_id` desde `carriers` (por nombre); `product_id` desde `products` (por `code` + `carrier_id`).
4. **Consolidación según el tipo de lector:**

   | Tipo de lector | `event_type` | `timestamp` | `analysis_datetime` |
   |---|---|---|---|
   | **Entry** | `entry` | `MIN(read_local_datetime)` | Si centro = `working_days` → `calculate_next_working_datetime(ts, centro)`; si no, = `timestamp` |
   | **Exit** | `exit` | `MAX(read_local_datetime)` | = `timestamp` (sin ajuste) |
   | **Mixed** | (split) | Llama a `consolidate_mixed_reader_events(...)` que separa entrada/salida por el **gap máximo** entre lecturas si supera el umbral | — |

5. Inserta en `processed_events` con todos los **snapshots** (lector, centro, carrier, producto, origen/destino) e `is_consolidated = TRUE`.
6. Marca las lecturas crudas correspondientes como `is_processed = TRUE`.

**Devuelve:** `{success, events_processed, events_created, unknown_readers, unknown_tags, duration_seconds}`.

#### `consolidate_mixed_reader_events(account, tag, reader, gap_threshold)`
Lee el array ordenado de timestamps del `(tag, lector Mixed)`. Busca el **mayor hueco** entre lecturas consecutivas:
- Si `max_gap > umbral` → emite dos eventos: `entry` (primera lectura) y `exit` (última), partiendo el conteo por el punto del hueco.
- Si no → un solo `entry` con todas las lecturas.

> ⚠️ Esta versión devuelve una tabla y tiene **4 argumentos**, pero `consolidate_rfid_events` la invoca con **10 argumentos** (`PERFORM consolidate_mixed_reader_events(account, tag, reader, reader_uuid, pc_id, gap, carrier, product, origin, dest)`). No existe esa sobrecarga de 10 args en el esquema → **la consolidación de lectores `Mixed` puede fallar hoy.** Ver [§7](#7-observaciones-e-inconsistencias-a-verificar).

### 5.2. Fase 2 — Reconstrucción de trayectos: `reconstruct_journeys(p_account_id, p_tag_id)`

`SECURITY DEFINER`. Recorre `processed_events` (con `is_consolidated = false`) **ordenados por `tag_id, timestamp`** y empareja eventos consecutivos del mismo tag para formar **segmentos**:

- **Segmento operacional** (mismo centro, `entry → exit`):
  - `adjusted_time` = `calculate_adjusted_time(entry, exit, centro)`; `pre_operational_wait` = `calculate_pre_operational_wait(...)`.
  - SLA vía `find_applicable_sla(account, 'operational', postal_center_id)`; cumplimiento vía `determine_sla_compliance(...)`.
  - Inserta en `journey_segments` (`segment_type='operational'`, sin carrier).
- **Segmento de distribución** (centros distintos, `exit → entry`):
  - Identifica el carrier desde `postal_center_carriers` (primero asociado al centro destino).
  - SLA vía `find_applicable_sla(account, 'distribution', from, to, carrier)`.
  - Inserta en `journey_segments` (`segment_type='distribution'`, con carrier).
- Tras crear cada segmento marca ambos `processed_events` como `is_consolidated = true, processed_at = NOW()`.

**Devuelve:** `segments_created, events_processed, execution_time_ms`.

### 5.3. Fase 3 — Ensamblado: `assemble_journeys(p_account_id)`

Agrupa `journey_segments` por `(account_id, tag_id)` y construye/actualiza un registro en `journeys` (UPSERT sobre `ON CONFLICT (account_id, tag_id)`):

- `route_path` (JSONB): array ordenado de tramos (tipo, centro, entrada/salida, cumplimiento SLA).
- Totales: `total_centers_visited`, tiempos `actual`/`adjusted`/`operational`/`distribution`/`pre_operational_wait`.
- `journey_status`: `in_progress` (último evento < 24 h), `anomalous` (hay SLA `violated`/`critical`), o `completed`.
- `total_sla_violations`, `total_segments`, `on_time_segments`.

**Devuelve:** `journeys_created, journeys_updated, execution_time_ms`.

### 5.4. Fase 4 — Agregación de rutas: `aggregate_journey_paths(p_account_id, p_since)`

Agrega `journey_segments` en `journey_paths`, una fila por **ruta única**. Internamente:

1. Subconsulta por tag: construye la **firma de ruta** (`path_signature`) concatenando `ciudad_origen→ciudad_destino` de cada tramo en orden, y suma tiempos naturales y laborables y el tiempo esperado.
2. Agrupa por `(carrier_id, product_id, origin_city_name, destination_city_name, path_signature)` y calcula:
   - `total_tags` = `COUNT(DISTINCT tag_id)`.
   - `avg_natural_time_minutes`, `avg_working_time_minutes`, y sus `stddev`.
   - `expected_time_minutes` = `MAX(...)` (todos los tags de una ruta comparten el esperado).
   - `compliance_rate` = media de `esperado / real * 100`.
   - `percent_real` = % de tags que llegaron en ≤ tiempo esperado.

Si se pasa `p_since`, primero borra los `journey_paths` de esa cuenta creados desde esa fecha (recálculo). **Devuelve:** `{success, paths_created}`.

---

## 6. Funciones auxiliares y de mantenimiento

### 6.1. Cálculo de tiempos y SLA (usadas por las fases 2–3)

| Función | Devuelve | Qué hace |
|---|---|---|
| `calculate_next_working_datetime(ts, centro)` | timestamptz | Próximo instante laborable según el centro (para `analysis_datetime` de entradas). |
| `calculate_working_time_minutes(ini, fin, centro)` | integer | Minutos laborables entre dos instantes (descuenta no laborables según `weekly_schedule`/`non_working_days`). |
| `calculate_adjusted_time(ini, fin, centro, account)` | integer | Tiempo ajustado; usa horario laboral si se pasan centro+cuenta, si no devuelve el tiempo real. |
| `calculate_pre_operational_wait(entrada_real, entrada_analisis)` | integer | Espera previa al inicio de proceso (llegadas tras hora de corte). |
| `find_applicable_sla(account, tipo, [centro], [from], [to], [carrier])` | tabla SLA | Busca SLA aplicable; prueba primero el específico de carrier y cae a uno genérico. |
| `determine_sla_compliance(real, esperado, %on_time, umbral_warning, umbral_critical)` | text | Nivel de cumplimiento (`on_time`/`warning`/`violated`/`critical`). |

### 6.2. Mantenimiento / reproceso

| Función | Qué hace |
|---|---|
| `archive_raw_events(account, tag, reader)` | Resume las lecturas **procesadas** de `rfid_events_raw` en `audit_raw_reads` (min/max/conteo) y luego las **borra** de `rfid_events_raw`. |
| `cleanup_processed_rfid_events(account, older_than_hours=24)` | Borra eventos procesados antiguos. ⚠️ **Opera sobre `rfid_intermediate_db`** (tabla heredada), no sobre `rfid_events_raw`. Ver [§7](#7-observaciones-e-inconsistencias-a-verificar). |
| `reprocess_failed_events(account)` | Reprocesa eventos fallidos. |
| `reprocess_transfer_errors(detail_ids[])` | Resetea registros con `transfer_error` a `received` para reintentar la transferencia. |

### 6.3. Ejecución/monitorización manual (usadas por el frontend)

| Función | Qué hace |
|---|---|
| `rpc_get_pipeline_status()` | Devuelve conteos (`raw_events` total/pendientes/procesados, `processed_events`, `segments`, `paths`) y `last_run` de cada etapa, para la pantalla **Pipeline Monitor**. |
| `rpc_execute_pipeline_phase(p_phase)` | Ejecuta manualmente una fase: `consolidation` → `consolidate_rfid_events`; `segments` → **`build_journey_segments`**; `aggregation` → `aggregate_journey_paths`; `all` → las tres. |

> **Nota importante:** la fase de segmentos del **cron** usa `reconstruct_journeys`, mientras que la ejecución **manual** (`rpc_execute_pipeline_phase 'segments'`) usa `build_journey_segments`. Son dos algoritmos distintos de construcción de `journey_segments` (ver [§7](#7-observaciones-e-inconsistencias-a-verificar)).

#### `build_journey_segments(p_account_id)` (vía manual)
Para cada tag con `processed_events` aún sin procesar (`processed_at IS NULL`), agrupa por centro visitado, detecta `entry_time`/`exit_time`, calcula **doble tiempo** (natural y laborable, este último vía `calculate_working_time_minutes` si el centro es `working_days`) tanto de permanencia como de tránsito al siguiente centro, e inserta el segmento (`operational` si no hay siguiente centro, `distribution` si lo hay). Marca los `processed_events` con `processed_at = NOW()`.

---

## 7. Observaciones e inconsistencias (a verificar)

Detectadas al leer el código real. Se documentan como hallazgos, **no** como cambios aplicados:

1. **`rpc_ingest_epcis_events` parece desalineada con el esquema.** Inserta una columna `event_timestamp` que **no existe** en `rfid_events_raw` (la columna real es `read_local_datetime`), y fija `account_id := auth.uid()` (el UID del usuario, no su `account_id`). Además `event_id` es `NOT NULL` sin default y la función no lo aporta. → **La ingesta vía esta RPC probablemente falla** en el esquema actual; conviene revisarla o tratarla como heredada.
2. **Consolidación de lectores `Mixed`:** `consolidate_rfid_events` invoca `consolidate_mixed_reader_events` con **10 argumentos**, pero solo existe la versión de **4 argumentos**. → Los lectores tipo `Mixed` podrían no consolidarse.
3. **Dos constructores de segmentos divergentes:** el cron usa `reconstruct_journeys` (emparejado entry/exit con SLA), y la UI manual usa `build_journey_segments` (por centro, con doble tiempo). Conviene unificar o documentar cuál es canónico.
4. **`cleanup_processed_rfid_events` limpia la tabla equivocada:** borra de `rfid_intermediate_db` (heredada) y no de `rfid_events_raw`. La limpieza real de `rfid_events_raw` la hace `archive_raw_events`.
5. **`account_id` por defecto "hardcodeado":** `rpc_execute_pipeline_phase` y `rpc_get_pipeline_status` caen a un UUID fijo (`f4d823d2-…`) si no resuelven la cuenta desde el JWT. Aceptable para demo, riesgo en producción multi-tenant.

---

## 8. Vía heredada: Edge Functions y `rfid_intermediate_db`

Arquitectura **paralela** (anterior), separada del pipeline del cron:

| Edge Function | Qué hace | Tablas |
|---|---|---|
| `process-rfid-events` | Agrupa eventos por `tag`, deduplica (<5 min), parte rutas (gap >24 h), calcula métricas y detecta anomalías. | lee `rfid_intermediate_db` → escribe `diagnosis_routes`, `diagnosis_time_metrics`, `diagnosis_anomalies` |
| `generate-epcis-data` | Genera eventos EPCIS sintéticos de prueba (solo admin/superadmin). | inserta en `rfid_intermediate_db` |
| `onedb-api` | API externa sobre datos de calidad postal. | `one_db` (auth vía `api_keys`) |
| `admin-reset-password` | Reseteo administrativo de contraseñas. | `auth.users` / `profiles` |

> Esta vía alimenta las tablas `diagnosis_*` y **no** está conectada al flujo `processed_events → journeys`. Tratar como heredada salvo confirmación en contra.

---

## 9. Monitorización (consultas útiles)

```sql
-- Estado del cron y de las últimas ejecuciones
SELECT * FROM cron.job WHERE jobname = 'rfid-pipeline-every-15min';
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;

-- Disparar el pipeline completo manualmente (todas las cuentas)
SELECT * FROM process_all_accounts_pipeline();

-- Backlog de carga: lecturas pendientes de procesar
SELECT account_id, COUNT(*) AS pendientes
FROM rfid_events_raw
WHERE is_processed = FALSE
GROUP BY account_id;

-- Estado del pipeline para la cuenta del usuario autenticado (lo usa la UI)
SELECT rpc_get_pipeline_status();
```

---

## 10. Resumen del flujo (una frase por fase)

1. **Carga:** las lecturas entran en `rfid_events_raw` (API / proveedor externo / demo) con `is_processed = FALSE`.
2. **Consolidación (F1):** se agrupan por `(tag, lector)`, se enriquecen con lector+centro+carrier+envío y se vuelcan a `processed_events` como `entry`/`exit`; lo desconocido genera `incidents`.
3. **Reconstrucción (F2):** se emparejan eventos en `journey_segments` (operacionales y de distribución) con tiempos y SLA.
4. **Ensamblado (F3):** los segmentos se agregan por tag en `journeys` (trayecto completo + estado).
5. **Agregación (F4):** los segmentos se agregan por ruta única en `journey_paths` (medias, SLA, % real) para los dashboards.
6. **Mantenimiento:** `archive_raw_events` mueve lo procesado a `audit_raw_reads` y libera `rfid_events_raw`.

*Documento generado por inspección directa de la BD (funciones, cron) y del código del repositorio. Para regenerarlo: releer `pg_get_functiondef` de las funciones del pipeline, `cron.job`, las Edge Functions y el frontend (`EventConsolidation.tsx`, `EPCISAPI.tsx`).*
