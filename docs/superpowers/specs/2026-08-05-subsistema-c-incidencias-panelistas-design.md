# Subsistema C — Marco "Incidencias" + Disponibilidad de panelistas (pantalla del manager)

**Fecha:** 2026-08-05
**Estado:** diseño aprobado, pendiente de plan de implementación.
**Depende de:** subsistema B (motor de propuestas), ya vivo en `onems-dev`.

---

## 1. Objetivo

Dar al manager una pantalla para **revisar y resolver** las propuestas de reasignación
que el motor B genera al crear una baja de panelista. Hoy esas propuestas viven solo en la
tabla `panelist_reassignment_proposal` y **nada las hace visibles ni accionables**; el plan
de asignación no se muta hasta que un manager confirma. Este subsistema cierra ese hueco.

Además, se sienta el **marco "Incidencias"**: un apartado de primer nivel en el menú,
pensado para alojar en el futuro otras categorías (materiales, entregas, allocation plan…).
En este spec **solo la categoría "Disponibilidad de panelistas" es funcional**; el marco
queda preparado para hermanos sin construir placeholders vacíos.

### Fuera de alcance (trabajo futuro, no aquí)

- Motores/pantallas de incidencias de **materiales, entregas o allocation plan**. Cada uno
  necesitará su propia tabla de propuestas y lógica (como B). Aquí solo se deja el marco.
- Subsistema **A** (Telegram/n8n): ingesta de la baja, lo hace el usuario desde su entorno.
- "Regenerar" muestra de reemplazo automáticamente: se cubre a mano con `final_action='manual'`.

---

## 2. Contrato del backend ya existente (subsistema B)

No se re-describe; se consume tal cual está desplegado:

- Tabla **`panelist_reassignment_proposal`**: `id, account_id, unavailability_id,
  allocation_plan_detail_id, affected_role ('origin'|'destination'),
  sample_status_at_detection, suggested_action ('reroute'|'shift_date'|'cancel'|'none'),
  suggested_target_node_id, suggested_date, suggested_reason,
  final_action, final_target_node_id, final_date,
  status ('pending'|'confirmed'|'dismissed'), confirmed_by, confirmed_at, timestamps`.
- Columna **`panelist_unavailability.review_status`** ('pending_review'|'reviewed') — señal de
  alarma y objetivo del "dar por estudiado".
- RPC **`apply_reassignment_proposal(p_proposal_id, p_final_action, p_final_target_node_id,
  p_final_date)`** — muta `allocation_plan_details` (reroute / shift_date / cancel / manual /
  none) y cierra la propuesta como `confirmed` (o `dismissed` si `none`). Guard multi-tenant.
- RPC `apply_reassignment_proposals_bulk(unavailability_id)` — existe, pero **la UI NO la usa**
  (actúa sobre todas las pendientes de la baja, no sobre una selección). Ver §5.3.

Toda la lógica de mutación del plan vive en la RPC; el frontend nunca escribe
`allocation_plan_details` directamente.

---

## 3. Backend nuevo — una única migración

### 3.1 `list_reroute_candidates(p_detail_id uuid)` — RPC de solo lectura

Devuelve los nodos válidos para reencaminar una muestra concreta: **misma ciudad que el nodo
actual del rol afectado, distintos de él, con panelista disponible en la fecha de la muestra**.
Reutiliza `is_node_available` (misma lógica que usa el motor al sugerir), para que el override
manual del manager ofrezca exactamente el mismo universo de candidatos que la sugerencia
automática.

**Firma con rol explícito** (la más simple y sin ambigüedad):

```sql
CREATE OR REPLACE FUNCTION public.list_reroute_candidates(
  p_detail_id uuid,
  p_role text)   -- 'origin' | 'destination'
RETURNS TABLE(node_id uuid, node_name text, city_id uuid, is_available boolean)
```

- Según `p_role`, toma el nodo actual (`origin_node_id` o `destination_node_id`) del
  `allocation_plan_details` indicado, obtiene su `city_id`, y devuelve los **demás** nodos de
  esa ciudad.
- Incluye **`is_available`** por nodo (evaluado con `is_node_available` en la
  `fecha_programada` de la muestra); **no** filtra los no disponibles, para que la UI pueda
  mostrarlos deshabilitados o con aviso en vez de ocultarlos.
- Excluye el propio nodo actual del rol.
- Valida `p_role IN ('origin','destination')`; si no, `RAISE EXCEPTION`.
- `GRANT EXECUTE ... TO authenticated`. Solo lectura: no muta nada.
- Guard multi-tenant coherente con el resto (deriva account del detail y compara con el actor
  salvo superadmin / service-role).

> El frontend ya conoce el rol de cada propuesta (`affected_role`), así que lo pasa
> directamente. No hace falta que la RPC lea la tabla de propuestas.

Migración forward-only: `supabase/migrations/20260805HHMMSS_list_reroute_candidates.sql`.
Se despliega por el SQL Editor web (el usuario opera Supabase por web), con su entrada en el
runbook de `docs/database/`.

