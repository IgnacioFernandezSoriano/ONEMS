# Registro y tratamiento de errores de recepción — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que cada recepción declarada por el bot pase por una única función de BD que la clasifica, la arregla sola cuando puede (fecha = primer intento), anula y compensa cuando no, registra cada fallo en una tabla de casos y genera recordatorios al panelista causante; y que el admin del país lo siga en una pestaña «Recepciones» con avisos individuales y generales.

**Architecture:** Toda la lógica vive en PL/pgSQL (`bot_receive_parcel` → `register_receipt_with_rules`), llamada desde el nodo SQL del flujo n8n «Mark Parcel as received»; el bot solo pinta el motivo. Los casos `not_found` se reintentan con pg_cron cada 30 min durante 5 días laborables. Los avisos (recordatorio automático, mensaje del admin, aviso general) se encolan en la tabla existente `panelist_notification` y los entrega el flujo existente «Deliver panelist notifications». La pantalla consume RPCs `SECURITY DEFINER` con control de cuenta.

**Tech Stack:** PostgreSQL 17 / PL-pgSQL (Supabase), pg_cron, harness `supabase/tests/run_tests.sh` (Postgres portable 127.0.0.1:5433), n8n cloud 2.68 (API REST + `N8N_API_KEY`), React 18 + TS + Vite + recharts, traducciones CSV `public/locales/{en,es,fr,ar,pt}.csv`, ayuda HTML `public/help/`.

**Spec:** `docs/superpowers/specs/2026-11-04-errores-recepcion-design.md`

## Global Constraints

- Una sola BD: `onems-dev`, ref `sehbnpgzqljrsqimwyuz`. **Nada se aplica en remoto sin nombrar proyecto + ref y OK explícito del usuario.** Nunca `supabase db reset` / `db push`. DEV y PROD del bot comparten esta BD: todo cambio de BD debe ser **aditivo** (el SQL actual del nodo «Find and mark received» de PROD tiene que seguir funcionando hasta la tarea 6).
- Migraciones forward-only con timestamp > `20261103110730`; validar en local con `bash supabase/tests/run_tests.sh <tests>`.
- Escrituras en `deferred_samples`, `receipt_case`, `panelist_notification` solo desde funciones `SECURITY DEFINER SET search_path = public`. RPCs de pantalla: control `auth.uid() IS NOT NULL AND NOT is_superadmin() AND p_account_id IS DISTINCT FROM profiles.account_id → RAISE 42501` (patrón de `rpc_deferred_samples_summary`). RLS por `account_id` en tablas nuevas (SELECT para su cuenta o superadmin; sin INSERT/UPDATE/DELETE directos).
- Fail-open: ningún fallo de registro/recordatorio puede impedir que el bot conteste (`EXCEPTION WHEN OTHERS → RAISE WARNING`, la recepción sigue).
- Fecha de un arreglo = `receipt_case.first_attempt_at`, nunca la del arreglo.
- Zona horaria: `COALESCE(accounts.timezone,'UTC')`; días laborables = `is_account_working_day`.
- n8n: [DEV] primero, luego PROD. Una expresión `={{ … }}` no puede contener `}}` (escribir `} }`). Tras cada PUT: readback y una ejecución real.
- UI: todo texto por `useTranslation`; cada clave en los **5** CSV. `npm run lint` (0 warnings) y `npm run build` pasan.
- **Sin commit ni push salvo que el usuario lo pida.** Cada tarea termina «listo para commit».
- Al usuario: castellano llano, resultado primero.

## Códigos (compartidos por todas las tareas)

`outcome` (lo que devuelve `bot_receive_parcel` y guarda `receipt_case.reason`):
`ok` · `ok_typo_fixed` · `ok_same_city` · `pobox_absent_unavailable` · `pobox_absent_no_visit` · `not_sent_cancelled` · `wrong_city_cancelled` · `already_received` · `blocked` · `not_found` · `ambiguous_typo` · `invalid_format` · `no_panelist` · `no_node`.

