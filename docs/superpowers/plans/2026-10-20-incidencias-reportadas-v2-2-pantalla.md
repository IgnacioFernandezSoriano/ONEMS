# Incidencias reportadas v2 — Plan 2: Pantalla del manager

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** La pantalla `/incidents/panelist-reported` muestra cabecera con contacto y papel, trata cada categoría como dice el spec (A en tres secciones, D con reenvío inline, el resto solo lectura o "Resolver"), filtra por defecto lo que requiere acción y enlaza con la pantalla de bajas.

**Architecture:** Patrón página → hook → supabase. `ReportedIncidentPanel.tsx` (434 líneas) se divide: la cabecera y el bloque de falta de material salen a componentes propios; el hook `useReportedIncidents` amplía la consulta de detalle y añade las acciones de reenvío; `useMaterialsTreatment` gana dos cálculos. Sin tests automatizados de frontend: la puerta es `npm run lint` + `npm run build` + una comprobación manual en la cuenta DEMO2 descrita en cada tarea.

**Tech Stack:** React 18 + TypeScript + Vite + Tailwind, `@supabase/supabase-js`, `date-fns`, i18n CSV.

**Spec:** `docs/superpowers/specs/2026-10-20-incidencias-reportadas-tratamiento-v2-design.md` (§5, §6, §8). Requiere el **Plan 1 aplicado en onems-dev** (RPCs `reroute_returned_sample`, `list_nodes_for_sample_move`, estado `auto_resolved`).

## Global Constraints

- Todo texto visible por `t('clave')`; claves nuevas en los **4** ficheros `public/locales/{en,es,fr,ar}.csv` (formato `key,translation`, valor entre comillas dobles si contiene coma; interpolación `{var}` resuelta con `.replace('{var}', …)` o el segundo argumento de `t` cuando el componente ya lo usa así). FR/AR autogeneradas, revisión nativa pendiente (nota del proyecto).
- `npm run lint` (0 warnings) y `npm run build` deben pasar al final de **cada** tarea.
- Componentes PascalCase `.tsx`; hooks camelCase `use*`. Botones con las constantes `BTN_PRIMARY` / `BTN_SECONDARY` ya definidas en `ReportedIncidentPanel.tsx:13-14` (moverlas a `src/components/incidents/buttonStyles.ts` en la Tarea 1 para compartirlas).
- Columnas reales de `allocation_plan_details`: `origin_node_id`, `destination_node_id`, `origin_panelist_id`, `destination_panelist_id`, `fecha_programada`, `status`, `tag_id`, `plan_id`. Plan → `allocation_plans.carrier_id`, `product_id`.
- Días laborables = lunes a viernes, sin festivos.
- No tocar `IncidentReviewPanel.tsx` ni el motor de bajas; la pantalla de bajas solo gana la lectura de `?unavailability=<id>`.

## Review Focus

1. Incidencia **sin envío enlazado** (`allocation_plan_detail_id` NULL) en D: el bloque de reenvío debe mostrar un aviso y no romper (`listNodesForMove` no se llama). *(Tarea 3, comprobación manual.)*
2. Incidencia de una categoría **histórica** (`unavailability_request`, `tag_photo_problem`) o con `payload` NULL: fichas de solo lectura sin excepción al leer `payload.before`. *(Tarea 2.)*
3. "Poner stock a cero" cuando el panelista **no tiene filas** en `panelist_material_stocks`: botón deshabilitado, sin llamadas. *(Tarea 4.)*
4. Fecha prevista **anterior a hoy** escrita a mano: el campo no la acepta (`min=hoy`) y "Días sin stock" muestra 0. *(Tarea 4.)*
5. `?unavailability=<id>` con un id que **no está en la bandeja** (otra cuenta, borrado): la pantalla de bajas abre la lista normal, no un detalle vacío. *(Tarea 5.)*

---

## File Structure

