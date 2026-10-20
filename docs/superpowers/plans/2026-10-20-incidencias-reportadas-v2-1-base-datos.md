# Incidencias reportadas v2 — Plan 1: Base de datos

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Una migración forward-only con el estado `auto_resolved`, la corrección de la razón `materials`, `update_panelist_contact` ampliada y validada, y tres RPCs nuevas (`insert_panelist_incident_auto`, `reroute_returned_sample`, `list_nodes_for_sample_move`), probadas en el Postgres local.

**Architecture:** Todo en `supabase/migrations/20261020170000_reported_incidents_v2.sql`, mismo estilo que `20260806160000_panelist_incident.sql` (RPCs `SECURITY DEFINER`, `SET search_path = public`, guarda `assert_same_account`). Un test `supabase/tests/reported_incidents_v2.test.sql` con la fixture `incident_city.sql`, un `BEGIN … ROLLBACK` por escenario, fechas relativas a `current_date`. Se aplica en onems-dev solo al final y con confirmación.

**Tech Stack:** PostgreSQL 17 (portable local 127.0.0.1:5433), Supabase (onems-dev), psql.

**Spec:** `docs/superpowers/specs/2026-10-20-incidencias-reportadas-tratamiento-v2-design.md` (§4, §6.D, §6.H, §7).

## Global Constraints

- Base única `onems-dev`, ref `sehbnpgzqljrsqimwyuz`. **Antes de `apply_migration` nombrar proyecto + ref y pedir confirmación explícita.** Nunca `db push` / `db reset`.
- Forward-only: una sola migración nueva, timestamp `20261020170000`. No tocar el baseline ni `migrations_archive_pre_baseline/`.
- Multi-tenant: toda RPC pasa por `assert_same_account(account_id)` (permite `auth.uid()` NULL = service-role) o por la guarda `profiles`/`is_superadmin()` que usa `apply_sample_move`.
- Tests: `bash supabase/tests/run_tests.sh reported_incidents_v2` (reconstruye `onems_t` con shim + todas las migraciones). `\set ON_ERROR_STOP on`, helpers en `pg_temp`, `\ir fixtures/incident_city.sql` dentro de cada `BEGIN`. **No existe `incident_today()`**: fechas relativas (`current_date + n`).
- Permisos: RPCs públicas con `REVOKE ALL … FROM PUBLIC, anon` y `GRANT EXECUTE … TO authenticated, service_role`.
- Códigos de categoría válidos (CHECK existente `pi_category_check`): `missing_materials`, `unreadable_label_receipt`, `parcel_damaged`, `parcel_returned`, `how_to_send`, `unavailability_request`, `tag_photo_problem`, `contact_data_change`, `other`.

## Review Focus

1. `reroute_returned_sample` sobre una muestra `received` o `cancelled` → debe rechazar (`Sample is not returned-eligible`), nunca reabrir. *(Test en Tarea 4.)*
2. `insert_panelist_incident_auto` llamada por n8n con un `p_panelist_id` de otra cuenta que el `p_detail_id` → debe rechazar (`detail belongs to another account`). *(Test en Tarea 3.)*
3. `update_panelist_contact` con `p_email = ''` (cadena vacía, no NULL) → debe tratarse como "no tocar", no violar `NOT NULL`. *(Test en Tarea 2.)*
4. `reroute_returned_sample` al mismo nodo destino y misma semana → `apply_sample_move` lanza `Nothing to change`; la muestra debe quedar como estaba (transacción atómica). *(Test en Tarea 4.)*
5. `list_nodes_for_sample_move` sobre una muestra sin `destination_node_id` (NULL) → lista vacía, no error. *(Test en Tarea 5.)*

---

## File Structure

