# Agente de operaciones — Fase 2 (pruebas activas con el panelista de prueba) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cada mañana, antes del informe de las 8:00, el agente usa la cuenta de Telegram del panelista de prueba de DEMO2 para recorrer cuatro procesos del bot de panelistas de PROD. Comprueba que el bot contesta lo correcto y que el dato queda en la base de datos, lo deja todo como estaba y pone el resultado en el informe.

**Architecture:**
- Un cliente de Telegram de usuario (Telethon) habla **solo** con el bot de panelistas de PROD.
- Cuatro pruebas se describen en un archivo del playbook (`playbook/pruebas.yaml`), con pasos, texto esperado y botones esperados.
- Tres funciones de Postgres preparan, consultan y borran los datos de prueba. Están fijadas a DEMO2 y al panelista PAN-DEM-004.
  - Se llaman por PostgREST con la clave pública (anon) más un token propio del agente.
  - El agente no tiene service_role.
- Las pruebas que fallan entran en el informe como problemas normales, con la huella `prueba|…`.

**Tech Stack:**
- Python 3.12, del agente existente `panelist_n8n/ops-agent`.
- Telethon ≥1.36, httpx, pydantic y pytest, que ya están.
- Postgres 17 en Supabase onems-dev (`sehbnpgzqljrsqimwyuz`).

**Spec:** `docs/superpowers/specs/2026-11-05-agente-operaciones-design.md` (§2.3, §7, §11, §13.1, §13.2, §13.9). Investigación de los flujos del bot, con los textos exactos, la SQL de reseteo y los efectos colaterales: `docs/superpowers/plans/2026-11-05-agente-operaciones-fase2-flujos-bot.md`. El plan de la fase 1 (`2026-11-05-agente-operaciones-fase1.md`) define el código existente.

## Global Constraints

- **Base de datos:**
  - BD única `onems-dev` (`sehbnpgzqljrsqimwyuz`).
  - Aplicar la migración **solo con confirmación explícita del responsable** en ese momento.
  - Nada de `db push` ni `db reset`.
- **Datos de prueba:** solo cuenta DEMO2 `f4d823d2-93e6-4755-9a89-9da87e7fa86e` y panelista PAN-DEM-004 (`ed98f175-853d-4a6b-a2fd-0c6d5641fd99`, telegram_id `7014977036`, nodo `a827d7a8-78db-4d25-8326-c38b8ff3c00a`, idioma `es`). Ninguna función toca otra cuenta.
- **Otros panelistas:** nunca escribir a otros panelistas. El cliente Telegram se niega a hablar con cualquier chat que no sea el bot configurado y que no sea un bot.
- **La cuenta de Telegram** es la del responsable, que también usa para otras monitorizaciones. El agente **no lee** otros chats: solo `get_messages` y los envíos al chat del bot. La sesión es el archivo `/var/lib/onems-ops-agent/tester.session`, con modo 0600 y dueño opsagent. Nunca se imprime ni se registra en los logs.
- **Sin IA:** sin fotos y sin texto libre. Solo botones, `/start` y etiquetas de 8 cifras escritas.
- **Limpieza:**
  - Después de cada ejecución, **siempre** se borra todo lo creado (en un `finally`), también si una prueba falla.
  - Un envío de prueba que se quedara en `sent` dispararía a los 15 días el correo de «no recibido».
- **Pausa:** en pausa («pausa»), no hay pruebas.
- **Pruebas por día:**
  - Solo la ejecución del temporizador (`run-daily`) lanza pruebas.
  - «Repetir informe» desde el bot reutiliza el resultado guardado de hoy, para no gastar ejecuciones de n8n ni tocar la sesión desde dos procesos a la vez.
  - `run-daily --dry-run` no lanza pruebas.
- **Textos:** todo lo que el agente escribe va en español llano. Formato del resumen: `Pruebas del bot: 4/4 bien.`
- **Secretos:** no se commitean. El hash del token se inserta a mano en una sesión con confirmación, nunca en el archivo de migración.
- **Repositorio panelist_n8n:** sin nombres reales de personas.
- **Guardarraíles añadidos** (aprobados por el responsable el 2026-11-05):
  - **G1:** `tester.session` queda **fuera de toda copia de seguridad**.
  - **G4:** como máximo **3 preparaciones al día**, controlado por la propia BD.
  - **G5:** **vigilante de efectos**. Tras las pruebas, la BD informa de cualquier aviso, caso o incidencia inesperada creada en DEMO2 desde la preparación, y eso es una alarma.
  - **G7:** **candado**. Nunca dos tandas de pruebas a la vez.
  - **G8:** **tope total de 300 s** para todas las pruebas.
  - **G9:** **registro de la conversación** de cada prueba (solo el chat con el bot), guardado 30 días. «detalle N» de una prueba lo muestra sin IA.
  - **G10:** al cambiar textos del bot en n8n, actualizar `playbook/pruebas.yaml`.
