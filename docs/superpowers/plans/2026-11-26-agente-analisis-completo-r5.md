# Agente de análisis en dos niveles + arreglo R5 — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** «Analizar» en Telegram resuelve los casos conocidos sin modelo (nivel 1) y, si hace falta, hace el análisis completo con un paquete ampliado; en ambos el gestor aplica R5 «etiqueta mal escrita» eligiendo el candidato.

**Architecture:** BD (ONEMS, Postgres/Supabase): `ops_case._data` gana tres listas y R5 se suma a `ops_fix` con el patrón de R4. Agente (panelist_n8n `ops-agent`, Python): módulo nuevo `case_quick.py` (nivel 1, reglas fijas + plantillas), `repairs.py` admite r5, los botones de arreglo se generalizan a R4/R5 con elección de candidato, y el análisis completo recibe las vistas previas en los hechos.

**Tech Stack:** Postgres 17 (plpgsql), tests SQL con `supabase/tests/run_tests.sh` sobre el Postgres portable 5433; Python 3.12 + pytest (`ops-agent/.venv`).

**Spec:** `ONEMS/docs/superpowers/specs/2026-11-26-agente-analisis-completo-r5-design.md`

## Global Constraints

- Una sola BD real: onems-dev `sehbnpgzqljrsqimwyuz` (= producción). Nada se aplica en remoto sin confirmación explícita de Ignacio nombrando proyecto y ref (Task 9). Las lecturas por MCP están permitidas.
- Migraciones forward-only nuevas: `20261126150000_ops_case_data_near_tags.sql`, `20261126150100_ops_fix_r5.sql`. No tocar el baseline ni migraciones anteriores.
- Base de `ops_case._data`: la definición **viva** (leerla con `pg_get_functiondef('ops_case._data(uuid,text,text,uuid)'::regprocedure)` por MCP); la BD puede ir por delante del repo.
- Todo dato filtrado por la cuenta del caso; ninguna función nueva concede EXECUTE a `anon`/`authenticated` (igual que R4: solo `service_role`).
- Error de tecleo = **una cifra distinta (misma longitud) o dos cifras contiguas intercambiadas** — exactamente la condición de `public.receipt_typo_candidates` (migración `20261104130000`).
- Candidatos R5: 1–5; con más, «demasiados parecidos». Motivos de caso admitidos: `ambiguous_typo`, `not_found`. La BD nunca elige.
- Nivel 1: no llama al modelo de análisis (`case_analysis`) ni a `case_redraft`; `extract_hints` (Haiku) solo si el lote tiene imágenes.
- Mensajes al panelista: `MESSAGE_RULES` (esquema problema → «ya lo hemos solucionado» / qué hacer); plantillas del nivel 1 con el mismo esquema, en `en, es, fr, ar, pt` (`case_i18n.LANGS`).
- Ramas: ONEMS `feat/agente-r5` desde `develop` (worktree `../ONEMS_wt_r5`); panelist_n8n `feat/analisis-r5` desde `main` (worktree `../panelist_n8n_wt_r5`). No pushear sin que Ignacio lo pida. Commits con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Puertas: `bash supabase/tests/run_tests.sh <tests>` en verde; `ops-agent/.venv/Scripts/python -m pytest -q` en verde (hoy 755 + 1 skip).
- La web ONEMS (`case_worker.py`) no ofrece arreglos ni nivel 1; solo debe seguir funcionando con el paquete nuevo.

## Review Focus

1. Caso cuyo panelista no tiene nodo o cuyo nodo no tiene ciudad → R5 «no aplica» con motivo, nunca error 500; el nivel 1 recomienda el completo. (Test en Task 2 y Task 5.)
2. Doble pulsación de un candidato o de «Confirmar» → un solo apply (estado atómico como R4). (Test en Task 7.)
3. Pulsar un candidato de un resultado viejo cuando la BD ya cambió (otro gestor lo resolvió) → «ha cambiado desde la propuesta», sin cambios. (Test en Task 2 y Task 7.)
4. Etiqueta del caso con espacios o ceros de más (`tag_raw` « 0011418 ») → se compara siempre `tag_norm`; `near_tags` no explota con etiquetas no numéricas del plan. (Test en Task 1.)
5. Plantilla de un idioma sin traducción o panelista sin idioma → cae al idioma de la cuenta y luego a `en`, nunca texto vacío. (Test en Task 5.)

