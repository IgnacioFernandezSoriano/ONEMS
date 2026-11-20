# Carrier Link fase 2 — Pantallas — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Una tercera pestaña "Carrier Link" con cinco pantallas (Planes de muestreo, Muestras, Puntos de lectura, Conectores, Monitor) y los dos tiempos de equivalencia en SLA E2E, para que un Account Manager monte y siga un plan sin guiones SQL.

**Architecture:** Patrón de la app: página → hook → supabase. El motor ya existe en la base (fases 0-1, vivas en prod); las pantallas escriben directamente en las tablas que RLS permite (`cl_plans`, `cl_feeds`, mapeos, `readers` carrier_scan, `cl_alerts.status`) y llaman a las RPC existentes (`cl_plan_set_quotas`, `cl_plan_missing_points`, `cl_plan_missing_standards`, `cl_plan_activate`, `cl_undo_batch`, `api_key_issue`). Lo único nuevo en la base es un envoltorio para el ensayo de lote desde el navegador. Las cuotas se calculan en el navegador con una librería pura que reutiliza el reparto semanal del generador del allocation plan.

**Tech Stack:** React 18 + TypeScript + Vite + Tailwind, `@supabase/supabase-js`, vitest (solo funciones puras de `src/lib`), Postgres 17 (tests SQL locales `supabase/tests`).

**Spec:** `docs/superpowers/specs/2026-11-19-carrier-link-design.md` §3, §5, §7 (y R16, R18, R22, R23) + boceto aprobado por el responsable el 20/11 (resumido en "Pantallas" abajo).

## Global Constraints

- Única base: `onems-dev` (`sehbnpgzqljrsqimwyuz`). Ninguna escritura remota sin confirmación explícita del responsable; los tests SQL corren en el Postgres local (`bash .superpowers/sdd/runlocal.sh <test>`).
- Rama `feat/carrier-link-fase2` en un worktree propio, creada desde la rama `fix/carrier-link-wave2` ya revisada (o desde `origin/main` si ya se fusionó). Migración nueva con timestamp posterior a `20261120111000`: `20261121100000_cl_ui_dry_run.sql`.
- Todo texto visible pasa por `useTranslation()` (`@/hooks/useTranslation`; el Sidebar usa `useLocale().t`) y se añade en los 5 CSV `public/locales/{en,es,fr,ar,pt}.csv` (formato `key,translation`). Prefijo de claves nuevas: `cl.` (las de menú `menu.carrier_link` y `menu.cl_*` ya existen).
- Permisos con `usePermissions()` (`canView(opt)`, `canEdit(opt)`) sobre las opciones `cl_plans`, `cl_samples`, `cl_reading_points`, `cl_connectors`, `cl_monitor`; en solo lectura no se pinta ningún botón de escritura y se muestra `<ReadOnlyBadge/>`.
- Claves de conector: solo superadmin o UPU Account Manager (`rpc('is_upu_account_manager', {p_account_id})`), aunque el usuario tenga `edit` en `cl_connectors`. La clave en claro se muestra una sola vez.
- Cuenta: `useEffectiveAccountId()`; si es `null` (superadmin con "todas"), las pantallas piden elegir una cuenta y no escriben nada.
- Lectores del carrier: siempre `capture_source = 'carrier_scan'` y `deleted_at IS NULL`; nunca se tocan lectores `rfid`.
- Errores `CL_*` de la base se muestran traducidos (mapa en `src/lib/carrierLink/clErrors.ts`), nunca el texto crudo de Postgres.
- `npm run lint` (0 warnings), `npm run build` y `npm test` pasan al final de cada tarea de frontend.

## Review Focus