- Modify: `src/lib/types.ts:521` — `ReportedIncidentStatus` + `'auto_resolved'`.
- Create: `src/components/incidents/buttonStyles.ts` — `BTN_PRIMARY`, `BTN_SECONDARY`.
- Modify: `src/lib/hooks/useReportedIncidents.ts` — detalle ampliado, `listNodesForMove`, `suggestSampleMove`, `rerouteReturnedSample`; se eliminan `actMarkReceived`, `actInvalidate`, `actReschedule`, `actCreateUnavailability` (ya sin uso).
- Create: `src/components/incidents/ReportedIncidentHeader.tsx` — cabecera (contacto + papel + envío).
- Create: `src/components/incidents/ReturnedSampleActions.tsx` — ficha D.
- Create: `src/components/incidents/MissingMaterialsSections.tsx` — ficha A (sustituye a `MissingMaterialsActions` dentro del panel).
- Modify: `src/components/incidents/ReportedIncidentPanel.tsx` — orquestación por categoría; queda < 200 líneas.
- Modify: `src/lib/hooks/useMaterialsTreatment.ts` — `zeroAllStock`, `daysWithoutStock`.
- Modify: `src/pages/incidents/PanelistReportedIncidents.tsx` — filtro de estado.
- Modify: `src/pages/incidents/PanelistAvailabilityIncidents.tsx` — `?unavailability=`.
- Modify: `public/locales/{en,es,fr,ar}.csv`.

---

### Task 1: Tipos, estilos compartidos y hook de detalle ampliado

**Files:**
- Modify: `src/lib/types.ts:521`
- Create: `src/components/incidents/buttonStyles.ts`
- Modify: `src/lib/hooks/useReportedIncidents.ts`

**Interfaces:**
- Produces en `useReportedIncidents()`:
  - `fetchIncident(id): Promise<ReportedIncidentDetail | null>` donde
    ```ts
    export interface ReportedIncidentDetail extends ReportedIncident {
      panelist: { id: string; name: string; panelist_code: string; email: string | null; mobile: string | null;
                  telegram_id: string | null; language: string | null; address_city: string | null; node_id: string | null } | null
      detail: { id: string; fecha_programada: string | null; status: string; tag_id: string | null;
                origin_node_id: string | null; destination_node_id: string | null;
                origin_panelist_id: string | null; destination_panelist_id: string | null;
                origin_node: { auto_id: string } | null; destination_node: { auto_id: string } | null;
                plan: { carrier: { name: string } | null; product: { description: string } | null } | null } | null
    }
    ```
    (select de supabase: `*, panelist:panelists(id,name,panelist_code,email,mobile,telegram_id,language,address_city,node_id), detail:allocation_plan_details(id,fecha_programada,status,tag_id,origin_node_id,destination_node_id,origin_panelist_id,destination_panelist_id, origin_node:nodes!allocation_plan_details_origin_node_id_fkey(auto_id), destination_node:nodes!allocation_plan_details_destination_node_id_fkey(auto_id), plan:allocation_plans(carrier:carriers(name), product:products(description)))` — comprobar los nombres reales de las FK en el baseline con `grep -n "allocation_plan_details.*FOREIGN KEY" supabase/migrations/00000000000000_baseline_prod_schema.sql`).
  - `panelistRole(inc: ReportedIncidentDetail): 'sender' | 'receiver' | null` — emisor si `detail.origin_panelist_id === panelist.id` o (`origin_panelist_id` NULL y `detail.origin_node_id === panelist.node_id`); receptor igual con destino; si no hay `detail`, `null`.
  - `listNodesForMove(detailId): Promise<{ node_id: string; auto_id: string; city_name: string; same_city: boolean; panelist_name: string }[]>` → `rpc('list_nodes_for_sample_move', { p_detail_id })`.
  - `suggestSampleMove(detailId, fromNodeId, toNodeId, weekStart): Promise<Record<string, any>>` → `rpc('suggest_for_sample_move', { p_detail_id, p_from_node_id, p_to_node_id, p_week_start })`.
  - `rerouteReturnedSample(detailId, toNodeId, weekStart): Promise<void>` → `rpc('reroute_returned_sample', …)`.
  - Se mantienen: `inbox`, `loading`, `error`, `openCount`, `fetchInbox`, `resolve`, `actCancel`, `signedPhotoUrl`. `actUpdateContact` se elimina (H es automática; si algún día hiciera falta, la RPC es `update_panelist_contact_v2`).
- `ReportedIncidentStatus = 'open' | 'in_progress' | 'resolved' | 'dismissed' | 'auto_resolved'`.
- `buttonStyles.ts` exporta `BTN_PRIMARY` y `BTN_SECONDARY` con los valores actuales de `ReportedIncidentPanel.tsx:13-14`.

- [ ] **Step 1: Editar `types.ts`, crear `buttonStyles.ts`, reescribir el hook** según Interfaces. En `ReportedIncidentPanel.tsx` cambiar el import de los estilos y dejar de desestructurar las acciones eliminadas (el panel se reescribe en la Tarea 2; aquí solo debe compilar).

