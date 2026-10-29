# E2E: business time según la unidad del estándar, hora local de la cuenta y selector Horas/Días

Fecha: 2026-10-29. Estado: aprobado por el usuario (regla final confirmada 2026-10-29).

## Por qué

Hoy la pantalla E2E DB y los informes calculan "a tiempo" con `business_transit_days`,
un entero que cuenta **cambios de fecha** (lunes a viernes) y no tiempo transcurrido.
Los productos de Kenya están definidos en horas (6 h / 24 h / 48 h), así que un Express
enviado a las 17:00 y recibido a las 09:00 del día siguiente (16 h) cuenta como tarde,
y un Economy de 60 h cuenta como a tiempo. Además:

- `transfer_to_one_db()` copia `sent_at`/`received_at` a `one_db` restando el offset de la
  cuenta (`AT TIME ZONE 'UTC' AT TIME ZONE tz`) sobre una columna `timestamptz`: el
  instante queda desplazado 3 h en Kenya. La captura original (bot n8n `NOW()`, modales
  web `toISOString()`) es correcta; el error está solo en la copia.
- La pantalla muestra las horas en la zona del navegador, no en la de la cuenta.
- `calculate_business_days()` no consulta festivos (`non_working_days`) ni el calendario
  semanal de la cuenta (`weekly_schedule`) y corta los días en UTC, no en la zona de la
  cuenta.
- `recalculate_on_time_delivery_on_sla_change()` casa el producto por `products.code`
  cuando `one_db.product_name` guarda `products.description`: nunca recalcula nada.

## Regla principal (decisión del usuario)

**La unidad del estándar de la ruta (`delivery_standards.time_unit`) decide cómo se mide.**

| Estándar en | Business time | A tiempo | J+K |
|---|---|---|---|
| **horas** | horas reales transcurridas, descontando días no laborables (24 h por día laborable), en hora local de la cuenta | `business_transit_hours <= standard_time` | en horas: distribución por horas de business time; "J+K real" = hora en la que se alcanza el % objetivo |
| **días** | días laborables por **cambio de fecha** en hora local de la cuenta, descontando festivos | `business_transit_days <= standard_time` | como hoy: J+1, J+2… por fecha |

- La base guarda siempre las dos medidas (horas y días). Cada informe usa la que
  corresponde al estándar de la ruta. Una ruta sin estándar no tiene "a tiempo" (NULL).
- Día laborable = `is_account_working_day(account_id, fecha)` (ya existe): festivos de
  `non_working_days` de cuenta entera y calendario `weekly_schedule` de la cuenta; sin
  calendario, lunes–viernes.
- Todas las fechas y horas se muestran en la zona horaria de la cuenta (`accounts.timezone`).
- El **selector Horas / Días** de la cabecera cambia solo cómo se **ven** las duraciones
  (medias, tiempos de tránsito, ejes y tooltips, CSV). No cambia cómo se decide "a tiempo"
  ni la unidad de J+K.

## No objetivos

- Horario de trabajo (8:00–17:00). Un día laborable son 24 h.
- Cambiar cómo capturan la hora el bot, los modales web o el ETL RFID.
- Festivos por centro postal (`non_working_days.postal_center_id`): solo cuenta entera.
- Cargar los festivos de Kenya: hace falta que el usuario facilite la lista; carga de
  datos aparte.
- Migrar las vistas `v_reporting_*` (no las usa el frontend): fase posterior.

## Decisiones

### Base de datos (una migración forward-only en `supabase/migrations/`)

**`one_db`**
- Nuevas columnas: `total_transit_hours numeric(10,2)`, `business_transit_hours numeric(10,2)`,
  `sent_at_local timestamp`, `received_at_local timestamp` (sin zona: la hora en la zona de
  la cuenta, para leerla sin convertir). No son columnas generadas (la conversión de zona
  no es inmutable).
- `sent_at` / `received_at` guardan el **mismo instante** que `allocation_plan_details`
  (se elimina el doble `AT TIME ZONE`).
- `total_transit_days`, `business_transit_days` se conservan con su significado (días por
  cambio de fecha), corregidos a hora local (y, en business, festivos/calendario).
- **Misma lógica en tránsito total y en business** (decisión del usuario): en horas,
  tiempo transcurrido; en días, cambios de fecha local. `total_transit_days` =
  `fecha_local(received) − fecha_local(sent)` en días (no `floor(horas/24)`);
  `total_transit_hours` = horas transcurridas. Business = lo mismo descontando días no
  laborables.

