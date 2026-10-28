# Incidencias de indisponibilidad — Plan 1/3: base de datos

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que toda baja de panelista se convierta en una incidencia con estado, que la BD resuelva sola lo que pueda (retrasar / otro nodo de la ciudad sin saturar), deje al manager solo lo que no, encole avisos Telegram y exponga a n8n una puerta de entrada única.

**Architecture:** Todo en Postgres (funciones plpgsql SECURITY DEFINER + triggers), sobre las tablas que ya existen: `panelist_unavailability` = incidencia, `panelist_reassignment_proposal` = líneas. Motor determinista que **aplica** cambios al plan conforme los decide (así la carga que consulta ya incluye lo asignado). Cola `panelist_notification` que n8n vacía. Migraciones forward-only validadas en el Postgres local 5433 con tests `.sql`.

**Tech Stack:** Postgres 17 (Supabase onems-dev `sehbnpgzqljrsqimwyuz`), plpgsql, psql + scripts `supabase/tests/`, Postgres portable local `C:\Users\fernandezi\pgportable` (127.0.0.1:5433, user `postgres`, pass `postgres`).

**Spec:** `docs/superpowers/specs/2026-10-20-incidencias-indisponibilidad-resolucion-automatica-design.md`

## Global Constraints

- Una sola BD: **onems-dev `sehbnpgzqljrsqimwyuz`**. Nada se aplica en remoto sin nombrar proyecto+ref y confirmación explícita del usuario. NUNCA `supabase db push` / `db reset`.
- Migraciones forward-only en `supabase/migrations/YYYYMMDDHHMMSS_*.sql`, timestamp > `20261015120000`. No tocar el baseline. El borrador `20261020120000_unavailability_refresh_and_declare.sql` y su test `unavailability_refresh_and_declare.test.sql` se **borran** en la Tarea 1 (se rehacen aquí).
- Cada tarea: test SQL que falla → migración → test pasa → los tests anteriores siguen pasando → commit en `develop`.
- Envíos solo lunes a viernes (`extract(isodow from d) between 1 and 5`).
- Nunca tocar muestras `sent`/`received`. Nunca mover a otra ciudad. Nunca bloquear INSERT/UPDATE del plan (triggers best-effort: `EXCEPTION WHEN OTHERS THEN RAISE WARNING`).
- Multi-tenant: toda función que un usuario pueda llamar comprueba `is_superadmin()` o misma `account_id` que `profiles.account_id` de `auth.uid()`. `anon` no ejecuta nada nuevo.
- Umbral de saturación semanal: `p_reference_load * (1 + 1.5 * p_deviation_percent / 100)`; por defecto 6 / 20 → 7,8. Un nodo se descarta si `carga_semana + 1 > umbral`.
- Carga semanal de un nodo = filas de `allocation_plan_details` con `fecha_programada` en lunes..domingo de esa semana, `status <> 'cancelled'`, donde el nodo es `origin_node_id` **o** `destination_node_id`.
- Semana actual = `date_trunc('week', current_date)::date` .. `+6`.
- Commits: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. Baja cuyo nodo no tiene panelista activo (`panelists.node_id` null o panelista inactivo): el motor no debe fallar ni crear líneas; incidencia `auto_resolved` con resumen "sin muestras". → test en Tarea 4.
2. Dos muestras del mismo nodo el mismo día, ambas afectadas: el paso 1 debe repartirlas en días distintos y no apilarlas. → test en Tarea 4.
3. Una muestra ya `notified` que se mueve debe volver a `pending` y refrescar `origin_panelist_name`/`destination_panelist_name`; si no, el aviso diario de n8n nunca la avisará. → test en Tarea 3.
4. El trigger de refresco por cambio de plan NO debe reaccionar a los UPDATE que hace el propio motor/manager (`reassigned_at` cambia), ni a cambios de `status` solos. → tests en Tarea 6.
5. Cancelar la baja debe devolver fecha y nodos originales y reactivar (`cancelled`→`pending`) solo lo que anuló este motor y no haya salido; una muestra anulada por otra vía no se toca. → test en Tarea 6.

---

### Task 1: Infraestructura de pruebas y limpieza del borrador

**Files:**
- Create: `supabase/tests/run_tests.sh`
- Create: `supabase/tests/fixtures/incident_city.sql`
- Delete: `supabase/migrations/20261020120000_unavailability_refresh_and_declare.sql`, `supabase/tests/unavailability_refresh_and_declare.test.sql`

**Interfaces:**
- Produces: `bash supabase/tests/run_tests.sh [test_name ...]` → reconstruye `onems_t` (shim + baseline + todas las migraciones) y ejecuta los tests dados (o todos `*.test.sql` si no se dan), imprimiendo `PASS`/`FAIL` por test y saliendo con código ≠ 0 si alguno falla.
- Produces: fixture `\ir fixtures/incident_city.sql` (ruta relativa al test) con estos ids fijos:
  - cuenta `a0000000-0000-0000-0000-000000000001`; región `e000…01`
  - ciudad C1 `c1000000-0000-0000-0000-000000000001` con nodos N1 `b1000000-…01` (panelista P1 `e1000000-…01`, `address_country='KENYA'`), N2 `b2000000-…02` (P2 `e2000000-…02`), N3 `b3000000-…03` (P3 `e3000000-…03`)
  - ciudad C2 `c2000000-0000-0000-0000-000000000002` con nodo N4 `b4000000-…04` (P4 `e4000000-…04`)
  - carrier `ca000000-…01`, producto `cb000000-…01`
  - planes `cc000000-…01` (2027-03-01..2027-03-31, `plan_name='Mar27'`) y `cc000000-…02` (2027-04-01..2027-04-30, `plan_name='Apr27'`)
  - **sin** muestras ni bajas (cada test inserta las suyas)
  - actor autenticado `99000000-0000-0000-0000-000000000099` en `auth.users` + `profiles` (role `user`, cuenta `a000…01`) y actor de otra cuenta `98000000-…98` (cuenta `a0000000-0000-0000-0000-000000000002`, creada también); NO activa el JWT (cada test hace `select set_config('request.jwt.claim.sub', …, true)` cuando lo necesite).

