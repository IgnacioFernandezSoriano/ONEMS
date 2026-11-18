# Deshacer en Allocation Plans — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Botón "Deshacer" en la lista de Allocation Plans que deshace, de una en una, hasta las 5 últimas acciones de la cuenta (incluido borrar muestras por compensar).

**Architecture:** Todas las acciones de la lista que se pueden deshacer pasan por funciones SECURITY DEFINER de la BD que, en la misma transacción, aplican el cambio y guardan la foto "antes" y "después" de las filas en `public.plan_undo_log` (máx. 5 por cuenta). `plan_undo_last` revierte la entrada más reciente fila a fila, saltando las filas que cambiaron después. El frontend sustituye sus escrituras directas por esas RPC y añade el botón.

**Tech Stack:** Postgres (Supabase, onems-dev `sehbnpgzqljrsqimwyuz`), plpgsql; React 18 + TS + supabase-js; vitest; tests SQL con Postgres portable local (127.0.0.1:5433).

**Spec:** `docs/superpowers/specs/2026-11-18-deshacer-allocation-plans-design.md`

## Global Constraints

- Una sola migración nueva: `supabase/migrations/20261118150000_plan_undo.sql`. Sustituye a `20261118150000_delete_deferred_samples.sql` (aún no aplicada; se borra ese fichero y `delete_deferred_samples` no existirá).
- Máximo **5** entradas por cuenta; deshacer siempre la **más reciente**; deshacer elimina la entrada; sin rehacer.
- Fila cambiada después de la acción ⇒ no se toca; el resto sí; se informa cuántas y cuáles.
- Acciones que entran: `delete` (envíos y muestras por compensar), `update` (bloque: nodo origen, nodo destino, fecha), `cancel` (bloque), `edit` (una fila), `create` (registro nuevo).
- NO entran: marcar enviado/recibido (`status` `sent`/`received`) ni reprocesar errores de transferencia.
- Autorización en todas las funciones: filas de `current_user_account_id()` o `is_superadmin()`; toda fila de una llamada debe ser de la misma cuenta, si no `RAISE EXCEPTION`.
- Muestras por compensar: solo `status = 'pending'`.
- Textos de UI en los 5 CSV `public/locales/{en,es,fr,ar,pt}.csv` (CRLF, comillas dobles escapadas `""`).
- Nada de escrituras en onems-dev sin confirmación explícita de Ignacio (proyecto + ref). No commit/push sin que lo pida.

## Review Focus

1. Deshacer un borrado cuando el balanceo ya volvió a crear una fila con el mismo id o la muestra ya fue reintroducida → esa fila se salta, no error.
2. Deshacer una edición cuando el bot marcó la fila como enviada después → se salta (la comparación es contra la foto "después" completa).
3. Dos managers pulsan Deshacer a la vez → cada pulsación deshace una entrada distinta (candado por cuenta), nunca la misma dos veces.
4. Superadmin con otra cuenta seleccionada → la pila y el botón son de la cuenta seleccionada.
5. Marcar enviado o registrar recepción desde la fila no crea entrada en la pila.

---

### Task 1: Diario y funciones en la BD

**Files:**
- Delete: `supabase/migrations/20261118150000_delete_deferred_samples.sql`
- Create: `supabase/migrations/20261118150000_plan_undo.sql`
- Create: `supabase/tests/plan_undo.test.sql`
- Modify: `supabase/tests/replay.ps1` (línea `$REPO = ...`: usar `$env:ONEMS_REPO` si existe, si no el valor actual)

**Interfaces:**
- Produces (todas `SECURITY DEFINER SET search_path = ''`, `GRANT EXECUTE ... TO authenticated`, revocado a `PUBLIC, anon`):
  - Tabla `public.plan_undo_log(id bigint identity pk, account_id uuid not null, user_id uuid, user_name text, action text check in ('delete','update','cancel','edit','create'), n_rows int not null, created_at timestamptz default now(), before_details jsonb not null default '[]', after_details jsonb not null default '[]', before_deferred jsonb not null default '[]')`. RLS activado; única política SELECT a `authenticated`: `account_id = current_user_account_id() OR is_superadmin()`. Sin permisos de escritura para `authenticated`.
  - `plan_action_update(p_ids uuid[], p_patch jsonb, p_action text) RETURNS integer` — `p_action` ∈ `update|cancel|edit`; aplica `p_patch` a las filas; claves permitidas = columnas de `allocation_plan_details` salvo `id, account_id, created_at, updated_at`; clave desconocida ⇒ excepción; `p_patch->>'status'` en (`sent`,`received`) ⇒ excepción. Devuelve filas cambiadas.
  - `plan_action_delete(p_detail_ids uuid[], p_deferred_ids uuid[]) RETURNS jsonb` → `{"details": n, "deferred": m}`.
  - `plan_action_create(p_row jsonb) RETURNS uuid` — inserta una fila (`account_id` del propio `p_row`, autorizado) y devuelve su id.
  - `plan_undo_last(p_account_id uuid) RETURNS jsonb` → `{"action": text, "restored": int, "skipped": int, "skipped_ids": uuid[]}`, o `NULL` si la pila está vacía.
