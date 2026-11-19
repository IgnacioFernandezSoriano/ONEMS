# Carrier Link, fases 0 y 1 (base y motor E2E) — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que un plan de Carrier Link se alimente de principio a fin con un lote de lecturas (inventado, en DEMO2) y sus muestras aparezcan en los informes E2E actuales, separables por origen y con tiempo de equivalencia.

**Architecture:** Todo el motor vive en la base como funciones PL/pgSQL sobre tablas `cl_*` nuevas; una Edge Function fina (`carrier-link-ingest`) autentica al conector y llama a esas funciones estrato a estrato. Los puntos de lectura son filas de `readers`; la muestra entra en `one_db` con `source='carrier'`. No se toca `allocation_plans`, `allocation_plan_details` ni ninguna función que las use. No hay pantallas de Carrier Link en este plan (fase 2).

**Tech Stack:** Postgres 17 (pgcrypto, pg_cron), Supabase Edge Functions (Deno), React + TypeScript.

**Spec:** `docs/superpowers/specs/2026-11-19-carrier-link-design.md`

**Depende de:** `docs/superpowers/plans/2026-11-19-api-e2e-claves.md` (funciones `api_key_issue` / `api_key_resolve`, columna `api_keys.feed_id`).

## Global Constraints

- Única base: `onems-dev` (`sehbnpgzqljrsqimwyuz`). **Ninguna escritura remota (migración, deploy, datos de prueba en DEMO2) sin confirmación explícita del responsable.** Desarrollo y validación en el Postgres local: `bash supabase/tests/run_tests.sh <test>`.
- Rama `feat/carrier-link` desde `develop`, en worktree propio (`ONEMS_wt_carrier_link`).
- Migraciones solo hacia delante, timestamps `202611201100NN`, posteriores a las del plan de claves.
- Prohibido modificar `allocation_plans`, `allocation_plan_details`, `transfer_to_one_db` y el pipeline RFID (`consolidate_rfid_events` y siguientes).
- Tablas `cl_*`: `account_id uuid NOT NULL` siempre explícito (sin el trigger `set_account_id`), RLS activada, sin privilegios para `anon`. Lectura: superadmin o cuenta propia con `has_any_access(account_id,'view',<opción>)`; escritura: lo mismo con `'edit'`. Escribir las políticas con `(SELECT …)` como las `*_edit` existentes.
- Funciones `SECURITY DEFINER` con `SET search_path = public, extensions`, `REVOKE ALL … FROM PUBLIC, anon`. Las que llama el conector, solo `service_role`.
- El identificador del envío se guarda **tal como llega** (sin `normalize_tag`, sin prefijos); el carrier va en su campo.
- Nombres al escribir en `one_db`: `carrier_name = carriers.name`, `product_name = products.description`, ciudades `cities.name`.
- Todo texto de pantalla por `useTranslation()` en los 5 idiomas (en, es, fr, ar, pt).
- `npm run lint`, `npm run build` y `npm test` sin errores nuevos.

## Review Focus

- Una fila `panelist` de `one_db` (insertada como hoy) queda **idéntica** tras los cambios del trigger de tránsito: mismas horas, días y "en plazo".
- Lote repetido (`batch_id` ya visto): no crea muestras ni lecturas nuevas y devuelve el mismo resumen.
- El mismo lote con la misma semilla produce exactamente los mismos elegidos.
- Un identificador ya usado como muestra en una petición anterior no vuelve a elegirse.
- Una clave de conector de la cuenta A no ve demandas ni puede cargar lotes de la cuenta B ni de otro conector de A.

---

## Fase 0 — Base

### Task 1: Campos nuevos en los maestros y opciones de acceso

**Files:**
- Create: `supabase/migrations/20261120110000_cl_masters.sql`
- Test: `supabase/tests/cl_masters.test.sql`

**Interfaces — Produces:**
- `readers`: `capture_source text NOT NULL DEFAULT 'rfid' CHECK (IN ('rfid','carrier_scan'))`, `carrier_id uuid REFERENCES carriers(id)`, `carrier_place_ref text`, `carrier_mode_ref text`, `e2e_role text NOT NULL DEFAULT 'none' CHECK (IN ('origin','destination','both','none'))`.
  - CHECK `readers_cl_shape`: `capture_source='rfid'` ⇒ los tres campos de carrier NULL y `e2e_role='none'`; `capture_source='carrier_scan'` ⇒ `carrier_id` y `carrier_place_ref` NOT NULL y `type IN ('Entry','Exit')`.
  - Índice único `readers_cl_point_key` sobre `(account_id, carrier_id, carrier_place_ref, COALESCE(carrier_mode_ref,''))` `WHERE capture_source='carrier_scan' AND deleted_at IS NULL`.
  - Trigger `readers_cl_defaults` BEFORE INSERT: si `capture_source='carrier_scan'` y `reader_id` viene vacío, lo genera como `'CL:' || accounts.slug || ':' || carriers.code || ':' || carrier_place_ref || COALESCE(':' || carrier_mode_ref, '')`. Trigger BEFORE INSERT OR UPDATE: `e2e_role <> 'none'` exige que el centro postal tenga `city_id` (si no, excepción `check_violation`).