- [ ] **Step 1: Borrar el borrador**

```bash
git rm supabase/migrations/20261020120000_unavailability_refresh_and_declare.sql supabase/tests/unavailability_refresh_and_declare.test.sql
```

- [ ] **Step 2: Escribir `supabase/tests/run_tests.sh`**

Bash (se ejecuta con Git Bash en Windows). Variables: `PG=/c/Users/fernandezi/pgportable/pgsql/bin`, `PGPASSWORD=postgres`, host `127.0.0.1`, puerto `5433`, BD `onems_t`. Pasos: `DROP DATABASE IF EXISTS onems_t WITH (FORCE); CREATE DATABASE onems_t; ALTER DATABASE onems_t SET search_path TO public, extensions;` → aplicar `supabase/tests/00_bootstrap_supabase_shim.sql` y después cada `supabase/migrations/*.sql` en orden con `-v ON_ERROR_STOP=1`, abortando en el primer error mostrando las últimas 15 líneas → para cada test: `psql -q -v ON_ERROR_STOP=1 -f <test>`, `PASS <nombre>` si exit 0, si no `FAIL <nombre>` + últimas 20 líneas. Al final resumen `N passed, M failed` y `exit 1` si M>0. Si el servidor no responde (`pg_isready`), imprimir cómo arrancarlo: `"$PG/pg_ctl.exe" -D /c/Users/fernandezi/pgportable/data -l /c/Users/fernandezi/pgportable/pg.log -o "-p 5433" start`.

- [ ] **Step 3: Escribir el fixture `supabase/tests/fixtures/incident_city.sql`**

Copiar las INSERT de `supabase/tests/generate_reassignment_proposals.test.sql` líneas 7–31 como base, añadir N3/P3 en C1 (mover el N3 original a N4/P4 en C2), el segundo plan, la segunda cuenta y los dos actores (ver Interfaces). Columnas obligatorias de `panelists`: `account_id, panelist_code, name, email, mobile, node_id, status, language`; añadir `address_country`.

- [ ] **Step 4: Verificar que el runner funciona con los tests existentes**

Run: `bash supabase/tests/run_tests.sh generate_reassignment_proposals apply_reassignment_proposals list_reroute_candidates reassignment_proposals_schema`
Expected: `4 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add supabase/tests/run_tests.sh supabase/tests/fixtures/incident_city.sql
git commit -m "test(db): runner local de migraciones+tests y fixture de ciudad para incidencias; retirar borrador"
```

---

### Task 2: Esquema de incidencias y cola de avisos

**Files:**
- Create: `supabase/migrations/20261020130000_incident_schema.sql`
- Test: `supabase/tests/incident_schema.test.sql`

**Interfaces:**
- Produces (columnas):
  - `panelist_unavailability.incident_status text NOT NULL DEFAULT 'new'` CHECK `in ('new','auto_resolved','pending_manager','resolved')`; `auto_summary text`; `final_resolution text`; `resolved_at timestamptz`.
  - `panelist_reassignment_proposal.status` CHECK pasa a `in ('pending','auto_resolved','manager_resolved','info','dismissed')`; `final_action` CHECK pasa a `in ('reroute','shift_date','cancel','manual','none')`; nuevas `resolution_note text`, `applied_at timestamptz`.
  - `allocation_plan_details.original_fecha_programada date`.
  - Tabla `panelist_notification(id uuid pk default gen_random_uuid(), account_id uuid not null references accounts(id) on delete cascade, panelist_id uuid not null references panelists(id) on delete cascade, kind text not null check (kind in ('unavailability_received','plan_change_this_week')), payload jsonb not null default '{}', status text not null default 'pending_send' check (status in ('pending_send','sent','failed')), error text, created_at timestamptz not null default now(), sent_at timestamptz)`; índice parcial `idx_pn_pending on (created_at) where status='pending_send'`; RLS activo; policy SELECT para `authenticated`: `account_id = current_user_account_id() OR is_superadmin()`; sin policies de escritura (solo service_role/definer).
- Datos: `UPDATE panelist_reassignment_proposal SET status='manager_resolved' WHERE status='confirmed'` (hacer ANTES de cambiar el CHECK). Incidencias existentes: `incident_status = CASE review_status WHEN 'pending_review' THEN 'pending_manager' ELSE 'resolved' END` cuando `status='cancelled'` o tengan líneas; las activas sin líneas quedan `new` (la puesta al día de la Tarea 8 las resuelve).

- [ ] **Step 1: Escribir el test `supabase/tests/incident_schema.test.sql`**

