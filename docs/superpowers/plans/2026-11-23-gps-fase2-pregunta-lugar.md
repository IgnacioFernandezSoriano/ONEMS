# GPS fase 2 — preguntar el lugar solo cuando la posición no cuadra Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cuando la posición de una visita sale fuera del sitio correcto, el bot pregunta una vez «¿Estás en tu
apartado?» (ciudad POBOX) o «¿Estás en tu domicilio?» (sin POBOX). Si la respuesta es «Sí», esa posición pasa a ser la
referencia del panelista. Si es «No», el bot manda un recordatorio y se registra una incidencia ya resuelta para la
estadística.

**Architecture:** La lógica vive en la BD (onems-dev): una tabla de referencias por panelista, la clasificación contra
esa referencia y una función que procesa la respuesta. El bot n8n solo pregunta, recoge el botón y llama a la BD. Se
hace en DEV antes que en PROD.

**Tech Stack:** PostgreSQL 17 (Supabase, plpgsql), pruebas psql en el Postgres portable local; n8n (bot Telegram) vía
n8n-mcp.

**Spec:** `docs/superpowers/specs/2026-11-20-gps-casa-apartado-design.md`. **§2 bis (decisiones del 23/11) prevalece**
sobre §5.4, §5.8 y §9 donde choquen. Parte de la fase 1 ya aplicada (`20261123180000..180200`).

## Global Constraints

- BD única onems-dev `sehbnpgzqljrsqimwyuz`. **Antes de cada escritura (migración o bot PROD): nombrar proyecto + ref
  y pedir confirmación explícita a Ignacio.** Nunca `db push`/`db reset` remoto.
- Migraciones forward-only, serie `202611231900xx` (Carrier Link usa `20261123100000` y `20261124…`; no intercalarse).
- Partir de la definición **viva** de cada función que se reemplaza: comparar su huella sin comentarios ni espacios
  (`md5(regexp_replace(regexp_replace(prosrc,'--[^\n]*','','g'),'\s','','g'))`) con la del repo. Si difieren, gana la
  viva y se avisa.
- Radio «en el sitio correcto»: `gps_setting('ok_radius_m')` (300). No hay umbrales nuevos fijos en el código:
  `ref_review_pobox_m` = 1000 y `ref_review_home_city_m` = 5000 se guardan en `gps_settings`.
- **Nunca bloquear ni perder una declaración.** Las funciones que llama el bot dentro de una declaración nunca lanzan.
- Mensajes al panelista escuetos y sin acusar, siempre en 5 idiomas (es, en, fr, ar, pt), como los mensajes GPS actuales.
- Una sola pregunta por visita (ventana de 30 min, la del 17/11); la respuesta vale para todas las declaraciones de la visita.
- Aislamiento por `account_id` y RLS en toda tabla nueva. Funciones nuevas: `REVOKE` a PUBLIC/anon/authenticated y
  `GRANT` a service_role.
- Pruebas locales con el runner propio (BD `onems_test_gps`, ver plan de la fase 1), nunca `onems_t`/`onems_test`.
- Bot: `[DEV]` (`eeM4E4RS1UDThvUF`) primero; PROD (`IkVtek2csP5AbWxB`) solo tras probar en DEV y con el visto bueno de
  Ignacio. Antes de editar, comparar el flujo vivo con `panelist_n8n/workflows/*.json`. Las claves de los nodos se tapan
  al copiar el JSON al repo.
- Trabajo en worktrees: ONEMS `fix/gps-solo-distancia` → rama nueva `feat/gps-pregunta-lugar` desde ella;
  panelist_n8n rama `feat/gps-pregunta-lugar` desde `origin/main`. Commit/PR solo si Ignacio lo pide.

## Fuera de este plan (fase 3)