`receipt_case.status`: `fixed` · `compensated` · `informative` · `pending` · `needs_decision` · `discarded`.

| outcome | status del caso | culprit_role | recordatorio |
|---|---|---|---|
| `ok` | sin caso | — | no |
| `ok_typo_fixed`, `ok_same_city` | `fixed` | `sender` | solo `ok_typo_fixed` |
| `pobox_absent_no_visit` | `compensated` | `receiver` | sí |
| `pobox_absent_unavailable` | `compensated` | `receiver` | **no** (estaba declarado indisponible) |
| `not_sent_cancelled`, `wrong_city_cancelled` | `compensated` | `sender` | sí |
| `already_received`, `blocked`, `invalid_format` | `informative` | — | no |
| `not_found` | `pending` → (5 laborables) `needs_decision` | — hasta resolverse | no |
| `ambiguous_typo`, `no_panelist`, `no_node` | `needs_decision` | — | no |

Un arreglo (`ok_*`) que la regla POBOX anula después queda con el outcome POBOX (`compensated`, culprit receiver).

## Review Focus

1. El mismo panelista reenvía la misma etiqueta 3 veces seguidas (como Cathy): debe haber **un** caso con `attempts = 3`, y no tres casos ni tres recordatorios. Test en tarea 1 (caso 9).
2. Una etiqueta con una sola cifra cambiada pero que coincide con **dos** envíos `sent` hacia la ciudad: no se arregla nada (`ambiguous_typo`), ningún envío cambia de etiqueta. Test en tarea 1 (caso 4).
3. El panelista declara a las 23:30 hora de Nairobi: el recordatorio no sale de noche (`send_after` = 08:00 del día siguiente, hora local); a las 10:00 sale en el acto. Test en tarea 2 (caso 4).
4. Un caso `not_found` que se resuelve 3 días después por reintento: `received_at` = primer intento (no `now()`), y la regla POBOX se evalúa con esa fecha. Test en tarea 2 (caso 1).
5. Un admin de la cuenta A llamando a una RPC con `p_account_id` de la cuenta B: error 42501, sin datos. Test en tarea 3 (caso 7).

---

### Task 1: Núcleo de BD — casos, recepción con reglas y función del bot

**Files:**
- Create: `supabase/migrations/20261104120000_receipt_cases.sql`
- Test: `supabase/tests/receipt_cases.test.sql`

