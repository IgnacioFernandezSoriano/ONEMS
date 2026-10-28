# Tratamiento de incidencia "Falta de materiales" — Diseño

**Fecha:** 2026-08-06
**Autor:** Ignacio Fernández (con Claude)
**Estado:** diseño acordado en conversación; pendiente revisión del spec antes del plan.

Extiende el marco de [incidencias reportadas por el panelista](2026-08-06-incidencias-reportadas-panelista-design.md). Define el **tratamiento completo** de la categoría `missing_materials`, que no es un botón sino un **procedimiento** que orquesta el módulo de Stock + el motor de baja/reasignación + un diálogo con el panelista.

---

## 0. Resumen

Cuando un panelista reporta que no tiene materiales para hacer un envío:
1. Se **reconcilia su stock** (lo que nos consta vs. lo que dice; se ajusta a lo real).
2. Se **recalcula todo lo que necesita** según su plan (no solo lo del envío actual).
3. Se **suministra** el material por una **cascada**: almacén central → excedente de otro panelista cercano → compra (manual/PDF).
4. Mientras no tenga el material **bloqueante**, se **desplazan las muestras de los productos afectados** (reusando el motor de baja), no todas.
5. La indisponibilidad **se cierra cuando el panelista confirma que recibió el material** (diálogo vía n8n/Telegram).

---

## 1. Decisiones cerradas (2026-08-06)

1. **Alcance del desplazamiento:** **panelista entero** durante la ventana (decisión revisada 2026-08-06 — se descarta el desplazamiento por producto para no complicarlo ahora). Reutiliza el motor de baja **tal cual**, sin extenderlo. El flag bloqueante se usa para decidir **si** hay que suspender (falta un material bloqueante de algún producto que envía), no para acotar qué muestras. *(El desplazamiento por producto queda como mejora futura.)*
2. **Fin de la indisponibilidad:** **por confirmación de recepción** del envío de material (evento), no por fecha fija. La fecha estimada (lead time) solo sirve para planificar la ventana.
3. **Flag "material bloqueante":** se añade atributo a `material_catalog` (la etiqueta RFID se marca así).
4. **Cascada de suministro:** orden **central → excedente cercano → compra**. **Sin margen de seguridad** para el donante (se toma todo su excedente por encima de su plan). La **compra real** (`purchase_orders`) se deja como está (PDF/manual) por ahora — la cascada llega hasta "hay que comprar" y ahí para.

---

## 2. Lo que YA existe (reutilizar) vs. lo que falta (construir)

### Reutilizar (cableado hoy)
- **Ajuste de stock del panelista** con nota + auditoría: `PanelistStockTab` → `panelist_material_stocks` + `material_movements` (`movement_type='adjustment'`).
- **Cálculo de necesidad por panelista según plan:** `calculatePanelistRequirements` (`src/lib/materialCalculator.ts`); fórmula `Σ(product_materials.quantity) − stock del panelista`, join `allocation_plan_details → allocation_plans → product_materials → material_catalog`.
- **Stock central + requisitos + "ordered" (en-tránsito a nivel regulador):** `material_stocks`, `useRegulatorRequirements`, `material_requirements_periods`.
- **Envío de material al panelista:** `material_shipments` / `_items`, `useStockManagement.createShipment/confirmShipment`.
- **Lead times:** columnas `stock_settings.purchase_lead_time_days` y `shipment_lead_time_days` (existen, hoy inertes).
- **Desplazamiento de muestras:** motor de baja/reasignación (subsistemas B/C).