Con `\set ON_ERROR_STOP on`, `BEGIN; \ir fixtures/incident_city.sql` y bloques `DO` que comprueben (RAISE EXCEPTION 'FAIL …' / RAISE NOTICE 'PASS …'):
- existen las 4 columnas nuevas de `panelist_unavailability` y el default de `incident_status` es `'new'` (insertar una baja y leerla);
- `INSERT INTO panelist_reassignment_proposal (… status='auto_resolved' …)` funciona y `status='confirmed'` lanza `check_violation`;
- `final_action='none'` se acepta;
- `allocation_plan_details.original_fecha_programada` existe;
- `panelist_notification`: insertar una fila con `kind='plan_change_this_week'` funciona, `kind='x'` falla; `relrowsecurity` es true; `has_table_privilege('anon','public.panelist_notification','SELECT')` es false.
Termina en `ROLLBACK;`.

- [ ] **Step 2: Ejecutarlo para ver que falla**

Run: `bash supabase/tests/run_tests.sh incident_schema`
Expected: `FAIL incident_schema` (columna `incident_status` no existe)

- [ ] **Step 3: Escribir la migración `20261020130000_incident_schema.sql`**

Orden obligatorio: (1) `UPDATE … status='manager_resolved' WHERE status='confirmed'`; (2) `ALTER TABLE panelist_reassignment_proposal DROP CONSTRAINT prp_status_check, ADD CONSTRAINT prp_status_check CHECK (…)`; igual con `prp_final_action_check`; (3) columnas nuevas; (4) tabla + índice + RLS + policy + `GRANT SELECT ON panelist_notification TO authenticated`; (5) relleno de `incident_status` para filas existentes.

- [ ] **Step 4: Ejecutar tests**

