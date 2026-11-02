# Recepción en POBOX tras ausencia — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anular, al declararse por el bot, las recepciones en ciudades POBOX de un solo nodo cuyo panelista no fue al apartado el último día de recogida anterior; devolver la muestra al registro de muestras por compensar; reintroducir las muestras por compensar aunque el plan haya terminado; mostrar el motivo al gestor y documentarlo.

**Architecture:** Un trigger `BEFORE UPDATE OF status` en `allocation_plan_details` evalúa la regla con dos funciones SQL puras y, si procede, convierte la recepción en `cancelled` e inserta la anotación en `deferred_samples` en la misma sentencia (el bot no cambia, el trigger `AFTER` de `one_db` no copia nada). `rpc_balance_city_v2` deja de acotar la reintroducción por `end_date` del plan. La pantalla de Balanceo gana una columna con el desglose por motivo, y la ayuda explica la regla.

**Tech Stack:** PostgreSQL 17 / PL-pgSQL (Supabase), harness local `supabase/tests/run_tests.sh` (Postgres portable 127.0.0.1:5433), React 18 + TypeScript (Vite), traducciones CSV en `public/locales/`, ayuda HTML estática en `public/help/`.

**Spec:** `docs/superpowers/specs/2026-10-30-recepcion-pobox-tras-ausencia-design.md`

## Global Constraints

- Una sola base Supabase: `onems-dev`, ref `sehbnpgzqljrsqimwyuz`. **Nada se aplica en la BD remota sin nombrar proyecto + ref y obtener OK explícito del usuario.** Nunca `supabase db reset` / `db push`.
- Migración forward-only, una sola, con timestamp posterior a `20261030145555`; se valida antes en local con `bash supabase/tests/run_tests.sh <tests>` (arrancar Postgres portable si no responde: el runner imprime el comando).
- Se re-emite **completa** la última versión de cada función modificada (`rpc_balance_city_v2` y `rpc_deferred_samples_summary` viven en `supabase/migrations/20261028210000_pobox_product_shares.sql`); solo se cambian las líneas que indica la tarea.
- `deferred_samples` solo se escribe desde funciones `SECURITY DEFINER` con `SET search_path = public`.
- Textos visibles vía `useTranslation`; cada clave nueva en los 4 CSV `public/locales/{en,es,fr,ar}.csv` (formato `key,translation`, sin cabecera nueva; valores con coma van entre comillas dobles).
- `npm run lint` (0 warnings) y `npm run build` deben pasar al cerrar la tarea 3.
- **No se hace commit ni push salvo que el usuario lo pida** (regla del repo). Cada tarea termina en "listo para commit".
- Explicar al usuario en lenguaje llano (no es programador).

## Review Focus

1. Recepción declarada a las 01:00 hora de Nairobi (22:00 UTC del día anterior): la fecha `R` debe ser el día local, no el UTC. Test en la tarea 1 (caso 12).
2. `UPDATE` del bot sin `received_at` o con `destination_node_id` NULL: el trigger no debe fallar ni anular; la recepción sigue su curso. Test en la tarea 1 (caso 13).
3. Error inesperado dentro de la evaluación (por ejemplo zona horaria inválida en `accounts.timezone`): el trigger hace `RAISE WARNING` y deja pasar la recepción como válida (fail-open), para que el bot nunca se quede sin respuesta. Test en la tarea 1 (caso 14).
4. La anotación en `deferred_samples` debe conservar el `row_snapshot` con `status = 'received'` y `received_at` (la foto de lo declarado), no la fila ya cancelada. Aserción en el caso 1 de la tarea 1.
5. El plan activo pero ya terminado se reintroduce; la anotación de un plan que **empieza después** del periodo sigue en `outside_period` (caso 3b de `ds_reintroduce.test.sql` debe seguir pasando). Test en la tarea 2 (caso 11) + rerun de `ds_reintroduce`.

---

### Task 1: Regla de recepción POBOX (migración, parte A) + tests

**Files:**
- Create: `supabase/migrations/20261030170000_pobox_receipt_after_absence.sql`
- Test: `supabase/tests/pobox_receipt_after_absence.test.sql`