- Superadmin con "todas las cuentas" seleccionado → ninguna pantalla inserta con `account_id` nulo; aparece el aviso de elegir cuenta (tests de los constructores de filas en Tasks 4-6).
- Plan que cruza fin de año (p. ej. 21/12/2026 → 10/01/2027) → semanas con año ISO correcto (2026-W53 y 2027-W01), sin duplicar ni perder semanas (test en Task 2).
- Total menor que rutas × semanas → la suma de cuotas es exactamente el total y muchas celdas quedan a 0, sin negativos (test en Task 2).
- Activar con puntos o cuotas que faltan → mensaje traducido que nombra las ciudades (`CL_MISSING_POINTS`, `CL_NO_QUOTAS`), no un error genérico (test del mapa de errores en Task 3).
- Usuario con `view` en Conectores o sin rol UPU AM → no ve "Nueva clave"; un DO Coordinator edita puntos pero no conectores (test de `canManageCarrierKeys` en Task 5 y de visibilidad del menú en Task 3).

---

## Pantallas (boceto aprobado, resumido)

- **Planes de muestreo** (`/carrier-link/plans`, `cl_plans`): lista de planes; formulario nombre, carrier, producto, conector, periodo, total, casilla diagnóstico; "Generar cuotas" → tabla ruta × semana con "previsto (+arrastrado) ✓obtenido"; aviso ⚠ por ruta sin estándar; "Activar plan" deshabilitado mientras falten puntos.
- **Muestras** (`/carrier-link/samples`, `cl_samples`): filtros plan, semana, ruta, "solo mal encaminados"; columnas identificador, ruta, salida, llegada, tiempo, en plazo, marca ⚠; al pulsar una fila, sus lecturas (punto, hora, papel inicio/intermedia/fin).
- **Puntos de lectura** (`/carrier-link/reading-points`, `cl_reading_points`): por carrier; lugar, modo, centro postal, ciudad, papel; alta/edición/baja; bloque "Lugares recibidos sin dar de alta" con su nº de lecturas y botón "Dar de alta" que precarga el formulario.
- **Conectores** (`/carrier-link/connectors`, `cl_connectors`): conector por carrier con estado (pruebas/activo/pausado), calendario (días + hora + zona), equivalencias de campos, de valores de producto, campos extra permitidos, claves (prefijo, caducidad, nueva clave), "Probar lote (ensayo)".
- **Monitor** (`/carrier-link/monitor`, `cl_monitor`): contadores de peticiones por estado; lotes con envíos, rechazados, elegidos y "Deshacer"; avisos con "Visto" / "Descartar".
- **SLA E2E**: columnas "Primer tramo (carrier)" y "Último tramo (carrier)" editables en línea y en el formulario.

---

### Task 1: Ensayo de lote desde el navegador (base de datos)

**Files:**
- Create: `supabase/migrations/20261121100000_cl_ui_dry_run.sql`
- Test: `supabase/tests/cl_ui_dry_run.test.sql`

**Interfaces:**
- Produces: `public.cl_dry_run_batch(p_feed_id uuid, p_payload jsonb) RETURNS jsonb` — `SECURITY DEFINER`, `SET search_path = public, extensions`, `REVOKE ALL FROM PUBLIC, anon`, `GRANT EXECUTE TO authenticated`. Autoriza si `is_superadmin()` o (el `account_id` del feed = `current_user_account_id()` y `has_any_access(account_id,'edit','cl_connectors')`); si no, `RAISE EXCEPTION 'CL_FORBIDDEN' USING ERRCODE = '42501'` (mismo error si el feed no existe). Devuelve `cl_ingest_batch(p_feed_id, p_payload, true)`. Nunca escribe nada (el ensayo de `cl_ingest_batch` ya no persiste).

- [ ] **Step 1: Test** (patrón de `supabase/tests/cl_ingest.test.sql`: fixture, `pg_temp.as_user`, `pg_temp.raises`, todo en `BEGIN … ROLLBACK`): AM de la cuenta del feed obtiene un jsonb con `dry_run = true` y el mismo `strata` que `cl_ingest_batch(...,true)`; tras la llamada `count(*)` de `cl_batches` y `cl_batch_scans` no cambia; usuario de otra cuenta → raises; usuario con `cl_connectors` solo `view` → raises; feed inexistente → raises con el mismo SQLSTATE `42501`; `anon` no tiene EXECUTE (`has_function_privilege`).
- [ ] **Step 2:** `bash .superpowers/sdd/runlocal.sh cl_ui_dry_run` → FAIL (función inexistente).
- [ ] **Step 3:** Escribir la migración.
- [ ] **Step 4:** `bash .superpowers/sdd/runlocal.sh cl_ui_dry_run cl_ingest cl_safeupdate_lint` → PASS.
- [ ] **Step 5: Commit** `feat(carrier-link): ensayo de lote desde la web (cl_dry_run_batch)`.

