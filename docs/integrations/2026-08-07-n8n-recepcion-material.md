# Traspaso a n8n + Telegram — Recepción de material (tratamiento "falta de materiales")

**Fecha:** 2026-08-07
**Para:** quien construya los workflows en el entorno n8n.
**Qué es esto:** el "contrato" con la BD de ONEMS para el diálogo bidireccional con el
panelista alrededor del **envío de material de reposición**: aviso de que el material va en
camino, confirmación de recepción por Telegram, y consulta de stock para reconciliación. No
incluye nada de n8n en sí — solo qué leer/escribir/llamar contra `onems-dev`.

Este flujo es la continuación natural de la incidencia `missing_materials` documentada en
`docs/integrations/2026-08-06-n8n-incidencias-reportadas.md`: el panelista reporta que le
falta material → el manager (o el motor de tratamiento) genera un `material_shipments` →
este documento cubre desde que ese envío se marca `sent` hasta que el panelista confirma
recepción y n8n cierra el ciclo.

---

## 0. Resumen en una frase

Cuando el manager marca un envío de material como enviado (`sent`), n8n avisa al panelista
por Telegram usando el **mismo canal de vuelta** que ya usa el flujo de incidencias
(`panelist_incident.reply_to_panelist` / `reply_status`). Cuando el panelista confirma que lo
recibió, n8n llama a la RPC `receive_material_shipment(p_shipment_id)`, que acredita el stock
del panelista, cierra la baja asociada (si la había) y resuelve la incidencia vinculada — todo
en una sola llamada idempotente. Para la reconciliación de stock, n8n puede leer directamente
`panelist_material_stocks`.

---

## 1. La base de datos (una sola, ojo con esto)

- **Proyecto Supabase:** `onems-dev`
- **project-ref:** `sehbnpgzqljrsqimwyuz`
- **Org:** "ONE for Regulators MS"
- Hay **UNA sola base**. "prod" y "dev" son solo la rama de código y el frontend desplegado:
  **apuntan a la misma BD**. No existe una base separada de staging.

### ⚠️ Regla de oro multi-tenant (no te la saltes)

ONEMS es **multi-cuenta**, aislado por `account_id`, normalmente vía RLS. El nodo de n8n que
llame `receive_material_shipment` entra con la **service-role key**, que **salta el RLS**. La
propia RPC deriva el `account_id` del envío y llama internamente a
`assert_same_account(...)`, así que no puedes usarla para tocar un envío de otra cuenta — pero
en cualquier `SELECT` manual que hagas (p. ej. la consulta de stock del §4), **tú debes seguir
filtrando por `account_id`** a mano: el service-role no lo hace por ti.

---

## 2. Flujo 1 — Aviso "material en camino" (ONEMS → n8n → Telegram)

Cuando el manager marca un envío como `sent` (o el motor de tratamiento lo hace
automáticamente), ONEMS debe dejar sobre la incidencia vinculada:

- `panelist_incident.reply_to_panelist` = texto del aviso ("tu material ya va en camino…")
- `panelist_incident.reply_status` = `'pending_send'`

Esto es **exactamente el mismo mecanismo** que documenta
`docs/integrations/2026-08-06-n8n-incidencias-reportadas.md` §4 — no hay un canal nuevo. n8n
sigue haciendo polling (cron) sobre:

```sql
SELECT id, panelist_id, reply_to_panelist
FROM panelist_incident
WHERE reply_status = 'pending_send'
  AND account_id = '<ACCOUNT_ID>';   -- filtrar cuenta, no te lo saltes
```

Para cada fila: buscar `telegram_id`/`language` en `panelists`, enviar `reply_to_panelist` por
Telegram, y marcar:

```sql
UPDATE panelist_incident
SET reply_status = 'sent', reply_sent_at = now()
WHERE id = '<id>';
```

n8n no necesita saber nada específico de "envío de material" para este paso: es el flujo de
respuesta genérico de incidencias, reutilizado.

> **Nota de estado (importante para quien conecte esto):** a fecha de este documento, el RPC
> `send_material_shipment` (que la app llama al marcar un envío como `sent`) **todavía no
> escribe** `reply_to_panelist`/`reply_status='pending_send'` sobre la incidencia vinculada —
> solo mueve stock y cambia `material_shipments.status`. Ese "enganche" (escribir el aviso al
> pasar a `sent`) es trabajo pendiente de otra tarea del plan, no de este documento. Si al
> montar el workflow no ves filas `pending_send` apareciendo cuando se envía material, esa es
> la causa: falta cablear la escritura del aviso, no un problema de n8n.

---

## 3. Flujo 2 — Confirmación de recepción (Telegram → n8n → RPC)

Cuando el panelista confirma por Telegram que recibió el material, n8n llama:

```js
await supabase.rpc('receive_material_shipment', { p_shipment_id: '<shipment_id>' })
```

con la **service-role key**. Esta es la única escritura que hace falta — no hay que tocar
`material_shipments`, `panelist_material_stocks`, `panelist_unavailability` ni
`panelist_incident` a mano.

### Qué hace la RPC (para que sepas qué esperar, no para reimplementarla)

