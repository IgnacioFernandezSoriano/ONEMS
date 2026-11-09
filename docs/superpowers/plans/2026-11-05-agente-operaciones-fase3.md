# Agente de operaciones, fase 3 — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el responsable autorice desde Telegram arreglos sencillos de n8n (DEV → PROD con doble sí) y tres reparaciones de datos cerradas (R1–R3), con copia, verificación y `deshaz`, más la orden `revisa ahora`.

**Architecture:**
- **El LLM propone y el código aplica.**
  - Al diagnosticar, la IA devuelve además un cambio estructurado (`FixProposal`).
  - El código comprueba que es «sencillo». Después lo aplica en n8n reescribiendo el flujo entero (PUT), solo si la versión del flujo no ha cambiado.
- **Las reparaciones de datos son funciones SQL nuevas.**
  - Llevan el prefijo `ops_fix_*` y van protegidas con el mismo token y el mismo `ops_test._check` de la fase 2.
  - Cada función guarda el estado anterior en `ops_fix.log`, y su `undo` lo restaura.
- **Cada arreglo es una fila de SQLite del agente** (`fixes`) con estado persistente. El bot de Telegram la va moviendo de estado según los botones que pulsa el responsable.

**Tech Stack:**
- Python 3.12+, uv, pytest, httpx, pydantic, python-telegram-bot y Telethon, como en las fases 1 y 2.
- Postgres/Supabase (plpgsql).
- API pública v1 de n8n.

**Spec:** `docs/superpowers/specs/2026-11-05-agente-operaciones-fase3-design.md`. Amplía el diseño base `docs/superpowers/specs/2026-11-05-agente-operaciones-design.md`.

**Repos:**
- **Código del agente:** repo `panelist_n8n`, carpeta `ops-agent/`, rama nueva `feat/ops-agent-fase3` desde `main`.
- **Migraciones y tests SQL:** repo `ONEMS`, rama `develop`.

## Global Constraints

- Base de datos única: onems-dev `sehbnpgzqljrsqimwyuz`. Antes de aplicar cualquier migración en remoto, PARADA: nombrar el proyecto y el ref, y pedir confirmación. Nunca `db push` ni `db reset`.
- **Accesos del agente:**
  - En la base, el agente no tiene service_role. Solo usa funciones `ops_fix_*` con permiso `GRANT EXECUTE` a `anon`, con `p_token`, `SECURITY DEFINER` y `SET search_path = ''`.
  - En n8n, solo hace PUT de flujos que ya existen. Nunca crea, borra, activa ni desactiva flujos.
  - En Telegram, la cuenta de prueba solo habla con `TESTER_BOT_USERNAME` (bot PROD) y `TESTER_DEV_BOT_USERNAME` (bot DEV).
- **Qué cuenta como «n8n sencillo»:**
  - como máximo 3 nodos de un mismo flujo;
  - solo cambia `parameters` de nodos que ya existen;
  - no toca credenciales, nodos disparadores de reloj (`*.scheduleTrigger`, `*.cron`), conexiones ni la lista de nodos.
- **Vida de las autorizaciones:**
  - el primer `autorizo` caduca con el siguiente informe de las 8:00;
  - el sí para PROD dura 24 h desde que DEV quedó probado;
  - si ese sí caduca, el agente restaura DEV.
- `revisa ahora` se puede usar como máximo 3 veces por día de Madrid, sin contar el informe de las 8:00.
- **Textos al responsable:**
  - en español llano;
  - nunca claves;
  - de los panelistas, solo código y nombre.
  - Al pedir permiso para una reparación de datos, nombrar «onems-dev (`sehbnpgzqljrsqimwyuz`)».
- **Repo `panelist_n8n`:** sin nombres reales y sin claves.
- **Pausa:** `pausa` bloquea `autorizo`, los botones de aplicar y `revisa ahora`. `deshaz` sigue permitido.
- **Tests:** `cd ops-agent && uv run pytest -q` tiene que acabar en verde en cada tarea. Los SQL se validan con `supabase/tests/replay_baseline.ps1` más el `.test.sql` de la tarea, en el Postgres local 127.0.0.1:5433.

## Review Focus

1. **Alguien edita el flujo en la UI de n8n** entre la copia y el PUT, o entre el arreglo y el `deshaz`. El agente no debe escribir nada y debe decirlo. Test en Task 4 y Task 7.
2. **El flujo propuesto no tiene copia [DEV]**, o la copia DEV y la PROD no coinciden. En ese caso no se ofrece `autorizo`, y sale «para sesión con Claude». Ojo: «Parcels to receive» es compartido por los bots DEV y PROD. Test en Task 3.
3. **Pulsar dos veces el mismo botón**, o pulsar uno de un arreglo caducado. No debe aplicarse dos veces ni volver un arreglo a la vida. Test en Task 7.
4. **Hay una pausa activa mientras un arreglo espera el sí de PROD.** El botón de PROD se rechaza, pero la caducidad de 24 h sigue corriendo y DEV se restaura. Test en Task 7.
5. **R3 encuentra que alguien ha tocado un envío movido** antes del `deshaz` (lo ha declarado o cambiado de fecha). Ese envío no se toca, el resto sí se restaura, y el mensaje lo dice. Test en Task 1.

