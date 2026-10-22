# Falta de material v2 — Anexo al diseño de incidencias reportadas v2

**Fecha:** 2026-10-21
**Autor:** Ignacio Fernández (con Claude)
**Amplía:** [2026-10-20-incidencias-reportadas-tratamiento-v2-design.md](2026-10-20-incidencias-reportadas-tratamiento-v2-design.md) §6.A. Donde este anexo contradice §6.A, manda el anexo.
**Estado:** acordado en conversación; pendiente de revisión del builder.

---

## 0. Resumen

Cuando un panelista no tiene material, el sistema calcula lo que necesita para el periodo, lo cubre con el excedente de panelistas de su ciudad, luego con el almacén central y por último con compra; genera la hoja de envíos para el manager; pide por Telegram al panelista donante que envíe; deja de recordarle al panelista afectado los envíos que no puede hacer; le pregunta cuándo recibe el material; y, al recibirlo, lo registra en su stock y le envía lo que tenía parado. El manager solo decide el suministro y, si queda algo sin cubrir, la replanificación.

## 1. Por qué

La versión actual (ya construida) calcula para 90 días, pone el central antes que los vecinos, no tiene en cuenta el periodo del plan, no da al manager una lista de qué enviar, no avisa al donante, sigue recordando al panelista envíos que no puede hacer y depende de que el panelista pulse "material recibido" por iniciativa propia.

## 2. Qué existe hoy (verificado 2026-10-21) y se reutiliza

- Pantalla de la incidencia `missing_materials` en tres secciones (`MissingMaterialsSections.tsx`, `useMaterialsTreatment.ts`), en `develop`.
- `material_shipments` / `_items` con `source_panelist_id` (donante) o central; `send_material_shipment(id)` descuenta stock del origen (central o donante); `receive_material_shipment(id)` suma al stock del receptor, cierra la baja por materiales y resuelve la incidencia.
- n8n: botón "Confirmar material recibido" (workflow "Material receipt" `UJiafr1Mt02dtpUy`); recordatorio diario 09:00 "On new parcel to send" (`p8497yoHcX1Z3cfH_9j5S`) que llama a "Parcels to send"; cola `panelist_notification` + "Deliver panelist notifications" (`592sTnywfgiIGKI7`, cada 15 min).
- **Problema detectado:** `receive_material_shipment` **cancela** la baja por materiales, y cancelar una baja **revierte** todo lo que el motor y el manager movieron (`incident_revert_unavailability`). Es decir, al llegar el material, las muestras replanificadas volverían a su sitio original. Se corrige en §6.

## 3. Cálculo (pantalla, sección 2)

- **Horizonte** por defecto: desde hoy hasta el último día del mes del plan en curso (el `end_date` del `allocation_plan` activo del panelista que incluya hoy; si no hay, fin del mes natural). Campo **"Días de necesidad a cubrir"** editable: si el manager lo rellena, horizonte = hoy + N días.
- **Necesidad del panelista** por material = Σ de material de sus envíos como **emisor** (`origin_node_id` = su nodo, estado `pending`/`notified`) con fecha en el horizonte, menos su stock actual, menos lo que ya tenga en camino hacia él. Se reutiliza `calculatePanelistRequirements` con el horizonte nuevo.
- **Orden de cobertura** por material:
  1. **Excedente de panelistas de la misma ciudad**: stock del donante − su propia necesidad en el **mismo horizonte**; se toman donantes de mayor a menor excedente hasta cubrir.
  2. **Almacén central** (`material_stocks`).
  3. **Compra** (lo que falte).
- El manager puede cambiar el origen de cualquier material antes de confirmar (nunca por encima de lo disponible en el origen elegido; lo que no quepa pasa a compra).
- Columnas visibles por material: necesidad · de vecinos (quién y cuánto) · del central · a comprar.
- **Fecha prevista de llegada** y **días sin stock**: solo se muestran si hay algo a comprar (o si el manager quita orígenes y queda hueco). Con todo cubierto por vecinos/central no hay baja.

## 4. Al confirmar el suministro