Definida en `supabase/migrations/20260807100100_material_shipment_lifecycle_rpcs.sql` y
extendida (versión vigente) en `supabase/migrations/20260807100200_materials_treatment_close.sql`:

1. Bloquea la fila del envío (`for update`) y valida que pertenece a la cuenta actual.
2. **Idempotente:** si el envío ya está `status = 'received'`, no hace nada y retorna
   silenciosamente — **reintentos seguros**. Si está en un estado que no es `pending` ni
   `sent` (p. ej. `cancelled`), lanza una excepción (n8n verá el error de la llamada RPC).
3. Por cada ítem del envío: acredita `panelist_material_stocks` (upsert, suma cantidad),
   marca `quantity_received` en `material_shipment_items`, y registra un movimiento
   `'receipt'` en `material_movements`.
4. Marca `material_shipments.status = 'received'` y `received_date = now()`.
5. **Si el envío está enlazado a una incidencia** (`panelist_incident.linked_material_shipment_id
   = p_shipment_id`):
   - si esa incidencia tiene una baja asociada (`linked_unavailability_id`) en estado
     `active`, la pasa a `status = 'cancelled'` (esto dispara el undo del motor de
     reasignación: revierte reroutes, descarta propuestas pendientes — mismo mecanismo que
     cualquier cancelación de baja);
   - resuelve la incidencia (`resolve_panelist_incident(..., 'resolved', 'Material recibido;
     disponibilidad restaurada.', null)`), dejando lista una respuesta pendiente de envío al
     panelista por el mismo canal del §2 si `resolve_panelist_incident` la genera.

Si el envío **no** está enlazado a ninguna incidencia (p. ej. reposición proactiva sin
incidencia previa), la RPC solo hace los pasos 1-4: acredita stock y marca el envío como
recibido, sin tocar bajas ni incidencias.

### Permisos

```sql
grant execute on function public.receive_material_shipment(uuid) to authenticated, service_role;
```

Confirmado en ambas migraciones (la original y la que la reemplaza con el cierre de
tratamiento) — **service_role puede llamarla**, así que n8n no necesita ninguna migración de
corrección para esto.

---

## 4. Flujo 3 — Consulta de stock para reconciliación

n8n puede leer `panelist_material_stocks` directamente para soportar el paso de
reconciliación (comparar lo que el panelista dice tener contra lo que registra ONEMS):

```sql
SELECT panelist_id, material_id, quantity, last_updated
FROM panelist_material_stocks
WHERE account_id = '<ACCOUNT_ID>'   -- obligatorio: sin RLS activo, filtra tú
  AND panelist_id = '<panelist_id>';
```

No hay una RPC dedicada para esto — es una lectura directa. El valor de stock ya vive en
Supabase; n8n solo lo consulta, no lo recalcula ni lo escribe (salvo indirectamente, vía la
RPC del §3).

---

## 5. Seguridad

- La credencial de servicio que use n8n para conectarse a `onems-dev` (`sehbnpgzqljrsqimwyuz`)
  **debe vivir en un secreto gestionado en el propio n8n** (credencial del nodo Postgres /
  variable de entorno de la llamada RPC), **nunca pegada en este documento ni en ningún otro
  doc committeado al repo**. Este documento no incluye ninguna clave ni cadena de conexión
  real.
- **RLS pendiente sobre las tablas de stock:** a fecha de este documento, `material_stocks` y
  `panelist_material_stocks` **no tienen Row Level Security activado** (hay una tarea
  planificada, "Task 11" del plan de tratamiento de materiales, para activarlo). El
  service-role de n8n **bypassa el RLS igualmente** una vez esté activo — así que el flujo de
  este documento (lectura del §4, escritura vía RPC del §3) seguirá funcionando sin cambios
  cuando se active. El riesgo real de RLS-desactivado es otro: mientras tanto, cualquier
  cliente `anon`/`authenticated` sin política explícita podría leer stock entre cuentas. Quien
  monte el workflow de n8n no tiene que hacer nada por esto — es una nota para que no se
  interprete la ausencia de RLS como "n8n necesita algo distinto" — pero si construyes
  cualquier lectura desde el frontend (no desde n8n) contra estas tablas, ten en cuenta que
  hoy no está aislada por cuenta a nivel de BD.

---

## 6. Reglas de seguridad (resumen para no romper prod)

- Antes de CUALQUIER escritura contra la BD desde n8n, ten claro el proyecto: `onems-dev`
  (`sehbnpgzqljrsqimwyuz`). No hay otra base.
- Para confirmar recepción, llama **siempre** la RPC `receive_material_shipment` — no
  actualices `material_shipments`/`panelist_material_stocks`/`panelist_unavailability` a mano.
  La RPC ya es idempotente: si no estás seguro de si una llamada anterior llegó a completarse,
  vuelve a llamarla, es seguro.
- Deriva y filtra **siempre** por `account_id` en las lecturas manuales (stock, polling de
  `reply_to_panelist`) — el RLS no te protege como service-role, y para stock ni siquiera está
  activado todavía.
- No hay tiempo real en la pantalla del manager: tras la recepción, la pantalla de tratamiento
  de materiales necesita refresco para reflejar el cambio (mismo patrón que el resto de
  ONEMS).