- [ ] **Step 2: Verificar** — Run: `npm run lint && npm run build`. Expected: ambos sin errores ni warnings.

- [ ] **Step 3: Commit**

```bash
git add src/lib/types.ts src/components/incidents/buttonStyles.ts src/lib/hooks/useReportedIncidents.ts src/components/incidents/ReportedIncidentPanel.tsx
git commit -m "refactor(incidents): detalle de incidencia reportada con contacto, papel y acciones de reenvio"
```

---

### Task 2: Cabecera y fichas de solo lectura

**Files:**
- Create: `src/components/incidents/ReportedIncidentHeader.tsx`
- Modify: `src/components/incidents/ReportedIncidentPanel.tsx`
- Modify: `public/locales/{en,es,fr,ar}.csv`

**Interfaces:**
- Consumes: `ReportedIncidentDetail`, `panelistRole` (Tarea 1).
- Produces: `ReportedIncidentHeader({ inc, role }: { inc: ReportedIncidentDetail; role: 'sender' | 'receiver' | null })`.
- Panel: el bloque por categoría queda así —
  - `missing_materials` → `<MissingMaterialsSections …/>` (Tarea 4; hasta entonces, el componente actual `MissingMaterialsActions`).
  - `parcel_returned` → `<ReturnedSampleActions …/>` (Tarea 3; hasta entonces, el texto `reported_incidents.action.support_only`).
  - `contact_data_change` → `<ReadonlyPayload payload={inc.payload} kind="contact" />`: tabla antes/después con `payload.before` / `payload.after` (claves `mobile,email,language,address_line1,address_line2,address_city,address_country`; ausentes → no se pintan; `payload` NULL → texto `reported_incidents.readonly.no_data`). **Se elimina `ContactAction` y `actUpdateContact` ya no se usa en el panel** (H es automática).
  - `unreadable_label_receipt` → `<ReadonlyPayload kind="receipt" />`: muestra `payload.chosen_detail_id` (8 chars) o `reported_incidents.readonly.no_candidates` si `payload.no_candidates`.
  - `parcel_damaged`, `how_to_send`, `unavailability_request`, `tag_photo_problem`, `other` → texto `reported_incidents.action.support_only`.
  - El bloque "Resolver / Respuesta" se muestra solo si `inc.status !== 'auto_resolved'`.
- Cabecera: nombre · código; línea de contacto `📞 mobile · ✉ email · Telegram sí/no · idioma · ciudad`; si hay `detail`: etiqueta `reported_incidents.role.sender` / `.receiver` (badge azul/verde) + `origin_node.auto_id → destination_node.auto_id` · transportista · producto · `fecha_programada` (dd/MM/yyyy con `date-fns`) · `tag_id`.

- [ ] **Step 1: Crear `ReportedIncidentHeader.tsx` y reescribir `ReportedIncidentPanel.tsx`** según Interfaces. Quitar `ContactAction`, `UnavailabilityAction`, los botones de B/C/G y `ReturnedOrMaterialsActions`.

- [ ] **Step 2: Añadir claves i18n** a los 4 CSV (EN/ES/FR/AR):
  `reported_incidents.role.sender` (Sender / Emisor / Expéditeur / المُرسِل), `reported_incidents.role.receiver` (Receiver / Receptor / Destinataire / المُستلِم), `reported_incidents.header.contact`, `reported_incidents.header.telegram_yes`, `reported_incidents.header.telegram_no`, `reported_incidents.status.auto_resolved` (Auto-resolved / Resuelta automáticamente / Résolue automatiquement / تم الحل تلقائيًا), `reported_incidents.readonly.title` (Handled automatically / Tratada automáticamente / …), `reported_incidents.readonly.no_data`, `reported_incidents.readonly.no_candidates` (No shipments in transit were found / No había envíos en camino / …), `reported_incidents.readonly.chosen_shipment`, `reported_incidents.contact.before`, `reported_incidents.contact.after`, `reported_incidents.contact.field.mobile/email/language/address_line1/address_line2/address_city/address_country`.

- [ ] **Step 3: Verificar** — `npm run lint && npm run build`. Manual (DEMO2): abrir la incidencia `contact_data_change` existente → cabecera con teléfono/email y tabla antes/después (o "sin datos" si el payload antiguo no tiene `before/after`); abrir una `other` → solo el bloque Resolver.

- [ ] **Step 4: Commit**

