# Agente de operaciones: análisis de casos — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** El gestor pide el análisis de un caso (por Telegram o con un botón en ONEMS). El agente devuelve el análisis y un mensaje redactado para cada panelista implicado. Cada mensaje sale por el bot de panelistas solo cuando el gestor lo aprueba, y todo queda en la conversación de la incidencia.

**Architecture:** La base de datos tiene funciones `ops_case_*`: leen el caso en una sola llamada, llevan una cola de peticiones desde ONEMS y escriben mensajes y notas. Están protegidas con el mismo token que `ops_test`/`ops_report`, usan la clave pública y nunca service_role. El agente del servidor Hetzner (proceso `ops-agent bot`) hace tres cosas: recoge lo que el gestor reenvía, consulta la cola cada 15 s y analiza. Los cálculos (días de retraso, SLA) los hace el código. La IA solo explica y redacta. Los mensajes reutilizan el canal de los managers: `incident_message` outbound/pending_send → disparador → n8n «Deliver incident messages». Los casos de recepción pasan a tener conversación (`incident_kind='receipt'`).

**Tech Stack:**
- Postgres 17 (Supabase onems-dev) con plpgsql.
- Python 3.12: python-telegram-bot, anthropic, httpx, pydantic, pytest.
- React 18 + TypeScript + Vite, con traducciones CSV en `public/locales/*.csv`.
- n8n Cloud, con los flujos [DEV] primero.

**Spec:** `docs/superpowers/specs/2026-11-10-agente-analisis-de-casos-design.md` (ONEMS). Amplía `2026-11-05-agente-operaciones-design.md`.

**Repos y ramas:**
- ONEMS: rama `feat/analisis-casos` desde `develop`. Contiene las migraciones, los tests SQL y el frontend.
- panelist_n8n: rama `feat/ops-agent-analisis-casos` desde `feat/ops-agent-informe-operacion`. Se parte de esa rama porque es la que corre en el servidor y aún no está en `main`. Contiene `ops-agent/` y `workflows/`.

## Global Constraints

- Base: **onems-dev `sehbnpgzqljrsqimwyuz`** (es también producción). Ninguna migración se aplica sin nombrar proyecto + ref y recibir confirmación explícita. Antes se valida en el Postgres local 5433 con `bash supabase/tests/run_tests.sh <test>`.
- Migraciones forward-only, con timestamp posterior a `20261109180100`: `20261110120000_incident_message_receipt_kind.sql` y `20261110121000_ops_case_analysis.sql`.
- El agente nunca usa service_role. Usa la clave pública + `OPS_TEST_TOKEN`, comprobado con `ops_test._check(p_token)`. Toda función `ops_case_*` es `SECURITY DEFINER SET search_path = ''`. Se revoca a PUBLIC/anon/authenticated y se concede EXECUTE solo a `anon`.
- Ninguna consulta mezcla cuentas. Cada función deriva la cuenta del panelista o de la incidencia, y rechaza con `ops_case: otra cuenta` cualquier id de otra cuenta.
- Ningún mensaje a un panelista sale sin pulsar Enviar.
- Mientras dure la prueba, `playbook/config.yaml` lleva `case.send_accounts: ["DEMO2"]`. El código se niega a enviar a cuentas fuera de esa lista. Solo Ignacio la amplía (a `["*"]`), por git.
- Modelos (en `playbook/config.yaml`):
  - `models.case_analysis: claude-sonnet-5-5`, para el análisis y los borradores.
  - `models.case_hints: claude-haiku-5-5`, para sacar nombres y etiquetas de las capturas.
  - `models.case_redraft: claude-haiku-5-5`, para el botón «Cambiar».
  - Se respeta `monthly_cap_eur`.
- Lo que va a la IA pasa antes por `masking.mask`, que tapa claves y teléfonos. Nombres y etiquetas van reales.
- Textos de la pantalla: en los 5 CSV `public/locales/{en,es,fr,ar,pt}.csv`, nunca escritos a mano en el `.tsx`. El árabe va con `dir="rtl"`.
- Idioma de cada mensaje: `panelists.language`; si falta, el de la cuenta (`accounts.default_language`); si falta, `en`.
- Mensaje al panelista: conciso, agradece siempre su actividad e implicación, explica qué pasó en 1–2 frases, dice qué hacer ahora si toca, da un consejo si el error fue suyo, nunca culpabiliza. Máximo 900 caracteres.
- Las causas siempre van marcadas como probables y con su prueba. Si no hay mejora que proponer, `improvement = null`: nunca se inventa una.
- Lo que el agente guarda de un caso se borra a los 30 días.
- Calidad:
  - Agente: `uv run pytest` en verde y `uv run ruff check`.
  - Frontend: `npm run lint` (0 avisos) y `npm run build`.
  - n8n: [DEV] antes que PROD.
- Pruebas solo con DEMO2 o con datos simulados. Durante las pruebas no se escribe a ningún panelista real.

## Review Focus

1. **Doble pulsación de Enviar**, en Telegram o en ONEMS, o un reintento tras un corte de red. Se espera un solo mensaje. Lo cubren `draft_key` único en BD (Task 3) y `mark_draft_sent` atómico en el agente (Task 7).
2. **Nombre ambiguo**: dos panelistas que coinciden con «Samwel», o el mismo nombre en dos cuentas. El agente nunca elige solo: pregunta con botones. Lo cubren Task 2 (`ops_case_find_panelists`) y Task 8 (`test_ambiguous_name_asks`).
3. **Sin norma de entrega**: la etiqueta no está en el plan, o no hay norma para ese producto y par de ciudades. El análisis dice «sin SLA en la configuración» y no se inventa uno. Lo cubre Task 5 (`test_no_standard_gives_none`).
4. **La IA redacta un mensaje para alguien que no está en el caso** (otra cuenta, un id inventado). El borrador se descarta. Lo cubre Task 6 (`test_foreign_draft_dropped`).
5. **El agente está caído** cuando se pulsa «Analizar caso» en ONEMS. A los 10 minutos la petición sale como «el agente no responde», no gira para siempre. Lo cubren Task 3 (`request_case_analysis` caduca) y Task 12.

---

### Task 1: Conversación en los casos de recepción y mensajes a otro panelista (ONEMS, BD)

**Files:**
- Create: `supabase/migrations/20261110120000_incident_message_receipt_kind.sql`
- Test: `supabase/tests/incident_message_receipt_kind.test.sql` (mismo estilo y fixture que `receipt_manager_rpcs.test.sql`)

