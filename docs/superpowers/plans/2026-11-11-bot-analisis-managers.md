# Bot de análisis para managers — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un bot de Telegram nuevo con el que los managers de cada cuenta, en chat privado, analizan sus casos, envían los mensajes a sus panelistas y aplican R4, solo en su cuenta, con un tope de 5 $ al mes por cuenta.

**Architecture:**
- **Base de datos:** las funciones `ops_case_*` y `ops_fix_r4_*` reciben la cuenta del que pregunta y rechazan lo de otra cuenta. Una función nueva dice qué cuentas y roles tiene un correo (o si es superadmin).
- **Agente:** el análisis de casos deja de ser de un único usuario. Todo va por chat y con un «actor» (chat, cuenta, rol, correo, si es Ignacio o superadmin). El bot de managers es un segundo proceso que reutiliza esa lógica, con alta por correo y código y gasto apuntado por cuenta.
- **ONEMS:** la ficha de la cuenta gana el correo del Allocation Plan Manager.

**Tech Stack:** Postgres (plpgsql), Python (python-telegram-bot, httpx, SQLite, pytest), React + TypeScript.

**Spec:** `docs/superpowers/specs/2026-11-11-bot-analisis-managers-design.md` (sobre todo §9 y §9b).

**Repos y ramas:** ONEMS `feat/analisis-casos`; panelist_n8n `feat/ops-agent-analisis-casos`. No se sube nada a GitHub.

## Global Constraints

- **Base de datos onems-dev `sehbnpgzqljrsqimwyuz`:**
  - la migración nueva `20261111090000_bot_managers.sql` se valida en el Postgres local 5433 (`bash supabase/tests/run_tests.sh <test>`; hay 9 fallos que ya existían);
  - solo se aplica en la base real con confirmación explícita.
- **Funciones con token:**
  - patrón de siempre: `SECURITY DEFINER SET search_path = ''`, comprobación `ops_test._check(p_token)`, permiso de ejecución solo para anon y mensajes de error con prefijo `ops_case:`/`ops_fix:`;
  - si se cambia la firma de una función que ya existe, se borra la vieja con DROP y se crea la nueva con valores por defecto, para que las llamadas de hoy sigan valiendo.
- **Roles que dan acceso:** `email_panelist_manager`, `email_account_manager` y `email_allocation_plan_manager` (columna nueva).
  - Superadmin = un perfil de ONEMS con `role = 'superadmin'` y ese correo; puede elegir cualquier país.
  - Un correo que no es de superadmin y aparece en más de una cuenta no se da de alta.
- **Tope de gasto:**
  - 5 $ al mes por cuenta (`case.manager_monthly_cap_usd: 5` en `playbook/config.yaml`), mes natural de Madrid;
  - se comprueba antes de cada análisis y de cada «Cambiar»;
  - el gasto se apunta a la cuenta y a la persona.
- **Alta:**
  - el código tiene 6 cifras, vale 15 minutos y se guarda solo su hash;
  - máximo 5 intentos por código y 3 códigos por hora, tanto por chat como por correo;
  - la respuesta es la misma sea el correo válido o no;
  - se envía con el Resend del informe de operación;
  - la comprobación del rol se recuerda 5 minutos.
- **Lo que no ven los managers:** el prompt para Claude Code (solo Ignacio y los superadmin), el informe de las 8:00 y los arreglos de n8n.
- **Puertas que siguen vigentes:**
  - `case_analysis_allowed` (hoy solo DEMO2): para el análisis del manager;
  - `case.send_accounts`: para enviar y aplicar R4.
- **Interfaz del bot de managers:** en el idioma de la cuenta (`accounts.default_language`, con en, es, fr, ar y pt; si no hay, inglés).
- **Registros:** nunca contenido, correos ni códigos.
- **Calidad:**
  - agente: `uv run pytest -q` en verde;
  - ONEMS: `npx tsc --noEmit`, `npx eslint --max-warnings 0` sobre lo tocado y `npm run build`.

## Review Focus

