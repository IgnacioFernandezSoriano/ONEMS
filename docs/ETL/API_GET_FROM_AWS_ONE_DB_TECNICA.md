# API GET from AWS ONE DB — Documentación Técnica

> **Propósito:** describir con precisión la API **tal como está implementada hoy**, como línea base antes de definir la nueva API de ingesta con el proveedor RFID.
> **Generado:** 2026-06-10 · A partir del código real (`EPCISAPI.tsx`, funciones RPC en Postgres y Edge Function `onedb-api`).
> **Relacionados:** [ETL_RFID_PIPELINE_TECNICO.md](ETL_RFID_PIPELINE_TECNICO.md) · [ETL_RFID_MANUAL_USUARIO.md](ETL_RFID_MANUAL_USUARIO.md).

---

## 0. Resumen

Hoy conviven **dos superficies de API distintas**, con propósitos y autenticación diferentes:

| API | Para qué | Transporte | Autenticación | Base URL |
|---|---|---|---|---|
| **A. EPCIS Pipeline API** | Ingerir lecturas y controlar/monitorizar el pipeline ETL. | PostgREST (RPC sobre funciones SQL) | **JWT de Supabase** (`Authorization: Bearer`) | `https://sehbnpgzqljrsqimwyuz.supabase.co/rest/v1/rpc` |
| **B. ONE DB API** | Exponer hacia fuera los registros de calidad postal (`one_db`). | Edge Function (Deno) | **API key** (`X-API-Key`) | `https://sehbnpgzqljrsqimwyuz.supabase.co/functions/v1/onedb-api` |

> La **ingesta de datos del ETL** vive en la API **A** (`rpc_ingest_epcis_events`). La API **B** es de **salida** (consulta de `one_db` por terceros) y no participa en la carga RFID.

---

## A. EPCIS Pipeline API (RPC + JWT)

Cuatro endpoints, todos `POST` sobre `/rest/v1/rpc/<función>`, con `Content-Type: application/json` y `Authorization: Bearer <JWT>`. El frontend los documenta en la pantalla **EPCIS Pipeline API** (`EPCISAPI.tsx`).

### A.1. `POST /rpc/rpc_ingest_epcis_events` — Ingesta de eventos

Inserta lecturas en bloque en `rfid_events_raw` (la "RFID Events Database").

**Body**
| Campo | Tipo | Req. | Descripción |
|---|---|---|---|
| `p_events` | `jsonb` (array) | Sí | Lista de lecturas. Cada elemento: `TagId`, `ReaderId`, `ReadLocalDateTime`. |

**Ejemplo**
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

**Comportamiento (función `rpc_ingest_epcis_events`, `SECURITY DEFINER`)**
- `account_id := auth.uid()` (UID del usuario autenticado).
- Itera `p_events`; por cada evento hace `INSERT INTO rfid_events_raw (account_id, tag_id, reader_id, event_timestamp, is_processed=FALSE)`.
- Cuenta éxitos/fallos por evento (cada inserción va en su propio bloque `EXCEPTION`).

**Respuesta**
```json
{ "success": true, "inserted": 1, "failed": 0 }
```
En error global: `{ "success": false, "error": "<mensaje>" }`.

> ⚠️ **Esta función está desalineada con el esquema actual** (ver §7 del doc técnico): inserta `event_timestamp` (la columna real es `read_local_datetime`), usa `auth.uid()` como `account_id` (debería ser el `account_id` del perfil) y **no aporta `event_id`**, que es `NOT NULL` sin default. En la práctica **la ingesta por esta vía probablemente falla** y será lo primero a rehacer al definir la nueva API.

### A.2. `POST /rpc/rpc_execute_pipeline_phase` — Ejecutar una fase

Lanza manualmente una fase del pipeline.

**Body**
| Campo | Tipo | Req. | Valores |
|---|---|---|---|
| `p_phase` | `text` | Sí | `consolidation` · `segments` · `aggregation` · `all` |