**Interfaces:**
- Consumes: `normalize_tag(p_raw text) RETURNS text`; `pobox_receipt_check(p_detail allocation_plan_details) RETURNS text`; trigger `pobox_receipt_rule` (se salta con `set_config('onems.skip_pobox_receipt_rule','on',true)`); fixtures `fixtures/incident_city.sql` + `fixtures/no_incident_triggers.sql` (ver `pobox_receipt_after_absence.test.sql` para helpers `mk_sent`, `receive`, `pobox_on`).
- Produces:
  - CHECKs ampliados: `allocation_plan_details_cancellation_reason_check` y `deferred_samples_reason_check` + `'receipt_before_sent','received_wrong_city'`.
  - tabla `public.receipt_case(id uuid pk, account_id uuid not null fk accounts, panelist_id uuid null fk panelists, telegram_id text not null, tag_raw text not null, tag_norm text null, detail_id uuid null fk allocation_plan_details, reason text not null, status text not null, culprit_panelist_id uuid null, culprit_role text null check in ('sender','receiver'), attempts int not null default 1, first_attempt_at timestamptz not null, last_attempt_at timestamptz not null, resolved_at timestamptz null, resolved_by uuid null, resolution_note text null, created_at timestamptz default now())` con CHECKs de `reason`/`status` = listas de «Códigos»; índices `(account_id, first_attempt_at)`, `(account_id, status)`, `(culprit_panelist_id, first_attempt_at)`; único parcial `(account_id, telegram_id, tag_norm) WHERE status IN ('pending','needs_decision')`. Agrupación de intentos: si ya existe un caso abierto (`pending`/`needs_decision`) con el mismo `telegram_id`+`tag_norm`, o un caso de cualquier otro status con el mismo `telegram_id`+`tag_norm`+`reason` cuyo `first_attempt_at` cae el mismo día local, se incrementa `attempts` y `last_attempt_at` en vez de crear otro.
  - `public.receipt_typo_candidates(p_account_id uuid, p_city_id uuid, p_tag text) RETURNS SETOF uuid` STABLE: ids de `allocation_plan_details` `status='sent'`, misma cuenta, destino en un nodo de `p_city_id`, cuyo `tag_id` (8 dígitos) difiere de `p_tag` en exactamente 1 posición, o en 2 posiciones adyacentes intercambiadas; nunca devuelve una etiqueta igual a `p_tag`.
  - `public.register_receipt_with_rules(p_detail_id uuid, p_received_at timestamptz, p_receiver_panelist_id uuid) RETURNS text`: pone `status='received'`, `received_at=p_received_at`, rellena `destination_panelist_id/name` si NULL, con la regla POBOX saltada en el trigger y evaluada **aquí** (`pobox_receipt_check` sobre la fila resultante); si devuelve motivo → inserta en `deferred_samples` (misma forma que `tg_pobox_receipt_rule`, `row_snapshot` con `status='received'`) y deja la fila `cancelled` con ese motivo. Devuelve `'ok'` o el motivo POBOX. Funciona igual con `auth.uid()` NULL o no.
  - `public.cancel_detail_for_compensation(p_detail_id uuid, p_reason text) RETURNS void`: `cancelled` + `cancellation_reason` + `cancelled_at` + fila en `deferred_samples` con ese `reason`.
  - `public.bot_receive_parcel(p_telegram_id text, p_tag_raw text) RETURNS jsonb` SECURITY DEFINER, devuelve `{outcome, registered bool, language, tag, origin_name, origin_city, case_id}`. Orden: panelista por `btrim(telegram_id)` (activo primero) → `no_panelist`/`no_node`; `normalize_tag` vacío o sin dígitos → `invalid_format`; envío con esa etiqueta hacia su nodo (`sent` primero) → `register_receipt_with_rules` (`ok` o POBOX); si `received` → `already_received`; si `pending`/`notified` → `cancel_detail_for_compensation(…,'receipt_before_sent')` → `not_sent_cancelled`; si otro estado → `blocked`; envío con esa etiqueta hacia **otro nodo de la misma ciudad** → mueve destino (`original_destination_node_id` = destino anterior si NULL, `destination_node_id/panelist` = los del receptor) y registra → `ok_same_city` (o POBOX); hacia **otra ciudad** → `wrong_city_cancelled`; si no existe → `receipt_typo_candidates`: 1 → corrige `tag_id`/`idtag` y registra → `ok_typo_fixed` (o POBOX); >1 → `ambiguous_typo`; 0 → `not_found`. Registra/actualiza `receipt_case` según la tabla de «Códigos» (sin caso si `ok`); el bloque de registro de caso va en su propio `BEGIN … EXCEPTION` (fail-open). `origin_name/origin_city` del envío afectado (como hoy, vía `v_allocation_details_with_availability`).
  - `GRANT EXECUTE … bot_receive_parcel TO service_role` (n8n usa la credencial Postgres; comprobar con qué rol conecta y concederle EXECUTE); `REVOKE` de `PUBLIC, anon, authenticated`.

- [ ] **Step 1: Escribir el test** (`\set ON_ERROR_STOP on`, `pg_temp.fail_if`, un `BEGIN … ROLLBACK` por caso; panelista receptor = P4 en N4/C2 con `telegram_id='4004'`; ciudad C1 con N1..N3; cuenta en `Africa/Nairobi`; POBOX desactivado salvo caso 7).