- Create: `supabase/migrations/20261020170000_reported_incidents_v2.sql` — todo el cambio de esquema y RPCs (una tarea añade una sección cada vez).
- Create: `supabase/tests/reported_incidents_v2.test.sql` — un bloque `BEGIN … ROLLBACK` por escenario; crece con cada tarea.
- Create: `docs/database/2026-10-20-deploy-incidencias-reportadas-v2.md` — runbook de aplicación (Tarea 6).

---

### Task 1: Estado `auto_resolved` y razón `materials`

**Files:**
- Create: `supabase/migrations/20261020170000_reported_incidents_v2.sql`
- Create: `supabase/tests/reported_incidents_v2.test.sql`

**Interfaces:**
- Produces: `panelist_incident.status IN ('open','in_progress','resolved','dismissed','auto_resolved')`; `create_unavailability_from_incident(uuid,date,date,text)` acepta `p_reason='materials'`.

- [ ] **Step 1: Escribir el test (falla porque la migración no existe)**

Cabecera del fichero: `\set ON_ERROR_STOP on`, helper `pg_temp.expect_err(p_sql text, p_msg text)` copiado de `supabase/tests/incident_move_to_cell.test.sql:41-52`, y helper `pg_temp.inc(p_cat text, p_status text DEFAULT 'open', p_detail uuid DEFAULT NULL) RETURNS uuid` que inserta en `panelist_incident` para la cuenta 1 / panelista `e1000000-…01` y devuelve el id.

```sql
-- ===== Escenario 1: status auto_resolved + razon materials =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.inc('other', 'auto_resolved');                           -- OK
SELECT pg_temp.expect_err($$SELECT pg_temp.inc('other', 'foo')$$, 'new row for relation "panelist_incident" violates check constraint "pi_status_check"');
DO $$
DECLARE v_inc uuid := pg_temp.inc('missing_materials'); v_unav uuid; v_reason text;
BEGIN
  v_unav := public.create_unavailability_from_incident(v_inc, current_date, current_date + 7, 'materials');
  SELECT reason INTO v_reason FROM public.panelist_unavailability WHERE id = v_unav;
  IF v_reason <> 'materials' THEN RAISE EXCEPTION 'FAIL reason=% (esperaba materials)', v_reason; END IF;
  IF (SELECT linked_unavailability_id FROM public.panelist_incident WHERE id = v_inc) IS DISTINCT FROM v_unav THEN
    RAISE EXCEPTION 'FAIL incidencia no enlazada'; END IF;
END $$;
ROLLBACK;
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `bash supabase/tests/run_tests.sh reported_incidents_v2`
Expected: `FAIL reported_incidents_v2` (la inserción `auto_resolved` viola `pi_status_check`).

- [ ] **Step 3: Escribir la sección 1 de la migración**

Cabecera de comentario (qué es, forward-only, no toca baseline). Luego:
- `ALTER TABLE public.panelist_incident DROP CONSTRAINT pi_status_check; ALTER TABLE … ADD CONSTRAINT pi_status_check CHECK (status IN ('open','in_progress','resolved','dismissed','auto_resolved'));`
- `CREATE OR REPLACE FUNCTION public.create_unavailability_from_incident(p_incident_id uuid, p_start date, p_end date, p_reason text DEFAULT NULL) RETURNS uuid` — copia del cuerpo actual (`20260806160000_panelist_incident.sql:180-205`) con la lista del `CASE` ampliada a `('vacation','sick_leave','personal','training','other','materials')` y el comentario actualizado.

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `bash supabase/tests/run_tests.sh reported_incidents_v2`
Expected: `PASS reported_incidents_v2`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261020170000_reported_incidents_v2.sql supabase/tests/reported_incidents_v2.test.sql
git commit -m "feat(db): estado auto_resolved en panelist_incident y razon materials en create_unavailability_from_incident"
```

---

### Task 2: `update_panelist_contact` ampliada y validada

**Files:**
- Modify: `supabase/migrations/20261020170000_reported_incidents_v2.sql` (sección 2)
- Modify: `supabase/tests/reported_incidents_v2.test.sql` (escenario 2)