1. **Dos managers de cuentas distintas analizan a la vez.** Cada uno ve solo su caso; no se mezclan cajas, «Cambiar» ni bloqueos (Task 3).
2. **Un manager pulsa un botón de un resultado de otra cuenta** (datos de botón manipulados). Se rechaza (Task 3 y Task 4).
3. **Alguien prueba correos al azar.** No se revela cuáles son de managers y no hay más de 3 códigos por hora (Task 4).
4. **La cuenta llega a 5 $.** No se llama a la IA hasta el día 1; los otros países siguen funcionando (Task 4).
5. **El bot de Ignacio sigue exactamente igual:** informe, arreglos, análisis de cualquier cuenta (Task 3).

---

### Task 1: Base de datos (ONEMS)

**Files:**
- Create: `supabase/migrations/20261111090000_bot_managers.sql`.
- Test: `supabase/tests/bot_managers.test.sql`.

**Interfaces:**
- **Produce, en la tabla de cuentas:** `accounts.email_allocation_plan_manager text NULL`, con el CHECK de formato igual que los otros (patrón de `20261109120000_account_contact_roles.sql`).
- **Produce `public.ops_manager_lookup(p_token text, p_email text) RETURNS jsonb`:**
  - devuelve `{superadmin: bool, accounts: [{account, language, role}]}`;
  - compara correos sin distinguir mayúsculas ni espacios;
  - solo cuentas activas, sin las de prueba que lleguen en `p_exclude text[] DEFAULT '{}'`;
  - `role` ∈ `panelist_manager`, `account_manager`, `allocation_plan_manager`.
- **Produce `public.ops_case_account_enabled(p_token text, p_account text) RETURNS boolean`:** llama a `case_analysis_allowed` de esa cuenta.
- **`p_account text DEFAULT NULL` nuevo** en `ops_case_find_panelists`, `ops_case_data`, `ops_case_send`, `ops_case_note`, `ops_fix_r4_preview`, `ops_fix_r4_apply` y `ops_fix_r4_undo`. Si viene:
  - `find_panelists` solo busca en esa cuenta;
  - las demás fallan con `ops_case: otra cuenta` (o `ops_fix: otra cuenta`) si el panelista, la incidencia, el caso o el registro son de otra.
  - Si viene NULL, se comportan exactamente como hoy (bot de Ignacio).

- [ ] **Step 1: Write the failing tests:**
  - un correo de panelist manager de la cuenta 1 → una cuenta con su rol;
  - el mismo correo también en la cuenta 2 → dos cuentas (el agente lo rechazará);
  - un correo de superadmin → `superadmin = true`;
  - un correo desconocido → listas vacías;
  - mayúsculas o espacios → coincide igual;
  - con `p_account = 'cuenta 2'`: `find_panelists` no devuelve panelistas de la cuenta 1; `ops_case_data` con un panelista de la cuenta 1 → `otra cuenta`; `ops_case_send` → `otra cuenta`; `ops_fix_r4_preview` sobre un caso de la cuenta 1 → `otra cuenta`;
  - sin `p_account`: los tests existentes de `ops_case_analysis` y `ops_fix_r4` pasan sin cambios;
  - permisos: anon puede ejecutar; authenticated no;
  - la columna nueva rechaza un correo con formato malo.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementar. Para cambiar las firmas: DROP de la vieja y CREATE de la nueva, con la definición actual (está en las migraciones `20261110121000` y `20261110140000`) más el control de cuenta.
- [ ] **Step 4:** el test → PASS; la suite completa → solo los 9 fallos conocidos.
- [ ] **Step 5: Commit** `feat(ops-agent): base para el bot de managers (rol Allocation Plan Manager, búsqueda por correo, control de cuenta)`.

### Task 2: Campo del Allocation Plan Manager en ONEMS (frontend)

**Files:**
- Modify: la pantalla donde se editan los correos de rol de la cuenta. Buscar `email_upu_account_manager` en `src/`.
- Modify: los tipos de la cuenta.
- Modify: `public/locales/{en,es,fr,ar,pt}.csv`, con la clave del campo nuevo al lado de las de los otros roles.

- [ ] **Step 1:** añadir el campo igual que los otros 5 roles: mismo componente, misma validación y mismo guardado.
- [ ] **Step 2:** pasar `npx tsc --noEmit`, `npx eslint --max-warnings 0` sobre lo tocado y `npm run build`.
- [ ] **Step 3: Commit** `feat(accounts): correo del Allocation Plan Manager en la ficha de la cuenta`.

