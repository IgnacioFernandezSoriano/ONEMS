# Claves de la API E2E protegidas — Plan de implementación (fase previa de Carrier Link)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que las claves de la API de extracción E2E se guarden hasheadas, con nombre, ámbito y caducidad, y que la API funcione de verdad.

**Architecture:** La clave se genera y se valida dentro de la base con dos funciones (`api_key_issue`, `api_key_resolve`); la tabla guarda solo el hash SHA-256 y un prefijo. La Edge Function `onedb-api` deja de leer la tabla directamente y llama a `api_key_resolve`. Las 6 claves actuales siguen valiendo: se calcula su hash y después se borra el texto en claro.

**Tech Stack:** Postgres 17 (pgcrypto), Supabase Edge Functions (Deno), React + TypeScript.

**Spec:** `docs/superpowers/specs/2026-11-19-carrier-link-design.md` (D15, §3.2 `api_keys`, §9 fase previa).

## Global Constraints

- Única base: `onems-dev` (`sehbnpgzqljrsqimwyuz`). **Ninguna escritura remota (migración, deploy) sin confirmación explícita del responsable**; el plan se desarrolla y valida en el Postgres local (`bash supabase/tests/run_tests.sh <test>`).
- Rama `feat/api-e2e-claves` desde `develop`, en un worktree propio. No commitear en `main` ni `develop`.
- Migraciones solo hacia delante, con timestamp posterior a `20261119100200`.
- Funciones `SECURITY DEFINER` con `SET search_path = public, extensions` y `REVOKE ALL ... FROM PUBLIC, anon`.
- Nunca escribir una clave real en el repo, en un test ni en el chat.
- Todo texto de pantalla pasa por `useTranslation()` y se añade en los 5 idiomas (en, es, fr, ar, pt), igual que se hizo con `roles_access.*` (commit 3aa38c0).
- `npm run lint` y `npm run build` deben pasar.

## Review Focus

- Clave caducada o desactivada: `api_key_resolve` no devuelve fila.
- Una clave antigua (emitida antes del cambio) sigue funcionando tras el paso a hash.
- Un usuario con `e2e_db_api` solo en `view` no puede emitir ni desactivar claves.
- La clave en claro no se puede leer por ninguna vía después de emitirla (ni `select`, ni la función de listado).
- `onedb-api` con clave válida de la cuenta A nunca devuelve filas de la cuenta B.

---

### Task 1: Hash, metadatos y funciones de clave

**Files:**
- Create: `supabase/migrations/20261120100000_api_keys_hash.sql`
- Test: `supabase/tests/api_keys_hash.test.sql`

**Interfaces:**
- Produces:
  - Columnas en `api_keys`: `key_hash text UNIQUE`, `key_prefix text`, `name text`, `scope text NOT NULL DEFAULT 'onedb_read' CHECK (scope IN ('onedb_read','carrier_feed'))`, `feed_id uuid` (sin FK todavía; la añade el plan de Carrier Link), `expires_at timestamptz`. `api_key` pasa a nullable.
  - `api_key_issue(p_account_id uuid, p_name text, p_scope text DEFAULT 'onedb_read', p_feed_id uuid DEFAULT NULL, p_expires_at timestamptz DEFAULT NULL) RETURNS TABLE (id uuid, api_key text)`. Permite a superadmin o a quien tenga `has_any_access(p_account_id,'edit','e2e_db_api')`. Formato de la clave: `'onems_' || encode(gen_random_bytes(24),'hex')`. Guarda `key_hash`, `key_prefix = left(clave, 12)`, `created_by = auth.uid()`; no guarda la clave.
  - `api_key_resolve(p_key text) RETURNS TABLE (id uuid, account_id uuid, scope text, feed_id uuid)`. Solo `service_role`. Devuelve fila si `is_active` y (`expires_at IS NULL OR expires_at > now()`), buscando por `encode(digest(p_key,'sha256'),'hex')`.
  - Backfill: `key_hash` y `key_prefix` de las filas existentes a partir de `api_key`; `name = 'Clave ' || key_prefix`.

- [ ] **Step 1: Escribir el test** (patrón de `supabase/tests/account_access.test.sql`: `pg_temp.fail_if`, `pg_temp.as_user`, `pg_temp.raises`, fixture `fixtures/incident_city.sql`, todo dentro de `BEGIN … ROLLBACK`). Aserciones:
  - una fila previa con `api_key='legacy-key-1'` insertada antes de simular el backfill (`UPDATE` del backfill re-ejecutable) resuelve con `api_key_resolve('legacy-key-1')` a su cuenta;
  - `api_key_issue` como AM de A1 devuelve una clave que empieza por `onems_`, y la fila creada tiene `api_key IS NULL`, `key_hash` de 64 caracteres y `key_prefix = left(clave,12)`;
  - `api_key_resolve(clave)` devuelve la cuenta A1 y `scope='onedb_read'`;
  - con `is_active=false` no devuelve fila; con `expires_at = now() - interval '1 minute'` tampoco;
  - `pg_temp.raises` es true al llamar `api_key_issue` como usuario sin rol de A1 y como AM de A1 pidiendo la cuenta A2;
  - `api_key_issue(..., p_scope => 'otro')` falla.