**Interfaces:**
- Produces: `public.update_panelist_contact(p_panelist_id uuid, p_telegram_id text DEFAULT NULL, p_phone text DEFAULT NULL, p_language text DEFAULT NULL, p_email text DEFAULT NULL, p_address_line1 text DEFAULT NULL, p_address_line2 text DEFAULT NULL, p_address_city text DEFAULT NULL, p_address_country text DEFAULT NULL) RETURNS void`. La firma antigua `(uuid,text,text,text)` sigue existiendo y delega en la nueva.
- Reglas: `NULL` o `''` = no tocar. `p_email` debe cumplir `~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'` → si no, `RAISE EXCEPTION 'invalid email'`. `p_phone` debe cumplir `~ '^[0-9+ ]{7,20}$'` → `'invalid phone'`. `p_language IN ('en','es','fr','ar')` → `'invalid language'`. Si `auth.uid() IS NULL` se ignora `p_telegram_id`.

- [ ] **Step 1: Escribir el escenario 2 del test**

```sql
-- ===== Escenario 2: update_panelist_contact ampliada =====
BEGIN;
\ir fixtures/incident_city.sql
UPDATE public.panelists SET telegram_id = 'tg-old' WHERE id = 'e1000000-0000-0000-0000-000000000001';
SELECT public.update_panelist_contact('e1000000-0000-0000-0000-000000000001',
  p_telegram_id => 'tg-new', p_phone => '+34 600 000 000', p_language => 'fr',
  p_email => 'nuevo@test.local', p_address_city => 'Lyon');
DO $$ DECLARE r public.panelists;
BEGIN
  SELECT * INTO r FROM public.panelists WHERE id = 'e1000000-0000-0000-0000-000000000001';
  IF r.telegram_id <> 'tg-old' THEN RAISE EXCEPTION 'FAIL telegram cambiado sin auth.uid()'; END IF;
  IF r.mobile <> '+34 600 000 000' OR r.language <> 'fr' OR r.email <> 'nuevo@test.local' OR r.address_city <> 'Lyon' THEN
    RAISE EXCEPTION 'FAIL campos no aplicados: %', row_to_json(r); END IF;
END $$;
-- cadena vacia = no tocar
SELECT public.update_panelist_contact('e1000000-0000-0000-0000-000000000001', p_email => '');
SELECT CASE WHEN email = 'nuevo@test.local' THEN 1 ELSE 1/0 END FROM public.panelists WHERE id = 'e1000000-0000-0000-0000-000000000001';
-- validaciones
SELECT pg_temp.expect_err($$SELECT public.update_panelist_contact('e1000000-0000-0000-0000-000000000001', p_email => 'sin-arroba')$$, 'invalid email');
SELECT pg_temp.expect_err($$SELECT public.update_panelist_contact('e1000000-0000-0000-0000-000000000001', p_phone => 'abc')$$, 'invalid phone');
SELECT pg_temp.expect_err($$SELECT public.update_panelist_contact('e1000000-0000-0000-0000-000000000001', p_language => 'xx')$$, 'invalid language');
-- firma antigua sigue funcionando
SELECT public.update_panelist_contact('e1000000-0000-0000-0000-000000000001', NULL, '600111222', 'es');
SELECT CASE WHEN mobile = '600111222' AND language = 'es' THEN 1 ELSE 1/0 END FROM public.panelists WHERE id = 'e1000000-0000-0000-0000-000000000001';
ROLLBACK;
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `bash supabase/tests/run_tests.sh reported_incidents_v2`
Expected: FAIL (`function update_panelist_contact(unknown, p_telegram_id => …, p_email => …) does not exist`).

- [ ] **Step 3: Escribir la sección 2 de la migración**

Nueva función de 9 parámetros (cuerpo: `SELECT account_id INTO v_account … PERFORM assert_same_account(v_account)`; normalizar `''` → NULL con `NULLIF(btrim(x),'')`; validaciones con las tres regex/listas; `UPDATE panelists SET telegram_id = CASE WHEN auth.uid() IS NULL THEN telegram_id ELSE COALESCE(v_tg, telegram_id) END, mobile = COALESCE(v_phone, mobile), … updated_at = now()`). Después `CREATE OR REPLACE FUNCTION public.update_panelist_contact(uuid,text,text,text)` que hace `PERFORM public.update_panelist_contact($1,$2,$3,$4,NULL,NULL,NULL,NULL,NULL)`. `REVOKE/GRANT` para ambas firmas (`authenticated, service_role`).

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `bash supabase/tests/run_tests.sh reported_incidents_v2`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261020170000_reported_incidents_v2.sql supabase/tests/reported_incidents_v2.test.sql
git commit -m "feat(db): update_panelist_contact con email/direccion, validacion y telegram protegido para n8n"
```