Paso del alta (§5.3), recordatorio de la casa al día siguiente del alta, informe L-X-V con las respuestas
(§5.9; partir de `ops_report._data` de Carrier Link), historial del panelista en la web (§5.8 bis), guía del panelista
y aviso a gestores. `from_home` (casa en ciudad POBOX) ya no hace falta con la regla del 23/11.

## Review Focus

1. Panelista sin nodo, o ciudad sin política → `gps_place_kind` usa la política de la cuenta (`account_config.pobox_enabled`);
   si tampoco la hay → `'home'`. Sin error.
2. Botón pulsado dos veces, o después de que caduque la visita (más de 30 min) → no duplica la referencia ni la
   incidencia: devuelve `already_answered` o `expired`.
3. «Sí» en una visita sin posición válida (por ejemplo, tras «Mi GPS no funciona») → `no_location`, no se guarda nada.
4. «Sí» cuando ya hay una referencia de ese tipo → la antigua pasa a `active = false` y queda **una sola** activa por
   `(panelist_id, kind)` (índice único parcial).
5. Otra cuenta: un usuario `authenticated` de la cuenta B no lee las referencias de la cuenta A (RLS). Las funciones
   escriben siempre con el `account_id` del panelista.

---

### Task 1: Referencias y clasificación contra la referencia

**Files:**
- Create: `supabase/migrations/20261123190000_gps_place_reference.sql`
- Test: `supabase/tests/gps_place_reference.test.sql` (misma fixture que `gps_solo_distancia.test.sql`; la ciudad
  POBOX se fija con `account_config.pobox_enabled` o con la política de ciudad que lee `effective_city_policy`)

**Interfaces:**
- Produces: tabla `public.panelist_location_reference` (`id`, `account_id`, `panelist_id` FK ON DELETE CASCADE,
  `kind` CHECK `('pobox','home')`, `latitude`/`longitude` numeric(10,7) NULL, `captured_at`, `source` CHECK
  `('declaration','registration','declined')`, `location_id` FK `declaration_location` ON DELETE SET NULL,
  `distance_to_postal_center_m`, `needs_review` bool default false, `review_reason` text, `active` bool default true,
  `created_at`). Índice único parcial `(panelist_id, kind) WHERE active AND source <> 'declined'`. RLS SELECT
  `account_id = current_user_account_id() OR is_superadmin()`; sin escritura para la app.
  La fila `source = 'declined'` (sin coordenadas, `active = false`) marca «no quiere que guardemos su casa» (Task 2).
- Produces: `declaration_location` + columnas `ref_kind text` CHECK `('postal_center','pobox','home')`,
  `reference_id uuid` FK a la tabla de referencias ON DELETE SET NULL, `ref_distance_m numeric`. `distance_m` sigue
  siendo la distancia a la oficina más cercana (el informe actual no cambia de significado).
- Produces: `gps_settings` + filas `ref_review_pobox_m` = 1000, `ref_review_home_city_m` = 5000.
- Produces: `public.gps_place_kind(p_panelist_id uuid) RETURNS text` → `'pobox'|'home'` (STABLE, SECURITY DEFINER).
  Orden: `effective_city_policy(ciudad del nodo).pobox_enabled`; si no hay ciudad, `account_config.pobox_enabled`;
  si no hay nada, `'home'`.
- Produces: `public.gps_active_reference(p_panelist_id uuid, p_kind text) RETURNS public.panelist_location_reference`
  (la activa con coordenadas, o NULL).
- Modifies (misma firma): `gps_save_location(...)`. Su `jsonb` de respuesta añade `ask_place boolean` y
  `place_kind text`.

