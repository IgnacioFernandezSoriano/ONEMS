# Fase 2 - Reconocimiento del bot PROD (envio, recepcion, lista) - 2026-11-05

Fuente: repo `panelist_n8n/workflows` (PROD sin prefijo). El repo coincide con el vivo: workflow principal PROD `IkVtek2csP5AbWxB` tiene 197 nodos en ambos (ultima edicion viva 2026-11-05 12:53 = errorWorkflow, hay backup). Migraciones leidas en `ONEMS/supabase/migrations`. No se ha consultado la BD viva (el MCP supabase-onems no conecto). Ningun secreto copiado.

## 0. Resumen de arquitectura
- Un solo Telegram Trigger (updates `message` + `callback_query`) en `Telegram - User initiated message` (PROD id `IkVtek2csP5AbWxB`, credencial Telegram `One For Panelist Telegram account` id `rp79mLnvGH8hxiaL`).
- Identificacion: `Set fields1` toma `telegram_id = callback_query.from.id | message.from.id`; nodo `Identify panelist` (SQL) hace `LEFT JOIN panelists p ON p.telegram_id = $1` (telegram_id como texto) y lee todos los contextos de `panelist_context` por `telegram_id`. `Route & Identify` (Code) decide la accion; `Main Router` (Switch) ramifica. Si el telegram_id no esta en `panelists` -> flujo de registro (pide email); no es el caso de PAN-DEM-004.
- El idioma sale de `panelists.language` (es). Todos los textos van en 5 idiomas (es/en/fr/ar/pt).
- Los botones inline llevan `callback_data`; los callbacks NO usan IA. El texto libre SI pasa por OpenAI (ver 6).
- Los subflujos (Parcels to send, Save parcel selection, Process send photo, Mark Parcel as received, Parcels to receive) se llaman con Execute Workflow y la tabla de credenciales Postgres es "OneMS dev - Postgres account" (misma BD unica `sehbnpgzqljrsqimwyuz`).
- NO se envia nunca foto/video/documento desde el bot en estos 3 procesos: todo es texto (Markdown/HTML) con botones inline. Unico "vinculo" a video: el mensaje de bienvenida de `/start` lleva un enlace Markdown a un MP4 de Supabase Storage (`training-videos`), con `disable_web_page_preview`, o sea sin previsualizacion ni vídeo adjunto.

