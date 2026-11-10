# Tarjeta del manager y arreglo R4 — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** El análisis de un caso empieza con Problema, Causa y Solución. Si la base dice que el arreglo R4 («redirigir y registrar la recepción») aplica, Ignacio lo aplica con botones: vista previa, confirmación y «Deshacer» durante 24 h. Si no aplica, recibe un prompt listo para Claude Code.

**Architecture:**
- **Base de datos:** el arreglo R4 sigue el patrón de R1-R3 (`ops_fix_r4_preview`, `ops_fix_r4_apply` y `ops_fix_r4_undo`, protegidas con el token del agente, con registro en `ops_fix.log`).
- **Agente:** la IA redacta problema, causa y solución; la vista previa de la base decide si sale el botón «Aplicar». Los botones viven en `case_bot.py` y reutilizan `RepairClient`. El prompt para Claude Code lo genera el código a partir del análisis y los datos.
- **ONEMS:** muestra la tarjeta y un botón «Copiar prompt».

**Tech Stack:** Postgres (plpgsql), Python (python-telegram-bot, pydantic, pytest), React + TypeScript.

**Spec:** `docs/superpowers/specs/2026-11-10-agente-casos-tarjeta-y-aplicar-design.md` (sobre todo §4 y §8b).

**Repos y ramas:** ONEMS `feat/analisis-casos`; panelist_n8n `feat/ops-agent-analisis-casos`. No se sube nada a GitHub.

## Global Constraints

- **Base onems-dev `sehbnpgzqljrsqimwyuz`:**
  - migración nueva `20261110140000_ops_fix_r4.sql`, validada en el Postgres local 5433 (`bash supabase/tests/run_tests.sh <test>`; hay 9 fallos que ya existían antes de este trabajo);
  - se aplica en la base real solo con confirmación explícita de Ignacio.
- **Funciones R4:** el mismo patrón que R1-R3.
  - `SECURITY DEFINER SET search_path = ''`.
  - Comprueban el token con `PERFORM ops_test._check(p_token)`.
  - Permisos: se revocan a PUBLIC, anon y authenticated, y solo se concede EXECUTE a anon.
  - Los errores llevan el prefijo `ops_fix:`.
- **Condiciones de R4** (spec §4 y §8b; si falla cualquiera, R4 no aplica):
  - un caso abierto (`pending` o `needs_decision`) de motivo `other_city_tag`;
  - exactamente una línea de la cuenta con `normalize_tag(tag_id) = tag_norm`, en estado `sent`, con `received_at` vacío y con `sent_at <= first_attempt_at`;
  - ningún otro caso abierto con la misma etiqueta;
  - el panelista del caso es activo, tiene nodo y es de la misma cuenta;
  - la línea no tiene errores de validación que impidan copiarla a ONE DB.
- **Lo que escribe R4 en la línea del plan:**
  - destino: el nodo, el panelista y el nombre del panelista del caso;
  - `original_destination_node_id`: el destino anterior, si estaba vacío;
  - `reassignment_reason = 'sender_wrong_address'` y `reassigned_at = now()`;
  - `status = 'received'` y `received_at = receipt_case.first_attempt_at`.
- **Lo que escribe R4 en el caso:** `status = 'fixed'`, la nota «Redirigida al receptor real (error de dirección del remitente) — agente de operaciones» y `resolved_by` vacío.
- **Deshacer:**
  - solo dentro de las 24 h siguientes y solo si la línea y el caso siguen como los dejó R4;
  - en la misma transacción borra la copia en ONE DB creada al aplicar y devuelve la línea y el caso a su estado anterior.
- **Vista previa:** devuelve `applicable` (true o false) y el motivo cuando es false. No falla por «no aplica»: falla solo por un token malo o un caso inexistente.
- **Quién usa cada botón:** «Aplicar», «Confirmar» y «Deshacer» solo en el chat privado de Ignacio (`owner_chat_id`). En ONEMS solo se ve la tarjeta y se copia el prompt; no se aplica nada.
- **Prompt para Claude Code:**
  - en español;
  - enmascarado con `masking.mask`;
  - incluye cuenta, etiqueta, ids (caso, línea y panelistas por código), problema, causa, solución propuesta y estas reglas: confirmar el proyecto y su ref antes de escribir en Supabase, validar en local y nunca mezclar cuentas.
- **Calidad:**
  - agente: `uv run pytest -q` en verde;
  - frontend: `npx tsc --noEmit`, `npx eslint --max-warnings 0` sobre los ficheros tocados y `npm run build`;
  - textos de la pantalla en los 5 CSV `public/locales/{en,es,fr,ar,pt}.csv`.
- **Logs:** nunca contenido; solo tipos y números.

## Review Focus