- **Riesgos aceptados por el responsable:**
  - Telegram podría limitar la cuenta por uso automatizado (poco volumen, unos 20 mensajes al día).
  - La limpieza corta cualquier conversación manual con el bot que esté en curso a esa hora.

## Review Focus

1. **Una prueba falla a mitad** (el bot no contesta o hay una excepción de Telethon). Hay que limpiar igual, informar «no contestó en 45 s» y seguir con las demás pruebas. Lo cubre `test_run_tests_resets_even_when_a_step_raises`.
2. **La lista de envíos tiene más filas** que la de prueba (Catorce tiene 14 atrasadas). Hay que pulsar el número de la fila cuya fecha es la de la prueba, no el «1». Lo cubre `test_press_numbered_picks_line_with_fixture_date`.
3. **Las pruebas no se ejecutan** (pausa, sin configurar, error de sesión). Los problemas `prueba|…` abiertos no se pueden marcar «resuelto». Lo cubre `test_sync_issues_keeps_prefix_open_when_not_checked`.
4. **La preparación falla** (token malo, BD caída). Ninguna prueba se ejecuta y el informe dice «No pude comprobar: pruebas del bot». Lo cubre `test_prepare_failure_skips_all_and_reports`.
5. **Peer equivocado:** el `TESTER_BOT_USERNAME` apunta a una persona o a otro bot. El cliente se niega. Lo cubre `test_conversation_refuses_non_bot_peer`.

---

## File Structure

- **ONEMS:** `supabase/migrations/20261105160000_ops_agent_test_fixtures.sql`. Contiene el esquema `ops_test` (no expuesto), el plan de prueba y tres funciones públicas.
- **panelist_n8n `ops-agent/`:**
  - `src/ops_agent/fixtures.py`: cliente HTTP de las tres funciones.
  - `src/ops_agent/bot_tests.py`: modelos y carga de `pruebas.yaml`, y el ejecutor `run_tests`.
  - `src/ops_agent/telegram_user.py`: adaptador Telethon (`TelethonConversation`) y el login.
  - Se modifican `config.py`, `store.py`, `daily.py`, `report.py`, `cli.py`, `pyproject.toml`, `README.md` y `playbook/revisiones.md`.
  - Se crea `playbook/pruebas.yaml`.
  - Tests: `tests/test_fixtures.py`, `tests/test_bot_tests.py`, `tests/test_telegram_user.py`, y se amplían `test_store.py`, `test_daily.py` y `test_report.py`.

---

### Task 1: Funciones de datos de prueba en la BD (ONEMS)

**Files:**
- Create: `supabase/migrations/20261105160000_ops_agent_test_fixtures.sql`
- Test: `supabase/tests/ops_agent_test_fixtures.sql` (script de comprobación para el Postgres local)

**Interfaces:**
- Produces:
  - `public.ops_test_prepare(p_token text) returns jsonb`. Devuelve `{"send_tag":"73915086","receive_tag":"73915087","send_date":"05/01/2026","receive_date":"05/01/2026","send_detail_id":uuid,"receive_detail_id":uuid,"prepared_at":timestamptz}`.
  - `public.ops_test_status(p_token text) returns jsonb`. Devuelve `{"send_status":text,"send_tag":text|null,"receive_status":text,"one_db":bool,"incident":bool,"unexpected":[text]}`.
  - `public.ops_test_reset(p_token text) returns jsonb`. Devuelve los conteos borrados por tabla.
  - Token incorrecto: `RAISE EXCEPTION 'ops_test: token no valido'`.

Contenido de la migración (decisiones):
- **Esquema `ops_test`.** Revoke all from public, anon y authenticated.
  - `ops_test.secret(token_sha256 text not null)`: una fila; se inserta a mano.
  - `ops_test.state(id int primary key default 1 check (id=1), prepared_at timestamptz)`.