**Función nueva `calculate_business_hours(p_start timestamptz, p_end timestamptz, p_account_id uuid) returns numeric`**
- Convierte ambos instantes a la zona de la cuenta (`accounts.timezone`, por defecto `'UTC'`).
- Para cada día local entre inicio y fin que cumpla `is_account_working_day`, suma las
  horas de solapamiento entre [inicio, fin] y ese día (fracción incluida). 2 decimales.
  Si fin < inicio devuelve 0.
- Ejemplos (zona `Africa/Nairobi`, sin festivos, semana lunes–viernes):
  - vie 16:00 → lun 10:00 = 18.00
  - mar 16:44 → jue 10:40 = 41.93
  - lun 09:00 → lun 09:00 = 0.00
  - vie 16:00 → lun 10:00 con el lunes festivo = 8.00

**`calculate_business_days(p_start, p_end, p_account_id)` se redefine** (misma firma):
cuenta los días locales de la cuenta desde la fecha de envío (incluida) hasta la fecha
de recepción (excluida) que cumplan `is_account_working_day`. Ejemplos (Nairobi):
  - mar 27/10 16:44 → jue 29/10 10:40 = 2
  - lun 09:00 → lun 18:00 = 0
  - vie 16:00 → lun 10:00 = 1; con el lunes festivo también 1; con el viernes festivo 0
  - 2026-10-28 23:30 UTC (= 29/10 02:30 Nairobi) → 2026-10-29 08:00 UTC = 0 (mismo día local)

**Trigger `one_db_compute_transit` (BEFORE INSERT OR UPDATE OF sent_at, received_at, account_id ON one_db)**
- Si `sent_at` y `received_at` no son NULL, rellena `total_transit_hours` (horas entre
  instantes, 2 decimales), `total_transit_days` (diferencia de fechas locales), `business_transit_hours`,
  `business_transit_days`, `sent_at_local`, `received_at_local`. Si alguno es NULL, deja
  las seis columnas en NULL.
- Así cualquier escritura en `one_db` (transfer, generador de pruebas, corrección de datos)
  queda calculada por la misma regla.

**`transfer_to_one_db()`**
- Deja de calcular días y de desplazar las fechas; escribe `sent_at`/`received_at` tal cual.
- `on_time_delivery` según la regla principal, con la fila ya calculada por el trigger
  (`standard_time` en horas → compara `business_transit_hours`; en días → `business_transit_days`).

**`recalculate_on_time_delivery_on_sla_change()`**
- Misma regla principal; casa el producto por `products.description`.

**Corrección de datos (en la misma migración, una sola vez)**
- Para cada fila de `one_db` cuyo `allocation_plan_details` exista y tenga `sent_at` y
  `received_at`: `sent_at`/`received_at` := los del detalle. Las demás filas (sin
  detalle: las crea `ReceiveGenerator.tsx`; o con fechas NULL) conservan sus fechas.
- Después, `UPDATE one_db SET sent_at = sent_at` para que el trigger recalcule todas las
  filas, y recálculo de `on_time_delivery` para las filas con detalle (por ids) y para
  las filas sin detalle (por nombres, como el recálculo por cambio de estándar).
- Afecta a todas las cuentas (Kenya 4 filas, DEMO2 y Senegal las que tengan).

**Orden de migraciones**: `20261029100000_one_db_on_time_respeta_unidad.sql` ya está
aplicada en `onems-dev`; la nueva redefine las funciones con `CREATE OR REPLACE`.

### Frontend

**Zona horaria de la cuenta**
- `Account` (`src/lib/types.ts`) incorpora `timezone: string`. `AccountContext` expone
  `accountTimezone: string` para la cuenta efectiva (consulta `accounts.timezone`; `'UTC'`
  si no hay cuenta). Llega a hooks y páginas por contexto, no por parámetro.
- Utilidad `src/lib/accountTime.ts`:
  - `formatInTz(iso: string | null, tz: string): string`: `Intl.DateTimeFormat` con
    `timeZone`; sin dependencias nuevas. Formato fijo `dd/MM/yyyy HH:mm` (24 h) en los
    cuatro idiomas, dígitos latinos también en árabe. `null` → `''`.
  - `formatDuration(hours: number | null, unit: 'hours' | 'days'): string`: horas →
    `"18 h"` (entero si exacto, si no 1 decimal); días → `"0.75 d"` (2 decimales).
    `null` → `"N/A"`.
  - `toUnit(hours: number, unit: 'hours' | 'days'): number`: valor crudo para gráficas y CSV.