- Se crean los envíos de material (como hoy: uno desde central, uno por donante), en estado `pending`, enlazados a la incidencia.
- **Hoja de envíos** (nueva): vista en la propia incidencia, imprimible, con descarga **PDF** y **Excel**. Una línea por envío y material: origen (almacén central, o panelista donante con nombre, nodo, dirección y teléfono) · destino (panelista con nombre, nodo, dirección y teléfono) · material, código, cantidad · fecha en que debe llegar. Se puede volver a abrir siempre desde la incidencia; los envíos aparecen también en Stock → Envíos (son los mismos registros).
- **Envío desde central**: lo marca como enviado el manager (Stock → Envíos o la hoja), como hoy.
- **Envío desde donante**: lo gestiona el sistema por Telegram (§5).

## 5. Telegram — automatismos (n8n)

**5.1 Al donante.** Al confirmar el suministro, el donante recibe: qué material y cuánto, a quién (**solo nombre y dirección** del receptor; nunca teléfono, email ni Telegram — decisión del usuario 2026-10-21) y para cuándo, con el botón **"Ya lo he enviado"**. Al pulsarlo: `send_material_shipment` (descuenta su stock) y se confirma. Si no lo pulsa, recordatorio cada 2 días; tras el 2.º recordatorio sin respuesta, aviso al manager (*decisión mía: 2 días / 2 recordatorios*).

**5.2 No insistir al panelista afectado.** Mientras la incidencia `missing_materials` esté abierta, el recordatorio diario de las 09:00 y la lista "envíos pendientes" **omiten** sus envíos cuyo producto necesita algún material de la incidencia que aún no ha recibido. El resto de sus envíos se le siguen recordando. La regla vive en la base de datos (una función que n8n consulta), no en n8n.

**5.3 Preguntar por la recepción.** Para cada envío de material hacia él ya marcado como enviado:
- Primera pregunta: el día de la fecha prevista (central/compra) o 2 días después de que el donante lo marque enviado (*decisión mía*).
- Texto: "¿Has recibido el material de {origen} ({materiales})?" con **Sí** / **Todavía no**.
- **Sí** → `receive_material_shipment` (suma a su stock). Si con eso ya tiene todo lo de la incidencia: se le envía en ese momento la lista de envíos que tenía parados, y la incidencia se resuelve.
- **Todavía no** → se le vuelve a preguntar cada 2 días; al 3.er "todavía no", aviso al manager (*decisión mía*).
- El botón actual "Confirmar material recibido" sigue funcionando por si el panelista se adelanta.

## 5.4 Recepción parcial (decisión del usuario 2026-10-21)

- Al decir **Sí**, el bot pregunta, por cada material del envío, **cuánto le ha llegado** (botones "Todo" / "Otra cantidad" → escribe el número; 0 permitido).
- Se suma a su stock **lo que de verdad ha llegado** (`quantity_received` por línea). Si llegó todo, el envío pasa a `received`; si no, queda **parcialmente recibido** y se le sigue preguntando por el resto ("¿Te ha llegado el resto de …?"), con las mismas reglas de §5.3 (cada 2 días; aviso al manager al 3.er "todavía no").
- **Liberación por stock:** cada vez que su stock cambia (recepción total o parcial, o ajuste del manager), el sistema recorre sus envíos en espera **por orden de fecha** y libera los que puede cubrir con el stock disponible, descontando el material de cada uno. Se le envía un mensaje con los envíos liberados ("Ya puedes enviar estos: …"). Los que no alcanzan siguen en espera.
- Esto sustituye a la regla de §5.2 y §8b.3 para decidir qué está en espera: **un envío está en espera si, recorriendo sus envíos pendientes por fecha y consumiendo su stock actual, no queda material suficiente para él**, y existe una incidencia `missing_materials` suya abierta. Sin incidencia abierta no se retiene nada (comportamiento de siempre).
- La incidencia se completa cuando todos sus envíos de material están recibidos del todo, o cuando el manager la cierra (p. ej. si el resto no va a llegar).

## 6. Baja por materiales y replanificación

- Solo hace falta si queda algo **sin cubrir con stock existente** (compra o hueco). La crea el manager desde la sección 3, como hoy, con la fecha prevista como fin.
- **Corrección:** al recibir el material **no se cancela la baja** (cancelar revierte las muestras ya replanificadas). La incidencia se resuelve y la baja termina sola en su fecha. Si el material llega antes, lo replanificado se queda como está (el manager puede deshacer a mano en la pantalla de bajas si quiere).
- Si el material llega **después** de la fecha de fin de la baja, los envíos posteriores que no se replanificaron estaban parados por §5.2 y se le envían al recibir.

## 7. Fuera de alcance