1. **El arreglo se aplica sobre una línea que cambió entre la vista previa y la confirmación.** `apply` recalcula y falla con «ha cambiado desde la propuesta» sin tocar nada (Task 1).
2. **Doble pulsación de «Confirmar» o de «Deshacer».** Solo una aplicación y solo un deshacer (Task 1: bloqueo `FOR UPDATE` más estado en `ops_fix.log`; Task 3: marca en el resultado guardado).
3. **Deshacer pasadas las 24 h, o después de que alguien tocara la línea.** Se rechaza con un mensaje claro (Task 1).
4. **Una etiqueta con dos casos abiertos, o con dos líneas.** R4 no aplica (Task 1).
5. **Un manager que no es Ignacio pulsa «Aplicar»,** hoy o en el futuro grupo. Se ignora (Task 3).

---

### Task 1: Arreglo R4 en la base (ONEMS)

**Files:**
- Create: `supabase/migrations/20261110140000_ops_fix_r4.sql`.
- Test: `supabase/tests/ops_fix_r4.test.sql`.

**Interfaces:**
- Consumes:
  - `ops_test._check(text)` y el esquema `ops_fix` con `ops_fix.log` (`20261106090000_ops_agent_fixes.sql`);
  - `public.normalize_tag(text)`;
  - las tablas `receipt_case`, `allocation_plan_details` y `panelists`;
  - el disparador `transfer_to_one_db`. Leer su definición para saber en qué tabla escribe la copia en ONE DB y cómo encontrarla para borrarla al deshacer.
- Produces:
  - **Permisos previos:**
    - el CHECK `allocation_plan_details_reassignment_reason_check` admite también `sender_wrong_address`;
    - el CHECK de `ops_fix.log.kind` admite también `r4`.
  - **`ops_fix._r4_check(p_case_id uuid) RETURNS jsonb`:** comprueba las condiciones de R4. Devuelve:
    - `{applicable, reason, account_id, account, case_id, tag, detail_id, origin_code, current_dest_code, new_dest_code, new_node, received_at, sla_hours_or_null}`;
    - con `applicable = false`, `reason` dice en castellano llano cuál de las condiciones falla.
  - **`public.ops_fix_r4_preview(p_token text, p_case_id uuid) RETURNS jsonb`:** la salida pública de `_r4_check`, sin ids internos salvo `case_id` y `detail_id`.
  - **`public.ops_fix_r4_apply(p_token text, p_case_id uuid, p_expected jsonb) RETURNS jsonb`:**
    - bloquea la línea y el caso (`FOR UPDATE`);
    - recalcula y compara `detail_id`, `new_dest_code` y `received_at` con lo esperado; si algo cambió, `ops_fix: ha cambiado desde la propuesta`;
    - si `applicable` es false, `ops_fix: R4 no aplica: <motivo>`;
    - escribe según Global Constraints;
    - registra en `ops_fix.log` el `before` (los campos de la línea y del caso que toca) y el `after` (incluido el id de la copia en ONE DB, si se creó);
    - devuelve `{log_id, detail_id, new_dest_code}`.
  - **`public.ops_fix_r4_undo(p_token text, p_log_id bigint) RETURNS jsonb`:**
    - solo `kind = 'r4'`, sin deshacer antes y con `applied_at > now() - 24 h`;
    - la línea y el caso tienen que seguir como dice el `after`; si no, `ops_fix: cambió después del arreglo; no lo deshago`;
    - borra la copia en ONE DB, restaura la línea y el caso desde el `before` y marca `undone_at`;
    - devuelve `{restored: true}`.

- [ ] **Step 1: Write the failing tests.** Cuenta 1 con un caso de referencia como el de 00011844: remitente en N1, destino previsto en N2, quien lo recibió en N3 con un caso `other_city_tag` `needs_decision`, la línea en `sent` y una norma de entrega para N1 → N3.
  - La vista previa devuelve `applicable = true`, con `new_dest_code` igual al del panelista del caso y `received_at` igual a `first_attempt_at`.
  - `apply` deja la línea `received`, con el destino nuevo, `original_destination_node_id` igual a N2 y `reassignment_reason = 'sender_wrong_address'`; el caso pasa a `fixed`; hay una fila en `ops_fix.log` y una copia en ONE DB.
  - Un segundo `apply` → error.
  - `undo` lo devuelve todo como estaba y borra la copia en ONE DB; un segundo `undo` → error.
  - `undo` con `applied_at` de hace 25 h → error.
  - `undo` después de cambiar a mano el `status` de la línea → error, sin tocar nada.
  - Casos que no aplican (`applicable = false`, cada uno con su motivo):
    - motivo del caso `not_found`;
    - dos líneas con la misma etiqueta;
    - un segundo caso abierto con la etiqueta;
    - la línea ya recibida;
    - `sent_at` posterior a `first_attempt_at`;
    - el panelista del caso sin nodo.
  - `apply` con un `expected` que no coincide → error, sin cambios.
  - Un token malo → error.
  - Permisos: `authenticated` no puede ejecutar las funciones.
