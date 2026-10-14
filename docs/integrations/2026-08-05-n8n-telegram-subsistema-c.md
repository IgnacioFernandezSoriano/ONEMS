# Traspaso a n8n + Telegram — Subsistema C (Incidencias / disponibilidad de panelistas)

**Fecha:** 2026-08-05
**Para:** quien construya los workflows en el entorno n8n.
**Qué es esto:** todo lo que necesitas saber de ONEMS para enlazar el subsistema C
(pantalla del manager para resolver reasignaciones por baja de panelista) con n8n y Telegram.
No incluye nada de n8n en sí — solo el "contrato" con la base de datos ONEMS.

---

## 0. Resumen en una frase

Cuando un panelista se da de baja temporal, ONEMS genera **propuestas de reasignación**
(una por muestra afectada). Hoy el manager las resuelve en una pantalla web. Queremos que
n8n **avise por Telegram** y/o **permita resolver desde Telegram**, hablando con la misma
base de datos.

---

## 1. La base de datos (una sola, ojo con esto)

- **Proyecto Supabase:** `onems-dev`
- **project-ref:** `sehbnpgzqljrsqimwyuz`
- **Org:** "ONE for Regulators MS"
- Hay **UNA sola base**. "prod" y "dev" son solo la rama de código y el frontend desplegado:
  **apuntan a la misma BD**. No existe una base separada de staging.

### Cómo se conecta n8n (dos vías, ambas ya usadas en el repo)

1. **Nodo Postgres (conexión directa a la BD).** Es lo que usan los workflows actuales
   (`workflow_on_new_parcel_to_send`). Sirve para leer (`SELECT`) y para **llamar funciones**
   con `SELECT public.mi_funcion(...)`. Necesita la cadena de conexión Postgres del proyecto
   (host/pooler, puerto, usuario, password — desde el dashboard de Supabase → Database →
   Connection string). **Usa el pooler de Supabase**, no conexión directa al 5432 (bloqueada
   por firewall fuera de la red).
2. **Nodo HTTP → Edge Function.** Para funciones ya envueltas en Deno (`propose-reassignments`).
   Menos recomendable aquí: desde n8n conviene llamar la función SQL directamente por Postgres.

### ⚠️ Regla de oro multi-tenant (no te la saltes)

ONEMS es **multi-cuenta**. El aislamiento entre cuentas es por la columna **`account_id`**,
aplicada normalmente por Row Level Security (RLS). **PERO el nodo Postgres entra como
superusuario/service-role y SALTA el RLS.** Consecuencias:

- Cuando escribas `SELECT` a mano en n8n, **TÚ debes filtrar por `account_id`** en el `WHERE`.
  Si lo olvidas, mezclarás datos de cuentas distintas → fuga de datos entre reguladores.
- Las **funciones** (`apply_reassignment_proposal`, `list_reroute_candidates`,
  `generate_reassignment_proposals`) ya llevan el filtro de cuenta **dentro**: al llamarlas es
  seguro. El riesgo está solo en los `SELECT`/`UPDATE` que escribas tú.
- **Nunca** hagas `UPDATE`/`INSERT` directo sobre `allocation_plan_details` ni sobre las
  propuestas: usa siempre las funciones. Escribir el plan a mano se salta la lógica del motor.

---

## 2. Objetos de la BD que vas a usar

### Tablas (para leer)

**`panelist_unavailability`** — la baja declarada. Señal de "hay trabajo pendiente":
| Columna | Tipo / valores | Nota |
|---|---|---|
| `id` | uuid | PK de la baja |
| `account_id` | uuid | **filtrar por esto** |
| `panelist_id` | uuid | FK a `panelists` |
| `start_date`, `end_date` | date | rango de la baja |
| `reason` | texto | causa (vacation/sick_leave/…) |
| `status` | 'active' \| 'cancelled' | |
| `review_status` | **'pending_review'** \| 'reviewed' | ← el manager la marca 'reviewed' al terminar |

**`panelist_reassignment_proposal`** — una fila por muestra afectada por la baja:
| Columna | Tipo / valores | Nota |
|---|---|---|
| `id` | uuid | PK de la propuesta |
| `account_id` | uuid | **filtrar por esto** |
| `unavailability_id` | uuid | FK a la baja |
| `allocation_plan_detail_id` | uuid | la muestra concreta del plan |
| `affected_role` | 'origin' \| 'destination' | si la baja afecta al que envía o al que recibe |
| `suggested_action` | 'reroute' \| 'shift_date' \| 'cancel' \| 'none' | qué propone el motor |
| `suggested_target_node_id` | uuid \| null | nodo destino sugerido (si reroute) |
| `suggested_date` | date \| null | fecha nueva sugerida (si shift_date) |
| `suggested_reason` | texto (código) | **código i18n**, no texto legible (ver §5) |
| `status` | **'pending'** \| 'confirmed' \| 'dismissed' | estado de resolución |
| `final_action`, `final_target_node_id`, `final_date` | | lo que decidió el manager |

