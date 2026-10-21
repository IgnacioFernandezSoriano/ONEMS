# Incidencias v2 — Plan 6: n8n (conversación registrada + automatismos de material)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** n8n entrega los mensajes del manager y registra cada mensaje del bot y cada respuesta del panelista en la conversación de la incidencia; pide al donante que envíe el material y confirma; pregunta al receptor si lo ha recibido y cuánto; no le recuerda los envíos que no puede cubrir; y al recibir le manda los que ya puede hacer.

**Architecture:** Workflows nuevos o cambiados (probar todo con el bot DEV antes de PROD):
- **"Deliver incident messages"** (sustituye a "Deliver incident replies" `zpCm5uOEeDTXUIco`): cada 5 min + webhook push; `pending_incident_messages()` → Telegram → `mark_incident_message_sent`.
- **"Material questions"** (nuevo, cada hora de 08:00 a 20:00): `due_material_questions()` → por fila envía la pregunta (donante o receptor) con botones → `record_material_question` → `log_incident_message`.
- **"Material receipt"** (`UJiafr1Mt02dtpUy`, ampliado): botones Todo / Otra cantidad por material → `receive_material_shipment_items` → si `released_detail_ids` no vacío, mensaje "Ya puedes enviar: …" → log.
- **Donante** (rama nueva en "Material receipt" o workflow propio): callback `mat_sent:<shipment_id>` → `send_material_shipment` → confirmación → log.
- **Recordatorio diario** (`p8497yoHcX1Z3cfH_9j5S`) y **"Parcels to send"** (`Tm2yrywGUDq0PEj3`): excluir `panelist_held_detail_ids(panelist)`; antes de la consulta, `refresh_material_hold(panelist)` para cada panelista con incidencia de material abierta.
- **Registro en conversación** en los flujos de incidencias del Plan 3 (alta, confirmación de categoría, ramas automáticas): cada mensaje enviado y cada respuesta → `log_incident_message`.

**Tech Stack:** n8n Cloud, MCP `n8n-mcp`; repo `C:\Users\fernandezi\projects\ONE n8n\panelist_n8n` (`feat/… → main`, commit tras promover).

**Specs:** `docs/superpowers/specs/2026-10-21-incidencias-conversacion-design.md` (§3, §4), `docs/superpowers/specs/2026-10-21-falta-material-v2-anexo-design.md` (§5). Requiere **Plan 4 aplicado** y se ejecuta **después del Plan 3**.

## Global Constraints

- Comparar vivo vs `workflows/*.json` antes de tocar; probar en `[DEV] Telegram - User initiated message` (`eeM4E4RS1UDThvUF`, bot DEV) y en copias `[DEV]` de los subworkflows; promover a PROD solo con confirmación explícita.
- Textos al panelista en 4 idiomas (patrón `({es,en,fr,ar})[lang] || en`). Al donante solo **nombre y dirección** del receptor.
- Escrituras solo por RPC; `account_id` nunca fijo. Credencial Postgres `735a8hxfuUEDPIYD`.
- Cada mensaje enviado/recibido ligado a una incidencia → `log_incident_message` con el **texto exacto**.
- `n8n_validate_workflow` sin errores al terminar cada tarea.

## Review Focus

1. El panelista responde "Otra cantidad" y escribe texto no numérico → se le vuelve a pedir, nada se registra en stock. *(Tarea 3)*
2. Doble pulsación de "Ya lo he enviado" → `send_material_shipment` es idempotente; un solo mensaje de confirmación. *(Tarea 2)*
3. Pregunta de recepción a un panelista sin Telegram → la fila se salta y se avisa al manager por email (una vez). *(Tarea 2)*
4. Recordatorio de las 09:00 a un panelista con todos sus envíos retenidos → no recibe el resumen ("todo al día" tampoco). *(Tarea 4)*
5. Mensaje del manager con Markdown roto → se envía como texto plano (sin `parse_mode`). *(Tarea 1)*

---

### Task 1: "Deliver incident messages"