- **Plan de prueba de DEMO2** (`allocation_plans`): `plan_name = 'OPS-AGENT pruebas automáticas (no tocar)'`, con `carrier_id` y `product_id` tomados de un plan existente de DEMO2 cuyo producto **no** sea POBOX. Si no hay ninguno, la migración falla con un mensaje claro. `total_samples 0`, fechas `2026-01-05`. `status` = un valor permitido distinto de `'active'` si el CHECK lo admite; si no, `'active'`. Se guarda su id en `ops_test.state` (añadir la columna `plan_id`).
- **Funciones comunes.** Todas `SECURITY DEFINER`, `SET search_path = ''`, `REVOKE ALL ... FROM public, authenticated` y `GRANT EXECUTE ... TO anon`. Comprueban `encode(extensions.digest(p_token,'sha256'),'hex')` contra `ops_test.secret` (verificar que pgcrypto está en `extensions`; si no, usar `sha256(convert_to(p_token,'UTF8'))`).
- **`ops_test_prepare`:**
  1. Llama a la lógica de reset (función interna `ops_test._reset()`).
  2. Comprueba que las etiquetas `73915086` y `73915087` no existen en ninguna fila de DEMO2.
  3. Inserta dos filas en `allocation_plan_details` del plan de prueba, ambas con `fecha_programada = '2026-01-05'` (lunes; queda la primera por fecha ASC) y `generation_source = 'plan'`:
     - **Envío:** origen = nodo de PAN-DEM-004, destino = nodo de PAN-DEM-003 (`2940e6ff-f666-4cb2-8780-ffb464bce544`), `status 'pending'`.
     - **Recepción:** origen = nodo de PAN-DEM-003, destino = nodo de PAN-DEM-004, `status 'sent'`, `tag_id = idtag = '73915087'`, `sent_at = sent_date = now() - interval '1 day'`, `origin_panelist_id` y `destination_panelist_id` con sus panelistas.
  4. Las columnas NOT NULL `week_number`, `month` y `year` las rellena el trigger `set_allocation_detail_week_fields`; si no lo hace, se calculan.
  5. Guarda `prepared_at = now()`.
- **`ops_test._reset()`.** Solo actúa sobre: filas del plan de prueba; datos de PAN-DEM-004 creados desde `prepared_at`; y `panelist_context` de `telegram_id='7014977036'`. Borra en este orden:
  1. `one_db` de las filas del plan de prueba (la FK es SET NULL, hay que borrarlas a mano);
  2. `receipt_case` de esas filas o de ese `telegram_id` desde `prepared_at`;
  3. `incident_message` y luego `panelist_incident` de PAN-DEM-004 con `category='parcel_damaged'` y `created_via='telegram'` desde `prepared_at`;
  4. `panelist_notification` de PAN-DEM-004 desde `prepared_at`;
  5. todas las filas `panelist_context` de ese `telegram_id`;
  6. las filas `allocation_plan_details` del plan de prueba.

  Si `prepared_at` es null, no borra lo que va «desde prepared_at». Pone `prepared_at = null`.
- **`ops_test_status`.** Solo lectura sobre las dos filas, `one_db` por `allocation_detail_id` y `panelist_incident` como arriba.
  - **G5:** `unexpected` es una lista de frases en español, vacía si todo va bien. Cuenta lo creado en DEMO2 desde `prepared_at`: `panelist_notification` de cualquier panelista, `receipt_case`, `panelist_incident` distintas de la esperada, `incident_message` cuyo `meta` no lleve `report_flow`, y `material_shipments`. Ejemplo: `"2 avisos a panelistas (panelist_notification)"`.
- **G4:** `ops_test.state` lleva también `prep_day date` y `prep_count int`. `ops_test_prepare` lanza `ops_test: tope diario de 3 preparaciones` si ese día ya hubo 3 (fecha en `Europe/Madrid`).

- [ ] **Step 1: Escribir el script de comprobación** `supabase/tests/ops_agent_test_fixtures.sql`. Sobre el baseline más la migración en el Postgres local:
  - inserta un hash de un token conocido;
  - `prepare` devuelve las dos etiquetas;
  - existen 2 filas;
  - simula la recepción (`update ... set status='received'`) y comprueba que el trigger crea `one_db`;
  - `status` dice `one_db=true`;
  - `reset` deja 0 filas del plan y 0 `one_db`;
  - un `panelist_notification` insertado a mano en DEMO2 aparece en `unexpected`;
  - la 4.ª preparación del día lanza el error de tope;
  - un token malo lanza `ops_test: token no valido`;
  - el rol `authenticated` no tiene EXECUTE (`has_function_privilege`);
  - ninguna fila de otra cuenta cambia: compara un `md5(string_agg(...))` de `allocation_plan_details` fuera del plan, antes y después.