**No hay más cambios de esquema.** "Dar por estudiado" es un `UPDATE` normal de
`panelist_unavailability.review_status`, ya cubierto por la RLS existente.

---

## 4. Estructura de navegación — marco "Incidencias"

El `Sidebar.tsx` organiza el menú en **grupos** (labels en mayúscula: `E2E`, `DIAGNOSIS`,
`Administración`). El filtro de módulo superior (E2E / Diagnosis) oculta **solo** los grupos
cuyo label es exactamente `'E2E'` o `'DIAGNOSIS'`.

**Se añade un grupo nuevo de primer nivel `INCIDENCIAS`**, con un ítem por categoría:

```
INCIDENCIAS
  🔔 Disponibilidad de panelistas   → /incidents/panelist-availability   (FUNCIONAL)
```

- Al no llamarse `E2E` ni `DIAGNOSIS`, el grupo es **visible en cualquier filtro de módulo**
  (igual que Administración).
- **Badge** en el ítem "Disponibilidad de panelistas": nº de bajas con
  `review_status='pending_review'` que tengan al menos una propuesta. (Cuando existan más
  categorías, cada una llevará su propio badge.)
- Roles: `['admin','superadmin']`, como el resto de ítems operativos.
- **No se crean** ítems vacíos de Materiales/Entregas/Allocation. Se añadirán como hermanos
  cuando se construya cada motor.

---

## 5. La pantalla — página `IncidentPanelistAvailability`

Ruta `/incidents/panelist-availability`. Sigue el patrón de la app: **página → hook →
supabase**, tablas con filtros, todo el texto por `useTranslation()`.

### 5.1 Nivel 1 · Bandeja (lista de bajas con incidencia)

Tabla de bajas `review_status='pending_review'` que tengan propuestas. Una fila por baja:

| Columna | Contenido |
|---|---|
| Panelista | nombre + `panelist_code` |
| Ciudad / nodo | nodo del panelista |
| Fechas baja | `start_date` – `end_date` |
| Muestras afectadas | nº total de propuestas |
| Desglose | nº envíos (origin) / recepciones (destination) |
| Pendientes | nº de propuestas `pending` (las no resueltas) |
| Acción | "Revisar" → abre nivel 2 |

- Filtros al estilo de la app (panelista, rango de fechas, búsqueda). Reutilizar el patrón de
  `PanelistUnavailability.tsx` (mismo look de filtros colapsables).
- Solo se listan bajas de la cuenta activa (`effectiveAccountId`) — la RLS ya lo garantiza,
  pero el hook filtra explícitamente para superadmin con cuenta seleccionada.
- Estado vacío: mensaje "No hay incidencias pendientes".

### 5.2 Nivel 2 · Detalle de una baja

**Cabecera:** datos de la baja (panelista, fechas, motivo, nº muestras) + acción global
**"Dar por estudiado"** (ver §5.4).

**Tabla de propuestas** — una fila por muestra afectada, **con checkbox de selección** (mismo
patrón que la tabla de Unavailability actual: `selectedIds: Set<string>`, seleccionar todo,
barra de acciones en bloque):

| Columna | Contenido |
|---|---|
| ☑ | checkbox de selección |
| Muestra | id corto del `allocation_plan_detail` + `fecha_programada` |
| Rol | Envío (origin) / Recepción (destination) |
| Estado muestra | `sample_status_at_detection` |
| Acción sugerida | reroute / shift_date / cancel / none (badge) |
| Sugerencia | nodo destino (nombre) o fecha sugerida, según la acción |
| Motivo | `suggested_reason` |
| Estado propuesta | pending / confirmed / dismissed (badge) |
| Acciones | ver §5.3 |

Las filas ya resueltas (`confirmed`/`dismissed`) se muestran deshabilitadas/atenuadas con su
resultado, sin acciones (auditoría visible).

### 5.3 Acciones de resolución

**Individual (por fila, solo si `pending`):**

- **Confirmar** → acepta la sugerencia:
  `apply_reassignment_proposal(id, suggested_action, suggested_target_node_id, suggested_date)`.
- **Cambiar…** → override manual. Abre un mini-form:
  - elegir **acción final**: reencaminar (elegir nodo de `list_reroute_candidates`), cambiar
    fecha (date picker), o cancelar la muestra;
  - se envía como `apply_reassignment_proposal(id, 'manual', nodo?, fecha?)` para reroute/shift,
    o `apply_reassignment_proposal(id, 'cancel', …)` para cancelar. (La RPC ya distingue: con
    `'manual'` edita nodo/fecha del mismo registro; con `'cancel'` marca la muestra cancelada.)
  - Esto cubre el **load balancing manual** (paso 8 del proceso) y el "cambiar nodo/fecha del
    mismo registro" acordado.
- **Descartar** → `apply_reassignment_proposal(id, 'none', …)` → queda `dismissed`, sin tocar
  el plan (para propuestas informativas o que el manager decide no aplicar).

