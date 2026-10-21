# Incidencias reportadas v2 — Plan 3: n8n (clasificación por IA y ramas automáticas)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cuando el panelista pulsa "Reportar incidente" y describe el problema, la IA lo clasifica, el bot pide confirmación Sí/No, y según la categoría se resuelve solo (B, C, G, H), o llega al manager con su categoría (A, D, E, I). n8n deja de marcar la muestra como `incident` y toda alta pasa por `insert_panelist_incident_auto`.

**Architecture:** Dos workflows cambian: el sub-workflow **"Report incident"** (`hwsO71yoXRHIOfHC`, sin copia DEV: se modifica de forma compatible hacia atrás) y el principal **"Telegram - User initiated message"** (se trabaja en la copia `[DEV]` `eeM4E4RS1UDThvUF`, bot DEV, y se promueve copiando nodos al PROD `IkVtek2csP5AbWxB`). La clasificación es un nodo OpenAI con salida JSON tras el texto libre; la confirmación guarda la propuesta en `panelist_context` (`pending_incident_confirm`); un `Switch` por categoría abre las ramas. Toda lectura/escritura en la BD va por el nodo Postgres con la credencial `735a8hxfuUEDPIYD` y RPCs; nunca INSERT/UPDATE a mano en `panelist_incident` ni `allocation_plan_details`.

**Tech Stack:** n8n Cloud (`upu-one.app.n8n.cloud`), nodos Telegram / Postgres / OpenAI (`@n8n/n8n-nodes-langchain.openAi`) / Switch / Code; MCP `n8n-mcp` (`n8n_update_partial_workflow`, `n8n_validate_workflow`); repo backup `C:\Users\fernandezi\projects\ONE n8n\panelist_n8n` (`workflows/*.json`, flujo `feat/… → main`, commit DESPUÉS de promover).

**Spec:** `docs/superpowers/specs/2026-10-20-incidencias-reportadas-tratamiento-v2-design.md` (§6, §9). Requiere **Plan 1 aplicado** (RPCs `insert_panelist_incident_auto`, `update_panelist_contact_v2` de 9 parámetros, `GRANT` a `service_role` de `mark_detail_received_manual`).

## Global Constraints

- **Comparar siempre el workflow vivo con `workflows/<nombre>.json` del repo antes de tocar** (`n8n_get_workflow` vs. fichero); si difieren, el vivo manda y se exporta primero.
- Probar **todo en `[DEV] Telegram - User initiated message` (`eeM4E4RS1UDThvUF`, bot DEV)** antes de tocar PROD. No cambiar nunca `workflowId` de los sub-workflows referenciados.
- Multi-tenant: `account_id` nunca fijo; lo deriva la RPC a partir del panelista. Service-role salta RLS.
- Textos al panelista en los 4 idiomas con el patrón ya usado: `({es:'…', en:'…', fr:'…', ar:'…'})[$json.panelist_language] || '…en…'`.
- Categorías vivas para la IA (8): `missing_materials`, `unreadable_label_receipt`, `parcel_damaged`, `parcel_returned`, `how_to_send`, `tag_photo_problem`, `contact_data_change`, `other`. **Nunca** `unavailability_request`.
- Umbral de confianza: `confidence < 0.7` → se trata como `other`.
- `Route & Identify` (Code) es el único sitio donde se añaden acciones nuevas; `Main Router` (Switch) gana una salida por acción nueva.
- Al terminar cada tarea: `n8n_validate_workflow({id})` sin errores.

## Review Focus

