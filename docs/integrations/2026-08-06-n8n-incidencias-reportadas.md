# Traspaso a n8n + Telegram — Incidencias reportadas por panelista

**Fecha:** 2026-08-06
**Para:** quien construya los workflows en el entorno n8n.
**Qué es esto:** todo lo que necesitas saber de ONEMS para enlazar el flujo de "incidencias
reportadas por el panelista" (falta material, etiqueta ilegible, paquete roto, devuelto,
baja, etc., reportadas por Telegram) con la base de datos ONEMS. No incluye nada de n8n en
sí — solo el "contrato" con la BD.

Esto es el **segundo tipo de incidencia** de ONEMS. El primero (subsistema C, bajas de
panelista resueltas por el manager) está documentado en
`docs/integrations/2026-08-05-n8n-telegram-subsistema-c.md`. Este documento cubre el flujo
inverso: el panelista **inicia** la incidencia desde Telegram, la app la guarda, y el manager
la resuelve desde una pantalla nueva ("Incidencias reportadas").

---

## 0. Resumen en una frase

El panelista escribe a un bot de Telegram para reportar un problema (le falta material, no
puede leer la etiqueta, el paquete llegó roto, se lo devolvieron, quiere darse de baja,
etc.). n8n recoge ese mensaje, sube la foto si la hay, e inserta una fila en
`panelist_incident`. El manager la ve en su pantalla de ONEMS (F5 para refrescar, no es
tiempo real), la resuelve, y opcionalmente escribe una respuesta que n8n debe reenviar por
Telegram al panelista.

---

## 1. La base de datos (una sola, ojo con esto)

- **Proyecto Supabase:** `onems-dev`
- **project-ref:** `sehbnpgzqljrsqimwyuz`
- **Org:** "ONE for Regulators MS"
- Hay **UNA sola base**. "prod" y "dev" son solo la rama de código y el frontend desplegado:
  **apuntan a la misma BD**. No existe una base separada de staging.

### ⚠️ Regla de oro multi-tenant (no te la saltes)

ONEMS es **multi-cuenta**. El aislamiento entre cuentas es por la columna **`account_id`**,
aplicado normalmente por Row Level Security (RLS). **El nodo Postgres de n8n entra como
service-role y SALTA el RLS.** Consecuencias:

- En cualquier `SELECT`/`INSERT`/`UPDATE` que escribas a mano en n8n, **TÚ debes derivar y
  filtrar por `account_id`**. Deriva el `account_id` a partir del panelista
  (`SELECT account_id FROM panelists WHERE id = <panelist_id>` o vía su `telegram_id`).
  Si lo olvidas, mezclarás datos de cuentas distintas → fuga de datos entre reguladores.
- **Nunca** escribas el plan de asignación (`allocation_plan_details`) a mano. Si una
  incidencia requiere tocar el plan (recepción manual, invalidar, reprogramar, cancelar), eso
  lo hace la app del manager a través de sus propias RPCs (`mark_detail_received_manual`,
  `invalidate_detail`, `reschedule_detail`, `cancel_detail`) — n8n **no** las necesita para dar
  de alta la incidencia.

### Cómo se conecta n8n

Igual que en el subsistema C: **nodo Postgres** (conexión por el pooler de Supabase, no al
5432 directo — bloqueado por firewall fuera de la red) para `INSERT`/`SELECT`/`UPDATE`, y
subida de fotos vía el SDK/API de Storage de Supabase con la service-role key.

---

## 2. Objetos de la BD que vas a usar

### Tabla `panelist_incident` (alta desde Telegram)

Columnas que **rellena n8n** al hacer el `INSERT`:

| Columna | Tipo / valores | Nota |
|---|---|---|
| `account_id` | uuid | **Derivado del panelista** (nunca lo mandes fijo/hardcodeado) |
| `panelist_id` | uuid | FK a `panelists`, identifica al que reporta |
| `category` | text | uno de los **9 códigos** (ver abajo) |
| `description` | text | texto libre del panelista |
| `photo_url` | text | **ruta** dentro del bucket `incident-photos` tras subir la foto — **no** una URL pública (ver §3) |
| `allocation_plan_detail_id` | uuid | el envío al que el panelista se refiere. El incidente se enlaza por **id del envío**, no por tag — el tag puede ser justo lo ilegible/el problema |
| `payload` | jsonb | esquema mínimo según la categoría (ver §2.2) |

Las demás columnas (`status` default `'open'`, `reply_to_panelist`, `reply_status`,
`resolution_note`, `resolved_at`, `resolved_by`, etc.) las gestiona la app del manager — **n8n
no las fija en el INSERT**.

**Los 9 códigos válidos de `category`** (CHECK constraint en la tabla):

1. `missing_materials` — falta material
2. `unreadable_label_receipt` — etiqueta/recibo ilegible
3. `parcel_damaged` — paquete roto
4. `parcel_returned` — paquete devuelto
5. `how_to_send` — duda de cómo enviar
6. `unavailability_request` — petición de baja
7. `tag_photo_problem` — problema con la foto del tag
8. `contact_data_change` — cambio de datos de contacto
9. `other` — otro