---

### Task 1: Reparaciones de datos en la BD (R1–R3) y nuevos avisos

**Files:**
- Create: `ONEMS/supabase/migrations/20261106090000_ops_agent_fixes.sql`
- Create: `ONEMS/supabase/tests/ops_agent_fixes.test.sql`, reutilizando `fixtures/incident_city.sql` como en `ops_operational_checks.test.sql`.
- Modify: `ops_test_checks`, dentro de la misma migración. Se redefine con `CREATE OR REPLACE` y añade dos listas nuevas.

**Interfaces (todas reciben `p_token text` primero y devuelven `jsonb`):**
- **Tabla `ops_fix.log`:**
  - columnas: `id bigserial`, `kind text` (r1/r2/r3), `account_id uuid`, `target text`, `before jsonb`, `after jsonb`, `applied_at timestamptz`, `undone_at timestamptz`;
  - sin acceso para `anon` ni `authenticated`.
- **R1, desatascar conversación:**
  - `ops_fix_r1_preview(p_token, p_panelist_code text)` devuelve `{panelist, account, contexts:[{context_type, created_at}]}`.
  - `ops_fix_r1_apply(p_token, p_panelist_code)` borra las filas de `panelist_context` de su `telegram_id` y devuelve `{log_id, deleted}`.
  - No tiene `undo`.
- **R2, asignar nodo:**
  - `ops_fix_r2_preview(p_token, p_panelist_code)` devuelve `{panelist, account, city, node}` o lanza `ops_fix: no aplicable (<motivo>)`.
  - Es aplicable solo si se cumplen tres condiciones: el panelista está activo, su `node_id` es NULL, y en su ciudad hay exactamente 1 nodo activo de su misma cuenta.
  - `ops_fix_r2_apply(p_token, p_panelist_code)` devuelve `{log_id, node}`.
  - `ops_fix_r2_undo(p_token, p_log_id bigint)` vuelve a poner NULL, solo si el `node_id` sigue siendo el que puso.
- **R3, rellenar POBOX:**
  - `ops_fix_r3_preview(p_token, p_account text, p_city text)` llama a `rpc_balance_city_v2(city_id, hoy, fin_del_plan, false, hoy)` y devuelve `{city, moves:[{tag_id|id, from, to}], count}`.
  - `ops_fix_r3_apply(p_token, p_account, p_city)`, en una sola transacción:
    1. guarda en `before` la fila completa (`to_jsonb`) de cada fila `pending` de esa ciudad y de cualquier otra tabla que escriba el balanceo;
    2. llama a la función con `p_apply_changes = true`;
    3. guarda en `after` las filas resultantes;
    4. devuelve `{log_id, moves}`.
  - `ops_fix_r3_undo(p_token, p_log_id)` restaura las filas cuyo estado actual es igual a su `after`, y devuelve `{restored, skipped:[ids]}`.
  - «Hoy» es la fecha local de la cuenta (`accounts.timezone`). R3 solo es aplicable si la ciudad aparece hoy en `pobox_no_send`.
- **`ops_test_checks`** añade:
  - `panelist_no_node: [{account, panelist (código), city}]`: activos, con `telegram_id` y `node_id` NULL.
  - `stuck_context: [{account, panelist, since}]`: panelistas activos con alguna fila de `panelist_context` de hace más de 24 h.
- **Todas:** un token malo lanza `ops_test: token no valido`. Las cuentas se resuelven por nombre (`accounts.name`) y los panelistas por `panelists.auto_id`.

- [ ] **Step 1: Leer `rpc_balance_city_v2`** (`supabase/migrations/20261102072347_pobox_receipt_after_absence.sql`, desde la línea 297) y anotar en el `.test.sql` cada tabla y columna que escribe.
  - Con una llamada interna, `auth.uid()` es NULL y la función la deja pasar.
  - Además de cambiar fechas, puede convertir filas `pobox` en `compensation` y mandar muestras al registro.