- `delivery_standards`: `cl_first_mile_time numeric NOT NULL DEFAULT 0 CHECK (>= 0)`, `cl_last_mile_time numeric NOT NULL DEFAULT 0 CHECK (>= 0)`.
- `one_db`: `source text NOT NULL DEFAULT 'panelist' CHECK (IN ('panelist','carrier'))`, `cl_sample_id uuid UNIQUE`, `carrier_id uuid`, `equivalence_hours numeric`, `equivalence_days integer`, `measured_total_hours numeric`, `measured_total_days integer`, `measured_business_hours numeric`, `measured_business_days integer`; índice `(account_id, source)`.
- `access_option`: `('cl_plans','carrier_link',152)`, `('cl_samples','carrier_link',153)`, `('cl_reading_points','carrier_link',154)`, `('cl_connectors','carrier_link',155)`, `('cl_monitor','carrier_link',156)`.
- `access_template` y `account_access` (esta última **para todas las cuentas existentes**), según la tabla del spec §7: account_manager y upu_account_manager → plans edit, samples view, reading_points edit, connectors edit, monitor edit; allocation_plan_manager → plans edit, samples view, reading_points view, monitor view; do_coordinator → plans view, samples view, reading_points edit, monitor view; el resto y `no_role`, nada.
- Políticas `readers_insert_edit`, `readers_update_edit`, `readers_delete_edit`, `postal_centers_insert_edit`, `postal_centers_update_edit`: recreadas añadiendo `'cl_reading_points'` a la lista VARIADIC que ya tienen (leer su definición viva con `pg_policies` antes de reescribirlas y conservar el resto literal).

- [ ] **Step 1: Test** (patrón y fixtures de `account_access_writes.test.sql`). Aserciones:
  - un lector existente tiene `capture_source='rfid'`, `e2e_role='none'`;
  - insertar un punto `carrier_scan` sin `reader_id` genera uno que empieza por `CL:`; un segundo con mismo carrier, lugar y modo falla; mismo lugar con modo distinto pasa; mismo lugar con modo NULL dos veces falla;
  - `carrier_scan` con `type='Mixed'` falla; `rfid` con `carrier_id` falla;
  - `e2e_role='origin'` en un centro sin `city_id` falla;
  - cada cuenta del fixture tiene 5 + 5 + 4 + 4 filas nuevas en `account_access` para las opciones `cl_%`;
  - un DO Coordinator con `cl_reading_points` en edit y sin `readers_management` puede insertar un punto; un Allocation Plan Manager no.
- [ ] **Step 2:** `bash supabase/tests/run_tests.sh cl_masters` → FAIL.
- [ ] **Step 3:** Escribir la migración.
- [ ] **Step 4:** `bash supabase/tests/run_tests.sh cl_masters account_access account_access_writes` → PASS.
- [ ] **Step 5: Commit** `feat(carrier-link): campos de maestros y opciones de acceso`.

### Task 2: El trigger de tránsito admite tiempo de equivalencia

**Files:**
- Create: `supabase/migrations/20261120110100_cl_equivalence.sql`
- Test: `supabase/tests/cl_equivalence.test.sql`

**Interfaces — Produces:**
- `one_db_compute_transit()` reescrita **conservando literal** el cálculo actual y añadiendo al final: si `NEW.source = 'carrier'`: `measured_total_hours/days` y `measured_business_hours/days` := lo calculado; después `total_transit_hours` y `business_transit_hours` += `COALESCE(NEW.equivalence_hours,0)`, `total_transit_days` y `business_transit_days` += `COALESCE(NEW.equivalence_days,0)`. Para `panelist` no cambia nada y los `measured_*` quedan NULL.
- El trigger `one_db_compute_transit` pasa a `BEFORE INSERT OR UPDATE OF sent_at, received_at, account_id, equivalence_hours, equivalence_days`.
- `cl_equivalence(p_standard_id uuid) RETURNS TABLE (eq_hours numeric, eq_days integer)`: `t := cl_first_mile_time + cl_last_mile_time`; si `time_unit='days'` → `(t*24, round(t))`; si no → `(t, round(t/24.0))`.
- Trigger `cl_equivalence_on_sla_change` AFTER INSERT OR UPDATE en `delivery_standards` (el nombre va alfabéticamente antes que `trigger_recalculate_on_time_on_sla_change`, así que se ejecuta primero): actualiza `equivalence_hours/days` de las filas `one_db` con `source='carrier'`, `carrier_id = NEW.carrier_id`, y producto y ciudades que casan por nombre igual que hace `recalculate_on_time_delivery_on_sla_change`. El trigger existente recalcula después el "en plazo" con los tiempos ya equivalentes.