**Interfaces:**
- Consumes: `effective_city_policy(p_city_id uuid) RETURNS TABLE(account_id, date_policy text, pobox_enabled boolean)`; `is_account_working_day(p_account_id uuid, p_date date) RETURNS boolean`; `accounts.timezone`; `delivery_standards(carrier_id, product_id, origin_city_id, destination_city_id, time_unit)`; `allocation_plans(carrier_id, product_id)`; fixtures `supabase/tests/fixtures/incident_city.sql` (cuenta `a0000000-…01`, C1 = N1,N2,N3; C2 = N4 único nodo; panelista P4 `e4000000-…04` en N4; plan Mar27 `cc000000-…01`) y `fixtures/no_incident_triggers.sql`.
- Produces:
  - columnas `allocation_plan_details.cancellation_reason text NULL CHECK IN ('pobox_absent_unavailable','pobox_absent_no_visit')` y `cancelled_at timestamptz NULL`;
  - `deferred_samples.reason` CHECK ampliado con esos dos valores;
  - `public.pobox_previous_collection_day(p_account_id uuid, p_date date) RETURNS date` (STABLE): último día con `is_account_working_day` estrictamente anterior a `p_date`, buscando hasta 14 días atrás; NULL si no hay;
  - `public.pobox_receipt_check(p_detail public.allocation_plan_details) RETURNS text` (STABLE): NULL si la recepción es válida, si no `'pobox_absent_unavailable'` o `'pobox_absent_no_visit'`, según spec 3.1–3.3;
  - trigger `pobox_receipt_rule BEFORE UPDATE OF status ON public.allocation_plan_details FOR EACH ROW EXECUTE FUNCTION public.tg_pobox_receipt_rule()`.

- [ ] **Step 1: Escribir el test con los casos de la spec (fallará porque no existen las funciones)**

Estructura igual que `supabase/tests/lb2_pobox.test.sql` (`\set ON_ERROR_STOP on`, `pg_temp.fail_if`, un `BEGIN … \ir fixtures … ROLLBACK` por caso). Helpers del test:
- `pg_temp.pobox_on()` como en `lb2_pobox.test.sql`;
- `pg_temp.mk_sent(p_o text, p_d text, p_sent timestamptz, p_tag text) RETURNS uuid`: inserta un detalle `status='sent'` del plan Mar27 con `origin_node_id`/`destination_node_id` por `auto_id`, `fecha_programada = p_sent::date`, `sent_at = p_sent`, `tag_id = p_tag`, `origin_panelist_id`/`destination_panelist_id` = panelistas de esos nodos;
- `pg_temp.receive(p_id uuid, p_at timestamptz)`: `UPDATE allocation_plan_details SET status='received', received_at=p_at WHERE id=p_id AND status='sent'` (misma forma que el bot; sin `set_config` de usuario → `auth.uid()` NULL);
- `pg_temp.unavail(p_pan uuid, p_from date, p_to date)`: inserta `panelist_unavailability(status='active', reason='vacation')`.
- La cuenta de pruebas: `UPDATE accounts SET timezone='Africa/Nairobi' WHERE id='a0000000-…01'` dentro de cada caso.

Casos (fechas de 2027; D se deduce de `received_at` local; destino siempre N4 en C2, origen N1 salvo indicación; `sent_at` por defecto el miércoles 2027-03-03 10:00+03):

