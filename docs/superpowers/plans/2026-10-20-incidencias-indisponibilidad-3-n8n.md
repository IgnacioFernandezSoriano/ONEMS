# Incidencias de indisponibilidad — Plan 3/3: n8n (Telegram)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que cualquier baja declarada por Telegram (texto libre o botones) se guarde en ONEMS por `declare_panelist_unavailability`, que el panelista reciba "Recibido. Gracias por informar", y que los avisos encolados por la BD (`panelist_notification`) lleguen por Telegram.

**Architecture:** Tres cambios en n8n, cada uno sobre un workflow: (1) herramienta nueva del `time_off_subagent` en el workflow principal **[DEV]**; (2) el workflow de botones llama a la misma función; (3) workflow nuevo `Deliver panelist notifications`, clon del patrón `deliver-incident-replies` (sondeo + marcar enviado). Los JSON viven en el repo `panelist_n8n`; los cambios se hacen con el MCP de n8n sobre [DEV] y se exportan al repo. PROD se replica después por el procedimiento del repo (`docs/dev-to-prod-workflow.md`).

**Tech Stack:** n8n Cloud, nodos Postgres (`executeQuery`), Telegram, LangChain agentTool/`postgresTool`; repo `C:\Users\fernandezi\projects\ONE n8n\panelist_n8n` (git, rama `main`).

**Spec:** `docs/superpowers/specs/2026-10-20-incidencias-indisponibilidad-resolucion-automatica-design.md` (§5.1, 5.5, §8)

## Global Constraints

- Requiere el Plan 1 aplicado en onems-dev: `declare_panelist_unavailability` y `panelist_notification` deben existir. Credencial Postgres de n8n: `OneMS dev - Postgres account` (id `735a8hxfuUEDPIYD`); su rol debe poder ejecutar la función (es `postgres`/service → sí; verificar en la Tarea 1).
- **Nunca** tocar `Telegram - User initiated message` (PROD, `IkVtek2csP5AbWxB`) ni `Panelist unavailability` PROD de entrada: todo primero en `[DEV] Telegram - User initiated message` (`eeM4E4RS1UDThvUF`). Antes de cada cambio, comparar el workflow vivo con el JSON del repo (`n8n_get_workflow` vs `workflows/*.json`) y avisar si difieren.
- Escribir en n8n es una acción externa: **confirmar con el usuario** antes de cada `n8n_update_*`/`n8n_create_workflow`.
- Mensajes en 4 idiomas (es/en/fr/ar) a partir de `panelist_language`, con el mismo patrón `({es:…, en:…, fr:…, ar:…})[lang] || en` de los workflows existentes. `parse_mode` coherente (Markdown) y escapar `_`.
- Tras nodos Postgres usar `$('Nodo').first().json.X` (no `.item`): `pairedItem` se rompe (lección del repo).
- Commits en `panelist_n8n` con `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`; no pushear sin que el usuario lo pida.

## Review Focus

1. El panelista escribe fechas y después **no** confirma (o corrige): no debe guardarse nada hasta el "sí". → prueba e2e Tarea 2.
2. `error_code='overlap'`: el bot debe decir qué periodo ya existe (`ov_start`–`ov_end`) y no mandar email. → Tarea 2.
3. Panelista sin `telegram_id` numérico (usuario registrado por `@username`): el aviso queda `pending_send` sin bloquear a los demás. → Tarea 4.
4. Un aviso falla al enviar (chat bloqueado): se marca `failed` con el error y no se reintenta eternamente. → Tarea 4.
5. Dos ejecuciones del sondeo solapadas: una notificación no debe enviarse dos veces (marcar `sent` con precondición `status='pending_send'`, como hace `Mark delivered`). → Tarea 4.


## Registro de ejecución (2026-10-20)

