# GPS fase 1 — juzgar solo por distancia (arreglo inmediato) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que la posición GPS de una declaración se juzgue solo por la distancia (Telegram no envía precisión), que
`low_accuracy`/`far` dejen de abrir incidencias, recalcular lo guardado desde el 17/11 y que las pruebas diarias del
agente no cuenten la incidencia GPS del panelista de prueba como efecto inesperado.

**Architecture:** Solo BD (onems-dev). Tres migraciones forward-only que reemplazan funciones existentes
(`CREATE OR REPLACE`) y corrigen datos. El bot n8n no cambia: deja de recibir la acción `low_accuracy_retry`, y esa
rama queda sin uso (se limpia en la fase 2, cuando se toque el bot).

**Tech Stack:** PostgreSQL 17 (Supabase), plpgsql; pruebas con psql contra el Postgres portable local
(`127.0.0.1:5433`, `supabase/tests/replay.ps1`).

**Spec:** `docs/superpowers/specs/2026-11-20-gps-casa-apartado-design.md` §5.1 (fases 2+ en planes aparte).

## Global Constraints

- BD única onems-dev `sehbnpgzqljrsqimwyuz`. **Antes de aplicar nada en ella: nombrar proyecto + ref y pedir
  confirmación explícita a Ignacio.** Nunca `db push`/`db reset` remoto.
- Forward-only: migraciones nuevas con timestamp `2026112018xxxx` (Carrier Link usa `2026112011xxxx`; ver Coexistencia).
- Partir de la definición **viva** de cada función (`pg_get_functiondef`), comprobando que coincide con la del repo
  (`20261117150000_gps_declaracion.sql` y siguientes); si difiere, gana la viva y se avisa.
- Radio «en el sitio correcto»: **300 m** (spec §5.5), guardado en configuración, no fijo en código.
- `accuracy_m` se sigue guardando si llega, pero no cambia el estado.
- Nunca bloquear una declaración; nunca mensajes nuevos al panelista en esta fase.
- Aislamiento por `account_id` en todo; RLS en toda tabla nueva.
- Trabajar en un worktree desde `origin/main` (rama `fix/gps-solo-distancia`); el checkout principal tiene trabajo
  ajeno sin commitear. Commit/PR solo si Ignacio lo pide.

## Coexistencia con Carrier Link (otra sesión en paralelo, rama `feat/carrier-link`, worktree `ONEMS_wt_carrier_link`)

Comprobado el 20/11:
- Carrier Link ya está **aplicado en onems-dev** hasta `20261120110800_cl_final_fixes` y tiene más en curso
  (`110900_cl_ingest_safeupdate`). Usa la serie `2026112011xxxx` → esta fase usa **`2026112018xxxx`** (no repetir
  números de versión ni intercalarse en su serie).
- **No toca** `gps_*`, `ops_test.*`, `panelist_incident` ni `declaration_location`: sin choque de objetos en esta fase.
- **Sí redefine `ops_report._data`** (el informe, en `cl_final_fixes`), que cuenta los estados GPS. Esta fase no lo
  toca (los recuentos de `low_accuracy` simplemente bajarán a 0). **La fase 2 (informe) debe partir de la versión de
  Carrier Link**, no de la de `20261117160000_ops_report_gps.sql`.
- Pruebas locales: el Postgres portable (`5433`) es compartido y `replay.ps1` recrea siempre la BD `onems_test`.
  Esta fase usa **otra BD local, `onems_test_gps`** (copia de `replay.ps1` en el scratchpad con `$DB` cambiado),
  para no borrar la de la otra sesión a mitad de sus pruebas.
- Antes de aplicar (Task 4): `list_migrations` en onems-dev para ver qué ha aplicado Carrier Link entretanto y
  confirmar que ninguna de sus migraciones nuevas redefine las funciones de esta fase.
- No se toca el worktree, la rama ni los ficheros de Carrier Link.