Run: `bash supabase/tests/run_tests.sh`
Expected: todos `PASS` (incluidos los antiguos: `apply_reassignment_proposals.test.sql` comprueba `status='confirmed'` tras aplicar → **editar ese test** para esperar `'manager_resolved'` y ajustar `apply_reassignment_proposal` en esta misma migración: `SET status='manager_resolved'` en lugar de `'confirmed'`; es compatibilidad para el frontend viejo hasta que llegue el Plan 2).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261020130000_incident_schema.sql supabase/tests/incident_schema.test.sql supabase/tests/apply_reassignment_proposals.test.sql
git commit -m "feat(db): esquema de incidencias de indisponibilidad y cola panelist_notification"
```

---

### Task 3: Funciones auxiliares: hoy local, carga semanal, huecos, aplicar cambio, avisos

**Files:**
- Create: `supabase/migrations/20261020130100_incident_helpers.sql`
- Test: `supabase/tests/incident_helpers.test.sql`

**Interfaces (todas `SECURITY DEFINER SET search_path=public`, REVOKE de PUBLIC/anon/authenticated salvo donde se indica):**
- `panelist_local_today(p_panelist_id uuid) RETURNS date` — `(now() AT TIME ZONE tz)::date` con tz por `upper(trim(address_country))`: `KENYA→Africa/Nairobi`, `UNITED STATES`/`USA→America/New_York`, `SPAIN→Europe/Madrid`, resto `UTC`. STABLE. GRANT a authenticated.
- `incident_week_start(p_date date) RETURNS date` IMMUTABLE — lunes de la semana.
- `incident_node_week_load(p_node_id uuid, p_date date) RETURNS integer` STABLE — ver Global Constraints.
- `incident_saturation_threshold(p_reference_load numeric DEFAULT 6, p_deviation_percent numeric DEFAULT 20) RETURNS numeric` IMMUTABLE.
- `incident_node_fits(p_node_id uuid, p_date date, p_reference_load numeric, p_deviation_percent numeric) RETURNS boolean` — `is_node_available(p_node_id, p_date) AND incident_node_week_load(p_node_id,p_date) + 1 <= threshold`.
- `incident_find_shift_date(p_node_id uuid, p_after date, p_month_anchor date, p_reference_load numeric, p_deviation_percent numeric) RETURNS date` — primer día `d` con `d > p_after`, `d` en el mes de `p_month_anchor`, isodow 1..5, `incident_node_fits(p_node_id, d, …)`; orden: `(nº de muestras no canceladas de ese nodo —origen o destino— el día d) ASC, d ASC`. NULL si no hay.
- `incident_find_node(p_city_id uuid, p_exclude_node_id uuid, p_date date, p_reference_load numeric, p_deviation_percent numeric) RETURNS uuid` — nodo de la ciudad (misma cuenta, `n.id <> p_exclude`) con `incident_node_fits`, orden `incident_node_week_load ASC, auto_id ASC`. NULL si no hay.
- `incident_apply_change(p_proposal_id uuid, p_new_date date, p_new_node_id uuid, p_mode text) RETURNS void` — `p_mode in ('auto','manager')`. Lee la línea y su muestra. Si `p_new_node_id` no nulo: según `affected_role` actualiza `origin_node_id`/`destination_node_id` guardando `original_origin_node_id`/`original_destination_node_id` con `COALESCE(original, actual)` y refresca `origin_panelist_name`/`destination_panelist_name` desde `get_panelist_for_node(nodo, fecha)`. Si `p_new_date` no nula y distinta: `original_fecha_programada = COALESCE(original_fecha_programada, fecha_programada)`, `fecha_programada = p_new_date`. En ambos casos: `status = CASE WHEN status='notified' THEN 'pending' ELSE status END`, `reassignment_reason='panelist_unavailable'`, `reassigned_at=now()`, `reassigned_by=auth.uid()`. Línea: `status = CASE p_mode WHEN 'auto' THEN 'auto_resolved' ELSE 'manager_resolved' END`, `final_action = CASE WHEN p_new_node_id IS NOT NULL THEN 'reroute' ELSE 'shift_date' END`, `final_target_node_id`, `final_date`, `applied_at=now()`, `confirmed_by=auth.uid()`, `confirmed_at=now()` (solo manager). Llama a `incident_enqueue_plan_change`.
- `incident_apply_cancel(p_proposal_id uuid, p_mode text) RETURNS void` — muestra `status='cancelled'`, `reassignment_reason='panelist_unavailable'`, `reassigned_at/by`; línea `final_action='cancel'`, estado según modo, `applied_at`. Llama a `incident_enqueue_plan_change`.
- `incident_enqueue_plan_change(p_detail_id uuid, p_change text, p_old_date date, p_new_date date, p_exclude_panelist_id uuid) RETURNS integer` — `p_change in ('shift_date','reroute_origin','reroute_destination','cancel','revert')`. Si `current_setting('onems.suppress_notifications', true) = 'on'` → 0. Si ni `p_old_date` ni `p_new_date` caen en la semana actual → 0. Destinatarios (panelista activo del nodo, excluyendo `p_exclude_panelist_id`): `shift_date`/`cancel`/`revert` → emisor; `reroute_origin` → nuevo emisor; `reroute_destination` → nuevo receptor **y** emisor. Inserta en `panelist_notification(kind='plan_change_this_week', payload)` con payload `{detail_id, change, recipient_role ('sender'|'receiver'), old_date, new_date, scheduled_date, origin_node_code, destination_node_code, origin_panelist_name, destination_panelist_name, destination_address:{address_line1,address_line2,postal_code,city}, product_description, carrier_name}` (direcciones y nombres desde `panelists`/`nodes`/`products`/`carriers`). Devuelve nº encoladas.

- [ ] **Step 1: Escribir `supabase/tests/incident_helpers.test.sql`**

Con fixture. Casos (cada uno un `DO` PASS/FAIL):
- `panelist_local_today(P1)` ≠ NULL y P4 (sin país) devuelve `(now() at time zone 'UTC')::date`.
- `incident_week_start('2027-03-10')` = `2027-03-08`.
- Insertar 3 muestras en N1 la semana del 2027-03-08 (una `cancelled`) y 1 con N1 destino → `incident_node_week_load(N1,'2027-03-10')` = 3.
- `incident_saturation_threshold()` = 7.8; `incident_node_fits(N1,'2027-03-10',6,20)` true; tras insertar 5 muestras más en N1 esa semana (total 8) → false.
- `incident_find_shift_date(N2, '2027-03-12', '2027-03-10', 6, 20)` = `2027-03-15` (lunes); con una muestra de N2 el 15 → `2027-03-16` (reparto por día); con `p_after='2027-03-31'` → NULL.
- `incident_find_node(C1, N1, '2027-03-10', 6,20)` = N2 cuando N2 y N3 tienen igual carga (por auto_id); tras dar 2 muestras a N2 esa semana → N3; con P3 de baja ese día (insertar `panelist_unavailability` activa para P3 — OJO: no disparar el motor aún; el trigger viejo sigue existiendo y es best-effort, aceptable) → N2.
- `incident_apply_change`: muestra `notified` origen N1 2027-03-10 con línea pending rol origin; aplicar `(line, NULL, N2, 'auto')` → `origin_node_id=N2`, `original_origin_node_id=N1`, `status='pending'`, `origin_panelist_name='Pan2'`, línea `auto_resolved`, `final_action='reroute'`; aplicar fecha en otra línea → `original_fecha_programada` guardada y `final_action='shift_date'`.
- `incident_enqueue_plan_change`: muestra con fecha `current_date` (semana actual), `reroute_destination` → 2 filas (`receiver` y `sender`); con fechas fuera de la semana → 0; con `set_config('onems.suppress_notifications','on',true)` → 0.
- Permisos: `has_function_privilege('anon','public.incident_apply_change(uuid,date,uuid,text)','EXECUTE')` false y lo mismo para `authenticated`.

- [ ] **Step 2: Ejecutar para ver que falla**

Run: `bash supabase/tests/run_tests.sh incident_helpers` → `FAIL` (función no existe).

- [ ] **Step 3: Escribir `20261020130100_incident_helpers.sql`** con las firmas de Interfaces y los REVOKE/GRANT.

- [ ] **Step 4: Ejecutar todos los tests** → todos `PASS`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261020130100_incident_helpers.sql supabase/tests/incident_helpers.test.sql
git commit -m "feat(db): auxiliares del motor de incidencias (carga semanal, huecos, aplicar cambio, cola de avisos)"
```

---

### Task 4: Motor `resolve_unavailability_incident`

**Files:**
- Create: `supabase/migrations/20261020130200_resolve_unavailability_incident.sql`
- Test: `supabase/tests/resolve_unavailability_incident.test.sql`