- **Tarea 1** hecha: repo n8n commiteado (`58f370a`); permisos verificados en la práctica (la credencial de n8n ejecuta `declare_panelist_unavailability`); traspaso en `docs/integrations/2026-10-20-n8n-incidencias-indisponibilidad.md`.
- **Tarea 2** hecha en DEV (`eeM4E4RS1UDThvUF`, ejecuciones 4623/4624 vía harness: baja guardada, "Recibido. Gracias por informar.") y replicada en PROD (`IkVtek2csP5AbWxB`); commit `5201f17`. Sin probar todavía: el caso de solape por texto libre.
- **Tarea 3** aplicada en `TWeVlUeFF0WzGH86` (compartido; versión publicada verificada): `Insert unavailability` → `declare_panelist_unavailability`, IF nuevo `Declared ok?`, confirmación "Recibido. Gracias por informar.". Commit `74cf89b`. Pendiente: prueba por botones con el bot real.
- **Tarea 4** hecha: workflow `Deliver panelist notifications` (`592sTnywfgiIGKI7`), activo, cada 15 min, bot PROD, texto plano, solo últimos 7 días. Commit `74cf89b`. Prueba en curso: aviso `404e81fb-…` para Ignacio UPU (DEMO2).
- **Tarea 5**: PROD hecho (ver arriba). E2E completo con plan de la semana actual: pendiente.

---

### Task 1: Estado del repo n8n y documento de traspaso

**Files:**
- Create (en ONEMS): `docs/integrations/2026-10-20-n8n-incidencias-indisponibilidad.md`
- Modify (en `panelist_n8n`): `docs/integrations.md` §2 (tabla "Operaciones críticas": añadir `declare_panelist_unavailability` y `panelist_notification`)

- [ ] **Step 1: Repo n8n al día.** En `panelist_n8n`, `git status` muestra cambios sin commitear (4 workflows, `.mcp.json`, `workflows/patches/coordinator-email-update.md`). Preguntar al usuario si se commitean tal cual ("chore: estado de workflows a 2026-10-20") antes de seguir; no commitear `.mcp.json` si contiene secretos (comprobar con `git diff .mcp.json`).
- [ ] **Step 2: Comparar vivo vs repo** para `eeM4E4RS1UDThvUF`, `TWeVlUeFF0WzGH86`, `zpCm5uOEeDTXUIco`: exportar con `n8n_get_workflow(mode='full')` a `workflows/` (mismo nombre de fichero que ya existe) y `git diff --stat`; anotar diferencias en el commit.
- [ ] **Step 3: Verificar permisos**: con la credencial Postgres de n8n ejecutar `select has_function_privilege('public.declare_panelist_unavailability(uuid,date,date,text,text)','EXECUTE')` (vía un nodo temporal o pidiendo al usuario que lo ejecute en el SQL Editor **de onems-dev**) → `true`. Si el rol es distinto de `postgres`/`service_role`, añadir GRANT en una migración `20261020130700_grant_declare_to_n8n_role.sql` (Plan 1, Tarea extra).
- [ ] **Step 4: Documento de traspaso** `docs/integrations/2026-10-20-n8n-incidencias-indisponibilidad.md` (estilo de `2026-08-05-n8n-telegram-subsistema-c.md`): contrato de `declare_panelist_unavailability` (parámetros, JSON de éxito y cada `error_code` con el texto sugerido en 4 idiomas), contrato de `panelist_notification` (columnas, `kind`, `payload` por tipo con ejemplo real, cómo marcar `sent`/`failed`), y los tres cambios de workflow de este plan.
- [ ] **Step 5: Commit** (ONEMS) `docs(n8n): traspaso de incidencias de indisponibilidad`; (panelist_n8n) `docs: contrato declare_panelist_unavailability y panelist_notification`.

---

### Task 2: `[DEV]` — el ayudante de texto libre guarda la baja

**Files (repo panelist_n8n):**
- Modify: `workflows/telegram-user-initiated-message.json` (exportación del [DEV] tras el cambio; mantener el fichero DEV separado si el repo lo hace así: comprobar `register-new-panelist-DEV-ARCHIVED.json` como precedente y, si no hay convención, exportar a `workflows/telegram-user-initiated-message.DEV.json`).

**Interfaces:**
- Nodo nuevo `declare_time_off` (`@n8n/n8n-nodes-langchain.toolWorkflow` **o** `n8n-nodes-base.postgresTool`, el que la versión de n8n ofrezca; preferir `postgresTool`): `executeQuery` con
  `select public.declare_panelist_unavailability($1::uuid, $2::date, $3::date, $4, null) as r`
  y `queryReplacement` = `{{ $('Identify panelist').first().json.panelist_id }},{{ $fromAI('start_date','yyyy-MM-dd','string') }},{{ $fromAI('end_date','yyyy-MM-dd','string') }},{{ $fromAI('reason','vacation|sick_leave|personal|other','string') }}`. Conectado como herramienta del `time_off_subagent`.