- [ ] **Step 2: Escribir `ops_agent_fixes.test.sql`**, siguiendo el patrón de `fail_if`. Cada caso es una comprobación:
  - R1 borra solo las filas del panelista indicado.
  - R2 en un panelista que ya tiene nodo lanza `no aplicable`.
  - R2 en una ciudad con 2 nodos activos lanza `no aplicable`.
  - R2 `apply` seguido de `undo` deja `node_id` NULL.
  - Si `node_id` se cambia a mano entre medias, el `undo` no lo toca.
  - R3 sobre `City2` (POBOX, 1 nodo, días sin envío): `preview.count` > 0, y después de `apply`, `pobox_no_send` ya no la incluye.
  - R3: si se marca a mano como `sent` uno de los envíos movidos, el `undo` lo devuelve en `skipped` y restaura el resto.
  - Ninguna fila de otra cuenta cambia: se compara `md5(string_agg)` antes y después.
  - `ops_test_checks` devuelve las 2 listas nuevas con un caso cada una.
  - `authenticated` no tiene EXECUTE sobre ninguna `ops_fix_*`.
  - Un token malo es rechazado.
- [ ] **Step 3: Ejecutar** `supabase/tests/replay_baseline.ps1` y el test sin la migración. Expected: FALLA porque `ops_fix_r1_preview` no existe.
- [ ] **Step 4: Escribir la migración.**
- [ ] **Step 5: Ejecutar de nuevo.** Expected: `ops_agent_fixes OK`, y `ops_operational_checks OK` sigue pasando.
- [ ] **Step 6: Commit** en ONEMS `develop`: `feat(ops-agent): reparaciones R1-R3 con copia y deshacer para el agente`.

### Task 2: Cliente de reparaciones y avisos nuevos en el informe

**Files:**
- Modify: `ops-agent/src/ops_agent/fixtures.py`. Generalizar `_call(name, **params)`: el nombre de la función pasa a ser completo, o se añade un prefijo.
- Create: `ops-agent/src/ops_agent/repairs.py`
- Modify: `ops-agent/src/ops_agent/daily.py`, en `operational_failures` y los diagnósticos fijos.
- Test: `ops-agent/tests/test_repairs.py`, `ops-agent/tests/test_operational_checks.py`

**Interfaces:**
- **Consume:** las funciones SQL de Task 1.
- **Produce:**
  - `class RepairClient(FixtureClient)` con:
    - `preview(kind: Literal["r1","r2","r3"], target: RepairTarget) -> dict`
    - `apply(kind, target) -> dict`
    - `undo(kind, log_id: int) -> dict`
    - `undo` lanza `RepairError("R1 no se puede deshacer")` si `kind == "r1"`.
  - `@dataclass RepairTarget(account: str, panelist: str | None = None, city: str | None = None)`
  - Huellas nuevas de los problemas: `operativa|sin_nodo|<cuenta>|<código>` y `operativa|atascado|<cuenta>|<código>`.
  - `REPAIR_FOR_PREFIX: dict[str, str] = {"operativa|pobox|": "r3", "operativa|sin_nodo|": "r2", "operativa|atascado|": "r1"}`
  - `repair_target(fingerprint: str) -> tuple[str, RepairTarget] | None`

- [ ] **Step 1: Tests en `test_repairs.py`:**
  - `test_preview_posts_token_kind_and_target`: con MockTransport, la ruta es `/rest/v1/rpc/ops_fix_r2_preview` y el body es `{"p_token":"tok-largo","p_panelist_code":"PAN-DEM-003"}`.
  - `test_r1_undo_refused_locally`
  - `test_not_applicable_message_is_passed_through`: un error `ops_fix: no aplicable (ciudad con 2 nodos)` aparece en `RepairError`.
  - `test_repair_target_maps_fingerprints`: `repair_target("operativa|pobox|KENYA|Moyale") == ("r3", RepairTarget("KENYA", city="Moyale"))`.
- [ ] **Step 2: Tests en `test_operational_checks.py`:**
  - `test_operational_failures_include_no_node_and_stuck`: las dos listas nuevas producen una Failure cada una, con las huellas de arriba.
- [ ] **Step 3:** `uv run pytest tests/test_repairs.py tests/test_operational_checks.py -q`. Expected: FAIL (ImportError).
- [ ] **Step 4: Implementar.** Los diagnósticos fijos nuevos van en `daily.py`, igual que `POBOX_DIAGNOSIS`, con `fix_kind="base_de_datos"`:
  - para `sin_nodo`: «asignarle el único nodo de su ciudad»;
  - para `atascado`: «borrar su conversación guardada para que el bot empiece de cero».
  - Cambiar el `fix` de `POBOX_DIAGNOSIS` por «volver a balancear esa ciudad (el agente puede hacerlo: autorizo N)».
- [ ] **Step 5:** `uv run pytest -q`. Expected: todo PASS.
- [ ] **Step 6: Commit:** `feat(ops-agent): cliente de reparaciones R1-R3 y avisos de panelista sin nodo o atascado`.