1. El panelista escribe la descripción **y además adjunta una foto**: hoy `Route & Identify` manda las fotos a `image`, no a `incident_text`; el texto de la foto (caption) debe clasificarse igual. *(Tarea 2, prueba manual con foto + caption.)*
2. Pulsa **Sí** dos veces (doble tap del botón): la segunda no debe crear una segunda incidencia → el `pending_incident_confirm` se borra en el primer Sí y el segundo callback responde "ya registrada". *(Tarea 2.)*
3. B sin candidatos y **también** sin `parcel_id` seleccionado: `insert_panelist_incident_auto` con `p_detail_id` NULL y `payload.no_candidates=true`, estado `open`. *(Tarea 3.)*
4. H con un email mal formado: la RPC lanza `invalid email`; el bot debe mostrar un mensaje claro y volver a pedir el dato, no un error técnico. *(Tarea 3.)*
5. Panelista **sin `node_id`**: B no puede listar candidatos → mismo camino que "sin candidatos". *(Tarea 3.)*

---

## File Structure (repo `panelist_n8n`)

- Modify: `workflows/report-incident.json` — export del PROD actualizado (Tarea 1).
- Modify: `workflows/telegram-user-initiated-message.json` — export del PROD actualizado (Tarea 4).
- Create: `workflows/patches/incidencias-reportadas-v2.md` — qué nodos cambian y por qué (Tarea 4).
- Modify (repo ONEMS): `docs/integrations/2026-08-06-n8n-incidencias-reportadas.md` — sección "v2 (2026-10-20)" (Tarea 4).

---

### Task 1: "Report incident" acepta categoría/estado/payload y deja de tocar la muestra

**Files:** workflow `hwsO71yoXRHIOfHC` (vivo) + `workflows/report-incident.json`.

**Interfaces:**
- Produces: inputs del trigger `telegram_id`, `parcel_id`, `description`, `panelist_language`, **`category`** (default `other`), **`status`** (default `open`), **`payload`** (JSON string, default `{}`). Salida como hoy (`response`, `telegram_id`, `panelist_language`, `action`, `email_sent`).
- Nodo **"Insert panelist incident"** sustituido por:
  ```sql
  SELECT public.insert_panelist_incident_auto($1::uuid, $2, $3, $4::jsonb, NULLIF($5,'')::uuid, $6) AS id
  ```
  con `queryReplacement` = `[panelist_id (de Get info), category, description, payload, parcel_id, status]`. Si la RPC lanza `invalid category`, el Code previo normaliza: `category` fuera de la lista → `other`.
- Nodo **"Update parcel status"** (`status='incident'`) **eliminado**; la conexión pasa de "Insert panelist incident" a un **IF "Needs manager?"** (`status == 'open'`): true → "Build email" (camino actual); false → "Delete contexts".
- "Insert incident" (tabla legacy `shipment_incident`) se mantiene solo en el camino `open`.
- Mismo cambio, mínimo, en **"Notify manager (AI tool)"** (`Z63nZ0hYRwbtKYbC`, vía del agente de IA por texto libre): su nodo "Insert panelist incident" pasa a `SELECT public.insert_panelist_incident_auto($panelist_id, $category, $description, NULL, NULL, 'open')` (misma normalización de categoría; `unavailability_request` → `other`). Nada más cambia en ese workflow.

- [ ] **Step 1: Exportar el vivo y comparar** — `n8n_get_workflow({id:'hwsO71yoXRHIOfHC', mode:'full'})` vs `workflows/report-incident.json`. Si difieren, sobrescribir el JSON del repo con el vivo y commit `chore: sync report-incident desde n8n`.

- [ ] **Step 2: Aplicar los cambios** con `n8n_update_partial_workflow` (operaciones: `updateNode` del trigger para añadir los 3 inputs; `updateNode` de "Insert panelist incident" con la query de la RPC; `removeNode` "Update parcel status"; `addNode` IF "Needs manager?"; `addConnection`/`removeConnection` según Interfaces).