- `systemMessage` del `time_off_subagent`, paso 5 reescrito: *When the user confirms (not before), FIRST call `declare_time_off` with start_date, end_date (yyyy-MM-dd) and reason (`vacation` for holidays, `sick_leave` for illness, `personal` otherwise). If it returns `ok:true`, THEN call `send_timeoff_to_manager` with the same summary and reply exactly, in the user's language: ES "Recibido. Gracias por informar." / EN "Received. Thank you for letting us know." / FR "Bien reçu. Merci de nous avoir prévenus." / AR "تم الاستلام. شكراً لإبلاغنا." If it returns `ok:false`, do NOT send the email; explain the `error_code` in the user's language: `overlap` → you already have a period from `ov_start` to `ov_end`, cancel it first or choose other dates; `in_past` → dates cannot be in the past; `too_long` → more than 90 days, split it; `end_before_start` → end is before start. Then stop.*

- [ ] **Step 1: Leer el nodo actual** `n8n_get_workflow(id='eeM4E4RS1UDThvUF', mode='filtered', nodeNames=['time_off_subagent','send_timeoff_to_manager','Identify panelist'])` y comprobar cómo está conectado `send_timeoff_to_manager` (tipo de nodo y conexión `ai_tool`) para replicar el patrón.
- [ ] **Step 2: Proponer el diff al usuario** (nodo nuevo + conexión + systemMessage) y, con su OK, aplicar con `n8n_update_partial_workflow` (addNode + addConnection + updateNode). Validar con `n8n_validate_workflow`.
- [ ] **Step 3: Prueba e2e por Telegram (bot DEV, panelista de DEMO2 o KENYA de prueba):**
  - "la próxima semana hago vacaciones" → propone fechas → "no, del martes al jueves" → repropone → "sí" → "Recibido. Gracias por informar." y en la BD (`q.sh`): fila nueva en `panelist_unavailability` con `reason='vacation'`, `incident_status` ≠ `new`; **antes del "sí" no existe la fila**.
  - Repetir las mismas fechas → mensaje de solape con el periodo existente; sin fila nueva; sin email.
  - "mañana estoy enfermo" → `reason='sick_leave'`, un solo día.
  - Verificar en `n8n_executions(mode='summary')` que `declare_time_off` se llamó una vez por confirmación.
- [ ] **Step 4: Exportar el [DEV] al repo** y commit `feat(telegram): el ayudante de bajas guarda la baja en ONEMS (declare_panelist_unavailability)`.

---

### Task 3: Botones — `Panelist unavailability` usa la misma función

**Files (repo panelist_n8n):**
- Modify: `workflows/panelist-unavailability.json` (nodo `Insert unavailability` y `Send confirmed`/`Send range error`)

- [ ] **Step 1:** En el workflow `TWeVlUeFF0WzGH86` (es compartido DEV/PROD: lo llaman ambos principales → **pedir confirmación explícita** porque afecta a PROD): `Insert unavailability` pasa a
  `WITH ctx AS (…igual…) SELECT public.declare_panelist_unavailability($2::uuid, (ctx.context_data->>'start_date')::date, (ctx.context_data->>'end_date')::date, 'other', null) AS r FROM ctx`
  y un nodo IF `Declared ok?` sobre `{{ $json.r.ok }}`: true → `Clear ctx after confirm` → `Send confirmed` (leer fechas de `$json.r.start_date/end_date`); false → `Send range error` con `error_code = $json.r.error_code` (ya traduce `overlap`, `in_past`, `too_long`, `end_before_start`).
- [ ] **Step 2:** Validar (`n8n_validate_workflow`) y probar por botones con el bot DEV: declarar hoy → "Listo…"; declarar solapado → error de solape. Comprobar la fila en la BD con `incident_status`.
- [ ] **Step 3:** Exportar y commit `refactor(unavailability): alta por botones via declare_panelist_unavailability`.

---

### Task 4: Workflow nuevo `Deliver panelist notifications`

**Files (repo panelist_n8n):**
- Create: `workflows/deliver-panelist-notifications.json`

**Nodos (clonar la estructura de `deliver-incident-replies.json`):**
1. `Schedule Trigger` cada 15 min.
2. `Get pending notifications` (Postgres):
   ```sql
   SELECT n.id, n.kind, n.payload, p.telegram_id, COALESCE(p.language,'en') AS language,
          (COALESCE(p.telegram_id,'') ~ '^[0-9]+$') AS entregable
   FROM panelist_notification n JOIN panelists p ON p.id = n.panelist_id
   WHERE n.status = 'pending_send' ORDER BY n.created_at LIMIT 50;
   ```