- [ ] **Step 2:** `bash supabase/tests/run_tests.sh ops_fix_r4` → FAIL.
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** el mismo test → PASS; la suite completa → solo los 9 fallos conocidos.
- [ ] **Step 5: Commit** `feat(ops-agent): arreglo R4 en la base (redirigir y registrar la recepción, con deshacer 24 h)`.

### Task 2: Tarjeta y prompt en el análisis (panelist_n8n, agente)

**Files:**
- Modify: `ops-agent/src/ops_agent/repairs.py`.
  - `Kind` admite `"r4"`.
  - `_params("r4", t)` = `{"p_case_id": t.case_id}`.
  - `RepairTarget` gana `case_id: str | None = None`.
  - `undo` admite r4.
- Modify: `ops-agent/src/ops_agent/case_analysis.py`.
  - `CaseAnalysis` gana `problem: str`, `cause: str` y `solution: str` (cortos).
  - El prompt del sistema pide esos tres apartados primero. La solución sigue la regla de aprovechar la muestra (spec §2.1).
  - `CaseResult` gana `fix: dict | None` (la vista previa de R4, si aplica) y `cc_prompt: str`.
  - `render_telegram` (petición de Ignacio del 2026-11-10: más concisa y sin repeticiones). La tarjeta lleva SOLO estos tres apartados, de 1 a 2 frases cada uno, sin repetir datos de un apartado en otro:
    - «Problema»;
    - «Causa»: la probable, con su prueba en media frase;
    - «Solución».
  - El análisis largo (plan, realidad, comparación, ruido, contactos, mejora) pasa a una función aparte, `render_detail(r)`, que se envía solo con el botón «📄 Ver detalle». La Task 3 añade ese botón.
  - El prompt del sistema pide `problem`, `cause` y `solution` concisos y sin repetir información entre sí. `summary` deja de mostrarse.
  - `to_onems_result` añade `problem`, `cause`, `solution`, `fix` (o null) y `prompt`.
  - Nuevo `build_cc_prompt(r: CaseResult, data: dict) -> str` (contenido según Global Constraints, máximo 3500 caracteres).
- Test: `ops-agent/tests/test_case_analysis.py` y `ops-agent/tests/test_repairs.py`.

**Interfaces:**
- Consumes: `RepairClient` y `RepairError` (`repairs.py`); `masking.mask`.
- Produces:
  - `RepairTarget(account, case_id=...)`;
  - `RepairClient.preview("r4", t)`, `apply("r4", t, expected)` y `undo("r4", log_id)`;
  - `CaseResult.fix` y `CaseResult.cc_prompt`;
  - `build_cc_prompt`.

- [ ] **Step 1: Write the failing tests:**
  - los parámetros de r4 que se envían a la base;
  - la tarjeta empieza con los tres apartados, en orden;
  - `to_onems_result` lleva las claves nuevas;
  - el prompt contiene la etiqueta, el código de cuenta, «ops_fix» o «confirmar», no contiene un teléfono del fixture y cabe en 3500 caracteres.
- [ ] **Step 2:** `uv run pytest tests/test_case_analysis.py tests/test_repairs.py -q` → FAIL.
- [ ] **Step 3:** implementar. `analyze` no llama a la base; el que pide la vista previa es la Task 3.
- [ ] **Step 4:** PASS; la suite completa en verde.
- [ ] **Step 5: Commit** `feat(ops-agent): tarjeta Problema/Causa/Solución y prompt para Claude Code`.

### Task 3: Botones Aplicar / Confirmar / Deshacer / Prompt (panelist_n8n, agente)

**Files:**
- Modify: `ops-agent/src/ops_agent/case_bot.py`, `ops-agent/src/ops_agent/case_worker.py` y `ops-agent/src/ops_agent/cli.py` (construir `RepairClient` para `case_bot` si `report_configured`).
- Test: `ops-agent/tests/test_case_bot.py` y `ops-agent/tests/test_case_worker.py`.

**Interfaces:**
- Consumes: Task 2; `Store.save_case_result` y `get_case_result` (guardar y releer el estado del arreglo dentro del resultado, en la clave `fix_state`).
- Produces (datos de los botones, enteros estrictos como en el resto de `case_bot`):
  - `dt:<rid>`: «📄 Ver detalle». Envía `render_detail` del resultado guardado. Está siempre en la tarjeta.
  - `ra:<rid>`: «✅ Aplicar». Enseña la vista previa en texto llano con «Confirmar» (`rc:<rid>`) y «No aplicar» (`rn:<rid>`).
  - `rc:<rid>`: aplica con `expected` = la vista previa guardada. Si va bien: «Aplicado» con «↩️ Deshacer» (`ru:<rid>`) y guarda `log_id` y `applied_at`. Si da error: el texto seguro del error (`ops_fix:`).
  - `rn:<rid>`: lo descarta.
  - `ru:<rid>`: deshace (solo dentro de 24 h, que comprueba la base) y lo marca como deshecho.
  - `cp:` ya existe para elegir panelista, así que el prompt usa `pp:<rid>`: «🧩 Prompt para Claude Code». Envía `cc_prompt` como texto llano, partido si pasa de 4000 caracteres.