---

### Task 3: `insert_panelist_incident_auto`

**Files:**
- Modify: migración (sección 3) y test (escenario 3).

**Interfaces:**
- Produces: `public.insert_panelist_incident_auto(p_panelist_id uuid, p_category text, p_description text DEFAULT NULL, p_payload jsonb DEFAULT NULL, p_detail_id uuid DEFAULT NULL, p_status text DEFAULT 'auto_resolved') RETURNS uuid`.
- Reglas: `p_status IN ('open','auto_resolved')` si no → `'invalid status'`; `p_category` en la lista de Global Constraints si no → `'invalid category'`; panelista inexistente → `'panelist not found'`; si `p_detail_id` no es NULL y su `account_id` difiere del del panelista → `'detail belongs to another account'`; `account_id` derivado del panelista; `created_via='telegram'`; `resolved_at = now()` solo si `auto_resolved`; `PERFORM assert_same_account(v_account)`.

- [ ] **Step 1: Escribir el escenario 3 del test**

```sql
-- ===== Escenario 3: insert_panelist_incident_auto =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
DO $$ DECLARE v uuid; r public.panelist_incident;
BEGIN
  v := public.insert_panelist_incident_auto('e1000000-0000-0000-0000-000000000001', 'parcel_damaged', 'roto', '{"x":1}'::jsonb);
  SELECT * INTO r FROM public.panelist_incident WHERE id = v;
  IF r.account_id <> 'a0000000-0000-0000-0000-000000000001' OR r.status <> 'auto_resolved' OR r.resolved_at IS NULL
     OR r.created_via <> 'telegram' OR r.payload->>'x' <> '1' THEN RAISE EXCEPTION 'FAIL auto: %', row_to_json(r); END IF;
  v := public.insert_panelist_incident_auto('e1000000-0000-0000-0000-000000000001', 'how_to_send', NULL, NULL, NULL, 'open');
  SELECT * INTO r FROM public.panelist_incident WHERE id = v;
  IF r.status <> 'open' OR r.resolved_at IS NOT NULL THEN RAISE EXCEPTION 'FAIL open: %', row_to_json(r); END IF;
END $$;
SELECT pg_temp.expect_err($$SELECT public.insert_panelist_incident_auto('e1000000-0000-0000-0000-000000000001', 'bad_cat')$$, 'invalid category');
SELECT pg_temp.expect_err($$SELECT public.insert_panelist_incident_auto('e1000000-0000-0000-0000-000000000001', 'other', NULL, NULL, NULL, 'resolved')$$, 'invalid status');
SELECT pg_temp.expect_err($$SELECT public.insert_panelist_incident_auto('00000000-0000-0000-0000-000000000000', 'other')$$, 'panelist not found');
-- muestra de la cuenta 2 con panelista de la cuenta 1
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
VALUES ('d2000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002', 'cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', current_date + 7, 'sent');
SELECT pg_temp.expect_err($$SELECT public.insert_panelist_incident_auto('e1000000-0000-0000-0000-000000000001', 'other', NULL, NULL, 'd2000000-0000-0000-0000-000000000002')$$, 'detail belongs to another account');
ROLLBACK;
```