| # | Escenario | Aserciones |
|---|---|---|
| 1 | `sent` N1→N4 tag `00012345`; `bot_receive_parcel('4004','12345')` | outcome `ok`, `registered` true, detalle `received`, 0 casos |
| 2 | `sent` N1→N4 tag `00012345`; bot con `00012354` (adyacentes intercambiados) | `ok_typo_fixed`; detalle con `tag_id='00012354'` y `received`; caso `fixed`, `culprit_role='sender'`, `culprit_panelist_id`=origen |
| 3 | Igual con `00012395` (1 dígito) | `ok_typo_fixed` |
| 4 | Dos `sent` hacia C2 con `00012345` y `00012347`; bot `00012346` | `ambiguous_typo`; ninguna etiqueta cambia; caso `needs_decision` |
| 5 | Detalle `pending` N1→N4 tag `00012345`; bot con esa etiqueta | `not_sent_cancelled`; detalle `cancelled`, `cancellation_reason='receipt_before_sent'`; 1 fila `deferred_samples` reason igual; caso `compensated`, culprit sender |
| 6a | `sent` N1→N5 (N5 nuevo en C2, misma ciudad que N4) | `ok_same_city`; `destination_node_id`=N4, `original_destination_node_id`=N5; caso `fixed` |
| 6b | `sent` N4→N1 (otra ciudad) recibido por P4 | `wrong_city_cancelled`; `deferred_samples` reason `received_wrong_city` |
| 7 | POBOX activo, escenario de `pobox_receipt_after_absence` caso 2 (no_visit) + recepción vía bot | outcome `pobox_absent_no_visit`; caso `compensated`, culprit receiver; **igual con `set_config('request.jwt.claim.sub', <uuid>, true)`** (la regla se aplica aunque haya usuario) |
| 8 | `bot_receive_parcel('9999','12345')` (telegram inexistente) | `no_panelist`; caso `needs_decision` con `panelist_id` NULL y `telegram_id='9999'` |
| 9 | `not_found` tres veces seguidas con la misma etiqueta | 1 caso, `attempts=3`, `first_attempt_at` < `last_attempt_at` |
| 10 | `bot_receive_parcel('4004','abc')` | `invalid_format`, caso `informative` |
| 11 | Recibir dos veces el mismo envío | segunda: `already_received`, caso `informative` |
| 12 | Forzar fallo en el registro del caso (`ALTER TABLE receipt_case ADD CONSTRAINT x CHECK (false) NOT VALID` dentro del caso) en escenario 2 | outcome `ok_typo_fixed`, detalle `received`; sin excepción |

- [ ] **Step 2:** `bash supabase/tests/run_tests.sh receipt_cases` → FAIL (función inexistente).
- [ ] **Step 3:** Escribir la migración con lo de «Produces».
- [ ] **Step 4:** `bash supabase/tests/run_tests.sh receipt_cases pobox_receipt_after_absence tag_normalization_receipt ds_register ds_reintroduce` → PASS todos.
- [ ] **Step 5:** Listo para commit — `feat(recepcion): registro de casos y recepcion del bot con arreglo automatico`.

---

### Task 2: Reintentos, recordatorios y cola de avisos

**Files:**
- Create: `supabase/migrations/20261104121000_receipt_retry_and_reminders.sql`
- Test: `supabase/tests/receipt_retry_reminders.test.sql`