### Task 3: Propuesta estructurada y regla de «sencillo»

**Files:**
- Modify: `ops-agent/src/ops_agent/models.py`, `ops-agent/src/ops_agent/diagnose.py` (SYSTEM y el modelo de salida)
- Create: `ops-agent/src/ops_agent/fixrules.py`
- Test: `ops-agent/tests/test_fixrules.py`, `ops-agent/tests/test_diagnose.py`

**Interfaces:**
- **Produce:**
  - En `models.py`:
    - `class ParamChange(BaseModel): node: str; path: list[str]; before: Any; after: Any`. `path` va relativo a `node.parameters`.
    - `class FixProposal(BaseModel): workflow_name: str; changes: list[ParamChange]`
    - `Diagnosis.proposal: FixProposal | None = None`, que va vacío cuando no es autorizable. Los JSON de diagnóstico ya guardados tienen que seguir cargando.
  - En `fixrules.py`:
    - `pair_dev_prod(workflows: list[Workflow], name: str) -> tuple[Workflow, Workflow] | None`. Empareja PROD «X» con «[DEV] X» por nombre, nunca por id. Ignora archivados y `excluded_name_prefixes`. Si no hay pareja o hay más de una, devuelve None.
    - `same_logic(a: dict, b: dict) -> bool`. Compara nodos (`name`, `type`, `parameters`) y conexiones. Ignora `id`, `position`, `webhookId`, `credentials`, `versionId` y el nombre del flujo. Ignora también los valores que difieren solo por la marca DEV/PROD. *(Ruling del plan: el constructor decide qué diferencias legítimas hay mirando 2 parejas reales con `n8n_client.get_workflow` en solo lectura, y las fija como lista en `fixrules.py` con un test por cada una.)*
    - `check_simple(p: FixProposal, dev: dict, prod: dict) -> str | None`. Devuelve None si es autorizable o, si no, el motivo en español. Los motivos son:
      - «más de 3 nodos»;
      - «nodo inexistente»;
      - «toca un disparador de reloj»;
      - «toca credenciales»;
      - «el valor actual no coincide» (`before` distinto de lo que hay en DEV o en PROD);
      - «DEV y PROD no coinciden»;
      - «sin copia DEV».
    - `apply_changes(wf: dict, changes: list[ParamChange]) -> dict`. Hace una copia profunda y cambia solo esas rutas.

- [ ] **Step 1: Tests en `test_fixrules.py`**, con flujos JSON mínimos en el propio test:
  - `test_pairs_by_name_not_id`
  - `test_shared_workflow_without_dev_copy_is_not_simple` («sin copia DEV»)
  - `test_rejects_4_nodes`
  - `test_rejects_schedule_trigger`
  - `test_rejects_credentials_path`: cualquier `path` que empiece por `credentials`, o un cambio sobre esa clave.
  - `test_rejects_before_mismatch_in_prod_only`
  - `test_same_logic_ignores_ids_positions_credentials`
  - `test_apply_changes_touches_only_given_path`: el resto del JSON queda igual que el original.
- [ ] **Step 2: Test en `test_diagnose.py`:**
  - `test_old_cached_diagnosis_without_proposal_still_loads`
  - `test_system_prompt_asks_for_proposal_only_for_n8n`: el SYSTEM menciona `proposal` y las reglas de sencillo.
- [ ] **Step 3:** `uv run pytest tests/test_fixrules.py tests/test_diagnose.py -q`. Expected: FAIL.
- [ ] **Step 4: Implementar.**
  - En SYSTEM, la IA rellena `proposal` solo si `fix_kind == "n8n"` y el cambio cabe en las reglas. Debe usar los nombres exactos de nodo y de ruta que aparecen en `parametros_del_nodo`.
  - El payload sigue enmascarado: las rutas y los valores que propone la IA se comprueban contra el flujo real en `check_simple` (Task 7). Nunca se aplica un valor que la IA no haya visto en el payload enmascarado como `before`. Si `before` contiene `***`, el motivo es «el valor actual no coincide».
- [ ] **Step 5:** `uv run pytest -q`. Expected: PASS.
- [ ] **Step 6: Commit:** `feat(ops-agent): propuesta de arreglo estructurada y reglas de arreglo sencillo`.

### Task 4: Escritura en n8n con control de versión

**Files:**
- Modify: `ops-agent/src/ops_agent/n8n_client.py`
- Test: `ops-agent/tests/test_n8n_client.py`

