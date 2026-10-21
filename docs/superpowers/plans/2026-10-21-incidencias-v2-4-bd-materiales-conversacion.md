# Incidencias v2 — Plan 4: Base de datos (conversación registrada + falta de material v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Una migración forward-only que añade el registro de conversación de todas las incidencias (`incident_message` + RPCs), enlaza todos los envíos de material con su incidencia, permite la recepción parcial, deja de cancelar la baja al recibir, calcula qué envíos del panelista quedan parados por falta de material y lleva el estado de las preguntas/recordatorios de Telegram.

**Architecture:** `supabase/migrations/20261021120000_incidents_conversation_materials.sql` con 5 secciones (una por tarea), estilo de `20261020170000_reported_incidents_v2.sql` (SECURITY DEFINER, `SET search_path = public`, `assert_same_account` o guarda `profiles`/`is_superadmin`, `REVOKE … FROM PUBLIC, anon` + `GRANT … TO authenticated, service_role`). Test `supabase/tests/incidents_conversation_materials.test.sql` con `fixtures/incident_city.sql`, un `BEGIN … ROLLBACK` por escenario, fechas relativas, aserciones con `DO … RAISE EXCEPTION 'FAIL …'` (nunca `CASE … 1/0`).

**Tech Stack:** PostgreSQL 17 (portable local 127.0.0.1:5433), Supabase onems-dev.

**Specs:** `docs/superpowers/specs/2026-10-21-incidencias-conversacion-design.md` (§2–§4) y `docs/superpowers/specs/2026-10-21-falta-material-v2-anexo-design.md` (§4–§6, §8b).

## Global Constraints

- Base única `onems-dev` `sehbnpgzqljrsqimwyuz`. **Aplicar solo en la Tarea 6, nombrando proyecto + ref y con confirmación explícita.** Nunca `db push`/`db reset`.
- Forward-only, una migración, timestamp `20261021120000`.
- Multi-tenant por `account_id`; n8n entra como service-role (`auth.uid()` NULL).
- Toda función nueva: `REVOKE ALL … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated, service_role` (salvo las marcadas "solo service_role").
- Tests: `bash supabase/tests/run_tests.sh incidents_conversation_materials`; 8 tests preexistentes fallan en local por falta de seed (consolidate_*, landing_tables, monitoring_*, poll_cron, readers_reader_id_unique, resolve_provider_reads); el resto debe pasar.
- Cantidad de material por muestra = `product_materials.quantity` del producto del plan de la muestra (así lo usa `calculatePanelistRequirements`).

## Review Focus

1. Recepción parcial seguida de recepción del resto: el stock suma exactamente lo recibido en total, nunca más que `quantity_sent`. *(Tarea 3)*
2. `refresh_material_hold` con stock que cubre la primera muestra pero no la segunda: libera solo la primera, por orden de fecha. *(Tarea 4)*
3. Incidencia con dos envíos (central + donante): recibir el primero NO la resuelve; recibir el segundo sí, y la baja enlazada sigue `active`. *(Tarea 3)*
4. `send_manager_message` de un usuario de otra cuenta → `Cross-tenant access denied`. *(Tarea 1)*
5. `log_incident_message` con `incident_kind`/`incident_id` inexistente → error claro, nada insertado. *(Tarea 1)*

---

### Task 1: `incident_message` y sus RPCs

**Files:** Create migration (sección 1) y test (escenario 1).

**Interfaces (produce):**
- Tabla `public.incident_message` (columnas del spec de conversación §2; `CHECK` de `incident_kind IN ('reported','unavailability')`, `direction IN ('outbound','inbound','internal')`, `author IN ('bot','panelist','manager','system')`, `status IN ('pending_send','sent','failed','received')`); índices `(incident_kind, incident_id, created_at)` y `(status) WHERE status = 'pending_send'`; RLS: SELECT `account_id = current_user_account_id() OR is_superadmin()`; sin INSERT/UPDATE directos para `authenticated`.
- `log_incident_message(p_incident_kind text, p_incident_id uuid, p_direction text, p_author text, p_body text, p_meta jsonb DEFAULT '{}', p_status text DEFAULT NULL) RETURNS uuid` — deriva `account_id` y `panelist_id` de `panelist_incident` o `panelist_unavailability`; inexistente → `'incident not found'`; `p_status` NULL → `'pending_send'` si outbound, `'received'` si inbound, `'sent'` si internal. `assert_same_account`.
- `send_manager_message(p_incident_kind text, p_incident_id uuid, p_body text) RETURNS uuid` — `outbound`/`manager`/`pending_send`, `meta.manager_user_id = auth.uid()`; `p_body` vacío → `'empty message'`. `assert_same_account`.
- `mark_incident_message_sent(p_id uuid, p_ok boolean, p_error text DEFAULT NULL, p_telegram_message_id text DEFAULT NULL) RETURNS void` — solo service_role (`REVOKE` a authenticated).
- `pending_incident_messages(p_limit int DEFAULT 50)` → filas `outbound` `pending_send` con `telegram_id` y `language` del panelista — solo service_role.