**Interfaces:**
- Produces:
  - `incident_message.incident_kind` admite `'receipt'` (el `incident_id` es `receipt_case.id`).
  - `public.log_incident_message(p_incident_kind text, p_incident_id uuid, p_direction text, p_author text, p_body text, p_meta jsonb DEFAULT '{}', p_status text DEFAULT NULL, p_panelist_id uuid DEFAULT NULL) RETURNS uuid`. Sustituye a la de 7 argumentos: se borra con DROP y se vuelve a conceder a service_role. Si llega `p_panelist_id`, ese panelista debe ser de la misma cuenta que la incidencia y es el que se guarda.
  - `public.send_case_message(p_incident_kind text, p_incident_id uuid, p_panelist_id uuid, p_body text, p_draft_key text DEFAULT NULL) RETURNS uuid`, para `authenticated`. Hace lo mismo que `send_manager_message`, pero con destinatario explícito. Guarda `meta = {manager_user_id: auth.uid(), case_draft_key: p_draft_key}`.
  - `public.mark_incident_conversation_read` admite `'receipt'`.
  - Helper interno `public.incident_owner(p_kind text, p_id uuid) RETURNS TABLE(account_id uuid, panelist_id uuid)`, con las ramas reported, unavailability y receipt. Solo lo pueden ejecutar service_role y las funciones definer. Lo usan las tres funciones anteriores.
  - Índice único parcial `incident_message_case_draft_key_uq` sobre `((meta->>'case_draft_key'))` `WHERE meta ? 'case_draft_key' AND meta->>'case_draft_key' IS NOT NULL`.

- [ ] **Step 1: Write the failing test** con estos casos:
  - `log_incident_message('receipt', <case>, 'inbound', 'panelist', 'hola')` guarda `panelist_id` = el del caso.
  - Con `p_panelist_id` = otro panelista de la misma cuenta, guarda ese.
  - Con un panelista de la cuenta 2 → `Cross-tenant`.
  - El usuario 99 (admin de la cuenta 1) llama `send_case_message('receipt', <case>, <P1>, 'x', 'k1')` y se crea una fila outbound/manager/pending_send con `panelist_id=P1`.
  - Si repite con la misma clave `'k1'`, salta la violación de unicidad.
  - El usuario 98 (cuenta 2) recibe `Cross-tenant`.
  - Un panelista sin telegram da `panelist has no telegram`.
  - `mark_incident_conversation_read('receipt', <case>)` funciona.
- [ ] **Step 2:** `bash supabase/tests/run_tests.sh incident_message_receipt_kind`. Debe FALLAR (falta `'receipt'` en el CHECK).
- [ ] **Step 3: Write the migration.**
  - Cambiar el CHECK `incident_message_incident_kind_check` a `('reported','unavailability','receipt')`.
  - Crear el helper y las 3 funciones de Interfaces.
  - Revocar a PUBLIC/anon/authenticated y conceder: `log_incident_message` a service_role; `send_case_message` a authenticated.
  - Copiar el cuerpo actual de `mark_incident_conversation_read` desde `20261022100000_incident_conversation_unread.sql` y añadir la rama receipt.
- [ ] **Step 4:** volver a lanzar el test. Debe dar PASS, y también `bash supabase/tests/run_tests.sh` completo (los tests anteriores siguen en verde).
- [ ] **Step 5: Commit** `feat(incidents): los casos de recepción tienen conversación y se puede escribir a otro panelista del caso`.

### Task 2: Lectura del caso para el agente (ONEMS, BD)

**Files:**
- Create: `supabase/migrations/20261110121000_ops_case_analysis.sql` (primera parte; Task 3 añade el resto)
- Test: `supabase/tests/ops_case_analysis.test.sql`

**Interfaces:**
- Consumes: `ops_test._check(text)`, `public.normalize_tag(text)`, `public.incident_owner` (Task 1).
- Produces:
  - `public.ops_case_find_panelists(p_token text, p_name text, p_tag text) RETURNS jsonb`. Devuelve un array (máx. 10) de `{panelist_id, code, name, account, city, by_name bool, by_tag bool}`.
    - `by_name`: cada palabra de `p_name` (≥2 letras) aparece en `lower(name)`.
    - `by_tag`: el panelista es origen o destino de un `allocation_plan_details` con `normalize_tag(tag_id) = normalize_tag(p_tag)`, o tiene un `receipt_case` con `tag_norm` igual.
    - Solo panelistas `active`. Orden: ambos > solo nombre > solo etiqueta.
  - `public.ops_case_data(p_token text, p_panelist_id uuid, p_tag text, p_incident_kind text DEFAULT NULL, p_incident_id uuid DEFAULT NULL) RETURNS jsonb`. La cuenta sale del panelista. Si se pasa una incidencia, debe ser de la misma cuenta (si no, `ops_case: otra cuenta`). Claves exactas:
    - `account {name, language, timezone}`
    - `panelist {id, code, name, language, city, node, has_telegram}`
    - `details[]`: las líneas del plan con esa etiqueta. Cada una: `{id, tag, status, scheduled, sent_at, received_at, origin{panelist_id, code, name, language, city, node}, destination{…igual}, carrier, product, product_code, standards[{standard_time, time_unit, success_percentage}]}`. Las `standards` salen de `delivery_standards` con el carrier y el producto de `allocation_plans`, y las ciudades de los nodos de origen y destino.
    - `siblings[]`: otras líneas del mismo nodo de origen y el mismo mes de `fecha_programada`. Cada una: `{tag, scheduled, sent_at, received_at, status, destination_code, destination_name}`. Máximo 30.
    - `receipt_cases[]`: los de esa etiqueta, o los del panelista en los últimos 30 días. Cada uno: `{id, tag_raw, tag_norm, reason, status, attempts, first_attempt_at, last_attempt_at, panelist_code, culprit_role}`.
    - `incidents[]`: `panelist_incident` de los implicados en los últimos 30 días. Cada uno: `{id, panelist_code, category, status, reported_at, description}`.
    - `unavailability[]`: bajas activas de los implicados que tocan el intervalo de hoy ±30 días. Cada una: `{id, panelist_code, start_date, end_date, reason, review_status}`.
    - `messages[]`: los últimos 20 `incident_message` de los implicados. Cada uno: `{incident_kind, incident_id, panelist_code, direction, author, body, created_at}`.
    - `anchor {kind, id} | null`. Si se pasó una incidencia, es esa. Si no, se busca por este orden: el `receipt_case` abierto (`pending` o `needs_decision`) del panelista con esa etiqueta; después, el `panelist_incident` abierto ligado a la línea; si no hay ninguno, null.
    - «Implicados» = el panelista + los panelistas de origen y destino de `details`.