**`panelists`** — datos de contacto para Telegram:
| Columna | Nota |
|---|---|
| `telegram_id` | **chatId de Telegram**; puede ser NULL o '' → filtrar esos casos |
| `language` | 'en' \| 'es' \| 'fr' \| 'ar' → idioma del mensaje |
| `name`, `panelist_code`, `node_id` | identificación |

**`accounts`** — destino del manager:
| Columna | Nota |
|---|---|
| `email_panelist_manager` | email del manager de panelistas. **NO hay chat_id de Telegram del manager todavía** (ver §6, decisión pendiente) |

**`nodes`** — el nombre visible del nodo es **`nodes.auto_id`** (no hay `nodes.name`).

### Funciones (RPC) desplegadas y estables

Llámalas desde el nodo Postgres con `SELECT public.<nombre>(<args>);`

| Función | Firma | Para qué | Escribe? |
|---|---|---|---|
| `generate_reassignment_proposals` | `(p_unavailability_id uuid)` | Genera/regenera las propuestas de una baja (motor B). Devuelve nº generadas. | Sí (propuestas) |
| `apply_reassignment_proposal` | `(p_proposal_id uuid, p_final_action text, p_final_target_node_id uuid DEFAULT NULL, p_final_date date DEFAULT NULL)` | **Resuelve UNA propuesta** y mueve el plan en consecuencia. | Sí (plan + propuesta) |
| `list_reroute_candidates` | `(p_detail_id uuid, p_role text)` | Nodos alternativos de la misma ciudad, con `is_available` por fecha. **Solo lectura.** | No |
| `rpc_get_node_load_by_period` | `(p_account_id uuid, p_start_date date, p_end_date date, p_reference_load numeric DEFAULT 6, p_deviation_percent numeric DEFAULT 20)` | Carga de cada nodo por semana + semáforo de saturación. **Solo lectura.** | No |

**Mapeo de decisión → `apply_reassignment_proposal` (`p_final_action`):**
- Confirmar la sugerencia del motor → mandar su `suggested_action` ('reroute'/'shift_date'/'cancel'/'none').
- Cambiar manualmente a otro nodo → `'manual'` + `p_final_target_node_id`.
- Cambiar manualmente de fecha → `'manual'` + `p_final_date`.
- Descartar (no hacer nada con esa muestra) → `'none'`.
- Cancelar la muestra → `'cancel'`.

### Edge Function (alternativa, menos recomendada aquí)

`propose-reassignments` — `POST { "unavailability_id": "<uuid>" }`, cabecera `Authorization`.
Su propio código dice: *"n8n (futuro) usará service-role directamente, fuera de este wrapper"*.
→ Desde n8n, mejor llamar la RPC `generate_reassignment_proposals` directa por Postgres.

---

## 3. Patrón de mensajería que YA existe (cópialo)

En `docs/superpowers/plans/workflow_on_new_parcel_to_send.json` está el patrón validado
para avisar a panelistas por Telegram. La forma es:

1. **Nodo Postgres** que saca los destinatarios: `telegram_id` + `language` (+ los datos del
   mensaje). Ejemplo real del workflow de parcels:
   ```sql
   SELECT DISTINCT p_orig.telegram_id, p_orig.language AS panelist_language
   FROM v_allocation_details_with_availability v
   JOIN panelists p_orig ON p_orig.node_id = v.origin_node_id
   WHERE v.fecha_programada = CURRENT_DATE
     AND v.status = 'pending'
     AND p_orig.telegram_id IS NOT NULL AND p_orig.telegram_id != ''
   ```
2. **Nodo Telegram** con `chatId = {{ $json.telegram_id }}` y el `text` construido según
   `panelist_language` (el workflow arma el texto con una función por idioma en/es/fr/ar).

Reaprovecha esa estructura: cambia solo el `SELECT` de origen y el texto.

---

## 4. Las dos direcciones del enlace

### A) SALIDA — avisar por Telegram (bajo riesgo, calca lo existente)