- [ ] **Step 2: Ejecutarlo** con `supabase/tests/replay_baseline.ps1` sin la migración. Expected: FALLA porque `ops_test_prepare` no existe.
- [ ] **Step 3: Escribir la migración** según las decisiones de arriba.
- [ ] **Step 4: Ejecutarlo de nuevo** con la migración. Expected: todas las comprobaciones dicen OK.
  - Si el Postgres local no tiene datos de DEMO2, el script siembra antes una cuenta, nodos, panelistas y un plan mínimos con esos mismos ids.
- [ ] **Step 5: Commit** en ONEMS `develop`: `feat(ops-agent): funciones de datos de prueba de DEMO2 para el agente`.
- [ ] **Step 6 (PARADA — confirmación del responsable):**
  1. Ensayo en vivo con la técnica `RAISE EXCEPTION 'ENSAYO'`: migración más prepare/status/reset dentro de una transacción que se deshace.
  2. Aplicar la migración en onems-dev (`sehbnpgzqljrsqimwyuz`) por la Management API, con confirmación explícita.
  3. Generar el token: 32 bytes aleatorios en el servidor, guardados en `/etc/onems-ops-agent/env`.
  4. Insertar solo su hash con una sentencia aparte, también confirmada.

### Task 2: Cliente de las funciones de prueba

**Files:**
- Create: `ops-agent/src/ops_agent/fixtures.py`
- Test: `ops-agent/tests/test_fixtures.py`

**Interfaces:**
- Produces:
  - `class FixtureError(Exception)`.
  - `@dataclass Fixture(send_tag: str, receive_tag: str, send_date: str, receive_date: str)`.
  - `@dataclass FixtureStatus(send_status: str, send_tag: str | None, receive_status: str, one_db: bool, incident: bool, unexpected: list[str])`.
  - `class FixtureClient(base_url: str, anon_key: str, token: str, transport: httpx.BaseTransport | None = None)` con `prepare() -> Fixture`, `status() -> FixtureStatus` y `reset() -> dict[str, int]`.
  - Llama `POST {base_url}/rest/v1/rpc/ops_test_<name>` con cabeceras `apikey` y `Authorization: Bearer <anon_key>` y cuerpo `{"p_token": token}`.

- [ ] **Step 1: Tests** con `httpx.MockTransport`:
  - `test_prepare_posts_token_and_parses_fixture`: comprueba la URL `/rest/v1/rpc/ops_test_prepare`, el cuerpo `{"p_token":"t"}` y que `Fixture.send_tag == "73915086"`.
  - `test_status_parses`.
  - `test_reset_returns_counts`.
  - `test_http_error_raises_fixture_error_without_token_in_message`: si llega un 400 con un cuerpo que contiene el token, el mensaje de `FixtureError` no contiene `"t0ken-secreto"`.
  - `test_non_json_raises_fixture_error`.
- [ ] **Step 2:** `uv run pytest tests/test_fixtures.py -q`. Expected: FAIL (ImportError).
- [ ] **Step 3: Implementar.** Timeout de 30 s; el mensaje de error dice solo `ops_test_<name> devolvio <código>`.
- [ ] **Step 4:** `uv run pytest -q`. Expected: todo PASS.
- [ ] **Step 5: Commit** `feat(ops-agent): cliente de datos de prueba`.

### Task 3: Definición y ejecutor de las pruebas

**Files:**
- Create: `ops-agent/playbook/pruebas.yaml`, `ops-agent/src/ops_agent/bot_tests.py`
- Test: `ops-agent/tests/test_bot_tests.py`