**Interfaces:**
- Consumes: Task 1 (`receipt_case`, `bot_receive_parcel`, `register_receipt_with_rules`, `receipt_typo_candidates`, códigos).
- Produces:
  - `panelist_notification`: columna `send_after timestamptz NULL`; CHECK de `kind` + `'receipt_reminder','manager_notice','broadcast'`; columna `case_id uuid NULL fk receipt_case`; índice único parcial `(panelist_id, (payload->>'reason'), (payload->>'local_date')) WHERE kind='receipt_reminder'`.
  - `public.receipt_send_after(p_account_id uuid, p_at timestamptz) RETURNS timestamptz`: `p_at` si la hora local ∈ [08:00, 20:00); si no, 08:00 local del día siguiente (o del mismo día si es antes de las 08:00).
  - `public.enqueue_receipt_reminder(p_case_id uuid) RETURNS uuid` (NULL si no procede): solo para casos con culprit y outcome con «recordatorio = sí»; payload `{reason, tag, local_date (fecha local de first_attempt_at), escalated bool, case_id}`; `escalated` = el culprit tiene ≥3 casos (este incluido) con el mismo `reason` en los últimos 7 días; `ON CONFLICT DO NOTHING` (uno al día por panelista y motivo). Llamada desde `bot_receive_parcel` (re-emitir la función completa añadiendo la llamada dentro del bloque fail-open) y desde los reintentos.
  - `public.receipt_retry_pending() RETURNS int` (nº resueltos): para cada caso `not_found` `pending`: repite la búsqueda exacta + typo (sin crear casos nuevos) y, si resuelve, `register_receipt_with_rules(detail, first_attempt_at, panelist_id)`, actualiza el caso (`reason` final, status, culprit) y encola recordatorio; si no resuelve y han pasado ≥5 días laborables desde `first_attempt_at` → `needs_decision`.
  - pg_cron `receipt-retry` `*/30 * * * *` → `SELECT public.receipt_retry_pending()` (idempotente: `cron.unschedule` previo si existe; patrón de `poll_cron.test.sql`).

- [ ] **Step 1: Escribir el test**

| # | Escenario | Aserciones |
|---|---|---|
| 1 | `not_found` el lunes 10:00+03 (`now` simulado con `first_attempt_at` fijado); luego se inserta el `sent` con esa etiqueta; `receipt_retry_pending()` | devuelve 1; detalle `received` con `received_at` = primer intento; caso `fixed`/`ok` |
| 2 | `not_found`, nada aparece, `first_attempt_at` hace 8 días naturales (≥5 laborables) | caso `needs_decision` |
| 3 | `not_found`, aparece un candidato typo único | caso `fixed`, reason `ok_typo_fixed`, 1 `receipt_reminder` al remitente |
| 4 | `receipt_send_after` con 23:30, 07:00 y 10:00 Nairobi | 08:00 día siguiente / 08:00 mismo día / sin cambio |
| 5 | Tres `pobox_absent_no_visit` del mismo receptor en 3 días | 3 recordatorios; el 3.º `escalated=true` |
| 6 | Dos `not_sent_cancelled` del mismo remitente el mismo día | 1 solo recordatorio |
| 7 | `pobox_absent_unavailable` | 0 recordatorios |

- [ ] **Step 2:** run → FAIL. **Step 3:** migración. **Step 4:** `bash supabase/tests/run_tests.sh receipt_retry_reminders receipt_cases poll_cron` → PASS.
- [ ] **Step 5:** Listo para commit — `feat(recepcion): reintentos de etiquetas no encontradas y recordatorios al panelista`.

---

### Task 3: RPCs de la pantalla del admin

**Files:**
- Create: `supabase/migrations/20261104122000_receipt_manager_rpcs.sql`
- Test: `supabase/tests/receipt_manager_rpcs.test.sql`

