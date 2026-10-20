# Incidencias reportadas por el panelista — Tratamiento v2 — Diseño

**Fecha:** 2026-10-20
**Autor:** Ignacio Fernández (con Claude)
**Estado:** diseño acordado en conversación; revisado por builder-check (preguntas resueltas en §12).

Revisa el tratamiento de cada categoría de incidencia reportada por el panelista. Sustituye
las fichas de §3 de [2026-08-06-incidencias-reportadas-panelista-design.md](2026-08-06-incidencias-reportadas-panelista-design.md)
y reordena el procedimiento de [2026-08-06-falta-material-tratamiento-design.md](2026-08-06-falta-material-tratamiento-design.md).

**Qué existe hoy (verificado 2026-10-20 en código, BD viva y n8n vivo):**
- BD: tabla `panelist_incident`, RPCs `resolve_panelist_incident`, `mark_detail_received_manual`,
  `invalidate_detail`, `reschedule_detail`, `cancel_detail`, `update_panelist_contact`,
  `create_unavailability_from_incident`, `receive_material_shipment`, `find_surplus_donors`,
  `suggest_for_sample_move`, `apply_sample_move`. Todas aplicadas en onems-dev.
- Pantalla `/incidents/panelist-reported` (`PanelistReportedIncidents.tsx`,
  `ReportedIncidentPanel.tsx`, `useReportedIncidents.ts`, `useMaterialsTreatment.ts`) con
  bloque de acción por categoría y asistente de falta de material. En `main`.
- n8n: "Report incident" (`hwsO71yoXRHIOfHC`) y "Deliver incident replies" (`zpCm5uOEeDTXUIco`).
- **Pero en Telegram NO existe el menú de categorías.** Hoy el panelista pulsa "reportar
  incidencia", elige el envío, describe el problema en texto libre y n8n inserta **siempre**
  `category='other'` y pone la muestra en `status='incident'`. Las 9 categorías solo existen
  en la BD y en la pantalla. Por eso en la BD viva hay 3 `other`, 2 `contact_data_change` y 1
  `missing_materials` (las dos últimas, pruebas manuales).

Este documento describe **qué cambia** sobre eso. La clasificación por categoría en Telegram es
**trabajo nuevo**, no un ajuste.

---

## 0. Resumen en una frase

El panelista describe el problema en Telegram y la IA lo clasifica (con confirmación); tres categorías se resuelven solas desde ahí
(etiqueta ilegible, foto del tag, cambio de contacto), una se elimina (petición
de baja), una queda como simple registro (roto), y las que requieren al manager (falta
de material, devuelto, cómo enviar, otros) se rehacen para que la pantalla le dé los datos y las decisiones
ordenadas.

---

## 1. Intención y por qué

El manager no debe tocar incidencias que el sistema puede cerrar solo, y las que sí requieren
su decisión deben presentarle el contexto completo (quién es, cómo contactarle, si es el que
envía o el que recibe) y las opciones ya calculadas. Las incidencias que no requieren acción
se conservan como registro para estudios posteriores.

## 2. Objetivos, no-objetivos, anti-objetivos

**Objetivos**
- Clasificación de la incidencia en Telegram por la IA del agente existente, con una
  confirmación sí/no al panelista antes de actuar (sin menú de 8 botones).
- Cabecera con datos de contacto y papel (emisor/receptor) en todas las incidencias.
- Resolución automática de B y H; G sin dejar registro; C solo registro; F eliminada; E al
  manager hasta que existan los vídeos.
- A rehecha en tres secciones (stock → necesidad y suministro → replanificación).
- D con decisión inline: anular o reenviar la muestra a otro nodo del plan.
- Estado nuevo `auto_resolved`, bandeja filtrada por defecto a lo que requiere acción.

**No-objetivos**
- Informes o estadísticas nuevas: basta con que las filas queden guardadas con categoría,
  fecha, estado y cómo se resolvieron.
- Grabar los vídeos de E (los aporta el usuario; el sistema solo los envía).
- Cambiar el motor de bajas ni la pantalla de bajas (`/incidents/panelist-availability`), salvo
  aceptar un parámetro para abrir una baja concreta.
- Cambiar el modelo de IA ni el resto de herramientas del agente principal.