**Interfaces:**
- Consumes: Tarea 3.
- Produces:
  - `incident_suggest(p_proposal_id uuid, p_week_start date DEFAULT NULL, p_reference_load numeric DEFAULT 6, p_deviation_percent numeric DEFAULT 20) RETURNS jsonb` STABLE — `{found:true, date, node_id, node_code, load_after, saturation_level}` o `{found:false}`. Si `p_week_start` es NULL recorre las semanas desde `incident_week_start(fin_baja)+7` hasta `fecha_original + 56 días`; si se da, solo esa semana (lunes..viernes, días > fin de baja). Por día: mismo nodo si `incident_node_fits`, si no `incident_find_node(ciudad, nodo_original, d)`. `load_after` = carga semanal del nodo elegido + 1; `saturation_level` = `'normal'|'high'|'saturated'` con los mismos cortes que `rpc_get_node_load_by_period` (`high` si > referencia×(1+desv/100)). GRANT a authenticated.
  - `incident_recompute_status(p_unavailability_id uuid) RETURNS text` — devuelve y guarda `incident_status`: alguna línea `pending` → `pending_manager`; ninguna pending y alguna `manager_resolved` → `resolved`; resto → `auto_resolved`. `auto_summary` = texto con códigos `shift=<n>;reroute=<n>;cancel=<n>;info=<n>;pending=<n>` (la UI lo traduce). `review_status` = `'pending_review'` si `pending_manager`, si no `'reviewed'`. `resolved_at = now()` al pasar a `resolved`/`auto_resolved` (NULL si vuelve a `pending_manager`).
  - `resolve_unavailability_incident(p_unavailability_id uuid, p_reference_load numeric DEFAULT 6, p_deviation_percent numeric DEFAULT 20) RETURNS integer` — nº de líneas nuevas creadas. Solo si la baja está `active`. Siempre aditivo (ver spec 5.2 y 5.6): (a) borra líneas `pending` cuya muestra ya no cae en la baja/rol o está `sent/received/cancelled`; (b) crea líneas para muestras afectadas sin línea en ese rol; (c) para cada línea nueva: `info` si muestra `sent`/`received`, o rol destination y `status='sent'`; si `cancelled`/`incident` no crea línea; resto: paso 1 `incident_find_shift_date(nodo, fin_baja, fecha_original)` → `incident_apply_change(linea, fecha, NULL, 'auto')`; paso 2 `incident_find_node(ciudad, nodo, fecha_original)` → `incident_apply_change(linea, NULL, nodo, 'auto')`; paso 2b: por cada día laborable del mes de la muestra ordenado por `abs(d - fecha_original), d` (excluyendo la propia fecha) `incident_find_node(ciudad, nodo, d)` → `incident_apply_change(linea, d, nodo, 'auto')`; si nada: línea queda `pending` con `suggested_*` = `incident_suggest(linea)` (`suggested_action='shift_date'` si mismo nodo, `'reroute'` si otro nodo, `'cancel'` si `found:false`; `suggested_reason` = `'shift_later_week'|'alt_node_later_week'|'no_slot_8_weeks'`); (d) `incident_recompute_status`. Guarda multi-tenant igual que el motor antiguo (si `auth.uid()` no nulo y no superadmin, misma cuenta o `RAISE EXCEPTION 'Cross-tenant access denied'`). REVOKE a anon; GRANT a authenticated y service_role.
  - `DROP FUNCTION generate_reassignment_proposals(uuid)` y borrar `supabase/tests/generate_reassignment_proposals.test.sql`; borrar la carpeta `supabase/functions/propose-reassignments/` (nada la llama: comprobar con `grep -rn propose-reassignments src supabase`).

- [ ] **Step 1: Escribir `supabase/tests/resolve_unavailability_incident.test.sql`**

Escenarios (baja de P1/N1 del 2027-03-10 al 2027-03-12 salvo que se diga otra cosa; el trigger viejo sigue vivo hasta la Tarea 6, así que cada escenario llama al motor **explícitamente** y las bajas se insertan con `status='cancelled'` y luego `UPDATE … status='active'`? NO: el trigger viejo llamaría a `generate_reassignment_proposals`, que esta migración ya ha borrado → su `EXCEPTION … RAISE WARNING` lo absorbe. Aceptable; se limpia en la Tarea 6):
- **Sin muestras** → devuelve 0, `incident_status='auto_resolved'`, `auto_summary` contiene `pending=0`.
- **Nodo sin panelista activo** (P1 `status='inactive'`) → 0 líneas, `auto_resolved`.
- **Paso 1**: muestra origen N1 el 10/03 `notified` → línea `auto_resolved`, `final_action='shift_date'`, `final_date='2027-03-15'`, muestra `status='pending'`, `original_fecha_programada='2027-03-10'`.
- **Reparto**: dos muestras origen N1 el 10/03 → fechas finales `2027-03-15` y `2027-03-16`.
- **Paso 2 (baja hasta fin de mes)**: baja 2027-03-10..2027-03-31; muestra origen N1 el 10/03 → `final_action='reroute'`, `final_target_node_id=N2`, `final_date IS NULL`, `origin_node_id=N2`.
- **Reparto entre nodos**: misma baja, 4 muestras N1 el 10/03 → entre N2 y N3 reparto 2/2.
- **Saturación**: N2 y N3 con 8 muestras cada uno esa semana, otra semana del mes libre → paso 2b: `final_date` en otra semana de marzo y nodo N2/N3.
- **Pendiente + propuesta**: baja 2027-03-01..2027-03-31, N2 y N3 saturados todo marzo (insertar 8 muestras por semana y nodo) → línea `pending`, `suggested_action='shift_date'`, `suggested_date='2027-04-01'` (jueves, primera semana tras la baja), `incident_status='pending_manager'`, `review_status='pending_review'`.
- **`incident_suggest` con semana dada**: la misma línea, `p_week_start='2027-04-12'` → `date='2027-04-12'`, `node_id=N1`.
- **Sin hueco en 8 semanas** (N1 de baja hasta 2027-05-31 y N2/N3 saturados hasta junio) → `suggested_action='cancel'`, `suggested_reason='no_slot_8_weeks'`.
- **Recepción**: muestra N4→N1 el 11/03 `pending` → paso 1 la retrasa (misma lógica); con baja a fin de mes → `destination_node_id=N2`, `destination_panelist_name='Pan2'`.
- **Recepción ya salida** (`status='sent'`, destino N1) → línea `info`, `final_action='none'`, no bloquea: incidencia `auto_resolved`.
- **Muestra `sent` origen N1** → línea `info`. **Muestra `cancelled`** → sin línea.
- **Idempotencia**: segunda llamada devuelve 0 y no cambia ids ni fechas.
- **Aditivo**: añadir una muestra nueva dentro de la baja → segunda llamada devuelve 1; mover una muestra `pending` fuera del rango → su línea desaparece.
- **Cross-tenant**: `set_config('request.jwt.claim.sub', actor98, true)` → `Cross-tenant access denied`; actor99 → funciona.