- Compra automática (`purchase_orders`): sigue manual.
- Envío desde central gestionado por el sistema: lo marca el manager.
- Donantes de otras ciudades.

## 8. Decisiones (2026-10-21)

1. Horizonte = periodo del plan; campo opcional "días a cubrir".
2. Orden: vecinos de la misma ciudad → central → compra; el manager puede cambiarlo por material.
3. Al confirmar: hoja de envíos (pantalla, PDF, Excel).
4. Al donante se lo pide el sistema por Telegram y confirma "ya lo he enviado".
5. No insistir al panelista en los envíos que necesitan el material que le falta.
6. El sistema pregunta al panelista si ha recibido; al decir que sí, stock y lista de pendientes.
7. Recibir material ya no cancela la baja (evita revertir la replanificación).
8. Al donante solo se le dan nombre y dirección del receptor (la hoja de envíos del manager sí lleva teléfonos).
9. Recepción parcial: el panelista indica cuánto le ha llegado; se suma eso y se le liberan, por fecha, los envíos que pueda cubrir (§5.4).
10. *Mías:* recordatorios cada 2 días; aviso al manager tras 2 (donante) o 3 (receptor) sin respuesta; primera pregunta al receptor 2 días después del envío del donante.

## 8b. Respuestas a la revisión del builder (decisiones mías salvo que se indique)

1. **Enlace de envíos con la incidencia:** columna nueva `material_shipments.panelist_incident_id` (todos los envíos de la incidencia, central y donantes). **Incidencia completa** = todos sus envíos en `received`. `receive_material_shipment` resuelve la incidencia solo cuando el último llega (deja de usar `linked_material_shipment_id`, que se mantiene por compatibilidad).
2. **Baja:** al resolverse la incidencia la baja no se toca; termina en su fecha. Las muestras de la ventana ya las procesó el motor (movidas o pendientes de decisión del manager), así que no queda nada "atrapado". El motor de bajas no exige que baja e incidencia cierren juntas (son tablas distintas).
3. **En espera por material (§5.2) — sustituido por §5.4:** un envío del panelista (como emisor, `pending`/`notified`) está en espera si su producto necesita **cualquier** material (no solo los bloqueantes: el panelista ha dicho que no puede enviar) que figura con necesidad > 0 en una incidencia `missing_materials` abierta suya cuyos envíos no se han recibido todos. Una sola función de BD filtra **ambos** puntos de n8n (recordatorio 09:00 y lista de pendientes). Al completarse la incidencia se le manda **un mensaje** con la lista de pendientes, además de reanudar el recordatorio normal.
4. **Estado de preguntas/recordatorios:** columnas nuevas en `material_shipments` (`ask_count`, `last_asked_at`, `next_ask_at`, `donor_notified_at`) y nuevos `kind` en `panelist_notification` (`material_send_request`, `material_receipt_question`, `material_pending_released`) con `shipment_id` en el `payload`; los botones llevan el id del envío en el `callback_data` (como ya hace "Material receipt"). **Aviso al manager:** email, por el mismo canal que las incidencias ("Send Email via Resend").
5. **Horizonte:** hasta el último día del mes natural de hoy (los planes son mensuales); con "días a cubrir" manda ese valor. Cuentan los envíos del panelista como emisor en `pending`/`notified` dentro del horizonte (los ya movidos a otro nodo dejan de ser suyos). "En camino" = envíos de material hacia él en `pending`/`sent` que **no** son de esta incidencia. La necesidad de los donantes sale de la misma llamada a `calculatePanelistRequirements` (ya calcula todos los panelistas de la cuenta); `find_surplus_donors` se sustituye por ese cálculo en el cliente (misma ciudad).
6. **n8n y las RPC:** `assert_same_account` deja pasar `auth.uid()` NULL (service-role), y "Material receipt" ya llama a `receive_material_shipment` así: sin versión aparte.
7. **Orden:** el mensaje al donante sale **al confirmar el suministro**. La sección 3 deja de marcar envíos como enviados: el central lo marca el manager (botón en la hoja de envíos) y el donante por Telegram. Como recibir ya no cancela la baja, desaparece la dependencia "baja antes de enviar".

## 9. Lo que queda al builder

- Formato exacto del PDF/Excel (reutilizar la librería de exportación que ya use el proyecto).
- Cómo se programan las preguntas y recordatorios (cola `panelist_notification` + workflow periódico, o workflow nuevo con su propia consulta).
- Nombre y firma de la función de "envíos en espera por material".