**Anti-objetivos**
- Duplicar la matriz de replanificación dentro del detalle de la incidencia.
- Permitir que un mensaje de Telegram cambie el `telegram_id` o el nombre del panelista.
- Que n8n escriba el plan (`allocation_plan_details`) a mano: siempre por RPC.

## 3. Restricciones (del proyecto)

- Base única `onems-dev` (`sehbnpgzqljrsqimwyuz`). Migraciones forward-only con timestamp
  posterior a `20261020150000`. Validar en el Postgres local (`127.0.0.1:5433`,
  `supabase/tests/replay_baseline.ps1`) antes de aplicar; confirmación explícita antes de aplicar.
- Multi-tenant: toda escritura aislada por `account_id`; RPCs `SECURITY DEFINER` con la guarda
  `assert_same_account` existente (permite `auth.uid()` NULL = service-role/n8n; usuario
  autenticado no-superadmin solo su cuenta). n8n deriva `account_id` del panelista.
- i18n: toda cadena nueva en `public/locales/{en,es,fr,ar}.csv`.
- `npm run lint` y `npm run build` deben pasar.
- Tests SQL nuevos en `supabase/tests/`: **no existe `incident_today()`** (es deuda DT-1);
  los tests nuevos usan fechas relativas (`current_date + n`) o implementan DT-1 primero.
- n8n: comparar el workflow vivo con el JSON del repo `panelist_n8n` antes de tocar; probar en
  `[DEV] Telegram - User initiated message` (`eeM4E4RS1UDThvUF`) antes de PROD
  (`IkVtek2csP5AbWxB`). Credencial Postgres `735a8hxfuUEDPIYD`.

## 4. Modelo de datos — cambios

- `panelist_incident.status`: añadir `auto_resolved` al CHECK
  (`open`, `in_progress`, `resolved`, `dismissed`, `auto_resolved`).
- `panelist_incident.category`: **no** se quita `unavailability_request` ni
  `tag_photo_problem` del CHECK (hay filas históricas). Se dejan de ofrecer en Telegram; en la
  pantalla se muestran solo en lectura con el botón genérico "Resolver".
- **La muestra ya no se marca `status='incident'` al reportar.** Hoy n8n lo hace para todas;
  eso bloquea después las RPCs de movimiento (`apply_sample_move` exige `pending`/`notified`)
  y la recepción normal. El estado de la muestra lo cambian solo las acciones (recibir, anular,
  reenviar). Las filas históricas en `incident` se dejan; el manager las resuelve con las
  acciones de D/anular.
- `panelist_incident.payload` (esquema mínimo, documentado en el contrato n8n):
  - `missing_materials`: `{materials?: [{name, quantity}], expected_date?, days_without_stock?,
    central_shipment_id?, donor_shipment_ids?, supply_executed_at?}`
  - `unreadable_label_receipt`: `{chosen_detail_id}`; si no hubo candidatos, `{no_candidates: true}`.
  - `how_to_send`: `{}` (futuro: `{video_language}`).
  - `contact_data_change`: `{before: {...}, after: {...}}` solo con los campos cambiados, `applied: true`.
  - `parcel_returned`: `{decision: 'cancelled' | 'rerouted', to_node_id?, week_start?}`.
- Papel del panelista en el envío señalado: **se calcula**, no se guarda. Si
  `allocation_plan_details.sender_panelist_id = panelist_id` → emisor; si
  `receiver_panelist_id = panelist_id` → receptor; si no hay envío → sin papel.
- Vídeos de E (futuro): se guardarán en **n8n** (nodo Set con mapa `{en, es, fr, ar} → file_id
  o URL`). ONEMS no necesita saber dónde están.

## 5. Regla general de la pantalla

**Cabecera** (todas las categorías): nombre, código, teléfono, email, Telegram (sí/no),
idioma, ciudad; y una etiqueta **"Emisor"** / **"Receptor"** junto al envío enlazado, con
transportista, producto, nodo origen → nodo destino y fecha programada.

**Estado:** cada acción deja el estado que corresponde (ver fichas). El bloque "Resolver /
Respuesta al panelista" se mantiene para las categorías que requieren al manager (A, D, E, I y
las históricas).

**Bandeja:** por defecto filtra `open` + `in_progress`. Selector de estado permite ver
`auto_resolved`, `resolved`, `dismissed`. El contador del menú cuenta solo `open` +
`in_progress` (ya es así).

## 6. Fichas por categoría

### A. `missing_materials` — Falta de materiales (manager)