---

### Task 0: Ramas y traslado de la regla de mensajes

**Files:**
- Modify (en el worktree nuevo): `ops-agent/src/ops_agent/case_analysis.py`, `ops-agent/tests/test_case_analysis.py`

- [ ] **Step 1:** `git -C ONEMS worktree add ../ONEMS_wt_r5 -b feat/agente-r5 develop`; `git -C panelist_n8n worktree add ../panelist_n8n_wt_r5 -b feat/analisis-r5 origin/main`. Crear `.venv` del worktree (`uv sync` en `ops-agent`).
- [ ] **Step 2:** En `panelist_n8n` (rama `fix/manager-nombre-cuenta`): `git diff -- ops-agent/src/ops_agent/case_analysis.py ops-agent/tests/test_case_analysis.py > <scratchpad>/message_rules.patch`; comprobar que el parche solo contiene `MESSAGE_RULES`, `_SAME_PERSON_RULE`, `_NO_ACTION_TAIL` y los dos tests (`test_case_panelist_message_scheme_problem_then_fixed_or_advice`, `"ya lo hemos solucionado"` en `test_prompt_has_facts_and_masks_phone`).
- [ ] **Step 3:** `git apply` del parche en `../panelist_n8n_wt_r5`; `git checkout --` de esos dos ficheros en el árbol viejo (el arreglo del manager queda solo con `manager_bot.py`, `store.py`, `test_manager_bot.py`).
- [ ] **Step 4:** pytest en el worktree nuevo → todo verde.
- [ ] **Step 5:** commit `feat(case): esquema general de mensajes al panelista (problema, ya solucionado o qué hacer)`.

### Task 1: Paquete ampliado en `ops_case._data` (BD)

**Files:**
- Create: `supabase/migrations/20261126150000_ops_case_data_near_tags.sql`
- Test: `supabase/tests/ops_case_data_near_tags.test.sql`

**Interfaces:**
- Produces: `ops_case._typo_kind(p_a text, p_b text) RETURNS text` → `'one_digit' | 'swap' | NULL` (NULL si iguales, longitudes distintas, no numéricas o más diferencias). `ops_case._data(...)` (misma firma) devuelve además:
  - `details[].cancellation_reason`
  - `near_tags`: `[{tag, kind, status, cancellation_reason, scheduled, sent_at, received_at, origin_code, origin_name, destination_code, destination_name, destination_city, same_city}]`, máx. 20, orden `same_city DESC, sent_at`.
  - `expected_for_panelist`: `[{tag, status, cancellation_reason, sent_at, origin_code, origin_name}]`, destino = nodo del panelista (o su ciudad si no tiene nodo), `sent` o (`cancelled` + `not_received_timeout` + `received_at IS NULL`), `sent_at >= now() - 45 days`, máx. 30, orden `sent_at`.
  - `sender_series`: `[{origin_code, origin_name, tags: [{tag, sent_at, status, destination_code}]}]`, remitentes de `near_tags` (solo `same_city`) y de `expected_for_panelist`, máx. 5 remitentes × 30 etiquetas, últimos 45 días por `sent_at`.
  - `v_involved` suma los remitentes de `near_tags` con `same_city`.

- [ ] **Step 1: Test que falla.** Con `fixtures/incident_city.sql` (+ `no_incident_triggers.sql`), crear en la cuenta 1: línea N1→N4 `cancelled`/`not_received_timeout` etiqueta `00014118`; N1→N4 `sent` `00011415`; N1→N2 `sent` `00011417` (otra ciudad: C1); y en la **cuenta 2** una línea `00011419`. Llamar `ops_case._data(P4, '00011418', NULL, NULL)` y comprobar:
  ```sql
  -- near_tags: 00014118 (swap, same_city), 00011415 (one_digit, same_city), 00011417 (one_digit, not same_city); nunca 00011419 de la cuenta 2
  -- expected_for_panelist contiene 00014118 y 00011415
  -- sender_series tiene 1 remitente (el de N1) con sus 3 etiquetas
  -- ops_case._typo_kind('00011418','00014118')='swap'; ('00011418','00011415')='one_digit';
  --   ('00011418','00011418') IS NULL; ('00011418','0011418') IS NULL; ('00011418','ABC11418') IS NULL; ('00011418','00041118') IS NULL
  -- con p_tag ' 0011418 ' (normaliza a 00011418) el resultado de near_tags es el mismo
  ```