**Interfaces:**
- Consumes: `Fixture`, `FixtureStatus`, `FixtureClient`, `FixtureError` (Task 2).
- Produces:
  - `class Conversation(Protocol)`, con dos métodos:
    - `async send_text(text: str) -> None`;
    - `async press(callback_data: str) -> None`: pulsa el botón con ese dato en el **último** mensaje del bot que lo tenga; si ninguno lo tiene, `StepError("no encontré el botón …")`.
    - Y además `async wait_reply(expect: list[str], buttons: list[str], timeout_s: float) -> BotMessage`: espera mensajes nuevos del bot hasta que uno contenga todos los `expect` y todos los `buttons`. Si no llega a tiempo, `StepError` con el último texto recibido.
  - `@dataclass BotMessage(id: int, text: str, buttons: list[str])`, donde `buttons` son los callback_data.
  - `class StepError(Exception)`.
  - `@dataclass Step(action: Literal["type","press","press_numbered"], value: str, expect: list[str], buttons: list[str] = [])`.
  - `@dataclass TestDef(name: str, title: str, steps: list[Step], check: Literal["send","receive","incident","none"])`.
  - `load_tests(path: Path) -> list[TestDef]`.
  - `@dataclass TranscriptLine(who: Literal["agente","bot"], text: str, buttons: list[str])`.
  - `@dataclass TestResult(name: str, title: str, ok: bool, step: int | None, problem: str | None, transcript: list[TranscriptLine])` (G9).
  - `@dataclass TestRun(ran: bool, results: list[TestResult], skipped_reason: str | None, cleanup_ok: bool, unexpected: list[str])`.
  - `async run_tests(defs: list[TestDef], conv: Conversation, fixtures: FixtureClient, timeout_s: float = 45, budget_s: float = 300, clock=time.monotonic) -> TestRun`.

`pruebas.yaml`:
- Lleva un comentario en español arriba que explica el formato.
- Los marcadores `{send_tag}`, `{receive_tag}`, `{send_date}` y `{receive_date}` se sustituyen con el `Fixture`.
- Cada prueba empieza con `type "/start"` y `expect ["¿qué necesitas?"]`, más los botones del menú que use.
- Las cuatro pruebas, en este orden:
  1. **`lista_recibir`**, «Ver paquetes a recibir»: pulsar `show_pending_receive`; esperar «Paquetes que vas a recibir» y «{receive_date}», con el botón `start_receipt`. `check: none`.
  2. **`envio`**, «Declarar un envío»:
     - pulsar `show_pending_parcels` y esperar «Tus envíos pendientes»;
     - `press_numbered` con el valor `{send_date}`, esperando «Has seleccionado este envío» y los botones `upload_photo_label` y `report_incident`;
     - escribir `{send_tag}` y esperar «registrado como enviado» y «{send_tag}».
     - `check: send`.
  3. **`recepcion`**, «Declarar una recepción»: pulsar `start_receipt` y esperar «Modo recepción»; escribir `{receive_tag}` y esperar «Paquete recibido» y «{receive_tag}». `check: receive`.
  4. **`incidencia`**, «Reportar una incidencia»: pulsar `report_incident` y esperar «¿Qué ha pasado?» con el botón `inc_cat:parcel_damaged`; pulsar `inc_cat:parcel_damaged` y esperar «Registrado, gracias por avisar». `check: incident`.

`press_numbered`:
- Busca, en el último mensaje del bot, la línea de envío que contiene el valor (la fecha). El formato es `<b>N. Destinatario …</b>` seguido de una línea con la fecha.
- Toma su número N y pulsa el botón con callback_data `N`.
- Si no la encuentra en la primera página, pulsa `show_more_parcels:<offset>` mientras exista, como máximo 5 páginas.

Comprobación en la BD tras cada prueba, con `fixtures.status()`:
- `send`: `send_status=='sent' and send_tag=='73915086'`.
- `receive`: `receive_status=='received' and one_db`.
- `incident`: `incident`.
- Si falla, el problema es «el bot contestó bien pero no quedó registrado en la base de datos (…)».

`run_tests`:
- `prepare()`. Si da `FixtureError`, devuelve `TestRun(ran=False, skipped_reason="no pude preparar los datos de prueba", cleanup_ok=True)` y no habla con Telegram.
- Ejecuta cada prueba. Un `StepError` o cualquier excepción en una prueba la marca como fallida con su número de paso, y se sigue con la siguiente.
- **G8:** si se agota `budget_s`, las pruebas restantes quedan fallidas con «no dio tiempo (tope de 5 min)».
- **G9:** cada acción del agente y cada `BotMessage` recibido se añaden al `transcript` de su prueba.
- **G5:** tras la última prueba y antes del reset, `unexpected = fixtures.status().unexpected`.
- En `finally`, `reset()`. Si falla, `cleanup_ok=False`.