Reordena el asistente existente (`MissingMaterialsActions` + `useMaterialsTreatment`) en
tres secciones visibles a la vez, en este orden:

**Sección 1 — Stock teórico.** Tabla de `panelist_material_stocks` del panelista (material,
cantidad que nos consta, marca "bloqueante" si `material_catalog.is_blocking`). Botón
**"Poner stock a cero"**: para cada material con stock > 0 llama a
`reconcileStock(panelistId, materialId, 0)` (existente: ajusta + `material_movements`
`adjustment`). Se conserva la edición cantidad a cantidad que ya existe.

**Sección 2 — Necesidad y suministro.** Para la ventana [hoy, fin del plan activo]:
- Necesidad neta por material (`recomputeNeed`, existente; resta en-tránsito).
- Por cada material que falta, tres columnas: **stock central**, **excedente en la misma
  ciudad** (`find_surplus_donors`, existente; panelista donante y cantidad), **a comprar**.
- El sistema **propone** el origen (cascada central → donante cercano → compra). El manager
  puede cambiar el origen por material (select) antes de confirmar.
- **Fecha prevista de llegada**: por defecto hoy + `stock_settings.shipment_lead_time_days`
  (o `purchase_lead_time_days` si hay compra), **editable hasta que se crea la baja**
  (sección 3). Después queda fija en esta pantalla; si cambia, se gestiona en la pantalla de
  bajas (cancelar la baja y declarar otra), como cualquier baja.
- **Días sin stock**: nº de días **laborables L–V** (regla vigente del proyecto; sin festivos)
  entre hoy y la fecha prevista, y lista de las muestras del panelista como emisor con fecha
  programada en ese rango cuyo producto requiere un material **bloqueante** que falta.
- Botón **"Confirmar suministro"** → `executeSupply` (existente), guarda en `payload`
  `expected_date`, `days_without_stock`, ids de envíos y `supply_executed_at`. **Idempotente:**
  si `payload.supply_executed_at` existe, el botón se deshabilita y muestra los envíos creados.

**Sección 3 — Replanificar.** Botón **"Crear baja por materiales y replanificar"**
(deshabilitado si `linked_unavailability_id` ya existe): `create_unavailability_from_incident`
con razón `materials`, ventana [hoy, fecha prevista]. Al insertarse la baja, el flujo de bajas
la convierte en incidencia de indisponibilidad y resuelve automáticamente lo que puede. La
pantalla muestra entonces **"Ir a la incidencia de baja"** → `/incidents/panelist-availability?unavailability=<id>`
(la pantalla de bajas debe aceptar el parámetro y abrir ese detalle). No se duplica la matriz.
La baja por materiales es de **panelista entero** (emisor y receptor), como cualquier baja; el
motor no la distingue, solo la razón.

**Estado:** `in_progress` tras cualquier acción; `resolved` lo pone el cierre existente
(`receive_material_shipment` cierra la baja y la incidencia cuando el panelista confirma
recepción del material).

### B. `unreadable_label_receipt` — Etiqueta ilegible (automática)

- **n8n:** al elegir esta categoría, lista los envíos **en camino hacia el panelista**
  (`allocation_plan_details` con `status='sent'` y `receiver_panelist_id` = él) mostrando
  transportista, producto y nº de etiquetas del producto. El panelista elige uno; n8n lanza la
  **declaración de recepción normal** (sub-workflow "Mark Parcel as received" con el
  `detail_id` elegido). **Orden:** recepción primero; si tiene éxito, inserta la incidencia
  `auto_resolved` con `payload.chosen_detail_id`; si falla, inserta `open` con
  `payload.error` para que el manager la vea.
- Si no hay candidatos, n8n lo dice al panelista e inserta `open` con
  `payload.no_candidates=true` (único caso normal en que B llega a la bandeja).
- **Pantalla:** solo lectura; sin botón de recepción manual (se quita el actual).

### C. `parcel_damaged` — Roto (solo registro)

- **n8n:** inserta `auto_resolved`. Mensaje al panelista: "Registrado, gracias". La muestra no
  cambia de estado.
- **Pantalla:** solo lectura; se quita el botón "Invalidar muestra".

### D. `parcel_returned` — Devuelto (manager)

Un paquete devuelto vuelve a manos del **emisor**, que lo conserva con su etiqueta. "Mover a
otro nodo" significa **reenviar la misma muestra (mismo tag) a otro nodo destino en otra
semana**; el emisor no cambia.