| # | Escenario | Aserciones |
|---|---|---|
| 1 | Recibe lunes 2027-03-08 10:00+03; P4 indisponible 03-05..03-05; N4 sin envíos el viernes | `status='cancelled'`, `cancellation_reason='pobox_absent_unavailable'`, `cancelled_at` no nulo, `received_at` conservado; 1 fila en `deferred_samples` con `reason` igual, `plan_id`, `origin_city_id=C1`, `dest_city_id=C2`, `fecha_programada` original, `row_snapshot->>'status'='received'`, `created_by` NULL; 0 filas en `one_db` |
| 2 | Recibe martes 03-09; lunes 03-08 N4 tenía un detalle `pending` programado (`mk('N4','2027-03-08')`) y no declaró | `cancelled`, `pobox_absent_no_visit`, 1 anotación |
| 3 | Como 1 pero N4 declaró un envío el viernes (`mk_sent('N4', 'N1', '2027-03-05 09:00+03', 'T2')`) aunque estuviera indisponible | `status='received'`, 1 fila en `one_db`, 0 anotaciones |
| 4 | Recibe miércoles 03-10; `non_working_days(account, postal_center_id NULL, date 03-09)`; P4 indisponible 03-08 | `cancelled`, `pobox_absent_unavailable` (D saltó el festivo) |
| 5 | Recibe lunes 03-08; viernes sin envío programado ni indisponibilidad | `received`, 1 fila en `one_db` |
| 6 | Ciudad sin POBOX (no se llama a `pobox_on`), escenario de 1 | `received` |
| 6b | POBOX, destino **N1 (C1 tiene 3 nodos)**, origen N4, P1 indisponible el viernes, sin envíos de N1 | `received` (regla no aplicable) |
| 7 | Escenario de 1 con `set_config('request.jwt.claim.sub','99000000-…99', true)` antes del `receive` | `received`. Repetir con `SET LOCAL onems.skip_pobox_receipt_rule = 'on'` y sin uid → `received` |
| 8 | Sin `delivery_standards`; el envío salió el viernes 03-05 10:00+03, recibe lunes 03-08; P4 indisponible el viernes | `received` (días: salió el día D) |
| 8b | Como 8 con `delivery_standards(carrier CA, product PR, C1→C2, standard_time 6, time_unit 'hours')` | `cancelled`, `pobox_absent_unavailable` |
| 8c | Como 8b pero salió el lunes 03-08 08:00+03 y recibe el lunes 15:00+03 | `received` |
| 8d | Como 8 con `delivery_standards(… time_unit 'days', standard_time 2)` | `received` |
| 9 | Escenario de 1, pero la indisponibilidad es de **otro** panelista activo insertado en N4 (`P5`), no de P4 | `cancelled`, `pobox_absent_unavailable` |
| 12 | Recibe `'2027-03-07 22:30+00'` (lunes 01:30 en Nairobi); P4 indisponible viernes 03-05 | `cancelled` (R = lunes, D = viernes) |
| 13 | `UPDATE … SET status='received'` sin `received_at` (NULL) sobre un detalle del escenario 1; y otro con `destination_node_id` NULL (deshabilitar `trigger_transfer_to_one_db` en ese caso para aislar) | ambos quedan `received`, 0 anotaciones |
| 14 | `UPDATE accounts SET timezone='No/Existe'`; escenario de 1 | `received`; el test no falla (el trigger solo emite WARNING) |

- [ ] **Step 2: Ejecutar el test y comprobar que falla**

Run: `bash supabase/tests/run_tests.sh pobox_receipt_after_absence`
Expected: `FAIL pobox_receipt_after_absence` con error de función `pobox_receipt_check` inexistente (o columna `cancellation_reason` inexistente).

- [ ] **Step 3: Escribir la migración (parte A)**

En `supabase/migrations/20261030170000_pobox_receipt_after_absence.sql`, cabecera de comentario con el resumen de la spec y, en este orden:

1. `ALTER TABLE allocation_plan_details ADD COLUMN IF NOT EXISTS cancellation_reason text, ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;` + CHECK `allocation_plan_details_cancellation_reason_check` con los dos valores.
2. `deferred_samples_reason_check` re-creado con `('origin_no_panelist','dest_no_panelist','no_valid_day','pobox_absent_unavailable','pobox_absent_no_visit')`.
3. `pobox_previous_collection_day` (LANGUAGE plpgsql STABLE, `SET search_path = public`): bucle de 1 a 14 sobre `p_date - i` devolviendo el primer `is_account_working_day`.
4. `pobox_receipt_check` (LANGUAGE plpgsql STABLE, `SET search_path = public`). Orden de evaluación fijado por la spec:
   - `received_at` o `destination_node_id` NULL → NULL;
   - ciudad destino = `nodes.city_id`; `effective_city_policy(city).pobox_enabled` false → NULL;
   - `count(*) FROM nodes WHERE city_id = ciudad AND status = 'active'` ≠ 1 → NULL;
   - `tz := COALESCE(accounts.timezone,'UTC')`; `R := (received_at AT TIME ZONE tz)::date`; `D := pobox_previous_collection_day(account_id, R)`; D NULL → NULL;
   - unidad del estándar: `delivery_standards` por `allocation_plans.carrier_id/product_id` del detalle y `origin_city_id/destination_city_id` por los nodos; `unit := COALESCE(time_unit,'days')`; `sent_local := (sent_at AT TIME ZONE tz)::date`; si `sent_at` NULL se trata como "pudo estar"; si (`unit='hours'` y `sent_local > D`) o (`unit<>'hours'` y `sent_local >= D`) → NULL;
   - visita: `EXISTS allocation_plan_details x WHERE x.account_id = … AND x.origin_node_id = destination_node_id AND x.sent_at IS NOT NULL AND (x.sent_at AT TIME ZONE tz)::date = D AND x.id <> p_detail.id` → NULL;
   - indisponible: `EXISTS panelist_unavailability u JOIN panelists p ON p.id = u.panelist_id WHERE p.node_id = destination_node_id AND p.status = 'active' AND u.status = 'active' AND D BETWEEN u.start_date AND u.end_date` → `'pobox_absent_unavailable'`;
   - programado y no declarado: `EXISTS allocation_plan_details x WHERE x.origin_node_id = destination_node_id AND x.fecha_programada = D AND x.status <> 'cancelled'` → `'pobox_absent_no_visit'`;
   - si no → NULL.
5. `tg_pobox_receipt_rule()` (LANGUAGE plpgsql SECURITY DEFINER, `SET search_path = public`): condición de entrada de la spec 6.1 (incluye `auth.uid() IS NULL` y el setting `onems.skip_pobox_receipt_rule`); dentro de `BEGIN … EXCEPTION WHEN OTHERS THEN RAISE WARNING 'tg_pobox_receipt_rule: % (detalle %)', SQLERRM, NEW.id; RETURN NEW; END`: `v_reason := pobox_receipt_check(NEW)`; si no es NULL: `INSERT INTO deferred_samples (account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id, fecha_programada, reason, row_snapshot, created_by)` con `row_snapshot = to_jsonb(NEW)` **antes** de tocar `NEW.status`, y luego `NEW.status := 'cancelled'; NEW.cancellation_reason := v_reason; NEW.cancelled_at := now();`. `RETURN NEW`.
6. `DROP TRIGGER IF EXISTS pobox_receipt_rule ON allocation_plan_details; CREATE TRIGGER pobox_receipt_rule BEFORE UPDATE OF status …`.
7. `REVOKE EXECUTE ON FUNCTION pobox_receipt_check, pobox_previous_collection_day FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated, service_role;`.

- [ ] **Step 4: Ejecutar el test y comprobar que pasa**

Run: `bash supabase/tests/run_tests.sh pobox_receipt_after_absence tag_normalization_receipt one_db_business_time`
Expected: `PASS` en los tres (los dos últimos demuestran que las recepciones normales siguen llegando a `one_db`).

- [ ] **Step 5: Listo para commit** (no commitear sin que el usuario lo pida). Mensaje propuesto: `feat(pobox): anular recepciones tras ausencia del panelista y anotarlas como muestras por compensar`.

---

### Task 2: Reintroducción más allá del fin del plan + desglose por motivo (migración, parte B)

**Files:**
- Modify: `supabase/migrations/20261030170000_pobox_receipt_after_absence.sql` (añadir sección B al final)
- Test: `supabase/tests/pobox_receipt_after_absence.test.sql` (casos 10 y 11), `supabase/tests/ds_reintroduce.test.sql` (debe seguir pasando sin cambios)