- [ ] **Step 1: Test**:
  - fila `panelist` insertada antes y después de aplicar el cambio (guardar sus valores con el trigger actual en una tabla temporal al inicio del test no es posible tras migrar: en su lugar, comparar contra `calculate_business_hours`/`calculate_business_days` y contra `received_at_local::date - sent_at_local::date`): `business_transit_hours = calculate_business_hours(...)`, `measured_business_hours IS NULL`;
  - fila `carrier` con `equivalence_hours=24, equivalence_days=1`: `business_transit_hours = measured_business_hours + 24`, `business_transit_days = measured_business_days + 1`, ídem totales;
  - estándar en días con primer tramo 0 y último tramo 1 → `cl_equivalence` = (24, 1); en horas con 6 + 6 → (12, 1);
  - cambiar `cl_last_mile_time` de un estándar actualiza la fila `carrier` de esa ruta y su `on_time_delivery` pasa de true a false cuando el tiempo equivalente supera el estándar; una fila `panelist` de la misma ruta no cambia.
- [ ] **Step 2:** `bash supabase/tests/run_tests.sh cl_equivalence` → FAIL.
- [ ] **Step 3:** Migración (leer el cuerpo vivo de `one_db_compute_transit` con `pg_get_functiondef` y partir de él).
- [ ] **Step 4:** `bash supabase/tests/run_tests.sh` (todos) → PASS; ningún test previo de `one_db` cambia de resultado.
- [ ] **Step 5: Commit** `feat(carrier-link): tiempo de equivalencia en el cálculo de tránsito`.

### Task 3: Tablas `cl_*`

**Files:**
- Create: `supabase/migrations/20261120110200_cl_tables.sql`
- Test: `supabase/tests/cl_tables.test.sql`

**Interfaces — Produces** (columnas además de `id uuid PK DEFAULT gen_random_uuid()`, `account_id`, `created_at`):
- `cl_feeds`: `carrier_id`, `name`, `extraction_model text`, `config jsonb DEFAULT '{}'`, `secret_ref text`, `status text CHECK (IN ('testing','active','paused')) DEFAULT 'testing'`, `last_batch_at`, `last_error`. Opción: `cl_connectors`. Aquí se añade la FK `api_keys.feed_id → cl_feeds(id) ON DELETE CASCADE`.
- `cl_field_mappings`: `carrier_id`, `standard_field text CHECK (IN ('item_id','product','scan_at','place_ref','mode_ref'))`, `carrier_field text NOT NULL`, `format text`, `timezone text`; UNIQUE `(account_id, carrier_id, standard_field)`. Opción: `cl_connectors`.
- `cl_value_mappings`: `carrier_id`, `kind text CHECK (kind = 'product')`, `carrier_value text`, `onems_value text` (= `products.code`); UNIQUE `(account_id, carrier_id, kind, carrier_value)`. Opción: `cl_connectors`.
- `cl_extra_fields`: `carrier_id`, `carrier_field text`; UNIQUE. Opción: `cl_connectors`.
- `cl_plans`: `plan_name`, `carrier_id`, `product_id`, `total_samples int`, `start_date`, `end_date`, `status CHECK (IN ('draft','active','closed')) DEFAULT 'draft'`, `close_lag_days int DEFAULT 7`, `oversampling_factor numeric DEFAULT 5`, `feed_id → cl_feeds`, `feed_diagnosis boolean DEFAULT false`, `created_by`. Opción: `cl_plans`.
- `cl_plan_quotas`: `plan_id → cl_plans ON DELETE CASCADE`, `origin_city_id`, `destination_city_id`, `iso_year int`, `iso_week int`, `period_start date`, `period_end date`, `samples_planned int`, `samples_carried_in int DEFAULT 0`, `samples_obtained int DEFAULT 0`, `demands_count int DEFAULT 0`, `status CHECK (IN ('pending','open','fulfilled','carried','unfilled')) DEFAULT 'pending'`; UNIQUE `(plan_id, origin_city_id, destination_city_id, iso_year, iso_week)`. Opción: `cl_plans`.
- `cl_demands`: `plan_id`, `feed_id`, `status CHECK (IN ('open','fulfilled','partial','failed')) DEFAULT 'open'`, `random_seed text NOT NULL`, `payload jsonb NOT NULL`, `requested_at`. Opción: `cl_monitor`.
- `cl_batches`: `demand_id`, `connector_batch_id text`, `status CHECK (IN ('received','validated','sampled','rejected','undone'))`, `summary jsonb`, `raw_payload jsonb`, `received_at`; UNIQUE `(demand_id, connector_batch_id)`. Opción: `cl_monitor`.
- `cl_batch_scans`: `batch_id ON DELETE CASCADE`, `stratum_id uuid` (= `cl_plan_quotas.id`), `item_id text`, `product_id uuid`, `scan_at timestamptz`, `place_ref text`, `mode_ref text`, `reader_id uuid`, `status CHECK (IN ('valid','rejected'))`, `reject_reason text`; índice `(batch_id, stratum_id, item_id)`. Opción: `cl_monitor`.
- `cl_sampling_runs`: `demand_id`, `batch_id`, `stratum_id`, `population_size int`, `candidates_valid int`, `samples_required int`, `samples_selected int`, `random_seed text`, `selected_item_ids text[]`, `executed_at`; UNIQUE `(batch_id, stratum_id)`. Opción: `cl_monitor`.
- `cl_alerts`: `plan_id`, `batch_id`, `quota_id`, `alert_type text`, `severity CHECK (IN ('low','medium','high'))`, `details jsonb`, `status CHECK (IN ('open','acknowledged','dismissed')) DEFAULT 'open'`. Opción: `cl_monitor`.
- `cl_samples`: `plan_id`, `quota_id`, `batch_id`, `carrier_id`, `product_id`, `item_id text NOT NULL`, `start_reader_id → readers`, `start_at`, `end_reader_id → readers`, `end_at`, `origin_city_id`, `destination_city_id`, `possible_misrouting boolean DEFAULT false`, `extra jsonb DEFAULT '{}'`, `status CHECK (IN ('active','voided')) DEFAULT 'active'`; índice único `(account_id, carrier_id, item_id) WHERE status='active'`. Opción: `cl_samples`. FK `one_db.cl_sample_id → cl_samples(id) ON DELETE CASCADE`.
- `cl_sample_scans`: `sample_id ON DELETE CASCADE`, `reader_id`, `scan_at`, `role CHECK (IN ('start','end','intermediate'))`, `place_ref`, `mode_ref`. Opción: `cl_samples`.
- `admin_reset_demo2`, `admin_reset_and_seed_demo2`, `admin_reset_account_data`: añaden el borrado de las tablas `cl_*` de la cuenta (y de los `readers` con `capture_source='carrier_scan'`), conservando literal el resto de su cuerpo.