- [ ] **Step 3: Probar aislado** — *Workflow Inputs* con un panelista de DEMO2 (TEST-INCIDENCIAS): (a) `category='parcel_damaged', status='auto_resolved'` → fila `auto_resolved`, sin email, muestra sin cambiar de estado; (b) `category='parcel_returned', status='open'` → fila `open`, email al manager, muestra sin cambiar de estado; (c) sin `category` → `other`, `open`. Verificar con `execute_sql`: `SELECT category,status,resolved_at,payload FROM panelist_incident ORDER BY created_at DESC LIMIT 3` y `SELECT status FROM allocation_plan_details WHERE id='<parcel_id>'`.

- [ ] **Step 4: `n8n_validate_workflow({id:'hwsO71yoXRHIOfHC'})`** — Expected: sin errores.

- [ ] **Step 5: Exportar y commitear** (repo `panelist_n8n`, rama `feat/incidencias-reportadas-v2`): `workflows/report-incident.json`; `git commit -m "feat(report-incident): categoria/estado/payload via insert_panelist_incident_auto; ya no marca la muestra como incident"`.

---

### Task 2: Clasificación por IA y confirmación Sí/No en el `[DEV]` principal

**Files:** workflow `eeM4E4RS1UDThvUF` (vivo DEV).

**Interfaces:**
- `Route & Identify` (Code): nuevas acciones —
  - `callbackAction === 'inc_yes'` → `action = 'incident_confirm_yes'`
  - `callbackAction === 'inc_no'` → `action = 'incident_confirm_no'`
  - `callbackAction.startsWith('inc_recv:')` → `action = 'incident_receipt_pick'` (Tarea 3)
  - `callbackAction.startsWith('inc_contact:')` → `action = 'incident_contact_field'` (Tarea 3)
  - `hasPendingContactCtx && !isCallback && userMessage.length > 0` → `action = 'incident_contact_value'` (Tarea 3; `Identify panelist` gana `has_pending_contact_ctx` por `context_type='pending_contact_change'`).
- `Main Router` (Switch): una salida nueva por acción.
- Camino `incident_text` (hoy: `Get pending incident ctx` → `Call Report incident`): pasa a
  1. **"Classify incident"** (OpenAI, modelo el mismo que `OpenAI Chat Model`, `response_format: json_object`), system prompt: "Clasifica el mensaje de un panelista postal en exactamente una de estas categorías: <8 códigos con una línea de definición cada uno, copiadas del `send_incident_to_manager` actual sin `unavailability_request`>. Devuelve JSON `{category, confidence (0-1), summary (una frase en el idioma del mensaje), payload}` donde `payload` es `{materials:[{name,quantity}]}` para missing_materials, `{mobile?,email?,language?,address_line1?,address_city?,address_country?}` para contact_data_change, `{}` en el resto." User = `user_message`.
  2. **"Normalize classification"** (Code): parsea; si `category` no está en la lista o `confidence < 0.7` → `category='other'`; añade `parcel_id` del `pending_incident` ctx y `description`.
  3. **"Save incident confirm ctx"** (Postgres): `DELETE … context_type='pending_incident_confirm'; INSERT INTO panelist_context (telegram_id, context_type, context_data) VALUES ($tg, 'pending_incident_confirm', $json::jsonb)`.
  4. **"Send classify confirm"** (Telegram): texto `({es:'Entiendo que: {summary}\n¿Es así?', …})` + botones **Sí** (`inc_yes`) / **No, es otra cosa** (`inc_no`). Si `category === 'other'` **no se pregunta**: se encadena directamente con el camino "No" (abajo).
- Camino `incident_confirm_yes`: **"Get incident confirm ctx"** (SELECT + DELETE en la misma query, `RETURNING context_data`; si no devuelve fila → mensaje `({es:'Esa incidencia ya está registrada.', …})` y fin) → **"Switch category"** con 8 salidas. En esta tarea solo se cablean **A, D, E, I** → `Call Report incident` (inputs: `category`, `status='open'`, `payload`, `parcel_id`, `description` = texto original) → `Send incident result` (existente). B, C, G, H se cablean en la Tarea 3 (provisionalmente apuntan también a `Call Report incident` con `status='open'` para que nada se pierda).
- Camino `incident_confirm_no`: `Get incident confirm ctx` → `Call Report incident` con `category='other'`, `status='open'`, `description` = texto original → `Send incident result`.
- Caption de foto: en `Route & Identify`, si `hasPendingIncidentCtx && fileId` → `action = 'incident_text'` usando `caption` como `user_message` (añadir `caption` en `Set fields1`: `$json.message?.caption || ''`).