- Todas las funciones de acción y `plan_undo_last` toman `pg_advisory_xact_lock(hashtext('plan_undo:' || account_id))`, guardan `user_name` de `profiles.full_name` de `auth.uid()` y, tras insertar, borran las entradas de la cuenta más allá de las 5 más recientes.
- Reversión en `plan_undo_last` (entrada más reciente de la cuenta, `FOR UPDATE`, se borra al final):
  - `update|cancel|edit`: por cada fila de `after_details`, si `to_jsonb(fila actual) = foto después` ⇒ restaurar todas las columnas desde `before_details`; si no existe o difiere ⇒ saltada.
  - `delete`: reinsertar cada fila de `before_details` / `before_deferred` (`jsonb_populate_record`) solo si no existe ya ese id; si existe ⇒ saltada.
  - `create`: borrar la fila solo si `to_jsonb(actual) = foto después`; si no ⇒ saltada.

- [ ] **Step 1: Write the failing test** `supabase/tests/plan_undo.test.sql` con el estilo de `gps_erase.test.sql` (`\ir fixtures/incident_city.sql`, `pg_temp.fail_if`, actor `99…99` vía `set_config('request.jwt.claim.sub', …, true)`), un bloque `BEGIN … ROLLBACK` por caso:
  1. `update` de 2 filas (`destination_node_id` → N3) ⇒ deshacer ⇒ ambas vuelven a su destino original; `restored = 2`, pila vacía.
  2. `delete` de 2 envíos + 1 `deferred_samples` pending ⇒ deshacer ⇒ los 3 vuelven con sus mismos ids y valores.
  3. `edit` y después `UPDATE status='sent'` directo en esa fila ⇒ deshacer ⇒ `skipped = 1`, `skipped_ids` contiene el id, la fila sigue `sent`.
  4. 6 acciones seguidas ⇒ `count(*) = 5` en `plan_undo_log` para la cuenta; 5 deshacer seguidos devuelven las acciones de la 6ª a la 2ª en orden; el 6º devuelve `NULL`.
  5. `create` ⇒ deshacer ⇒ la fila ya no existe.
  6. Actor `98…98` (cuenta 2) sobre ids de la cuenta 1 ⇒ excepción en `plan_action_update`, `plan_action_delete` y `plan_undo_last('a0…01')`.
  7. `plan_action_update` con `{"status":"sent"}` o con clave `"foo"` ⇒ excepción.
  8. `plan_action_delete` sobre una `deferred_samples` `reintroduced` ⇒ no la borra (`deferred = 0`).
- [ ] **Step 2: Run test to verify it fails.** Run (PowerShell): `$env:ONEMS_REPO='c:\Users\fernandezi\projects\ONEMS_wt_defdel'; powershell -File supabase\tests\replay.ps1; & C:\Users\fernandezi\pgportable\pgsql\bin\psql.exe -h 127.0.0.1 -p 5433 -U postgres -d onems_test -v ON_ERROR_STOP=1 -f supabase\tests\plan_undo.test.sql` (con `$env:PGPASSWORD='postgres'`). Expected: replay OK, test FAIL (función inexistente).
- [ ] **Step 3: Implement the migration** con las interfaces de arriba. Comentarios en español explicando el porqué (decisión de Ignacio 18/11/2026).
- [ ] **Step 4: Run test to verify it passes.** Mismo comando. Expected: sin `FAIL:`, salida limpia.
- [ ] **Step 5: Commit** `feat(allocation): diario de deshacer (5 acciones por cuenta) y borrado de muestras por compensar`.

### Task 2: Frontend — acciones por RPC y botón Deshacer

**Files:**
- Create: `src/lib/planUndo.ts`, `src/lib/__tests__/planUndo.test.ts`
- Modify: `src/lib/hooks/useAllocationPlanDetails.ts`, `src/pages/AllocationPlans.tsx`, `public/locales/{en,es,fr,ar,pt}.csv`