- [ ] **Step 2: Ejecutar** → `FAIL`.

- [ ] **Step 3: Escribir `20261020130200_resolve_unavailability_incident.sql`** (firmas de Interfaces; borrar función vieja, test viejo y edge function).

- [ ] **Step 4: Ejecutar todos los tests** → `PASS` (el test `apply_reassignment_proposals` sigue; el de `generate_*` ya no existe).

- [ ] **Step 5: Commit**

```bash
git add -A supabase/migrations/20261020130200_resolve_unavailability_incident.sql supabase/tests/resolve_unavailability_incident.test.sql supabase/tests/generate_reassignment_proposals.test.sql supabase/functions/propose-reassignments
git commit -m "feat(db): motor resolve_unavailability_incident (retrasar, otro nodo sin saturar, propuesta al manager)"
```

---

### Task 5: RPCs del manager

**Files:**
- Create: `supabase/migrations/20261020130300_incident_manager_rpcs.sql`
- Test: `supabase/tests/incident_manager_rpcs.test.sql`

**Interfaces (GRANT a authenticated; guarda multi-tenant: superadmin o `profiles.account_id` = cuenta de la línea/baja, si no `RAISE EXCEPTION 'Cross-tenant access denied'`):**
- `suggest_for_week(p_proposal_id uuid, p_week_start date, p_reference_load numeric DEFAULT 6, p_deviation_percent numeric DEFAULT 20) RETURNS jsonb` — envoltorio de `incident_suggest` con la guarda.
- `apply_manager_decision(p_proposal_id uuid, p_decision text, p_week_start date DEFAULT NULL, p_reference_load numeric DEFAULT 6, p_deviation_percent numeric DEFAULT 20) RETURNS jsonb` — `p_decision in ('accept','week','cancel')`; la línea debe estar `pending` (si no `RAISE EXCEPTION 'Proposal % already %'`). `accept`: si `suggested_action='cancel'` → `incident_apply_cancel(line,'manager')`; si no `incident_apply_change(line, suggested_date, CASE WHEN suggested_target_node_id <> nodo original THEN suggested_target_node_id END, 'manager')`. `week`: `incident_suggest(line, p_week_start, …)`; si `found:false` → `RAISE EXCEPTION 'No slot in week %'`; si no aplica igual que accept. `cancel`: `incident_apply_cancel`. Luego `incident_recompute_status`. Devuelve `{ok:true, incident_status, final_action, final_date, final_target_node_id}`.
- `set_incident_resolution(p_unavailability_id uuid, p_text text) RETURNS void` — guarda `final_resolution`, `updated_by=auth.uid()`.
- `apply_reassignment_proposal` queda (compatibilidad) sin cambios adicionales.

- [ ] **Step 1: Escribir `supabase/tests/incident_manager_rpcs.test.sql`**

Fixture + baja P1 2027-03-01..2027-03-31 con N2/N3 saturados en marzo (como en Tarea 4) y una muestra origen N1 el 10/03 → tras el motor hay 1 línea `pending`. Con actor99:
- `suggest_for_week(line,'2027-04-12')` → `found:true`, `date='2027-04-12'`.
- `apply_manager_decision(line,'week','2027-04-12')` → muestra `fecha_programada='2027-04-12'`, `plan_id` sin cambiar, línea `manager_resolved`, `confirmed_by=actor99`, respuesta `incident_status='resolved'`; baja `resolved`, `resolved_at` no nulo, `review_status='reviewed'`.
- Repetir sobre la misma línea → `Proposal % already manager_resolved`.
- Nueva baja/línea pendiente: `apply_manager_decision(line,'accept')` → aplica `suggested_date`.
- Otra: `apply_manager_decision(line,'cancel')` → muestra `cancelled`, línea `final_action='cancel'`.
- `set_incident_resolution(baja,'Hablado con el panelista')` → `final_resolution` guardado.
- Actor98 sobre cualquiera → `Cross-tenant access denied`. `anon` sin EXECUTE en las tres.