*(Si `allocation_plan_details` tiene FK de `plan_id` por cuenta y el INSERT de la cuenta 2 falla, crear un plan `cc…03` para la cuenta 2 en el propio escenario.)*

- [ ] **Step 2: Ejecutar y ver que falla** — Run: `bash supabase/tests/run_tests.sh reported_incidents_v2`. Expected: FAIL (función inexistente).

- [ ] **Step 3: Escribir la sección 3 de la migración** con la firma y reglas del bloque Interfaces. `REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated, service_role`.

- [ ] **Step 4: Ejecutar y ver que pasa** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261020170000_reported_incidents_v2.sql supabase/tests/reported_incidents_v2.test.sql
git commit -m "feat(db): insert_panelist_incident_auto para altas desde n8n con account_id derivado"
```

---

### Task 4: `reroute_returned_sample`

**Files:**
- Modify: migración (sección 4) y test (escenario 4).

**Interfaces:**
- Consumes: `public.apply_sample_move(p_detail_id uuid, p_from_node_id uuid, p_to_node_id uuid, p_week_start date, p_reference_load numeric DEFAULT 6, p_deviation_percent numeric DEFAULT 20) RETURNS jsonb` (`20261020150000_incident_move_to_cell.sql:470`); exige `status IN ('pending','notified')` vía `incident_suggest_sample_move` y decide el lado por `p_from_node_id`.
- Produces: `public.reroute_returned_sample(p_detail_id uuid, p_to_node_id uuid, p_week_start date) RETURNS jsonb`.
- Reglas: `SELECT … FOR UPDATE`; no encontrada → `'Sample % not found'`; guarda tenant igual que `apply_sample_move` (`auth.uid()` no NULL, no superadmin, cuenta distinta → `'Cross-tenant access denied'`); `status NOT IN ('sent','incident')` → `'Sample is not returned-eligible'`; `UPDATE allocation_plan_details SET status='pending', sent_at=NULL, sent_date=NULL, updated_at=now()` **conservando `tag_id`/`idtag`**; después `RETURN public.apply_sample_move(p_detail_id, v_d.destination_node_id, p_to_node_id, p_week_start)`. Si `apply_sample_move` lanza, toda la función revierte (misma transacción).

- [ ] **Step 1: Escribir el escenario 4 del test**

Antes de escribir, leer `incident_suggest_sample_move` (`20261020150000_incident_move_to_cell.sql:260-320`) para saber qué exige del plan/semana (rango del plan, nodo activo, carga). Elegir `v_week := date_trunc('week', current_date + 14)::date` e insertar un plan de la cuenta 1 que cubra esa semana si el existente (`Mar27`) no la cubre.

```sql
-- ===== Escenario 4: reroute_returned_sample =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
-- (plan que cubre current_date .. current_date + 60 si hace falta; muestra devuelta N1 -> N2, etiqueta T1)
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id)
VALUES ('d1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '<plan_id>',
        'b1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', current_date - 3, 'sent', 'T1');
DO $$ DECLARE j jsonb; r public.allocation_plan_details; w date := date_trunc('week', current_date + 14)::date;
BEGIN
  j := public.reroute_returned_sample('d1000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000003', w);
  SELECT * INTO r FROM public.allocation_plan_details WHERE id = 'd1000000-0000-0000-0000-000000000001';
  IF r.status <> 'pending' OR r.destination_node_id <> 'b3000000-0000-0000-0000-000000000003'
     OR r.original_destination_node_id <> 'b2000000-0000-0000-0000-000000000002' OR r.tag_id <> 'T1'
     OR r.fecha_programada < w OR r.fecha_programada > w + 6 OR r.sent_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL reroute: % / %', j, row_to_json(r); END IF;
  IF (j->>'side') <> 'destination' THEN RAISE EXCEPTION 'FAIL side=%', j->>'side'; END IF;