- [ ] **Step 1: Write the failing test** con un fixture que reproduce el caso de referencia: Arbe (N1/C1) → James (N2/C2), con la etiqueta `00011844` programada el 27/10 y enviada el 30/10, más 3 hermanas para Samwel (N3/C3). Samwel tiene un `receipt_case other_city_tag needs_decision` y una baja del 09 al 16/11. La norma es de 6 horas para el producto del plan; existe otra norma de 48 h para otro producto en el mismo par, que no debe salir. Afirma:
  - `find_panelists('Samwel Mettet','00011844')` → 1 fila con `by_name` y `by_tag` en true.
  - `find_panelists('Samwel', NULL)` con un segundo «Samwel» en la cuenta 2 → 2 filas.
  - `ops_case_data(P_samwel, '00011844')`:
    - `details[0].standards` = exactamente `[{standard_time: 6, time_unit: 'hours', …}]`;
    - `siblings` tiene 3 filas;
    - `anchor.kind='receipt'`;
    - `unavailability` contiene la baja 09–16/11.
  - `ops_case_data` con una incidencia de la cuenta 2 → `ops_case: otra cuenta`.
  - Un token erróneo → excepción.
  - `has_function_privilege('authenticated','public.ops_case_data(...)','execute')` = false.
- [ ] **Step 2:** lanzar el test. Debe FALLAR (la función no existe).
- [ ] **Step 3:** escribir las dos funciones. Los internos van en el esquema `ops_case` (`CREATE SCHEMA`, `REVOKE ALL`), con una envoltura pública por token, igual que `ops_report`.
- [ ] **Step 4:** volver a lanzar el test. Debe dar PASS.
- [ ] **Step 5: Commit** `feat(ops-agent): lectura del caso en una sola llamada (plan, SLA del producto, realidad, bajas)`.

### Task 3: Cola desde ONEMS, envío y notas del agente (ONEMS, BD)

**Files:**
- Modify: `supabase/migrations/20261110121000_ops_case_analysis.sql` (se añade al final)
- Test: `supabase/tests/ops_case_analysis.test.sql` (casos nuevos)

**Interfaces:**
- Consumes: `incident_owner`, el índice `case_draft_key` (Task 1).
- Produces:
  - Tabla `public.case_analysis_request`, con las columnas:
    - `id uuid pk`, `account_id uuid not null`, `requested_by uuid`;
    - `incident_kind text check in (reported,unavailability,receipt)`, `incident_id uuid not null`;
    - `status text check in (queued,running,done,failed) default 'queued'`;
    - `result jsonb`, `error text`;
    - `created_at`, `started_at`, `finished_at`.
  - RLS de la tabla: SELECT solo para usuarios de la misma cuenta (o superadmin), sin INSERT/UPDATE directos.
  - `public.request_case_analysis(p_incident_kind text, p_incident_id uuid) RETURNS uuid`, para authenticated. Comprueba con `assert_same_account`. Si ya hay una petición `queued`/`running` de menos de 10 min para esa incidencia, devuelve esa.
  - `public.case_analysis_status(p_request_id uuid) RETURNS jsonb`, para authenticated: `{status, result, error}`. Si lleva más de 10 min en `queued`/`running`, la marca `failed` con `error='agent_timeout'` antes de devolver.
  - `public.ops_case_claim(p_token text) RETURNS jsonb`. Toma la más antigua en `queued` con `FOR UPDATE SKIP LOCKED` y la pasa a `running`. Devuelve `{request_id, account, incident_kind, incident_id, panelist_id, tag}`, o `{}` si no hay ninguna. El `tag` sale de `receipt_case.tag_norm`, de `panelist_incident → allocation_plan_details.tag_id`, o null en las bajas.
  - `public.ops_case_finish(p_token text, p_request_id uuid, p_result jsonb, p_note text, p_error text) RETURNS void`. Pasa la petición a `done` (o a `failed` si viene `p_error`). Si `p_note` no está vacío, inserta una nota `internal/system/sent` en la incidencia de la petición.
  - `public.ops_case_send(p_token text, p_incident_kind text, p_incident_id uuid, p_panelist_id uuid, p_body text, p_draft_key text) RETURNS uuid`:
    - Con incidencia: inserta en `incident_message` outbound/manager/pending_send con `meta {manager_user_id: null, via: 'ops_agent', case_draft_key}`. La clave `manager_user_id` presente hace que n8n lo trate como mensaje del manager y añada «Responder».
    - Con `p_incident_kind` NULL: inserta `panelist_notification kind='manager_notice'` con `payload {body, via:'ops_agent', case_draft_key}`.
    - En los dos casos: el panelista debe estar activo, tener telegram y ser de la misma cuenta que la incidencia. El texto debe tener entre 1 y 900 caracteres. Si la `draft_key` se repite, devuelve el id existente en lugar de fallar.
  - `public.ops_case_note(p_token text, p_incident_kind text, p_incident_id uuid, p_body text) RETURNS uuid`: nota `internal/system`.

- [ ] **Step 1: Write the failing tests:**
  - El admin 99 pide un análisis dos veces seguidas → el mismo id.
  - El admin 98 pide sobre una incidencia de la cuenta 1 → `Cross-tenant`.
  - `ops_case_claim` → `running`, con `tag='00011844'` y `panelist_id` del caso. Una segunda llamada devuelve `{}`.
  - `ops_case_finish(…, '{"x":1}', 'nota', NULL)` → `done`, más 1 nota internal en la incidencia.
  - Una petición con `created_at` de hace 11 min → `case_analysis_status` devuelve `failed/agent_timeout`.
  - `ops_case_send('receipt', <case>, <Arbe>, 'hi', 'r1:0')` dos veces → mismo id y 1 sola fila.
  - `ops_case_send(NULL, NULL, <Arbe>, 'hi', 'r1:1')` → 1 fila en `panelist_notification`.
  - Un panelista de la cuenta 2 → `ops_case: otra cuenta`.
  - Un texto de 901 caracteres → error.
  - El usuario 96 (cuenta 1) ve su petición con SELECT; el 98 no la ve.
- [ ] **Step 2:** lanzar el test. Debe FALLAR.
- [ ] **Step 3:** implementar. Las concesiones: `request_case_analysis` y `case_analysis_status` a authenticated; las `ops_case_*` solo a anon.
- [ ] **Step 4:** lanzar `bash supabase/tests/run_tests.sh` completo. Debe dar PASS.
- [ ] **Step 5: Commit** `feat(ops-agent): cola de análisis desde ONEMS y envío/nota por token`.

### Task 4: Cliente del caso y configuración (panelist_n8n, agente)