- **Pantalla:** dos acciones:
  - **Anular**: `cancel_detail` (existente).
  - **Reenviar a otro nodo**: selector de nodo destino (nodos de la cuenta en la **misma
    ciudad del destino actual** primero, luego el resto) y de semana (desde la actual); al
    elegir muestra el resultado de `suggest_for_sample_move(p_detail_id, from_node=destino
    actual, to_node, week_start)` (carga resultante / avisos) y botón **Confirmar** →
    RPC nueva `reroute_returned_sample(p_detail_id, p_to_node_id, p_week_start)` que:
    (1) comprueba que el estado actual es `sent` o `incident`, (2) lo pone en `pending`
    conservando `tag_id`, (3) llama a `apply_sample_move` con el extremo destino, (4) devuelve
    el resultado. Las notificaciones a los afectados las genera `apply_sample_move`.
    `p_reference_load`/`p_deviation_percent` se dejan en sus defaults (no se exponen).
- Se quita el "Reprogramar a fecha" actual (el reenvío por semana lo sustituye).
- **Estado:** `in_progress` tras la acción; "Resolver" con respuesta al panelista lo cierra.

### E. `how_to_send` — Cómo enviar (manager, de momento)

**Los vídeos no existen todavía** (2026-10-20). Mientras no existan, esta categoría la atiende
el manager, que se pone en contacto con el panelista.

- **n8n:** inserta la incidencia `open` (email al manager, como A/D/I) y responde al panelista:
  "Gracias, un responsable se pondrá en contacto contigo para explicarte cómo hacer el envío".
- **Pantalla:** cabecera con los datos de contacto (teléfono, Telegram) bien visibles; sin
  acción propia; el manager resuelve con "Resolver" y, si quiere, respuesta por Telegram.
- **Futuro (cuando haya vídeos, uno por idioma):** pasar a automática: n8n envía el vídeo del
  idioma del panelista e inserta `auto_resolved` con `payload.video_language`. Es solo un
  cambio en n8n; la pantalla no cambia.

### F. `unavailability_request` — Petición de baja (eliminada)

- **n8n:** no aparece en el menú nuevo. El panelista ya tiene el flujo de botones de baja
  (`TWeVlUeFF0WzGH86`).
- **Pantalla:** filas históricas en solo lectura con "Resolver". Se quita el formulario de baja.

### G. `tag_photo_problem` — Foto del tag (automática, sin registro)

- **n8n:** pide al panelista que escriba el número de la etiqueta y lo pasa al flujo de texto
  existente ("Call Process tag photo (text)" / "Assign tag to parcel (direct)").
  **No inserta en `panelist_incident`.**
- **Pantalla:** nada nuevo (filas históricas en lectura).

### H. `contact_data_change` — Cambio de contacto (automática)

- **n8n:** pregunta qué campo cambia (botones: teléfono, email, idioma, dirección), pide el
  valor, lo **valida** (email: patrón básico `x@y.z`; teléfono: solo dígitos, `+`, espacios,
  7–20 caracteres; idioma: uno de `en/es/fr/ar`; dirección: texto ≤ 200), pide confirmación
  sí/no y llama a `update_panelist_contact` ampliada. Inserta `auto_resolved` con
  `payload.before/after`. Mensaje: "Datos actualizados".
- **No** se puede cambiar `telegram_id` (identifica al panelista en este canal) ni `name`.
- **Pantalla:** solo lectura, muestra antes/después desde `payload`.

### I. `other` — Otros (manager, como hoy)

- Sin cambios: texto libre, nota interna, respuesta al panelista por Telegram
  (`reply_status='pending_send'` → "Deliver incident replies"). También sigue siendo el
  destino del texto libre que el `incident_subagent` de IA envía al manager.

## 7. Backend — cambios (una migración forward-only)

1. CHECK de `status` con `auto_resolved`.
2. **Bug a corregir:** `create_unavailability_from_incident` convierte cualquier razón distinta
   de `vacation/sick_leave/personal/training/other` en `other`, así que la baja por materiales
   que crea el frontend hoy sale como `other` aunque el CHECK ya admite `materials`
   (migración `20260807100000`). Aceptar `materials`.