### Task 2: Calculadora de cuotas (librería pura)

**Files:**
- Modify: `src/lib/allocationPlanCalculator.ts` (exportar `buildPlanWeeks` y `distributeSamplesAcrossWeeks` sin cambiar su comportamiento; añadir un parámetro opcional `rng?: () => number` a `distributeSamplesAcrossWeeks`, por defecto `Math.random`)
- Create: `src/lib/carrierLink/quotaCalculator.ts`
- Test: `src/lib/__tests__/clQuotaCalculator.test.ts`

**Interfaces:**
- Produces:
  - `type ClRoute = { origin_city_id: string; destination_city_id: string; weight?: number }`
  - `type ClQuota = { origin_city_id: string; destination_city_id: string; iso_year: number; iso_week: number; samples: number }` (forma exacta que espera `cl_plan_set_quotas`)
  - `isoWeekOf(d: Date): { iso_year: number; iso_week: number }`
  - `buildClRoutes(points: { city_id: string; e2e_role: 'origin'|'destination'|'both'|'none' }[]): ClRoute[]` — todas las parejas origen (origin|both) × destino (destination|both) de ciudades distintas (no hay rutas dentro de una ciudad, R23), ordenadas por (origin, destination), sin duplicados.
  - `generateClQuotas(p: { totalSamples: number; startDate: string; endDate: string; routes: ClRoute[]; nonWorkingDays?: string[]; workingDows?: number[] }): ClQuota[]` — reparte el total entre semanas con `buildPlanWeeks` + `distributeSamplesAcrossWeeks` (rng determinista: `() => 0.5`), y cada semana entre rutas por peso (defecto 1) con restos mayores (empate: orden de rutas). Omite cuotas con `samples = 0`.

- [ ] **Step 1: Tests**: `isoWeekOf(new Date('2026-12-31'))` → `{2026, 53}`, `isoWeekOf(new Date('2027-01-04'))` → `{2027, 1}`; `buildClRoutes` con NY(origin), BAL(both), PHL(destination) → `[NY→BAL, NY→PHL, BAL→PHL]` y nunca BAL→BAL; `generateClQuotas({totalSamples:18, startDate:'2026-11-02', endDate:'2026-11-15', routes: 3 rutas})` → suma 18, 2 semanas (2026-W45, W46), cada ruta 3 por semana; total 5 con 3 rutas × 4 semanas → suma 5, ninguna negativa; periodo 2026-12-21 → 2027-01-10 contiene 2026-W53 y 2027-W01 una sola vez cada una; mismo input dos veces → resultado idéntico; peso 2 en una ruta → recibe el doble (±1); `routes: []` → `[]`.
- [ ] **Step 2:** `npx vitest run src/lib/__tests__/clQuotaCalculator.test.ts` → FAIL.
- [ ] **Step 3:** Implementar; `npx vitest run src/lib/__tests__/allocationPlanCalculator.test.ts` sigue PASS.
- [ ] **Step 4:** `npx vitest run src/lib/__tests__/clQuotaCalculator.test.ts` → PASS.
- [ ] **Step 5: Commit** `feat(carrier-link): calculadora de cuotas ruta x semana`.

### Task 3: Pestaña, rutas, permisos y errores