- [ ] **Step 1: Pruebas que fallan** (centro A en (-1.28, 36.82); 0.0009° de latitud ≈ 100 m; permiso `granted`):
  - `kind_pobox_ciudad` / `kind_pobox_cuenta` / `kind_home_defecto` → `gps_place_kind` da `pobox`, `pobox` y `home`
    (Review Focus 1, incluido un panelista con `node_id NULL`).
  - `pobox_sin_ref_lejos`: POBOX, sin referencia, ≈400 m de la oficina → `status='far'`, `ref_kind='postal_center'`,
    `ask_place=true`, `place_kind='pobox'`. Una segunda posición en la misma visita → `ask_place=false`.
  - `pobox_sin_ref_cerca`: ≈200 m → `ok`, `ask_place=false`.
  - `pobox_con_ref`: referencia `pobox` activa a 2 km de la oficina; posición a ≈100 m de la referencia → `ok`,
    `ref_kind='pobox'`, `reference_id` puesto, `ref_distance_m` ≈100 y `distance_m` ≈ distancia a la oficina.
  - `home_sin_ref`: ciudad sin POBOX y sin referencia → `status='no_reference'` y `ask_place=true` en cada visita nueva
    mientras no haya casa.
  - `home_declinada`: con una fila `source='declined'` → `ask_place=false`.
  - `home_con_ref_lejos`: referencia `home`, posición a ≈400 m → `far`, `ref_kind='home'`, `ask_place=true`.
  - `rls_otra_cuenta` (Review Focus 5): como `authenticated` de la cuenta 2, `count(*)` de referencias = 0.
  - `una_activa` (Review Focus 4): un segundo INSERT activo del mismo `(panelist, kind)` falla por el índice único.

- [ ] **Step 2: Correr y ver que fallan.** `gpstest.sh mig` de la migración + `gpstest.sh test gps_place_reference`.
  Expected: FAIL (`gps_place_kind` no existe).

- [ ] **Step 3: Implementar la migración.** En `gps_save_location`, después de calcular oficina y distancia (igual
  que ahora): `kind := gps_place_kind(...)` y `ref := gps_active_reference(p, kind)`.
  - Si hay referencia: estado `ok` o `far` según `ref_distance_m` frente al radio.
  - Si no hay y `kind = 'pobox'`: `gps_classify(oficina, distance_m)` y `ref_kind = 'postal_center'`.
  - Si no hay y `kind = 'home'`: `no_reference`.
  - `ask_place` vale true si la visita no tiene `place_asked` **y** (`status = 'far'` **o** (`kind = 'home'` sin
    referencia y sin fila `declined`)). Cuando es true, marcar `place_asked = true` en la visita.
  - El resto de la función no cambia (enlace retroactivo, incidencias).

- [ ] **Step 4: Correr las pruebas GPS** (`gps_place_reference`, `gps_solo_distancia`, `gps_declaracion`, `gps_ask_once`,
  `gps_consent_keep`, `gps_erase`, `ops_report_gps`, `ops_test_gps_incident`). Expected: todo PASS. Si una prueba
  antigua de DEMO2 o de una ciudad sin POBOX esperaba `ok`/`far` contra la oficina, se actualiza a `no_reference` (regla
  nueva) y se anota.

- [ ] **Step 5: Commit** (solo si Ignacio lo ha pedido).

### Task 2: Respuesta del panelista, recordatorio e incidencia resuelta

**Files:**
- Create: `supabase/migrations/20261123190100_gps_answer_place.sql`
- Test: `supabase/tests/gps_answer_place.test.sql`

**Interfaces:**
- Consumes: la tabla, `gps_place_kind` y `gps_active_reference` de la Task 1; `gps_visit_location`, `gps_get_visit`,
  `insert_panelist_incident_auto` y `gps_current_consent`, que ya existen.
- Produces: `allocation_plan_details` + `sent_self_reported_place`, `received_self_reported_place` text CHECK
  `('pobox','home','other')`.
- Produces: `public.gps_consent_version(p_panelist_id uuid) RETURNS text`, la versión del último permiso `granted`
  (`'v4'`, `'v3'`…).