**Interfaces:**
- **Produce:**
  - `N8nClient.get_workflow(workflow_id: str) -> dict`. Devuelve el JSON completo de GET `/workflows/{id}`, con `versionId` y `updatedAt`.
  - `N8nClient.put_workflow(workflow_id: str, body: dict, expected_version: str) -> dict`, que hace tres cosas:
    1. relee el flujo y, si su `versionId` no es `expected_version`, lanza `N8nConflict(N8nError)`;
    2. envía PUT solo con `name`, `nodes`, `connections`, `settings` (filtrados a las claves que acepta la API pública: `executionOrder`, `saveDataErrorExecution`, `saveDataSuccessExecution`, `saveManualExecutions`, `saveExecutionProgress`, `executionTimeout`, `errorWorkflow`, `timezone`, `callerPolicy`) y `staticData`;
    3. devuelve el flujo resultante.
  - Un 4xx en el PUT es un `N8nError` con el código. No se reintenta.

- [ ] **Step 1: Tests:**
  - `test_get_workflow_returns_full_json`
  - `test_put_sends_only_allowed_fields`: `id`, `active`, `tags`, `versionId` y las claves desconocidas de `settings` no viajan.
  - `test_put_refuses_when_version_changed`: lanza `N8nConflict` y no se hace ningún PUT, lo que se comprueba contando las peticiones del handler.
  - `test_put_4xx_not_retried`
- [ ] **Step 2:** `uv run pytest tests/test_n8n_client.py -q`. Expected: FAIL.
- [ ] **Step 3: Implementar.** Para escribir se usa el método `_http.put` con la misma cabecera. El docstring del módulo pasa a decir «lectura y escritura acotada».
- [ ] **Step 4:** `uv run pytest -q`. Expected: PASS.
- [ ] **Step 5: Commit:** `feat(ops-agent): leer y reescribir un flujo de n8n solo si nadie lo ha cambiado`.

### Task 5: Registro de arreglos y copias

**Files:**
- Modify: `ops-agent/src/ops_agent/store.py`
- Test: `ops-agent/tests/test_fix_store.py`

**Interfaces:**
- **Produce:**
  - **Tabla `fixes`:**
    - `id INTEGER PRIMARY KEY` (es el número de arreglo que ve el responsable);
    - `fingerprint TEXT`, `kind TEXT` (`n8n`, `r1`, `r2` o `r3`), `proposal TEXT` (JSON), `state TEXT`;
    - `created TEXT`, `authorized_until TEXT`, `dev_ok_at TEXT`, `prod_until TEXT`;
    - `dev_id TEXT`, `prod_id TEXT`, `dev_version_after TEXT`, `prod_version_after TEXT`, `db_log_id INTEGER`, `notes TEXT` (JSON con la lista de eventos).
  - **Estados:** `propuesto`, `dev_aplicado`, `prod_aplicado`, `aplicado` (para R1–R3), `caducado`, `deshecho` y `fallido`.
  - **Copias:** `<data_dir>/fix_copies/<fix_id>_<dev|prod>.json`, con permisos 0600 y carpeta 0700. Las escribe `save_copy(fix_id, env, wf: dict) -> Path` y las lee `load_copy(fix_id, env) -> dict`.
  - **Métodos:**
    - `create_fix(fingerprint, kind, proposal: dict, now, authorized_until) -> int`
    - `get_fix(id) -> FixRow | None`
    - `transition(id, from_states: tuple[str, ...], to: str, now, **fields) -> bool`. Hace un `UPDATE ... WHERE state IN (...)` atómico y devuelve False si el estado ya no era ninguno de esos. Esto impide la doble pulsación.
    - `open_fix_for_workflow(dev_id) -> FixRow | None`, para los estados `propuesto` y `dev_aplicado`.
    - `due_expirations(now) -> list[FixRow]`
    - `last_fix_for(fingerprint) -> FixRow | None`
    - `count_revisions(day) -> int` y `add_revision(day, now)`, sobre una tabla `revisions(day, at)`.
  - Toda transición se añade a `notes` con su hora. Este es el registro del guardarraíl 10.

- [ ] **Step 1: Tests:**
  - `test_transition_is_compare_and_set`: la segunda transición idéntica devuelve False.
  - `test_due_expirations_picks_authorized_and_prod_windows`: un `propuesto` con `authorized_until` en el pasado sale, igual que un `dev_aplicado` con `prod_until` en el pasado. Un `prod_aplicado` no sale.
  - `test_copies_are_0600_in_0700_dir`, que se salta en Windows con `skipif os.name == "nt"`, como los tests de permisos de la fase 2.
  - `test_revisions_counted_per_day`
- [ ] **Step 2:** `uv run pytest tests/test_fix_store.py -q`. Expected: FAIL.
- [ ] **Step 3: Implementar.** `data_dir` es `settings.db_path.parent`. `deploy/backup.sh` ya copia `agent.db`: añadirle `fix_copies/`, pero no `tester.session`.
- [ ] **Step 4:** `uv run pytest -q`. Expected: PASS.
- [ ] **Step 5: Commit:** `feat(ops-agent): registro persistente de arreglos y copias de flujos`.