- [ ] **Step 1: Test**: como usuario sin rol de A1, `SELECT count(*)` de cada tabla `cl_*` = 0 aunque haya filas; como AM de A1 ve las de A1 y ninguna de A2; como Allocation Plan Manager puede insertar en `cl_plans` y no en `cl_feeds`; como `anon`, `pg_temp.raises('SELECT 1 FROM cl_plans')`; dos muestras activas con mismo carrier e `item_id` fallan, y pasa si la primera está `voided`; borrar una muestra borra su fila de `one_db`.
- [ ] **Step 2:** `bash supabase/tests/run_tests.sh cl_tables` → FAIL.
- [ ] **Step 3:** Migración.
- [ ] **Step 4:** `bash supabase/tests/run_tests.sh cl_tables cl_masters` → PASS.
- [ ] **Step 5: Commit** `feat(carrier-link): tablas del plan, la captura y la muestra`.

### Task 4: La matriz de roles conoce las opciones nuevas

**Files:**
- Modify: `src/lib/access.ts`, `src/lib/accessAdmin.ts`, `src/lib/__tests__/access.test.ts`, `src/lib/__tests__/accessAdmin.test.ts`, traducciones de los 5 idiomas.

Sin rutas ni menú nuevos (fase 2). Solo: las 5 claves en la unión `AccessOption` y en `ACCESS_OPTIONS`, el grupo `carrier_link` en `GROUP_LABEL_KEYS` con su etiqueta, y la etiqueta de cada opción, para que la pestaña Roles y accesos muestre el grupo con nombre.

- [ ] **Step 1:** Ajustar los tests existentes que cuentan opciones (28 → 33) y añadir: `GROUP_LABEL_KEYS.carrier_link` definido; ninguna opción `cl_*` aparece en `ROUTE_OPTION`.
- [ ] **Step 2:** `npm test` → FAIL.
- [ ] **Step 3:** Implementar y traducir.
- [ ] **Step 4:** `npm test && npm run lint && npm run build` → PASS.
- [ ] **Step 5: Commit** `feat(carrier-link): opciones de acceso en la matriz de roles`.

---

## Fase 1 — Motor E2E

### Task 5: Cuotas y activación del plan

**Files:**
- Create: `supabase/migrations/20261120110300_cl_plan_functions.sql`
- Test: `supabase/tests/cl_plan.test.sql`

**Interfaces — Produces:**
- `cl_plan_set_quotas(p_plan_id uuid, p_quotas jsonb) RETURNS int`: reemplaza las cuotas `pending` del plan por las de `p_quotas` (array de `{origin_city_id, destination_city_id, iso_year, iso_week, samples}`); calcula `period_start/period_end` (lunes a domingo de la semana ISO); ignora `samples <= 0`; rechaza semanas fuera de las fechas del plan y ciudades de otra cuenta. Requiere `edit` en `cl_plans`. Devuelve el número de cuotas.
- `cl_plan_missing_points(p_plan_id uuid) RETURNS TABLE (city_id uuid, city_name text, missing text)`: una fila por ciudad de origen sin ningún punto activo del carrier del plan con `e2e_role IN ('origin','both')`, y por ciudad de destino sin `('destination','both')`; `missing` ∈ `'origin'|'destination'`.
- `cl_plan_missing_standards(p_plan_id uuid) RETURNS TABLE (origin_city_id uuid, destination_city_id uuid)`.
- `cl_plan_activate(p_plan_id uuid) RETURNS void`: excepción `'CL_MISSING_POINTS'` si `cl_plan_missing_points` devuelve filas, si el plan no tiene `feed_id` o si no tiene cuotas; si no, `status='active'`.