- [ ] **Step 1: Exportar el DEV vivo** (`mode:'full'`) a `C:\Users\FERNAN~1\AppData\Local\Temp\claude\…\scratchpad\dev-main-before.json` como respaldo.

- [ ] **Step 2: Aplicar los cambios** con `n8n_update_partial_workflow` (`updateNode` de `Set fields1`, `Identify panelist`, `Route & Identify`, `Main Router`; `addNode` × 6; conexiones).

- [ ] **Step 3: Probar con el bot DEV** (panelista de DEMO2 con Telegram vinculado al bot DEV):
  - "Se me ha roto el paquete al abrirlo" → confirmación "Entiendo que: el paquete llegó dañado" → **Sí** → (provisional) incidencia `parcel_damaged` `open`.
  - "No sé" (texto ambiguo) → sin pregunta, incidencia `other`.
  - "Me han devuelto el envío" → **No** → incidencia `other` con el texto íntegro.
  - Pulsar **Sí** dos veces → segunda vez "ya está registrada", una sola fila.
  - Foto con caption "etiqueta rota" → se clasifica.
  Verificar filas con `execute_sql` sobre `panelist_incident` (cuenta DEMO2, últimas 10).

- [ ] **Step 4: `n8n_validate_workflow({id:'eeM4E4RS1UDThvUF'})`** — sin errores.

- [ ] **Step 5: Anotar en `workflows/patches/incidencias-reportadas-v2.md`** (repo `panelist_n8n`) los nodos añadidos/cambiados con sus nombres exactos. Commit `wip(telegram): clasificacion IA + confirmacion si/no en [DEV]`.

---

### Task 3: Ramas automáticas B, C, G, H en el `[DEV]` principal

**Files:** workflow `eeM4E4RS1UDThvUF`.

**Interfaces (por salida del "Switch category"):**
- **C `parcel_damaged`**: Postgres `SELECT public.insert_panelist_incident_auto($panelist_id,'parcel_damaged',$description,$payload::jsonb,NULLIF($parcel_id,'')::uuid,'auto_resolved')` → Telegram `({es:'Registrado, gracias por avisar.', en:'Noted, thanks for letting us know.', fr:'Enregistré, merci de nous avoir prévenus.', ar:'تم التسجيل، شكرًا لإبلاغنا.'})`.
- **G `tag_photo_problem`**: sin INSERT. Reutilizar el camino existente `another_parcel_route` (`Clear selected parcel ctx` → `Send ask number msg`): conectar la salida G a `Clear selected parcel ctx`. El panelista escribe el número y sigue el flujo de texto ya existente (`Call Process tag photo (text)`).
- **B `unreadable_label_receipt`**: Postgres **"List receipt candidates"**:
  ```sql
  SELECT d.id, d.fecha_programada, c.name AS carrier, pr.description AS product,
         COALESCE((SELECT sum(pm.quantity) FROM product_materials pm JOIN material_catalog mc ON mc.id=pm.material_id
                   WHERE pm.product_id=ap.product_id AND mc.is_blocking), 0) AS tags
    FROM allocation_plan_details d JOIN allocation_plans ap ON ap.id=d.plan_id
    LEFT JOIN carriers c ON c.id=ap.carrier_id LEFT JOIN products pr ON pr.id=ap.product_id
   WHERE d.destination_node_id = $node_id AND d.account_id = (SELECT account_id FROM panelists WHERE id=$panelist_id)
     AND d.status = 'sent' ORDER BY d.fecha_programada LIMIT 8
  ```
  → IF "Has candidates?": **sí** → Telegram con una línea por candidato (`1. {carrier} · {product} · {tags} etiquetas · {dd/MM}`) y un botón por fila `inc_recv:<id>` + botón "Ninguno" (`inc_recv:none`); **no** (0 filas o `node_id` NULL) → `insert_panelist_incident_auto(…, 'unreadable_label_receipt', …, '{"no_candidates":true}', parcel_id, 'open')` → Telegram `({es:'No encuentro envíos en camino hacia ti; un responsable lo revisará.', …})`.
  Camino `incident_receipt_pick` (`callbackAction = inc_recv:<id>`): si `<id> = none` → igual que "no"; si no → Postgres `SELECT public.mark_detail_received_manual('<id>'::uuid)` (con `onError: continueErrorOutput`) → éxito: `insert_panelist_incident_auto(…, 'auto_resolved')` con `payload {"chosen_detail_id":"<id>"}` → Telegram `({es:'Recepción registrada, gracias.', …})`; error: `insert_panelist_incident_auto(…, 'open')` con `payload {"error": <mensaje>}` → Telegram `({es:'No he podido registrar la recepción; un responsable lo revisará.', …})`.