END $$;
-- ya pending -> no es devuelta
SELECT pg_temp.expect_err($$SELECT public.reroute_returned_sample('d1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', date_trunc('week', current_date + 14)::date)$$, 'Sample is not returned-eligible');
-- received -> rechazada
UPDATE public.allocation_plan_details SET status = 'received' WHERE id = 'd1000000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_err($$SELECT public.reroute_returned_sample('d1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', date_trunc('week', current_date + 14)::date)$$, 'Sample is not returned-eligible');
-- mismo nodo y misma semana -> Nothing to change y la muestra sigue 'incident'
UPDATE public.allocation_plan_details SET status = 'incident', destination_node_id = 'b2000000-0000-0000-0000-000000000002',
       fecha_programada = date_trunc('week', current_date + 14)::date WHERE id = 'd1000000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_err($$SELECT public.reroute_returned_sample('d1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', date_trunc('week', current_date + 14)::date)$$, 'Nothing to change');
SELECT CASE WHEN status = 'incident' THEN 1 ELSE 1/0 END FROM public.allocation_plan_details WHERE id = 'd1000000-0000-0000-0000-000000000001';
ROLLBACK;
```

*(La comprobación de `Nothing to change` dentro de `expect_err` usa un sub-bloque con `EXCEPTION`, así que el UPDATE a `pending` queda revertido: es exactamente la atomicidad que se quiere probar.)*

Añadir también el caso cross-tenant con el actor 98 siguiendo cómo lo hace `incident_move_to_cell.test.sql` (buscar `98` en ese fichero para el helper de JWT): esperado `'Cross-tenant access denied'`.

- [ ] **Step 2: Ejecutar y ver que falla** — Expected: FAIL (función inexistente).

- [ ] **Step 3: Escribir la sección 4 de la migración** según Interfaces. `REVOKE/GRANT` como las demás.

- [ ] **Step 4: Ejecutar y ver que pasa** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261020170000_reported_incidents_v2.sql supabase/tests/reported_incidents_v2.test.sql
git commit -m "feat(db): reroute_returned_sample reenvia una muestra devuelta a otro nodo destino"
```

---

### Task 5: `list_nodes_for_sample_move` y permisos

**Files:**
- Modify: migración (sección 5 + bloque final de permisos) y test (escenario 5 + permisos).

**Interfaces:**
- Produces: `public.list_nodes_for_sample_move(p_detail_id uuid) RETURNS TABLE (node_id uuid, auto_id text, city_name text, same_city boolean, panelist_name text)`.
- Reglas: guarda tenant como `apply_sample_move`; si la muestra no existe → `'Sample % not found'`; si `destination_node_id IS NULL` → 0 filas; devuelve los nodos de la **misma cuenta** con un panelista `active` (`panelists.node_id = n.id AND status='active'`), **excluyendo el destino actual**; `same_city = (n.city_id = ciudad del destino actual)`; orden `same_city DESC, auto_id ASC`.

- [ ] **Step 1: Escribir el escenario 5 del test**

