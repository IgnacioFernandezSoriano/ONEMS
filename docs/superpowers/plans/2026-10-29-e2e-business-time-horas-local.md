# E2E business time según unidad del estándar, hora local y selector Horas/Días — Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que "a tiempo", business time y J+K se midan en horas cuando el estándar de la ruta está en horas y por fecha cuando está en días, que todas las fechas se vean en la zona de la cuenta, y que un selector Horas/Días cambie la presentación de duraciones en E2E DB y en todos los informes.

**Architecture:** Una migración Postgres añade a `one_db` las medidas en horas y las horas locales, las rellena por trigger en cualquier escritura, redefine `calculate_business_days` (hora local + `is_account_working_day`), crea `calculate_business_hours`, y arregla `transfer_to_one_db` y el recálculo por cambio de estándar; luego corrige los datos existentes. En el frontend, `AccountContext` expone la zona de la cuenta, `lib/accountTime.ts` formatea fechas y duraciones, `TimeUnitContext` + `TimeUnitToggle` llevan el selector, `lib/transitMeasure.ts` elige la medida por ruta, y cada hook/página de reporting pasa a usarlos.

**Tech Stack:** Postgres (plpgsql, triggers), tests SQL con `supabase/tests/run_tests.sh` sobre el Postgres portable local (127.0.0.1:5433), React 18 + TypeScript + Vite, recharts, `Intl.DateTimeFormat`, traducciones en `public/locales/{en,es,fr,ar}.csv`.

**Spec:** `docs/superpowers/specs/2026-10-29-e2e-business-time-horas-local-design.md`

## Global Constraints