## Review Focus

1. Panelista sin nodo, o nodo sin centro con coordenadas → `no_reference`, sin error (la función no debe lanzar).
2. Incidencia GPS que mezcla declaraciones `no_location` con `low_accuracy` → al recalcular **sigue abierta** (solo
   se cierran las que ya no tienen ningún `no_location`/`gps_unavailable`).
3. Incidencia de «No acepto» (sin `details` en el payload) → el recálculo no la toca.
4. Recálculo ejecutado dos veces → mismo resultado (idempotente).
5. Otra cuenta con incidencias GPS → solo se borran las del panelista de prueba de `ops_test.config`.

---

### Task 1: Clasificación por distancia y menos incidencias

**Files:**
- Create: `supabase/migrations/20261120180000_gps_solo_distancia.sql`
- Test: `supabase/tests/gps_solo_distancia.test.sql` (misma fixture y estilo que `gps_declaracion.test.sql`:
  `\ir fixtures/incident_city.sql`, `pg_temp.gps_fixture()`, `pg_temp.fail_if`, cada escenario en BEGIN/ROLLBACK)

**Interfaces:**
- Produces: tabla `public.gps_settings(key text primary key, value numeric not null)` con fila
  `('ok_radius_m', 300)`, RLS activado sin políticas (solo la leen funciones SECURITY DEFINER);
  `public.gps_setting(p_key text) RETURNS numeric` (STABLE, SECURITY DEFINER, `search_path = ''`).
- Produces: `public.gps_classify(p_center uuid, p_dist numeric) RETURNS text` → `'no_reference'` si `p_center` es
  NULL; `'far'` si `p_dist > gps_setting('ok_radius_m')`; si no `'ok'`. La usan esta tarea y la Task 2.
- Modifies (misma firma): `gps_save_location(...)`, `gps_mark_declaration(...)`, `gps_refresh_incident(...)`.

- [ ] **Step 1: Escribir las pruebas que fallan**

Escenarios (centro A en (-1.28, 36.82); 0.0009° lat ≈ 100 m; permiso `granted` antes de cada uno):
- `sin_precision_cerca`: `gps_save_location(P1,'1001',-1.28180,36.82,NULL,now(),'m1')` (≈200 m) →
  `action='saved'`, `status='ok'`; fila en `declaration_location` con `accuracy_m IS NULL`, `status='ok'`.
- `sin_precision_lejos`: punto a ≈400 m (`-1.28360`) → `status='far'`.
- `precision_mala_no_cambia`: ≈200 m con `p_accuracy = 900` → `status='ok'`, `accuracy_m = 900`, y **nunca**
  `action='low_accuracy_retry'`.
- `sin_referencia`: P4 (City2, centro sin coordenadas) → `status='no_reference'`.
- `umbral_configurable`: `UPDATE gps_settings SET value=100 WHERE key='ok_radius_m'` → el punto de ≈200 m da `far`.
- `far_no_abre_incidencia`: visita con posición `far` + `gps_mark_declaration(D1,'sent',P1)` → `status='far'`,
  0 filas nuevas en `panelist_incident` con `category='gps_location'`.
- `sin_posicion_si_abre`: `gps_mark_declaration` sin posición → `status='no_location'` y 1 incidencia `open`
  (comportamiento del 17/11 intacto).
- `refresh_cierra_sin_problemas`: incidencia `open` con un detalle `no_location`; llega posición `far` en la ventana
  (enlace retroactivo) → la incidencia pasa a `auto_resolved` (antes exigía todo `ok`).

- [ ] **Step 2: Correr y ver que fallan**

Run: la copia de `replay.ps1` con `$DB = "onems_test_gps"` (ver Coexistencia; nunca el `replay.ps1` original) y luego
`psql -h 127.0.0.1 -p 5433 -U postgres -d onems_test_gps -v ON_ERROR_STOP=1 -f supabase\tests\gps_solo_distancia.test.sql`
Expected: FAIL en `sin_precision_cerca` (hoy devuelve `low_accuracy_retry`).