- Produces: `public.gps_answer_place(p_panelist_id uuid, p_answer text, p_texts jsonb) RETURNS jsonb`.
  - `p_answer` puede ser `'yes'`, `'no'` o `'home_declined'`.
  - `p_texts` es `{question, answer, reminder}`: los textos exactos que ve el panelista, para dejarlos registrados.
  - Devuelve `{action, place_kind, incident_id}`. `action` puede ser `reference_saved`, `reminder`, `need_v4`,
    `declined_saved`, `no_location`, `already_answered` o `expired`.
  - Nunca lanza: si hay un error, devuelve `{action:'error'}` y deja un `RAISE WARNING`.
- Modifies (misma firma): `gps_mark_declaration` (copia la respuesta de la visita en `*_self_reported_place` y, tras
  un «No», añade la declaración a la incidencia de la visita) y `gps_erase_panelist_locations` (borra también las
  referencias del panelista y pone `ref_distance_m` a NULL).

- [ ] **Step 1: Pruebas que fallan:**
  - `si_guarda_pobox`: POBOX, posición `far` en la visita, `gps_answer_place(P,'yes',…)` → `reference_saved`.
    - Referencia `pobox` activa con las coordenadas de esa posición, `source='declaration'` y `location_id` puesto.
    - La posición pasa a `ok` y las declaraciones de la visita ya marcadas pasan de `far` a `ok`, con
      `*_self_reported_place='pobox'`.
    - 0 incidencias nuevas.
  - `si_needs_review`: referencia `pobox` a > 1000 m de la oficina → `needs_review = true`,
    `review_reason = 'pobox_far_from_postal_center'`. En el caso `home`: a > 5000 m del centro de la ciudad del nodo →
    `'home_far_from_city'`. «Centro de la ciudad» = media de las coordenadas de sus oficinas; si no hay ninguna, no se
    comprueba.
  - `si_reemplaza` (Review Focus 4): ya había referencia → la antigua queda `active=false` y la nueva activa.
  - `no_recordatorio`: `gps_answer_place(P,'no',{question:'Q',answer:'A',reminder:'R'})` → `reminder` con `incident_id`.
    - La incidencia: `category='gps_location'`, `status='auto_resolved'`, `resolved_at` puesto, `created_via='telegram'`,
      `description='📍 Panelist confirmed declaring from a place that is not the correct one'`.
    - Su payload: `{reason:'wrong_place', place_kind, visit_started_at, location_id, ref_distance_m, declarations:[…]}`.
      La clave es `declarations`, **no** `details`, para que `gps_refresh_incident` y el recálculo no la toquen.
    - 3 filas `incident_message` (`incident_kind='reported'`): Q (outbound, bot, sent), A (inbound, panelist,
      received) y R (outbound, bot, sent).
    - Las declaraciones de la visita quedan con `*_self_reported_place='other'` y siguen en `far`.
  - `no_luego_declara`: tras el «No», `gps_mark_declaration` de otra declaración de la visita → se añade a
    `payload.declarations` y queda con `'other'`. La incidencia sigue `auto_resolved` y no se crea ninguna nueva.
  - `doble_pulsacion` (Review Focus 2): segundo `gps_answer_place` en la misma visita → `already_answered`, sin filas
    nuevas. Con la visita caducada (`created_at` − 31 min) → `expired`.
  - `si_sin_posicion` (Review Focus 3): visita sin posición → `no_location`.
  - `home_necesita_v4`: sin POBOX, el último permiso `granted` es `v3`, «Sí» → `need_v4` y no guarda nada. Tras
    `gps_record_consent(P,'granted','es','v4',…)`, otro «Sí» → `reference_saved` (kind `home`). Esa es la única
    excepción a `already_answered`: la visita guarda `place_answer = 'yes_pending_v4'`.
  - `home_declinada`: `'home_declined'` → `declined_saved`. Fila `source='declined'` sin coordenadas, el permiso
    vigente sigue `granted` y la siguiente visita tiene `ask_place=false`.
  - `borrar_mis_datos`: `gps_erase_panelist_locations` → 0 referencias del panelista y `ref_distance_m` NULL en todas
    sus posiciones.