- [ ] Step 1: Test escenario 1: log de los 3 tipos sobre una `panelist_incident` y una `panelist_unavailability` de la fixture (estados por defecto correctos, `account_id`/`panelist_id` derivados); `'incident not found'`; `send_manager_message` como actor 99 (cuenta 1) OK y como actor 98 → `'Cross-tenant access denied'` (claims con `set_config('request.jwt.claim.sub', …, true)` como en `incident_move_to_cell.test.sql`); `'empty message'`; `mark_incident_message_sent` cambia a `sent`/`failed`; `pending_incident_messages` devuelve solo `pending_send` outbound; privilegios (anon false; authenticated false en las dos "solo service_role").
- [ ] Step 2: `bash supabase/tests/run_tests.sh incidents_conversation_materials` → FAIL (tabla inexistente).
- [ ] Step 3: Sección 1 de la migración.
- [ ] Step 4: → PASS.
- [ ] Step 5: Commit `feat(db): incident_message - conversacion registrada de todas las incidencias`.

### Task 2: Envíos de material enlazados y estado de preguntas

**Files:** sección 2 + escenario 2.

**Interfaces (produce):**
- `material_shipments`: columnas nuevas `panelist_incident_id uuid REFERENCES panelist_incident(id) ON DELETE SET NULL`, `source_notified_at timestamptz`, `ask_count int NOT NULL DEFAULT 0`, `last_asked_at timestamptz`, `next_ask_at timestamptz`; índice parcial `(next_ask_at) WHERE status IN ('pending','sent','partially_received')`.
- `material_shipments_status_check` añade `'partially_received'`.
- Relleno: para cada `panelist_incident` con `linked_material_shipment_id`, poner `panelist_incident_id` en ese envío.
- `due_material_questions(p_now timestamptz DEFAULT now())` → solo service_role. Filas `{shipment_id, kind, panelist_id, telegram_id, language, ask_count}` con `kind`:
  - `donor_send_request`: envío con `source_panelist_id` NOT NULL, `status='pending'`, enlazado a incidencia, y (`source_notified_at` NULL o `next_ask_at <= p_now`); el destinatario del mensaje es el donante.
  - `receipt_question`: `status IN ('sent','partially_received')` y `next_ask_at <= p_now`; destinatario el receptor.
- `record_material_question(p_shipment_id uuid, p_kind text) RETURNS void` — solo service_role: `ask_count += 1`, `last_asked_at = now()`, `next_ask_at = now() + interval '2 days'`, `source_notified_at = COALESCE(source_notified_at, now())` si `donor_send_request`.
- `send_material_shipment` (redefinida, mismo cuerpo) además fija `next_ask_at`: `expected_date` (00:00) si es central; `now() + 2 days` si es de donante; y `ask_count = 0`.

- [ ] Steps 1–5 (TDD como Tarea 1). Test: envío de donante sin notificar aparece como `donor_send_request`; tras `record_material_question` desaparece hasta `next_ask_at`; tras `send_material_shipment` pasa a `receipt_question` cuando vence; estado `partially_received` admitido. Commit `feat(db): envios de material enlazados a la incidencia y agenda de preguntas por Telegram`.

### Task 3: Recepción parcial y cierre sin cancelar la baja

**Files:** sección 3 + escenario 3.

**Interfaces (produce):**
- `receive_material_shipment_items(p_shipment_id uuid, p_items jsonb) RETURNS jsonb` — `p_items` = `[{material_id, quantity}]` con lo recibido **en esta confirmación**; suma a `material_shipment_items.quantity_received` (tope `quantity_sent`; exceso → `'quantity exceeds sent'`) y al stock del receptor exactamente lo sumado; `material_movements` `receipt` por la cantidad; estado `received` si todas las líneas completas, si no `partially_received`; `next_ask_at = now() + 2 days`, `ask_count = 0` si queda pendiente. Si el envío tiene `panelist_incident_id` y **todos** los envíos de esa incidencia están `received` → `resolve_panelist_incident(incidente, 'resolved', 'Material recibido', NULL)` y `log_incident_message(..., 'internal', 'system', …)`; **no toca la baja**. Llama a `refresh_material_hold(receptor)` (Tarea 4) y devuelve `{status, incident_resolved, released_detail_ids}`.
- `receive_material_shipment(p_shipment_id uuid)` (redefinida): recibe todo lo pendiente vía `receive_material_shipment_items` (compatibilidad con el botón actual); **deja de cancelar la baja**.