**Files:**
- Create: `ops-agent/src/ops_agent/case_client.py`
- Modify:
  - `ops-agent/src/ops_agent/config.py`: campo `case: dict = {}`, que se rellena con `cfg.get("case")`;
  - `ops-agent/playbook/config.yaml`: los modelos `case_analysis`, `case_hints`, `case_redraft` y el bloque `case: {send_accounts: ["DEMO2"], queue_interval_s: 15, max_images: 6}`;
  - `ops-agent/src/ops_agent/llm.py`: `parse` y `text` aceptan `user: str | list[dict]` (bloques de contenido de Anthropic, imágenes incluidas) y pasan la lista tal cual como `content`.
- Test: `ops-agent/tests/test_case_client.py`, `ops-agent/tests/test_config.py` (caso nuevo)

**Interfaces:**
- Consumes: el patrón `report_run._Rpc` (`call(fn, **params)` con `p_token`; errores con prefijo seguro). Se hereda de él y no se copia.
- Produces: `class CaseError(Exception)` y `class CaseClient(_Rpc)`, con `__init__(url, anon, token, transport=None)` y prefijo `"ops_case:"`. Métodos:
  - `find_panelists(name: str, tag: str | None) -> list[dict]`
  - `data(panelist_id: str, tag: str | None, kind: str | None = None, incident_id: str | None = None) -> dict`
  - `claim() -> dict | None` (None cuando la BD devuelve `{}`)
  - `finish(request_id: str, result: dict | None, note: str | None, error: str | None) -> None`
  - `send(kind: str | None, incident_id: str | None, panelist_id: str, body: str, draft_key: str) -> str`
  - `note(kind: str, incident_id: str, body: str) -> str`
  - Settings: la propiedad `case_send_allowed(account: str) -> bool` es true si `"*"` o el nombre de la cuenta está en `case.send_accounts`.

- [ ] **Step 1: Write the failing tests** con `httpx.MockTransport`:
  - Cada método hace POST a `/rest/v1/rpc/ops_case_<x>`, con `p_token` y los parámetros con prefijo `p_`.
  - `claim()` → None con `{}`.
  - Un 400 con `message="ops_case: otra cuenta"` → `CaseError` que contiene ese texto. Un mensaje que incluya el token → no se muestra el token.
  - `case_send_allowed("DEMO2")` true, `("KENYA")` false; con `["*"]` es true.
  - `AnthropicLLM.parse` con `user=[{"type":"text","text":"a"}]` envía `messages=[{"role":"user","content":[…]}]`; probarlo con un cliente falso inyectado en `_c`.
- [ ] **Step 2:** `cd ops-agent && uv run pytest tests/test_case_client.py tests/test_config.py -q`. Debe FALLAR.
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** volver a lanzar las pruebas. Debe dar PASS.
- [ ] **Step 5: Commit** `feat(ops-agent): cliente del análisis de casos y configuración`.

### Task 5: Hechos calculados por código (panelist_n8n, agente)

**Files:**
- Create: `ops-agent/src/ops_agent/case_facts.py`
- Create: `ops-agent/tests/fixtures/case_00011844.json`. Es una respuesta de `ops_case_data` con el caso de referencia, en el formato exacto de Task 2. Los nombres son reales en el planteamiento, pero en el fichero van ficticios: «Sender A» (PAN-T-048), «Receiver S» (PAN-T-053), «Dest J» (PAN-T-039).
- Test: `ops-agent/tests/test_case_facts.py`

**Interfaces:**
- Consumes: el dict de `CaseClient.data`.
- Produces: `@dataclass CaseFacts` con los campos:
  - `tag: str | None`, `scheduled: date | None`, `sent_date: date | None` (fecha local de la cuenta);
  - `send_delay_days: int | None` (días naturales, enviado − programado);
  - `received: bool`, `received_by_code: str | None`;
  - `sla_value: float | None`, `sla_unit: str | None`;
  - `elapsed: float | None`, en la unidad del SLA, desde el envío hasta la recepción o hasta ahora si no se ha recibido;
  - `sla_overrun: float | None` (elapsed − SLA cuando es > 0);
  - `same_route_to_case_panelist: list[str]`, las etiquetas hermanas cuyo destino es el panelista del caso;
  - `open_receipt_cases: list[tuple[str, str, int]]`, como (tag, reason, días abierto);
  - `overlapping_leaves: list[tuple[str, date, date]]`.

  Más `compute_facts(data: dict, now: datetime) -> CaseFacts` y `facts_text(f: CaseFacts) -> str`, que es el bloque en español que se pasa a la IA. Si hay varias `standards`, se usa la primera y se añade «(hay N normas)». Sin ninguna, `sla_value=None` y el texto dice «sin SLA en la configuración».

- [ ] **Step 1: Write the failing tests:**
  - `test_reference_case`: con `now=2026-11-10T09:00Z`:
    - `send_delay_days == 3`, `sla_value == 6`, `sla_unit == "hours"`, `received is False`;
    - `same_route_to_case_panelist == ["00011846","00011848","00011850"]`;
    - `open_receipt_cases[0][1] == "other_city_tag"` y `open_receipt_cases[0][2] == 4`;
    - `overlapping_leaves[0][1:] == (date(2026,11,9), date(2026,11,16))`.
  - `test_no_standard_gives_none`: con `standards=[]` → `sla_value is None` y `"sin SLA en la configuración" in facts_text(f)`.
  - `test_tag_not_in_plan`: con `details=[]` → `scheduled is None`, `send_delay_days is None` y sin excepción.
  - `test_days_unit`: una norma de 2 días, enviado el lunes y recibido el jueves → `elapsed == 3`, `sla_overrun == 1`.
- [ ] **Step 2:** `uv run pytest tests/test_case_facts.py -q`. Debe FALLAR.
- [ ] **Step 3:** implementar. Las fechas locales se calculan con `ZoneInfo(data["account"]["timezone"])`.
- [ ] **Step 4:** volver a lanzar las pruebas. Debe dar PASS.
- [ ] **Step 5: Commit** `feat(ops-agent): hechos del caso calculados por código (retraso, SLA, hermanas, bajas)`.

### Task 6: Análisis, borradores y salvaguardas (panelist_n8n, agente)

**Files:**
- Create: `ops-agent/src/ops_agent/case_analysis.py`
- Test: `ops-agent/tests/test_case_analysis.py`

**Interfaces:**
- Consumes:
  - `CaseFacts`, `facts_text` (Task 5);
  - `LLM` con contenido en bloques (Task 4);
  - `masking.mask`;
  - `Store.add_cost`;
  - `Settings.models` y `prices`.