- [ ] **Step 2: Correr y ver que fallan.** Expected: FAIL (`gps_answer_place` no existe).

- [ ] **Step 3: Implementar la migración.** El estado vive en la visita (`panelist_context` 'gps_visit'), con las
  claves `place_asked`, `place_answer` (`yes`|`no`|`yes_pending_v4`|`home_declined`) y `place_incident_id`. Al
  reemplazar `gps_mark_declaration` y `gps_erase_panelist_locations`, partir de su cuerpo vivo y verificar la huella.

- [ ] **Step 4: Correr todas las pruebas GPS** (las de la Task 1 + `gps_answer_place`). Expected: PASS.

- [ ] **Step 5: Commit** (misma regla).

### Task 3: Bot DEV — pregunta, botones, recordatorio y permiso v4

**Files:** flujo n8n `[DEV]` `eeM4E4RS1UDThvUF` (vía n8n-mcp, cambios parciales) y su copia
`panelist_n8n/workflows/dev-telegram-user-initiated-message.json` (con las claves tapadas).

**Interfaces:**
- Consumes: `gps_save_location` → `ask_place`, `place_kind` (Task 1). `gps_answer_place`, `gps_record_consent`
  con versión `'v4'` (Task 2).
- Produces: callbacks `gps_place:yes`, `gps_place:no`, `gps_v4:yes`, `gps_v4:no`.

- [ ] **Step 1:** Comparar el DEV vivo con el JSON del repo y guardar una copia de seguridad del DEV en
  `panelist_n8n/backups/`.
- [ ] **Step 2: Nodo `GPS save location`.** Devuelve también `ask_place` y `place_kind`. Tras `Send GPS location saved`:
  - Si `ask_place` → nodo nuevo `Send GPS place question` (botones en línea) y **no** se retoma la declaración. El
    panelista puede seguir declarando igualmente: el enrutado por foto o número no depende de la pregunta.
  - Si no → `GPS resume target`, como hoy.
- [ ] **Step 3: `Route & Identify`.** Añadir `gps_place:yes|no` → acción `gps_place` (`gps_place_answer`) y
  `gps_v4:yes|no` → acción `gps_v4`, con el mismo patrón que `gps_consent`. Añadir las salidas `gps_place` y `gps_v4`
  en `Main Router`.
- [ ] **Step 4: Rama `gps_place`.**
  - Quitar los botones del mensaje de la pregunta, igual que hace `Edit GPS consent message`.
  - Llamar a `gps_answer_place` con `p_texts` = {texto de la pregunta, etiqueta del botón pulsado, recordatorio del
    idioma y tipo}.
  - Según `action`:
    - `reminder` → enviar el recordatorio.
    - `reference_saved` → enviar «✅ Gracias, lo hemos anotado.».
    - `need_v4` → enviar el texto v4 con los botones `gps_v4:yes|no`.
    - `already_answered`, `expired`, `no_location` o `error` → nada.
  - Después, `GPS resume target`, salvo en `need_v4`.
- [ ] **Step 5: Rama `gps_v4`.**
  - `yes`: `gps_record_consent(granted, 'v4', texto v4)` y después `gps_answer_place(P,'yes',…)`.
  - `no`: `gps_answer_place(P,'home_declined',…)`.
  - Después, `GPS resume target`.
- [ ] **Step 6:** El texto general del permiso (`Send GPS consent request`, el menú de permiso y `GPS_CONSENT_TEXT` de
  `Route & Identify`) pasa a v4 con versión `'v4'`. Quitar `GPS low accuracy?`, `Send GPS low accuracy` y la acción
  `gps_retry`: ya no tienen uso desde la fase 1.