### Task 6: Pruebas contra el bot DEV y relación de flujos con pruebas

**Files:**
- Modify: `ops-agent/src/ops_agent/config.py`, para añadir `TESTER_DEV_BOT_USERNAME`, que es opcional.
- Modify: `ops-agent/src/ops_agent/cli.py`, en `build_tester(s, env="PROD")`.
- Modify: `ops-agent/playbook/pruebas.yaml`, añadiendo a cada prueba un `covers:` con la lista de nombres de flujo PROD que atraviesa.
- Modify: `ops-agent/src/ops_agent/bot_tests.py`, en `load_tests` y `TestDef.covers`.
- Modify: `ops-agent/deploy/env.template`
- Test: `ops-agent/tests/test_bot_tests.py`, `ops-agent/tests/test_fase2_daily_cli.py`

**Interfaces:**
- **Produce:**
  - `Settings.tester_dev_bot_username: str | None`
  - `build_tester(s, env: Literal["PROD","DEV"] = "PROD", only: set[str] | None = None) -> Callable[[], Awaitable[TestRun]]`. Con `env="DEV"` usa `tester_dev_bot_username`. Con `only`, ejecuta solo esas pruebas.
  - `tests_covering(defs: list[TestDef], workflow_name: str) -> set[str]`
  - El `covers` de cada prueba se saca de los flujos que llama el flujo principal en cada paso. El constructor lo deduce leyendo los JSON de `panelist_n8n/workflows/` y lo apunta en el yaml, con un comentario.

- [ ] **Step 1: Tests:**
  - `test_dev_tester_uses_dev_username`: con `open_tester` simulado, se comprueba el username que recibe.
  - `test_dev_tester_none_without_dev_username`: `build_tester(..., env="DEV")` lanza `ValueError("falta TESTER_DEV_BOT_USERNAME")`.
  - `test_tests_covering_by_workflow_name`
  - `test_only_filters_tests`
- [ ] **Step 2:** `uv run pytest -q`. Expected: FAIL en los nuevos.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4:** `uv run pytest -q`. Expected: PASS.
- [ ] **Step 5: Commit:** `feat(ops-agent): pruebas del bot tambien contra el bot DEV y flujos cubiertos por cada prueba`.

### Task 7: El ejecutor de arreglos

**Files:**
- Create: `ops-agent/src/ops_agent/fixer.py`
- Test: `ops-agent/tests/test_fixer.py`, con los fakes de n8n (escritura incluida) y de reparaciones añadidos a `tests/fakes.py`.

**Interfaces:**
- **Consume:**
  - Task 2: `RepairClient`, `repair_target`, `REPAIR_FOR_PREFIX`
  - Task 3: `pair_dev_prod`, `check_simple`, `apply_changes`, `FixProposal`
  - Task 4: `get_workflow`, `put_workflow`, `N8nConflict`
  - Task 5: `Store` fixes
  - Task 6: `build_tester`, `tests_covering`