3. `update_panelist_contact`: nueva firma `(p_panelist_id, p_telegram_id, p_phone, p_language,
   p_email, p_address_line1, p_address_line2, p_address_city, p_address_country)`, todas
   `DEFAULT NULL` (NULL = no tocar). Si `auth.uid()` es NULL (n8n), **ignora** `p_telegram_id`.
   Valida email (`~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'`) y `language IN ('en','es','fr','ar')`;
   error claro si no. La firma antigua de 4 parámetros se mantiene como wrapper.
4. RPC `insert_panelist_incident_auto(p_panelist_id, p_category, p_description, p_payload,
   p_detail_id, p_status DEFAULT 'auto_resolved')`: deriva `account_id` del panelista, inserta
   con `created_via='telegram'`, `resolved_at=now()` si `auto_resolved`. n8n la usa para B, C,
   E, H (y para A, D, I con `p_status='open'`) en lugar del INSERT directo: una sola forma de
   insertar y el `account_id` siempre bien derivado. `GRANT EXECUTE` a `service_role`.
5. RPC `reroute_returned_sample(p_detail_id, p_to_node_id, p_week_start)` (ficha D).
6. RPC de lectura `list_nodes_for_sample_move(p_detail_id)` → nodos activos de la cuenta con
   ciudad, ordenados (misma ciudad del destino actual primero). *(Si la pantalla de bajas ya
   tiene esa consulta en el frontend, reutilizarla y no crear la RPC — decisión del plan.)*
7. Tests `supabase/tests/reported_incidents_v2.test.sql` con fechas relativas.

## 8. Frontend — cambios

- `ReportedIncidentPanel.tsx`: cabecera ampliada (contacto + papel + envío); bloque de acción
  por categoría según §6 (quitar botones de B, C, F, G; D con selector nodo/semana; A en tres
  secciones; B/C/H solo lectura con `payload` legible).
- `PanelistReportedIncidents.tsx`: filtro de estado con `auto_resolved`; por defecto
  `open`+`in_progress`.
- `useReportedIncidents.ts`: traer `panelist` con email, mobile, telegram_id, language,
  address_city; traer de la muestra enlazada `sender_panelist_id`, `receiver_panelist_id`,
  nodos origen/destino, transportista, producto, fecha; acciones `suggestSampleMove(...)`,
  `rerouteReturnedSample(...)`, `listNodesForMove(detailId)`.
- `useMaterialsTreatment.ts`: `zeroAllStock(panelistId)`, `daysWithoutStock(panelistId,
  from, to, missingBlockingMaterialIds)`; `createDisplacementBaja` sin cambios (la RPC
  arreglada ya respeta `materials`).
- Pantalla de bajas (`PanelistAvailabilityIncidents.tsx`): aceptar `?unavailability=<id>` para
  abrir ese detalle al cargar.
- i18n: claves `reported_incidents.role.sender/receiver`, `reported_incidents.status.auto_resolved`,
  `reported_incidents.materials.zero_stock`, `.expected_date`, `.days_without_stock`,
  `.affected_samples`, `.go_to_unavailability`, `.supply_done`, `reported_incidents.returned.reroute`,
  `.to_node`, `.week`, `.confirm_reroute`, `reported_incidents.readonly_auto`,
  `reported_incidents.contact.before/after` … en los 4 CSV.

## 9. n8n — cambios

**Workflow principal `IkVtek2csP5AbWxB`** (probar antes en `eeM4E4RS1UDThvUF`):
- El panelista describe el problema en texto libre, como hoy. El `incident_subagent` (IA ya
  existente) **clasifica** el texto en una de las 8 categorías vivas (A, B, C, D, E, G, H, I)
  y extrae los datos que pueda (`payload` inicial: material que falta, dato de contacto nuevo,
  envío al que se refiere). Devuelve `{category, confidence, payload, summary}`.
- **Confirmación obligatoria** antes de actuar: el bot responde en el idioma del panelista con
  una frase ("Entiendo que te falta material para enviar. ¿Es así?") y dos botones **Sí** /
  **No, es otra cosa**. La categoría y el payload se guardan en el contexto pendiente
  (`Save pending incident ctx`, ya existe; añadir campos).
- *Sí* → rama de la categoría (ver fichas): B, G, H se resuelven dentro del flujo; C registra
  y responde; A, D, E, I piden el envío si hace falta y no lo identificó la IA (E no lo
  necesita) y llaman a "Report incident" con `status='open'`.