**Interfaces:**
- Consumes: Tasks 1-2.
- Produces (todas `SECURITY DEFINER`, control de cuenta de Global Constraints, `GRANT EXECUTE TO authenticated`):
  - `rpc_receipt_day_summary(p_account_id uuid, p_date date) RETURNS jsonb`: `{attempts, ok_first_time, fixed, compensated, pending, needs_decision, informative, by_reason: {reason: n}}`; `ok_first_time` = detalles recibidos ese día local sin caso; `attempts` = `ok_first_time` + suma de `attempts` de casos con `first_attempt_at` ese día.
  - `rpc_receipt_trend(p_account_id uuid, p_days int DEFAULT 30) RETURNS TABLE(day date, ok_first_time int, fixed int, compensated int, open int)`.
  - `rpc_receipt_repeat_panelists(p_account_id uuid) RETURNS TABLE(panelist_id uuid, name text, panelist_code text, language text, fails_7d int, fails_30d int, top_reason text, last_notice_at timestamptz)`: por `culprit_panelist_id`, solo con `fails_30d > 0`, orden `fails_7d DESC, fails_30d DESC`; `last_notice_at` = último `panelist_notification` `manager_notice` o `receipt_reminder` enviado.
  - `rpc_receipt_cases(p_account_id uuid, p_status text DEFAULT NULL, p_date date DEFAULT NULL) RETURNS TABLE(id, panelist_name, tag_raw, tag_norm, reason, status, attempts, first_attempt_at, detail_id, culprit_name, culprit_role, resolved_by_name, resolved_at)`.
  - `rpc_receipt_case_fix(p_case_id uuid, p_detail_id uuid) RETURNS text`: solo casos `needs_decision`/`pending`; el detalle debe ser de la cuenta y `sent`; si su etiqueta ≠ `tag_norm` se corrige; destino de otra ciudad → error `22023`; misma ciudad → mueve destino; `register_receipt_with_rules(detail, first_attempt_at, panelist)`; caso `fixed` (o `compensated` si POBOX), `resolved_by = auth.uid()`; devuelve el outcome.
  - `rpc_receipt_case_close(p_case_id uuid, p_note text) RETURNS void`: con `detail_id` cuyo detalle está `sent`/`pending`/`notified` → `cancel_detail_for_compensation(detail, 'receipt_before_sent')` y caso `compensated`; con detalle en otro estado o sin `detail_id` → caso `discarded` sin tocar ningún envío. Guarda nota y `resolved_by`.
  - `rpc_send_panelist_notice(p_panelist_id uuid, p_body text) RETURNS uuid`: encola `manager_notice` `{body, author_user_id}`; panelista de la cuenta del llamante; body 1..3000.
  - `rpc_broadcast_notice(p_account_id uuid, p_bodies jsonb) RETURNS int`: `p_bodies` = `{"en": "...", "es": "...", ...}`; una fila `broadcast` por panelista `status='active'` con `telegram_id` numérico; texto = `p_bodies->>language` o `en`; payload `{body, broadcast_id (uuid común), author_user_id}`; devuelve nº encolados.
  - `rpc_broadcast_recipients(p_account_id uuid) RETURNS TABLE(language text, n int)` (para la confirmación).
  - `rpc_broadcast_history(p_account_id uuid) RETURNS TABLE(broadcast_id uuid, created_at timestamptz, body_en text, total int, sent int, failed int)`.

- [ ] **Step 1: Test** (usuarios simulados con `set_config('request.jwt.claim.sub', …)` y `profiles` de fixtures; ver `incident_manager_rpcs.test.sql`):
  1. summary con 2 recepciones ok + 1 caso fixed (attempts 2) → `attempts=4, ok_first_time=2, fixed=1`;
  2. repeat_panelists ordena por fails_7d;
  3. case_fix sobre `not_found` con detalle de etiqueta distinta → etiqueta corregida, `received_at`=primer intento, caso `fixed`, `resolved_by` = usuario;
  4. case_fix con detalle de otra ciudad → error 22023;
  5. case_close sin detalle → `discarded`;
  6. broadcast con 3 panelistas activos (en, es, sin telegram) → 2 filas, cada una en su idioma;
  7. admin de cuenta B → 42501 en summary, cases, broadcast;
  8. superadmin → acceso a cualquier cuenta.
- [ ] **Step 2-4:** FAIL → migración → `bash supabase/tests/run_tests.sh receipt_manager_rpcs receipt_retry_reminders receipt_cases` PASS.
- [ ] **Step 5:** Listo para commit — `feat(recepcion): RPCs de seguimiento, decisiones y avisos para el admin`.