- [ ] **Step 1: Test**: fixture con 2 ciudades, carrier, producto, 2 centros con ciudad; sin puntos → `cl_plan_missing_points` da 2 filas y `cl_plan_activate` lanza; con un punto `origin` en A y uno `destination` en B → 0 filas y activa; cuota con `samples=0` no se guarda; semana fuera del periodo lanza; `period_start` de la semana ISO 2026-W47 = 2026-11-16.
- [ ] **Step 2–4:** FAIL → migración → `bash supabase/tests/run_tests.sh cl_plan` PASS.
- [ ] **Step 5: Commit** `feat(carrier-link): cuotas y activación del plan`.

### Task 6: Emisión de demandas

**Files:**
- Create: `supabase/migrations/20261120110400_cl_demands.sql`
- Test: `supabase/tests/cl_demands.test.sql`

**Interfaces — Produces:**
- `cl_build_demand(p_plan_id uuid, p_quota_ids uuid[]) RETURNS uuid`: crea `cl_demands` con `random_seed = encode(gen_random_bytes(16),'hex')` y `payload`:
  ```json
  { "schema_version": "1.1", "demand_id": "…", "carrier": "<carriers.code>",
    "products": ["<carrier_value de cl_value_mappings cuyo onems_value = products.code; si no hay, products.code>"],
    "include_all_scans": false,
    "strata": [ { "stratum_id": "<quota id>", "period": {"start": "…", "end": "…", "iso_week": "2026-W47"},
                  "start_points": [{"place_ref": "…", "mode_ref": null}], "end_points": [...],
                  "samples_required": 6, "candidates_requested": 30 } ] }
  ```
  `samples_required = samples_planned + samples_carried_in - samples_obtained`; `candidates_requested = ceil(samples_required * oversampling_factor)`. La semilla **no** va en el payload. Pone las cuotas en `open` y suma 1 a `demands_count`.
- `cl_emit_due_demands(p_today date DEFAULT NULL) RETURNS int`: por cada plan `active` con conector `active` o `testing`, toma sus cuotas `pending` con `period_end + close_lag_days <= hoy` (hoy en la zona de la cuenta si `p_today` es NULL) y llama a `cl_build_demand` (una demanda por plan y ejecución). Cierra como `closed` los planes cuya `end_date + close_lag_days` ha pasado y no tienen cuotas `pending` ni `open`.
- Job de `pg_cron` `cl-emit-demands`, `15 * * * *`, comando `SELECT public.cl_emit_due_demands();` (sin token ni llamada HTTP).

- [ ] **Step 1: Test**: con `p_today` = `period_end + 6` no emite; con `+ 7` emite 1 demanda con 1 estrato, `candidates_requested = 30` para cuota 6 y factor 5; el payload lleva los `place_ref` de los puntos y el valor de producto del carrier; `random_seed` no aparece dentro de `payload`; segunda llamada el mismo día no emite otra; plan `draft` no emite.
- [ ] **Step 2–4:** FAIL → migración → PASS.
- [ ] **Step 5: Commit** `feat(carrier-link): emisión de demandas`.

### Task 7: Entrada del lote: equivalencias, resolución y validación

**Files:**
- Create: `supabase/migrations/20261120110500_cl_ingest.sql`
- Test: `supabase/tests/cl_ingest.test.sql`