**Interfaces:**
- Consumes: `rpc_balance_city_v2(p_city_id uuid, p_start_date date, p_end_date date, p_apply_changes boolean) RETURNS jsonb` y `rpc_deferred_samples_summary(p_account_id uuid) RETURNS jsonb`, ambas en su versión de `20261028210000_pobox_product_shares.sql`.
- Produces: `rpc_balance_city_v2` con ventana de reintroducción `[GREATEST(pl.start_date, v_from, v_today+1), p_end_date]`; `rpc_deferred_samples_summary` cuyo `by_city[]` incluye `by_reason` (jsonb `{motivo: conteo}` de las anotaciones `pending` de esa ciudad).

- [ ] **Step 1: Añadir los casos 10 y 11 al test (fallarán)**

| # | Escenario | Aserciones |
|---|---|---|
| 10 | Tras el caso 1 (sin ROLLBACK intermedio): `set_config` de usuario y `rpc_balance_city_v2(C1, '2027-03-15', '2027-03-19', true)` | `r->'deferred'->>'reintroduced' = '1'`; existe detalle `generation_source='compensation'` del plan Mar27 con `origin_node_id` en C1, `destination_node_id = N4`, `fecha_programada` entre 03-15 y 03-19; la anotación pasa a `status='reintroduced'` |
| 11 | Anotación `pending` del plan Mar27 (vía caso 1) y `UPDATE allocation_plans SET end_date='2027-03-10'`; balancear C1 en `2027-03-15..19` | reintroducida (antes: `waiting_reason='outside_period'`). Luego `UPDATE allocation_plans SET status='completed'` sobre otra anotación nueva → `waiting_by_reason->>'plan_inactive' = '1'` |
| 11b | `rpc_deferred_samples_summary(cuenta)` con dos anotaciones pendientes de C1: una `pobox_absent_unavailable` y otra `pobox_absent_no_visit` | `by_city[0]->'by_reason'->>'pobox_absent_unavailable' = '1'` y `…no_visit = '1'`; `count = 2` |

- [ ] **Step 2: Ejecutar y comprobar que fallan**

Run: `bash supabase/tests/run_tests.sh pobox_receipt_after_absence`
Expected: FAIL en el caso 11 (`outside_period`) y 11b (`by_reason` nulo).

- [ ] **Step 3: Re-emitir `rpc_balance_city_v2` y `rpc_deferred_samples_summary`**

Copiar íntegra la versión de `20261028210000_pobox_product_shares.sql` al final de la migración nueva y cambiar solo:
- en `rpc_balance_city_v2`, la línea `GREATEST(pl.start_date, v_from, v_today + 1), LEAST(pl.end_date, p_end_date),` → `GREATEST(pl.start_date, v_from, v_today + 1), p_end_date,` y actualizar el comentario de cabecera (la fecha de fin del plan ya no acota; `outside_period` = sin día laborable en la ventana);
- en `rpc_deferred_samples_summary`, en el `jsonb_build_object` de `by_city` añadir `'by_reason', (SELECT COALESCE(jsonb_object_agg(d3.reason, d3.n), '{}'::jsonb) FROM (SELECT d2.reason, count(*) n FROM deferred_samples d2 WHERE d2.account_id = p_account_id AND d2.status = 'pending' AND d2.origin_city_id = d.origin_city_id GROUP BY d2.reason) d3)`.

- [ ] **Step 4: Ejecutar la batería del balanceo**

Run: `bash supabase/tests/run_tests.sh pobox_receipt_after_absence ds_reintroduce ds_balance_defer ds_register ds_plan_progress lb2_balance_city lb2_pobox lb2_fence_pobox_replace lb2_pobox_dest_sin_panelista lb2_pobox_product_shares`
Expected: todos `PASS` (el caso 3b de `ds_reintroduce` sigue en `outside_period` porque su plan empieza después del periodo).

- [ ] **Step 5: Listo para commit.** Mensaje propuesto: `feat(balanceo): reintroducir muestras por compensar aunque el plan haya terminado; desglose por motivo`.

---

### Task 3: Columna "Motivo" en Muestras por compensar (frontend + traducciones)