- [ ] **Step 2: Ejecutar** → `FAIL`. **Step 3: Escribir la migración.** **Step 4: Todos los tests `PASS`.**

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261020130300_incident_manager_rpcs.sql supabase/tests/incident_manager_rpcs.test.sql
git commit -m "feat(db): RPCs del manager: suggest_for_week, apply_manager_decision, set_incident_resolution"
```

---

### Task 6: Triggers: alta/cancelación de baja y cambios del plan

**Files:**
- Create: `supabase/migrations/20261020130400_incident_triggers.sql`
- Test: `supabase/tests/incident_triggers.test.sql`

**Interfaces:**
- Reemplaza `tg_generate_proposals_on_unavailability()` por `tg_unavailability_incident()` (mismo trigger `generate_proposals_on_unavailability_trigger` AFTER INSERT OR UPDATE FOR EACH ROW, recreado):
  - activación (INSERT con `status='active'`, o UPDATE a `active`): `resolve_unavailability_incident(NEW.id)` dentro de `BEGIN … EXCEPTION WHEN OTHERS THEN RAISE WARNING`.
  - desactivación (`active` → otro): para cada línea `auto_resolved`/`manager_resolved`: `reroute` → restaurar `origin/destination_node_id` desde `original_*` (y limpiar `original_*`, refrescar nombres); `shift_date` → `fecha_programada = original_fecha_programada`, limpiar; `cancel` → si la muestra sigue `cancelled` y `reassignment_reason='panelist_unavailable'` → `status='pending'`; en todos limpiar `reassignment_reason/reassigned_at/reassigned_by`; `incident_enqueue_plan_change(detail,'revert', fecha_antes, fecha_después, NEW.panelist_id)`. Líneas `pending` → `dismissed`. Todas las líneas tocadas: `resolution_note='unavailability_cancelled'`. Baja: `incident_status='resolved'`, `final_resolution = COALESCE(final_resolution,'') || 'unavailability_cancelled'` (código; UI traduce), `resolved_at=now()`, `review_status='reviewed'`.
- `tg_refresh_incidents_on_plan_change()` + triggers de sentencia `refresh_incidents_on_plan_insert` (AFTER INSERT, `REFERENCING NEW TABLE AS new_rows`) y `refresh_incidents_on_plan_update` (AFTER UPDATE, `REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows`): bajas activas con `end_date >= current_date` cuyo panelista tenga nodo en origen/destino de filas nuevas (INSERT) o de filas cuyo `fecha_programada`/`origin_node_id`/`destination_node_id` cambió **y** `reassigned_at IS NOT DISTINCT FROM` el antiguo (UPDATE), posición nueva y antigua; por cada baja `resolve_unavailability_incident(id)` en bloque best-effort. Función entera envuelta en `EXCEPTION WHEN OTHERS THEN RAISE WARNING`.

- [ ] **Step 1: Escribir `supabase/tests/incident_triggers.test.sql`**

- **Alta dispara el motor**: insertar muestra N1 10/03 y luego la baja → sin llamar al motor, la línea existe y es `auto_resolved`; `incident_status='auto_resolved'`.
- **Plan después de la baja**: baja primero (→ `auto_resolved`, 0 líneas); INSERT de 3 muestras en una sola sentencia (2 dentro de la baja, 1 fuera) → 2 líneas; estado recalculado.
- **Mover muestra dentro** (UPDATE fecha de la 3ª al 11/03) → línea nueva. **Mover fuera** (una `pending` del escenario saturado → fecha 2027-03-25 fuera de la baja) → línea desaparece.
- **Cambio de `status` solo** → sin líneas nuevas ni borradas. **UPDATE con `reassigned_at` cambiado** (simular manager) → sin reacción.
- **Trigger no bloquea**: `DROP FUNCTION incident_find_shift_date(uuid,date,date,numeric,numeric)` dentro del test (savepoint) y UPDATE del plan → la sentencia **no** falla (WARNING).
- **Cancelar baja**: escenario con una `shift_date` (10/03→15/03), un `reroute` (N1→N2), un `cancel` del manager, una `pending`, y una muestra `cancelled` **por otra vía** (`reassignment_reason IS NULL`) → `UPDATE … status='cancelled'`: fechas/nodos restaurados, `original_*` NULL, el `cancel` del motor vuelve a `pending`, la otra `cancelled` sigue `cancelled`, `pending` → `dismissed`, todas con `resolution_note='unavailability_cancelled'`, baja `resolved` con `final_resolution` conteniendo `unavailability_cancelled`.
- **Aviso de reversión**: lo anterior con una muestra en la semana actual → fila `panelist_notification` `change='revert'`.

- [ ] **Step 2: Ejecutar** → `FAIL`. **Step 3: Migración.** **Step 4: Todos `PASS`.** (Ajustar `reassignment_proposals_schema.test.sql` si comprueba el nombre del trigger viejo.)

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261020130400_incident_triggers.sql supabase/tests/incident_triggers.test.sql
git commit -m "feat(db): triggers de incidencias: alta/cancelacion de baja y refresco por cambios del plan"
```

---

### Task 7: Puerta de entrada `declare_panelist_unavailability` y aviso "Recibido"

**Files:**
- Create: `supabase/migrations/20261020130500_declare_panelist_unavailability.sql`
- Test: `supabase/tests/declare_panelist_unavailability.test.sql`