- [ ] **Step 1: Tests** con un `FakeConversation` guionizado (una lista de respuestas por acción) y un `FakeFixtures`:
  - `test_load_tests_reads_four_tests_in_order`: los nombres son `["lista_recibir","envio","recepcion","incidencia"]`.
  - `test_placeholders_are_filled_from_fixture`.
  - `test_all_ok_gives_four_ok_and_resets_once`.
  - `test_press_numbered_picks_line_with_fixture_date`: con una lista de 3 envíos y la fecha de prueba en el 3.º, se pulsa `"3"`.
  - `test_press_numbered_follows_show_more`.
  - `test_timeout_marks_failed_with_step_and_continues`: el problema contiene «no contestó» y las otras 3 pruebas se ejecutan.
  - `test_db_check_failure_marks_failed`.
  - `test_run_tests_resets_even_when_a_step_raises`: una `RuntimeError` en `press` lleva a `reset` llamado y `cleanup_ok` True.
  - `test_prepare_failure_skips_all_and_reports`: la conversación no recibe ninguna llamada.
  - `test_reset_failure_sets_cleanup_false`.
  - `test_budget_exhausted_marks_remaining_failed` (con un reloj falso).
  - `test_transcript_records_both_sides`.
  - `test_unexpected_effects_are_collected_before_reset`.
- [ ] **Step 2:** `uv run pytest tests/test_bot_tests.py -q`. Expected: FAIL.
- [ ] **Step 3: Implementar** `bot_tests.py` y `pruebas.yaml`. El texto del problema va en español llano, por ejemplo `paso 3: esperaba «registrado como enviado», llegó «⚠️ La etiqueta…»` (recortado a 200 caracteres).
- [ ] **Step 4:** `uv run pytest -q`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(ops-agent): pruebas del bot descritas en el playbook y su ejecutor`.

### Task 4: Adaptador Telethon y login

**Files:**
- Create: `ops-agent/src/ops_agent/telegram_user.py`
- Modify: `ops-agent/pyproject.toml` (añadir `telethon>=1.36`)
- Test: `ops-agent/tests/test_telegram_user.py`

**Interfaces:**
- Consumes: `Conversation`, `BotMessage`, `StepError` (Task 3).
- Produces:
  - `class TelethonConversation(Conversation)`, con `__init__(client, bot_username: str)` y `async open() -> None`:
    - resuelve la entidad;
    - si no es `User` con `.bot == True`, lanza `StepError("el chat configurado no es un bot")`;
    - guarda `last_id` = el último mensaje existente.
  - `async open_tester(session_path: Path, api_id: int, api_hash: str, bot_username: str) -> AsyncContextManager[TelethonConversation]`. Conecta sin pedir login: si `not await client.is_user_authorized()`, lanza `StepError("la cuenta de prueba no está conectada; ejecuta ops-agent tester-login")`.
  - `def login_interactive(session_path: Path, api_id: int, api_hash: str) -> None`. Hace `client.start()` interactivo (teléfono, código y, si hay, contraseña en dos pasos) y deja el archivo con `os.chmod(path, 0o600)`.
  - **G7:** `@contextmanager tester_lock(path: Path)`. Es un candado no bloqueante sobre `path`: `fcntl.flock` en Linux y `msvcrt.locking` en Windows, para los tests. Si está ocupado, lanza `StepError("ya había otra tanda de pruebas en marcha")`.

Decisiones:
- `wait_reply` sondea `client.get_messages(bot, min_id=last_id, limit=20)` cada 1 s.
  - Considera solo los mensajes que no son `out`.
  - Toma texto `message.message` y callback_data de `message.buttons`, decodificado en utf-8.
  - Actualiza `last_id`.
  - Si el bot **edita** un mensaje en vez de mandar uno nuevo, también lo acepta: relee el último mensaje del bot.
- `press` usa `message.click(data=callback_data.encode())`.
- No se registra nunca el contenido de otros chats; el adaptador no se suscribe a eventos.

- [ ] **Step 1: Tests** con un cliente falso (objetos con `get_entity`, `get_messages` y `send_message`):
  - `test_conversation_refuses_non_bot_peer`.
  - `test_wait_reply_ignores_outgoing_and_old_messages`.
  - `test_wait_reply_matches_buttons_by_callback_data`.
  - `test_press_without_button_raises_step_error`.
  - `test_only_bot_peer_is_ever_used`: todas las llamadas del cliente falso reciben la entidad del bot.
  - `test_tester_lock_second_holder_raises`.
- [ ] **Step 2:** ejecutar. Expected: FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4:** `uv run pytest -q`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(ops-agent): cliente de Telegram de la cuenta de prueba`.