```bash
git add src/components/incidents/ReportedIncidentHeader.tsx src/components/incidents/ReportedIncidentPanel.tsx public/locales/*.csv
git commit -m "feat(incidents): cabecera con contacto y papel; fichas de solo lectura para categorias automaticas"
```

---

### Task 3: Ficha D — reenviar muestra devuelta

**Files:**
- Create: `src/components/incidents/ReturnedSampleActions.tsx`
- Modify: `src/components/incidents/ReportedIncidentPanel.tsx` (enchufar el componente)
- Modify: `public/locales/{en,es,fr,ar}.csv`

**Interfaces:**
- Consumes: `listNodesForMove`, `suggestSampleMove`, `rerouteReturnedSample`, `actCancel` (Tarea 1).
- Produces: `ReturnedSampleActions({ detail, busy, onCancel, onReroute, t })` con `detail: ReportedIncidentDetail['detail']`, `onCancel(): Promise<void>`, `onReroute(toNodeId: string, weekStart: string): Promise<void>`.
- Comportamiento: si `!detail` → `reported_incidents.returned.no_detail`. Si no: `<select>` de nodos (al montar `listNodesForMove(detail.id)`; la RPC devuelve solo nodos de la misma ciudad que el destino actual, porque el motor no admite cambiar de ciudad; opción `${auto_id} — ${city_name} (${panelist_name})`; si la lista viene vacía, texto `reported_incidents.returned.no_nodes`); `<select>` de semanas: 8 lunes a partir del lunes de la semana actual (`startOfWeek(new Date(), { weekStartsOn: 1 })` + 7·k, k=0..7, etiqueta `dd/MM`); al cambiar nodo o semana → `suggestSampleMove(detail.id, detail.destination_node_id, toNode, week)` y pintar `found ? reported_incidents.returned.fits (date, load) : reported_incidents.returned.reason.<reason>`; botón **Confirmar reenvío** (`BTN_PRIMARY`, deshabilitado si `!found`) → `onReroute`; botón **Anular envío** (`BTN_SECONDARY`) → `onCancel`. El panel envuelve ambos con `run(…, 'reported_incidents.done.rerouted' | 'reported_incidents.done.cancelled')` (deja `in_progress`).

- [ ] **Step 1: Crear el componente y enchufarlo** en el panel para `parcel_returned`.

- [ ] **Step 2: Claves i18n (4 CSV):** `reported_incidents.returned.title`, `.to_node`, `.no_nodes` (No other node in this city / No hay otro nodo en esta ciudad / …), `.week`, `.confirm_reroute` (Confirm re-send / Confirmar reenvío / Confirmer le renvoi / تأكيد إعادة الإرسال), `.cancel_shipment` (reutilizar `reported_incidents.action.cancel_shipment` existente), `.no_detail`, `.fits` ("Fits: {date} (load {load})"), `.reason.not_found`, `.reason.not_in_cell`, `.reason.sample_not_movable`, `.reason.has_incident_line`, `.reason.other_city`, `.reason.inactive_node`, `.reason.other_end` y los demás `reason` que devuelva `incident_suggest_sample_move` (`20261020150000_incident_move_to_cell.sql:240-330`; cubrir todos), `reported_incidents.done.rerouted`.

- [ ] **Step 3: Verificar** — `npm run lint && npm run build`. Manual (DEMO2): crear a mano una incidencia `parcel_returned` enlazada a una muestra `sent` de TEST-INCIDENCIAS (`insert_panelist_incident_auto(..., 'parcel_returned', ..., p_detail_id, 'open')` por `execute_sql` **con confirmación**); elegir otro nodo y semana → ver "Cabe"; confirmar → la muestra pasa a `pending` con el nuevo destino; la incidencia queda `in_progress`.

- [ ] **Step 4: Commit**

```bash
git add src/components/incidents/ReturnedSampleActions.tsx src/components/incidents/ReportedIncidentPanel.tsx public/locales/*.csv
git commit -m "feat(incidents): devuelto -> reenviar la muestra a otro nodo y semana o anular"
```

---

### Task 4: Ficha A en tres secciones

**Files:**
- Create: `src/components/incidents/MissingMaterialsSections.tsx`
- Modify: `src/lib/hooks/useMaterialsTreatment.ts`
- Modify: `src/components/incidents/ReportedIncidentPanel.tsx` (quitar `MissingMaterialsActions`)
- Modify: `public/locales/{en,es,fr,ar}.csv`