- **Produce** la clase `class Fixer`, construida con `Fixer(settings, store, n8n, repairs, tester_factory, now)`. Todos sus métodos son async y devuelven `FixMessage(text: str, buttons: Buttons | None)`.
  - **`propose(item: IssueView) -> FixMessage`:**
    - Si el problema se puede arreglar, crea el arreglo y devuelve el texto «Arreglo #K: …» con botones `fx:<K>:dev`/`fx:<K>:no` (para n8n) o `fx:<K>:db`/`fx:<K>:no` (para R1–R3).
    - **n8n:** muestra el flujo, el nodo y el campo, con el valor de antes y el de después, y si hay pruebas que lo cubran.
    - **R1–R3:**
      - Muestra la base («onems-dev (`sehbnpgzqljrsqimwyuz`)»), la cuenta y el objetivo, más el preview: para R3, cuántos envíos se mueven y de qué día a qué día, como máximo 10 líneas y luego «…y N más».
      - Para R1, añade «no se puede deshacer».
    - Si no es autorizable, devuelve el motivo y «para sesión con Claude», sin crear el arreglo.
  - **`apply_dev(fix_id) -> FixMessage`:**
    1. pasa el arreglo de `propuesto` a `propuesto` usando `transition` como cerrojo, y comprueba que no ha caducado;
    2. relee DEV y PROD, vuelve a pasar `check_simple` y guarda las dos copias;
    3. hace el PUT a DEV con `expected_version`, relee el flujo y comprueba el valor;
    4. ejecuta las pruebas que lo cubren contra el bot DEV;
    5. si todo va bien, pasa a `dev_aplicado`, con `prod_until = ahora + 24 h`, y devuelve «DEV probado ✅, ¿lo paso a PROD?» con botones `fx:<K>:prod`/`fx:<K>:undo`. Si no hay pruebas que lo cubran, el texto dice «solo he comprobado que el flujo es válido».
    6. si algo falla, restaura DEV desde la copia, pasa a `fallido` y explica el motivo.
  - **`apply_prod(fix_id) -> FixMessage`:** igual que `apply_dev`, pero sobre PROD y con las pruebas contra el bot PROD. Si falla, restaura PROD y DEV.
  - **`apply_db(fix_id) -> FixMessage`:** llama a `repairs.apply`, guarda `db_log_id` y pasa a `aplicado`.
  - **`undo(fix_id) -> FixMessage`:**
    - **n8n:** por cada entorno tocado, si su `versionId` actual es igual a `*_version_after`, restaura desde la copia con `put_workflow`. Si no, no toca ese entorno y dice «alguien lo cambió después, para sesión con Claude».
    - **R2/R3:** llama a `repairs.undo` e informa de `skipped`.
    - **R1:** se niega.
  - **`expire_due() -> list[FixMessage]`:**
    - `propuesto` caducado pasa a `caducado`, sin mensaje.
    - `dev_aplicado` caducado restaura DEV (con la misma regla de versión que `undo`), pasa a `caducado` y genera el mensaje «Arreglo #K caducado: he dejado DEV como estaba».
  - **Pausa:** `apply_*` devuelve «En pausa» sin hacer nada. `undo` y `expire_due` funcionan igual en pausa.
  - Un solo arreglo de n8n abierto por flujo: si `open_fix_for_workflow(dev_id)` ya devuelve uno, `propose` contesta «ya hay un arreglo en curso para ese flujo (#J)».

- [ ] **Step 1: Tests en `test_fixer.py`:**
  - `test_happy_path_dev_then_prod`: dos PUT, uno a DEV y luego uno a PROD, con el mismo cambio.
  - `test_dev_test_failure_restores_dev_and_never_touches_prod`
  - `test_conflict_on_dev_put_writes_nothing` (Review Focus 1)
  - `test_double_press_applies_once` (Review Focus 3)
  - `test_expired_button_refused`
  - `test_pause_blocks_prod_but_expiry_restores_dev` (Review Focus 4)
  - `test_undo_skips_env_edited_after_fix` (Review Focus 1)
  - `test_r3_undo_reports_skipped` (Review Focus 5)
  - `test_r1_confirmation_says_not_undoable_and_names_db`: el texto contiene `sehbnpgzqljrsqimwyuz`.
  - `test_second_fix_on_same_workflow_refused`
  - `test_no_dev_copy_goes_to_session` (Review Focus 2)
- [ ] **Step 2:** `uv run pytest tests/test_fixer.py -q`. Expected: FAIL.
- [ ] **Step 3: Implementar.** Ninguna llamada a la IA dentro de `Fixer`.
- [ ] **Step 4:** `uv run pytest -q`. Expected: PASS.
- [ ] **Step 5: Commit:** `feat(ops-agent): ejecutor de arreglos con DEV primero, doble autorizacion y deshacer`.

### Task 8: Órdenes de Telegram, `revisa ahora` e informe

**Files:**
- Modify: `ops-agent/src/ops_agent/telegram_io.py`, `buttons.py`, `report.py`, `daily.py`, `cli.py`
- Test: `ops-agent/tests/test_telegram_io.py`, `test_buttons.py`, `test_report.py`, `test_fase2_daily_cli.py`

**Interfaces:**
- **Consume:** `Fixer` (Task 7).
- **Produce:**
  - **Orden `autorizo N`:**
    - Busca el punto N del último informe o revisión con `store.get_item(latest_report_date(), N)` y llama a `fixer.propose(item)`.
    - Si el punto está resuelto o no existe, contesta «No hay punto N».
  - **Orden `deshaz K`:** llama a `fixer.undo(K)`. Aquí K es el número de arreglo, no el del punto.
  - **Orden `revisa ahora`:**
    - Se añade a la expresión regular `_CMD` como `^(revisa ahora)$`.
    - Ejecuta `run_daily(..., fresh_tests=True)`, que ignora la prueba guardada del día y no la sobrescribe si falla el candado.
    - Antes cuenta con `count_revisions`. A partir de la cuarta contesta «Ya he hecho 3 revisiones hoy; la próxima es el informe de mañana a las 8:00».
    - Respeta la pausa.
  - **Botones `fx:<K>:(dev|prod|db|undo|no)`:**
    - `parse_callback` acepta este formato.
    - `no` pasa el arreglo de `propuesto` a `caducado`, con nota «cancelado».
  - **Informe:**
    - Cada punto abierto con `proposal` válida, o con huella en `REPAIR_FOR_PREFIX`, muestra «→ autorizo N».
    - Los que tienen `fix_kind` `n8n` o `base_de_datos` pero no son autorizables muestran «→ para sesión con Claude».
    - Si `last_fix_for(fingerprint)` está en estado `prod_aplicado` o `aplicado`, el punto lleva la nota «se aplicó el arreglo #K el dd/mm».
    - `run_daily` llama al principio a `fixer.expire_due()` y envía sus mensajes.
    - El botón «🔧 Autorizar N» se añade junto a «🔍 Detalle N» solo en los puntos autorizables.
  - **Bot:** `run_bot` lanza una tarea `asyncio` que llama a `fixer.expire_due()` cada 15 minutos y envía sus mensajes al responsable.
  - **`HELP`:** «Comandos: detalle N · autorizo N · deshaz N · revisa ahora · pausa · sigue · estado · informe».
  - `NOT_YET` desaparece.

- [ ] **Step 1: Tests:**
  - `test_autorizo_calls_propose_with_item`
  - `test_deshaz_uses_fix_number`
  - `test_revisa_ahora_limited_to_3_per_day`
  - `test_revisa_ahora_runs_fresh_tests`
  - `test_paused_blocks_revisa_and_autorizo_not_deshaz`
  - `test_fx_callback_parsed`
  - `test_report_marks_authorizable_and_session_items`
  - `test_report_notes_applied_fix_next_day`
  - `test_run_daily_sends_expiry_messages_first`
  - `test_other_chat_ignored_for_fx_buttons`
  - Actualizar el test que comprobaba `NOT_YET`.
- [ ] **Step 2:** `uv run pytest -q`. Expected: FAIL en los nuevos.
- [ ] **Step 3: Implementar.** `cmd_bot` construye el `Fixer` con:
  - `N8nClient`;
  - `RepairClient`, o None si faltan la URL o el token, y entonces R1–R3 salen como «para sesión»;
  - `build_tester`.
- [ ] **Step 4:** `uv run pytest -q`. Expected: PASS.
- [ ] **Step 5:** `uv run ops-agent run-daily --dry-run` contra n8n Cloud. Expected: el informe sale sin errores y con «→ autorizo» o «→ para sesión» en los puntos abiertos.
- [ ] **Step 6: Commit:** `feat(ops-agent): ordenes autorizo, deshaz y revisa ahora en el bot`.
- [ ] **Step 7:** actualizar `ops-agent/README.md` con la sección «Fase 3» (órdenes, estados, copias, `TESTER_DEV_BOT_USERNAME`) y `playbook/revisiones.md` con las reglas de sencillo y la lista R1–R3. Commit: `docs(ops-agent): fase 3`.

### Task 9: Despliegue y simulacro (con el responsable)

Ninguna parte de esta tarea se hace sin el responsable. Cada PARADA espera su respuesta.

- [ ] **Step 1 (PARADA):** pedir confirmación para aplicar `20261106090000_ops_agent_fixes.sql` en onems-dev (`sehbnpgzqljrsqimwyuz`). Con el sí, aplicarla con `apply_migration` y comprobar:
  - `ops_test_checks` responde con las 4 listas;
  - `authenticated` no tiene EXECUTE sobre `ops_fix_*`.
- [ ] **Step 2 (responsable):** pulsar Start en el bot DEV con la cuenta de prueba y decir el nombre de usuario del bot DEV. Añadir `TESTER_DEV_BOT_USERNAME` en `/etc/onems-ops-agent/env`, comprobando el número de líneas (trampa de nano).
- [ ] **Step 3:** `deploy/deploy.ps1`. Después, reiniciar el bot y comprobar que `estado` responde.
- [ ] **Step 4: Simulacro en DEV (PARADA para elegir el flujo con el responsable):**
  1. en un flujo [DEV] cubierto por las pruebas, cambiar a mano un texto inofensivo para provocar un fallo de prueba;
  2. `revisa ahora`;
  3. `autorizo N`;
  4. aplicar en DEV;
  5. cuando pregunte por PROD, pulsar `deshaz`.
  - Expected: DEV vuelve a estar como antes del arreglo, y PROD nunca se ha tocado (se compara el `versionId` antes y después).
  - Luego revertir a mano el texto del simulacro.
- [ ] **Step 5:** `uv run pytest -q`. Expected: verde. Después, commits finales y push de `feat/ops-agent-fase3` (panelist_n8n) y `develop` (ONEMS), con el permiso del responsable. Él abre el PR y lo fusiona.
- [ ] **Step 6:** actualizar la memoria `agente-operaciones.md`.