- Produces:
  - `@dataclass Evidence(texts: list[str], images: list[bytes])`, con las imágenes en JPEG.
  - El modelo pydantic `Hints(names: list[str], tags: list[str])`.
  - `extract_hints(llm, settings, store, ev: Evidence, now) -> Hints`. Usa `models.case_hints`. Las etiquetas también se sacan por regex `\b\d{8}\b` de los textos, se unen y se quitan duplicados.
  - Los modelos pydantic de la salida:
    - `Cause(text, evidence, likelihood: Literal["alta","media","baja"])`
    - `Contact(panelist_id, role: Literal["remitente","receptor","destinatario"], why)`
    - `Draft(panelist_id, text)`
    - `CaseAnalysis(summary, plan, reality, comparison, causes: list[Cause], noise: list[str], contacts: list[Contact], improvement: str | None, drafts: list[Draft])`
  - `@dataclass ReadyDraft(key: str, panelist_id: str, code: str, name: str, language: str, text: str)`
  - `@dataclass CaseResult(analysis: CaseAnalysis, drafts: list[ReadyDraft], account: str, anchor: dict | None, usd: float)`
  - `analyze(llm, settings, store, data: dict, facts: CaseFacts, ev: Evidence, request_key: str, now) -> CaseResult`. Llama a `models.case_analysis` con: el system prompt, que recoge las reglas de Global Constraints sobre causas y mensajes; los datos enmascarados; `facts_text`; la evidencia; y, para cada implicado, la línea «escribe a <code> en <idioma>».
  - `redraft(llm, settings, store, d: ReadyDraft, instruction: str, now) -> ReadyDraft`: mismo key, mismo idioma, texto nuevo. Usa `models.case_redraft`.
  - `render_telegram(r: CaseResult) -> list[str]`: el primer mensaje es la tarjeta del análisis en HTML (secciones Plan · Realidad · Comparación · Causas probables · Ruido · A quién contactar · Mejora); después, un mensaje por borrador. Cada uno cabe en `MAX_REPLY`.
  - `to_onems_result(r: CaseResult) -> dict`: `{analysis: <CaseAnalysis.model_dump()>, drafts: [<ReadyDraft as dict>], anchor}`.
  - `analysis_note(r: CaseResult) -> str`: texto plano para la nota interna, de máximo 4000 caracteres.
  - Salvaguardas del código, aplicadas después de la IA:
    - se quitan los borradores cuyo `panelist_id` no esté entre los implicados de `data`;
    - el idioma lo fija el código según Global Constraints;
    - se recorta a 900 caracteres;
    - `key = f"{request_key}:{i}"`.
  - Si `month_cost` ≥ `monthly_cap_eur`, se lanza `CaseError("tope de gasto de IA alcanzado")` antes de llamar.