### Task 5: Integración en el informe diario

**Files:**
- Modify: `config.py`, `store.py`, `daily.py`, `report.py` y `cli.py` en `ops-agent/src/ops_agent/`; `ops-agent/playbook/revisiones.md`; `ops-agent/README.md`.
- Test: amplía `tests/test_store.py`, `tests/test_daily.py`, `tests/test_report.py` y `tests/test_config.py`.

**Interfaces:**
- Consumes: `TestRun`, `TestResult`, `run_tests`, `load_tests` (Task 3); `open_tester`, `login_interactive` (Task 4); `FixtureClient` (Task 2).
- Produces:
  - **`Settings`:** campos opcionales `tester_api_id: int | None`, `tester_api_hash: SecretStr | None`, `tester_bot_username: str | None`, `supabase_url: str | None`, `supabase_anon_key: SecretStr | None` y `ops_test_token: SecretStr | None`, leídos de las variables de entorno `TESTER_API_ID`, `TESTER_API_HASH`, `TESTER_BOT_USERNAME`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `OPS_TEST_TOKEN`. Además, la propiedad `tests_configured: bool`, que es True si todos están presentes.
  - **`Store.sync_issues(..., keep_open_prefixes: tuple[str, ...] = ())`:** los problemas abiertos cuya huella empieza por uno de esos prefijos no se resuelven en esta ejecución.
  - **`Store.save_test_run(day: date, run: TestRun)` y `Store.get_test_run(day: date) -> TestRun | None`.** Tabla nueva `test_runs(day TEXT PRIMARY KEY, json TEXT)`, creada en el esquema existente.
  - **`run_daily(..., tester: Callable[[], Awaitable[TestRun]] | None = None)`:**
    - Si hay `tester`, no hay pausa y no hay un resultado guardado hoy, ejecuta `tester()` **antes** de `collect_facts` y lo guarda.
    - Si no, usa `store.get_test_run(today)`.
    - Las pruebas fallidas se convierten en `Failure(fingerprint=f"prueba|{name}", workflow_name=f"Prueba: {title}", env="PROD", node=f"paso {step}", message=problem, count=1, first_at=now, last_at=now, sample_execution_id="")` y se añaden a `facts.failures`. Si `cleanup_ok` es False, también `Failure(fingerprint="prueba|limpieza", workflow_name="Prueba: limpieza de datos", node="reset", message="no pude borrar los datos de prueba de DEMO2; hay que borrarlos en una sesión con Claude")`.
    - **G5:** si `unexpected` no está vacío, `Failure(fingerprint="prueba|efectos", workflow_name="Prueba: efectos inesperados", node="después de las pruebas", message="las pruebas crearon algo que no debían: " + "; ".join(unexpected))`.
    - Se salta el diagnóstico IA de las huellas `prueba|`.
  - **G9:** `Store.save_test_run` guarda también las conversaciones y borra las de más de 30 días. Para huellas `prueba|<name>`, `detail.explain_detail` devuelve sin IA el problema y la conversación de ese día, en formato `🤖 agente: …` / `💬 bot: …` y recortada a `MAX_REPLY`.
    - Si las pruebas no se ejecutaron, se pasa `keep_open_prefixes=("prueba|",)`.
  - **`render_report(..., tests: TestRun | None = None)`.** Línea de resumen debajo de «Bot: …»:
    - `Pruebas del bot: {ok}/{n} bien.`;
    - `Pruebas del bot: no hechas (en pausa).`;
    - `Pruebas del bot: no hechas ({skipped_reason}).`;
    - nada si las pruebas no están configuradas.
    - Si no se ejecutaron por un error, se añade «pruebas del bot» a «No pude comprobar».
  - **`cli.py`:**
    - `cmd_run_daily`, sin `--dry-run` y con `settings.tests_configured`, pasa un `tester` que, dentro de `tester_lock(db_path.parent/"tester.lock")` (G7), abre `open_tester(db_path.parent/"tester.session", …)` y llama a `run_tests(load_tests(playbook/pruebas.yaml), conv, FixtureClient(...))`. Un error al abrir lleva a `TestRun(ran=False, skipped_reason=<mensaje>)`.
    - `cmd_bot` no pasa tester.
    - Subcomando nuevo `tester-login` que llama a `login_interactive`.