- [ ] **Step 2:** `bash supabase/tests/run_tests.sh ops_case_data_near_tags` → FAIL (`_typo_kind` no existe). Si el runner se para en la guarda de `20261119100200`, ejecutarlo con una copia temporal que convierta esa guarda en NOTICE (como el 26/11); nunca editar la migración.
- [ ] **Step 3:** Migración: `CREATE OR REPLACE` de `ops_case._typo_kind` (SQL inmutable, misma lógica cifra a cifra que `receipt_typo_candidates`) y de `ops_case._data` partiendo de la definición viva, añadiendo las claves. `SET lock_timeout = '5s'`. Mismos GRANT/REVOKE que la función viva.
- [ ] **Step 4:** run_tests de `ops_case_data_near_tags`, `ops_case_analysis`, `ops_case_find_by_code`, `ops_case_find_partial_name`, `bot_managers` → PASS.
- [ ] **Step 5:** commit `feat(ops-case): etiquetas parecidas, envíos esperados y serie del remitente en el paquete`.

### Task 2: Arreglo R5 en la BD

**Files:**
- Create: `supabase/migrations/20261126150100_ops_fix_r5.sql`
- Test: `supabase/tests/ops_fix_r5.test.sql`

**Interfaces:**
- Consumes: `ops_case._typo_kind`, `ops_case._actor(p_token, p_account, p_actor_email, 'ops_fix')` (como R4 en `20261111090000_bot_managers.sql`), `public.revive_timeout_detail`, `public.rpc_receipt_case_fix`, `ops_fix.log`, la comprobación de copia a ONE DB de R4.
- Produces:
  - `public.ops_fix_r5_preview(p_token text, p_case_id uuid, p_account text DEFAULT NULL, p_actor_email text DEFAULT NULL) RETURNS jsonb` → `{applicable bool, reason text|null, case_status text, tag text, candidates: [{detail_id, current_tag, new_tag, kind, origin_code, origin_name, destination_code, destination_name, sent_at, status, revive bool, moves_node bool}]}`; `candidates` presente también si no aplica por «demasiados parecidos» (los 5 primeros).
  - `public.ops_fix_r5_apply(p_token text, p_case_id uuid, p_detail_id uuid, p_expected jsonb, p_account text DEFAULT NULL, p_actor_email text DEFAULT NULL) RETURNS jsonb` → `{log_id bigint, outcome text}`; `p_expected` = el objeto candidato tal como se enseñó.
  - `public.ops_fix_r5_undo(p_token text, p_log_id bigint, p_account text DEFAULT NULL, p_actor_email text DEFAULT NULL) RETURNS jsonb` → `{undone true, reminder_already_sent bool}`.
  - Motivos (`reason`, y errores `ops_fix: …`) con texto fijo: `el caso no está abierto`, `motivo del caso no admitido`, `el panelista no tiene nodo con ciudad`, `la etiqueta ya existe en el plan`, `ningún envío parecido`, `demasiados parecidos`, `ha cambiado desde la propuesta`, `no es un candidato`, `la copia a ONE DB no se hizo; no toco nada`, `el arreglo % ya se deshizo`, `han pasado más de 24 h desde el arreglo %; no lo deshago`, `cambió después del arreglo; no lo deshago`.
  - Orden de candidatos: mismo nodo que el receptor primero, luego `kind='swap'`, luego `sent_at` ascendente.

