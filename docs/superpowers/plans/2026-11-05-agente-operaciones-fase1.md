# Agente de operaciones — Fase 1 (revisión diaria + informe + bot) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An agent on the Hetzner server reviews the last 24 h of n8n executions every day at 08:00 Europe/Madrid. It sends the owner a Spanish report through its own Telegram bot, with a cause and a proposed fix for each failure, and answers a fixed set of owner-only commands. An n8n watch raises an alarm if no report arrives by 08:30.

**Architecture:** A Python package, `ops_agent`, with three processes. A systemd timer runs `ops-agent run-daily` once a day. A systemd service runs the Telegram bot by long polling, so it needs no inbound port. One small n8n workflow receives a heartbeat and raises the 08:30 alarm. Facts are collected with plain code against the n8n public API. Claude Sonnet 5.5 only diagnoses new failures and returns structured output. Claude Haiku 5.5 only writes the "detalle N" expansions. The report itself is a fixed template. State lives in one SQLite file.

**Tech Stack:**
- Python ≥3.12, managed with `uv`
- `httpx` (n8n API), `anthropic` 1.x, `python-telegram-bot` ≥21 (async), `croniter`, `pydantic` v2, `PyYAML`
- `pytest` + `pytest-asyncio`
- SQLite (stdlib `sqlite3`)
- systemd on Ubuntu 26.04

**Spec:** `docs/superpowers/specs/2026-11-05-agente-operaciones-design.md`

**Scope of this plan:** The spec covers four separable subsystems, delivered as four plans. This is phase 1. Phases 2–4 get their own plans once phase 1 is live:
- **Phase 2:** active tests with the real Telegram account of the DEMO2 test panelist, plus DEMO2 fixtures and cleanup (spec §6.10–6.11, §11, §13.1–13.2).
- **Phase 3:** authorised fixes, covering `autorizo N`, `deshaz N`, DEV→PROD, backups and Opus (spec §7.2, 7.4–7.5, §13.6–13.8).
- **Phase 4:** statistical anomalies and baseline. This needs the read-only DB role, a DB change done in a session with confirmation (spec §2.4, §8.3, §13.3–13.4).

In phase 1, `autorizo` and `deshaz` reply "disponible en la fase 3".

## Global Constraints

- **Language.** All user-facing text is in plain Spanish, outcome first. Code, identifiers and commit messages are in English.
- **Report schedule.** The report runs at **08:00 Europe/Madrid**, every day including weekends (`OnCalendar=*-*-* 08:00:00 Europe/Madrid`, `Persistent=true`).
- **Owner only.** The bot obeys **only** `OWNER_CHAT_ID`. Every other chat is ignored silently and logged.
- **Fixed commands.** Commands are exact, case-insensitive and never interpreted by AI: `detalle N`, `pausa`, `sigue`, `estado`, `informe`, `autorizo N`, `deshaz N`.
- **Models.** These are config lines in `playbook/config.yaml`:
  - `diagnose: claude-sonnet-5-5`
  - `detail: claude-haiku-5-5`
  - `apply_fix: claude-opus-5-5` (unused in phase 1)
- **Monthly AI cap.** The cap is **20 EUR/month**, tracked in code from `response.usage` × the prices in config (treat USD≈EUR). At ≥80 % the report says so. At ≥100 % diagnosis stops and the report says "diagnóstico IA pausado por tope de gasto".
- **Prices in config, USD per 1M tokens (input/output):**

  | Model | Input | Output |
  |---|---|---|
  | sonnet-5-5 | 2.00 | 10.00 |
  | haiku-5-5 | 0.10 | 0.50 |
  | opus-5-5 | 4.00 | 20.00 |

- **Secrets.**
  - Never print, log or send any secret.
  - Before any n8n data leaves for an LLM or Telegram, it passes through `mask()` (Task 1).
  - Panelists appear only as code or first name.