**Comportamiento (`SECURITY DEFINER`)**
- Resuelve `account_id` en cascada: `auth.users.raw_user_meta_data->>'account_id'` → `auth.jwt()->>'account_id'` → **fallback hardcodeado** `f4d823d2-93e6-4755-9a89-9da87e7fa86e`.
- Valida `p_phase`; mapea: `consolidation` → `consolidate_rfid_events`; `segments` → `build_journey_segments`; `aggregation` → `aggregate_journey_paths`; `all` → las tres.
- Devuelve `{ success, account_id, phase, consolidation, segments, aggregation }`.

> Nota: esta vía usa `build_journey_segments`, mientras que el **cron** usa `reconstruct_journeys` (algoritmos distintos; ver §7 del doc técnico).

### A.3. `POST /rpc/rpc_get_pipeline_status` — Estado del pipeline

Sin parámetros. Devuelve contadores y últimas ejecuciones para la cuenta del usuario.

**Respuesta (resumen)**
```json
{
  "success": true,
  "account_id": "…",
  "raw_events":       { "total": N, "pending": N, "processed": N },
  "processed_events": { "total": N },
  "segments":         { "total": N },
  "paths":            { "total": N },
  "last_run": { "consolidation": "…", "segment_building": "…", "aggregation": "…" }
}
```
Resuelve `account_id` con la misma cascada (incluido el fallback hardcodeado) que A.2.

### A.4. `POST /rpc/rpc_query_journey_paths` — Consultar rutas agregadas

Consulta `journey_paths` con filtros opcionales.

**Body / parámetros**
| Parámetro | Tipo | Req. | Descripción |
|---|---|---|---|
| `p_carrier_id` | uuid | No | Filtra por transportista |
| `p_product_id` | uuid | No | Filtra por producto |
| `p_origin_city` | text | No | Filtra por ciudad origen |
| `p_destination_city` | text | No | Filtra por ciudad destino |
| `p_min_tags` | integer | No | Mínimo de tags por ruta |
| `p_limit` | integer | No | Máx. resultados (default **100**) |

**Comportamiento (`SECURITY DEFINER`)**
- `account_id := auth.uid()`.
- `SELECT` sobre `journey_paths` filtrando por cuenta + los filtros aportados, `ORDER BY total_tags DESC LIMIT p_limit`.
- Devuelve un array JSON (o `[]`). Campos por fila: `id, carrier_id, product_id, origin_city, destination_city, path_signature, path_segments, total_tags, avg_natural_time_minutes, avg_working_time_minutes, compliance_rate, segment_details, last_updated`.

> ⚠️ A verificar: la función referencia las columnas `segment_details` y `last_updated`, que **no aparecen** entre las que escribe `aggregate_journey_paths` (esa usa `path_segments`, `created_at`, `updated_at`, `percent_real`…). Posible desajuste de columnas. Además usa `auth.uid()` como `account_id` (mismo patrón que A.1).

### A.5. Autenticación y modelo de cuenta (API A)

- **Auth:** JWT de Supabase en `Authorization: Bearer`. Con el cliente de Supabase se incluye automáticamente.
- **Resolución de `account_id` inconsistente entre endpoints:**
  - A.1 y A.4 → `auth.uid()` directamente (UID del usuario, **no** su `account_id`).
  - A.2 y A.3 → cascada `user_meta_data` → `jwt` → **fallback fijo**.
  - Unificar este criterio forma parte del trabajo de §7.

---

## B. ONE DB API (Edge Function `onedb-api`)

API de **salida** para que sistemas externos lean los registros de calidad postal (`one_db`). Es una Edge Function en Deno que usa el `service_role` internamente y se autentica por **API key**.

- **URL:** `https://sehbnpgzqljrsqimwyuz.supabase.co/functions/v1/onedb-api`
- **Método:** `GET` (soporta `OPTIONS` para CORS).
- **Auth:** cabecera **`X-API-Key: <api_key>`** (se valida contra la tabla `api_keys` con `is_active = true`). Se usa `X-API-Key` deliberadamente en lugar de `Authorization` para no disparar la validación de JWT.