**Interfaces:**
- Consumes del hook (existentes): `reconcileStock`, `recomputeNeed(panelistId, start, end): Promise<NeedLine[]>`, `resolveSupply(needLines, panelistId): Promise<SupplyPlan>`, `executeSupply(plan, panelistId)`, `createDisplacementBaja(incidentId, expectedDate): Promise<string>`, `linkShipmentToIncident`, `markShipmentSent`.
- Produces en el hook:
  - `fetchPanelistStock(panelistId): Promise<{ material_id: string; name: string; code: string; quantity: number; is_blocking: boolean }[]>` — `panelist_material_stocks` join `material_catalog(name, code, is_blocking)`, filtrado por `account_id`.
  - `zeroAllStock(panelistId): Promise<number>` — para cada fila con `quantity > 0` llama a `reconcileStock(panelistId, material_id, 0)`; devuelve cuántas puso a cero.
  - `daysWithoutStock(panelistNodeId: string, from: string, to: string, blockingMaterialIds: string[]): Promise<{ businessDays: number; samples: { id: string; fecha_programada: string; destination_auto_id: string; product: string }[] }>` — `businessDays` = nº de fechas `d` con `from <= d <= to` y día de semana 1..5 (`date-fns` `eachDayOfInterval` + `isWeekend`); `samples` = `allocation_plan_details` con `origin_node_id = panelistNodeId`, `status in ('pending','notified')`, `fecha_programada between from and to`, cuyo `plan.product_id` aparece en `product_materials` con `material_id in blockingMaterialIds` (dos consultas: ids de producto afectados, luego muestras). Si `to < from` → `{ businessDays: 0, samples: [] }`.
- Componente `MissingMaterialsSections({ incidentId, panelist, payload, t })` con `panelist: ReportedIncidentDetail['panelist']`:
  - **Sección 1** (`reported_incidents.materials.s1_title`): tabla de `fetchPanelistStock`; badge bloqueante; botón **Poner stock a cero** (`BTN_SECONDARY`, deshabilitado si todas las cantidades son 0 o no hay filas; `confirm(t('reported_incidents.materials.zero_confirm'))` antes); conserva el input "cantidad real" por fila del componente actual.
  - **Sección 2** (`s2_title`): al montar, `recomputeNeed(panelist.id, hoy, hoy+90)` y `resolveSupply`; tabla por material: necesidad, `<select>` origen con opciones `central` / `donor:<id>` / `purchase` preseleccionado según `SupplyPlan`; campo **Fecha prevista** (`type=date`, `min=hoy`, valor inicial `hoy + shipment_lead_time_days` o `purchase_lead_time_days` si algún origen es `purchase`, leído de `stock_settings` como hace `handleCreateBaja` hoy; deshabilitado si `payload.supply_executed_at`); debajo, `daysWithoutStock(panelist.node_id, hoy, fechaPrevista, ids bloqueantes con necesidad > 0)` → "{n} días laborables sin stock" + lista de muestras afectadas; botón **Confirmar suministro** (`BTN_PRIMARY`; deshabilitado si `payload.supply_executed_at`) → recompone `SupplyPlan` con los orígenes elegidos, `executeSupply`, `linkShipmentToIncident` del envío central si lo hay, y `update panelist_incident set payload = payload || {expected_date, days_without_stock, central_shipment_id, donor_shipment_ids, supply_executed_at}` (vía `supabase.from('panelist_incident').update`). Si ya ejecutado: muestra los ids de envío guardados.
  - **Sección 3** (`s3_title`): botón **Crear baja por materiales y replanificar** (`BTN_PRIMARY`; deshabilitado si `linked_unavailability_id` ya existe o no se ha confirmado el suministro) → `createDisplacementBaja(incidentId, expectedDate)`, después `markShipmentSent` de los envíos guardados (mismo orden que hoy: baja antes de enviar); luego `<Link to={`/incidents/panelist-availability?unavailability=${id}`}>` **Ir a la incidencia de baja**. Texto `close_hint` existente.
- Tras cualquier acción el panel hace `resolve(incidentId, 'in_progress')` + recarga (patrón `run`).

- [ ] **Step 1: Ampliar el hook** con las tres funciones.

- [ ] **Step 2: Crear `MissingMaterialsSections.tsx`** y sustituir `MissingMaterialsActions` en el panel (borrar el componente antiguo del fichero).