- [ ] **Step 3: Implementar la migración**

- `gps_save_location`: `v_status := public.gps_classify(v_center, v_dist)`; quitar el bloque `low_accuracy_retry`.
  Todo lo demás igual (inserción, enlace retroactivo, `gps_refresh_incident`).
- `gps_mark_declaration`: la incidencia por visita se abre/actualiza solo si
  `v_status IN ('no_location','gps_unavailable')` (antes también `low_accuracy`,`far`).
- `gps_refresh_incident`: «sin problemas» = ningún detalle con estado en `('no_location','gps_unavailable')`
  (antes: todos `ok`); con eso pasa `open → auto_resolved` como hoy.

- [ ] **Step 4: Correr las pruebas nuevas y las existentes de GPS**

Run: replay + `gps_solo_distancia.test.sql`, `gps_declaracion.test.sql`, `gps_ask_once.test.sql`,
`gps_consent_keep.test.sql`, `gps_erase.test.sql`, `ops_report_gps.test.sql`.
Expected: todo PASS. Si alguna prueba antigua afirmaba `low_accuracy`/`low_accuracy_retry` o la incidencia por
`far`, se actualiza a la regla nueva (anotarlo en el informe de la tarea).

- [ ] **Step 5: Commit** (solo si Ignacio lo ha pedido; si no, dejar los ficheros preparados)

### Task 2: Recalcular lo guardado desde el 17/11

**Files:**
- Create: `supabase/migrations/20261120180100_gps_solo_distancia_recalculo.sql`
- Test: añadir escenarios a `supabase/tests/gps_solo_distancia.test.sql`

**Interfaces:**
- Consumes: `gps_classify(uuid, numeric)` de la Task 1.
- Produces: datos corregidos; sin funciones nuevas (bloque `DO` dentro de la migración).

- [ ] **Step 1: Pruebas que fallan** (insertando a mano filas «antiguas» y ejecutando el bloque del recálculo,
  extraído a `pg_temp.recalc()` en la prueba con el mismo SQL que la migración):
- `recalc_location`: `declaration_location` con `status='low_accuracy'`, centro A, `distance_m=150` → `ok`; con
  `distance_m=2000` → `far`; sin centro → `no_reference`.
- `recalc_marcas`: D1 con `sent_location_id` = esa fila y `sent_gps_status='low_accuracy'` → pasa al estado de la
  fila; D2 con `received_gps_status='no_location'` (sin location) → no cambia.
- `recalc_incidencia_solo_precision`: incidencia `open` con detalles solo `low_accuracy` → `auto_resolved`,
  `resolved_at` no nulo, `resolution_note` =
  `'Regla corregida el 20/11: Telegram no envía la precisión; la posición se juzga solo por la distancia.'`,
  y los estados de `payload.details` actualizados.
- `recalc_incidencia_mixta` (Review Focus 2): detalles `low_accuracy` + `no_location` → sigue `open`, detalles
  actualizados.
- `recalc_no_consent` (Review Focus 3): incidencia `gps_location` sin `details` → intacta.
- `recalc_idempotente` (Review Focus 4): ejecutar dos veces → mismas filas y estados.

- [ ] **Step 2: Correr y ver que fallan.** Expected: FAIL en `recalc_location`.

- [ ] **Step 3: Implementar el bloque de recálculo** (en una transacción, en este orden):
  1. `declaration_location`: `status := gps_classify(nearest_postal_center_id, distance_m)` donde
     `status IN ('low_accuracy','far','ok')`.
  2. `allocation_plan_details`: `sent_gps_status` / `received_gps_status` = estado de su `*_location_id` cuando el
     estado actual está en `('low_accuracy','far','ok')`.
  3. Incidencias `gps_location` `open`/`in_progress` con `details` array: refrescar estados de `details` desde
     `allocation_plan_details`; si ningún detalle queda en `('no_location','gps_unavailable')` → `auto_resolved`,
     `resolved_at = now()`, `resolution_note` (texto exacto de arriba).
  4. `RAISE NOTICE` con los recuentos de cada paso.

