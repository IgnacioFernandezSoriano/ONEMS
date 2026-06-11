# Ingesta RFID desde la API de AWS (proveedor) — Diseño

> **Fecha:** 2026-06-11
> **Proyecto:** ONEMS · Supabase `onems-dev` (`sehbnpgzqljrsqimwyuz`, eu-central-2)
> **Estado:** diseño aprobado, pendiente de plan de implementación
> **Relacionados:** [ETL_RFID_PIPELINE_TECNICO.md](../../ETL/ETL_RFID_PIPELINE_TECNICO.md) · [API_GET_FROM_AWS_ONE_DB_TECNICA.md](../../ETL/API_GET_FROM_AWS_ONE_DB_TECNICA.md) · API del proveedor: `ONEMS-AWS_API-ONE_DB_V1.md` (Stefan Gelov)

---

## 1. Objetivo

Implementar la **captura incremental** de lecturas RFID desde la API del proveedor (AWS, eu-central-1) hacia ONEMS, normalizar los campos al formato que espera el ETL, y encadenar el pipeline ETL **inmediatamente después** de cada captura. Todo gobernado por un único disparo cada **30 minutos**, secuencial: **primero captura, luego ETL**.

Cubre las cuatro peticiones del usuario:
1. Implementar la API de captura de datos desde AWS.
2. Cron cada 30 min, secuencial (captura → ETL).
3. Analizar la estructura del registro de origen.
4. Analizar el impacto en el ETL.

## 2. Origen de datos (API del proveedor)

`GET https://t81an8rql2.execute-api.eu-central-1.amazonaws.com/v1/reads`, auth `x-api-key`, paginado por cursor opaco, append-only, idempotente por `id`.

Estructura del registro (§3 de la doc del proveedor):

```json
{
  "id":          "1a66a44f-c905-4ac4-a8b0-3d1811ef86f0",
  "location":    "Brazil | Aparecida de Goiania | CTCE Goiania | GO",
  "readerId":    "J11DBRA02100000319",
  "tagId":       "urn:oid:1.0.15961.14.B.A00122245737",
  "timestamp":   "2024-05-07T09:53:06.238-03:00",
  "ingested_at": "2024-05-07T12:53:08.412Z"
}
```

Semántica relevante:
- **`id`** (UUID): idempotencia / de-dup.
- **`ingested_at`** (UTC, monótono): único campo garantizado monótono → base del *high-water mark*. `timestamp` es hora local del lector con offset.
- **`location`**: pipe-delimited `País | Ciudad | Sitio | Estado`, siempre 4 partes, trim.
- **Exactamente uno** de `since` (ISO-8601 UTC) o `cursor` por petición. `since` solo en la 1ª llamada o tras un hueco largo; después siempre `cursor`.
- **Rate limits:** 20 req/s steady, burst 50, 50.000 req/día por key. `429` → respetar `Retry-After`.
- **Paginación:** `limit` 1–1000 (default 500); `next_cursor` null = al día (el cursor sigue válido).

## 3. Decisiones tomadas