- [ ] **Step 1: Test que falla** (fixture como Task 1, caso de recepción de P4 `ambiguous_typo`/`needs_decision`, `tag_norm='00011418'`, `first_attempt_at = now()`):
  - preview → `applicable`, 2 candidatos en orden `[00014118 (swap, revive=true), 00011415 (one_digit, revive=false)]`.
  - apply con `00014118` → `outcome='ok_typo_fixed'`; línea `received`, `tag_id='00011418'`, `received_at = first_attempt_at`; caso `fixed`, `original_tag='00014118'`; `00011415` sigue `sent` con su etiqueta; hay 1 fila en `panelist_notification` del caso.
  - undo → línea vuelve a `cancelled`/`not_received_timeout`/`00014118`/`received_at NULL`; caso vuelve a `needs_decision`, `ambiguous_typo`, `detail_id NULL`, `culprit_* NULL`; notificación borrada; `reminder_already_sent=false`. Repetir apply+undo marcando antes la notificación como enviada → `reminder_already_sent=true` y la notificación sigue.
  - No aplica: caso `other_city_tag`; caso `fixed`; línea con etiqueta exacta `00011418`; 0 candidatos; 6 candidatos (`demasiados parecidos`, 5 en `candidates`); candidato con `sent_at > first_attempt_at`; candidato en `deferred_samples`; panelista sin nodo (`el panelista no tiene nodo con ciudad`, sin excepción); caso de la cuenta 2 con `p_account` de la cuenta 1 → error de cuenta.
  - apply con `p_detail_id` que no es candidato → `ops_fix: no es un candidato`; con `p_expected` alterado (`sent_at` distinto) → `ops_fix: ha cambiado desde la propuesta`, nada cambia.
  - undo dos veces → `ya se deshizo`; undo con `ops_fix.log.created_at` a −25 h → `más de 24 h`.
  - `has_function_privilege('anon'|'authenticated', 'public.ops_fix_r5_*', 'EXECUTE')` = false.
- [ ] **Step 2:** run_tests `ops_fix_r5` → FAIL.
- [ ] **Step 3:** Migración: `ops_fix._r5_check(p_case_id uuid) RETURNS jsonb` (cálculo de la vista previa, reutilizable por apply) y las tres públicas, copiando de R4 el control de actor/cuenta, el `FOR UPDATE`, la foto `before` en `ops_fix.log` (`kind='r5'`, `target = {case_id, detail_id}`), la comprobación de ONE DB y el undo con su ventana de 24 h. Undo restaura de la foto: línea (`tag_id, idtag, status, received_at, cancellation_reason, cancelled_at, destination_node_id, destination_panelist_id, destination_panelist_name, original_destination_node_id`) y caso (`status, reason, detail_id, original_tag, culprit_role, culprit_panelist_id, resolved_at, resolved_by`); borra la `panelist_notification` del caso con `kind='receipt_reminder'` si no está enviada.
- [ ] **Step 4:** run_tests `ops_fix_r5 ops_fix_r4 ops_fix_r4_with_triggers receipt_manager_rpcs receipt_cases` → PASS (también con triggers: añadir una variante del caso apply sin `no_incident_triggers.sql`).
- [ ] **Step 5:** commit `feat(ops-fix): R5 etiqueta mal escrita con elección de candidato`.

### Task 3: `repairs.py` admite R5

**Files:**
- Modify: `ops-agent/src/ops_agent/repairs.py`
- Test: `ops-agent/tests/test_repairs.py` (o el fichero de tests de repairs existente)

**Interfaces:**
- Produces: `Kind = Literal["r1","r2","r3","r4","r5"]`; `RepairTarget.detail_id: str | None = None`; para r5 `_params` = `{"p_case_id"}` y en `apply` además `{"p_detail_id": target.detail_id}`; `_acct` acepta `r4` y `r5`.

- [ ] **Step 1:** Tests: `preview("r5", RepairTarget("Kenya", case_id="c"), account="Kenya", actor_email="a@b")` llama a `ops_fix_r5_preview` con `p_case_id, p_account, p_actor_email`; `apply("r5", RepairTarget(..., case_id="c", detail_id="d"), {...})` envía `p_detail_id="d"`; `apply("r5", target sin detail_id, …)` → `RepairError("falta el envío elegido")`; `undo("r5", 7)` llama a `ops_fix_r5_undo`.
- [ ] **Step 2:** pytest de esos tests → FAIL. **Step 3:** implementar. **Step 4:** pytest completo → verde.
- [ ] **Step 5:** commit `feat(repairs): R5`.

### Task 4: Vistas previas antes del análisis completo y `recommended_tag`