**Parámetros de query**
| Parámetro | Req. | Descripción |
|---|---|---|
| `start_date` | Sí | Formato `YYYY-MM-DD` |
| `end_date` | Sí | Formato `YYYY-MM-DD` |
| `limit` | No | Default `100`; máx **1000** por página |
| `offset` | No | Default `0` |

**Lógica**
1. Valida API key → obtiene `account_id`.
2. **Rate limit:** máx **10 peticiones/minuto** por API key (contadas en `api_usage_log`). Excede → `429`.
3. Valida fechas (presencia y formato). Registra el uso en `api_usage_log`.
4. **Tope total de 10.000 registros** (`offset >= 10000` → `400`). Pagina internamente en lotes de 1000.
5. Consulta `one_db` filtrando por `account_id` y `sent_at` entre `start_date`/`end_date`, `ORDER BY sent_at DESC`.
6. Actualiza `api_keys.last_used_at` y `usage_count`.

**Respuesta (éxito `200`)**
```json
{
  "success": true,
  "data": [ /* registros de one_db */ ],
  "pagination": {
    "total": 0, "total_available": 0,
    "limit": 100, "offset": 0,
    "has_more": false, "max_records": 10000
  },
  "meta": {
    "response_time_ms": 0,
    "rate_limit": { "limit": 10, "remaining": 9, "reset_at": "…" },
    "data_limit": { "max_total_records": 10000, "note": "…" }
  }
}
```

**Códigos de error**
| Código | Causa |
|---|---|
| `401` | Falta `X-API-Key` / API key inválida o inactiva |
| `429` | Rate limit superado (10/min) |
| `400` | Faltan `start_date`/`end_date`, formato inválido, u `offset >= 10000` |
| `500` | Error de base de datos o interno |

---

## C. Tablas de soporte de la API

| Tabla | Rol |
|---|---|
| `api_keys` | Claves API (campo `api_key`, `account_id`, `is_active`, `usage_count`, `last_used_at`). Usadas por la API B. |
| `api_usage_log` | Registro de cada llamada (`api_key_id`, `endpoint`, `request_timestamp`, `ip_address`). Base del rate-limit. |

> En el frontend, la pantalla EPCIS API tiene la gestión de API keys **pendiente** (`apiKey = null`, "TODO: Implement API key management hook").

---

## D. Catálogo rápido de endpoints

| API | Método | Endpoint | Auth | Función / fuente |
|---|---|---|---|---|
| A | POST | `/rest/v1/rpc/rpc_ingest_epcis_events` | JWT | Ingesta → `rfid_events_raw` |
| A | POST | `/rest/v1/rpc/rpc_execute_pipeline_phase` | JWT | Ejecutar fase del pipeline |
| A | POST | `/rest/v1/rpc/rpc_get_pipeline_status` | JWT | Estado del pipeline |
| A | POST | `/rest/v1/rpc/rpc_query_journey_paths` | JWT | Consultar `journey_paths` |
| B | GET | `/functions/v1/onedb-api` | X-API-Key | Consultar `one_db` |

---

## E. Notas para la nueva API (a tener en cuenta)

Al definir la nueva API de ingesta con el proveedor, esta línea base deja claros los puntos a corregir/decidir:

1. **Rehacer `rpc_ingest_epcis_events`** alineándola con el esquema real (`read_local_datetime`, aportar `event_id`, resolver `account_id` correctamente). *(Origen: §7 del doc técnico.)*
2. **Unificar la resolución de `account_id`** entre todos los endpoints y eliminar el fallback hardcodeado.
3. **Revisar `rpc_query_journey_paths`** (columnas `segment_details`/`last_updated`).
4. **Decidir el modelo de auth de ingesta:** ¿JWT de usuario, API key (como `onedb-api`), o servicio dedicado para el job de polling del proveedor?
5. **Definir campos del origen** (proveedor externo): hoy el contrato propuesto es `{id, location, readerId, tagId, timestamp}`; confirmar cuáles persistimos y cómo mapean a `rfid_events_raw`.

*Documento generado por inspección directa del código y de las funciones desplegadas. Para regenerarlo: releer `EPCISAPI.tsx`, `pg_get_functiondef` de las RPC `rpc_*`, y la Edge Function `onedb-api`.*