- [ ] **Step 4: Correr todas las pruebas GPS.** Expected: PASS.

- [ ] **Step 5: Commit** (misma regla que la Task 1).

### Task 3: Pruebas diarias del agente sin falso «efecto inesperado»

**Files:**
- Create: `supabase/migrations/20261120180200_ops_test_gps_incident.sql`
- Test: `supabase/tests/ops_test_gps_incident.test.sql` (fixture: `ops_test.config` con cuenta y panelista de
  prueba, `ops_test.state.prepared_at` fijado; ver `20261105160000_ops_agent_test_fixtures.sql`)

**Interfaces:**
- Modifies (misma firma): `ops_test._expected_incidents() RETURNS SETOF uuid`.

- [ ] **Step 1: Pruebas que fallan**
- `gps_esperada`: incidencia `gps_location` del panelista de prueba creada tras `prepared_at` → aparece en
  `_expected_incidents()`; `ops_test_status(token)` no lista «incidencias no esperadas».
- `reset_la_borra`: `ops_test._reset()` borra esa incidencia y sus `incident_message`.
- `otra_cuenta_intacta` (Review Focus 5): incidencia `gps_location` de otro panelista u otra cuenta → no aparece ni
  se borra.

- [ ] **Step 2: Correr y ver que fallan.** Expected: FAIL en `gps_esperada`.

- [ ] **Step 3: Implementar**
- `_expected_incidents()`: `i.category IN ('parcel_damaged','gps_location')`; el resto de condiciones igual
  (panelista de prueba, cuenta de prueba, `created_at >= prepared_at`). `created_via` se exige solo para
  `parcel_damaged` (comprobar el valor real de `created_via` en las incidencias GPS antes de decidir).
- Limpieza puntual en la misma migración: borrar las incidencias `gps_location` del panelista de prueba
  (`ops_test.config.tester_panelist_id`, `account_id` de la config) y sus `incident_message`. En onems-dev son 4
  (17, 18, 19 y 20/11).

- [ ] **Step 4: Correr las pruebas.** Expected: PASS.

- [ ] **Step 5: Commit** (misma regla).

### Task 4: Aplicar en onems-dev y verificar

- [ ] **Step 1:** Comparar la definición viva de `gps_save_location`, `gps_mark_declaration`,
  `gps_refresh_incident` y `ops_test._expected_incidents` con las que reemplazan las migraciones (sin otros cambios).
- [ ] **Step 2:** Pedir a Ignacio confirmación explícita: «aplico 3 migraciones en onems-dev
  (`sehbnpgzqljrsqimwyuz`)».
- [ ] **Step 3:** Aplicar las 3 migraciones en orden (`apply_migration`).
- [ ] **Step 4:** Verificar con consultas:
  - `declaration_location`: 0 filas `low_accuracy`; reparto `ok`/`far`/`no_reference` por cuenta (esperado en
    Kenya: unos 4 panelistas `ok` y el resto `far`).
  - `allocation_plan_details`: 0 marcas `low_accuracy` desde el 17/11.
  - `panelist_incident` `gps_location` abiertas: solo las de `no_location`/`gps_unavailable`/permiso.
  - 0 incidencias `gps_location` del panelista de prueba.
- [ ] **Step 5:** Al día siguiente (informe de salud de las 08:00): sin «Las pruebas dejaron efectos inesperados»
  por GPS. Con Ignacio, una declaración real de prueba en el bot PROD: el bot ya no pide «Reintentar».
- [ ] **Step 6:** Actualizar la memoria `gps-declaracion` con el estado.