---

### Task 4: Aplicar en onems-dev y repetir los casos de Kenya

- [ ] **Step 1:** Pedir al usuario OK explícito: «aplicar 3 migraciones en **onems-dev (`sehbnpgzqljrsqimwyuz`)**». Sin OK, parar.
- [ ] **Step 2:** `apply_migration` de las tres en orden; `list_migrations` las muestra.
- [ ] **Step 3:** Verificación sin escribir datos reales: dentro de `BEGIN … ROLLBACK` vía `execute_sql`, `SELECT bot_receive_parcel('<telegram de Cathy>','00010406')` → `blocked`; con un envío `sent` real de Kenya tecleado con un dígito cambiado → `ok_typo_fixed`. Comprobar `cron.job` contiene `receipt-retry`.
- [ ] **Step 4:** `get_advisors` (security) sin avisos nuevos sobre las tablas/funciones creadas.

---

### Task 5: Bot y entrega de avisos en n8n DEV

**Files (repo `panelist_n8n/workflows`, tras sincronizar con `sync_repo.py write`):** `dev-mark-parcel-as-received.json` (`dg9yQ4eqCYnB2tcl`), `deliver-panelist-notifications.json` (`592sTnywfgiIGKI7`, solo existe en PROD: ver step 4).

- [ ] **Step 1:** En `[DEV] Mark Parcel as received`: «Validate input» deja de cortar por formato de etiqueta (solo valida `telegram_id`); «Find and mark received» pasa a `SELECT public.bot_receive_parcel($1::text, $2::text) AS r` con `$2 = tag_raw`; «Receipt response» lee `r.outcome` y tiene un mensaje por outcome en 5 idiomas, que dice el motivo real y qué hacer (ok / ok_typo_fixed: «registrado; la etiqueta del envío estaba mal declarada y la hemos corregido» / ok_same_city / pobox_absent_no_visit: «no vale porque el día laborable anterior no hay envío tuyo declarado; ve al apartado cada día» / pobox_absent_unavailable / not_sent_cancelled: «el remitente no lo había declarado; se volverá a enviar» / wrong_city_cancelled / already_received / blocked / not_found: «no lo encontramos; lo seguiremos buscando unos días» / ambiguous_typo / invalid_format / no_panelist / no_node). `action` = `'ok'` solo si `registered` y outcome empieza por `ok`.
- [ ] **Step 2:** Comprobar que ninguna expresión contiene `}}` interno (`fixbrace.py dry`), PUT, readback.
- [ ] **Step 3:** Prueba real con el bot DEV (el usuario declara una etiqueta de prueba: correcta, con un dígito cambiado e inexistente) y revisar las 3 ejecuciones y las filas de `receipt_case`.
- [ ] **Step 4:** «Deliver panelist notifications» (PROD, único): pedir OK al usuario antes de tocarlo. Cambios: horario cada 15 min; `WHERE … AND (n.send_after IS NULL OR n.send_after <= now())`; «Build message» añade `receipt_reminder` (texto por `reason` × 5 idiomas, variante `escalated` con «tu responsable está informado»), `manager_notice` y `broadcast` (texto = `payload.body` tal cual). Las kinds existentes no cambian. PUT + readback + una ejecución con un aviso de prueba al Telegram del usuario (pedir su panelista de prueba).
- [ ] **Step 5:** Listo para commit en `panelist_n8n` (sincronizar con `sync_repo.py write`, claves tapadas).

---

### Task 6: Promoción del bot a PROD

- [ ] **Step 1:** Pedir OK. Aplicar los mismos cambios del Step 1 de la tarea 5 a `Mark Parcel as received` (`pEOWvi8uU4JhYUf4`), comparando antes el vivo con el JSON.
- [ ] **Step 2:** `fixbrace.py dry`, PUT, readback, `active=true`.
- [ ] **Step 3:** Vigilar las ejecuciones reales de la siguiente hora (`n8n_executions` del flujo y del «Telegram - User initiated message» `IkVtek2csP5AbWxB`): 0 errores; filas nuevas en `receipt_case` coherentes.
- [ ] **Step 4:** Listo para commit (repo n8n).