- **No writes in phase 1.** The agent makes **no writes** to n8n workflows or to Supabase. Its only outbound actions are Telegram messages to the owner and one heartbeat POST.
- **Never raise schedule frequency.** The only n8n artefact is one workflow (Task 9). It runs 2 executions per day.
- **Excluded workflows.** Exclude any workflow whose name starts with `[BACKUP`, `_temp`, or that is archived.
- **Partial report over silence.** Every collector failure becomes a line under "No pude comprobar" and the rest of the report is still sent.
- **Telegram format.** Messages use `parse_mode=HTML` with all dynamic text HTML-escaped. Messages are split at ≤4000 chars on item boundaries.
- **Repository.** The code lives in `c:\Users\fernandezi\projects\ONE n8n\panelist_n8n\ops-agent\`, on branch `feat/ops-agent`. Commit, but do not push or merge without the owner's explicit order.

## Review Focus

1. **An n8n API page that returns 401/5xx or times out mid-pagination.** The report still goes out, with "No pude comprobar: ejecuciones de n8n" and a count of what was read. Test: `test_run_daily_n8n_down_sends_partial_report` (Task 8).
2. **The same failure repeated 30 times in a morning (the 04/11 case).** It is one item with "30 veces" and the first and last time, not 30 items. Test: `test_group_failures_collapses_same_fingerprint` (Task 3).
3. **An error message or node parameters that contain a key, a JWT or a phone number.** These are masked before Sonnet sees them and before Telegram shows them. Test: `test_mask_removes_secrets` (Task 1) and `test_diagnose_sends_masked_payload` (Task 5).
4. **A command from a chat that is not the owner's, including "autorizo 1".** No reply and no action. Test: `test_non_owner_ignored` (Task 7).
5. **A report longer than 4096 chars, or an error text containing `<`, `&` or Markdown chars.** It is split and escaped, and Telegram does not reject it. Test: `test_render_splits_and_escapes` (Task 6).

---

## File Structure

```
ops-agent/
  pyproject.toml                 # uv project, console script `ops-agent = ops_agent.cli:main`
  README.md                      # Spanish: what it is, commands, how to deploy
  playbook/
    config.yaml                  # models, prices, cap, window, exclusions, thresholds
    revisiones.md                # Spanish, human-readable: what is checked and why
  src/ops_agent/
    config.py                    # load env + config.yaml → Settings
    masking.py                   # mask()
    n8n_client.py                # N8nClient (public API v1)
    collect.py                   # facts: activity, failures, clock freshness
    store.py                     # SQLite: issues, report items, costs, flags, runs
    diagnose.py                  # Sonnet diagnosis (structured output), cost cap
    report.py                    # template → list[str] Telegram HTML messages
    detail.py                    # Haiku "detalle N"
    telegram_io.py               # send_messages(); bot command handlers
    daily.py                     # run_daily() orchestration + heartbeat
    cli.py                       # `ops-agent run-daily | bot | whoami`
  tests/  (one test_<module>.py per module + fixtures/*.json)
  deploy/
    onems-ops-agent-bot.service
    onems-ops-agent-report.service
    onems-ops-agent-report.timer
    deploy.ps1                   # copy to server over SSH + uv sync + restart
  n8n/ops-agent-heartbeat-watch.json   # masked copy of the Task 9 workflow
```

---

### Task 1: Project scaffold, config and masking

**Files:**
- Create: `ops-agent/pyproject.toml`, `ops-agent/playbook/config.yaml`, `ops-agent/playbook/revisiones.md`, `ops-agent/src/ops_agent/{__init__,config,masking}.py`
- Test: `ops-agent/tests/test_config.py`, `ops-agent/tests/test_masking.py`

**Interfaces:**
- Produces:
  - `Settings` (pydantic model) with these fields: `n8n_api_url: str`, `n8n_api_key: SecretStr`, `anthropic_api_key: SecretStr`, `telegram_bot_token: SecretStr`, `owner_chat_id: int`, `heartbeat_url: str`, `heartbeat_secret: SecretStr`, `db_path: Path`, `timezone: str = "Europe/Madrid"`, `models: dict[str,str]`, `prices: dict[str, tuple[float,float]]`, `monthly_cap_eur: float`, `window_hours: int = 24`, `excluded_name_prefixes: list[str]`, `main_workflow_ids: dict[str,str]` (`{"prod":"IkVtek2csP5AbWxB","dev":"eeM4E4RS1UDThvUF"}`), `clock_grace_factor: float = 1.5`.
  - `load_settings(env: Mapping[str,str], config_path: Path) -> Settings`
  - `mask(value: Any) -> Any`. It works recursively on dicts, lists and strings.

- [ ] **Step 1: Create the branch.** Run `git -C "c:\Users\fernandezi\projects\ONE n8n\panelist_n8n" switch -c feat/ops-agent`, then `uv init --package --name ops-agent ops-agent`. Add the deps from the Tech Stack. Add the dev deps `pytest` and `pytest-asyncio`.
- [ ] **Step 2: Write the failing tests.**

```python
def test_load_settings_reads_env_and_yaml(tmp_path):
    s = load_settings(ENV_OK, CONFIG)          # ENV_OK has the 6 env vars
    assert s.models["diagnose"] == "claude-sonnet-5-5"
    assert s.monthly_cap_eur == 20
    assert s.main_workflow_ids["prod"] == "IkVtek2csP5AbWxB"
    assert "secret" not in repr(s)             # SecretStr hides values

def test_load_settings_missing_env_names_the_variable():
    with pytest.raises(ValueError, match="OWNER_CHAT_ID"):
        load_settings({k: v for k, v in ENV_OK.items() if k != "OWNER_CHAT_ID"}, CONFIG)

def test_mask_removes_secrets():
    raw = {"h": "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc", "k": "sk-ant-api03-XYZ123456789",
           "r": "re_AbCdEf123456789", "p": "0723836905", "t": "12345678:AAH4kL9xQwErTyUiOpAsDfGhJkL",
           "credentials": {"postgres": {"id": "735a8hxfuUEDPIYD"}}, "ok": "PAN-KEN-060"}
    m = mask(raw)
    flat = json.dumps(m)
    for leaked in ["eyJhbGci", "sk-ant-api03", "re_AbCdEf", "0723836905", "AAH4kL9x", "735a8hxfuUEDPIYD"]:
        assert leaked not in flat
    assert m["ok"] == "PAN-KEN-060"            # panelist codes survive
```

- [ ] **Step 3: Run the tests.** Run `uv run pytest tests/test_config.py tests/test_masking.py -v`. Expected: FAIL (import errors).
- [ ] **Step 4: Implement `load_settings` and `mask`.**
  - Env var names: `N8N_API_URL`, `N8N_API_KEY`, `ANTHROPIC_API_KEY`, `TELEGRAM_BOT_TOKEN`, `OWNER_CHAT_ID`, `HEARTBEAT_URL`, `HEARTBEAT_SECRET` (sent as header `X-Ops-Secret`), `OPS_AGENT_DB` (the last one defaults to `/var/lib/onems-ops-agent/agent.db`).
  - `mask` replaces these with `«oculto»`:
    - JWTs (`eyJ[\w-]+\.[\w-]+\.[\w-]+`)
    - `sk-`/`sk-ant-` keys
    - `re_` keys (≥12 chars)
    - Telegram bot tokens (`\d{6,}:[\w-]{30,}`)
    - phone numbers (`\+?\d{9,13}` not part of a longer token)
    - any value under a key named `credentials`, `password`, `token`, `apiKey`, `authorization` (case-insensitive)
  - Write `playbook/config.yaml` with the Global Constraints values.
  - Write `revisiones.md`: one Spanish paragraph per check in Task 3.
- [ ] **Step 5: Run the tests.** Expected: PASS.
- [ ] **Step 6: Commit.** Message: `feat(ops-agent): scaffold, settings and secret masking`.

### Task 2: n8n API client

**Files:**
- Create: `src/ops_agent/n8n_client.py`
- Test: `tests/test_n8n_client.py`, `tests/fixtures/executions_page{1,2}.json`, `tests/fixtures/execution_error.json`, `tests/fixtures/workflows.json`
  - Build the fixtures from real responses: fetch them with the n8n MCP tools against Cloud, run them through `mask`, and trim them to ≤20 items.

**Interfaces:**
- Produces:
  - `Execution` dataclass: `id: str, workflow_id: str, status: Literal["success","error","waiting","running","canceled","crashed"], mode: str, started_at: datetime, stopped_at: datetime | None`
  - `Workflow` dataclass: `id, name, active: bool, archived: bool, tags: list[str], nodes: list[dict]`
  - `ExecutionDetail` dataclass: `execution: Execution, error_node: str | None, error_message: str | None, error_node_type: str | None, error_node_parameters: dict, trigger_payload: dict`
  - `class N8nClient(base_url: str, api_key: str, transport: httpx.BaseTransport | None = None)` with these methods:
    - `list_workflows() -> list[Workflow]`
    - `list_executions_since(since: datetime, workflow_id: str | None = None, status: str | None = None) -> list[Execution]`
    - `get_execution_detail(execution_id: str) -> ExecutionDetail`
  - `N8nError(Exception)`

- [ ] **Step 1: Write the failing tests.** Use `httpx.MockTransport`.

```python
def test_list_executions_since_paginates_and_stops_at_window():
    # page1: 3 items inside window + nextCursor; page2: 1 inside, 1 older than `since`
    ex = client.list_executions_since(since=T0)
    assert [e.id for e in ex] == ["105", "104", "103", "102"]
    assert requests_made == 2

def test_api_key_sent_in_header_and_never_in_url():
    client.list_workflows()
    assert last_request.headers["X-N8N-API-KEY"] == "k"
    assert "k" not in str(last_request.url)

def test_get_execution_detail_extracts_error_node():
    d = client.get_execution_detail("16701")
    assert d.error_node == "Send ask receipt msg"
    assert "ECONNRESET" in d.error_message

def test_http_500_raises_n8nerror():
    with pytest.raises(N8nError): client.list_workflows()
```

- [ ] **Step 2: Run the tests.** Run `uv run pytest tests/test_n8n_client.py -v`. Expected: FAIL.
- [ ] **Step 3: Implement `N8nClient`.**
  - It uses the public API v1: `GET /api/v1/workflows?limit=100&cursor=`, `GET /api/v1/executions?limit=250&cursor=&workflowId=&status=` and `GET /api/v1/executions/{id}?includeData=true`.
  - Executions come newest first. Stop paginating once an item has `startedAt < since`.
  - Set timeout 30 s, with 2 retries on connect errors and 5xx.
  - Read the error node from `data.resultData.error.node.name` and the message from `data.resultData.error.message`, falling back to `lastNodeExecuted`.
  - Read node parameters from the workflow node of that name. `trigger_payload` is the first item of the first trigger node's output.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit.** Message: `feat(ops-agent): n8n public API client`.

### Task 3: Fact collectors

**Files:**
- Create: `src/ops_agent/collect.py`
- Test: `tests/test_collect.py`

**Interfaces:**
- Consumes: `N8nClient`, `Execution`, `Workflow`, `ExecutionDetail`, `Settings`, `mask`
- Produces:
  - `Failure` dataclass, with fingerprint `= f"{workflow_id}|{node}|{normalize(message)}"`:
    - `fingerprint: str, workflow_id: str, workflow_name: str, env: Literal["PROD","DEV"], node: str, message: str`
    - `count: int, first_at: datetime, last_at: datetime, sample_execution_id: str`
    - `panelists: list[str]` (first names or codes found in trigger payloads, max 5)
  - `ClockStatus` dataclass: `workflow_id, workflow_name, env, expected_every: timedelta, last_run: datetime | None, late: bool`
  - `Activity` dataclass: `bot_messages: int, bot_errors: int` (PROD main workflow only)
  - `Facts` dataclass: `window_start: datetime, window_end: datetime, activity: Activity | None, failures: list[Failure], clocks: list[ClockStatus], could_not_check: list[str]`
  - `normalize(message: str) -> str`. It replaces digits runs, UUIDs, quoted values and execution ids with `#`.
  - `collect_facts(client: N8nClient, settings: Settings, now: datetime) -> Facts`. It never raises; each sub-collector failure is appended to `could_not_check` in Spanish ("ejecuciones de n8n", "procesos automáticos", "detalle de los fallos").
  - `expected_interval(trigger_node: dict) -> timedelta | None`. It parses `n8n-nodes-base.scheduleTrigger` `rule.interval[]`: `field` in minutes, hours, days, weeks, with `*Interval`, or `cronExpression` via `croniter`, taking the gap between the next 2 fires. It returns `None` for non-schedule triggers.

- [ ] **Step 1: Write the failing tests.**

```python
def test_group_failures_collapses_same_fingerprint():
    # 30 error executions of IkVtek2csP5AbWxB, node "Send receipt result", "invalid syntax"
    facts = collect_facts(fake_client_30_same, S, NOW)
    assert len(facts.failures) == 1
    f = facts.failures[0]
    assert f.count == 30 and f.env == "PROD" and f.node == "Send receipt result"

def test_normalize_ignores_ids_and_numbers():
    assert normalize('invalid input syntax for type uuid: "null" at 16842') == \
           normalize('invalid input syntax for type uuid: "abc" at 99')

def test_env_from_name_prefix():
    # "[DEV] Mark Parcel as received" → DEV, "Mark Parcel as received" → PROD

def test_excluded_and_inactive_workflows_skipped():
    # "[BACKUP 2026-04-29] …", "_temp_read_accounts", archived → not in clocks/failures

def test_clock_late_when_last_run_older_than_grace():
    # every 6h, last run 10h ago, grace 1.5 → late=True; 8h ago → late=False

def test_expected_interval_parses_hours_and_cron():
    assert expected_interval(SCHED_HOURS_6) == timedelta(hours=6)
    assert expected_interval(SCHED_CRON_DAILY_9) == timedelta(days=1)

def test_collector_failure_goes_to_could_not_check():
    facts = collect_facts(client_raising_on_executions, S, NOW)
    assert "ejecuciones de n8n" in facts.could_not_check and facts.activity is None

def test_panelists_from_trigger_payload_are_first_names_only():
    assert facts.failures[0].panelists == ["Ana"]
```

- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - The environment is DEV if the workflow name starts with `[DEV]`; otherwise it is PROD.
  - Get detail once per new fingerprint, using the first execution only. This caps API calls at roughly the number of distinct failures plus pages.
  - Panelist name comes from `trigger_payload.message.from.first_name` or `callback_query.from.first_name`.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit.** Message: `feat(ops-agent): collect failures, activity and clock freshness`.

### Task 4: State store

**Files:**
- Create: `src/ops_agent/store.py`
- Test: `tests/test_store.py`

**Interfaces:**
- Produces: `class Store(db_path: Path)`, which creates its schema on open. Methods:
  - `sync_issues(failures: list[Failure], report_date: date) -> list[IssueView]`
    - It upserts by fingerprint and marks issues not seen in this window as resolved.
    - It returns the open issues followed by those resolved today.
    - Each one is numbered 1..N for this report and the numbering is persisted.
  - `IssueView` dataclass: `number: int, fingerprint: str, state: Literal["nuevo","sigue","resuelto"], days_open: int, failure: Failure | None, diagnosis: Diagnosis | None`
  - `get_item(report_date: date, number: int) -> IssueView | None`
  - `latest_report_date() -> date | None`
  - `save_diagnosis(fingerprint: str, d: Diagnosis) -> None` and `get_diagnosis(fingerprint: str) -> Diagnosis | None`
  - `add_cost(model: str, input_tokens: int, output_tokens: int, usd: float, at: datetime) -> None` and `month_cost(at: datetime) -> float`
  - `set_paused(flag: bool) -> None` and `is_paused() -> bool`
  - `record_run(started: datetime, finished: datetime, sent: bool, summary: str) -> None` and `last_run() -> dict | None`

- [ ] **Step 1: Write the failing tests.**

```python
def test_new_then_ongoing_then_resolved(tmp_path):
    st = Store(tmp_path/"a.db")
    v1 = st.sync_issues([F1], date(2026,11,5)); assert v1[0].state == "nuevo"
    v2 = st.sync_issues([F1], date(2026,11,6)); assert v2[0].state == "sigue" and v2[0].days_open == 2
    v3 = st.sync_issues([],   date(2026,11,7)); assert v3[0].state == "resuelto"
    assert st.sync_issues([], date(2026,11,8)) == []   # resolved shown once

def test_numbering_is_stable_for_the_day_and_lookup_works(tmp_path):
    views = st.sync_issues([F1, F2], D); assert [v.number for v in views] == [1, 2]
    assert st.get_item(D, 2).fingerprint == F2.fingerprint

def test_month_cost_sums_only_current_month(tmp_path): ...
def test_pause_flag_persists_across_instances(tmp_path): ...
```

- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement `Store` with stdlib `sqlite3`.** Use WAL mode. The tables are `issues`, `report_items(report_date, number, fingerprint)`, `diagnoses`, `costs`, `flags` and `runs`.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit.** Message: `feat(ops-agent): sqlite store for issues, costs and flags`.

### Task 5: Diagnosis with Sonnet

**Files:**
- Create: `src/ops_agent/diagnose.py`
- Test: `tests/test_diagnose.py`

**Interfaces:**
- Consumes: `Failure`, `ExecutionDetail`, `Store`, `Settings`, `mask`
- Produces:
  - `Diagnosis` (pydantic):
    - `cause: str` (Spanish, ≤300 chars)
    - `fix: str` (Spanish, ≤400 chars; exactly what would change)
    - `fix_kind: Literal["n8n","base_de_datos","externo","ninguno"]`
    - `confidence: Literal["alta","media","baja"]`
  - `diagnose(failure: Failure, detail: ExecutionDetail, settings: Settings, store: Store, llm: LLM) -> Diagnosis | None`
    - It returns the cached diagnosis when the fingerprint already has one.
    - It returns `None` without calling the API when `store.month_cost(now) >= settings.monthly_cap_eur`.
    - It records cost after every call.
  - `LLM` Protocol: `parse(model: str, system: str, user: str, schema: type[BaseModel]) -> tuple[BaseModel, int, int]`, returning (result, input_tokens, output_tokens).
  - `AnthropicLLM(api_key)` implements `LLM` with `client.messages.parse(..., output_format=schema)`.
    - Confirm the exact structured-output parameter in the `anthropic` 1.x README before writing it. Do not guess.
    - Use the default effort, `max_tokens=4000`.
    - Use no `temperature`; it is rejected on current models.

- [ ] **Step 1: Write the failing tests.** Use a `FakeLLM` that records its calls.

```python
def test_diagnose_sends_masked_payload():
    diagnose(F_WITH_SECRET, DETAIL_WITH_TOKEN, S, st, fake)
    assert "AAH4kL9x" not in fake.calls[0].user and "eyJ" not in fake.calls[0].user
    assert fake.calls[0].model == "claude-sonnet-5-5"

def test_diagnose_cached_per_fingerprint():
    diagnose(F1, D1, S, st, fake); diagnose(F1, D1, S, st, fake)
    assert len(fake.calls) == 1

def test_diagnose_skipped_when_over_cap():
    st.add_cost("claude-sonnet-5-5", 0, 0, usd=20.0, at=NOW)
    assert diagnose(F2, D2, S, st, fake) is None and fake.calls == []

def test_cost_recorded_with_config_prices():
    # fake returns 10_000 in / 1_000 out → 0.02 + 0.01 = 0.03 USD
    assert st.month_cost(NOW) == pytest.approx(0.03)
```

- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - The system prompt is fixed: Spanish, aimed at a non-programmer owner. It describes the ONEMS panelist bot, the rules (no DB changes from Telegram, DEV before PROD, never raise schedule frequency) and the instruction to propose the smallest exact change.
  - The user message holds the masked `failure`, the error node type, the masked node parameters and the masked trigger payload, trimmed to 20,000 chars.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit.** Message: `feat(ops-agent): sonnet diagnosis with cache and monthly cap`.

### Task 6: Report rendering

**Files:**
- Create: `src/ops_agent/report.py`
- Test: `tests/test_report.py`

**Interfaces:**
- Consumes: `Facts`, `IssueView`, `Store.month_cost`, `Settings`
- Produces: `render_report(facts: Facts, items: list[IssueView], month_cost_eur: float, settings: Settings, now: datetime, paused: bool = False) -> list[str]`. It returns Telegram HTML messages, each ≤4000 chars.
- Format. The values are fixed by the spec §10. Times are shown in Europe/Madrid.
  - Line 1:
    - `✅ Todo funciona — dd/mm · HH:MM` when there are no open items, no late clocks and nothing in `could_not_check`;
    - otherwise `⚠️ N problemas — dd/mm · HH:MM`.
  - `Bot: {bot_messages} mensajes de panelistas en 24 h, {bot_errors} fallos.`
  - `Procesos automáticos: {ok}/{total} a su hora.` Then one line per late clock.
  - Numbered items:
    - `{n}. {NUEVO|SIGUE (d días)|RESUELTO} · {workflow_name} — {node}: {count} veces ({first}–{last})`
    - then `Causa: …` and `Arreglo: …` when there is a diagnosis
    - `[DEV]` items go after PROD items under a `DEV:` subheading.
  - `No pude comprobar: …` when the list is not empty.
  - A cost line only at ≥80 % of the cap, or `diagnóstico IA pausado por tope de gasto` at 100 %.
  - Footer: `Escribe «detalle N» para ampliar.`

- [ ] **Step 1: Write the failing tests.**

```python
def test_all_ok_headline():
    msgs = render_report(FACTS_OK, [], 0.4, S, NOW)
    assert msgs[0].startswith("✅ Todo funciona — 05/11 · 08:00")

def test_problem_item_lines():
    m = "".join(render_report(FACTS_1_FAIL, [ITEM_NEW_DIAG], 0.4, S, NOW))
    assert "1. NUEVO · Parcels to receive — Get allocation plans: 1 veces" in m
    assert "Causa:" in m and "Arreglo:" in m

def test_render_splits_and_escapes():
    items = [item_with_message("<b>&" + "x"*900) for _ in range(10)]
    msgs = render_report(FACTS_MANY, items, 0.4, S, NOW)
    assert all(len(x) <= 4000 for x in msgs) and len(msgs) > 1
    assert "&lt;b&gt;&amp;" in "".join(msgs)

def test_could_not_check_listed(): ...
def test_cap_warning_at_80_percent(): ...
```

- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit.** Message: `feat(ops-agent): spanish report template`.

### Task 7: Telegram bot and commands

**Files:**
- Create: `src/ops_agent/telegram_io.py`, `src/ops_agent/detail.py`
- Test: `tests/test_telegram_io.py`, `tests/test_detail.py`

**Interfaces:**
- Consumes: `Store`, `Settings`, `LLM`, `mask`, `run_daily` (Task 8, injected as a callable to avoid an import cycle)
- Produces:
  - `parse_command(text: str) -> tuple[str, int | None] | None`. It accepts exactly `detalle N`, `pausa`, `sigue`, `estado`, `informe`, `autorizo N` and `deshaz N`, case-insensitive, with surrounding spaces trimmed. Anything else gives `None`.
  - `handle_command(chat_id: int, text: str, ctx: BotContext) -> str | None`. It returns the reply text, or `None` meaning "ignore".
  - `BotContext` dataclass: `settings, store, llm, run_daily: Callable[[], Awaitable[None]], now: Callable[[], datetime]`
  - `send_messages(token: str, chat_id: int, messages: list[str]) -> None` (async, HTML)
  - `run_bot(ctx: BotContext) -> None`. This is long polling with `python-telegram-bot`. It wires `handle_command` and replies to unknown text with `Comandos: detalle N · pausa · sigue · estado · informe`.
  - `explain_detail(item: IssueView, settings, store, llm) -> str`, in `detail.py`. Haiku writes a ≤1200-char plain-Spanish expansion from the masked item and diagnosis. It falls back to the raw item text when over the cap or on API error.
- Replies (Spanish, fixed):
  - `pausa` → `En pausa: no haré pruebas ni arreglos hasta que escribas «sigue».`
  - `sigue` → `Reanudado.`
  - `estado` → the last run time, whether it was sent, the month cost and whether it is paused
  - `informe` → `Preparando el informe…`, then it calls `run_daily()`
  - `autorizo N` / `deshaz N` → `Los arreglos automáticos llegan en la fase 3. Por ahora, abre una sesión con Claude para aplicarlo.`
  - `detalle N` with no such item → `No hay punto N en el último informe.`

- [ ] **Step 1: Write the failing tests.**

```python
def test_non_owner_ignored():
    assert handle_command(999, "autorizo 1", CTX) is None
    assert handle_command(999, "pausa", CTX) is None and CTX.store.is_paused() is False

def test_parse_command_exact_forms():
    assert parse_command(" Detalle 2 ") == ("detalle", 2)
    assert parse_command("autoriza 1") is None and parse_command("detalle") is None

def test_pause_and_resume_owner():
    handle_command(OWNER, "pausa", CTX); assert CTX.store.is_paused()
    handle_command(OWNER, "sigue", CTX); assert not CTX.store.is_paused()

def test_detalle_uses_haiku_and_latest_report():
    r = handle_command(OWNER, "detalle 1", CTX)
    assert fake.calls[-1].model == "claude-haiku-5-5" and r

def test_authorize_not_available_in_phase1(): ...
```

`handle_command` can be sync. If it is, `run_bot` adapts it. Mark `informe` tests `asyncio` if needed.

- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Log every ignored chat id at WARNING without the message text.
  - In phase 1, `pausa` only sets the flag. The report still runs and adds the line `⏸️ En pausa (pruebas y arreglos detenidos).` It is produced by `render_report(..., paused=True)` (Task 6; add `test_paused_line` there).
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit.** Message: `feat(ops-agent): owner-only telegram commands`.

### Task 8: Daily run, CLI and heartbeat

**Files:**
- Create: `src/ops_agent/daily.py`, `src/ops_agent/cli.py`
- Test: `tests/test_daily.py`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `async run_daily(settings, store, client, llm, sender, now) -> bool`. The steps are:
    1. `collect_facts`
    2. `store.sync_issues(facts.failures, today_madrid)`
    3. `diagnose` each item with state `nuevo` or no diagnosis
    4. `render_report`
    5. `sender(messages)`
    6. POST `{"date": "YYYY-MM-DD", "sent": true}` to `settings.heartbeat_url` (timeout 10 s, failure logged and not raised)
    7. `store.record_run`
  - It returns True if the messages were sent. Any exception before sending results in a minimal message `⚠️ El agente falló al preparar el informe: {tipo de error}` and no heartbeat, which lets the 08:30 alarm also fire.
  - `cli.main()` has these subcommands:
    - `run-daily`
    - `bot`
    - `whoami`, which starts polling and prints the chat id of the first message received, so the owner's chat id can be found. It prints only the id.

- [ ] **Step 1: Write the failing tests.**

```python
async def test_run_daily_happy_path_sends_and_heartbeats(): 
    ok = await run_daily(S, st, fake_client, fake_llm, sender, NOW)
    assert ok and sender.sent and heartbeat.posted == [{"date": "2026-11-05", "sent": True}]

async def test_run_daily_n8n_down_sends_partial_report():
    ok = await run_daily(S, st, client_all_500, fake_llm, sender, NOW)
    assert ok and "No pude comprobar" in "".join(sender.sent[0])

async def test_run_daily_crash_sends_minimal_message_and_no_heartbeat(): ...
async def test_heartbeat_failure_does_not_fail_run(): ...
```

- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the full suite.** Run `uv run pytest -v`. Expected: all PASS.
- [ ] **Step 5: Do a dry run against real n8n Cloud with read-only calls.**
  - Run `uv run ops-agent run-daily --dry-run`, which prints the messages instead of sending them and skips the heartbeat.
  - Add the `--dry-run` flag in this step.
  - Set the env vars from the user variables `N8N_API_KEY` and `N8N_API_URL=https://upu-one.app.n8n.cloud`.
  - Expected: a Spanish report that matches the 05/11 manual review in shape, with no secrets in the output (check with `rg -n "eyJ|sk-ant|re_[A-Za-z0-9]{10}"` over the output).
- [ ] **Step 6: Commit.** Message: `feat(ops-agent): daily orchestration, cli and heartbeat`.

### Task 9: n8n heartbeat watch workflow

**Files:**
- Create: `ops-agent/n8n/ops-agent-heartbeat-watch.json`, a masked export.

**Interfaces:**
- Produces:
  - The n8n workflow `Ops agent heartbeat watch` has two triggers sharing `$getWorkflowStaticData('global')`:
    - a Webhook `POST /webhook/ops-agent-heartbeat` with header auth, using the secret in a new n8n credential;
    - a Schedule Trigger daily at **08:30 Europe/Madrid**.
  - It needs the workflow setting `timezone: Europe/Madrid`. Check the instance timezone first.
  - The webhook stores `lastDate`.
  - The schedule fires and, if `lastDate != today`, sends via the **agent's bot** (new Telegram credential "Ops agent bot") to `OWNER_CHAT_ID`: `⚠️ Son las 8:30 y el agente de operaciones no ha enviado el informe de hoy. Revisa el servidor.`
  - `HEARTBEAT_URL` is the production webhook URL; `HEARTBEAT_SECRET` (Task 1) is the value of the Header Auth credential.

- [ ] **Step 1: The owner creates the credentials in the n8n UI**, so the secrets never pass through the chat:
  - a Telegram credential "Ops agent bot" with the new bot token;
  - a Header Auth credential "Ops agent heartbeat" (`X-Ops-Secret`).
- [ ] **Step 2: Create the workflow inactive** using the n8n MCP tools, then validate it with `n8n_validate_workflow`.
- [ ] **Step 3: Test it.**
  - Run the schedule branch manually with no heartbeat stored. Expected: the alarm reaches the owner.
  - POST a heartbeat, then run it again. Expected: no message.
  - Then activate the workflow. It costs 2 executions per day.
- [ ] **Step 4: Export, mask and commit.** Export the workflow, run `mask` on the JSON and commit `ops-agent/n8n/ops-agent-heartbeat-watch.json`. Message: `feat(ops-agent): n8n heartbeat watch`.

### Task 10: Deploy to Hetzner

**Files:**
- Create: `deploy/onems-ops-agent-bot.service`, `deploy/onems-ops-agent-report.service`, `deploy/onems-ops-agent-report.timer`, `deploy/deploy.ps1`, `README.md`

**Interfaces:**
- Server facts:
  - servidor Hetzner (datos de acceso fuera del repositorio).
  - Shared with the `nms-scraper`, `scraper-qcs` and `/opt/n8n` services: **do not touch them, and do not change `sslh`, Caddy or SSH config.**
- Layout:
  - code in `/opt/onems-ops-agent` (owner `opsagent`, a new system user with no login);
  - env in `/etc/onems-ops-agent/env` (`root:opsagent 0640`);
  - DB in `/var/lib/onems-ops-agent/agent.db`.
- Add `/var/lib/onems-ops-agent` to the existing daily backup in `/etc/cron.d/n8n-backup`. Read that script first and change only the path list.
- Units:
  - the bot service runs `uv run ops-agent bot` with `Restart=always`;
  - the report service is `Type=oneshot` and runs `uv run ops-agent run-daily`;
  - the timer uses `OnCalendar=*-*-* 08:00:00 Europe/Madrid` and `Persistent=true`.

- [ ] **Step 1: The owner creates three things:**
  1. a bot with @BotFather;
  2. a new n8n API key labelled "ops-agent";
  3. an Anthropic API key for the agent, with a **monthly spend limit of 20 USD set in the Anthropic Console**.

  The owner writes the values directly into `/etc/onems-ops-agent/env` over SSH using a template that `deploy.ps1` places there. They are never pasted into the chat.
- [ ] **Step 2: Write `deploy.ps1`.** It copies `ops-agent/` without `tests/` and `.venv`, using `scp -i`. It then runs over `ssh`: create the user and dirs if missing, install `uv` for `opsagent` if missing, `uv sync --frozen`, install the units, `systemctl daemon-reload`, then `enable --now onems-ops-agent-bot.service onems-ops-agent-report.timer`.
- [ ] **Step 3: Find the owner's chat id.** Run `ssh … sudo -u opsagent … ops-agent whoami`. The owner writes "hola" to the new bot and the printed id goes into `OWNER_CHAT_ID`.
- [ ] **Step 4: Verify.**
  - Run `systemctl list-timers onems-ops-agent-report.timer`. Expected: the next run is at 08:00 CET/CEST.
  - The owner sends `estado`. Expected: a reply.
  - The owner sends `informe`. Expected: the report arrives in Telegram, and the heartbeat watch shows today's date.
  - Confirm `nms-scraper` and `scraper-qcs` are still active.
- [ ] **Step 5: Commit** `deploy/` and the README. Message: `feat(ops-agent): hetzner deployment`. Report to the owner. Wait for their order before pushing or merging.