3. `Keep deliverable` (Filter `entregable == true`).
4. `Loop over notifications` (SplitInBatches 1).
5. `Build message` (Code): por `kind` y `language`:
   - `unavailability_received` → "Recibido. Gracias por informar." (4 idiomas, mismos textos que la Tarea 2) + fechas `dd/MM/yyyy`.
   - `plan_change_this_week` → cabecera según `payload.change` (`shift_date`: "Tu envío ha cambiado de fecha", `reroute_origin`: "Se te ha asignado un nuevo envío esta semana", `reroute_destination` + `recipient_role='receiver'`: "Vas a recibir un envío nuevo esta semana" / `'sender'`: "Ha cambiado el destino de tu envío", `cancel`: "Se ha anulado un envío de esta semana", `revert`: "Un cambio de esta semana se ha deshecho") + detalle: fecha (`scheduled_date`), producto, carrier, origen (`origin_node_code`, `origin_panelist_name`), destino (`destination_node_code`, `destination_panelist_name`, `destination_address.address_line1/2, postal_code, city`), y "antes: `old_date`" cuando cambia la fecha.
6. `Send notification` (Telegram, `chatId = telegram_id`, Markdown, `continueOnFail: true`).
7. IF `Sent ok?` (`$json.ok === true` o sin `error`): true → `Mark sent`:
   `UPDATE panelist_notification SET status='sent', sent_at=now() WHERE id=$1::uuid AND status='pending_send' RETURNING id;`
   false → `Mark failed`: `UPDATE panelist_notification SET status='failed', error=left($2,500) WHERE id=$1::uuid AND status='pending_send' RETURNING id;`
8. Vuelta al loop.

- [ ] **Step 1:** Proponer el JSON al usuario; con su OK `n8n_create_workflow` (inactivo), `n8n_validate_workflow`, corregir, activar.
- [ ] **Step 2: Prueba:** insertar a mano (el usuario, en el SQL Editor de **onems-dev**) una fila `panelist_notification` `kind='plan_change_this_week'` para un panelista de prueba con `telegram_id` numérico, payload de ejemplo del documento de traspaso → en ≤15 min llega el mensaje y la fila pasa a `sent`. Otra con `telegram_id` `@usuario` → queda `pending_send`. Otra con `chatId` inválido (payload ok, panelista con `telegram_id='1'`) → `failed` con `error`.
- [ ] **Step 3:** Exportar y commit `feat: workflow Deliver panelist notifications (cola panelist_notification → Telegram)`.

---

### Task 5: Prueba de punta a punta y paso a PROD

- [ ] **Step 1: E2E completo con el bot DEV** sobre una cuenta de prueba con plan aplicado en la semana actual: declarar por texto libre una baja que afecte a un envío de esta semana → en ONEMS la incidencia aparece `auto_resolved`/`pending_manager`; el panelista que recibe el envío reasignado recibe el aviso en ≤15 min; el manager resuelve una pendiente en la web → aviso al afectado si es de esta semana.
- [ ] **Step 2: PROD** siguiendo `panelist_n8n/docs/dev-to-prod-workflow.md`: replicar el nodo `declare_time_off` y el `systemMessage` en `Telegram - User initiated message` (`IkVtek2csP5AbWxB`) **con confirmación explícita**; `Panelist unavailability` ya es compartido; `Deliver panelist notifications` es único. Exportar PROD al repo y commit `chore: incidencias de indisponibilidad en PROD`.
- [ ] **Step 3:** Actualizar la memoria del asistente (`incidencias-subsistema-c.md`) con el nuevo flujo y la fecha de puesta en producción.

## Self-review

- Spec 5.1 (dos vías Telegram → `declare`; "Recibido" en línea) → Tareas 2 y 3; 5.5 (cola → Telegram) → Tarea 4; §8 (doc de traspaso) → Tarea 1; despliegue §9 → Tarea 5. Webhook de empuje: omitido a propósito (sondeo de 15 min basta; añadir si el usuario quiere inmediatez).
- Review Focus 1–2 → Tarea 2; 3–5 → Tarea 4.