### 2.2 Esquema mínimo de `payload` por categoría

- **`contact_data_change`** → `{ "telegram_id"?: string, "mobile"?: string, "language"?: string }`
  — ojo: el campo de teléfono se llama **`mobile`** (coincide con la columna real de
  `panelists.mobile`, no `phone`).
- **`missing_materials`** → `{ "materials"?: [{ "name": string, "quantity": number }] }`
- **Resto de categorías** → libre/omitible. No hay esquema obligatorio; deja `payload` como
  `null` o con lo que capture el flujo de Telegram si es útil para el manager.

### Tabla `panelists` (para resolver `panelist_id`/`account_id` y responder)

| Columna | Nota |
|---|---|
| `telegram_id` | chatId de Telegram; puede ser NULL o `''` |
| `language` | `'en'`\|`'es'`\|`'fr'`\|`'ar'` → idioma para responder |
| `account_id` | de aquí sale el `account_id` a insertar en la incidencia |

---

## 3. Subida de foto (bucket `incident-photos`)

- Bucket **privado** (`public: false`), creado por la migración
  `20260806160000_panelist_incident.sql`.
- n8n sube el archivo con la **service-role key** (tiene permiso de escritura sobre buckets
  privados sin pasar por RLS de Storage).
- En `panelist_incident.photo_url` guarda **la ruta del objeto** dentro del bucket (p. ej.
  `<account_id>/<panelist_id>/<timestamp>.jpg`), **no** una URL pública ni firmada.
- La app del manager genera **signed URLs** bajo demanda para mostrar la foto — por eso no
  hace falta (ni conviene) que la URL sea pública.

---

## 4. Canal de vuelta (responder al panelista)

Cuando el manager resuelve una incidencia y escribe una respuesta, la app deja la fila así:
`reply_to_panelist` = texto de la respuesta, `reply_status = 'pending_send'`.

n8n debe **hacer polling** (cron, como en el resto de workflows) sobre:

```sql
SELECT id, panelist_id, reply_to_panelist
FROM panelist_incident
WHERE reply_status = 'pending_send'
  AND account_id = '<ACCOUNT_ID>';   -- ⚠️ filtrar cuenta, una consulta por cuenta o con account_id explícito
```

Para cada fila:

1. Buscar `telegram_id` y `language` del panelista (`panelists.telegram_id`,
   `panelists.language`) y enviar `reply_to_panelist` por Telegram en ese idioma (el texto ya
   viene redactado por el manager — no hace falta traducirlo, es texto libre).
2. Marcar como enviado:

```sql
UPDATE panelist_incident
SET reply_status = 'sent', reply_sent_at = now()
WHERE id = '<id>';
```

---

## 5. No es tiempo real — importante

La bandeja del manager (pantalla "Incidencias reportadas") **carga al montar / al cambiar de
cuenta**, no se suscribe a cambios en vivo. Tras un `INSERT` de n8n, el manager **debe
refrescar la página (F5)** para verlo. No asumas que la incidencia aparecerá sola en pantalla
de forma instantánea.

---

## 6. "Petición de baja" — nota de flujo (no lo construyas en n8n)

Si `category = 'unavailability_request'`, n8n solo necesita insertar la incidencia como
cualquier otra. La conversión a una baja real (que dispara el motor de reasignación existente,
ver `docs/integrations/2026-08-05-n8n-telegram-subsistema-c.md`) la hace el **manager desde la
app**, vía la RPC `create_unavailability_from_incident` — eso ya crea la
`panelist_unavailability` y dispara el motor B. n8n no necesita llamar esa RPC ni conocer sus
detalles; solo dar de alta la incidencia.

---

## 7. Seguridad — recordatorio (decisión §1.b del spec de diseño)

La API key/credencial de servicio que use n8n para conectarse a `onems-dev`
(`sehbnpgzqljrsqimwyuz`) **debe vivir en un secreto gestionado en el propio n8n** (credencial
del nodo Postgres / variable de entorno), **nunca pegada en este documento ni en ningún otro
doc committeado al repo**. Este documento no incluye ninguna clave ni cadena de conexión real
— quien monte el workflow debe obtenerla del dashboard de Supabase y guardarla como credencial
en n8n, no como texto plano en ningún sitio versionado.

---

## 8. Reglas de seguridad (resumen para no romper prod)

- Antes de CUALQUIER escritura contra la BD desde n8n, ten claro el proyecto: `onems-dev`
  (`sehbnpgzqljrsqimwyuz`). No hay otra base.
- Deriva y filtra **siempre** por `account_id` en tus `INSERT`/`SELECT`/`UPDATE` manuales (el
  RLS no te protege como service-role).
- No escribas el plan de asignación a mano; eso es responsabilidad de la app del manager vía
  sus RPCs.
- Fotos: bucket privado `incident-photos`, guarda ruta (no URL), sube con service-role.
- No hay tiempo real: recuerda a quien opere el flujo que el manager necesita F5 tras un alta.