- Una sola BD Supabase: `onems-dev`, ref `sehbnpgzqljrsqimwyuz`. Ninguna escritura remota (apply_migration, execute_sql) sin nombrar proyecto + ref y recibir OK explícito del usuario en ese momento. Nunca `supabase db push` / `db reset`.
- Migraciones forward-only con timestamp posterior a `20261029100000`; no editar migraciones anteriores ni el baseline.
- Validar SQL en local antes de proponer aplicarlo: `bash supabase/tests/run_tests.sh <test>` (reconstruye `onems_t` con shim + migraciones y corre los `*.test.sql`).
- Todo texto visible pasa por `t('clave')`; cada clave nueva se añade a los 4 CSV `public/locales/{en,es,fr,ar}.csv` (formato `key,translation`, orden alfabético de clave).
- Día laborable = `public.is_account_working_day(account_id, date)` (existe desde `20261027120000`). Un día laborable son 24 h. Festivos solo de cuenta entera (`postal_center_id IS NULL`).
- Zona de la cuenta = `accounts.timezone` (text, NOT NULL, default `'UTC'`). Formato de fecha fijo `dd/MM/yyyy HH:mm`, dígitos latinos en los 4 idiomas.
- Selector: `'hours' | 'days'`, default `'hours'`, `localStorage` clave `onems.timeUnit`. Solo afecta a presentación.
- No tocar `*.backup`, `*.bak`, `*.old`, `_old`, ni `src/hooks/reporting/useTerritoryEquityData.ts` (V1, sin uso: todas las páginas importan `useTerritoryEquityDataV2`).
- Puerta de calidad frontend: `npm run lint` (0 warnings) y `npm run build`.
- Commits en `develop`; no push. Mensajes con `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. `received_at < sent_at` en `one_db`: horas y días deben quedar en 0, nunca negativos, sin error. (Test en Task 2.)
2. Estándar con `time_unit` NULL: tratar como `'hours'` (default de la columna). (Test en Task 2.)
3. Cuenta con `timezone` ausente en la consulta del frontend (cuenta sin seleccionar, superadmin "todas"): `accountTimezone` = `'UTC'` y la pantalla no rompe. (Verificación en Task 4.)
4. `localStorage` no disponible o con valor basura: el selector arranca en `'hours'`. (Verificación en Task 5.)
5. Informe sin envíos o ruta sin estándar: duraciones muestran `N/A`, no `NaN`; "a tiempo" NULL no cuenta ni como sí ni como no. (Test en Task 2 para NULL; verificación en Tasks 8–10.)

---

## Fase 1 — Base de datos

### Task 1: Funciones `calculate_business_hours` y `calculate_business_days`

**Files:**
- Create: `supabase/migrations/20261029120000_one_db_business_time.sql` (sección 1 de 3; las Tasks 2 y 3 añaden secciones al mismo fichero)
- Create: `supabase/tests/one_db_business_time.test.sql`
- Create: `supabase/tests/fixtures/one_db_kenya.sql`

**Interfaces:**
- Produces: `public.calculate_business_hours(p_start timestamptz, p_end timestamptz, p_account_id uuid) RETURNS numeric` (2 decimales; 0 si `p_end < p_start`; NULL si alguna entrada NULL). `public.calculate_business_days(p_start timestamptz, p_end timestamptz, p_account_id uuid DEFAULT NULL) RETURNS integer` (misma firma que hoy; cuenta días locales en `[fecha(p_start), fecha(p_end))` que cumplen `is_account_working_day`; `p_account_id` NULL → zona `'UTC'` y lunes–viernes; 0 si `p_end < p_start`).

- [ ] **Step 1: Fixture**

`supabase/tests/fixtures/one_db_kenya.sql`: inserta `accounts` id `'a0000000-0000-0000-0000-000000000003'`, name `'Ken'`, slug `'ken'`, `timezone 'Africa/Nairobi'` (ya permitido por `20261026150000`). Nada más (los tests de Task 2 añaden lo suyo).

- [ ] **Step 2: Test que falla** — `supabase/tests/one_db_business_time.test.sql`, mismo estilo que `lb2_working_days.test.sql` (`\set ON_ERROR_STOP on`, `pg_temp.fail_if`, un `BEGIN … ROLLBACK` por caso, `\ir fixtures/one_db_kenya.sql`). Casos (cuenta `…0003`, instantes dados en UTC = hora Nairobi − 3 h):

```sql
-- H1: vie 2026-10-30 16:00 Nairobi (13:00Z) -> lun 2026-11-02 10:00 Nairobi (07:00Z) = 18.00
-- H2: mar 2026-10-27 16:44 Nairobi -> jue 2026-10-29 10:40 Nairobi = 41.93
-- H3: lun 09:00 -> lun 09:00 = 0.00 ; H4: fin < inicio = 0.00
-- H5: H1 con non_working_days (account …0003, postal_center_id NULL, date 2026-11-02) = 8.00
-- H6: p_account_id NULL -> calcula en UTC, lunes-viernes
-- D1: mar 2026-10-27 16:44 -> jue 2026-10-29 10:40 Nairobi = 2
-- D2: lun 09:00 -> lun 18:00 = 0
-- D3: vie 2026-10-30 16:00 -> lun 2026-11-02 10:00 = 1 ; con lunes festivo = 1 ; con viernes festivo = 0
-- D4: '2026-10-28 23:30Z' -> '2026-10-29 08:00Z' = 0 (ambos 29/10 en Nairobi; en UTC serian 1)
```
Cada caso: `SELECT pg_temp.fail_if(public.calculate_business_hours(...) IS DISTINCT FROM 18.00, 'H1 ...')`.

- [ ] **Step 3: Comprobar que falla** — `bash supabase/tests/run_tests.sh one_db_business_time` → FAIL (función no existe). Si el Postgres local no responde, arrancarlo con el comando que imprime el script.

- [ ] **Step 4: Implementar** en la migración (cabecera de comentario en español explicando el porqué, como las demás migraciones):
  - `calculate_business_hours`: `LANGUAGE plpgsql STABLE`. Zona = `COALESCE((SELECT timezone FROM accounts WHERE id = p_account_id), 'UTC')`. Convertir a local con `p_x AT TIME ZONE v_tz` (timestamp sin zona). Recorrer `generate_series(date_trunc('day', ini_local), date_trunc('day', fin_local), '1 day')`; por cada día con `is_account_working_day(p_account_id, d::date)` (si `p_account_id` IS NULL usar `extract(isodow) <= 5`) sumar `GREATEST(0, LEAST(fin_local, d + 1 day) - GREATEST(ini_local, d))` en horas (`extract(epoch …)/3600`). `ROUND(…, 2)`.
  - `calculate_business_days`: `CREATE OR REPLACE` con la firma actual (`DEFAULT NULL::uuid`), mismo esquema de zona; contar días `d` en `[ini_local::date, fin_local::date)` con la misma condición de laborable.

- [ ] **Step 5: Pasa** — `bash supabase/tests/run_tests.sh one_db_business_time` → `OK`. Después `bash supabase/tests/run_tests.sh` completo → todo OK (ningún test existente depende de días en UTC; si alguno falla por el cambio de `calculate_business_days`, revisar el caso: la regla nueva manda).

- [ ] **Step 6: Commit** — `git add supabase/migrations/20261029120000_one_db_business_time.sql supabase/tests/one_db_business_time.test.sql supabase/tests/fixtures/one_db_kenya.sql` — `feat(db): business time en horas y dias laborables en hora local de la cuenta`.

### Task 2: Trigger de cálculo en `one_db`, `transfer_to_one_db` y recálculo por estándar

**Files:**
- Modify: `supabase/migrations/20261029120000_one_db_business_time.sql` (sección 2)
- Modify: `supabase/tests/one_db_business_time.test.sql`
- Modify: `supabase/tests/fixtures/one_db_kenya.sql`

**Interfaces:**
- Consumes: funciones de Task 1.
- Produces: columnas `one_db.total_transit_hours numeric(10,2)`, `business_transit_hours numeric(10,2)`, `sent_at_local timestamp`, `received_at_local timestamp`; trigger `one_db_compute_transit` BEFORE INSERT OR UPDATE OF `sent_at, received_at, account_id` ON `one_db` (función `public.one_db_compute_transit()`); función `public.one_db_on_time(p_business_hours numeric, p_business_days integer, p_standard_time numeric, p_time_unit text) RETURNS boolean` (NULL si `p_standard_time` NULL; `time_unit` NULL o `'hours'` → `p_business_hours <= p_standard_time`; `'days'` → `p_business_days <= p_standard_time`); `transfer_to_one_db()` y `recalculate_on_time_delivery_on_sla_change()` redefinidas.

- [ ] **Step 1: Ampliar fixture** — en `one_db_kenya.sql` añadir para la cuenta `…0003`: 1 `regions`, 2 `cities` (`Kericho`, `Garissa`), 2 `nodes`, 2 `panelists` (uno por nodo, `status 'active'`), 1 `carriers` (`KENYA POST`), 2 `products` (`description` `'Economy delivery within 48hrs'` y `'Prod dias'`), 1 `allocation_plans` por producto, `delivery_standards` para Kericho→Garissa: producto 1 `standard_time 48, time_unit 'hours'`; producto 2 `standard_time 2, time_unit 'days'`. Usar ids fijos con el prefijo `…0003` como el fixture `incident_city.sql`.

- [ ] **Step 2: Tests que fallan** (añadir casos al mismo fichero):
  - T1: insertar `allocation_plan_details` (plan producto 1, nodos, `tag_id '00010305'`, `status 'sent'`, `sent_at '2026-10-27 13:44:18Z'`), luego `UPDATE … SET status='received', received_at='2026-10-29 07:40:57Z'`. Esperado en `one_db`: 1 fila, `sent_at = '2026-10-27 13:44:18Z'` (sin desplazar), `sent_at_local = '2026-10-27 16:44:18'`, `received_at_local = '2026-10-29 10:40:57'`, `total_transit_hours = 41.94`, `business_transit_hours = 41.94`, `total_transit_days = 2` (27/10 → 29/10 local: cambios de fecha, misma lógica que business sin descontar días), `business_transit_days = 2`, `on_time_delivery = true`. T1b: envío jue 29/10 16:00 Nairobi → lun 2/11 10:00 Nairobi: `total_transit_hours = 90.00`, `total_transit_days = 4`, `business_transit_hours = 42.00`, `business_transit_days = 2`.
  - T2: igual con producto 2 (estándar 2 días): `on_time_delivery = true`; y con `received_at` del viernes 30/10 10:40Z: `business_transit_days = 3`, `on_time_delivery = false`.
  - T3: `INSERT INTO one_db` directo (sin `allocation_detail_id`) con `sent_at`/`received_at` → el trigger rellena horas, días y locales. Con `received_at < sent_at` → horas 0.00, días 0.
  - T4: `UPDATE delivery_standards SET standard_time = 30` en la ruta de T1 → `on_time_delivery` pasa a `false` (recálculo por nombres, producto casado por `description`).
  - T5: ruta sin estándar → `on_time_delivery IS NULL`. Estándar con `time_unit` NULL → se compara en horas.
- [ ] **Step 3: Comprobar que fallan** — `bash supabase/tests/run_tests.sh one_db_business_time` → FAIL (columnas no existen).
- [ ] **Step 4: Implementar** (sección 2 de la migración):
  - `ALTER TABLE one_db ADD COLUMN IF NOT EXISTS` las cuatro columnas.
  - `one_db_compute_transit()`: si `NEW.sent_at` y `NEW.received_at` no NULL → zona de `NEW.account_id`; `total_transit_hours = ROUND(GREATEST(0, extract(epoch from received-sent)/3600), 2)`; `total_transit_days = GREATEST(0, (received_at AT TIME ZONE v_tz)::date - (sent_at AT TIME ZONE v_tz)::date)` (cambios de fecha local, misma lógica que business sin descontar días); `business_transit_hours = calculate_business_hours(...)`; `business_transit_days = calculate_business_days(...)`; locales con `AT TIME ZONE v_tz`. Si alguno NULL → las seis columnas NULL. `CREATE TRIGGER one_db_compute_transit BEFORE INSERT OR UPDATE OF sent_at, received_at, account_id ON one_db FOR EACH ROW`.
  - `one_db_on_time(...)` como en Interfaces.
  - `transfer_to_one_db()`: partir del texto vivo en `20261029100000_one_db_on_time_respeta_unidad.sql`; quitar el cálculo de `v_total_transit_days`/`v_business_transit_days`, el `AT TIME ZONE` doble y el `IF v_delivery_standard`; insertar `sent_at`/`received_at` tal cual sin las columnas de días/horas; tras el `INSERT … RETURNING business_transit_hours, business_transit_days INTO …`, `UPDATE one_db SET on_time_delivery = one_db_on_time(h, d, v_delivery_standard, v_time_unit) WHERE id = v_new_id`. Alternativa equivalente: calcular las dos medidas con las funciones antes del INSERT y pasarlas; el trigger las recalcula igual.
  - `recalculate_on_time_delivery_on_sla_change()`: mismo texto vivo (ver spec "Por qué"), cambiando `p.code = one_db.product_name` por `p.description = one_db.product_name` y la expresión por `one_db_on_time(one_db.business_transit_hours, one_db.business_transit_days, ds.standard_time, ds.time_unit)`.
- [ ] **Step 5: Pasa** — `bash supabase/tests/run_tests.sh one_db_business_time` → OK; `bash supabase/tests/run_tests.sh` → OK.
- [ ] **Step 6: Commit** — `feat(db): one_db calcula horas/dias por trigger; a tiempo segun unidad del estandar`.

### Task 3: Corrección de datos existentes y aplicación en onems-dev

**Files:**
- Modify: `supabase/migrations/20261029120000_one_db_business_time.sql` (sección 3)
- Modify: `supabase/tests/one_db_business_time.test.sql`

- [ ] **Step 1: Test que falla** — T6: insertar en `one_db` una fila "vieja" con `allocation_detail_id` apuntando a un detalle con fechas, pero `sent_at` desplazado −3 h y `total_transit_days` incorrecto; ejecutar el bloque de corrección (copiar el SQL de la sección 3 dentro del test con `\ir ../migrations/...` no sirve porque la migración ya corrió: en su lugar, envolver la corrección en una función `public.one_db_backfill_transit() RETURNS integer` creada en la migración y llamarla desde el test). Esperado: `sent_at` = el del detalle, horas/días/locales recalculados, `on_time_delivery` según estándar. T7: fila sin detalle conserva sus fechas y se recalcula.
- [ ] **Step 2: Falla** — `run_tests.sh one_db_business_time` → FAIL.
- [ ] **Step 3: Implementar** `one_db_backfill_transit()`: (a) `UPDATE one_db o SET sent_at = d.sent_at, received_at = d.received_at FROM allocation_plan_details d WHERE d.id = o.allocation_detail_id AND d.sent_at IS NOT NULL AND d.received_at IS NOT NULL AND (o.sent_at IS DISTINCT FROM d.sent_at OR o.received_at IS DISTINCT FROM d.received_at)`; (b) `UPDATE one_db SET sent_at = sent_at` (dispara el trigger en todas); (c) `on_time_delivery` por ids para filas con detalle (join detalle → plan → nodos → ciudades → `delivery_standards`) y por nombres para el resto (misma lógica que el recálculo). Devuelve filas tocadas. La migración termina con `SELECT public.one_db_backfill_transit();`.
- [ ] **Step 4: Pasa** — `run_tests.sh one_db_business_time` y suite completa → OK. Además `powershell -File supabase\tests\replay.ps1` → termina sin error.
- [ ] **Step 5: Commit** — `feat(db): correccion de fechas y medidas de one_db existentes`.
- [ ] **Step 6: Aplicar en remoto — PARAR Y PEDIR OK.** Mostrar al usuario: proyecto `onems-dev`, ref `sehbnpgzqljrsqimwyuz`, resumen de lo que hace la migración y cuántas filas de `one_db` hay por cuenta (consulta read-only). Solo con su OK explícito: `apply_migration` con nombre `one_db_business_time` y el contenido del fichero. Después, consulta read-only de las 4 filas de Kenya: esperado 00010305 → `sent_at_local 2026-10-27 16:44`, `received_at_local 2026-10-29 10:40`, `business_transit_hours 41.9x`, `on_time true`; 00010597 → `business_transit_hours ≈ 34.2`, `on_time false`.

## Fase 2 — Zona horaria, selector y E2E DB

### Task 4: Zona de la cuenta en el frontend y `lib/accountTime.ts`

**Files:**
- Modify: `src/lib/types.ts` (interface `Account`)
- Modify: `src/contexts/AccountContext.tsx`
- Create: `src/lib/accountTime.ts`

**Interfaces:**
- Produces: `Account.timezone: string`; `useAccount().accountTimezone: string` (`'UTC'` si no hay cuenta efectiva o la consulta falla); `formatInTz(iso: string | null | undefined, tz: string): string`; `formatDuration(hours: number | null | undefined, unit: TimeUnit): string`; `toUnit(hours: number, unit: TimeUnit): number`; `export type TimeUnit = 'hours' | 'days'`.

- [ ] **Step 1: Implementar `accountTime.ts`** (sin imports de React): `formatInTz` con `new Intl.DateTimeFormat('en-GB', { timeZone: tz, year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit', hour12:false })` y recomponer a `dd/MM/yyyy HH:mm`; `''` para null/inválido; si `tz` no es válida (lanza `RangeError`), reintentar con `'UTC'`. `formatDuration`: null → `'N/A'`; hours → `Number.isInteger(h) ? `${h} h` : `${h.toFixed(1)} h``; days → `${(h/24).toFixed(2)} d`. `toUnit`: `unit === 'days' ? h/24 : h`.
- [ ] **Step 2: Verificar con un script** — `npx --yes tsx -e "import {formatInTz,formatDuration} from './src/lib/accountTime'; console.log(formatInTz('2026-10-27T13:44:18Z','Africa/Nairobi'), formatDuration(41.93,'hours'), formatDuration(41.93,'days'), formatDuration(null,'hours'), formatInTz('2026-10-27T13:44:18Z','No/Zone'))"` → `27/10/2026 16:44 41.9 h 1.75 d N/A 27/10/2026 13:44`.
- [ ] **Step 3: `Account.timezone`** en `types.ts` y, en `AccountContext`, estado `accountTimezone` cargado con `supabase.from('accounts').select('timezone').eq('id', effectiveAccountId).maybeSingle()` cuando `effectiveAccountId` cambia; `'UTC'` si null/error. Exponerlo en el value y en el tipo del contexto.
- [ ] **Step 4: Verificar** — `npm run lint` y `npm run build` → OK. En el navegador (cuenta KENYA): `useAccount().accountTimezone` = `'Africa/Nairobi'` (comprobar con un `console.log` temporal y quitarlo).
- [ ] **Step 5: Commit** — `feat(front): zona horaria de la cuenta y utilidades de hora local/duracion`.

### Task 5: `TimeUnitContext`, `TimeUnitToggle` y traducciones

**Files:**
- Create: `src/contexts/TimeUnitContext.tsx`
- Create: `src/components/common/TimeUnitToggle.tsx`
- Modify: `src/App.tsx` (envolver dentro de `AccountProvider`)
- Modify: `public/locales/en.csv`, `es.csv`, `fr.csv`, `ar.csv`

**Interfaces:**
- Consumes: `TimeUnit` de Task 4.
- Produces: `useTimeUnit(): { unit: TimeUnit; setUnit: (u: TimeUnit) => void }`; `<TimeUnitToggle />` (sin props) que pinta dos botones `t('common.unit_hours')` / `t('common.unit_days')`, el activo con `bg-blue-600 text-white`, el resto `bg-white text-gray-700 border`, con `aria-pressed`.

- [ ] **Step 1: Claves** en los 4 CSV (orden alfabético, sin comillas salvo que el valor lleve coma): `common.unit_days` (Days / Días / Jours / أيام), `common.unit_hours` (Hours / Horas / Heures / ساعات), `onedb.avg_transit_time` (Avg transit time / Tiempo medio de tránsito / Temps moyen de transit / متوسط وقت العبور), `onedb.business_time` (Business time / Tiempo hábil / Temps ouvré / الوقت الفعلي), `onedb.business_time_average` (Business time average / Promedio de tiempo hábil / Moyenne du temps ouvré / متوسط الوقت الفعلي), `onedb.transit_time` (Transit time / Tiempo en tránsito / Temps de transit / وقت العبور).
- [ ] **Step 2: Contexto** — lectura inicial de `localStorage.getItem('onems.timeUnit')` dentro de `try/catch`; solo `'hours'`/`'days'` son válidos, cualquier otro valor → `'hours'`; `setUnit` guarda en `localStorage` (try/catch).
- [ ] **Step 3: Toggle** y provider en `App.tsx` (dentro de `AccountProvider`, fuera de `BrowserRouter`).
- [ ] **Step 4: Verificar** — `npm run lint`, `npm run build` → OK. En consola del navegador `localStorage.setItem('onems.timeUnit','basura')` + recarga → el toggle muestra Horas activo.
- [ ] **Step 5: Commit** — `feat(front): selector global Horas/Dias y textos en 4 idiomas`.

### Task 6: E2E DB en hora local y con el selector

**Files:**
- Modify: `src/hooks/useOneDB.ts` (`OneDBRecord` + `exportToCSV`)
- Modify: `src/components/OneDB/OneDBTable.tsx`
- Modify: `src/pages/OneDB.tsx`

**Interfaces:**
- Consumes: `useAccount().accountTimezone`, `useTimeUnit()`, `formatInTz`, `formatDuration`, `toUnit`, `<TimeUnitToggle />`.
- Produces: `OneDBRecord` con `total_transit_hours: number | null`, `business_transit_hours: number | null`, `sent_at_local: string | null`, `received_at_local: string | null`.

- [ ] **Step 1: `useOneDB.ts`** — ampliar `OneDBRecord`; `exportToCSV` recibe `(selectedRecords, opts: { tz: string; unit: TimeUnit })`: columnas `Sent (local)`, `Received (local)` con `formatInTz`, `Transit time (h|d)`, `Business time (h|d)` con `toUnit` (2 decimales). Quitar las columnas separadas de fecha/hora.
- [ ] **Step 2: `OneDBTable.tsx`** — props nuevas `tz: string`, `unit: TimeUnit`; `formatDate` → `formatInTz(iso, tz)`; cabeceras `t('onedb.transit_time')` / `t('onedb.business_time')` seguidas de ` (${unit === 'hours' ? 'h' : 'd'})`; celdas con `formatDuration(record.total_transit_hours, unit)` y `formatDuration(record.business_transit_hours, unit)`.
- [ ] **Step 3: `OneDB.tsx`** — `<TimeUnitToggle />` a la derecha del título; tarjeta 4: título `t('onedb.avg_transit_time')`, valor = `formatDuration(media de business_transit_hours de los registros con valor, unit)` (`N/A` si no hay), subtítulo `t('onedb.business_time_average')`; pasar `tz`/`unit` a tabla y export.
- [ ] **Step 4: Verificar** — lint/build OK. Con KENYA: 00010305 muestra `27/10/2026 16:44` → `29/10/2026 10:40`, `41.9 h` / `1.75 d` al cambiar el selector; CSV con las mismas cifras.
- [ ] **Step 5: Commit** — `feat(onedb): fechas en hora de la cuenta y tiempos en horas/dias segun selector`.

### Task 7: Planes de asignación en hora de la cuenta

**Files:**
- Modify: `src/pages/AllocationPlans.tsx` (export CSV, ~líneas 450-451)
- Modify: `src/components/allocation-plans/RegisterReceptionModal.tsx` (~línea 109)

- [ ] **Step 1:** sustituir `new Date(x).toLocaleString()` por `formatInTz(x, accountTimezone)` en ambos (obtener `accountTimezone` de `useAccount()`).
- [ ] **Step 2: Verificar** — lint/build OK; abrir "Registrar recepción" de un envío de Kenya: "Sent at" en hora de Nairobi.
- [ ] **Step 3: Commit** — `fix(plans): fechas de envio/recepcion en hora de la cuenta`.

## Fase 3 — Informes

### Task 8: `lib/transitMeasure.ts`, Dashboard y Compliance data

**Files:**
- Create: `src/lib/transitMeasure.ts`
- Modify: `src/hooks/reporting/useComplianceData.ts`, `src/hooks/reporting/useReportingGeneral.ts`, `src/hooks/reporting/useCarrierProductOverview.ts`
- Modify: `src/pages/Reporting/Dashboard.tsx`

**Interfaces:**
- Produces: `export interface TransitShipment { business_transit_hours: number | null; business_transit_days: number | null }`; `export interface StandardRef { standard_time: number | null; time_unit: 'hours' | 'days' | null }`; `measureUnit(std?: StandardRef | null): TimeUnit` (`'days'` solo si `time_unit === 'days'`); `measureOf(s: TransitShipment, unit: TimeUnit): number | null` (horas o días según `unit`); `measureHours(s, unit)`: la medida expresada en horas (`days * 24`) para medias presentables con `formatDuration`.
- Consumes: Tasks 4–5.

- [ ] **Step 1: `transitMeasure.ts`** con las funciones anteriores.
- [ ] **Step 2: Hooks** — en `useComplianceData`: el `standardsMap` guarda `standardTime` y `unit` (sin dividir por 24); por envío `measureOf(shipment, unit)` alimenta `daysArray` (renombrar a `measureArray`) y la comparación con el estándar; las medias que se devuelven a la página se expresan en horas (`measureHours`). `useReportingGeneral`/`useCarrierProductOverview`: `totalDays`/`transitDays` → sumas en horas (`business_transit_hours ?? business_transit_days*24`), nombres `totalHours`/`avgHours`. Las consultas con `select('…columnas…')` añaden `business_transit_hours`.
- [ ] **Step 3: `Dashboard.tsx`** — `<TimeUnitToggle />` junto al `h1`; cada valor de duración mostrado pasa por `formatDuration(hours, unit)`; ejes/tooltips de recharts con `toUnit` y sufijo `h`/`d`.
- [ ] **Step 4: Verificar** — lint/build OK; con KENYA el Dashboard muestra medias en `h`, y en `d` al cambiar; sin envíos → `N/A`.
- [ ] **Step 5: Commit** — `feat(reporting): medida por unidad del estandar en Dashboard y datos de cumplimiento`.

### Task 9: J+K Performance

**Files:**
- Modify: `src/hooks/reporting/useJKPerformance.ts`
- Modify: `src/pages/Reporting/JKPerformance.tsx`, `src/pages/Reporting/JKPerformanceV2.tsx`

**Interfaces:**
- Consumes: Task 8.
- Produces: `JKRouteData` gana `unit: TimeUnit` (unidad de la ruta: la del estándar; `'hours'` si no hay estándar). `samples`, `distribution`, `jkActual`, `jkStandard`, `deviation` están en esa unidad. `maxDays` pasa a `maxMeasure` por unidad: `{ hours: number; days: number }`.

- [ ] **Step 1: Hook** — `standardsMap` guarda `standardTime` y `unit`; `jkStandard = standardTime` (sin /24); por envío `measure = measureOf(shipment, unit)`; `distribution` por `Math.round(measure)` cuando `unit === 'hours'` (cubos de 1 h) y por `measure` entero cuando `'days'`; `onTimeSamples` y `jkActual` sobre `measure`. Agregados por centro/ciudad (`inbound`/`outbound` `samples`) promedian `jkActual` solo entre rutas de la misma unidad; si mezclan unidades, convertir a horas (`days*24`) y marcar `unit: 'hours'`.
- [ ] **Step 2: Páginas** — `<TimeUnitToggle />` junto al `h1`; donde se pinta `jkActual`/`jkStandard`/`deviation`: si `route.unit === 'days'` → `J+${n}`; si `'hours'` → `${n} h` o, con selector en días, `${(n/24).toFixed(2)} d`. Gráfica de distribución: eje X con etiqueta `t('common.unit_hours')`/`t('common.unit_days')` según la unidad de la ruta seleccionada.
- [ ] **Step 3: Verificar** — lint/build OK; KENYA: ruta Kericho→Garissa Economy muestra J+K real en horas y estándar `48 h`; DEMO2 sigue mostrando `J+2`.
- [ ] **Step 4: Commit** — `feat(reporting): J+K en horas cuando el estandar es en horas`.

### Task 10: Territory Equity, Compliance report y tabla de productos

**Files:**
- Modify: `src/hooks/reporting/useTerritoryEquityDataV2.ts`
- Modify: `src/lib/e2eCalculations.ts` (`calculateJKActual`, `loadSLAStandards`, `Sample`/`SLAStandard`)
- Modify: `src/components/reporting/ProductAnalysisTable.tsx`
- Modify: `src/pages/Reporting/ComplianceReport.tsx`, `src/pages/Reporting/TerritoryEquity.tsx`, `src/pages/Reporting/TerritoryEquityV2.tsx`

**Interfaces:**
- Consumes: Tasks 8–9.
- Produces: en `e2eCalculations.ts`, `SLAStandard` gana `unit: TimeUnit` y `standardMeasure: number` (sustituye a `standardDays`); `Sample` gana `businessTransitHours: number | null`; `calculateJKActual(measureArray, standardPercentage, fallback)` sin cambio de firma (ya es genérica).

- [ ] **Step 1: `e2eCalculations.ts`** — `loadSLAStandards` lee `time_unit`; `loadSamples` (la función que mapea `row.business_transit_days`) añade `businessTransitHours: row.business_transit_hours`; `calculateRouteMetrics` usa `measureOf` con la unidad del estándar.
- [ ] **Step 2: `useTerritoryEquityDataV2.ts`** — todas las apariciones de `allowedDays`/`standardDaysSum`/`actualDaysArray` (líneas ~335-530): guardar `standardTime` + `unit`, empujar `measureOf(shipment, unit)`; las medias devueltas a la página en horas (`measureHours`). `select('*')` ya trae las columnas nuevas.
- [ ] **Step 3: `ProductAnalysisTable.tsx`** — `transitDays` (línea ~118) → `measureOf` según la unidad de la ruta; cabecera de columna con `h`/`d` según selector para medias.
- [ ] **Step 4: Páginas** — `<TimeUnitToggle />` en `ComplianceReport.tsx` (~línea 71), `TerritoryEquity.tsx` (~494), `TerritoryEquityV2.tsx` (~592); `TerritoryEquityV2.tsx` líneas ~156/210 (consulta propia y export) añaden `business_transit_hours` y exportan `Business time (h|d)` con `toUnit`; fechas de export con `formatInTz`.
- [ ] **Step 5: Verificar** — lint/build OK; Compliance con KENYA: ruta Economy 48 h "a tiempo" coincide con E2E DB (00010305 sí, 00011082 no); selector cambia medias a `d`.
- [ ] **Step 6: Commit** — `feat(reporting): equidad territorial y cumplimiento con medida por unidad del estandar`.

### Task 11: Filtros de fecha en la zona de la cuenta

**Files:**
- Modify: `src/lib/dateUtils.ts`
- Modify: `src/hooks/reporting/useComplianceData.ts`, `useJKPerformance.ts`, `useReportingGeneral.ts`, `useCarrierProductOverview.ts`, `useTerritoryEquityDataV2.ts`, `src/pages/Reporting/TerritoryEquityV2.tsx`

**Interfaces:**
- Produces: `startOfDayInTz(ymd: string, tz: string): string` y `endOfDayInTz(ymd: string, tz: string): string` en `dateUtils.ts` (devuelven ISO UTC del 00:00:00 / 23:59:59 local; `''` si `ymd` vacío). Implementación sin dependencias: construir `Date.UTC(y,m,d,h,mi,s)`, calcular el offset de `tz` en ese instante con `Intl.DateTimeFormat(...).formatToParts` y restarlo.

- [ ] **Step 1: Implementar** y verificar con `npx --yes tsx -e "..."`: `startOfDayInTz('2026-10-27','Africa/Nairobi')` → `2026-10-26T21:00:00.000Z`; `endOfDayInTz('2026-10-27','Europe/Madrid')` → `2026-10-27T22:59:59.000Z`.
- [ ] **Step 2: Hooks** — cada `.gte('sent_at', filters.startDate)` / `.lte('sent_at', filters.endDate)` (y `dateFrom`/`dateTo`) pasa por `startOfDayInTz(..., accountTimezone)` / `endOfDayInTz(...)`; `accountTimezone` llega por `useAccount()` dentro del hook.
- [ ] **Step 3: Verificar** — lint/build OK; en KENYA, filtrar Compliance por 27/10–27/10 incluye 00010305 (enviado 16:44 Nairobi = 13:44Z) y no 00010597 (05:40 Nairobi del 27 = 02:40Z del 27 → sí incluido; comprobar que 26/10 lo excluye).
- [ ] **Step 4: Commit** — `fix(reporting): filtros de fecha en la zona horaria de la cuenta`.

## Fase 4 — Generador de pruebas y datos demo

### Task 12: `ReceiveGenerator` y `demo2/one_db.json`

**Files:**
- Modify: `src/pages/ReceiveGenerator.tsx` (~líneas 288-303)
- Create: `scripts/regenerate-demo-one-db.mjs`
- Modify: `src/data/demo2/one_db.json`

- [ ] **Step 1: Generador** — eliminar `transitDays` y las propiedades `total_transit_days`/`business_transit_days` del `record` (el trigger las calcula); mantener `on_time_delivery` y `source_data_snapshot.standard_days`.
- [ ] **Step 2: Script** (Node ≥ 18, sin dependencias): lee `src/data/demo2/one_db.json`, para cada fila calcula con zona `Europe/Madrid` y festivos de `src/data/demo2/non_working_days.json` si existe (si no, sin festivos): `total_transit_hours`, `business_transit_hours` (misma regla que `calculate_business_hours`: 24 h por día laborable lunes–viernes no festivo), `total_transit_days` (diferencia de fechas locales), `business_transit_days` (cambios de fecha local solo en días laborables), `sent_at_local`, `received_at_local` (`yyyy-MM-ddTHH:mm:ss`), y reescribe el JSON con 2 espacios. Comprobar con la primera fila: `2026-01-19T10:20:43Z` → `2026-01-21T14:59:48Z` (Madrid +1): `total_transit_hours 52.65`, `business_transit_hours 52.65`, `business_transit_days 2`.
- [ ] **Step 3: Ejecutar** `node scripts/regenerate-demo-one-db.mjs` y revisar `git diff --stat src/data/demo2/one_db.json` (solo campos añadidos). `useAccountManagement.ts` inserta el objeto completo, así que las columnas nuevas entran sin cambios; el trigger las recalcula igualmente.
- [ ] **Step 4: Verificar** — lint/build OK.
- [ ] **Step 5: Commit** — `chore(demo): campos de horas y hora local en one_db demo; generador deja el calculo al trigger`.

## Cierre

- [ ] `npm run lint && npm run build` → OK en `develop`.
- [ ] Revisión final de la rama (subagent-driven: reviewer en el modelo más capaz).
- [ ] Recordar al usuario la Fase 5 (festivos de Kenya en `non_working_days`) y que las vistas `v_reporting_*` siguen en días.