- [ ] **Step 7: Textos exactos.** ES y EN fijados aquí. FR, AR y PT los traduce el implementador con el mismo tono y
  los revisa Ignacio antes de PROD.

  | Clave | ES | EN |
  |---|---|---|
  | pregunta pobox | 📍 ¿Estás ahora en tu apartado de correos? | 📍 Are you at your PO Box right now? |
  | botón sí pobox | 📮 Sí, estoy en mi apartado | 📮 Yes, I'm at my PO Box |
  | pregunta home | 📍 ¿Estás ahora en tu domicilio (la dirección que nos diste)? | 📍 Are you at home right now (the address you gave us)? |
  | botón sí home | 🏠 Sí, estoy en casa | 🏠 Yes, I'm at home |
  | botón no | ❌ No | ❌ No |
  | recordatorio pobox | 📮 Recuerda: las declaraciones se hacen desde tu apartado de correos. ¡Gracias! | 📮 Remember: declarations are made from your PO Box. Thank you! |
  | recordatorio home | 🏠 Recuerda: las declaraciones se hacen desde tu domicilio. ¡Gracias! | 🏠 Remember: declarations are made from your home address. Thank you! |
  | gracias sí | ✅ Gracias, lo hemos anotado. | ✅ Thank you, noted. |
  | v4 | v3 vivo con los cambios de spec §6 (lo usamos para comprobar que declaras desde el sitio que te corresponde: tu apartado de correos o, si en tu ciudad no hay, tu casa; 🏠 guardamos una vez la ubicación de tu casa y, si tienes, de tu apartado) | ídem |
  | botones v4 | ✅ Acepto / ❌ No, no guardar mi casa | ✅ I accept / ❌ No, don't save my home |

- [ ] **Step 8: Probar en DEV con el panelista DEV**, en Android y en iPhone si es posible:
  - POBOX lejos → «No» → recordatorio. En la BD: 1 incidencia `auto_resolved` con 3 mensajes.
  - Nueva visita → «Sí» → referencia guardada. Siguiente visita en el mismo sitio → sin pregunta.
  - Sin POBOX con permiso v3 → «Sí» → v4 → «Acepto» → casa guardada. Repetir con «No» → `declined` y no vuelve a
    preguntar.
  - Pulsar dos veces el mismo botón → no pasa nada.
  - Declarar sin contestar → la declaración se registra igual.
- [ ] **Step 9:** Copiar el flujo DEV al repo (claves tapadas). Commit solo si Ignacio lo pide.

### Task 4: Producción y verificación

- [ ] **Step 1:** Antes de aplicar, `list_migrations` para ver si Carrier Link ha aplicado algo nuevo, y comparar las
  huellas vivas de `gps_save_location`, `gps_mark_declaration` y `gps_erase_panelist_locations`.
- [ ] **Step 2:** Pedir a Ignacio confirmación explícita: «aplico 2 migraciones en onems-dev
  (`sehbnpgzqljrsqimwyuz`)». Aplicarlas en orden. Las migraciones son compatibles con el bot PROD actual: ignora
  `ask_place`.
- [ ] **Step 3:** Ignacio revisa los textos FR/AR/PT y el v4. Explicarle antes qué verán los panelistas de Kenya
  (pregunta del apartado cuando la posición no cuadra) y de Senegal (pregunta del domicilio y permiso v4).
- [ ] **Step 4:** Con su confirmación, copia de seguridad del bot PROD y los mismos cambios de la Task 3 en PROD
  (`IkVtek2csP5AbWxB`). Una declaración real de prueba con Ignacio.
- [ ] **Step 5: Verificar con consultas al día siguiente.**
  - Referencias creadas por cuenta, cuántas con `needs_review` y por qué motivo.
  - Incidencias `wrong_place` y sus mensajes.
  - Ningún `error` en `gps_answer_place`: revisar los `RAISE WARNING` en los logs de Postgres.
  - El informe de salud de las 08:00 sin «efectos inesperados».
- [ ] **Step 6:** Actualizar la memoria `gps-declaracion` y `CLAUDE.md` si hay algo nuevo que recordar.