**Files:**
- Modify: `ops-agent/src/ops_agent/case_fix_buttons.py` (`check_r4` → `check_fixes`), `case_analysis.py` (prompt, `CaseAnalysis`, `r4_line`→`fix_line`, `build_cc_prompt`), `case_facts.py` (`facts_text` incluye las vistas previas), `case_bot.py` (`_analyse`), `case_worker.py`
- Test: `tests/test_case_analysis.py`, `tests/test_case_bot.py`, `tests/test_case_worker.py`

**Interfaces:**
- Produces: `async def check_fixes(repairs, account: str, anchor: dict | None, actor=None) -> tuple[dict | None, dict | None, bool]` → `(r4, r5, ok)`; solo pide vistas previas si `anchor.kind == "receipt"`; si R4 y R5 son aplicables, devuelve R5 como `None` y registra `log.warning("R4 y R5 aplicables a la vez")`.
- `CaseResult.fix` pasa a ser el arreglo ofrecido y se añade `CaseResult.fix_kind: Literal["r4","r5"] | None`.
- `CaseAnalysis.recommended_tag: str | None = None`; tras validar, si no coincide con ningún `current_tag` de `r5.candidates`, se pone a `None`.
- `facts_text(f, r4=None, r5=None)` añade líneas «Arreglo R4: …» / «Arreglo R5: candidatos …» (con marcas de Task 5).
- `analyze(..., fixes: tuple[dict|None, dict|None] = (None, None))`.
- `fix_line(kind, fix, failed) -> str | None` sustituye a `r4_line` (mismo texto para R4; para R5 «Arreglo automático R5: N candidatos (…)» / «no aplica: motivo»). `PROMPT_LINE`/`_with_r4_line` buscan el prefijo «Arreglo automático R».

- [ ] **Step 1:** Tests: en `_analyse` las vistas previas se piden **antes** que `analyze` y llegan en `facts`; `SYSTEM_ANALYSIS` contiene `near_tags`, `expected_for_panelist`, `sender_series` y la regla «si la etiqueta no está en el plan, busca el error de tecleo»; un `recommended_tag` fuera de los candidatos queda `None`; el worker sigue sin aplicar nada (pide vistas previas solo para el prompt) y sus tests pasan; con R4 y R5 aplicables se ofrece R4.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** pytest completo → verde.
- [ ] **Step 5:** commit `feat(case): vistas previas R4/R5 en los hechos y candidato recomendado`.

### Task 5: Nivel 1 (`case_quick.py`) y plantillas

**Files:**
- Create: `ops-agent/src/ops_agent/case_quick.py`
- Modify: `ops-agent/src/ops_agent/case_i18n.py` (claves `Q_*` en los 5 idiomas y en español para Ignacio)
- Test: `ops-agent/tests/test_case_quick.py`

**Interfaces:**
- Produces:
  - `@dataclass QuickResult: pattern: Literal["typo","other_city","already","none"]; recommend_full: bool; why_full: str | None; fix_kind: Literal["r4","r5"] | None; fix: dict | None; candidates: list[dict]` (cada uno el candidato R5 + `marks: list[str]` de `{"timeout","in_transit","same_panelist","out_of_series"}`); `hint_tag: str | None` (el único `out_of_series`); `template_key: str | None`.
  - `def classify(data: dict, r4: dict | None, r5: dict | None, *, has_images: bool, has_free_text: bool) -> QuickResult`.
  - `def candidate_marks(c: dict, data: dict, case_tag: str) -> list[str]`.
  - `def render_quick(q: QuickResult, data: dict, lang: str) -> str` (tarjeta, ≤ 4000) y `def quick_draft(q: QuickResult, data: dict) -> ReadyDraft | None` (plantilla al panelista del caso en su idioma; `None` si `template_key` es `None`).
- Reglas fijas (spec §0): orden P1 `typo` (R5 con ≥1 candidato) → P2 `other_city` (R4 aplicable) → P3 `already` (`details` con `status='received'` y `destination.panelist_id == panelist.id`) → `none`. `recommend_full = True` si `none`, `has_images`, `has_free_text`, ancla no `receipt`, o `typo` con >1 candidato y `hint_tag is None`.
- `out_of_series`: con `S` = etiquetas numéricas del mismo remitente en `sender_series` excluido el propio candidato, el candidato es «fuera de serie» si `min |c − s| > 50` y `min |case_tag − s| ≤ 50` (umbral 50, decisión del constructor fijada aquí).
- Plantillas (`Q_TPL_typo`, `Q_TPL_other_city`, `Q_TPL_already`), campos `{name}`, `{tag}`; texto inglés fijo de `Q_TPL_typo`: «Hi {name}, thank you for reporting envelope {tag}. The bot couldn't register it because the sender had typed the number incorrectly. We've already fixed it, so there's nothing else you need to do. Great job!». Idioma: el del panelista → el de la cuenta → `en`. Todas ≤ 350 caracteres y sin «keep/guardar/conserver/guardar/احتفظ» (reutilizar `_asks_to_keep`).