- [ ] **Step 1: Tests:**
  - `test_sync_issues_keeps_prefix_open_when_not_checked`.
  - `test_test_run_roundtrip`.
  - `test_run_daily_runs_tester_before_collect_and_stores_it`.
  - `test_run_daily_reuses_stored_run_when_already_ran_today`: el tester no se llama.
  - `test_run_daily_skips_tester_when_paused`.
  - `test_failed_test_becomes_issue_without_diagnosis`: la IA no se llama.
  - `test_cleanup_failure_becomes_issue`.
  - `test_report_shows_tests_summary_line`: `"Pruebas del bot: 3/4 bien."`.
  - `test_report_says_not_done_when_paused`.
  - `test_settings_tests_configured_requires_all_six`.
  - `test_dry_run_never_builds_tester`.
  - `test_unexpected_effects_become_alarm_issue`.
  - `test_detail_of_test_issue_shows_transcript_without_llm`.
  - `test_transcripts_older_than_30_days_are_purged`.
- [ ] **Step 2:** ejecutar. Expected: FAIL.
- [ ] **Step 3: Implementar.**
  - En `revisiones.md`, reescribir «Fase 2» como una sección «Pruebas del bot (fase 2)» en lenguaje llano. Incluir la regla G10: «si cambias un texto del bot en n8n, cambia también lo esperado en `pruebas.yaml`».
  - En el README, añadir la instalación: variables de entorno, `sudo -u opsagent … ops-agent tester-login`, modo 0600 y cómo desactivarlo (borrar `TESTER_API_ID`).
- [ ] **Step 4:** `uv run pytest -q`. Expected: todo PASS (83 + los nuevos).
- [ ] **Step 5:** `uv run ops-agent run-daily --dry-run` contra Cloud. Expected: el informe sale sin la línea de pruebas y sin errores.
- [ ] **Step 6: Commit** `feat(ops-agent): pruebas del bot en el informe diario`.

### Task 6: Puesta en marcha en el servidor (con el responsable)

Este bloque no es código. Lo ejecuta Claude en sesión, con el responsable presente:

1. **Rama y PR.** Rama `feat/ops-agent-fase2` en panelist_n8n. El responsable hace el push y el merge.
2. **Clave de Telegram.** El responsable saca `api_id` y `api_hash` en my.telegram.org con el móvil de la cuenta de prueba y los pega en `/etc/onems-ops-agent/env`. Hay que comprobar con `wc -l` y `grep -c` que cada clave está en su línea: la trampa conocida de nano.
3. **Resto del env.** Se añaden `TESTER_BOT_USERNAME` (comprobar el nombre real del bot PROD con el responsable), `SUPABASE_URL`, `SUPABASE_ANON_KEY` (la pública del frontend) y `OPS_TEST_TOKEN`.
4. **Token y migración.** Task 1, step 6, con confirmación.
5. **Instalar.** Actualizar el código en `/opt/onems-ops-agent` y el venv.
   - **G1:** localizar la copia de seguridad del agente (la que guarda `/var/lib/onems-ops-agent`), excluir `tester.session` y `tester.lock`, y comprobar en la siguiente copia que no están.
   - El responsable activa la verificación en dos pasos de la cuenta de Telegram, si no la tiene, y sabe cerrar la sesión «ops-agent» en Ajustes → Dispositivos.
6. **Login.** `sudo -u opsagent ... ops-agent tester-login`. El responsable escribe el código que le llega a Telegram. Comprobar que `tester.session` tiene modo 600.
7. **Primera ejecución a mano.** `sudo systemctl start onems-ops-agent-report.service`. Comprobar:
   - que llega el informe con `Pruebas del bot: 4/4 bien.`;
   - que en la BD quedan 0 filas en el plan de prueba;
   - que no se creó ningún `panelist_notification` ni correo.
8. **Notas.** Actualizar la memoria `agente-operaciones.md`.

Consumo estimado: unas 20 ejecuciones de n8n por día (4 `/start` y 9 pasos, más subflujos), unas 600 al mes de las 10.000.