- [ ] Duplicar "Deliver incident replies" como `[DEV] Deliver incident messages`; consulta `SELECT * FROM pending_incident_messages(50)`; envío Telegram **sin** `parse_mode`; éxito → `mark_incident_message_sent(id, true, NULL, message_id)`; error → `(id, false, error)`. Mantener el webhook push. Probar con `send_manager_message` sobre una incidencia `[TEST-V2]` de DEMO2 (panelista con Telegram en el bot DEV). Validar.
- [ ] Respuestas del panelista: al enviarse un mensaje del manager, guardar `panelist_context` `pending_incident_reply {incident_kind, incident_id}` (48 h); en `Route & Identify` una acción `incident_reply` cuando haya ese contexto y llegue texto → `log_incident_message(…,'inbound','panelist', texto)` y respuesta "Mensaje enviado al responsable". Validar.

### Task 2: Peticiones al donante y preguntas de recepción

- [ ] Workflow `[DEV] Material questions` (Schedule cada hora 08–20): `SELECT * FROM due_material_questions()`; `donor_send_request` → mensaje al donante: material(es) y cantidades, **nombre y dirección** del receptor, fecha en que debe llegar; botón `mat_sent:<shipment_id>`; `receipt_question` → al receptor: "¿Has recibido el material de {origen} ({materiales})?" botones `mat_rcv_yes:<id>` / `mat_rcv_no:<id>`. Tras enviar: `record_material_question` y `log_incident_message` (incidencia = `panelist_incident_id` del envío). Aviso al manager por email ("Send Email via Resend") cuando `ask_count` alcanza 2 (donante) o 3 (receptor), una sola vez (flag en `meta` del último mensaje o `ask_count` exacto).
- [ ] Callbacks en el principal (`Route & Identify`): `mat_sent:*` → `send_material_shipment` → "Gracias, anotado" → log; `mat_rcv_no:*` → "De acuerdo, te preguntaremos más adelante" → log. Validar.

### Task 3: Recepción con cantidades

- [ ] `mat_rcv_yes:<id>` → por cada línea del envío pendiente de recibir: "{material}: ¿cuánto te ha llegado?" botones `mat_qty_all:<id>:<material_id>` / `mat_qty_other:<id>:<material_id>`; "Otra cantidad" guarda `panelist_context` `pending_material_qty` y espera un número (0..pendiente; inválido → repetir); al tener todas las cantidades → `receive_material_shipment_items(id, items)`; respuesta según `status` ("Recibido todo" / "Anotado; te preguntaremos por el resto"); si `released_detail_ids` → "Ya puedes enviar estos: …" con fecha y destino de cada uno; todo → log. El botón actual "Confirmar material recibido" del menú lleva al mismo flujo. Validar.

### Task 4: Recordatorio sin insistir

- [ ] `[DEV]` de "On new parcel to send" y "Parcels to send": antes de la consulta, `SELECT refresh_material_hold(p.id) FROM panelists p JOIN panelist_incident i ON i.panelist_id = p.id AND i.category='missing_materials' AND i.status IN ('open','in_progress')`; excluir de ambas consultas los ids de `panelist_held_detail_ids(panelist)`; si `refresh_material_hold` devolvió liberados para un panelista, enviarle "Ya puedes enviar estos: …" (log en su incidencia). Validar con un panelista de DEMO2 con incidencia de material.

### Task 5: Registro en los flujos del Plan 3

- [ ] En cada nodo Telegram de los flujos de incidencias del Plan 3 (confirmación de categoría, respuestas de B/C/H/G, resultado del alta) y en cada respuesta del panelista (texto de la incidencia, botones Sí/No, valores de contacto, elección de envío), añadir `log_incident_message` con el texto exacto y el `incident_id` (cuando aún no existe la incidencia —antes de confirmar—, guardar los mensajes en el `panelist_context` y volcarlos al crearla). Validar.

### Task 6: Promoción a PROD

- [ ] Confirmación explícita del usuario; replicar en PROD (`IkVtek2csP5AbWxB`, "Material receipt", "On new parcel to send", "Parcels to send", nuevo "Material questions", "Deliver incident messages"; desactivar "Deliver incident replies"); prueba de humo en DEMO2; exportar JSON al repo; contrato `docs/integrations/` actualizado; memoria.