**Interfaces — Produces:**
- `cl_ingest_batch(p_feed_id uuid, p_payload jsonb, p_dry_run boolean DEFAULT false) RETURNS jsonb`. Solo `service_role`. `p_payload`:
  ```json
  { "demand_id": "…", "batch_id": "<id del conector>",
    "strata": [ { "stratum_id": "…", "population_size": 48213,
                  "selection_method": "uniform_random_within_stratum",
                  "rows": [ { "<campos del carrier>": "…" } ] } ] }
  ```
  Comportamiento, en orden:
  1. La demanda debe ser de `p_feed_id` y estar `open`; si no, excepción `'CL_DEMAND_NOT_OPEN'`.
  2. `(demand_id, batch_id)` ya existente → devuelve su `summary` sin escribir nada.
  3. `selection_method` distinto → lote `rejected`, alerta, fin.
  4. Por fila: aplica `cl_field_mappings` del carrier (`p_row ->> carrier_field`); `scan_at`: con `format` usa `to_timestamp(valor, format)` interpretado en `timezone` del mapeo (o `accounts.timezone`), sin `format` usa `valor::timestamptz`; producto por `cl_value_mappings` → `products.code` → `product_id`; campos de `cl_extra_fields` se guardan en `extra`, el resto se descarta.
  5. Resuelve `reader_id` entre los puntos activos del carrier: primero lugar + modo exacto, si no lugar con modo NULL.
  6. Motivos de rechazo por fila (`reject_reason`): `missing_field`, `bad_timestamp`, `unknown_product`, `unknown_reading_point`.
  7. Por `item_id` dentro de cada estrato: inicio = primera lectura en un punto con papel `origin|both`; fin = última en un punto `destination|both`. Rechazo del candidato: `no_start`, `no_end`, `start_after_end`, `end_out_of_period` (fecha local del fin fuera de `period`), `already_sampled` (existe muestra activa con ese carrier e `item_id`; este motivo no cuenta para `rejected_ratio`).
  8. Con `p_dry_run`: devuelve el resumen y hace `ROLLBACK` lógico (no deja filas; implementar calculando en tablas temporales o con subtransacción que se revierte).
  9. Sin él: guarda `cl_batches` (`status='validated'`) y `cl_batch_scans`; alertas `rejected_ratio` (> 20 %), `unknown_product`, `population_incoherent` (`population_size` < candidatos distintos recibidos), `empty_stratum` (`population_size = 0`).
  Resumen devuelto: `{ batch: <uuid>, strata: [ { stratum_id, population_size, rows, candidates, candidates_valid, rejected: { <motivo>: n } } ] }`.

- [ ] **Step 1: Test** con un lote de 5 envíos en un estrato: campos del carrier `trk`, `svc`, `ts` (formato `DD/MM/YYYY HH24:MI`, zona `Africa/Nairobi`), `office`, `evt`; uno sin lectura de fin (`no_end`), uno con fin fuera del periodo, uno con producto desconocido, dos válidos → `candidates_valid = 2`; la hora `20/10/2026 09:14` queda como `2026-10-20 06:14+00`; un campo `recipient_name` no permitido no aparece en ninguna tabla; mismo lote otra vez → mismo resumen y mismo número de filas en `cl_batch_scans`; `p_dry_run` no deja filas; demanda de otro conector → excepción; lugar con punto específico y punto "cualquier modo" → se resuelve al específico.
- [ ] **Step 2–4:** FAIL → migración → PASS.
- [ ] **Step 5: Commit** `feat(carrier-link): entrada y validación de lotes`.

### Task 8: Sorteo, muestra y paso a E2E

**Files:**
- Create: `supabase/migrations/20261120110600_cl_sampler.sql`
- Test: `supabase/tests/cl_sampler.test.sql`

**Interfaces — Produces:**
- `cl_sample_stratum(p_batch_id uuid, p_stratum_id uuid) RETURNS jsonb`. Solo `service_role`. Idempotente por `(batch_id, stratum_id)` (si existe `cl_sampling_runs`, devuelve su resumen).
  - Orden del sorteo: candidatos válidos ordenados por `md5(random_seed || ':' || item_id)`, desempate `item_id COLLATE "C"`; se toman los primeros `samples_required` del estrato (el valor que quedó en el payload de la demanda).
  - Por elegido: `cl_samples` (ciudades = las del centro postal de sus lectores de inicio y fin), `cl_sample_scans` (todas sus lecturas de inicio y fin con su `role`), y `cl_transfer_sample`.
  - `possible_misrouting = true` si tiene lecturas de inicio en más de un punto, de fin en más de un punto, o si su ciudad de origen o destino no es la de la cuota → alerta `possible_misrouting`.
  - Suma a `cl_plan_quotas.samples_obtained`; escribe `cl_sampling_runs`; alertas `insufficient_candidates`, `suspicious_distribution` (n ≥ 20 y 100 % en plazo).
- `cl_transfer_sample(p_sample_id uuid) RETURNS uuid`: inserta en `one_db` (`source='carrier'`, `cl_sample_id`, `carrier_id`, `tag_id = item_id`, `plan_name`, nombres según Global Constraints, `sent_at = start_at`, `received_at = end_at`, `equivalence_*` de `cl_equivalence` del estándar de la ruta o NULL, `source_data_snapshot = jsonb` con `sample_id`, `plan_id`, `start_reader_id`, `end_reader_id`, `origin_city_id`, `destination_city_id`, `extra`); después `on_time_delivery = one_db_on_time(business_transit_hours, business_transit_days, standard_time, time_unit)`. Sin estándar: `on_time_delivery` NULL y alerta `missing_standard` (una por ruta y plan, no por muestra).
- `cl_finish_batch(p_batch_id uuid) RETURNS jsonb`: cuando todos los estratos del lote tienen `cl_sampling_runs`: lote `sampled`, demanda `fulfilled` o `partial`, y llama a `cl_settle_quota` (Task 9) por cada cuota.