- **H `contact_data_change`**: Telegram **"Ask contact field"**: `({es:'¿Qué dato quieres cambiar?', …})` + botones `inc_contact:mobile` / `inc_contact:email` / `inc_contact:language` / `inc_contact:address` (textos en 4 idiomas). Camino `incident_contact_field`: guarda `pending_contact_change {field}` en `panelist_context` → Telegram `({es:'Escribe el nuevo valor.', …})` (para `language`: botones `inc_lang:en/es/fr/ar` en lugar de texto libre; el callback `inc_lang:*` entra por `incident_contact_value`). Camino `incident_contact_value`: Code **"Validate contact value"** con las mismas reglas que la RPC (email `^[^@\s]+@[^@\s]+\.[^@\s]+$`, teléfono `^[0-9+ ]{7,20}$`, idioma en lista, dirección ≤ 200) → inválido: Telegram `({es:'Ese valor no parece correcto. Escríbelo de nuevo.', …})` y se mantiene el ctx; válido: guarda `value` en el ctx y Telegram `({es:'¿Confirmas cambiar {campo} a "{valor}"?', …})` con **Sí** (`inc_contact_ok`) / **No** (`inc_contact_cancel`). `inc_contact_ok`: Postgres `SELECT public.update_panelist_contact_v2($panelist_id, NULL, $mobile, $language, $email, $address_line1, NULL, NULL, NULL)` (solo el campo elegido no NULL; `address` → `p_address_line1`) con `onError: continueErrorOutput` → éxito: `insert_panelist_incident_auto(…, 'contact_data_change', …, '{"before":{<campo>:<antes>},"after":{<campo>:<nuevo>},"applied":true}', NULL, 'auto_resolved')` (el valor "antes" se lee con un SELECT previo a `panelists`) → Telegram `({es:'Datos actualizados.', …})`; error → Telegram con el motivo legible y fin. `inc_contact_cancel`: borra el ctx y Telegram `({es:'Sin cambios.', …})`. Al terminar (ok o cancel) se borra `pending_contact_change`.

- [ ] **Step 1: Aplicar los cambios** (`n8n_update_partial_workflow`, nodos y conexiones por rama; `Route & Identify` y `Main Router` con las acciones `incident_receipt_pick`, `incident_contact_field`, `incident_contact_value`, `inc_contact_ok`, `inc_contact_cancel`, `inc_lang:*`).