```sql
-- ===== Escenario 5: list_nodes_for_sample_move =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
VALUES ('d1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', current_date + 7, 'sent');
DO $$ DECLARE ids text;
BEGIN
  SELECT string_agg(auto_id || ':' || same_city::text, ',' ORDER BY same_city DESC, auto_id) INTO ids
    FROM public.list_nodes_for_sample_move('d1000000-0000-0000-0000-000000000001');
  IF ids <> 'N1:true,N3:true,N4:false' THEN RAISE EXCEPTION 'FAIL lista=%', ids; END IF;
END $$;
UPDATE public.allocation_plan_details SET destination_node_id = NULL WHERE id = 'd1000000-0000-0000-0000-000000000001';
SELECT CASE WHEN count(*) = 0 THEN 1 ELSE 1/0 END FROM public.list_nodes_for_sample_move('d1000000-0000-0000-0000-000000000001');
ROLLBACK;

-- ===== Permisos =====
DO $$ DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.update_panelist_contact(uuid,text,text,text,text,text,text,text,text)',
    'public.insert_panelist_incident_auto(uuid,text,text,jsonb,uuid,text)',
    'public.reroute_returned_sample(uuid,uuid,date)',
    'public.list_nodes_for_sample_move(uuid)'] LOOP
    IF NOT has_function_privilege('authenticated', f, 'EXECUTE') OR NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL falta GRANT en %', f; END IF;
    IF has_function_privilege('anon', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL anon con EXECUTE en %', f; END IF;
  END LOOP;
END $$;
```

- [ ] **Step 2: Ejecutar y ver que falla** — Expected: FAIL (función inexistente).

- [ ] **Step 3: Escribir la sección 5 de la migración** (función + bloque final `REVOKE/GRANT` de las cuatro funciones nuevas si no se hizo por tarea). Añadir también `GRANT EXECUTE ON FUNCTION public.mark_detail_received_manual(uuid) TO service_role;` (hoy solo `authenticated`; n8n la usará en la ficha B) y su comprobación en el bloque de permisos del test.

- [ ] **Step 4: Ejecutar toda la suite** — Run: `bash supabase/tests/run_tests.sh`. Expected: todos `PASS` (los tests antiguos no deben romperse; en particular `incident_manager_rpcs` y `incident_move_to_cell`).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20261020170000_reported_incidents_v2.sql supabase/tests/reported_incidents_v2.test.sql
git commit -m "feat(db): list_nodes_for_sample_move y permisos de las RPCs v2 de incidencias reportadas"
```

---

### Task 6: Runbook y aplicación en onems-dev (con confirmación)

**Files:**
- Create: `docs/database/2026-10-20-deploy-incidencias-reportadas-v2.md`

- [ ] **Step 1: Escribir el runbook** siguiendo `docs/database/2026-10-20-deploy-incidencias-indisponibilidad.md`: qué cambia, orden, comprobaciones post-aplicación (las 3 consultas del paso 3), vuelta atrás (recrear `pi_status_check` sin `auto_resolved` solo si no hay filas con ese estado; `DROP FUNCTION` de las 3 nuevas; `CREATE OR REPLACE` de las dos antiguas con su cuerpo de `20260806160000`).

- [ ] **Step 2: Pedir confirmación** — Decir al usuario: "Voy a aplicar `20261020170000_reported_incidents_v2.sql` en **onems-dev** (`sehbnpgzqljrsqimwyuz`). ¿Confirmas?". **No seguir sin un sí explícito.**

- [ ] **Step 3: Aplicar y comprobar** — `mcp__supabase-onems__apply_migration` con el contenido del fichero. Después, por `execute_sql`:
  - `SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='pi_status_check'` → contiene `auto_resolved`.
  - `SELECT proname, pg_get_function_identity_arguments(oid) FROM pg_proc WHERE proname IN ('insert_panelist_incident_auto','reroute_returned_sample','list_nodes_for_sample_move','update_panelist_contact') ORDER BY 1,2` → 5 filas (dos firmas de `update_panelist_contact`).
  - `SELECT reason FROM panelist_unavailability WHERE reason='materials' LIMIT 1` (puede ser 0 filas; solo comprueba que el CHECK lo admite: `SELECT 'materials' = ANY(…)` no aplica; basta con que la función se haya recreado).

- [ ] **Step 4: Commit del runbook**

```bash
git add docs/database/2026-10-20-deploy-incidencias-reportadas-v2.md
git commit -m "docs(db): runbook de despliegue de incidencias reportadas v2"
```