- [ ] **Step 2:** `bash supabase/tests/run_tests.sh api_keys_hash` → FAIL (la función no existe).
- [ ] **Step 3: Escribir la migración** con las columnas, el backfill, las dos funciones y sus `REVOKE`/`GRANT` (`api_key_issue` a `authenticated`; `api_key_resolve` solo a `service_role`).
- [ ] **Step 4:** `bash supabase/tests/run_tests.sh api_keys_hash account_access_writes` → PASS (el segundo comprueba que las políticas de `api_keys` no se han roto).
- [ ] **Step 5: Commit** `feat(api): claves de API hasheadas con ámbito y caducidad`.

### Task 2: `onedb-api` valida por hash y lee la tabla correcta

**Files:**
- Modify: `supabase/functions/onedb-api/index.ts`
- Create: `supabase/functions/onedb-api/lib.ts`, `supabase/functions/onedb-api/lib.test.ts`
- Modify: `supabase/config.toml` (bloque `[functions.onedb-api]` con `verify_jwt = false`)

**Interfaces:**
- Consumes: `api_key_resolve` (Task 1).
- Produces: `parseQuery(url: URL): { ok: true; startDate: string; endDate: string; limit: number; offset: number; source: 'panelist'|'carrier'|null } | { ok: false; error: string }` en `lib.ts`. `source` se acepta ya como parámetro opcional, pero el filtro solo se aplica si la columna existe (la crea el plan de Carrier Link): en este plan se valida el valor y se ignora.

Hechos comprobados en `origin/main`: la función consulta `.from('onedb')` y la columna `sent`, que no existen (la tabla es `one_db`, la columna `sent_at`), y está desplegada con `verify_jwt = true`, que rechaza una clave que no sea un JWT. Hoy la API no puede responder.

- [ ] **Step 1: Test** `lib.test.ts` (patrón de `supabase/functions/rfid-provider-poll/lib.test.ts`): fechas ausentes → error; formato distinto de `YYYY-MM-DD` → error; `limit=5000` → 1000; `source=otro` → error; `source=carrier` → `'carrier'`.
- [ ] **Step 2:** `deno test supabase/functions/onedb-api/lib.test.ts` → FAIL.
- [ ] **Step 3: Implementar** `lib.ts` y cambiar `index.ts`: resolver la clave con `supabaseClient.rpc('api_key_resolve', { p_key })` exigiendo `scope === 'onedb_read'`; consultar `.from('one_db')` filtrando y ordenando por `sent_at` (`gte startDate`, `lt` día siguiente a `endDate`); la actualización de `last_used_at`/`usage_count` pasa a un único `update` sin leer antes la fila.
- [ ] **Step 4:** `deno test supabase/functions/onedb-api/lib.test.ts` → PASS.
- [ ] **Step 5: Commit** `fix(onedb-api): validar clave por hash y leer one_db`.

### Task 3: Pantalla de claves: emitir, mostrar una vez, listar sin la clave

**Files:**
- Modify: `src/hooks/useOneDBAPI.ts` y la página que lo usa
- Modify: ficheros de traducción de los 5 idiomas

**Interfaces:**
- Consumes: `api_key_issue` (Task 1).

- [ ] **Step 1:** En `useOneDBAPI.ts`, la creación pasa a `supabase.rpc('api_key_issue', { p_account_id, p_name })`; el listado selecciona `id, name, key_prefix, scope, is_active, created_at, last_used_at, usage_count, expires_at` (nunca `api_key`).
- [ ] **Step 2:** La página pide un nombre al crear, muestra la clave completa **una sola vez** con botón de copiar y el aviso de que no se podrá volver a ver; en la lista aparece `key_prefix…` y el nombre.
- [ ] **Step 3:** Claves nuevas de traducción en los 5 idiomas.
- [ ] **Step 4:** `npm run lint && npm run build && npm test` → sin errores nuevos (el fallo previo de `rfid-provider-poll/lib.test.ts` bajo vitest y el aviso de `accountScope.ts` son anteriores a este plan).
- [ ] **Step 5: Commit** `feat(api): emitir claves con nombre y mostrarlas una sola vez`.

### Task 4: Retirar el texto en claro

**Files:**
- Create: `supabase/migrations/20261120100100_api_keys_drop_plaintext.sql`
- Modify: `supabase/tests/api_keys_hash.test.sql`

- [ ] **Step 1:** Añadir al test: la columna `api_key` no existe en `information_schema.columns`; la clave heredada sigue resolviendo.
- [ ] **Step 2:** Migración: `ALTER TABLE public.api_keys ALTER COLUMN key_hash SET NOT NULL; ALTER TABLE public.api_keys DROP COLUMN api_key;`
- [ ] **Step 3:** `bash supabase/tests/run_tests.sh api_keys_hash` → PASS.
- [ ] **Step 4: Commit** `chore(api): eliminar la clave en claro`.

### Puesta en producción (cada paso con confirmación explícita sobre `onems-dev` `sehbnpgzqljrsqimwyuz`)

1. Aplicar la migración de Task 1.
2. Desplegar `onedb-api` con `verify_jwt = false`. Probar con una clave recién emitida: 200 y datos solo de su cuenta.
3. PR `feat/api-e2e-claves` → `develop` → `main` (los abre el responsable).
4. Con la web nueva ya publicada, aplicar la migración de Task 4.