- [ ] **Step 2: Probar con el bot DEV** (DEMO2; el panelista de prueba debe tener al menos una muestra `sent` hacia su nodo, creada por `execute_sql` **con confirmación** si no existe):
  - "El paquete está roto" → Sí → fila `parcel_damaged` `auto_resolved`, muestra intacta.
  - "No puedo leer la etiqueta del paquete que me ha llegado" → Sí → lista → elegir → muestra `received`, fila `auto_resolved` con `chosen_detail_id`.
  - Lo mismo con un panelista sin envíos `sent` → fila `open` con `no_candidates`.
  - "No consigo hacer la foto del tag" → Sí → pide el número; **no** se crea fila.
  - "Mi nuevo teléfono es 600 123 456" → Sí → botones de campo → teléfono → valor → confirmar → `panelists.mobile` actualizado, fila `auto_resolved` con `before/after`; probar también email inválido (`hola`) → vuelve a pedir.
  - Comprobar que `telegram_id` del panelista no ha cambiado en ningún caso.

- [ ] **Step 3: `n8n_validate_workflow({id:'eeM4E4RS1UDThvUF'})`** — sin errores.

- [ ] **Step 4: Completar `workflows/patches/incidencias-reportadas-v2.md`**; commit `wip(telegram): ramas automaticas B/C/G/H en [DEV]`.

---

### Task 4: Promover a PROD, exportar, contrato y memoria

**Files:** workflow `IkVtek2csP5AbWxB` (PROD); `workflows/telegram-user-initiated-message.json`; `docs/integrations/2026-08-06-n8n-incidencias-reportadas.md` (repo ONEMS).

- [ ] **Step 1: Comparar PROD vivo con `workflows/telegram-user-initiated-message.json`**; si difieren, exportar primero (`chore: sync`).

- [ ] **Step 2: Pedir confirmación al usuario** ("Voy a copiar los nodos nuevos del `[DEV]` al PROD `IkVtek2csP5AbWxB`; el bot de producción cambiará para todos los panelistas. ¿Confirmas?"). **No seguir sin un sí.**

- [ ] **Step 3: Promover** — replicar en PROD, con `n8n_update_partial_workflow`, exactamente las operaciones de las Tareas 2 y 3 (mismos nombres de nodo; la credencial Telegram es la de PROD `rp79mLnvGH8hxiaL`, ya puesta en los nodos existentes; los nodos Telegram nuevos deben usarla). `n8n_validate_workflow` sin errores.

- [ ] **Step 4: Prueba de humo en PROD** con el panelista de prueba de DEMO2 (Telegram PROD): un `parcel_damaged` (Sí) y un texto ambiguo (→ `other`). Verificar las dos filas y borrarlas con `execute_sql` **con confirmación** (son datos de prueba de DEMO2; recordar la regla "no tocar datos de demo" vigente: preguntar antes).

- [ ] **Step 5: Exportar PROD** → `workflows/telegram-user-initiated-message.json`; actualizar `docs/workflows-reference.md` y `docs/integrations.md` del repo n8n (categorías, RPCs usadas, `pending_incident_confirm`, `pending_contact_change`).

- [ ] **Step 6: Contrato en ONEMS** — añadir sección **"v2 (2026-10-20)"** a `docs/integrations/2026-08-06-n8n-incidencias-reportadas.md`: `insert_panelist_incident_auto` (firma, estados permitidos), `update_panelist_contact_v2` (9 parámetros; Telegram ignorado desde n8n), `mark_detail_received_manual` para B, `payload` por categoría, categorías retiradas (`unavailability_request`, `tag_photo_problem` sin registro), "la muestra ya no se marca `incident`", umbral 0,7 y confirmación Sí/No.

- [ ] **Step 7: Commits** — repo `panelist_n8n`: `feat(telegram): incidencias reportadas v2 — clasificacion IA, confirmacion y ramas automaticas (PROD)` y merge `feat/… → main` por PR. Repo ONEMS: `docs(n8n): contrato v2 de incidencias reportadas`. Actualizar la memoria `incidencias-reportadas-panelista.md` (estado: v2 VIVA en PROD; pendiente vídeos de E).