- *No*, o `confidence` baja (umbral: el builder lo fija; sugerido 0,7), o sin respuesta →
  `other` al manager con el texto íntegro, como hoy. Nunca se pierde una incidencia.
- Las acciones automáticas con consecuencias (B declara una recepción, H cambia datos) llevan
  además su propia confirmación (elegir envío de una lista; sí/no al dato nuevo), así que una
  clasificación errónea no ejecuta nada sin que el panelista lo vea.

**Workflow "Report incident" `hwsO71yoXRHIOfHC`:**
- Recibe `category` y `status`; sustituye el INSERT directo por `insert_panelist_incident_auto`.
- **Quita** el nodo "Update parcel status" (`status='incident'`).
- El email al manager se envía solo para A, D, E, I.

**Contrato:** nueva sección "v2 (2026-10-20)" en
`docs/integrations/2026-08-06-n8n-incidencias-reportadas.md`: RPC de inserción, payloads,
categorías retiradas, regla "no tocar `allocation_plan_details`".

Plantillas en los 4 idiomas; FR/AR con revisión nativa pendiente (nota del proyecto).

## 10. Lo que queda al builder

- Orden de las tareas y granularidad del plan (sugerido: 1 migración+tests → 2 frontend →
  3 n8n DEV → 4 n8n PROD + contrato).
- Si el selector de nodos de D reutiliza una consulta existente del frontend o la RPC §7.6.
- Formato exacto del `payload` legible en las fichas de solo lectura.
- Cómo el sub-workflow "Mark Parcel as received" recibe el `detail_id` elegido en B (leer el
  workflow vivo antes de decidir).
- Prompt de clasificación del `incident_subagent` y textos de confirmación en los 4 idiomas.

## 11. Decisiones cerradas (2026-10-20)

1. Replanificación de A en la pantalla de bajas existente, enlazada; no se duplica la matriz.
2. D se resuelve inline: reenviar la misma muestra (mismo tag) a otro nodo destino y semana;
   RPC `reroute_returned_sample` sobre `apply_sample_move`.
3. E: los vídeos no existen; mientras tanto la atiende el manager (contacta al panelista).
   Cuando existan, uno por idioma, configurados en n8n, y E pasa a automática.
4. H automática para teléfono, email, idioma y dirección, con validación y confirmación sí/no;
   nunca Telegram ni nombre.
5. Bandeja por defecto solo `open`+`in_progress`; automáticas visibles por filtro.
6. Sin informes nuevos; el registro es la propia tabla.
7. "Poner stock a cero" afecta a todos los materiales del panelista, con movimiento de ajuste.
8. Fecha prevista por defecto desde el lead time de Stock, editable hasta crear la baja.
9. G no deja registro; F se elimina del menú; sus códigos siguen en el CHECK por histórico.
10. n8n deja de marcar la muestra `status='incident'` al reportar.
11. Días sin stock = días laborables L–V; "bloqueante" = `material_catalog.is_blocking`.
12. La categoría la decide la IA del agente existente a partir del texto libre, con
    confirmación sí/no al panelista; sin menú de 8 botones (decisión del usuario: los botones
    son difíciles de entender para el panelista). Si no confirma o la IA duda → `other`.

## 12. Respuestas al builder-check

| Pregunta del revisor | Respuesta |
|---|---|
| Razón `materials` no admitida | Sí lo está (CHECK ampliado en `20260807100000`); lo que falla es la RPC, que la convierte en `other`. Se corrige (§7.2). |
| ¿El motor trata distinto la baja por materiales? | No. Panelista entero, como cualquier baja. |
| ¿Editar fecha prevista tras crear la baja? | No se puede desde aquí; se gestiona en la pantalla de bajas. Confirmar suministro es idempotente (§6.A). |
| D: ¿qué extremo se mueve y en qué estado? | Destino; la RPC nueva pasa la muestra de `sent`/`incident` a `pending` antes de mover (§6.D). |
| H: validación | En n8n y en la RPC (§6.H, §7.3). |
| Días sin stock / bloqueante | L–V sin festivos; `is_blocking` (§11.11). |
| B: orden recepción vs. inserción | Recepción primero; inserción `auto_resolved` si OK, `open` si falla (§6.B). |
| E: ¿existen los vídeos? | No. E va al manager hasta que existan (§6.E). |
| `incident_today()` | No existe; fechas relativas en tests (§3). |