- **Al terminar el análisis:**
  - si el ancla es un caso de recepción, se pide `preview("r4", case_id)` sin bloquear el bucle (`to_thread`). Si `applicable` es true, la tarjeta lleva `ra:`; si no, `pp:`.
  - si la vista previa falla, solo `pp:`, más una línea «no pude comprobar si se puede arreglar solo».
- **Doble pulsación:** el estado guardado (`fix_state`: `previewed`, `applying`, `applied`, `undone` o `dismissed`) se cambia de forma atómica antes de llamar a la base.
- **Solo el responsable:** las pulsaciones de otros chats se ignoran, igual que hoy.
- **`case_worker`** (ONEMS): pide la misma vista previa y la guarda en `fix` del resultado. Nunca aplica.

- [ ] **Step 1: Write the failing tests** (`FakeRepairs` en `tests/fakes.py` que registre las llamadas):
  - el análisis con ancla `receipt` y vista previa aplicable → la tarjeta lleva el botón `ra:`;
  - con vista previa no aplicable → `pp:`, sin `ra:`;
  - `ra:` → texto de vista previa con `rc:`/`rn:`;
  - `rc:` dos veces → un solo `apply`;
  - `rc:` con un `RepairError` → texto seguro, y el estado vuelve a `previewed`;
  - `ru:` → `undo` una vez;
  - `pp:` → envía un prompt que contiene la etiqueta;
  - un chat ajeno → `(None, None)`;
  - el worker guarda `fix` en el resultado y nunca llama a `apply`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3:** implementar. Si `case_bot.py` pasa de 450 líneas, separar los botones del arreglo en `case_fix_buttons.py`.
- [ ] **Step 4:** `uv run pytest -q` en verde.
- [ ] **Step 5: Commit** `feat(ops-agent): aplicar R4 desde el análisis con vista previa y deshacer; prompt para Claude Code`.

### Task 4: Tarjeta en ONEMS (frontend)

**Files:**
- Modify: `src/lib/hooks/useCaseAnalysis.ts` (tipos: `problem`, `cause`, `solution`, `fix`, `prompt`).
- Modify: `src/components/incidents/CaseAnalysisPanel.tsx`:
  - la tarjeta arriba con Problema, Causa y Solución;
  - una línea «Este caso se puede corregir solo desde el agente (R4)» cuando `fix.applicable`;
  - el botón «Copiar prompt para Claude Code», que copia con `navigator.clipboard.writeText` y muestra «Copiado».
- Modify: `public/locales/{en,es,fr,ar,pt}.csv`, con las claves `case_analysis.problem`, `.cause`, `.solution`, `.fix_available`, `.copy_prompt` y `.copied`.

- [ ] **Step 1:** implementar y pasar `npx tsc --noEmit`.
- [ ] **Step 2:** claves en los 5 CSV (`grep -c` igual en todos). Pasar `npx eslint --max-warnings 0` sobre los ficheros tocados y `npm run build`.
- [ ] **Step 3: Commit** `feat(incidents): tarjeta Problema/Causa/Solución y copiar prompt en el análisis`.

### Task 5: Puesta en marcha y aceptación (con Ignacio)

Cada escritura en la base o en el servidor se confirma en el momento.

- [ ] **Step 1:** confirmación de Ignacio, nombrando onems-dev `sehbnpgzqljrsqimwyuz`, para aplicar `20261110140000_ops_fix_r4.sql`. Después, comprobar permisos y los avisos de seguridad.
- [ ] **Step 2:** desplegar el agente (`deploy.ps1`) y comprobar el log.
- [ ] **Step 3:** aceptación en DEMO2 con el caso de prueba (etiqueta 99991844, caso `50b24d43-…`):
  - analizar en Telegram: la tarjeta con «Aplicar»;
  - Aplicar → Confirmar: comprobar en la base la línea `received` en PAN-DEM-003 y el caso `fixed`;
  - Deshacer: todo como estaba.
- [ ] **Step 4:** Kenya 00011844, solo vista previa: la tarjeta tiene que proponer R4. No se aplica sin decisión de Ignacio en ese momento.
- [ ] **Step 5:** limpiar los datos de prueba de DEMO2 antes del 14/11; está en el registro de seguimiento.