## 1. Menu y `/start` (punto de entrada opcional, 2 mensajes)
Panelista envia: texto `/start`.
Bot responde (nodos `Welcome message` -> `Send start menu`):
1. (Markdown) `🎉 *¡Hola, <PrimerNombre>!*\n\nTodo se hace con los *botones* del menú.\n\nSi tienes un problema, pulsa *Reportar incidente* y elige qué te pasa.\n\n🎬 Si tienes dudas, [mira este vídeo](<url mp4>).\n\n📖 La guía está en el botón *Ayuda*.`
2. (Markdown) `Hola <PrimerNombre>, ¿qué necesitas?` con botones inline (una fila cada uno):
   - `Ver envíos pendientes` -> `show_pending_parcels`
   - `Ver paquetes a recibir` -> `show_pending_receive`
   - `Confirmar un envío` -> `show_pending_parcels`
   - `Confirmar una recepción` -> `start_receipt`
   - `Reportar incidente` -> `report_incident`
   - `🗓️ Días no disponibles` -> `unavailability_menu`
   - `📦 Confirmar material recibido` -> `material_received`
   - `📖 Ayuda` -> boton URL (https://onems.edgeavs.net/help/panelist-guide.es.html), sin callback.
Escrituras: ninguna. Sin IA.
Cierre de sesion al final del test: boton/callback `finish_session` -> `Clean session contexts` borra de `panelist_context` los tipos pending_list, selected_parcel, pending_incident, pending_tag, pending_receipt, pending_incident_confirm, pending_incident_receipt, pending_contact_change, pending_tag_code_request y responde `👋 ¡Hasta pronto! Gracias por usar OneMS. Cuando quieras, vuelve a escribir o espera el próximo aviso. 💪` (sin botones, Markdown).

## 2. PROCESO 1 - DECLARAR UN ENVIO (declare shipment)
### Guion
| # | Panelista envia | Bot responde | Nodos |
|---|---|---|---|
| 1 | Pulsa boton `show_pending_parcels` (o escribe un texto como "quiero declarar un envío" -> OpenAI lo clasifica como `confirm_sent` -> mismo camino; recomendado el boton, sin IA) | Si `silent`=true (camino directo del bot): sin mensaje de "obteniendo informacion". Lista (HTML): `📦 <b>Tus envíos pendientes</b> (N):\n\n<b>1. <Destinatario> - <Ciudad destino></b>\n<Producto> · dd/mm/aaaa\n\n... (max 5 por pagina)\n\n[<i>(X más. Pulsa «Ver más».)</i>]\n\n👇 <b>PULSA EL NÚMERO DEL ENVÍO QUE VAS A CONFIRMAR</b>` + posible nota de envíos retenidos por falta de material. Botones: uno por envio con texto y `callback_data` = el numero global ("1","2".. "5"), mas `🏁 Finalizar` (`finish_session`). Si hay mas de 5, el mensaje "more" lleva ademas boton de "Ver más" con `callback_data` = `show_more_parcels:<offset>`. Si no hay nada: `No tienes envíos para hoy.\n📅 El próximo: <b>dd/mm/aaaa</b> (n envíos).` o `No tienes envíos pendientes.` | main: `Set fields1` -> `Identify panelist` -> `Route & Identify` (action `text`) -> `Main Router` -> `Free text needs classify?` (false si es callback) -> `Text route (no AI)` (rama `list_send`) -> `Reset list ctx` -> `Call Parcels to send (direct)` [sub `Tm2yrywGUDq0PEj3`] -> `Format parcels to send list` -> `Has more parcels?` -> `Parcels button count` -> `Send parcels to send (N)` |
| 2 | Pulsa el boton con el numero (callback_data `"1"`, o escribe `1` si hay lista pendiente) | (Markdown) `✅ *Has seleccionado este envío:*\n\n📬 *Enviar a:* <dest>\n🏠 Dirección: <dir>\n\n📦 *Qué enviar:*\nProducto: <p>\n🚚 Transportista: <c>\n\n📅 *Cuándo:* <fecha>\n\n🧰 *Materiales que necesitas:*\n• <qty> <unidad> <material> ...\n\n¿Qué quieres hacer ahora? Usa uno de los botones de abajo, o envía directamente la foto de la etiqueta o el código alfanumérico.\n\n*Si tienes algún problema para hacer el envío, pulsa el botón Reportar incidencia.*` Botones: `📷 Hacer foto a la etiqueta` (`upload_photo_label`), `⚠️ Reportar incidencia` (`report_incident`), `🔙 Volver a la lista` (`another_parcel`). (Numero fuera de rango: `⚠️ Selección inválida. Por favor responde con un número válido de la lista.`) | `Route & Identify` action `numeric` (requiere ctx pending_list y NO selected_parcel) -> `Has pending tag context?` (false) -> `Call Save parcel selection` [sub `wMuV1xhvaaHkR8sd`] -> `Send selection response` -> `Take tag code request ctx` (no hace nada salvo que exista ctx pending_tag_code_request) |
| 3 | Escribe el numero de etiqueta como TEXTO, p. ej. `20261105` -> mejor 8 digitos `12345678` (SI se puede declarar escribiendo el codigo, no hace falta foto) | (Markdown) `✅ *¡Paquete #<n> registrado como enviado!*\nEtiqueta: `<tag normalizada>`\nPara: <dest> (<ciudad>)\n📦 Te quedan *<k>* envíos por registrar hoy.` o `🎉 Has registrado todos tus envíos de hoy. ¡Gracias!` Botones: `🔢 Otro número de la lista` (`another_parcel`), `📋 Solicitar lista nueva` (`new_list`), `📥 Declarar recepción` (`start_receipt`), `🏁 Finalizar` (`finish_session`). Errores posibles (ver abajo). | `Route & Identify` action `tag_code` (requiere ctx selected_parcel y texto) -> `Call Process send photo (text)` [sub `07Kx1L9S29BfbLrV`] -> `Send send result (text)` |
Alternativa con foto (dispara OpenAI vision): paso 3' = foto con ctx selected_parcel -> `Get photo file` -> `Analyze image` (OpenAI gpt-4o-mini, texto "You should be provided a barcode, get the id...") -> `Photo + caption message` -> `Check send context` -> `Is send photo?` -> `Call Process send photo` -> `Send send result`. Foto SIN ningun contexto -> action `ambiguous` -> `Send ambiguous selector` ("🤔 No sé qué quieres declarar. Elige una opción:" + botones `📤 Declarar envío` `show_pending_parcels` / `📥 Declarar recepción` `start_receipt`). Un texto tipo etiqueta (/^[A-Za-z0-9_-]{3,}$/) sin ningun contexto activo tambien da `ambiguous`; por eso hay que pasar por la lista y seleccionar antes de escribir la etiqueta.

Mensajes de error del paso 3 (todos Markdown, mismos botones `Send send result (text)`):
- etiqueta ya usada en otro envio de la cuenta: `⚠️ La etiqueta `X` *NO* se ha registrado: ya está registrada en otro envío (a <nombre>).\nComprueba la etiqueta del paquete #n y manda la correcta.`
- paquete ya enviado: `⚠️ El paquete #n ya estaba registrado como enviado con la etiqueta `Y`. La etiqueta `X` *NO* se ha registrado....`
- sin seleccion: `⚠️ La etiqueta `X` *NO* se ha registrado: no había ningún paquete elegido....`
- formato invalido (sin ningun digito o >40): `⚠️ La etiqueta no tiene un formato válido. Escríbela de nuevo.`

### Identificacion y reglas de la etiqueta
- `Process send photo` (`07Kx1L9S29BfbLrV`): `Validate input` normaliza igual que `public.normalize_tag`: mayusculas, quita todo menos A-Z0-9; si es solo digitos quita ceros a la izquierda y rellena a 8; si mezcla letras la deja tal cual (maximo 40; debe contener algun digito). `Get panelist` = `SELECT id,name,node_id,telegram_id,language FROM panelists WHERE telegram_id=$1`.
- La etiqueta debe ser UNICA en la cuenta: el chequeo `dup` mira todas las filas de `allocation_plan_details` de la misma `account_id` con `btrim(tag_id)=tag`. Para un test diario hay que generar una etiqueta nueva cada dia (p. ej. contador de 8 digitos o fecha+serie) o limpiar la anterior en el reset.

### Escrituras en BD
Paso 1 (primera pagina; offset 0):
- `Refresh my material hold`: solo si el panelista tiene incidencia `missing_materials` abierta o `material_hold` sin liberar (si no, no escribe). Llama `refresh_material_hold(panelist_id)`.
- `UPDATE allocation_plan_details SET status='notified', origin_panelist_name=<p_orig.name>, destination_panelist_name=<p_dest.name>` para todas las filas con `origin_node_id=<nodo del panelista>`, `status='pending'`, `fecha_programada <= hoy local de la cuenta`, destino con panelista `active`, no retenidas. (Trigger `trigger_transfer_to_one_db` AFTER UPDATE: no actua salvo status 'received'. Trigger statement `refresh_incidents_on_plan_update` recalcula incidencias de baja: sin bajas activas no hace nada.)
- `panelist_context`: `DELETE ... context_type IN ('selected_parcel','pending_tag')` (Reset list ctx) y luego `DELETE`+`INSERT` de `context_type='pending_list'` con `context_data` = array JSON de todos los envios listados (hasta 200). Paginas siguientes (offset>0): solo lectura del snapshot.
Paso 2:
- `panelist_context`: `DELETE` de `selected_parcel` del telegram_id e `INSERT (telegram_id,'selected_parcel',{parcel_id, parcel_number, destination, carrier, product, date})`. (Nota: SQL con valores interpolados, sin parametros.)
Paso 3 (`Mark as sent`, una sola sentencia):
- `UPDATE allocation_plan_details SET tag_id=<tag>, idtag=<tag>, status='sent', sent_at=NOW(), sent_date=NOW(), origin_panelist_id=<panelists.id del nodo origen>` WHERE `id=<parcel_id del contexto>` AND `status IN ('pending','notified')` AND no hay duplicado de etiqueta. Triggers: `normalize_allocation_tag` (BEFORE, normaliza tag_id), `pobox_receipt_rule` (BEFORE UPDATE OF status, solo actua en status 'received'), `update_updated_at`, `refresh_incidents_on_plan_update`, `trigger_transfer_to_one_db` (no actua con 'sent').
- `DELETE FROM panelist_context WHERE telegram_id=$1 AND context_type='selected_parcel'`.
- No se crea fila en `one_db` ni en `receipt_case`, ni mensajes a otros.
Columnas de `allocation_plan_details` que cambian en el flujo completo de envio: `status` (pending -> notified -> sent), `origin_panelist_name`, `destination_panelist_name`, `tag_id`, `idtag`, `sent_at`, `sent_date`, `origin_panelist_id`, `updated_at`.

### Precondiciones (datos)
- `panelists`: PAN-DEM-004 con `telegram_id='7014977036'`, `node_id` no nulo, `language='es'`, status active.
- Una fila `allocation_plan_details` con `origin_node_id = <node_id de PAN-DEM-004>`, `account_id = DEMO2`, `status='pending'` (o `notified`), `fecha_programada <= hoy` en la zona horaria de la cuenta (`accounts.timezone`; si no hay hoy, aparece como atrasado igualmente; filas futuras no salen), `plan_id` con carrier/product (el SELECT tiene LEFT JOIN, funciona aunque falten), y un `destination_node_id` cuyo nodo tenga un panelista `status='active'` (JOIN obligatorio: sin el la fila no se lista ni se avisa). Fecha laborable (regla L-V solo para generacion, no se valida aqui). Que no este retenida por `panelist_held_detail_ids` (solo si hay incidencia missing_materials abierta). Con `tag_id` NULL (o cualquiera: se sobrescribe).
- Si se quiere que el test sea determinista: UNA sola fila pendiente para el panelista, asi siempre es el numero 1 y el mensaje final dice "Has registrado todos tus envíos de hoy". Si hay varias, el orden es `fecha_programada ASC, id ASC` y hay que elegir el boton `1`.

## 3. PROCESO 2 - DECLARAR UNA RECEPCION (declare reception)
### Guion
| # | Panelista envia | Bot responde | Nodos |
|---|---|---|---|
| 1 | Pulsa `start_receipt` (boton "Confirmar una recepción" del menu o "📥 Declarar recepción") o escribe texto tipo "he recibido un paquete" (OpenAI -> `confirm_received`, mismo camino) | (Markdown) `📥 Modo recepción. Envíame ahora la *foto del tag* del paquete que has recibido o escribe el *código alfanumérico* de la etiqueta.` Sin botones. | `Route & Identify` action `start_receipt` -> `Save pending receipt ctx` -> `Send ask receipt msg` |
| 2 | Escribe el numero de etiqueta como TEXTO (8 digitos, p. ej. `12345678`) | Caso feliz (Markdown): `✅ *¡Paquete recibido!*\nEtiqueta: `<tag>`\nDe: <Remitente> (<ciudad origen>)\n¡Gracias!` Botones: `📥 Declarar otra recepción` (`start_receipt`), `📤 Declarar envío` (`show_pending_parcels`), `🏁 Finalizar` (`finish_session`). Otros resultados (ver abajo). | `Route & Identify` action `receipt_text` (ctx pending_receipt + texto) -> `Call Mark Parcel as received (text)` [sub `pEOWvi8uU4JhYUf4`] -> `Clean pending receipt ctx` -> `Send receipt result` |
Con foto: ctx pending_receipt + foto -> action `receipt_image` -> `Get photo file` -> `Analyze image` (OpenAI vision) -> `Photo + caption message` -> `Check send context` -> `Is send photo?` (false si no hay selected_parcel) -> `Has receipt context?` -> `Call Mark Parcel as received (image)` -> `Clean pending receipt ctx` -> `Send receipt result`. OJO: si coexistieran ctx selected_parcel y pending_receipt, una foto se trataria como etiqueta de ENVIO.
Salidas de la funcion (`Receipt response`, texto es): ok -> arriba; `ok_typo_fixed` (etiqueta corregida, avisa al remitente); `ok_same_city`; `pobox_absent_no_visit`/`pobox_absent_unavailable` (solo POBOX); `not_sent_cancelled` (el remitente no la habia declarado como enviada); `wrong_city_cancelled`; `other_city_tag`; `already_received` (`ℹ️ El paquete con la etiqueta `X` ya estaba registrado como recibido. No hay que hacer nada más.`); `blocked`; `not_found` (`⚠️ La etiqueta `X` todavía *NO* se ha registrado: no encontramos ningún paquete con esta etiqueta entre los que tienes que recibir...`); `ambiguous_typo`; `invalid_format`; `no_panelist`; `no_node`.

### Escrituras en BD (todo lo decide `public.bot_receive_parcel(telegram_id, tag_raw)`, SECURITY DEFINER, migraciones 20261104120000/121000/124000/130000)
Caso feliz (status 'sent' hacia el nodo del panelista, etiqueta exacta):
- `panelist_context`: DELETE+INSERT `pending_receipt` ('{}') al empezar; DELETE `pending_receipt` al terminar.
- `receipt_match_tag` -> `register_receipt_with_rules` -> `UPDATE allocation_plan_details SET status='received', received_at=<now>, destination_panelist_id=COALESCE(actual, panelista), destination_panelist_name=COALESCE(actual, nombre)` WHERE id. Antes comprueba `sent_at <= recepcion` (si no: cancela por compensar) y la regla POBOX (`pobox_receipt_check`, solo aplica a destinos/productos POBOX; si anula crea `deferred_samples`).
- Trigger `trigger_transfer_to_one_db` (AFTER UPDATE, cuando pasa a 'received' y `transferred_to_one_db_at IS NULL`): valida `sent_at`, `received_at`, `tag_id` no vacio, `origin_panelist_id` NO NULO, `destination_panelist_id` NO NULO (si falta algo, la fila pasa a status `invalid` con `validation_errors`); si va bien hace `INSERT INTO one_db (account_id, allocation_detail_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name, sent_at, received_at, source_data_snapshot)` (trigger `one_db_compute_transit` rellena horas/dias laborables y `on_time_delivery`) y `UPDATE allocation_plan_details SET transferred_to_one_db_at=NOW(), validation_errors=NULL, transfer_error_message=NULL`.
- `receipt_case`: NO se crea fila en el caso `ok` normal (solo deja huella si cierra un caso abierto, o cuando el resultado no es ok: not_found, pobox_*, cancelled, already_received, etc., que insertan `receipt_case` con `reason`, `status` (pending/fixed/compensated/informative/needs_decision), `attempts`...).
- `panelist_notification` (kind `receipt_reminder`, al REMITENTE "culpable") solo en `ok_typo_fixed`, `pobox_absent_no_visit`, `not_sent_cancelled`, `wrong_city_cancelled`. En `ok` no hay notificacion.
Columnas de `allocation_plan_details` que cambian: `status` (sent -> received), `received_at`, `destination_panelist_id`, `destination_panelist_name` (si estaban nulos), `transferred_to_one_db_at`, `validation_errors`, `transfer_error_message`, `updated_at`.
Segunda recepcion con la misma etiqueta: `already_received` -> crea/actualiza `receipt_case` (status informative) -> evitarla en el test.

### Precondiciones
- Una fila `allocation_plan_details` con `account_id=DEMO2`, `destination_node_id = <node_id de PAN-DEM-004>` y `status='sent'`, `tag_id` = etiqueta de 8 digitos ya normalizada (p. ej. `90000001`), `sent_at` anterior a "ahora" y de los ULTIMOS 15 DIAS (si no, ver seccion 5), `origin_panelist_id` y `destination_panelist_id` NO NULOS (si no, queda `invalid`), `origin_node_id` distinto del destino (otro nodo/panelista de DEMO2; PAN-DEM-004 no puede ser origen y destino a la vez en un mismo envio razonable), `fecha_programada` coherente (la lista de "por recibir" pide `fecha_programada <= domingo de esta semana`), `plan_id` de un plan con carrier/producto/standard para que `one_db` se rellene (si falla el INSERT solo queda `transfer_error_message`, el bot igual contesta ok), producto NO POBOX.
- Panelista con `node_id` no nulo.
- Esa etiqueta no debe existir duplicada en la cuenta (el match busca primero por nodo destino y etiqueta).
- Para que el test de envio y el de recepcion sean independientes, usar DOS filas distintas (la de envio origen=PAN-DEM-004 pending; la de recepcion destino=PAN-DEM-004 sent). La fila de recepcion NO puede ser la declarada en el proceso 1 (esa va a otro destino).

### Reset de la recepcion
`UPDATE allocation_plan_details SET status='sent', received_at=NULL, transferred_to_one_db_at=NULL, validation_errors=NULL, transfer_error_message=NULL WHERE id=<fila>` (y restaurar destination_panelist_* si se quiere); `DELETE FROM one_db WHERE allocation_detail_id=<fila>`; `DELETE FROM receipt_case WHERE telegram_id='7014977036' AND created_at > <inicio del test>` (si el test dio un camino no-ok); `DELETE FROM panelist_context WHERE telegram_id='7014977036' AND context_type='pending_receipt'`. Cuidado: el trigger BEFORE `normalize_allocation_tag` no estorba; poner status='sent' no dispara one_db. Ojo con `refresh_incidents_on_plan_update`: inocuo sin bajas activas.

### Reset del envio
`UPDATE allocation_plan_details SET status='pending', tag_id=NULL, idtag=NULL, sent_at=NULL, sent_date=NULL, origin_panelist_id=<valor original o NULL> WHERE id=<fila>`; limpiar `panelist_context` (pending_list, selected_parcel) de ese telegram_id (el boton `finish_session` ya lo hace). Si se quiere repetir con la misma etiqueta, ponerla a NULL basta (la unicidad es por fila viva).

## 4. PROCESO 3 - PEDIR LA LISTA DE PAQUETES/ENVIOS
Dos listas distintas:
### 3a. "Ver envíos pendientes" (envios por hacer) = igual que paso 1 del proceso 1
Boton `show_pending_parcels` (o `new_list` = "📋 Solicitar lista nueva", o `show_more_parcels:<offset>` para paginar). Mismo mensaje y nodos del Proceso 1 paso 1. Escribe (ver arriba): `allocation_plan_details.status` pending->notified (+ nombres), `panelist_context` pending_list. Reiniciando el contexto borra selected_parcel/pending_tag.
### 3b. "Ver paquetes a recibir" (envios en camino hacia el panelista)
Panelista pulsa `show_pending_receive` (o escribe "¿qué paquetes voy a recibir?" -> OpenAI `parcels_to_receive`).
Bot (HTML): `📥 <b>Paquetes que vas a recibir</b> (N):\n\n<b>1. De <Remitente> - <Ciudad origen></b>\n📅 dd/mm/aaaa\n...\n\nCuando te llegue uno, pulsa «Declarar recepción» y envíame la foto del tag.` Botones: `📥 Declarar recepción` (`start_receipt`), `🏁 Finalizar` (`finish_session`). Vacio: `No tienes paquetes pendientes de recibir hasta el final de esta semana.` Maximo 10 filas.
Nodos: `Route & Identify` action `text` -> `Main Router` -> `Free text needs classify?` (false: es callback) -> `Text route (no AI)` rama `list_receive` -> `Call Parcels to receive (direct)` [sub `jbuilD2MD4nU3iPN`] -> `Format parcels to receive list` -> `Send parcels to receive`.
Lectura: `panelists` por telegram_id y `v_allocation_details_with_availability` con `destination_node_id=<nodo del panelista> AND status='sent' AND fecha_programada <= (lunes de esta semana + 6 dias)` ORDER BY fecha ASC LIMIT 10. SOLO LECTURA (no escribe nada).
Precondicion de 3b: la fila de recepcion de la seccion 3 (sent, destino = nodo del panelista, fecha_programada <= domingo de esta semana). Si solo se quiere verificar la lista de envios (3a), basta la fila pendiente del Proceso 1. Texto "aviso" cuando no hay filas: `Send error response` interno -> `rows.length===0` -> mensaje "vacio" (no es error).

## 5. Efectos colaterales que podrian llegar a personas reales (DEMO2)
Camino feliz de los 3 procesos: NINGUN email, NINGUN mensaje a otros panelistas, ningun grupo. Solo se escribe `panelist_context`, `allocation_plan_details`, `one_db`. Pero ojo con estos disparadores:
1. **Aviso "no recibido a los 15 dias" (email a gestor)** - workflow PROD `On parcel not received, notify Manager` (`uVkCnDSikolRe7Rjfp4Iu`), Schedule diario a las 8:00 (hora del servidor n8n). Selecciona TODA fila con `status='sent'` y `sent_at::date <= hoy-15`; la pasa a `cancelled` (`cancellation_reason='not_received_timeout'`) y envia un email via Resend (`Send Email via Resend` `ZLb752muvdIHpFYp`) a `accounts.email_panelist_manager` de la cuenta del origen; si vacio, a `accounts.admin_email`; si tambien vacio, a `<email de respaldo fijo>` (fallback fijo). Consecuencia para el test: (a) el envio declarado en el Proceso 1 queda `sent` y, si no se resetea, en 15 dias dispara un email al gestor de DEMO2 (verificar que emails tiene DEMO2 en `accounts`); (b) la fila de recepcion NO debe tener `sent_at` con 15+ dias de antiguedad o se cancelara a las 8:00 y enviara email. Resetear el envio a `pending` tras cada ejecucion lo evita.
2. **Resumen diario 9:00 local** (pg_cron `daily-parcel-summary-hourly` -> webhook n8n `daily-parcel-summary`, workflow `On new parcel to send` `p8497yoHcX1Z3cfH_9j5S`): si DEMO2 tiene a las 9:00 locales filas `pending` con fecha de hoy (o `notified` atrasadas) con origen en un panelista con telegram_id numerico y destino con panelista activo, envia por Telegram "📦 ¡Buenos días!..." a CADA panelista de DEMO2 con envios pendientes (incluido PAN-DEM-004 y cualquier otro panelista DEMO2 con telegram_id real). Es un mensaje de Telegram, no email. Para no molestar a terceros, dejar la fila de test en `pending` solo si el unico origen con telegram_id numerico es PAN-DEM-004; revisar que los demas panelistas DEMO2 no tengan telegram_id real.
3. **Recordatorios de recepcion al remitente**: `bot_receive_parcel` -> `enqueue_receipt_reminder` inserta `panelist_notification(kind='receipt_reminder')` al remitente (`culprit`), y el trigger `panelist_notice_push` (migracion 20261104123000) lo empuja a n8n `Deliver panelist notifications` (`592sTnywfgiIGKI7`) que lo manda por Telegram al remitente (hora de envio 08:00-20:00 local, `send_after`). Solo ocurre en resultados no-ok (`ok_typo_fixed`, `not_sent_cancelled`, `wrong_city_cancelled`, `pobox_absent_*`). En el camino feliz no ocurre. Si el origen de la fila de recepcion es un panelista DEMO2 con telegram_id real, un resultado raro (p. ej. etiqueta distinta) podria avisarle.
4. **Casos de recepcion not_found**: crean `receipt_case` pending; a los 5 dias laborables pasan a `needs_decision` y aparecen al gestor en la pantalla Recepciones (sin email). Un segundo `not_found` en 30 min abre una incidencia `unreadable_label_receipt` (+ `incident_message` + ctx `pending_incident_reply`) que pide foto: evitar teclear etiquetas inexistentes.
5. El Telegram Trigger es el unico canal: no hay notificacion a gestores al declarar envio/recepcion.
6. Incidencias (`Report incident`, `notify-manager-ai-tool`, `Deliver incident messages`) mandan emails/Telegram al gestor pero NO se tocan en estos 3 procesos (ojo: el boton `report_incident` esta presente en los mensajes; no pulsarlo).
Verificar en `accounts` (DEMO2, id f4d823d2-93e6-4755-9a89-9da87e7fa86e): `timezone`, `email_panelist_manager`, `admin_email`.

## 6. IA / OpenAI
- Declarar envio escribiendo el codigo: SI, sin foto. Con ctx `selected_parcel` el texto cae en `tag_code` -> `Process send photo` directamente; sin OpenAI. (Tambien vale `receipt_text` para recepcion.)
- OpenAI interviene en: (a) CUALQUIER FOTO (nodo `Analyze image`, gpt-4o-mini vision, credencial "AgentStudio (to be changed) - OpenAi account") tanto para envio como recepcion: el resultado (texto del modelo) se usa como `tag_id`; si la imagen no es un codigo de barras el modelo devuelve una frase ("can't read the barcode...") que acaba como etiqueta invalida/no encontrada; (b) CUALQUIER TEXTO LIBRE que no sea comando ni este en un contexto que lo consuma: `Classify free text` (gpt-4o-mini, 1 llamada por mensaje, temperatura 0). Texto sin contexto con aspecto de etiqueta/solo digitos NO pasa por IA: da `ambiguous` o `numeric`. (c) El AI Agent clasico esta desactivado.
- Botones (callback_data) y `/start`, `/ayuda`, `/myid` nunca llaman a OpenAI. Plan de test: usar solo botones + texto con codigo en contexto = 0 llamadas IA.

## 7. Ejecuciones n8n por corrida
Cada update de Telegram = 1 ejecucion del workflow principal; cada Execute Workflow = 1 ejecucion adicional del subflujo (aparecen en la lista de ejecuciones; segun el plan de n8n Cloud se pueden contar o no en cuota - no verificado).
Guion minimo recomendado:
- `/start` (opcional): 1 (solo principal)
- Proceso 3a/1 paso 1 `show_pending_parcels`: 1 principal + 1 `Parcels to send` = 2
- Proceso 1 paso 2 (numero): 1 + 1 `Save parcel selection` = 2
- Proceso 1 paso 3 (codigo): 1 + 1 `Process send photo` = 2
- Proceso 3b `show_pending_receive`: 1 + 1 `Parcels to receive` = 2
- Proceso 2 paso 1 `start_receipt`: 1
- Proceso 2 paso 2 (codigo): 1 + 1 `Mark Parcel as received` = 2
- `finish_session`: 1
Total ~ 13 sin `/start` (12 + 1), de ellas 8 del principal y 5 subflujos. Con repeticion del listado tras declarar (para verificar), sumar 2 por listado. A ~1 ejecucion de workflow principal por pulsacion (8-9 pulsaciones).
Disparos adicionales no del test: el trigger pg_net `panelist_notice_push`/`incident_message_push` solo si se inserta notificacion/mensaje (no en el camino feliz).

## 8. Bot Telegram
- Credencial PROD: `One For Panelist Telegram account` (id `rp79mLnvGH8hxiaL`), usada en los 57 nodos Telegram del principal PROD. Credencial DEV: `ONE4Panelist DEV Telegram Account` (id `XWH25E2sLytLHGeZ`), 57 nodos Telegram del principal DEV. Son credenciales DISTINTAS => bots/tokens distintos. `docs/dev-to-prod-workflow.md` dice que se creo un "segundo bot de Telegram ("OnePanelist Dev Bot")".
- Username del bot PROD segun documentacion del repo: `@OneMSBot` (docs/architecture.md, docs/integrations.md - con la nota "revisar nombre exacto en BotFather"; manual de formacion tambien lo usa). No aparece ningun `t.me/<bot>` ni username dentro de los JSON de workflows; es dato de documentacion, NO verificado con la API de Telegram. El username del bot DEV no aparece en ninguna parte. Los workflows DEV (`[DEV] ...` ids eeM4E4RS1UDThvUF etc.) estan ACTIVOS en n8n Cloud con su propio trigger/webhook, asi que el test debe escribir al bot PROD y no al DEV (misma BD para ambos).
- Cuidado: DEV y PROD comparten la MISMA base de datos y mismos contextos `panelist_context` por telegram_id; si PAN-DEM-004 hablara con los dos bots a la vez, los contextos se mezclan.

## 9. Riesgos/ajustes para el test
1. Orden obligatorio del envio: lista -> numero -> codigo. Escribir el codigo sin seleccionar da `ambiguous` (menu de eleccion), o `Error no context` si llega por otra ruta.
2. La lista solo muestra filas con `fecha_programada <= hoy` (zona de la cuenta). Preparar el fixture con fecha de hoy/ayer cada dia; ademas la pasa de `pending` a `notified` (el reset debe devolverla a `pending`).
3. Unicidad de etiqueta por cuenta: usar etiqueta nueva cada dia o NULL en el reset; ademas la normalizacion de 8 digitos: `1234` se guarda `00001234`; usar directamente 8 digitos para que el texto del bot coincida (`Etiqueta: `12345678``).
4. El menu `/start` ya no manda video adjunto, solo un enlace.
5. Respuesta de lista con "Obteniendo informacion... hasta 1 minuto" solo cuando se llama SIN `silent` (camino de la IA antigua); el camino directo del menu manda `silent=true`, asi que no sale.
6. Sub `Save parcel selection`/`Reset list ctx`/`Clear selected parcel ctx`/`Check send context` interpolan `telegram_id` directamente en SQL (sin inyeccion en este caso, telegram_id numerico).
7. Verificado solo por lectura de JSON y migraciones; conviene una pasada manual unica de prueba contra `execution` reciente (n8n_executions) del propio PAN-DEM-004 para confirmar los textos antes de fijar las aserciones.

## Incidencias (seguimiento: "Reportar incidente" en el bot PROD)
Fuentes: workflow principal PROD `IkVtek2csP5AbWxB`, `Report incident` (`hwsO71yoXRHIOfHC`), `Deliver incident messages` (`D8dRPQGK2HiMKzDZ`), `Notify unread incident replies` (`uW4wQDhodSus7b5z`), `Notify manager (AI tool)` (`Z63nZ0hYRwbtKYbC`), `Material questions` (`iYlRf37ly1xbCPxp`), `Missing materials dialog` (`Gq5mKym7FQq1bpU1`, solo estructura leida del vivo), migraciones 20260806160000, 20261020170000, 20261021120000, 20261022100000, 20261102120000. Sin consultar la BD viva.

### I.1 Entrada comun (2 mensajes del panelista en el camino por botones)
1. Pulsa `report_incident` (boton "Reportar incidente" del menu, o "Reportar incidencia" tras elegir envio). Route action `start_incident` -> `Save pending incident ctx` -> `Send describe incident msg`.
   Bot (sin parse mode): `⚠️ ¿Qué ha pasado? Elige una opción:` con botones (uno por fila):
   `📦 Me falta material` `inc_cat:missing_materials` / `💥 Paquete roto o dañado` `inc_cat:parcel_damaged` / `↩️ Me han devuelto un envío` `inc_cat:parcel_returned` / `🔍 No puedo leer una etiqueta` `inc_cat:unreadable_label_receipt` / `📷 No puedo hacer la foto del tag` `inc_cat:tag_photo_problem` / `❓ Duda sobre cómo enviar` `inc_cat:how_to_send` / `📱 Cambiar mis datos` `inc_cat:contact_data_change` / `💬 Otro problema` `inc_cat:other` / `🗓️ Días no disponibles` `unavailability_menu` / `↩️ Volver al menú` `unav_back`.
   Escribe: `panelist_context` DELETE de `pending_incident` y `pending_incident_confirm` del telegram_id e INSERT `pending_incident` (copia del `selected_parcel` si existe; si no, `{}`); luego la bitacora (`Build incident conversation logs` -> `Stash conversation logs`) anade los mensajes a `pending_incident.context_data.conv_logs` (aun no existe incidencia).
2. Pulsa `inc_cat:<categoria>`. Route action `incident_category_pick` (excepto `missing_materials` -> `mm_dialog`). `Prepare picked incident` fabrica el item con `status='open'`, `confidence=1`, `source='button'`, `description` = etiqueta del boton (p. ej. `💥 Paquete roto o dañado`), `payload='{}'`; `Save picked incident ctx` (`pending_incident_confirm`, ya "confirmado") -> `Get incident confirm ctx` (consume y BORRA `pending_incident_confirm` y `pending_incident`) -> `Switch category`. NO hay pregunta Si/No cuando se elige por boton.
   Texto libre (alternativa, usa OpenAI): el texto -> `Classify free text` (gpt-4o-mini, 1 llamada) -> `Prepare free-text incident` -> `Save incident confirm ctx` -> `Send classify confirm`: `Entiendo que: <resumen fijo por categoria>.\n¿Es así?` con botones `✅ Sí` `inc_yes` y `❌ No, es otra cosa` `inc_no`. `inc_yes` -> mismo camino (`Get incident confirm ctx` -> `Switch category`); `inc_no` -> descarta (sin incidencia) y manda el menu de inicio.
3. Al crearse la incidencia, la bitacora hace `flush`: `log_incident_message(...)` una vez por mensaje (panelista: boton pulsado, `direction=inbound`, `status=received`; bot: texto enviado, `direction=outbound`, `status='sent'`), todos con `meta.report_flow=true` (y `meta.callback` en botones). Estos mensajes NO disparan `incident_message_push` (solo `outbound`+`pending_send`) NI cuentan como "sin leer" (`due_unread_reply_notifications` excluye `callback` y `report_flow`).
No se crea ctx `pending_incident_reply` (la "conversacion abierta") salvo que luego un manager escriba desde la web (`send_manager_message` -> cola `pending_send` -> push -> `Deliver incident messages` por Telegram al panelista).

Escritura comun: `public.insert_panelist_incident_auto(panelist_id, category, description, payload, detail_id, status)` (SECURITY DEFINER): `INSERT INTO panelist_incident (account_id, panelist_id, category, description, payload, allocation_plan_detail_id, status, created_via='telegram', resolved_at = now() solo si auto_resolved)`. Unico trigger del INSERT: `panelist_incident_same_account` (BEFORE, validacion). Los AFTER UPDATE (`close_reported_incident_conversation` al pasar a resolved/dismissed/auto_resolved, y otro sobre `reply_status`) solo actuan en UPDATEs. Ningun trigger envia email ni Telegram al insertar.
Emails: `Report incident` ya NO envia email al gestor (comentario del nodo 2026-10-26: las incidencias se gestionan en la pantalla Incidencias); aun lee `accounts.email_panelist_manager` en `Get info` pero no se usa.

### I.2 Por categoria
**parcel_damaged (C) - boton `inc_cat:parcel_damaged`**
- Bot (texto plano, sin botones): `Registrado, gracias por avisar.`
- DB: `insert_panelist_incident_auto(panelist_id,'parcel_damaged','💥 Paquete roto o dañado','{}',NULL,'auto_resolved')` => 1 fila `panelist_incident` (status `auto_resolved`, resolved_at=now, allocation_plan_detail_id NULL, payload `{}`) + filas `incident_message` (kind `reported`, ver I.1.3: menu "¿Qué ha pasado?", boton elegido, "Registrado..."), `panelist_context` pending_incident / pending_incident_confirm borrados. No toca `allocation_plan_details`, materiales ni `panelist_unavailability`.
- Notifica: nadie (ni email ni Telegram). No llama a `Report incident` ni a OpenAI. El gestor solo la ve en la pantalla de Incidencias.
- Ejecuciones: 2 (report_incident + inc_cat).

**parcel_returned (D) / how_to_send (E) / other (I) - `inc_cat:parcel_returned|how_to_send|other`**
- Bot final (Markdown): `✅ *Incidencia registrada*. El manager de tu cuenta la revisará y se pondrá en contacto contigo si necesita más información. ¡Gracias por reportarla!` (+ botones de continuar).
- DB: subflujo `Report incident` -> `insert_panelist_incident_auto(..., 'open')` => `panelist_incident` status `open` (pendiente del manager); `shipment_incident` (legacy) solo si hubiera `parcel_id` (por menu no hay); DELETE de `panelist_context` selected_parcel y pending_incident; `incident_message` como I.1.3.
- Notifica: nadie inmediato. Diferido: el gestor la ve en la web; solo si el MANAGER escribe al panelista, Telegram al panelista; y si el panelista contesta con texto libre y el gestor no lo lee en 1 h, `Notify unread incident replies` (cada 12 h) manda EMAIL a `accounts.email_panelist_manager` (si vacio, `accounts.admin_email`). Con botones no ocurre.
- OpenAI: no. Ejecuciones: 3 (2 principal + `Report incident`).

**tag_photo_problem (G) - `inc_cat:tag_photo_problem`**
- No crea incidencia en ese momento: prepara `selected_parcel` o un marcador `pending_tag_code_request`. Con envio elegido: `Escribe el número que aparece en la etiqueta del envío y lo registro por ti.`; sin envio: `Primero elige el envío: pulsa el botón, escribe el número del envío en la lista y después te pediré el número de la etiqueta.` con boton `show_pending_parcels`. Escribir la etiqueta despues registra el ENVIO (modifica allocation_plan_details). No apto para el test.

**unreadable_label_receipt (B) - `inc_cat:unreadable_label_receipt`**
- Bot: lista hasta 8 envios `sent` hacia el nodo del panelista (`¿Cuál de estos envíos te ha llegado? ...` + un mensaje por candidato con boton `inc_recv:<detail_id>` y opcion `inc_recv:none`). Sin candidatos: `No encuentro envíos en camino hacia ti; un responsable lo revisará.` + incidencia `open`.
- DB al elegir uno: `mark_detail_received_manual(detail_id)` (pasa el envio a `received`, dispara one_db) + incidencia `auto_resolved` con `payload {chosen_detail_id}` y `allocation_plan_detail_id`; "ninguno" o fallo => incidencia `open`. Ctx `pending_incident_receipt`. Modifica envios. Sin email. 3 ejecuciones.

**contact_data_change (H) - `inc_cat:contact_data_change`**
- Pasos: `¿Qué dato quieres cambiar?` botones `inc_contact:mobile|email|language|address` + `inc_contact_cancel`; elegir -> pide valor por texto (o botones `inc_lang:en|es|fr|ar|pt`); tras escribir -> confirmacion con `inc_contact_ok` / `inc_contact_cancel`; ok -> `update_panelist_contact_v2(...)` (CAMBIA datos reales de `panelists`) + incidencia `auto_resolved` con payload before/after; respuesta `Datos actualizados.`
- Sin emails, pero modifica la ficha (y el idioma del bot si se toca language). 5 ejecuciones.

**missing_materials (A) - `inc_cat:missing_materials`**
- Abre `Missing materials dialog` (callbacks `mm_ok:<i>`, `mm_zero:<i>`, `mm_type:<i>`, `mm_confirm`, `mm_restart`, `mm_cancel`; texto de cantidad). Al confirmar -> `Report incident` con `status open` y payload de materiales. Luego el sistema enlaza `material_shipments.panelist_incident_id`, `material_hold` retiene envios del panelista, y `Material questions` (cada hora, 08:00-20:59 locales) pregunta por Telegram al panelista/donantes y puede mandar EMAILS al gestor (`Send escalation email`, `Send undeliverable email`). Mayor impacto: NO usar en el test. Varias ejecuciones (report, cat, 3-6 pasos del dialogo, +1 subflujo por paso).

**Camino por texto libre (cualquier incidente)**: 1 llamada OpenAI gpt-4o-mini, Si/No (`inc_yes`/`inc_no`); ejecuciones: texto (1) + `inc_yes` (1) + `Report incident` (1) = 3.
Programados relacionados: `Deliver incident messages` (cada 30 min + webhook), `Notify unread incident replies` (cada 12 h, email al gestor por respuestas libres sin leer), `Material questions` (cada hora), `Notify manager (AI tool)` (herramienta del AI Agent antiguo, desactivado; no alcanzable).

### I.3 Recomendacion para el test diario: `parcel_damaged`
Motivos: nace `auto_resolved`; no llama a `Report incident` ni a OpenAI; no escribe en envios, materiales, bajas ni datos del panelista; ningun email ni Telegram a nadie (no usa `accounts.email_panelist_manager` / `admin_email`); solo 2 ejecuciones; reversible con unos DELETE.
Guion:
1. Pulsa `report_incident` -> bot: `⚠️ ¿Qué ha pasado? Elige una opción:` (+ botones).
2. Pulsa `inc_cat:parcel_damaged` -> bot: `Registrado, gracias por avisar.`
3. (Opcional) `finish_session` para limpiar contextos.
Aserciones: paso 1 contiene "¿Qué ha pasado?"; paso 2 "Registrado, gracias por avisar"; en BD 1 `panelist_incident` nuevo (panelist PAN-DEM-004, category `parcel_damaged`, status `auto_resolved`, created_via `telegram`).
Precondicion: solo que el panelista exista (telegram_id 7014977036, language es); no necesita envios.
SQL de reset (service role; `:t0` = instante de inicio del test; se borran primero los mensajes porque `incident_message.incident_id` es polimorfico):
```sql
WITH me AS (
  SELECT id FROM public.panelists
   WHERE telegram_id = '7014977036' AND account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
), inc AS (
  SELECT i.id FROM public.panelist_incident i, me
   WHERE i.panelist_id = me.id AND i.category = 'parcel_damaged' AND i.created_via = 'telegram'
     AND i.status = 'auto_resolved' AND i.created_at >= :t0
), m AS (
  DELETE FROM public.incident_message
   WHERE incident_kind = 'reported' AND incident_id IN (SELECT id FROM inc)
  RETURNING 1
)
DELETE FROM public.panelist_incident WHERE id IN (SELECT id FROM inc);

DELETE FROM public.panelist_context
 WHERE telegram_id = '7014977036'
   AND context_type IN ('pending_incident','pending_incident_confirm','pending_incident_reply');
```
Notas: (a) si el test se corta tras el paso 1 solo queda el ctx `pending_incident` (lo borra la segunda sentencia o `finish_session`); (b) filtrar por `created_at >= :t0` evita borrar incidencias reales del panelista; (c) comprobar en la BD viva que no hay FK adicionales hacia `panelist_incident` (la conocida, `material_shipments.panelist_incident_id`, es ON DELETE SET NULL); (d) `close_reported_incident_conversation` no actua porque la fila nace ya resuelta.
Alternativa menos buena: `inc_cat:how_to_send` (queda `open` en la pantalla del gestor real de DEMO2, sin email, 3 ejecuciones).