- [ ] **Step 1: Tests:** el paquete del caso de referencia (fixture JSON nuevo `tests/fixtures/case_00011418.json`, con los dos candidatos R5) → `pattern="typo"`, marcas `00014118: {timeout, same_panelist, out_of_series}`, `00011415: {in_transit, same_panelist}`, `hint_tag="00014118"`, `recommend_full=False`, plantilla inglesa exacta con `name="Jacktone"`… (nombre de pila = primera palabra de `panelist.name`); sin `hint_tag` y 2 candidatos → `recommend_full=True`; P2, P3, `none`; `has_images=True` → `recommend_full=True`; panelista sin idioma y cuenta `fr` → plantilla francesa; idioma desconocido → `en`; ninguna plantilla de ningún idioma supera 350 ni pide guardar; mismos `{campos}` en todos los idiomas; `classify` y `render_quick` no reciben ni usan `llm`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** verde.
- [ ] **Step 5:** commit `feat(case): nivel 1 sin modelo con patrones fijos y plantillas`.

### Task 6: Botones de arreglo genéricos R4/R5 con elección de candidato

**Files:**
- Modify: `ops-agent/src/ops_agent/case_fix_buttons.py`, `case_fix_texts.py`, `case_i18n.py`
- Test: `ops-agent/tests/test_case_fix_buttons.py` (o donde estén hoy los de R4)

**Interfaces:**
- Consumes: `repairs` r5 (Task 3); resultado guardado con `fix_kind`, `fix`, `fix_state`.
- Produces: prefijo nuevo `"rk:"` (`rk:{rid}:{i}`, elegir candidato `i` de R5) en `PREFIXES2 = ("rk:",)` (dos números); `card_buttons(rid, fix, fix_kind=..., prompt=..., actor=..., recommended=i|None, full=True)` → una fila por candidato R5 («00014118 · Faith Joseph · 04/11», con «★» si es el recomendado/`hint_tag`) + fila «Ver detalle» / «Análisis completo» (`an:{rid}`); R4 sigue igual (`ra:`). Estado R5: `fix_choice` (índice) guardado con `set_case_fix_state(..., "previewed", choice=i)`; `rc:` aplica `fix["candidates"][choice]` con `RepairTarget(detail_id=...)` y `expected=` ese candidato; `rn:` vuelve a enseñar la lista. Tras `APPLIED`, si hay plantilla o borrador pendiente, el mensaje termina con `Q_SEND_NOW` («Ya puedes enviar el mensaje al panelista.») y devuelve los botones de enviar de ese borrador. Undo con `reminder_already_sent=true` añade `Q_REMINDER_SENT`.

- [ ] **Step 1: Tests:** R4: todos los tests actuales siguen verdes sin cambios de comportamiento; R5: `rk:` pide vista previa nueva y enseña la de ese candidato con Confirmar/No aplicar; doble `rc:` → una sola llamada a `repairs.apply`; `rc:` con BD «ha cambiado desde la propuesta» → texto `APPLY_FAILED` y lista refrescada; reconciliación de `applying` cortado (usa la vista previa: si el caso está `fixed` → aplicado); `rk:` con índice fuera de rango → `BAD`; undo con aviso de recordatorio enviado; gestor de cuenta cerrada a envíos no puede `rk:`/`rc:` (`SENDS_OFF`); callback data ≤ 64 bytes.
- [ ] **Step 2:** FAIL. **Step 3:** implementar (parametrizar por `fix_kind` en lugar de duplicar). **Step 4:** pytest completo → verde.
- [ ] **Step 5:** commit `feat(case-bot): botones de arreglo R4/R5 con elección de candidato`.