**Files:**
- Modify: `src/hooks/useDeferredSamples.ts` (interfaz `DeferredCityRow`)
- Modify: `src/components/NodeLoadBalancing/DeferredSamplesSection.tsx` (tabla "Por ciudad de origen")
- Modify: `public/locales/en.csv`, `public/locales/es.csv`, `public/locales/fr.csv`, `public/locales/ar.csv`

**Interfaces:**
- Consumes: `by_city[].by_reason` de la tarea 2.
- Produces: `DeferredCityRow.by_reason?: Record<string, number>`; claves i18n `lb2.deferred.col_defer_reason` y `lb2.deferred.reason.{origin_no_panelist,dest_no_panelist,no_valid_day,pobox_absent_unavailable,pobox_absent_no_visit}`.

- [ ] **Step 1: Tipo**: añadir `by_reason?: Record<string, number>` a `DeferredCityRow`.

- [ ] **Step 2: Componente**: nueva columna entre "Ciudad" y "En espera" con cabecera `t('lb2.deferred.col_defer_reason')`; celda = lista `<div>` por motivo con `n · etiqueta`, orden descendente por `n`; etiqueta vía helper `deferReasonLabel(reason)` con el mismo patrón que `reasonLabel` (clave `lb2.deferred.reason.<reason>`, fallback al código). Sin `by_reason` → `—`.

- [ ] **Step 3: Traducciones** (añadir tras `lb2.deferred.waiting.outside_period` en cada CSV):

| clave | es | en | fr | ar |
|---|---|---|---|---|
| `lb2.deferred.col_defer_reason` | Motivo | Reason | Motif | السبب |
| `lb2.deferred.reason.origin_no_panelist` | Sin panelista en el nodo de origen | No panelist at origin node | Aucun panéliste au nœud d'origine | لا يوجد مشارك في عقدة الأصل |
| `lb2.deferred.reason.dest_no_panelist` | Sin panelista en el nodo de destino | No panelist at destination node | Aucun panéliste au nœud de destination | لا يوجد مشارك في عقدة الوجهة |
| `lb2.deferred.reason.no_valid_day` | Sin día válido en el plan | No valid day in the plan | Aucun jour valide dans le plan | لا يوجد يوم صالح في الخطة |
| `lb2.deferred.reason.pobox_absent_unavailable` | Posible retraso de recepción por vacaciones del panelista | Possible late receipt: panelist on leave | Réception possiblement tardive : panéliste absent | احتمال تأخر الاستلام بسبب غياب المشارك |
| `lb2.deferred.reason.pobox_absent_no_visit` | Posible retraso de recepción: el panelista no fue al apartado el día anterior | Possible late receipt: panelist did not visit the PO box the day before | Réception possiblement tardive : le panéliste n'est pas passé à la boîte postale la veille | احتمال تأخر الاستلام: لم يزر المشارك صندوق البريد في اليوم السابق |

Valores con comas o dos puntos: comprobar el escape que usa el CSV en filas vecinas (comillas dobles si hay coma).

- [ ] **Step 4: Verificar**

Run: `npm run lint && npm run build`
Expected: 0 errores, 0 warnings nuevos (los 48 `react-hooks/exhaustive-deps` preexistentes se mantienen), build OK. Comprobación manual en `npm run dev` con la cuenta KENYA: la tabla muestra la columna aunque `by_reason` esté vacío.

- [ ] **Step 5: Listo para commit.** Mensaje propuesto: `feat(balanceo): columna de motivo en muestras por compensar`.

---

### Task 4: Ayuda (Balanceo y guía del panelista, 4 idiomas)

**Files:**
- Modify: `public/help/load-balancing.{es,en,fr,ar}.html` — `<section id="deferred">` (línea ~395 en los cuatro)
- Modify: `public/help/panelist-guide.{es,en,fr,ar}.html` — secciones "Enviar un paquete" y `<section id="recibir">` (ids equivalentes por idioma)

**Interfaces:** ninguna de código. Contenido fijado por la spec 3.5 y 3.4 bis.