- Todas las pantallas que hoy usan `toLocaleString()` / `toLocaleDateString()` sobre
  `sent_at`/`received_at` pasan por `formatInTz`: E2E DB (`OneDBTable`, CSV de `useOneDB`),
  Planes de asignación (`AllocationPlans.tsx` export, `RegisterReceptionModal`), informes.

**Selector Horas / Días**
- `TimeUnitContext` (`src/contexts/TimeUnitContext.tsx`), valor `'hours' | 'days'`, por
  defecto `'hours'`, persistido en `localStorage` (`onems.timeUnit`), compartido.
- Componente `TimeUnitToggle` (`src/components/common/TimeUnitToggle.tsx`) en la cabecera
  de: E2E DB, Reporting Dashboard, Compliance, J+K Performance (V1 y V2) y Territory
  Equity (V1 y V2). Afecta a tarjetas, tablas, gráficas (ejes y tooltips) y CSV (la
  cabecera de columna indica la unidad).
- Textos nuevos en los 4 idiomas: `common.unit_hours`, `common.unit_days`,
  `onedb.transit_time`, `onedb.business_time`, `onedb.avg_transit_time`.

**E2E DB (`OneDB.tsx`, `OneDBTable.tsx`, `useOneDB.ts`)**
- Columnas "Transit time" / "Business time" muestran `total_transit_hours` /
  `business_transit_hours` en la unidad elegida. Tarjeta de media en la unidad elegida.
  CSV: fechas en zona de cuenta, duraciones en la unidad elegida.

**Informes (`src/hooks/reporting/*`, `src/pages/Reporting/*`, `src/lib/e2eCalculations.ts`,
`ProductAnalysisTable.tsx`)**
- Cada hook carga de `one_db` las dos medidas y, por ruta, elige según `time_unit` del
  estándar: `measure = time_unit === 'hours' ? business_transit_hours : business_transit_days`
  y `standardInMeasure = standard_time`. "A tiempo", J+K real, distribuciones y comparación
  con el estándar se hacen en esa medida. Sin estándar: medida = horas (solo para medias).
- Las medias de duración se muestran con `formatDuration` / `toUnit` según el selector
  (conversión horas↔días ×/÷ 24 solo para presentación).
- Los filtros por fecha (`ReportingFiltersContext`, `dateUtils.ts`) interpretan el día en
  la zona de la cuenta (inicio 00:00 y fin 23:59:59 locales convertidos a instante).
- Ficheros `*.backup` / `.bak` / `.old` no se tocan.

**`ReceiveGenerator.tsx`** (datos de prueba): deja de enviar `total_transit_days` /
`business_transit_days`; el trigger los calcula. Sigue fijando `on_time_delivery`.

### Datos demo
- `src/data/demo2/one_db.json` incorpora los campos nuevos (`*_hours`, `*_local`),
  regenerados con un script a partir de `sent_at`/`received_at` interpretados en
  `Europe/Madrid`, con la misma regla y los festivos de DEMO2 de `non_working_days`.

## Criterios de aceptación

- Etiqueta 00010305 (Kericho → Garissa, Economy 48 h): E2E DB muestra envío
  27/10/2026 16:44 y recepción 29/10/2026 10:40 en cualquier navegador; business time
  41.9 h / 1.75 d; a tiempo = sí.
- Etiqueta 00010597 (Kitale → Nakuru, Express 6 h; 27/10 05:40 → 28/10 15:53 Nairobi):
  business time 34.2 h; a tiempo = no.
- Una ruta DEMO2 con estándar "2 días" y envío lun 18:00 → mié 09:00 (Madrid):
  business days 2; a tiempo = sí.
- Cambiar el selector a Días en Compliance cambia también E2E DB y J+K al volver.
- `npm run lint` y `npm run build` pasan; los tests SQL de `supabase/tests` pasan en local.
- La migración se aplica a `onems-dev` (`sehbnpgzqljrsqimwyuz`) solo con OK explícito.

## Queda al constructor

- Estructura interna de `calculate_business_hours` (bucle por días o `generate_series`).
- Colocación exacta del `TimeUnitToggle` en cada cabecera y su estilo.
- Redondeos de presentación en gráficas.

## Fases

1. Base de datos: funciones, trigger, transfer, recálculo, corrección de datos (tests locales).
2. Zona horaria en frontend + `accountTime.ts` + selector + E2E DB + Planes de asignación.
3. Informes (Dashboard, Compliance, J+K, Territory Equity, ProductAnalysisTable, e2eCalculations).
4. Datos demo y generador de pruebas.
5. Festivos de Kenya (cuando el usuario facilite la lista).