- [ ] **Step 1: Test**: 10 candidatos válidos, cuota 4 → 4 muestras, 4 filas `one_db` con `source='carrier'`, `tag_id` idéntico al `item_id` recibido (incluido uno con guiones y ceros a la izquierda, p. ej. `00-12 34`); repetir `cl_sample_stratum` no crea más; rehacer el mismo escenario en otra transacción con la misma semilla fija elige los mismos `item_id`; con estándar de 48 h y último tramo 12 h, una muestra de 40 h hábiles medidas queda `business_transit_hours = 52`, `measured_business_hours = 40`, `on_time_delivery = false`; ruta sin estándar → `on_time_delivery IS NULL` y una sola alerta `missing_standard` para 3 muestras; envío con fin en una ciudad distinta de la pedida → muestra creada, `possible_misrouting`, `destination_city_name` = la real.
- [ ] **Step 2–4:** FAIL → migración → `bash supabase/tests/run_tests.sh cl_sampler cl_equivalence` PASS.
- [ ] **Step 5: Commit** `feat(carrier-link): sorteo reproducible y paso a la base E2E`.

### Task 9: Cuota no cubierta y deshacer un lote

**Files:**
- Create: `supabase/migrations/20261120110700_cl_settle_undo.sql`
- Test: `supabase/tests/cl_settle_undo.test.sql`

**Interfaces — Produces:**
- `cl_settle_quota(p_quota_id uuid) RETURNS text` (devuelve el estado final). Con `falta = samples_planned + samples_carried_in - samples_obtained`:
  - `falta <= 0` → `fulfilled`.
  - si la última población informada del estrato > candidatos distintos ya recibidos para esa cuota y `demands_count < 3` → vuelve a `pending` (la siguiente ejecución de `cl_emit_due_demands` pide solo lo que falta).
  - si no: reparte `falta` entre las cuotas `pending` de la misma ruta y plan en el mismo mes natural de `period_start` (reparto a partes iguales, el resto a las más tempranas); si no hay ninguna, entre las de meses posteriores con el mismo criterio; la cuota queda `carried`. Si no queda ninguna cuota posterior → `unfilled` y alerta `quota_unfilled`.
- `cl_undo_batch(p_batch_id uuid) RETURNS jsonb`. Requiere `edit` en `cl_monitor`. Borra las filas `one_db` de sus muestras, marca las muestras `voided`, resta de `samples_obtained`, borra sus `cl_sampling_runs`, pone el lote `undone`, la demanda `failed` y las cuotas afectadas que no estén `carried` en `pending`. Las cuotas que ya repartieron su déficit se dejan como están y se abre la alerta `undo_after_carry` para revisión manual.

- [ ] **Step 1: Test**: cuota 6, obtenidas 2, población 2 → `carried`, y las dos semanas siguientes del mes reciben +2 cada una; déficit 5 entre 2 semanas → +3 y +2 (la primera recibe el resto); última semana del mes → reparte en el mes siguiente; última cuota del plan → `unfilled` con alerta; población 40, recibidos 30, `demands_count=1` → `pending`; con `demands_count=3` → `carried`; `cl_undo_batch` deja 0 filas `one_db` de ese lote, muestras `voided`, y el mismo `item_id` puede volver a ser muestra; usuario sin `cl_monitor` edit → excepción.
- [ ] **Step 2–4:** FAIL → migración → PASS.
- [ ] **Step 5: Commit** `feat(carrier-link): reparto del déficit y deshacer lote`.

### Task 10: Edge Function `carrier-link-ingest`

**Files:**
- Create: `supabase/functions/carrier-link-ingest/index.ts`, `lib.ts`, `lib.test.ts`
- Modify: `supabase/config.toml` (`[functions.carrier-link-ingest] verify_jwt = false`)

**Interfaces:**
- Consumes: `api_key_resolve`, `cl_ingest_batch`, `cl_sample_stratum`, `cl_finish_batch`.
- Produces:
  - `GET  /carrier-link-ingest/demands` → `{ demands: [payload…] }` de las demandas `open` del conector de la clave.
  - `POST /carrier-link-ingest/batches?dry_run=true|false` con el lote → resumen de `cl_ingest_batch`; sin `dry_run`, además llama a `cl_sample_stratum` por cada estrato (una llamada RPC por estrato) y a `cl_finish_batch`.
  - Autenticación: `Authorization: Bearer <clave>`; se exige `scope === 'carrier_feed'` y `feed_id` no nulo; ese `feed_id` es el único que se pasa a las funciones.
  - Límites (constantes en `lib.ts`): cuerpo ≤ 5 MB (413), ≤ 20 000 filas por lote (413), 30 peticiones por minuto por clave usando `api_usage_log` (429).
  - Conector `paused` → 403. Conector `testing` → solo se aceptan lotes con `dry_run=true`.
  - `lib.ts`: `countRows(batch: unknown): number`, `validateEnvelope(batch: unknown): { ok: true } | { ok: false; error: string }` (exige `demand_id`, `batch_id`, `strata[]` con `stratum_id`, `population_size` entero ≥ 0, `selection_method`, `rows[]`).