**Files:**
- Modify: `src/components/layout/Sidebar.tsx` (unión de módulo `'all'|'e2e'|'diagnosis'|'carrier_link'` en l.58, l.92, l.95; grupo `'CARRIER_LINK'` con 5 hijos; tercer botón de pestaña; filtros de l.561-565 y título l.574)
- Modify: `src/App.tsx` (5 `<Route>` con `ProtectedRoute option=…`), `src/lib/access.ts` (`ROUTE_OPTION` y `OPTION_ROUTE`; quitar el comentario "cl_* have no route until phase 2")
- Create: `src/pages/carrier-link/{ClPlans,ClSamples,ClReadingPoints,ClConnectors,ClMonitor}.tsx` (esqueleto con título, ayuda y `ReadOnlyBadge`), `src/components/carrier-link/SelectAccountNotice.tsx`, `src/lib/carrierLink/clErrors.ts`
- Modify: 5 CSV de `public/locales`
- Test: `src/lib/__tests__/access.test.ts` (ampliar), `src/lib/__tests__/clErrors.test.ts`

**Interfaces:**
- Produces: rutas `/carrier-link/plans` (`cl_plans`), `/carrier-link/samples` (`cl_samples`), `/carrier-link/reading-points` (`cl_reading_points`), `/carrier-link/connectors` (`cl_connectors`), `/carrier-link/monitor` (`cl_monitor`); `clErrorKey(err: { message?: string; code?: string } | null): string` que devuelve `cl.error.<code en minúsculas>` para cualquier `CL_[A-Z_]+` contenido en el mensaje (p. ej. `CL_MISSING_POINTS` → `cl.error.cl_missing_points`), `cl.error.forbidden` para SQLSTATE `42501`, `cl.error.generic` en otro caso; `SelectAccountNotice` (sin props) para `accountId === null`.

- [ ] **Step 1: Tests**: `routeAccess('/carrier-link/plans')` → `'cl_plans'` (y las 5); `OPTION_ROUTE.cl_monitor` → `'/carrier-link/monitor'`; `landingPath` de un usuario que solo ve `cl_samples` → `/carrier-link/samples`; `clErrorKey({message:'CL_MISSING_POINTS: 2 city/role…'})` → `'cl.error.cl_missing_points'`; `clErrorKey({code:'42501', message:'x'})` → `'cl.error.forbidden'`; `clErrorKey(null)` → `'cl.error.generic'`. Además un test que lee los 5 CSV y comprueba que cada `CL_*` listado en `CL_ERROR_CODES` (exportado de `clErrors.ts`: los 19 códigos `CL_BAD_PAYLOAD CL_BATCH_ALREADY_UNDONE CL_BATCH_NOT_FOUND CL_BATCH_NOT_UNDOABLE CL_BATCH_NOT_VALIDATED CL_DEMAND_NOT_OPEN CL_DUPLICATE_QUOTA CL_FEED_CARRIER_MISMATCH CL_FEED_PAUSED CL_MAPPING_INCOMPLETE CL_MISSING_POINTS CL_NO_FEED CL_NO_QUOTAS CL_PLAN_CLOSED CL_PLAN_LOCKED_FIELD CL_PLAN_NOT_DRAFT CL_QUOTA_LOCKED CL_TOO_MANY_ROWS CL_UNKNOWN_STRATUM` + `CL_FORBIDDEN` + los que añada la tanda 2, p. ej. `CL_DEMAND_TESTING_DRY_RUN_ONLY`) tiene traducción en los 5 idiomas.
- [ ] **Step 2:** `npx vitest run src/lib/__tests__/access.test.ts src/lib/__tests__/clErrors.test.ts` → FAIL.
- [ ] **Step 3:** Implementar; pestaña visible solo si el usuario ve alguna opción `cl_*` (misma regla que los grupos: un grupo se muestra si algún hijo se muestra).
- [ ] **Step 4:** Tests PASS + `npm run lint && npm run build`.
- [ ] **Step 5: Commit** `feat(carrier-link): pestaña Carrier Link, rutas y mensajes de error`.

### Task 4: Puntos de lectura

**Files:**
- Create: `src/hooks/carrierLink/useClReadingPoints.ts`, `src/lib/carrierLink/readingPoints.ts`
- Modify: `src/pages/carrier-link/ClReadingPoints.tsx`, 5 CSV
- Test: `src/lib/__tests__/clReadingPoints.test.ts`