### Task 3: Análisis de casos por chat y por actor (panelist_n8n, agente)

**Files:**
- Modify: `ops-agent/src/ops_agent/store.py`:
  - `case_bundles` y el flag de «Cambiar» llevan `chat_id`;
  - `case_results` lleva `chat_id` y `account`;
  - `costs` gana `account TEXT NULL` y `actor TEXT NULL`.
  - Todo con migración de columnas (`ADDED_COLUMNS`).
- Modify: `case_bot.py`, `case_fix_buttons.py`, `case_client.py`, `case_analysis.py`, `case_worker.py` y `telegram_io.py`.
- Test: `tests/test_case_bot.py`, `tests/test_case_fix_buttons.py` (o donde estén) y `tests/test_store.py`.

**Interfaces:**
- **Produce `@dataclass Actor(chat_id: int, account: str | None, role: str, email: str | None, is_owner: bool, is_superadmin: bool)`** en `case_bot.py`. Ignacio = `Actor(owner_chat_id, None, "owner", None, True, True)`; `account=None` significa «cualquier cuenta».
- **Todas las entradas** (`case_item`, `case_text` y `case_callback`) reciben el `Actor` en lugar de comparar con `owner_chat_id`. La comprobación de quién puede entrar sube a quien llama: `telegram_io` para Ignacio y Task 4 para los managers.
- **Por chat:**
  - `open_bundle`, `current_bundle` y `case_change` filtran por `chat_id`;
  - el bloqueo de «analizando» va por `chat_id`;
  - cada botón comprueba que el resultado guardado es del mismo `chat_id` y, si el actor tiene cuenta, de esa cuenta.
- **`CaseClient`:** todos los métodos aceptan `account: str | None = None` y lo pasan como `p_account` (Task 1).
- **`RepairClient`:** `preview`, `apply` y `undo` de r4 aceptan `account`.
- **Gasto:** `_charge` apunta `account` (del actor o del caso) y `actor` (correo o «owner»).
- **Funciones nuevas en `Store`:**
  - `account_month_cost(account, at) -> float` (mes de Madrid);
  - `month_costs_by_account(at) -> list[dict]` y `month_costs_by_actor(at) -> list[dict]`.
- **Prompt para Claude Code:** sin botón `pp:` y sin prompt si el actor no es Ignacio ni superadmin.

- [ ] **Step 1: Write the failing tests:**
  - dos chats con cajas independientes;
  - el «Cambiar» de un chat no afecta al otro;
  - el análisis en marcha de un chat no bloquea al otro;
  - un botón con un `rid` de otro chat → «Ese botón ya no es válido»;
  - un actor con cuenta X → `find_panelists` y `data` reciben `account='X'`;
  - el gasto queda apuntado con su cuenta y actor;
  - `account_month_cost` suma solo esa cuenta y ese mes;
  - un actor que no es Ignacio no recibe `pp:`;
  - todos los tests del bot de Ignacio siguen pasando con su `Actor`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementar. Si algún fichero pasa de unas 450 líneas, separar.
- [ ] **Step 4:** `uv run pytest -q` en verde.
- [ ] **Step 5: Commit** `refactor(ops-agent): análisis de casos por chat y por actor (base del bot de managers)`.

### Task 4: Bot de managers (panelist_n8n, agente)

**Files:**
- Create: `ops-agent/src/ops_agent/manager_bot.py` (alta, actores, tope, órdenes) y `ops-agent/src/ops_agent/manager_i18n.py` (textos en en, es, fr, ar y pt).
- Modify:
  - `config.py`: `MANAGER_BOT_TOKEN` opcional y `case.manager_monthly_cap_usd`;
  - `cli.py`: orden `ops-agent manager-bot`;
  - `telegram_io.py`: orden «gastos» en el bot de Ignacio;
  - `store.py`: tablas `manager_enrolments(telegram_id PK, email, account, role, superadmin, enrolled_at, blocked)`, `manager_codes(telegram_id, email_hash, code_hash, expires_at, attempts, created_at)` y `manager_role_cache`;
  - `report_run.py`: reutilizar `send_resend`.