- [ ] **Step 3: Claves i18n (4 CSV):** `reported_incidents.materials.s1_title` (Theoretical stock / Stock teórico / Stock théorique / المخزون النظري), `.s2_title` (Needs and supply / Necesidad y suministro / …), `.s3_title` (Re-plan / Replanificar / Replanifier / إعادة التخطيط), `.zero_stock` (Set stock to zero / Poner stock a cero / Mettre le stock à zéro / تصفير المخزون), `.zero_confirm`, `.zero_done` ("{n} materials set to zero"), `.source` , `.source_central`, `.source_donor` ("Surplus from {name}"), `.source_purchase`, `.expected_date` (Expected arrival / Fecha prevista de llegada / Date d'arrivée prévue / تاريخ الوصول المتوقع), `.days_without_stock` ("{n} business days without stock"), `.affected_samples`, `.no_affected_samples`, `.confirm_supply`, `.supply_done` ("Supply confirmed on {date}"), `.create_baja_replan`, `.go_to_unavailability` (Open the unavailability incident / Ir a la incidencia de baja / Ouvrir l'incident d'indisponibilité / فتح حادثة عدم التوفر), `.no_stock_rows`. Quitar las claves `step1_title…step5_title` que dejen de usarse (comprobar con `grep -rn "materials.step" src`).

- [ ] **Step 4: Verificar** — `npm run lint && npm run build`. Manual (DEMO2, incidencia `missing_materials` existente): sección 1 lista stock; poner a cero pide confirmación; sección 2 muestra necesidad con origen propuesto y fecha prevista editable; cambiar la fecha recalcula días sin stock; **no** confirmar el suministro en DEMO2 salvo que el usuario lo autorice (crea envíos reales).

- [ ] **Step 5: Commit**

```bash
git add src/components/incidents/MissingMaterialsSections.tsx src/lib/hooks/useMaterialsTreatment.ts src/components/incidents/ReportedIncidentPanel.tsx public/locales/*.csv
git commit -m "feat(incidents): falta de material en tres secciones (stock, necesidad y suministro, replanificar)"
```

---

### Task 5: Bandeja con `auto_resolved` y enlace a la pantalla de bajas

**Files:**
- Modify: `src/pages/incidents/PanelistReportedIncidents.tsx:16-21,39-42`
- Modify: `src/pages/incidents/PanelistAvailabilityIncidents.tsx:1-30`
- Modify: `public/locales/{en,es,fr,ar}.csv`

**Interfaces:**
- Bandeja: `statusFilter: ReportedIncidentStatus | 'open_active'` ya existe; añadir `<option value="auto_resolved">` con `t('reported_incidents.status.auto_resolved')` (clave de la Tarea 2). El filtro por defecto sigue siendo `open_active`.
- Pantalla de bajas: `const [params, setParams] = useSearchParams()`; `useEffect` que, cuando `!loading` y `params.get('unavailability')` está en `inbox.map(r => r.unavailability_id)`, hace `setSelected(id)` y borra el parámetro (`setParams({}, { replace: true })`). Si el id no está en la bandeja, no hace nada.

- [ ] **Step 1: Editar las dos páginas** según Interfaces.

- [ ] **Step 2: Verificar** — `npm run lint && npm run build`. Manual: `/incidents/panelist-availability?unavailability=<id de una baja de DEMO2>` abre el detalle; con un id inventado abre la lista. En la bandeja de reportadas, el selector muestra "Resuelta automáticamente".

- [ ] **Step 3: Commit**

```bash
git add src/pages/incidents/PanelistReportedIncidents.tsx src/pages/incidents/PanelistAvailabilityIncidents.tsx
git commit -m "feat(incidents): filtro auto_resolved en la bandeja y apertura de una baja por URL"
```

---

### Task 6: Comprobación de traducciones y cierre

- [ ] **Step 1: Comprobar que ninguna clave `reported_incidents.*` usada en `src/` falta en los 4 CSV** (script Node ad hoc en el scratchpad: extraer `t('reported_incidents.[a-z_.]+')` de `src/**/*.tsx` y comparar con la primera columna de cada CSV; también la lista de claves `reported_incidents.returned.reason.*` construidas dinámicamente). Expected: `missing=0` en los 4 idiomas.

- [ ] **Step 2: `npm run lint && npm run build`** — Expected: limpio.

- [ ] **Step 3: `graphify update .`** para refrescar el grafo del proyecto.

- [ ] **Step 4: Commit si hubo cambios** — `git commit -m "chore(i18n): claves de incidencias reportadas v2 completas en EN/ES/FR/AR"`.