**Interfaces:**
- Consumes: `clErrorKey`, `SelectAccountNotice` (Task 3).
- Produces:
  - `buildReadingPointRow(accountId: string | null, f: { carrier_id: string; carrier_place_ref: string; carrier_mode_ref: string; postal_center_id: string; e2e_role: 'origin'|'destination'|'both'|'none'; name: string }): { ok: true; row: Record<string, unknown> } | { ok: false; error: 'no_account'|'missing_place'|'missing_carrier'|'missing_center' }` — `row` lleva `account_id`, `capture_source:'carrier_scan'`, `carrier_place_ref` y `carrier_mode_ref` con `trim()` (modo vacío → `null`), sin `reader_id` (lo genera el trigger `readers_cl_defaults`).
  - `unknownPlaces(scans: { place_ref: string; mode_ref: string|null; reject_reason: string|null; reader_id: string|null }[]): { place_ref: string; mode_ref: string|null; readings: number }[]` — agrupa las de `reject_reason = 'unknown_reading_point'` o `reader_id` nulo, ordenadas por lecturas desc.
  - Hook `useClReadingPoints(accountId, carrierId)`: `{ points, unknown, loading, error, create(f), update(id, f), remove(id), refetch }`; lee `readers` con `capture_source='carrier_scan'`, `deleted_at IS NULL`, `carrier_id`; `remove` hace la misma baja lógica que la pantalla de lectores RFID; `unknown` lee `cl_batch_scans` de la cuenta (RLS `cl_monitor`; si no hay permiso, lista vacía sin error).

- [ ] **Step 1: Tests**: `buildReadingPointRow(null, …)` → `no_account`; lugar `'  NYC-RDC '` → `'NYC-RDC'`; modo `''` → `null`; `capture_source` siempre `'carrier_scan'`; sin `reader_id` en la fila; `unknownPlaces` agrupa 3 lecturas del mismo lugar/modo en una fila con `readings: 3` e ignora las que tienen `reader_id`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar hook y página (tabla del boceto; formulario modal; "Dar de alta" precarga lugar y modo). **Step 4:** tests PASS + lint + build.
- [ ] **Step 5: Commit** `feat(carrier-link): pantalla de puntos de lectura`.

### Task 5: Conectores

**Files:**
- Create: `src/hooks/carrierLink/useClConnectors.ts`, `src/hooks/useIsUpuAccountManager.ts`, `src/lib/carrierLink/connectorConfig.ts`
- Modify: `src/hooks/useOneDBAPI.ts` (usar `useIsUpuAccountManager`; sin cambio de comportamiento), `src/pages/carrier-link/ClConnectors.tsx`, 5 CSV
- Test: `src/lib/__tests__/clConnectorConfig.test.ts`

**Interfaces:**
- Consumes: `cl_dry_run_batch` (Task 1), `clErrorKey` (Task 3).
- Produces:
  - `STANDARD_FIELDS = ['item_id','product','scan_at','place_ref','mode_ref'] as const`
  - `validateFieldMappings(m: { standard_field: string; carrier_field: string }[]): { ok: boolean; missing: string[]; duplicates: string[] }` — obligatorios `item_id`, `scan_at`, `place_ref`; `product` y `mode_ref` opcionales; `carrier_field` vacío cuenta como ausente; duplicado = mismo `standard_field` dos veces.
  - `validateCalendar(c: { emit_days: number[]; emit_hour: number; emit_timezone: string|null }): { ok: boolean; error?: 'no_days'|'bad_day'|'bad_hour' }` — días ISO 1-7 sin repetir, hora 0-23.
  - `canManageCarrierKeys(p: { isSuperadmin: boolean; isUpuAm: boolean }): boolean`
  - `useIsUpuAccountManager(accountId: string | null): { isUpuAm: boolean; loading: boolean }`
  - Hook `useClConnectors(accountId)`: `{ feeds, mappings(feedId), save*/remove* de feed, mapeos de campos, de valores (kind 'product'), campos extra; setStatus(feedId, 'testing'|'active'|'paused'); keys(feedId); issueKey(feedId, name, expiresAt): Promise<{ id: string; api_key: string }>` (= `rpc('api_key_issue', {p_account_id, p_name, p_scope:'carrier_feed', p_feed_id, p_expires_at})`); `deactivateKey(id)`; `dryRun(feedId, payload: unknown): Promise<jsonb>` (= `rpc('cl_dry_run_batch', …)`) `}`.