- Create: `ops-agent/deploy/onems-ops-agent-managerbot.service`, igual que el del bot de Ignacio pero con `ExecStart=… ops-agent manager-bot`. Ajustar `server-install.sh` para instalarlo solo si el fichero de entorno tiene `MANAGER_BOT_TOKEN`.
- Test: `ops-agent/tests/test_manager_bot.py`.

**Interfaces:**
- Consume: `Actor`, `case_item`, `case_text` y `case_callback` (Task 3); `ops_manager_lookup` y `ops_case_account_enabled` (Task 1) en un `ManagerClient(_Rpc)`.
- **Flujo del chat:**
  - Sin alta: un texto con forma de correo → `lookup`. Si vale (una sola cuenta, o superadmin), se genera y envía el código. La respuesta es siempre «Si el correo es de un responsable de una cuenta, recibirás un código en unos minutos».
  - Un texto de 6 cifras con un código pendiente → se comprueba y se da de alta. Al superadmin se le enseñan botones de país.
  - Cualquier otra cosa sin alta → «Escríbeme tu correo de ONEMS para empezar».
- **Con alta, en cada mensaje o botón:**
  1. Se vuelve a comprobar el rol (5 minutos en caché). Si ya no vale, se bloquea el alta y el bot pide identificarse de nuevo.
  2. `ops_case_account_enabled`: si es false, «Tu cuenta aún no tiene el análisis activado».
  3. Al pedir un análisis o un «Cambiar»: si `account_month_cost ≥ tope`, «Tu cuenta ha llegado al límite de este mes».
  4. Se pasa a `case_*` con el `Actor`.
- **Órdenes del manager:** «país» (solo superadmin) muestra botones de cuentas para cambiar; «ayuda».
- **Órdenes de Ignacio:** «gastos» devuelve, para el mes en curso, lo gastado por cuenta (con el tope) y por persona (correo, enmascarado salvo el dominio y las 2 primeras letras).
- **Enviar y R4 para managers:** solo si `settings.case_send_allowed(account)`. Si no, el botón contesta «Los envíos de tu cuenta aún no están activados».

- [ ] **Step 1: Write the failing tests:**
  - alta correcta con un correo de una cuenta;
  - un correo de dos cuentas → no se da de alta, pero con la misma respuesta pública;
  - un correo desconocido → la misma respuesta y ningún correo enviado;
  - el cuarto código en una hora → no se envía;
  - el sexto intento con un código malo → hay que pedir otro;
  - un código caducado;
  - el superadmin elige país y lo cambia con «país»;
  - el rol retirado → alta bloqueada;
  - la cuenta cerrada → el mensaje correspondiente y ninguna llamada a la IA;
  - el tope alcanzado → ninguna llamada a la IA, mientras otra cuenta sí funciona;
  - «gastos» en el bot de Ignacio con dos cuentas;
  - ningún registro contiene el correo ni el código.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** `uv run pytest -q` en verde.
- [ ] **Step 5: Commit** `feat(ops-agent): bot de análisis para los managers (alta por correo, por cuenta, tope 5 $)`.

### Task 5: Puesta en marcha y aceptación (con Ignacio)

- [ ] **Step 1:** con confirmación, nombrando onems-dev `sehbnpgzqljrsqimwyuz`, aplicar `20261111090000_bot_managers.sql`. Después comprobar permisos y los avisos de seguridad.
- [ ] **Step 2:** Ignacio crea el bot en BotFather (privacidad desactivada). Se le guía para poner `MANAGER_BOT_TOKEN` en `/etc/onems-ops-agent/env` sin pasarlo por el chat.
- [ ] **Step 3:** desplegar el agente (`deploy.ps1`), con los dos servicios activos, y revisar los logs.
- [ ] **Step 4:** aceptación en DEMO2:
  - poner un correo de Ignacio como Allocation Plan Manager de DEMO2, desde ONEMS en local o con SQL confirmada;
  - alta, análisis del caso de prueba, envío a PAN-DEM-003, R4 aplicar y deshacer;
  - un caso de Kenya → rechazado;
  - con el tope bajado a 0,01 $ en la configuración del servidor → aviso de límite;
  - «gastos» en el bot de Ignacio.
- [ ] **Step 5:** volver a poner el tope en 5 $ y limpiar los datos de prueba de DEMO2 (también los de los planes anteriores) antes del 14/11.