**Interfaces:**
- `declare_panelist_unavailability(p_panelist_id uuid, p_start_date date, p_end_date date, p_reason text DEFAULT 'other', p_notes text DEFAULT NULL) RETURNS jsonb` — GRANT solo `service_role`. Errores (en este orden): `panelist_not_found`, `no_date`, `bad_reason` (fuera de `vacation,sick_leave,personal,training,other,materials`), `end_before_start`, `in_past` (`p_start_date < panelist_local_today`), `too_long` (> 90 días), `overlap` (+ `ov_start`, `ov_end`). Éxito: INSERT (el trigger resuelve) → `{ok:true, unavailability_id, start_date, end_date, days, affected_samples (nº líneas no info), pending_samples, incident_status}`. **No** encola `unavailability_received` (n8n contesta en línea).
- Trigger `tg_enqueue_unavailability_received` AFTER INSERT en `panelist_unavailability`: si `auth.uid() IS NOT NULL` (alta desde la web) → `INSERT panelist_notification(kind='unavailability_received', payload={unavailability_id,start_date,end_date})` para el panelista. Best-effort.

- [ ] **Step 1: Test**: fixture; `declare(P1,'2027-03-24','2027-03-26','vacation')` → `ok`, `incident_status='auto_resolved'` (sin muestras) y 0 filas en `panelist_notification`; cada `error_code` con sus entradas; `in_past` con `current_date - 1`; con muestra dentro → `affected_samples=1`; alta por web (`set_config jwt sub actor99` + INSERT directo) → 1 fila `unavailability_received`; `has_function_privilege('authenticated', …, 'EXECUTE')` false, `service_role` true.
- [ ] **Step 2–4:** fallo → migración → todos `PASS`.
- [ ] **Step 5: Commit** `feat(db): declare_panelist_unavailability para n8n y aviso 'recibido' en altas web`.

---

### Task 8: Puesta al día, permisos y runbook de despliegue

**Files:**
- Create: `supabase/migrations/20261020130600_incident_backfill.sql`
- Create: `docs/database/2026-10-20-deploy-incidencias-indisponibilidad.md`
- Modify: `docs/superpowers/specs/2026-08-05-subsistema-c-incidencias-panelistas-design.md` (nota al inicio: "sustituido por el diseño de 2026-10-20")

- [ ] **Step 1: Migración de puesta al día**

```sql
-- Bajas activas vigentes sin resolver: tratarlas como nuevas, sin avisos por cambios antiguos.
SELECT set_config('onems.suppress_notifications','on', true);
DO $$ DECLARE r record; v integer; BEGIN
  FOR r IN SELECT id FROM panelist_unavailability
           WHERE status='active' AND end_date >= current_date ORDER BY start_date LOOP
    BEGIN
      v := public.resolve_unavailability_incident(r.id);
      RAISE NOTICE 'baja %: % lineas nuevas', r.id, v;
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'puesta al dia fallo para %: %', r.id, SQLERRM; END;
  END LOOP; END $$;
-- Incidencias antiguas sin estado coherente
UPDATE panelist_unavailability SET incident_status='resolved', resolved_at=COALESCE(resolved_at, updated_at)
 WHERE incident_status='new' AND (status='cancelled' OR end_date < current_date);
```
Añadir al final el test rápido: `SELECT count(*) FROM panelist_unavailability WHERE incident_status='new' AND status='active' AND end_date>=current_date` debe ser 0 (como `DO` con RAISE EXCEPTION si no).

- [ ] **Step 2: Comprobar en local** — `bash supabase/tests/run_tests.sh` → todos `PASS` (la puesta al día sobre una BD vacía no hace nada).

- [ ] **Step 3: Simular la puesta al día sobre KENYA en solo lectura** (no escribe): con `$TEMP/q.sh` (Management API read-only) listar las bajas activas vigentes y sus muestras afectadas por nodo/fecha; anotar en el runbook el resultado esperado (nº retrasadas / reencaminadas / pendientes por baja).

- [ ] **Step 4: Runbook `docs/database/2026-10-20-deploy-incidencias-indisponibilidad.md`** en lenguaje claro: qué cambia, orden de las 7 migraciones, cómo se aplican (MCP `supabase-onems` `apply_migration` una a una, con el nombre de cada fichero como `name`), verificación tras cada una (consultas `SELECT` concretas: existencia de funciones, `incident_status` de las bajas de KENYA, nº de líneas, 0 filas en `panelist_notification`), rollback (qué `DROP`/`UPDATE` deshace cada migración) y qué NO hace (no manda avisos, no toca muestras `sent`).

- [ ] **Step 5: Commit** `feat(db): puesta al dia de incidencias existentes y runbook de despliegue`.

- [ ] **Step 6: Aplicar en onems-dev (`sehbnpgzqljrsqimwyuz`) — SOLO con confirmación explícita del usuario**, una migración por llamada a `apply_migration`, verificando tras cada una como dice el runbook. Registrar en el runbook fecha/hora y resultado real (líneas creadas por baja).

---

## Self-review

- Cobertura spec: 5.1 (Tarea 7), 5.2 (Tareas 3–4), 5.3 (Tarea 4 `incident_suggest`), 5.4 (Tarea 5), 5.5 (Tareas 3 y 7), 5.6 y 5.8 (Tarea 6), 5.7 (Plan 2, frontend), §7 datos (Tarea 2), puesta al día (Tarea 8). Pantalla y n8n en los Planes 2 y 3.
- Nombres consistentes entre tareas: `incident_apply_change`, `incident_apply_cancel`, `incident_enqueue_plan_change`, `incident_suggest`, `incident_recompute_status`, `resolve_unavailability_incident`, `suggest_for_week`, `apply_manager_decision`, `set_incident_resolution`, `declare_panelist_unavailability`, `panelist_local_today`.
- Review Focus: 1 y 2 → Tarea 4; 3 → Tarea 3; 4 y 5 → Tarea 6.