**Interfaces:**
- Consumes: las 4 RPC y la tabla de la Task 1.
- Produces en `src/lib/planUndo.ts`:
  - `type UndoAction = 'delete' | 'update' | 'cancel' | 'edit' | 'create'`
  - `interface UndoEntry { id: number; action: UndoAction; n_rows: number; user_name: string | null; created_at: string }`
  - `fetchLastUndo(accountId: string): Promise<UndoEntry | null>` — `select id, action, n_rows, user_name, created_at` (nunca las columnas jsonb) de `plan_undo_log`, `account_id = accountId`, orden `created_at desc, id desc`, `limit 1`.
  - `undoLast(accountId: string): Promise<{ action: UndoAction; restored: number; skipped: number; skipped_ids: string[] } | null>`
  - `undoLabel(entry: UndoEntry, t: (k: string, p?: Record<string, unknown>) => string): string` — pura: `t('allocation_plans.undo_label', { action: t('allocation_plans.undo_action_' + entry.action), count: entry.n_rows, user: entry.user_name || '—', time: HH:mm local })`.

- [ ] **Step 1: Write the failing test** `src/lib/__tests__/planUndo.test.ts`: `undoLabel` con `t` falso que devuelve `key|JSON(params)`: para `{action:'delete', n_rows:164, user_name:'Ana', created_at:'2026-11-18T09:32:00Z'}` el resultado contiene `allocation_plans.undo_action_delete`, `"count":164`, `"user":"Ana"`; con `user_name: null` contiene `"user":"—"`.
- [ ] **Step 2: Run** `npm test -- planUndo` ⇒ FAIL (módulo inexistente).
- [ ] **Step 3: Implement** `planUndo.ts` y cambia el hook:
  - `bulkUpdateDetails(ids, updates, action: 'update' | 'cancel' = 'update')` → `rpc('plan_action_update', { p_ids, p_patch: updates, p_action })`; si `ids` vacío, no llama.
  - `bulkDeleteDetails(ids, deferredIds)` → una sola `rpc('plan_action_delete', …)` (sustituye los borrados uno a uno y la llamada a `delete_deferred_samples`); mantiene `notifyDeferredSamplesChanged()` si `deferredIds` no vacío.
  - `createDetail` → `rpc('plan_action_create', { p_row: validFields })`, devuelve la fila leída por id.
  - `updateDetail(id, updates)`: si `updates.status` es `sent` o `received` ⇒ camino directo actual (sin pila); si no ⇒ `rpc('plan_action_update', { p_ids: [id], p_patch: updates, p_action: 'edit' })`. `markAsSent` sigue sin pila.
  - Página: `handleBulkCancel` pasa `'cancel'`. Estado `lastUndo: UndoEntry | null`, recargado con `fetchLastUndo(effectiveAccountId)` al montar, tras cada acción y tras deshacer. Botón "Deshacer" (icono `Undo2` de lucide) junto a "Export CSV", deshabilitado si `lastUndo` es null, `title = undoLabel(...)`; al pulsar `confirm(t('allocation_plans.undo_confirm', { label }))`, llama `undoLast`, `alert` con `undo_done` (`restored`) y, si `skipped > 0`, `undo_skipped` (`count`), luego recarga datos y `lastUndo`.
  - Claves nuevas (5 idiomas): `allocation_plans.undo`, `undo_confirm` ("¿Deshacer {label}?"), `undo_done` ("Deshecho: {count} registros restaurados"), `undo_skipped` ("{count} registros no se han tocado porque cambiaron después"), `undo_label` ("{action} {count} registros · {user} · {time}"), `undo_action_delete|update|cancel|edit|create` (Borrar / Cambiar / Cancelar / Editar / Crear).
- [ ] **Step 4: Verify** `npm test -- planUndo` PASS; `npm run build` OK; `npx eslint` sobre los ficheros tocados sin avisos nuevos.
- [ ] **Step 5: Commit** `feat(allocation): botón Deshacer (últimas 5 acciones de la cuenta)`.

### Task 3: Puesta en producción (requiere confirmaciones de Ignacio)

- [ ] Pedir confirmación y aplicar `20261118150000_plan_undo.sql` en onems-dev `sehbnpgzqljrsqimwyuz` (`apply_migration`).
- [ ] Verificar en vivo: la tabla existe con RLS; `authenticated` sin INSERT/UPDATE/DELETE en `plan_undo_log`; las 4 funciones con EXECUTE para `authenticated` y no para `anon`.
- [ ] Commit + push de la rama `feat/borrar-compensacion` cuando Ignacio lo pida; darle todos los campos del PR (base `develop`).