| # | Decisión | Valor |
|---|---|---|
| D1 | Cadencia y orden | 1 disparo cada 30 min, **secuencial**: captura → resolve → ETL |
| D2 | Arquitectura | **Enfoque A**: landing table `rfid_provider_reads` + resolver, sin tocar el esquema de `rfid_events_raw` |
| D3 | Alcance formato/matching | **Captura + normalización** (decodificar `tagId`, validar `readerId`) |
| D4 | Cron 15 min existente | **Desprogramar** `rfid-pipeline-every-15min` (el ETL pasa a correr dentro del poll) |
| D5 | Bug lectores Mixed (§7 #2) | **Fuera de alcance** de esta entrega (señalado como riesgo) |
| D6 | Resolución de `account_id` | Derivada de `readerId → readers.account_id` (reader_id único global: 14/14, 0 en varias cuentas) |
| D7 | Idempotencia | `id` proveedor → PK de landing; `(account_id, event_id)` → UNIQUE ya existente en `rfid_events_raw` |

## 4. Arquitectura

```
pg_cron  (rfid-provider-poll-every-30min, */30 * * * *)
   └─ net.http_post ─▶ Edge Function: rfid-provider-poll
         1. GET AWS /v1/reads   (cursor incremental, paginado, x-api-key)
         2. UPSERT verbatim     → rfid_provider_reads           (landing, account nullable)
         3. RPC resolve_provider_reads()
              · normalize_provider_tag(tag_id_raw)  → tag_id_normalized
              · readerId → readers.account_id
              · matched         → INSERT en rfid_events_raw (idempotente)
              · unknown_reader  → permanece en landing (se reintenta cada run)
              · tag_decode_failed → permanece en landing (se reintenta cada run)
         4. al terminar OK → RPC process_all_accounts_pipeline()  (ETL: F1..F4)
         5. devuelve resumen { fetched, matched, unmatched, pipeline }
```

## 5. Componentes

### 5.1. Tablas nuevas (migración)

**`rfid_provider_reads`** (landing):

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid PK | `id` del proveedor → idempotencia |
| `location` | text | cruda, `País \| Ciudad \| Sitio \| Estado` |
| `reader_id` | text NOT NULL | `readerId` |
| `tag_id_raw` | text NOT NULL | `tagId` tal cual |
| `read_local_datetime` | timestamptz NOT NULL | `timestamp` |
| `ingested_at` | timestamptz NOT NULL | `ingested_at` del proveedor |
| `tag_id_normalized` | text NULL | lo escribe el resolver |
| `resolved_account_id` | uuid NULL | FK `accounts(id)`, derivado del reader |
| `match_status` | text NOT NULL default `'pending'` | `pending`/`matched`/`unknown_reader`/`tag_decode_failed` |
| `unmatch_reason` | text NULL | motivo legible |
| `rfid_events_raw_id` | uuid NULL | fila creada en raw (traza) |
| `created_at` | timestamptz default now() | |
| `resolved_at` | timestamptz NULL | |

Índices: `(match_status)`, `(reader_id)`, `(ingested_at)`. CHECK sobre los valores de `match_status`.

**`rfid_ingest_state`** (estado del polling, 1 fila por fuente):

| Columna | Tipo | Notas |
|---|---|---|
| `id` | text PK | p.ej. `'aws-rfid-read-api'` |
| `next_cursor` | text NULL | high-water mark |
| `last_since` | timestamptz NULL | último `since` usado |
| `backfill_since` | timestamptz NULL | config 1ª corrida (máx 24 meses atrás) |
| `last_run_at` | timestamptz NULL | |
| `last_status` | text NULL | `ok`/`error`/`rate_limited` |
| `last_error` | text NULL | |
| `total_fetched` | bigint default 0 | acumulado |
| `last_fetched` / `last_matched` / `last_unmatched` | int | de la última corrida |

### 5.2. Edge Function `rfid-provider-poll` (Deno)

- **Auth de entrada:** `Authorization: Bearer <CRON_SECRET>` (patrón de `consolidate-rfid-events-cron`).
- **Secrets (env, NO en repo):** `RFID_PROVIDER_API_URL`, `RFID_PROVIDER_API_KEY`, `CRON_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.
- **Flujo:**
  1. Lee `rfid_ingest_state`. Si no hay `next_cursor` ni corrida previa → `?since=backfill_since`; si no → `?cursor=next_cursor`.
  2. Bucle paginado `GET …/v1/reads?cursor=…&limit=1000` con `x-api-key`. Tras **cada página**: `UPSERT` a `rfid_provider_reads` `ON CONFLICT (id) DO NOTHING` y **persiste `next_cursor`/`last_since`** (reanudable ante fallo).
  3. Termina el bucle cuando `next_cursor` es null **o** se alcanza el presupuesto de páginas/tiempo de la corrida (proteger rate limit y timeout de la función).
  4. `RPC resolve_provider_reads()`.
  5. Si OK → `RPC process_all_accounts_pipeline()` (ETL).
  6. Actualiza `rfid_ingest_state` (status, contadores) y devuelve resumen.

### 5.3. RPC `resolve_provider_reads()` (SECURITY DEFINER)

- Procesa filas con `match_status IN ('pending','unknown_reader','tag_decode_failed')` → **auto-sana**: al cargar LPI reales o confirmar el decode, el siguiente run reintenta los no-casados.
- Por fila:
  - `tag_id_normalized := normalize_provider_tag(tag_id_raw)`.
  - `resolved_account_id := (SELECT account_id FROM readers WHERE reader_id = r.reader_id AND deleted_at IS NULL)`.
  - reader no existe → `match_status='unknown_reader'`, `unmatch_reason`, skip.
  - `tag_id_normalized IS NULL` → `match_status='tag_decode_failed'`, skip.
  - OK → `INSERT INTO rfid_events_raw (account_id, event_id, read_local_datetime, reader_id, tag_id, is_processed) VALUES (resolved_account_id, r.id::text, r.read_local_datetime, r.reader_id, tag_id_normalized, false) ON CONFLICT (account_id, event_id) DO NOTHING`; guarda `rfid_events_raw_id`, `match_status='matched'`, `resolved_at=now()`.
- Devuelve `{ processed, matched, unknown_reader, tag_decode_failed }`.

### 5.4. `normalize_provider_tag(raw text) returns text`

- Si `raw` ya es hex EPC (p.ej. `^[0-9A-Fa-f]+$`) → devolver tal cual (mayúsculas).
- Si `raw` es `urn:oid:…` → aplicar la regla documentada de extracción del identificador → hex EPC.
- Si no se puede decodificar → `NULL`.
- Acompañado de **vectores de test**. **(ABIERTO, ver §8.)**

### 5.5. Cron

- `cron.unschedule('rfid-pipeline-every-15min')` (D4).
- `cron.schedule('rfid-provider-poll-every-30min', '*/30 * * * *', <net.http_post a la edge function>)`.
- Requiere extensión `pg_net`. Secreto de la llamada HTTP vía **Supabase Vault** o tabla de config (no hardcodear en el comando del cron). **(infra abierta, ver §8.)**

## 6. Mapeo de campos (origen → destino)

| Proveedor | Landing `rfid_provider_reads` | `rfid_events_raw` (si matched) |
|---|---|---|
| `id` | `id` (PK) | `event_id` (text) |
| `timestamp` | `read_local_datetime` | `read_local_datetime` |
| `readerId` | `reader_id` | `reader_id` (+ resuelve `account_id`) |
| `tagId` | `tag_id_raw` | `tag_id` (= `tag_id_normalized`) |
| `location` | `location` | — (no se propaga; el ETL deriva origen/destino de `one_db`+centros) |
| `ingested_at` | `ingested_at` | — |

## 7. Impacto en el ETL

- **Camino feliz: cero cambios** en las funciones del pipeline. La ingesta alimenta `rfid_events_raw` con el esquema exacto que consume el ETL (`event_id`, `read_local_datetime`, `reader_id`, `tag_id`, `account_id`, `is_processed=false`).
- Se **bypassa** `rpc_ingest_epcis_events` (rota, §7 #1: inserta `event_timestamp` inexistente, no aporta `event_id`, usa `auth.uid()` como cuenta). Insertamos vía `resolve_provider_reads()` con service_role, bien formado. → **Recomendación:** marcar esa RPC como heredada.
- **`tagId`:** sin normalización, el lookup del ETL contra `one_db` (hex) fallaría siempre con el `urn:oid` del proveedor → `unknown_tag` en cada lectura. La normalización le da una oportunidad real de casar. El match definitivo contra `one_db` lo sigue haciendo el ETL (genera incidencia `unknown_tag` si no casa).
- **`readerId`:** el catálogo `readers` en dev tiene LPI demo (`LA-LC-ENTRY`…), no los reales (`J11DBRA…`). Hasta cargar los LPI reales, el resolver marcará `unknown_reader` (esperado y visible en `match_status`; auto-sana al actualizar el catálogo).
- **Riesgo (§7 #2, fuera de alcance):** `consolidate_rfid_events` invoca `consolidate_mixed_reader_events` con 10 args y solo existe la de 4 → los lectores **Mixed** pueden fallar al llegar datos reales. Señalado; se abordará por separado.

## 8. Cuestiones abiertas

1. **Regla exacta de decodificación `urn:oid:1.0.15961.14.B.A00122245737` → EPC hex.** No determinable desde el código actual; depende del esquema del proveedor. Confirmar con **Stefan Gelov**. Diseño con fallback seguro (`tag_decode_failed`, reintentable).
2. **Carga de LPI reales en `readers`.** Tarea de datos; sin ella el resolver no casará lectores reales.
3. **Secreto del cron para `net.http_post`** (Vault vs tabla de config) y disponibilidad de `pg_net` en el proyecto.
4. **`backfill_since` inicial**: qué fecha de arranque del histórico (máx 24 meses) se solicita al proveedor.

## 9. Seguridad

- La doc del proveedor **incluye la API key de producción** (`upu-rfid-read-key-onems-prod`). Recomendación: **(a) rotarla** con Stefan (ha circulado en texto), **(b)** guardarla como **secret de Supabase**, nunca en el repo, **(c)** no commitear la doc con la clave dentro.

## 10. Estrategia de pruebas

- **Unit `normalize_provider_tag`:** vectores `urn:oid` conocido, hex ya válido, basura → NULL.
- **`resolve_provider_reads`:** rutas matched / unknown_reader / tag_decode_failed con filas semilla; verificar auto-sanado al añadir el reader.
- **Idempotencia:** re-procesar la misma página/`id` → sin duplicados en landing ni en `rfid_events_raw`.
- **Edge function:** respuestas AWS simuladas (1 página, multi-página con cursor, `429` con `Retry-After`, página vacía); verificar persistencia de cursor y encadenado del ETL.