- Ensayo: el usuario sube un fichero JSON con el formato de lote (§4 del spec); la pantalla muestra por estrato candidatos, válidos y rechazados por motivo, sin escribir nada. Si el fichero no es JSON válido, aviso traducido sin llamar a la base.

- [ ] **Step 1: Tests**: mapeos sin `scan_at` → `missing: ['scan_at']`; dos `item_id` → `duplicates: ['item_id']`; completos → `ok`; calendario `[]` → `no_days`, `[8]` → `bad_day`, hora 24 → `bad_hour`, `[1,1]` → `bad_day`; `canManageCarrierKeys({isSuperadmin:false,isUpuAm:false})` → `false`, cualquiera de los dos → `true`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar (la clave se muestra una vez con botón copiar, mismo patrón que `OneDBAPI.tsx`; "Nueva clave" solo si `canEdit('cl_connectors') && canManageCarrierKeys`). **Step 4:** tests PASS + lint + build; la pantalla de API E2E sigue funcionando igual.
- [ ] **Step 5: Commit** `feat(carrier-link): pantalla de conectores con equivalencias, calendario, claves y ensayo`.

### Task 6: Planes de muestreo

**Files:**
- Create: `src/hooks/carrierLink/useClPlans.ts`, `src/lib/carrierLink/planView.ts`, `src/components/carrier-link/QuotaMatrix.tsx`
- Modify: `src/pages/carrier-link/ClPlans.tsx`, 5 CSV
- Test: `src/lib/__tests__/clPlanView.test.ts`

**Interfaces:**
- Consumes: `generateClQuotas`, `buildClRoutes`, `ClQuota` (Task 2); `clErrorKey` (Task 3); puntos activos de `useClReadingPoints` (Task 4) para las rutas.
- Produces:
  - `quotaMatrix(quotas: { origin_city_id: string; destination_city_id: string; iso_year: number; iso_week: number; samples_planned: number; samples_carried_in: number; samples_obtained: number; status: string }[], cityName: (id: string) => string): { weeks: string[]; rows: { route: string; key: string; cells: Record<string, { planned: number; carried: number; obtained: number; status: string } | null>; total: number }[] }` — semanas como `'2026-W45'` ordenadas por (año, semana); filas por nombre de ruta `'Origen → Destino'`.
  - `buildPlanRow(accountId: string | null, f: { plan_name: string; carrier_id: string; product_id: string; feed_id: string; start_date: string; end_date: string; total_samples: number; feed_diagnosis: boolean }): { ok: true; row: Record<string, unknown> } | { ok: false; error: 'no_account'|'bad_period'|'bad_total'|'missing_field' }` (`bad_period` si fin < inicio; `bad_total` si < 1).
  - Hook `useClPlans(accountId)`: `{ plans, quotas(planId), create(f), update(id, f), setQuotas(planId, q: ClQuota[]), missingPoints(planId), missingStandards(planId), activate(planId) }` — `create` inserta en `cl_plans` (queda `draft`); `setQuotas` = `rpc('cl_plan_set_quotas', {p_plan_id, p_quotas})`; `activate` = `rpc('cl_plan_activate', {p_plan_id})`.
- Flujo: crear plan → "Generar cuotas" (calcula con `generateClQuotas` sobre las rutas de los puntos activos del carrier del plan y muestra la tabla antes de guardar) → "Guardar cuotas" → la página consulta `missingPoints` y `missingStandards` → "Activar" deshabilitado si hay puntos que faltan, con la lista de ciudades; rutas sin estándar con ⚠ y el texto "entra sin en plazo". En un plan activo solo se editan los campos que la base permite (nombre, total, fecha de fin…); los bloqueados aparecen deshabilitados.