### Construir (huecos)
- **G1. Ciclo de recepción del envío a panelista (`pending → en camino → recibido`).** HOY `confirmShipment` **borra el envío y acredita el stock del panelista al enviar** — no hay recepción. Hay que: mantener la fila como `sent`/`in_transit`, **acreditar el stock del panelista SOLO al confirmar `received`**, y que el cálculo de necesidad **reste el en-tránsito a panelista**. Esta es la espina dorsal del flujo y **corrige un bug existente**.
- **G2. Flag bloqueante** en `material_catalog` (+ marcar RFID).
- **G3. Suministro desde panelista donante** (nivel 2 cascada): detectar excedente (`stock − necesidad de su propio plan`), preferir cercanía (misma ciudad/región), crear el envío donante→receptor.
- **G4. Ventana de indisponibilidad desde lead times** (`shipment_lead_time_days` / `purchase_lead_time_days`), como fecha estimada.
- **G5. Puente incidencia → baja por materiales** (crear la indisponibilidad de **panelista entero**, ventana [hoy, expected_date], cerrarla al confirmar recepción).
- ~~G6. Extensión del motor por producto~~ — **descartado** (decisión #1 revisada: desplazamiento panelista entero, motor sin cambios). Mejora futura.
- **G7. Diálogo de recepción con el panelista** (n8n/Telegram): "va en camino" → comprobar → confirmar.

### Bugs preexistentes a corregir de paso
- `confirmShipment`/`deleteShipment` usan `shipment_id` donde la columna es `material_shipment_id` (`useStockManagement.ts:503,686-689,752`) → no casan.
- El borrado-al-enviar sin recepción (mismo que G1).

### Seguridad (preexistente, fuera de este alcance pero a resolver)
- **Todas las tablas de stock tienen RLS desactivada** (`material_stocks`, `panelist_material_stocks`, `material_movements`, `material_shipments*`, `purchase_orders*`, `stock_settings`, `material_requirements_periods`, `stock_alerts`), igual que `api_keys` y `n8n_upu_*`. Como este flujo (y n8n) las tocará, hay que **activar RLS con políticas por `account_id`** en una tarea propia antes de exponerlo. No auto-aplicar (romper acceso).

---

## 3. Modelo de datos — cambios

- **`material_catalog`**: nueva columna `is_blocking boolean NOT NULL DEFAULT false`. Un material bloqueante (RFID) hace que **cualquier producto que lo requiera** no se pueda enviar si falta. Marcar la RFID `is_blocking=true`.
- **`material_shipments`**: usar el `status` existente con ciclo real `pending → sent → received` (y `cancelled`). Añadir/usar `received_date`. El crédito a `panelist_material_stocks` ocurre en la transición a `received`, no antes. `expected_date` = fecha estimada por lead time.
- **`panelist_incident`** (ya existe): enlazar con el envío de material y la baja generada. Reutilizar `payload` para: material(es) que faltan, resultado de la reconciliación, id del `material_shipment` creado, `linked_unavailability_id` (ya existe) para la baja por materiales. (Si hace falta más estructura, se decide en el plan; preferencia: columnas mínimas + payload.)
- **`panelist_unavailability`**: la baja por materiales es de **panelista entero** (sin scope por producto), así que el motor la usa **sin cambios**. Solo hace falta una **razón nueva** `materials` en el CHECK de `reason` (extensión de la constraint) para distinguirla de vacation/sick/...

---

## 4. Procedimiento (flujo del manager, guiado)

Al abrir una incidencia `missing_materials`, la pantalla ejecuta/asiste este procedimiento:

**Paso 1 — Reconciliación de stock (con el panelista).**
- Mostrar lo que nos consta (`panelist_material_stocks`) vs. lo que el panelista dice (del texto/`payload`).
- Si hay diferencia → **confirmar con el panelista** (diálogo n8n) y, confirmado, **ajustar** `panelist_material_stocks` al valor real (+ `material_movements` `adjustment`). Paso conversacional.

**Paso 2 — Recalcular necesidad total del panelista (todo el plan).**
- `calculatePanelistRequirements` para ese panelista sobre su plan → materiales netos que necesita.
- **Restar el material ya en-tránsito hacia él** (`material_shipments` en `sent`/`in_transit` no recibidos) → evita duplicar pedidos (idempotencia).

**Paso 3 — Determinar productos afectados / bloqueo.**
- De los materiales que faltan, ¿cuáles son `is_blocking`? Los productos cuyo `product_materials` incluye un material bloqueante faltante → **bloqueados**; sus muestras entran al desplazamiento. Los que solo requieren material sustituible → siguen enviándose (pero se reponen igual).

**Paso 4 — Suministro (cascada).**
1. **Central** (`material_stocks`): si cubre → crear `material_shipment` central→panelista.
2. **Excedente de donante**: panelista cercano con `stock − necesidad_propia > 0` → crear envío donante→receptor (sin margen de seguridad). Decrementa al donante.
3. **Comprar**: si ni central ni excedentes cubren → marcar necesidad de compra (PDF/manual, como hoy); NO se automatiza `purchase_orders`.
- La **fecha estimada** de disponibilidad = hoy + `shipment_lead_time_days` (o `purchase_lead_time_days` si hay compra) → `material_shipments.expected_date` y ventana de la baja.

**Paso 5 — Desplazar muestras (baja por materiales, panelista entero).**
- Crear una `panelist_unavailability` razón `materials`, ventana [hoy, expected_date]. Panelista entero (sin scope por producto).
- El **motor de reasignación (sin cambios)** genera las propuestas de todas las muestras afectadas del panelista en la ventana → aparecen en la bandeja **"Disponibilidad de panelistas"** (subsistema C ya existente).
- **Decisión manual por muestra:** el manager resuelve **cada propuesta individualmente** (confirmar la sugerencia, cambiar nodo/fecha manualmente, o descartar) **exactamente igual que en el balance de indisponibilidad** — es la misma pantalla y el mismo flujo del subsistema C, sin nada nuevo. También puede resolver en bloque sobre la selección, como ya hace.

**Paso 6 — Diálogo de recepción y cierre.**
- Avisar al panelista "tu material va en camino" (n8n).
- Ir comprobando; cuando **confirma recepción** → `material_shipment.status='received'`, **acreditar** `panelist_material_stocks`, y **cerrar la baja por materiales** (levanta la indisponibilidad; el motor ya sabe deshacer impacto al cancelar/cerrar una baja — ver la lógica de cancelación existente).
- Marcar la incidencia `resolved` con respuesta al panelista.

---

## 5. Idempotencia y casos límite

- **Material en camino no se vuelve a pedir:** el Paso 2 resta el en-tránsito; si llega otra incidencia del mismo material con envío en curso, la cascada no reaprovisiona — informa "ya va en camino" (y opcional acelerar).
- **Donante que se quedaría corto:** al no haber margen de seguridad (decisión #4), se toma todo el excedente por encima de su plan; documentarlo (riesgo asumido).
- **Recepción que tarda más que el lead time:** la baja está abierta hasta la confirmación (evento), no hasta la fecha estimada → no reaparecen eventos prematuramente. La fecha estimada es solo planificación.
- **Producto con material sustituible faltante:** no bloquea envío; se repone pero no entra al desplazamiento.

---

## 6. Alcance de construcción (para el plan)

1. Migración: `material_catalog.is_blocking`; razón `materials` en `panelist_unavailability`; ciclo `received` de `material_shipments`.
2. Corregir bugs de `useStockManagement` (`material_shipment_id`; crédito en recepción, no en envío) + restar en-tránsito en el cálculo.
3. ~~Motor por producto~~ — **no se construye** (decisión #1: panelista entero, motor reutilizado sin cambios; la resolución manual por muestra ya la da el subsistema C existente).
4. Suministro donante-excedente (cálculo + creación de envío).
5. Orquestación del tratamiento en el detalle de la incidencia `missing_materials` (los 6 pasos), reusando hooks de stock + motor + la bandeja del subsistema C para la decisión por muestra.
6. Diálogo n8n de recepción (contrato bidireccional; el envío de material y su confirmación).
7. RLS de las tablas de stock (tarea de seguridad, con políticas por `account_id`).

---

## 7. Cuestiones abiertas (a cerrar en el plan)

- ¿La reconciliación de stock (Paso 1) siempre exige confirmación del panelista, o el manager puede ajustar directo si el panelista ya lo afirmó en el texto del reporte?
- Definición exacta de "cercanía" del donante (misma ciudad → misma región → cuenta).
- ¿El "material sustituible" se repone en el mismo envío que el bloqueante o va aparte?