### Task 7: Flujo del bot: nivel 1 primero, «Análisis completo» después

**Files:**
- Modify: `ops-agent/src/ops_agent/case_bot.py`
- Test: `ops-agent/tests/test_case_bot.py`

**Interfaces:**
- Consumes: `check_fixes` (Task 4), `classify`/`render_quick`/`quick_draft` (Task 5), `card_buttons` (Task 6).
- Produces: `_analyse` hace el nivel 1: `extract_hints` solo si hay imágenes (si no, pistas por regex como hoy: `_TAG`, `find_ids`); datos; `check_fixes`; `classify`; guarda resultado `{"level": 1, "quick": asdict(q), "fix_kind", "fix", "fix_state", "account", "anchor", "chosen": <candidato de panelista>}` con la plantilla como borrador 0; enseña la tarjeta y los botones; **no** muestra los botones de enviar de la plantilla hasta `applied` (P1/P2) — en P3 sí desde el principio. Callback `an:{rid}`: comprueba dueño (`_mine`), `_busy`, y lanza el análisis completo de siempre con el mismo bundle y panelista (`_start(ctx, actor, bid, chosen=…, level=2)`), reutilizando las pistas en caché; su resultado es uno nuevo (rid nuevo) con `level: 2`. Línea de gasto (`_spend_line`) en nivel 1: ninguna.

- [ ] **Step 1: Tests:** con el `FakeLLM` de `fakes.py`, un lote de solo texto («PAN-KEN-050 00011418») → 0 llamadas al LLM y tarjeta P1 con 2 candidatos y «Análisis completo»; botones de enviar plantilla ausentes hasta aplicar y presentes después; lote con imagen → 1 llamada (hints) y `recommend_full`; `an:` → 1 llamada a `case_analysis` y tarjeta del completo con candidato ★ = `recommended_tag`; `an:` de otro chat → `BAD`; `an:` mientras hay otro análisis → `BUSY`; caso sin ancla de recepción → nivel 1 «no es un caso conocido» con completo recomendado.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** pytest completo → verde; `ruff`/lint del proyecto si existe en `pyproject.toml`.
- [ ] **Step 5:** commit `feat(case-bot): análisis en dos niveles`.

### Task 8: Revisión final de ramas

- [ ] **Step 1:** ONEMS worktree: `bash supabase/tests/run_tests.sh` (todos) → verde salvo la guarda conocida; anotar el resultado exacto.
- [ ] **Step 2:** panelist_n8n worktree: pytest completo → verde; `graphify update .` en ONEMS si aplica (CLAUDE.md).
- [ ] **Step 3:** revisión de toda la rama (superpowers:requesting-code-review) y arreglar lo real.

### Task 9: Puesta en producción (con confirmación de Ignacio en cada paso)

- [ ] **Step 1:** Pedir confirmación: «aplicar `20261126150000` y `20261126150100` en onems-dev `sehbnpgzqljrsqimwyuz`». Antes, leer por MCP `ops_case._data` viva y comprobar que no cambió desde la Task 1 (si cambió, rehacer la Task 1 sobre la nueva).
- [ ] **Step 2:** Tras el sí: `apply_migration` de las dos; comprobar por MCP `ops_fix_r5_preview` sobre un caso abierto real `ambiguous_typo` (solo lectura).
- [ ] **Step 3:** Pedir confirmación para Hetzner. Comparar con `diff` cada fichero tocado contra el del servidor (`/opt/...ops_agent/`; el servidor ya tiene `manager_bot.py` y `store.py` del 26/11, no subirlos); copia `*.20261126b` y subir solo: `case_analysis.py, case_bot.py, case_facts.py, case_fix_buttons.py, case_fix_texts.py, case_i18n.py, case_quick.py, case_worker.py, repairs.py`; reiniciar los servicios del agente (owner y `onems-ops-agent-managerbot`) y revisar sus logs 2 min.
- [ ] **Step 4:** Prueba real en DEMO2 (caso sintético de etiqueta mal escrita, como el 11/11), probar nivel 1 → R5 → deshacer → completo; borrar los datos de prueba.
- [ ] **Step 5:** Actualizar la memoria `agente-r5-etiqueta-mal-escrita` y `agente-analisis-casos`; preguntar a Ignacio si quiere commits/PR.