- [ ] **Step 1: Tests**: `quotaMatrix` con 2 rutas × 2 semanas → `weeks: ['2026-W45','2026-W46']`, celda con `carried: 1` conservado, `total` = suma de `planned + carried`; semana sin cuota para una ruta → `null`; orden 2026-W53 antes de 2027-W01; `buildPlanRow(null, …)` → `no_account`; fin antes de inicio → `bad_period`; total 0 → `bad_total`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** tests PASS + lint + build.
- [ ] **Step 5: Commit** `feat(carrier-link): pantalla de planes de muestreo con generador de cuotas`.

### Task 7: Muestras

**Files:**
- Create: `src/hooks/carrierLink/useClSamples.ts`, `src/lib/carrierLink/sampleView.ts`
- Modify: `src/pages/carrier-link/ClSamples.tsx`, 5 CSV
- Test: `src/lib/__tests__/clSampleView.test.ts`

**Interfaces:**
- Produces:
  - `filterSamples<T extends { quota_week?: string; route_key: string; possible_misrouting: boolean }>(rows: T[], f: { week: string|null; route: string|null; misroutedOnly: boolean }): T[]`
  - `transitLabel(startAt: string, endAt: string): { days: number; hours: number }` — días con un decimal y horas enteras, a partir de la diferencia real.
  - Hook `useClSamples(accountId, planId)`: `{ samples, scans(sampleId), loading, error }` — `cl_samples` con `status='active'` (las anuladas no se listan) unido a su fila de `one_db` por `cl_sample_id` para `on_time_delivery`; `scans` lee `cl_sample_scans` ordenadas por `scan_at`.

- [ ] **Step 1: Tests**: `misroutedOnly` deja solo las marcadas; filtro de ruta y semana combinados; `transitLabel('2026-11-03T09:12:00Z','2026-11-06T14:30:00Z')` → `{days: 3.2, hours: 77}`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar (panel lateral con las lecturas al pulsar una fila). **Step 4:** tests PASS + lint + build.
- [ ] **Step 5: Commit** `feat(carrier-link): pantalla de muestras`.

### Task 8: Monitor

**Files:**
- Create: `src/hooks/carrierLink/useClMonitor.ts`, `src/lib/carrierLink/monitorView.ts`
- Modify: `src/pages/carrier-link/ClMonitor.tsx`, 5 CSV
- Test: `src/lib/__tests__/clMonitorView.test.ts`

**Interfaces:**
- Produces:
  - `demandCounts(demands: { status: string }[]): Record<'open'|'fulfilled'|'partial'|'failed', number>` (estados desconocidos se ignoran).
  - `batchSummary(b: { summary: unknown }): { shipments: number; rejected: number; selected: number }` — lee de `cl_batches.summary` (estructura real de `cl_ingest_batch`/`cl_finish_batch`; campos ausentes → 0).
  - `alertLabelKey(alertType: string): string` → `cl.alert.<alert_type>` (los 13 tipos de §5 del spec tienen traducción en los 5 idiomas: test que lee los CSV).
  - Hook `useClMonitor(accountId, planId|null)`: `{ demands, batches, alerts, undo(batchId), setAlertStatus(id, 'acknowledged'|'dismissed') }` — `undo` = `rpc('cl_undo_batch', {p_batch_id})` tras una confirmación dentro de la página (no `confirm()`), mostrando el resultado; `setAlertStatus` actualiza solo `status`.

- [ ] **Step 1: Tests**: `demandCounts` con 2 open, 1 fulfilled, 1 'raro' → `{open:2, fulfilled:1, partial:0, failed:0}`; `batchSummary({summary:{}})` → ceros; con un summary real copiado de la prueba de DEMO2 (`supabase/tests/adhoc/cl_demo2`) → `{shipments: 36, rejected: 2, selected: 18}`; `alertLabelKey('missing_standard')` → `'cl.alert.missing_standard'` y todas las claves existen en los 5 CSV.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar ("Deshacer" solo con `canEdit('cl_monitor')`; "Visto/Descartar" igual). **Step 4:** tests PASS + lint + build.
- [ ] **Step 5: Commit** `feat(carrier-link): monitor de capturas`.