- **Avisar al MANAGER de bajas nuevas por revisar:**
  ```sql
  SELECT u.id, p.name, p.panelist_code, u.start_date, u.end_date
  FROM panelist_unavailability u
  JOIN panelists p ON p.id = u.panelist_id
  WHERE u.review_status = 'pending_review'
    AND u.status = 'active'
    AND u.account_id = '<ACCOUNT_ID>';   -- ⚠️ filtrar cuenta
  ```
  → mensaje al chat del manager. **Falta definir el chat_id de Telegram del manager** (§6).

- **Avisar al PANELISTA de que su muestra se reasignó** (tras confirmar):
  ```sql
  SELECT pr.id, pr.final_action, pr.final_target_node_id, d.fecha_programada,
         pan.telegram_id, pan.language
  FROM panelist_reassignment_proposal pr
  JOIN allocation_plan_details d ON d.id = pr.allocation_plan_detail_id
  JOIN panelists pan ON pan.id = COALESCE(d.origin_panelist_id, d.destination_panelist_id)
  WHERE pr.status = 'confirmed'
    AND pr.updated_at > now() - interval '15 minutes'
    AND pr.account_id = '<ACCOUNT_ID>'    -- ⚠️ filtrar cuenta
    AND pan.telegram_id IS NOT NULL AND pan.telegram_id != '';
  ```
  → "Tu envío del {fecha} ahora sale desde el nodo {auto_id}".

### B) ENTRADA — resolver desde Telegram (más potente, más diseño)

Botones inline en Telegram (Confirmar / Descartar / Cambiar nodo). Al pulsarlos, un
**webhook de n8n** llama:
```sql
SELECT public.apply_reassignment_proposal(
  '<proposal_id>'::uuid, '<final_action>', '<target_node_id_o_null>'::uuid, NULL);
```
Para "Cambiar nodo" primero ofreces las alternativas con:
```sql
SELECT * FROM public.list_reroute_candidates('<detail_id>'::uuid, '<origin|destination>');
```
Esto convierte Telegram en un segundo frontend del subsistema C. Requiere pensar la seguridad
(quién puede pulsar), el estado de la conversación y el idempotente (no aplicar dos veces).

---

## 5. Idioma (i18n) — importante para los textos

- Los mensajes deben ir en el idioma del destinatario: `panelists.language` ('en'|'es'|'fr'|'ar';
  árabe es RTL).
- **`suggested_reason` de la propuesta es un CÓDIGO, no texto legible.** Los códigos son:
  `alt_node_same_city`, `shift_same_month`, `no_alt_no_date`, `reroute_reception`,
  `no_alt_reception`, `in_transit`. Si quieres mostrar el motivo en el mensaje de Telegram,
  traduce el código a cada idioma en el propio workflow (mini-diccionario), igual que hace la
  web. Las traducciones de referencia están en `public/locales/{en,es,fr,ar}.csv` bajo las
  claves `incidents.reason.*`.

---

## 6. Decisiones pendientes antes de construir (respóndelas y se concreta)

1. **Dirección:** ¿solo notificar (A), solo resolver desde Telegram (B), o ambas?
2. **Destinatario del aviso:** ¿al manager, a los panelistas afectados, o a ambos?
3. **Disparador:** ¿programado (cron, como parcels) o reactivo (webhook al declararse la baja /
   al confirmar el manager)?
4. **Chat de Telegram del manager:** hoy solo hay `accounts.email_panelist_manager` (email).
   Si el manager debe recibir por Telegram, hay que **añadir un campo con su chat_id** (nueva
   columna en `accounts` o tabla de config) — cambio de esquema pendiente de decidir y aprobar.

---

## 7. Datos de prueba (DEMO2)

- Baja de prueba usada en el desarrollo: `unavailability_id = ed403820-b518-4b0a-9c95-1f9ee64fcd58`.
- Para regenerar sus propuestas pendientes:
  `SELECT public.generate_reassignment_proposals('ed403820-b518-4b0a-9c95-1f9ee64fcd58');`

---

## 8. Reglas de seguridad (resumen para no romper prod)

- Antes de CUALQUIER escritura contra la BD desde n8n, ten claro el proyecto: `onems-dev`
  (`sehbnpgzqljrsqimwyuz`). No hay otra base.
- Filtra **siempre** por `account_id` en tus SELECT/UPDATE manuales (el RLS no te protege como
  service-role).
- Para mover el plan usa **solo** `apply_reassignment_proposal`; nunca UPDATE directo.
- Empieza en modo "solo lectura / solo notificar" (dirección A) y valida con la baja de prueba
  antes de habilitar la resolución desde Telegram (dirección B).