**En bloque sobre la selección (barra que aparece al marcar ≥1 checkbox):**

- **Confirmar seleccionadas** → recorre la selección y ejecuta, por cada id,
  `apply_reassignment_proposal(id, suggested_action, suggested_target_node_id, suggested_date)`
  (cada una aplica **su propia** sugerencia). Mismo patrón de bucle que el "bulk cancel" actual
  de `PanelistUnavailability.tsx` (que hace un `for (id of selectedIds)`).
- **Descartar seleccionadas** → bucle con `apply_reassignment_proposal(id, 'none', …)`.
- **No** se ofrece "cambiar" en bloque (el override manual es intrínsecamente por-muestra:
  nodos/fechas distintos).
- **No** se usa la RPC `_bulk` de la BD: actúa sobre *todas* las pendientes de la baja, no
  sobre la selección concreta del manager.

Tras cada acción (individual o en bloque) se refresca la lista y se recalcula el nº de
pendientes.

### 5.4 "Dar por estudiado"

- Botón en la cabecera del detalle. **Habilitado solo cuando no queda ninguna propuesta
  `pending`** en esa baja (todas confirmadas o descartadas individualmente). Coherente con
  "se han de resolver unitariamente, no como grupo": la incidencia se cierra cuando cada
  muestra tiene su decisión.
- Acción: `update panelist_unavailability set review_status='reviewed' where id = <baja>`
  (a través del hook; RLS existente lo permite). Apaga la alarma y saca la baja de la bandeja.
- Mientras haya pendientes, el botón está deshabilitado con tooltip explicativo.

---

## 6. Hook `useReassignmentProposals`

`src/lib/hooks/useReassignmentProposals.ts`. Patrón idéntico a los hooks existentes.

Expone:

- `inbox` — bajas `pending_review` con propuestas y sus contadores (para nivel 1).
- `fetchProposals(unavailabilityId)` — propuestas de una baja, con joins a nombres de nodo,
  ciudad y datos de la muestra (`allocation_plan_details`), para nivel 2.
- `confirmProposal(id)` — aplica la sugerencia (envuelve la RPC con `suggested_*`).
- `overrideProposal(id, { action, nodeId?, date? })` — override manual (RPC con `'manual'` o
  `'cancel'`).
- `dismissProposal(id)` — RPC con `'none'`.
- `confirmMany(ids)` / `dismissMany(ids)` — bucles sobre la selección.
- `listRerouteCandidates(detailId, role)` — llama a la RPC de §3.1 (`role` = `affected_role`).
- `markReviewed(unavailabilityId)` — update de `review_status`.
- `pendingCount` — para el badge del menú.

Errores: `try/catch` con `setError` y `console.error`, como el resto de hooks. Las acciones
que mutan refrescan los datos al terminar.

---

## 7. i18n

Todo el texto visible pasa por `useTranslation()`. Se añaden claves nuevas bajo un namespace
`incidents.*` (título de página, columnas, acciones, estados, mini-form de override, tooltips,
badge) a los **cuatro** ficheros: `src/locales/{en,es,fr,ar}/…`. El árabe implica RTL (el
layout ya lo soporta). Un `.tsx` con texto fijo que no pase por el hook es un bug de traducción.

---

## 8. Seguridad / multi-tenant

- Toda lectura y escritura pasa por RLS por `account_id` ya existente en las tablas.
- Las mutaciones van por las RPC `SECURITY DEFINER` con guard cross-tenant ya probado (B).
- La nueva RPC `list_reroute_candidates` es solo lectura y lleva el mismo guard.
- El frontend nunca escribe `allocation_plan_details` directamente; siempre vía RPC.

---

## 9. Puerta de calidad

- `npm run lint` (0 warnings) y `npm run build` deben pasar.
- La migración `list_reroute_candidates` se valida en el Postgres portable local
  (`supabase/tests/`) antes de proponer despliegue, con un `.test.sql` que verifica:
  candidatos correctos por ciudad, exclusión del nodo propio, flag `is_available`, y rechazo
  cross-tenant.
- No hay suite de tests de frontend; lint + build + revisión son la puerta.

---

## 10. Resumen de entregables

| # | Entregable | Tipo |
|---|---|---|
| 1 | Migración `list_reroute_candidates` + `.test.sql` | BD (forward-only) |
| 2 | Grupo `INCIDENCIAS` + ítem con badge en `Sidebar.tsx` | Frontend |
| 3 | Ruta + página `IncidentPanelistAvailability` (nivel 1 bandeja) | Frontend |
| 4 | Detalle nivel 2 (tabla propuestas, checkboxes, acciones, override) | Frontend |
| 5 | Hook `useReassignmentProposals` | Frontend |
| 6 | "Dar por estudiado" (gating por pendientes) | Frontend |
| 7 | Claves i18n en EN/ES/FR/AR | Frontend |
| 8 | Entrada de despliegue en runbook `docs/database/` | Docs |