### Task 9: Tiempos de equivalencia en SLA E2E

**Files:**
- Modify: `src/lib/types.ts` (`DeliveryStandard` + `cl_first_mile_time: number; cl_last_mile_time: number`), `src/hooks/useDeliveryStandards.ts` (tipos de `createStandard`, `updateStandard`, `updateMultiple`), `src/pages/DeliveryStandards.tsx` (dos columnas tras la de unidad, edición en línea por `handleInlineUpdate` ampliando su unión de campos), `src/components/delivery-standards/DeliveryStandardForm.tsx` (dos campos numéricos ≥ 0, en la unidad del estándar), 5 CSV
- Test: `src/lib/__tests__/clEquivalenceInput.test.ts` con `src/lib/carrierLink/equivalenceInput.ts`

**Interfaces:**
- Produces: `parseEquivalenceInput(v: string): number | null` — acepta `''` → `0`, decimales con punto o coma, rechaza negativos y no numéricos (`null`).
- Columnas visibles para todos los que ven SLA; la cabecera lleva una ayuda breve: "solo se suma a las muestras del carrier".

- [ ] **Step 1: Tests**: `''` → 0; `'1,5'` → 1.5; `'-1'` → null; `'abc'` → null.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** tests PASS + lint + build; editar `standard_time` en línea sigue funcionando.
- [ ] **Step 5: Commit** `feat(carrier-link): tiempos de primer y último tramo en SLA E2E`.

### Task 10: Ayuda

**Files:**
- Create: `public/help/carrier-link.{en,es,fr,ar,pt}.html` (según `docs/help/GUIA-DISENO-AYUDA.md`; árabe RTL)
- Modify: `src/lib/helpDocs.ts` (`HELP_DOCS` entrada `{ id:'carrier-link', file:'carrier-link', audience:'managers', managersOnly:true, public:false, titleKey:'help_center.doc.carrier_link.title', descKey:'help_center.doc.carrier_link.desc' }`), las 5 páginas `Cl*.tsx` (enlace "Ayuda" con `helpDocUrl('carrier-link', language, '<sección>')`), 5 CSV
- Test: `src/lib/__tests__/helpDocs.test.ts` (ampliar: la entrada existe y los 5 ficheros existen)

- Contenido: qué es Carrier Link (muestras al azar de los registros ya cerrados del carrier, R23); orden de trabajo (puntos → conector → plan → activar → monitor); qué significan los avisos; el tiempo de equivalencia; secciones con ancla `#plans`, `#samples`, `#reading-points`, `#connectors`, `#monitor`.

- [ ] **Step 1:** Ampliar el test → FAIL. **Step 2:** Escribir las páginas y la entrada. **Step 3:** `npm test && npm run lint && npm run build` → PASS.
- [ ] **Step 4: Commit** `docs(carrier-link): página de ayuda en 5 idiomas`.

### Task 11: Puesta en marcha (cada escritura con confirmación sobre `onems-dev` `sehbnpgzqljrsqimwyuz`)

- [ ] **Step 1:** Antes de aplicar: comprobar (solo lectura) que existe `20261120111000` (tanda 2) y no existe `20261121100000`.
- [ ] **Step 2:** Aplicar `20261121100000_cl_ui_dry_run.sql` (BEGIN/COMMIT + fila en `schema_migrations` + `NOTIFY pgrst, 'reload schema'`).
- [ ] **Step 3:** Subir la rama y dar al responsable los campos de los PR `feat/carrier-link-fase2` → `develop` y `develop` → `main`.
- [ ] **Step 4:** Tras publicar, con el responsable en DEMO2: recorrer las 5 pantallas sobre los datos de demostración ("Carrier Link DEMO"), ensayar un lote desde Conectores y comprobar que un usuario sin permisos de Carrier Link no ve la pestaña.