- [ ] **Step 1: Balanceo, sección "Muestras por compensar"** (misma estructura en los 4 ficheros, traducida):
  - tras la lista "Por ciudad / Por plan", añadir una viñeta "**Motivo**: por qué se apartó cada muestra (sin panelista en origen/destino, sin día válido, o una recepción POBOX anulada)";
  - en la tabla, añadir dos filas: `Posible retraso de recepción por vacaciones del panelista` y `Posible retraso de recepción: el panelista no fue al apartado el día anterior`, ambas con "Qué hacer" = "Nada: la muestra se reintroduce sola en el siguiente balanceo de la ciudad de origen. Si se repite con el mismo panelista, recuérdele declarar envíos y recepciones el mismo día.";
  - cambiar la fila "Fuera del periodo del plan" → "El periodo balanceado termina antes de que empiece el plan, o no tiene días laborables. Balancee un periodo que llegue al plan." ;
  - nuevo bloque `<h3>Recepciones en POBOX tras una ausencia</h3>` + párrafo con la regla en llano (ciudad POBOX de un solo nodo; último día laborable anterior; prueba de visita = declaró un envío; anulación, fuera de E2E, vuelve al registro; servicios express: también si el paquete salió ese mismo día) + el ejemplo "vuelve el lunes de vacaciones y declara una recepción: se anula; si el viernes sí fue y declaró un envío, vale";
  - callout "Y después": añadir "aunque el plan ya haya terminado, mientras siga activo".

- [ ] **Step 2: Guía del panelista**: en "Enviar un paquete" y en "Recibir un paquete" añadir un `<div class="callout">` (misma clase que use la guía para avisos) con: "Si recoges en un apartado de correos (POBOX), declara cada envío y cada recepción **el mismo día** que lo depositas o lo recoges. Si lo declaras al día siguiente, ONEMS entenderá que ese día no fuiste y la recepción no contará."

- [ ] **Step 3: Verificar**: abrir cada fichero en el navegador (`npm run dev` → `/help/load-balancing.es.html` etc.); comprobar el índice lateral y que no hay etiquetas sin cerrar (`npx htmlhint public/help/load-balancing.*.html public/help/panelist-guide.*.html` si está disponible; si no, revisión visual).

- [ ] **Step 4: Listo para commit.** Mensaje propuesto: `docs(ayuda): recepciones POBOX tras ausencia y reintroducción tras fin de plan`.

---

### Task 5: Aplicar en onems-dev y verificar con Kenya

**Files:** ninguno nuevo. Usa la migración de las tareas 1–2.

- [ ] **Step 1: Pedir OK explícito**: "Voy a aplicar `20261030170000_pobox_receipt_after_absence.sql` en el proyecto **onems-dev** (ref `sehbnpgzqljrsqimwyuz`). ¿OK?". Sin OK no se sigue.
- [ ] **Step 2: Aplicar** con `apply_migration` (nombre `pobox_receipt_after_absence`). Si el servidor asigna otra versión, renombrar el fichero del repo para que coincida (como se hizo con `20261030140708`).
- [ ] **Step 3: Verificar sin escribir**: `SELECT proname FROM pg_proc WHERE proname IN ('pobox_receipt_check','pobox_previous_collection_day','tg_pobox_receipt_rule')` → 3 filas; `SELECT tgname FROM pg_trigger WHERE tgname='pobox_receipt_rule'` → 1; `SELECT count(*) FROM deferred_samples WHERE reason LIKE 'pobox_absent%'` → 0 (sin backfill). Comprobar en KENYA (`account_config.pobox_enabled = true`) cuántas ciudades tienen exactamente un nodo activo: `SELECT c.name, count(n.*) FROM cities c JOIN nodes n ON n.city_id=c.id AND n.status='active' WHERE c.account_id=<KENYA> GROUP BY c.name HAVING count(*)=1` y decirle al usuario a cuántas ciudades alcanza la regla hoy.
- [ ] **Step 4: Avisar al usuario** de que a partir de la siguiente recepción en esas ciudades la regla está viva, y que el frontend (tareas 3–4) está en `develop` pendiente de publicar.