---

### Task 7: Pestaña «Recepciones» (frontend)

**Files:**
- Create: `src/lib/hooks/useReceiptErrors.ts`, `src/pages/incidents/ReceiptErrors.tsx`, `src/components/incidents/receipts/ReceiptDaySummary.tsx`, `ReceiptRepeatPanelists.tsx`, `ReceiptCasesTable.tsx`, `PanelistNoticeDialog.tsx`, `BroadcastDialog.tsx`, `src/lib/receiptNoticeTemplates.ts`
- Modify: `src/App.tsx` (ruta `/incidents/receipts`, `ProtectedRoute allowedRoles={['superadmin','admin']}`), `src/components/layout/Sidebar.tsx` (ítem en el grupo `incidents.menu_group`, icono `PackageX` de lucide, roles admin/superadmin), `src/lib/types` (tipos de las RPCs), `public/locales/{en,es,fr,ar,pt}.csv` (claves `receipt_errors.*`).

**Interfaces:**
- Consumes: RPCs de la tarea 3 con `p_account_id = effectiveAccountId` (`useAccount()`), como `useReportedIncidents`.
- Produces: hook `useReceiptErrors(date: string)` → `{summary, trend, repeaters, cases, loading, error, refresh, fixCase(caseId, detailId), closeCase(caseId, note), sendNotice(panelistId, body), broadcast(bodies), recipients()}`.

- [ ] **Step 1:** Página: selector de fecha (hoy por defecto) + tres bloques de la spec §5 (resumen con tarjetas y reparto por motivo; gráfica recharts de 30 días con `fixed/compensated/open/ok_first_time`; repetidores; pendientes de decisión con «Arreglar» —pide el envío correcto: lista de envíos `sent` hacia la ciudad del panelista vía `allocation_plan_details`— y «Pasar a compensar / Descartar»). Motivos y estados traducidos (`receipt_errors.reason.<code>`, `receipt_errors.status.<code>`).
- [ ] **Step 2:** `PanelistNoticeDialog`: prellena con `receiptNoticeTemplates[top_reason][panelist.language]` (contenido para el panelista en SU idioma, por eso fuera de los CSV), editable, enviar → `sendNotice`. `BroadcastDialog`: plantilla elegible (incluida la lección POBOX en los 5 idiomas), una pestaña por idioma presente en `rpc_broadcast_recipients`, muestra nº de destinatarios, confirmación, historial (`rpc_broadcast_history`).
- [ ] **Step 3:** `npm run lint` → 0 warnings; `npm run build` → OK.
- [ ] **Step 4:** Probar en navegador (`npm run dev`) con cuenta KENYA: el día 2026-11-04 aparecen los casos reales registrados desde la tarea 6; un admin de otra cuenta no ve nada de Kenya.
- [ ] **Step 5:** Listo para commit — `feat(incidencias): pestaña Recepciones con seguimiento diario y avisos`.

---

### Task 8: Ayuda

**Files:** `public/help/incidents-and-availability.{en,es,fr,ar,pt}.html`, `public/help/panelist-guide.{en,es,fr,ar,pt}.html`.

- [ ] **Step 1:** Sección «Errores de recepción» en la ayuda del admin: qué arregla el sistema solo, qué pasa a compensar, cómo leer la pestaña, cuándo usar mensaje individual o aviso general.
- [ ] **Step 2:** En la guía del panelista: «Visita tu apartado cada día laborable» (texto de la lección del 2026-11-04) y qué significa cada respuesta del bot al declarar una recepción.
- [ ] **Step 3:** Listo para commit — `docs(ayuda): errores de recepcion y visita diaria al apartado`.