- [ ] **Step 1: Test** `lib.test.ts`: lote sin `batch_id` → error; `population_size` negativo → error; `countRows` suma las filas de todos los estratos; estrato sin `rows` → error.
- [ ] **Step 2:** `deno test supabase/functions/carrier-link-ingest/lib.test.ts` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** `deno test …` → PASS.
- [ ] **Step 5: Commit** `feat(carrier-link): API de entrada para conectores`.

### Task 11: Origen del dato en los informes E2E y en la API

**Files:**
- Modify: `src/contexts/ReportingFiltersContext.tsx`, `src/components/reporting/ReportFilters.tsx`, `src/components/reporting/TerritoryEquityFilters.tsx`, `src/hooks/reporting/useReportingGeneral.ts`, `useComplianceData.ts`, `useJKPerformance.ts`, `useCarrierProductOverview.ts`, `useTerritoryEquityDataV2.ts`, `src/lib/e2eCalculations.ts`, `src/hooks/useOneDB.ts`, `src/pages/OneDB.tsx`, traducciones ×5.
- Modify: `supabase/functions/onedb-api/index.ts`

**Interfaces — Produces:**
- `ReportingFilters.source: '' | 'panelist' | 'carrier'` (`''` = todos, valor por defecto).
- `applySourceFilter<T>(query: T, source: string): T` en `src/lib/e2eCalculations.ts` (añade `.eq('source', source)` si no está vacío), usada por todos los hooks listados.
- Selector "Origen del dato" (Todos / Panelistas / Carrier) en los dos componentes de filtros; se oculta si la cuenta no tiene ninguna fila `carrier` en `one_db` (consulta `head: true, count` con `source='carrier'`).
- Página E2E DB (`OneDB.tsx`): columna "Origen"; en el detalle de una fila `carrier`, tiempo medido y tiempo de equivalencia añadido.
- Nota metodológica (texto traducido) visible cuando el filtro está en "Todos" y hay filas de ambos orígenes.
- `onedb-api`: aplica `source` si viene; cada fila ya lleva `source`.

- [ ] **Step 1: Test** vitest de `applySourceFilter` con un doble de consulta: `''` no llama a `eq`; `'carrier'` llama `eq('source','carrier')`.
- [ ] **Step 2:** `npm test` → FAIL.
- [ ] **Step 3:** Implementar y traducir.
- [ ] **Step 4:** `npm test && npm run lint && npm run build` → PASS. Comprobación manual en el servidor de desarrollo: con filtro "Panelistas" los totales de General Performance coinciden con los de antes del cambio.
- [ ] **Step 5: Commit** `feat(carrier-link): origen del dato en los informes E2E`.

### Task 12: Prueba completa en DEMO2

**Files:**
- Create: `supabase/tests/adhoc/cl_demo2_setup.sql`, `supabase/tests/adhoc/cl_demo2_batch.json`, `supabase/tests/adhoc/cl_demo2_check.sql`, `supabase/tests/adhoc/cl_demo2_cleanup.sql`

Cada paso que escribe en `onems-dev` (`sehbnpgzqljrsqimwyuz`) se ejecuta **solo tras confirmación explícita del responsable**.

- [ ] **Step 1:** Aplicar las migraciones del plan (envueltas en `BEGIN/COMMIT` con su `INSERT INTO supabase_migrations.schema_migrations`), `NOTIFY pgrst, 'reload schema'`, y desplegar `carrier-link-ingest` y `onedb-api`.
- [ ] **Step 2:** `cl_demo2_setup.sql`: en DEMO2, un conector `testing`, equivalencias de campos y de producto, 2 centros con ciudad, 4 puntos de lectura (inicio y fin en 2 ciudades), un estándar con último tramo, un plan con 2 cuotas en semanas ya vencidas; activar el plan; `SELECT cl_emit_due_demands();`. Emitir la clave del conector con `api_key_issue(..., 'carrier_feed', <feed>)` y **no** escribirla en ningún fichero.
- [ ] **Step 3:** `GET /demands` con la clave → 1 demanda. `POST /batches?dry_run=true` con `cl_demo2_batch.json` (≈40 envíos inventados, con 2 rechazos deliberados y 1 mal encaminado) → resumen esperado. Poner el conector `active` y repetir sin `dry_run`.
- [ ] **Step 4:** `cl_demo2_check.sql` (solo lectura): número de muestras = cuotas pedidas; filas `one_db` `source='carrier'` con `measured_*` y equivalencia; 1 alerta `possible_misrouting`; ninguna fila nueva en `allocation_plan_details` ni en `incidents`.
- [ ] **Step 5:** En la web de desarrollo, cuenta DEMO2: las muestras aparecen en General Performance, Compliance y Territory Equity; filtro "Carrier" las aísla; filtro "Panelistas" da las cifras anteriores.
- [ ] **Step 6:** Probar `cl_undo_batch` y comprobar que los informes vuelven a las cifras anteriores. Dejar DEMO2 limpio con `cl_demo2_cleanup.sql` o con los datos de demostración, según diga el responsable.
- [ ] **Step 7: Commit** de los ficheros `adhoc` (sin claves).