- [ ] **Step 1: Write the failing tests** con `FakeLLM` (devuelve un `CaseAnalysis` fijo) y el fixture de Task 5:
  - `test_foreign_draft_dropped`: un borrador para `"00000000-…"` desaparece y quedan 3.
  - `test_language_from_panelist_then_account`: el panelista con `language=None` y la cuenta `fr` → `"fr"`.
  - `test_keys_stable`: las claves son `"req1:0","req1:1","req1:2"`.
  - `test_prompt_has_facts_and_masks_phone`: el `user` enviado contiene `"3 días"` y `"«oculto»"` en lugar de `+254712345678`.
  - `test_images_as_blocks`: con 2 imágenes → 2 bloques `{"type":"image","source":{"type":"base64","media_type":"image/jpeg",…}}`.
  - `test_render_has_sections_and_probable`: «Causas probables» y «(probable:» aparecen en el primer mensaje.
  - `test_no_improvement_section_when_null`.
  - `test_cap_reached_raises`.
  - `test_extract_hints_merges_regex`: el texto «tag 00011844» y unos `Hints` vacíos de la IA → `tags == ["00011844"]`.
- [ ] **Step 2:** `uv run pytest tests/test_case_analysis.py -q`. Debe FALLAR.
- [ ] **Step 3:** implementar. El system prompt va en el módulo como constante `SYSTEM_ANALYSIS`, en español, con las reglas de los mensajes copiadas de Global Constraints.
- [ ] **Step 4:** volver a lanzar las pruebas. Debe dar PASS.
- [ ] **Step 5: Commit** `feat(ops-agent): análisis del caso y borradores con salvaguardas`.

### Task 7: Memoria de casos en el agente (panelist_n8n, agente)

**Files:**
- Modify: `ops-agent/src/ops_agent/store.py`: tablas en `SCHEMA` y métodos nuevos.
- Test: `ops-agent/tests/test_store.py` (casos nuevos)

**Interfaces:**
- Produces:
  - Tablas:
    - `case_bundles(id INTEGER PK, created TEXT, updated TEXT, state TEXT, items TEXT '[]', panelist_id TEXT, candidates TEXT '[]')`. `state` toma uno de estos valores: `open|picking|analyzing|done|discarded`.
    - `case_results(id INTEGER PK, created TEXT, bundle_id INTEGER, json TEXT)`.
    - `case_drafts(result_id INTEGER, k INTEGER, json TEXT, sent_at TEXT, message_id TEXT, PRIMARY KEY(result_id,k))`.
    - `flags.case_change`, que guarda `"<result_id>:<k>"` mientras se espera la instrucción de «Cambiar».
  - Métodos de `Store`:
    - `open_bundle(now) -> int`, que reutiliza el que esté `open`;
    - `add_to_bundle(bundle_id, item: dict, now)`, donde item es `{"kind":"text"|"image","text"?,"file_id"?}`;
    - `get_bundle(bundle_id) -> dict | None`, `current_bundle() -> dict | None` (el `open` o `picking` más reciente);
    - `set_bundle(bundle_id, *, state=None, panelist_id=None, candidates=None, now)`;
    - `save_case_result(bundle_id: int | None, result: dict, drafts: list[dict], now) -> int`;
    - `get_draft(result_id, k) -> dict | None`, `set_draft_text(result_id, k, text)`;
    - `mark_draft_sent(result_id, k, message_id, now) -> bool`: atómico, `UPDATE … WHERE sent_at IS NULL`; da False si ya estaba enviado;
    - `get_case_result(result_id) -> dict | None`;
    - `set_case_change(value: str | None)`, `case_change() -> str | None`;
    - `purge_cases(now)`: borra bundles, resultados y borradores de más de 30 días.

- [ ] **Step 1: Write the failing tests:**
  - `open_bundle` dos veces → el mismo id.
  - Cuando el bundle pasa a `done`, `open_bundle` da un id nuevo.
  - `mark_draft_sent` → True la primera vez y False la segunda.
  - `purge_cases` con `now` + 31 días lo borra todo; con + 29 días no borra nada.
  - Una base antigua (sin las tablas) se abre y las tablas se crean.
- [ ] **Step 2:** `uv run pytest tests/test_store.py -q`. Debe FALLAR.
- [ ] **Step 3:** implementar. Llamar a `purge_cases` dentro de `purge` existente o en `run_daily`, lo que ya haga la limpieza de `test_runs` (30 días).
- [ ] **Step 4:** volver a lanzar las pruebas. Debe dar PASS.
- [ ] **Step 5: Commit** `feat(ops-agent): memoria de casos (30 días) y envío marcado una sola vez`.

### Task 8: Entrada por Telegram y botones Enviar / Cambiar (panelist_n8n, agente)

**Files:**
- Create: `ops-agent/src/ops_agent/case_bot.py`
- Modify:
  - `ops-agent/src/ops_agent/telegram_io.py`:
    - `BotContext` gana `case_client: object | None = None` y `fetch_image: Callable[[str], Awaitable[bytes]] | None = None`;
    - `respond` deriva a `case_bot` el texto no reconocido como orden si hay un bundle abierto o un «Cambiar» pendiente. La ayuda `HELP` dice: «… · reenvía una conversación para analizar un caso».
    - `handle_callback` deriva a `case_bot` los datos `ca:`/`cx:`/`cp:`/`cs:`/`cc:`;
    - `run_bot` añade `MessageHandler(filters.PHOTO | filters.FORWARDED, on_case_item)`.
  - `ops-agent/src/ops_agent/cli.py`: `cmd_bot` construye el `CaseClient` si `report_configured`.
- Test: `ops-agent/tests/test_case_bot.py`

**Interfaces:**
- Consumes:
  - `Store`, con los métodos de casos (Task 7);
  - `CaseClient` (Task 4);
  - `compute_facts` (Task 5);
  - `extract_hints`, `analyze`, `redraft`, `render_telegram`, `analysis_note`, `to_onems_result` (Task 6).
- Produces:
  - `async case_item(ctx, chat_id: int, item: dict) -> tuple[str | None, Buttons | None]`. Solo acepta al responsable. Abre o amplía el bundle y contesta «Recibido (N). Si no se ve, escribe el nombre del panelista. Pulsa Analizar.» con los botones `[("🔎 Analizar", f"ca:{id}"), ("✖️ Descartar", f"cx:{id}")]`. Con un bundle abierto, el resto de la conversación son ampliaciones: un solo mensaje de respuesta por cada 10 elementos, para no inundar el chat.
  - `async case_text(ctx, chat_id, text) -> tuple[str | None, Buttons | None] | None`. Devuelve None si no le toca (no hay bundle ni «Cambiar»).
  - `async case_callback(ctx, chat_id, data) -> tuple[str | None, Buttons | None]`. Datos:
    - `ca:<bundle>`: analizar. Busca candidatos con `find_panelists`:
      - exactamente 1 → sigue;
      - ninguno o varios → pasa el bundle a `picking` y pregunta, con un botón `cp:<bundle>:<i>` por candidato (máx. 6, con «código · nombre · cuenta · ciudad») y otro «Ninguno: escribo el nombre».
      - Con el panelista resuelto: `data` (con `anchor` automático) → `compute_facts` → `analyze` → `save_case_result` → `note` en `anchor`, si lo hay.
      - Respuesta: `render_telegram`. Cada borrador lleva `[("📤 Enviar a <nombre>", f"cs:{rid}:{k}"), ("✏️ Cambiar", f"cc:{rid}:{k}")]`.
    - `cx:<bundle>`: lo descarta.
    - `cs:<rid>:<k>`:
      - comprueba `case_send_allowed(account)`; si no, contesta «Envío bloqueado: la cuenta X no está en case.send_accounts»;
      - marca el borrador con `mark_draft_sent` (si da False: «Ya enviado»);
      - hace `client.send(anchor.kind|None, anchor.id|None, panelist_id, text, key)`;
      - si `send` falla, deshace la marca (pone `sent_at` a NULL) y contesta con el error seguro;
      - si va bien: «Enviado a <nombre>. Queda en la conversación de la incidencia» o, sin incidencia, «… como aviso».
    - `cc:<rid>:<k>`: guarda `case_change` y pregunta «¿Qué cambio?». El siguiente texto pasa por `redraft`, con `set_draft_text`, y se devuelve el borrador nuevo con sus dos botones.
  - El análisis tarda: el botón contesta enseguida «Analizando…» y el resultado llega como mensaje nuevo, con `_start_run` o una tarea propia. Mientras tanto no se acepta otro `ca:`.

- [ ] **Step 1: Write the failing tests**, con `FakeCaseClient` en `tests/fakes.py` (lo que lleva cada método queda en `calls`) y `FakeLLM`:
  - `test_forward_then_analyze_single_candidate`: 2 elementos + `ca:` → 1 llamada a `data`, 1 a `note` en el anchor, y 1 respuesta + 3 borradores con botones `cs:`.
  - `test_ambiguous_name_asks`: 2 candidatos → botones `cp:` y ninguna llamada a `data`.
  - `test_send_blocked_outside_allowlist`: la cuenta KENYA → ninguna llamada a `send`.
  - `test_double_send_once`: `cs:` dos veces con la cuenta DEMO2 → 1 llamada a `send` y el texto «Ya enviado».
  - `test_send_failure_unmarks`: si `send` lanza `CaseError`, después se puede volver a enviar.
  - `test_change_flow`: `cc:` → texto «más corto» → `redraft` llamado y nuevos botones `cs:` con el mismo `k`.
  - `test_stranger_ignored`: otro `chat_id` → `(None, None)`.
  - `test_commands_still_work_with_open_bundle`: «estado» con un bundle abierto da la respuesta de estado y no lo añade al bundle.
- [ ] **Step 2:** `uv run pytest tests/test_case_bot.py tests/test_telegram_io.py -q`. Debe FALLAR.
- [ ] **Step 3:** implementar. `on_case_item` hace dos cosas:
  - En las fotos, coge la mayor de `update.message.photo` y la baja con `bot.get_file(...).download_as_bytearray()`.
  - En lo reenviado, antepone «Reenviado de <forward_origin.sender_user_name o sender_user.full_name>:» al texto o al pie de foto.
- [ ] **Step 4:** lanzar `uv run pytest -q` completo. Debe dar PASS, y `uv run ruff check` limpio.
- [ ] **Step 5: Commit** `feat(ops-agent): análisis de casos desde Telegram con Enviar/Cambiar por mensaje`.

### Task 9: Peticiones desde ONEMS en el proceso del bot (panelist_n8n, agente)

**Files:**
- Create: `ops-agent/src/ops_agent/case_worker.py`
- Modify:
  - `ops-agent/src/ops_agent/telegram_io.py`: `run_bot.post_init` arranca `queue_loop` si `ctx.case_client`;
  - `ops-agent/playbook/revisiones.md`: sección «Análisis de casos» en lenguaje llano: qué hace, las dos entradas, que nunca envía solo, la lista `send_accounts` y qué hacer si ONEMS dice «el agente no responde»;
  - `ops-agent/README.md`: una línea en órdenes.
- Test: `ops-agent/tests/test_case_worker.py`

**Interfaces:**
- Consumes: `CaseClient.claim/data/finish`, `compute_facts`, `analyze`, `to_onems_result`, `analysis_note` (Tasks 4–6).
- Produces:
  - `async process_one(ctx) -> bool`: True si había petición. Para cada petición:
    - `claim`;
    - `data(panelist_id, tag, kind, incident_id)`;
    - `analyze` con `Evidence([], [])` y `request_key = request_id`;
    - `finish(request_id, to_onems_result(r), analysis_note(r), None)`.
    - Ante cualquier excepción: `finish(request_id, None, None, "<mensaje seguro>")`.
  - `async queue_loop(ctx, interval: float)`: no se para por un fallo, igual que `expiry_loop`, y espera `interval` (`case.queue_interval_s`) entre vueltas vacías.

- [ ] **Step 1: Write the failing tests:**
  - Con una petición → `finish` con `result["drafts"]` de 3 elementos y una nota no vacía.
  - Si `analyze` lanza una excepción → `finish` con `error` y `result=None`.
  - Con `claim` None → False y ninguna otra llamada.
  - El bucle sigue tras una excepción de `claim`. Se prueba con `interval=0` y dos vueltas: se cancela tras la 2ª.
- [ ] **Step 2:** `uv run pytest tests/test_case_worker.py -q`. Debe FALLAR.
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** lanzar `uv run pytest -q` y `uv run ruff check`. Debe dar PASS.
- [ ] **Step 5: Commit** `feat(ops-agent): el bot atiende las peticiones de análisis de ONEMS` (en el mismo commit va el playbook).

### Task 10: n8n — cabecera y respuestas de los casos de recepción ([DEV] primero) (panelist_n8n, flujos)

**Files:**
- Modify: `workflows/deliver-incident-messages.json`, nodos «Get incident header» y «Build message text».
- Modify: `workflows/dev-telegram-user-initiated-message.json` (y después `telegram-user-initiated-message.json`), nodos:
  - «Reopen conversation ctx»;
  - «Log incident reply» y «Log incident reply photo»;
  - «Log conversation closed».
- Backups: `workflows/backups/*_pre_analisis_casos_20261110.json`, con la versión viva de cada flujo descargada justo antes de tocarlo.

**Interfaces:**
- Consumes: el kind `'receipt'` y el `p_panelist_id` de `log_incident_message` (Task 1).
- Produces (sin funciones nuevas, solo comportamiento):
  - Un mensaje del manager o del agente sobre un caso de recepción sale con la cabecera «Recepción de la etiqueta <tag_raw>» en el idioma del panelista. «Get incident header» añade `tag_raw` cuando `$1='receipt'`. «Build message text» añade la entrada `receipt` con es/en/fr/ar/pt.
  - «Responder» reabre la conversación de un mensaje `receipt` si el caso existe y el mensaje tiene menos de 7 días.
  - Las respuestas se guardan con el panelista que responde. En los dos nodos «Log incident reply», la llamada a `log_incident_message` pasa como 8º argumento `NULLIF($6,'')::uuid`, y el array de `queryReplacement` añade `String($('Route & Identify').first().json.panelist_id || '')`.
  - «Log conversation closed» admite `'receipt'` en su `IN (...)`.

- [ ] **Step 1:** descargar los flujos vivos DEV y PROD con `n8n_get_workflow`, guardar los backups y comparar con el JSON del repo. Si difieren, se para y se avisa: la regla es comparar lo vivo antes de tocar.
- [ ] **Step 2:** aplicar los cambios en [DEV] con `n8n_update_partial_workflow` y lanzar `n8n_validate_workflow`. Debe salir sin errores nuevos.
- [ ] **Step 3: Prueba en DEV con DEMO2**, una vez aplicadas las migraciones (Task 13 paso 2). Se hace como en la fase 2: el tester PAN-DEM-003 escribe al bot DEV.
  - Insertar con `ops_case_send` un mensaje `receipt` a PAN-DEM-003 sobre un `receipt_case` de prueba de DEMO2.
  - Comprobar que llega con la cabecera.
  - Pulsar Responder, escribir «ok» y comprobar que aparece una fila inbound con `panelist_id` = PAN-DEM-003.
  - Limpiar las filas de prueba.
- [ ] **Step 4:** con la prueba en verde, replicar en PROD (`deliver-incident-messages` es único y lo comparten DEV y PROD; el flujo principal PROD aparte). Volver a validar y exportar los JSON al repo, tapando las claves según [[n8n-claves-en-nodos]].
- [ ] **Step 5: Commit** `feat(bot): conversación en los casos de recepción y respuestas con el panelista que responde`.

### Task 11: ONEMS — tipos, hook y panel «Analizar caso» (ONEMS, frontend)

**Files:**
- Modify: `src/lib/hooks/useIncidentConversation.ts`:
  - `ConversationKind` pasa a ser `'reported' | 'unavailability' | 'receipt'`;
  - el select añade `panelists(name, panelist_code)`;
  - `IncidentMessage` gana `panelist_id: string` y `panelists?: {name: string, panelist_code: string} | null`.
- Modify: `src/components/incidents/IncidentConversation.tsx`. Cuando un mensaje es para otro panelista, distinto del de la incidencia, muestra «→ <nombre> (<código>)». Recibe una prop nueva `incidentPanelistId?: string`.
- Create: `src/lib/hooks/useCaseAnalysis.ts`
- Create: `src/components/incidents/CaseAnalysisPanel.tsx`
- Modify: `public/locales/{en,es,fr,ar,pt}.csv`, con las claves `case_analysis.*` de abajo.

**Interfaces:**
- Consumes: las RPC `request_case_analysis`, `case_analysis_status` (Task 3) y `send_case_message` (Task 1); el formato de `result` de `to_onems_result` (Task 6).
- Produces:
  - `useCaseAnalysis(kind: ConversationKind, incidentId: string)`. Devuelve `{state: 'idle'|'running'|'done'|'failed', result: CaseAnalysisResult | null, error: string | null, start(): Promise<void>, send(draft: CaseDraft, body: string): Promise<void>, sent: Set<string>}`.
    - Mientras está en `running`, consulta `case_analysis_status` cada 5 s.
    - `send` llama a `send_case_message(kind, incidentId, draft.panelist_id, body, draft.key)`. Si la base da un error de duplicado (`23505`), lo cuenta como enviado.
  - Los tipos `CaseDraft {key, panelist_id, code, name, language, text}` y `CaseAnalysisResult {analysis: {summary, plan, reality, comparison, causes[{text,evidence,likelihood}], noise[], contacts[{panelist_id, role, why}], improvement: string|null}, drafts: CaseDraft[], anchor}`, en el propio fichero del hook.
  - `<CaseAnalysisPanel kind incidentId />`:
    - un botón «Analizar caso», con spinner mientras corre;
    - la tarjeta con las secciones;
    - cada borrador en un `textarea` editable (`dir="rtl"` si `language==='ar'`), con el botón «Enviar a <nombre>», que se desactiva al pulsarlo y mientras se envía; una vez enviado, muestra «Enviado».
    - Si `error === 'agent_timeout'`, muestra el texto «el agente no responde».
  - Claves CSV (en los 5 idiomas):
    - `case_analysis.button`, `.running`, `.failed`, `.agent_timeout`;
    - `.summary`, `.plan`, `.reality`, `.comparison`, `.causes`, `.probable`, `.noise`, `.contacts`, `.improvement`, `.no_improvement`;
    - `.drafts`, `.send_to` (con `{name}`), `.sent`, `.send_error`;
    - `.role.remitente`, `.role.receptor`, `.role.destinatario`;
    - `case_analysis.recipient`.

- [ ] **Step 1:** implementar los tipos y el hook. Comprobar con `npx tsc --noEmit`: debe salir sin errores.
- [ ] **Step 2:** implementar el panel y el cambio en `IncidentConversation`, y añadir las claves a los 5 CSV. Comprobar con `grep -c "^case_analysis\." public/locales/*.csv`: el mismo número en los 5.
- [ ] **Step 3:** `npm run lint`. Debe dar 0 avisos.
- [ ] **Step 4: Commit** `feat(incidents): panel «Analizar caso» con borradores editables y envío uno a uno`.

### Task 12: ONEMS — montar el panel en las tres pantallas (ONEMS, frontend)

**Files:**
- Modify: `src/components/incidents/ReportedIncidentPanel.tsx`. Pone `<CaseAnalysisPanel kind="reported" incidentId={incidentId} />` encima de `IncidentConversation`.
- Modify: `src/components/incidents/IncidentReviewPanel.tsx`. Lo mismo con `kind="unavailability"`.
- Modify: `src/components/incidents/receipts/ReceiptCasesTable.tsx`. Añade el botón «Analizar» en cada fila, junto a Fix y Cerrar. Abre `ReceiptCaseDialog`.
- Create: `src/components/incidents/receipts/ReceiptCaseDialog.tsx`. Es un modal con `CaseAnalysisPanel kind="receipt"` + `IncidentConversation kind="receipt" incidentId={c.id} incidentPanelistId={c.panelist_id}`.
- Modify: `public/locales/*.csv`, con `receipt_errors.analyze` y `receipt_errors.case_dialog_title` en los 5.

**Interfaces:**
- Consumes: `CaseAnalysisPanel`, `IncidentConversation` (Task 11).

- [ ] **Step 1:** implementar.
- [ ] **Step 2:** `npm run lint && npm run build`. Los dos deben pasar.
- [ ] **Step 3: Verificación en navegador** (`npm run dev`, cuenta DEMO2):
  - el botón aparece en las tres pantallas;
  - sin el agente en marcha, una petición pasa a «el agente no responde» a los 10 min. Para probarlo antes, se cambia `created_at` de la petición de prueba con SQL: es DEMO2 y está autorizado como dato de prueba.
- [ ] **Step 4:** `graphify update .` (regla del proyecto tras modificar código).
- [ ] **Step 5: Commit** `feat(incidents): «Analizar caso» en recepciones, incidencias reportadas y bajas`.

### Task 13: Puesta en marcha y aceptación (con el usuario)

Cada paso que escribe en la base o en el servidor se confirma con el usuario en ese momento.

- [ ] **Step 1:** pasar el conjunto entero de tests en local: `bash supabase/tests/run_tests.sh` y `cd ops-agent && uv run pytest -q`. Los dos deben dar PASS.
- [ ] **Step 2:** **aplicar las migraciones**:
  - Pedir confirmación nombrando «onems-dev `sehbnpgzqljrsqimwyuz`», y aplicar `20261110120000` y luego `20261110121000` con `apply_migration`.
  - Comprobar las concesiones con `has_function_privilege`: anon solo en `ops_case_*`; authenticated en `request_case_analysis`, `case_analysis_status` y `send_case_message`.
  - `get_advisors(security)`: no debe salir ningún aviso nuevo.
- [ ] **Step 3:** Task 10 pasos 3–4 (n8n DEV y luego PROD).
- [ ] **Step 4:** **desplegar el agente**:
  - con `deploy/deploy.ps1`; no hace falta ninguna variable nueva en `/etc/onems-ops-agent/env`, porque se reutilizan SUPABASE_URL, la clave anon y OPS_TEST_TOKEN;
  - `systemctl restart onems-ops-agent-bot`;
  - mirar `journalctl` 1 minuto: el bucle de la cola debe estar en marcha y sin errores.
- [ ] **Step 5:** **aceptación en DEMO2**:
  - preparar un caso simulado con la misma forma que 00011844 (remitente PAN-DEM-004, destinatario PAN-DEM-003, etiqueta de prueba);
  - analizarlo por Telegram y desde ONEMS;
  - enviar un mensaje a PAN-DEM-003 y comprobar que llega y queda en la conversación;
  - pulsar Enviar dos veces: un solo mensaje;
  - limpiar los datos de prueba.
- [ ] **Step 6:** **aceptación con el caso real 00011844**, sin enviar nada: con `send_accounts` = DEMO2, el envío a KENYA está bloqueado por código. Entrada por Telegram con las dos capturas y «Samwel Mettet», y también desde ONEMS. Comprobar el apartado 7 del spec:
  - plan + SLA de 6 h de SMALL PACKETS EXPRESS;
  - 3 días de retraso;
  - causa probable en origen;
  - el solape explicado como ruido;
  - borradores en inglés para Arbe, Samwel y James.
- [ ] **Step 7:** el usuario decide si amplía `case.send_accounts` a `["*"]`: commit en panelist_n8n y despliegue.
- [ ] **Step 8:**
  - PRs: ONEMS `feat/analisis-casos` → `develop` y después `main`; panelist_n8n `feat/ops-agent-analisis-casos`. Los fusiona el usuario.
  - Actualizar la memoria [[agente-operaciones]].