*(La Tarea 3 depende de `refresh_material_hold` de la Tarea 4: en la Tarea 3 crear un stub `refresh_material_hold(uuid) RETURNS uuid[]` que devuelve `'{}'` y que la Tarea 4 reemplaza.)*

- [ ] Steps 1–5. Test: Review Focus 1 y 3; exceso → error; botón antiguo recibe todo y la baja sigue `active`. Commit `feat(db): recepcion parcial de material y cierre de incidencia sin cancelar la baja`.

### Task 4: Envíos parados por falta de material

**Files:** sección 4 + escenario 4.

**Interfaces (produce):**
- Tabla `material_hold (allocation_plan_detail_id uuid PRIMARY KEY REFERENCES allocation_plan_details(id) ON DELETE CASCADE, account_id uuid NOT NULL, panelist_id uuid NOT NULL, held_since timestamptz NOT NULL DEFAULT now(), released_at timestamptz)`; RLS SELECT por cuenta.
- `refresh_material_hold(p_panelist_id uuid) RETURNS uuid[]` — si el panelista no tiene `panelist_incident` `missing_materials` en `open`/`in_progress`: libera todo lo retenido y devuelve esos ids. Si la tiene: recorre sus muestras como emisor (`origin_node_id` = su nodo, `status IN ('pending','notified')`, `fecha_programada >= current_date`) por `fecha_programada, id`, consumiendo una copia de su stock por material (`product_materials.quantity` del producto del plan); una muestra queda **retenida** si algún material no alcanza (y no consume); si alcanza, consume y queda libre. Inserta/actualiza `material_hold` (retenidas: `released_at = NULL`; antes retenidas y ahora libres: `released_at = now()`). Devuelve los ids **recién liberados** en esta llamada.
- `panelist_held_detail_ids(p_panelist_id uuid) RETURNS SETOF uuid` — retenidas actuales (para filtrar recordatorios en n8n).

- [ ] Steps 1–5. Test: Review Focus 2; sin incidencia abierta → nada retenido y libera; stock suficiente para todo → nada retenido; reemplaza el stub de la Tarea 3 y el escenario 3 sigue pasando (devuelve los liberados). Commit `feat(db): retener los envios del panelista que no puede cubrir con su stock`.

### Task 5: Avisos automáticos a la conversación

**Files:** sección 5 + escenario 5.

**Interfaces (produce):**
- `panelist_notification.kind` añade `'material_pending_released'`.
- Disparador `AFTER UPDATE OF status ON panelist_notification` — al pasar a `sent`, si `payload ? 'incident_kind'` y `payload ? 'incident_id'`, registra `outbound/bot/sent` con `body = payload->>'text'` (si no hay texto, `kind`) en `incident_message`.
- `resolve_panelist_incident` (redefinida, mismo comportamiento) además registra `internal/system` "Estado: {status}" y, si trae `p_reply_text`, lo registra como `outbound/manager/pending_send` (y deja `reply_status='none'` para que el workflow antiguo no lo envíe dos veces).

- [ ] Steps 1–5. Test: notificación con `incident_id` en payload → aparece en `incident_message` al pasar a `sent`; sin él → nada; `resolve_panelist_incident` con respuesta → mensaje manager pendiente y `reply_status='none'`. Commit `feat(db): los avisos y respuestas del manager quedan en la conversacion de la incidencia`.

### Task 6: Runbook y aplicación (con confirmación)

- [ ] Step 1: Pre-checks por Management API (solo lectura): firmas existentes de `send_material_shipment(uuid)`, `receive_material_shipment(uuid)`, `resolve_panelist_incident(uuid,text,text,text)`; cuerpos vivos = repo (`md5(pg_get_functiondef)` vs migraciones 20260807/20260806); filas actuales de `material_shipments.status` dentro del nuevo CHECK; ningún `panelist_notification` con `kind` fuera de la lista nueva.
- [ ] Step 2: Runbook `docs/database/2026-10-21-deploy-incidencias-conversacion-materiales.md` (qué cambia, pre-checks, post-checks, vuelta atrás).
- [ ] Step 3: Pedir confirmación ("aplicar `20261021120000_…` en onems-dev `sehbnpgzqljrsqimwyuz`"). No seguir sin un sí.
- [ ] Step 4: `apply_migration`; post-checks (tablas, funciones, privilegios anon=false).
- [ ] Step 5: Commit del runbook.
