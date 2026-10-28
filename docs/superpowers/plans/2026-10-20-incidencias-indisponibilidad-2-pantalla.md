# Incidencias de indisponibilidad — Plan 2/3: pantalla del manager

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que `/incidents/panelist-availability` muestre todas las bajas como incidencias con estado y permita al manager resolver las líneas pendientes aceptando la propuesta del sistema, eligiendo otra semana o anulando, con la carga de la ciudad delante y un campo de resolución final.

**Architecture:** React + hook de datos (`useUnavailabilityIncidents`) que lee `panelist_unavailability` + `panelist_reassignment_proposal` y llama a las RPC del Plan 1 (`suggest_for_week`, `apply_manager_decision`, `set_incident_resolution`). El panel de detalle actual (`ProposalReviewPanel`, 584 líneas) se parte en componentes pequeños. Sin tests automatizados de frontend: la puerta es `npm run lint` + `npm run build` + comprobación manual en la URL de dev.

**Tech Stack:** React 18, TypeScript, Vite, Tailwind, supabase-js, i18n por CSV en `public/locales/{en,es,fr,ar}.csv`.

**Spec:** `docs/superpowers/specs/2026-10-20-incidencias-indisponibilidad-resolucion-automatica-design.md` (§6, 5.3, 5.4, 5.7)

## Global Constraints

- Requiere el Plan 1 aplicado en onems-dev (las RPC deben existir). Hasta entonces la pantalla vieja sigue funcionando gracias a `apply_reassignment_proposal`.
- Todo texto visible por `useTranslation()`; cada clave nueva en los **4** CSV (`key,translation`; variables `{var}`). FR/AR autogenerados, marcados para repaso.
- Superadmin: cuenta seleccionada vía `useAccount().effectiveAccountId` (null = todas); usuarios normales por RLS.
- `npm run lint` con el tope actual (`--max-warnings 48`) y `npm run build` deben pasar al cerrar cada tarea.
- No commitear/pushear salvo que el usuario lo pida; rama `develop`.
- Commits: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. Incidencia sin líneas (baja sin muestras): la fila debe verse con estado "Resuelta automáticamente" y el detalle no debe romperse con tablas vacías. → comprobación manual Tarea 3.
2. Pulsar "Otra semana…" sobre una semana sin hueco: el diálogo debe mostrar "no hay hueco" y no dejar confirmar. → Tarea 4.
3. Cambiar los filtros del panel de carga (referencia/desviación) debe recalcular lo que muestra el diálogo de semana (se pasan como parámetros a `suggest_for_week`). → Tarea 4.
4. Dos acciones seguidas sobre la misma línea (doble clic): la segunda falla con "already manager_resolved"; la UI debe deshabilitar el botón mientras carga y recargar tras el error. → Tarea 4.
5. Baja activa en la pantalla de panelistas: el formulario de edición ya no permite cambiar fechas. → Tarea 5.

---

### Task 1: Tipos y hook `useUnavailabilityIncidents`

**Files:**
- Modify: `src/lib/types.ts` (bloque `ProposalStatus`…`UnavailabilityHeader`, líneas 365–425)
- Create: `src/lib/hooks/useUnavailabilityIncidents.ts`
- Delete: `src/lib/hooks/useReassignmentProposals.ts` (en Tarea 3, cuando nadie lo importe)

**Interfaces (Produces):**
```ts
export type IncidentStatus = 'new' | 'auto_resolved' | 'pending_manager' | 'resolved'
export type ProposalStatus = 'pending' | 'auto_resolved' | 'manager_resolved' | 'info' | 'dismissed'
export type ProposalAction = 'reroute' | 'shift_date' | 'cancel' | 'none'
export interface ReassignmentProposal { /* como hoy + */ resolution_note: string | null; applied_at: string | null;
  detail?: { id; fecha_programada; original_fecha_programada: string | null; status; origin_node_id; destination_node_id;
             origin_node?: { auto_id }; destination_node?: { auto_id } } | null
  suggested_target_node?: { id; auto_id } | null; final_target_node?: { id; auto_id } | null }
export interface IncidentInboxRow { unavailability_id; panelist_name; panelist_code; node_label; city_name; start_date; end_date;
  reason: string | null; incident_status: IncidentStatus; auto_summary: string | null; created_at: string;
  affected_count; origin_count; destination_count; pending_count }
export interface UnavailabilityHeader { /* como hoy + */ incident_status: IncidentStatus; auto_summary: string | null;
  final_resolution: string | null; resolved_at: string | null }
export interface WeekSuggestion { found: boolean; date?: string; node_id?: string; node_code?: string; load_after?: number;
  saturation_level?: 'normal' | 'high' | 'saturated' }
export type IncidentStatusFilter = 'open' | 'all' | IncidentStatus   // open = new + pending_manager

export function useUnavailabilityIncidents(): {
  inbox: IncidentInboxRow[]; loading: boolean; error: string | null; pendingManagerCount: number;
  statusFilter: IncidentStatusFilter; setStatusFilter(f: IncidentStatusFilter): void;
  fetchInbox(): Promise<void>;
  fetchHeader(unavailabilityId: string): Promise<UnavailabilityHeader | null>;
  fetchLines(unavailabilityId: string): Promise<ReassignmentProposal[]>;
  suggestForWeek(proposalId: string, weekStart: string, referenceLoad: number, deviationPercent: number): Promise<WeekSuggestion>;
  decide(proposalId: string, decision: 'accept' | 'week' | 'cancel', weekStart?: string, referenceLoad?: number, deviationPercent?: number): Promise<IncidentStatus>;
  decideMany(proposalIds: string[], decision: 'accept' | 'cancel'): Promise<void>;   // bucle secuencial
  saveResolution(unavailabilityId: string, text: string): Promise<void>;
}
```
- `fetchInbox`: consulta `panelist_unavailability` (select `id,start_date,end_date,reason,incident_status,auto_summary,created_at, panelist:panelists(name,panelist_code,node:nodes(auto_id,city:cities(name))), lines:panelist_reassignment_proposal(affected_role,status)`), filtro `account_id` si `effectiveAccountId`, filtro de estado en cliente, orden `created_at desc`; contadores en JS. `pendingManagerCount` = filas con `incident_status==='pending_manager'` **sin** aplicar el filtro de UI (cuenta siempre sobre las abiertas).
- `fetchLines`: como `fetchProposals` hoy, añadiendo `original_fecha_programada`, `origin_node:nodes!allocation_plan_details_origin_node_id_fkey(auto_id)`, `destination_node:nodes!allocation_plan_details_destination_node_id_fkey(auto_id)` (comprobar nombres reales de las FK con `select conname from pg_constraint where conrelid='allocation_plan_details'::regclass and contype='f'` por `q.sh`) y `final_target_node:nodes!prp_final_target_node_fkey(id,auto_id)` (idem), orden `status` (pending primero), `affected_role`, `created_at`.
- Todas las funciones en `useCallback` (lección aprendida: bucle infinito de fetch si no).

- [ ] **Step 1: Escribir tipos y hook** según Interfaces.
- [ ] **Step 2: `npx tsc --noEmit -p .`** → sin errores nuevos (los componentes viejos siguen usando el hook viejo; ambos conviven hasta la Tarea 3).
- [ ] **Step 3: Commit** `feat(incidents): hook useUnavailabilityIncidents y tipos del nuevo flujo`.

---

### Task 2: Claves i18n

**Files:**
- Modify: `public/locales/en.csv`, `es.csv`, `fr.csv`, `ar.csv` (bloque `incidents.*`, tras `incidents.detail.cause`)

**Produces (claves, EN de referencia; ES/FR/AR equivalentes):**
```
incidents.status.new,New
incidents.status.auto_resolved,Resolved automatically
incidents.status.pending_manager,Pending manager decision
incidents.status.resolved,Resolved
incidents.filter.open,Open
incidents.filter.all,All
incidents.inbox.status,Status
incidents.inbox.created,Declared
incidents.summary.shift,{n} moved to a later date
incidents.summary.reroute,{n} moved to another node
incidents.summary.cancel,{n} cancelled
incidents.summary.info,{n} informational
incidents.summary.pending,{n} pending
incidents.summary.none,No samples affected
incidents.detail.final_resolution,Final resolution
incidents.detail.final_resolution_placeholder,Add a note about how this incident was resolved…
incidents.detail.save,Save
incidents.detail.saved,Saved
incidents.detail.pending_lines,Pending your decision
incidents.detail.resolved_lines,Resolved
incidents.detail.original_date,Original date
incidents.detail.new_date,New date
incidents.detail.new_node,New node
incidents.detail.system_proposal,System proposal
incidents.detail.resolved_by_system,System
incidents.detail.resolved_by_manager,Manager
incidents.detail.info_line,No action possible (already sent)
incidents.action.accept,Accept proposal
incidents.action.other_week,Other week…
incidents.action.cancel_sample,Cancel sample
incidents.action.accept_selected,Accept selected
incidents.action.cancel_selected,Cancel selected
incidents.week.title,Choose a week
incidents.week.hint,Click a week header in the load panel or pick a Monday
incidents.week.proposal,Proposal for week {week}: {date} · node {node} · load after {load}
incidents.week.no_slot,No slot available that week
incidents.week.confirm,Move sample
incidents.load.reference,Reference load
incidents.load.deviation,Deviation %
incidents.load.range,Range
incidents.reason.shift_later_week,Move to the first later week with capacity
incidents.reason.alt_node_later_week,Another node of the city in a later week
incidents.reason.no_slot_8_weeks,No slot within 8 weeks; suggest cancelling
incidents.resolution.unavailability_cancelled,Unavailability cancelled by the panelist; changes reverted
incidents.status_badge.pending_manager_tooltip,Incidents waiting for a manager decision
unavailability.dates_locked,Dates come from the panelist and cannot be edited. Cancel and declare a new period if needed.
```
- [ ] **Step 1: Añadir las claves a los 4 CSV** (ES a mano; FR/AR traducidos y marcados en el commit como pendientes de repaso nativo). Eliminar las que dejan de usarse al final de la Tarea 3 (`incidents.detail.mark_reviewed*`, `incidents.action.confirm*`, `incidents.action.dismiss*`, `incidents.status.confirmed`, `incidents.status.dismissed`) solo si `grep -rn` en `src/` no las encuentra.
- [ ] **Step 2: `npm run build`** → OK. **Step 3: Commit** `feat(i18n): claves del flujo de incidencias de indisponibilidad (en/es/fr/ar)`.

---

### Task 3: Bandeja con estado y filtro; badge del menú

**Files:**
- Modify: `src/pages/incidents/PanelistAvailabilityIncidents.tsx`
- Modify: `src/components/layout/Sidebar.tsx:43,68,362,603` (usar `useUnavailabilityIncidents().pendingManagerCount`)
- Create: `src/components/incidents/IncidentStatusBadge.tsx` — `({ status }: { status: IncidentStatus })` → badge con clases: `new` gris, `auto_resolved` verde, `pending_manager` amarillo, `resolved` azul; texto `t('incidents.status.' + status)`.
- Create: `src/components/incidents/IncidentReviewPanel.tsx` — de momento un envoltorio que renderiza el viejo `ProposalReviewPanel` (se sustituye en la Tarea 4).
- Delete: `src/lib/hooks/useReassignmentProposals.ts` cuando `grep -rn useReassignmentProposals src` no devuelva nada (ocurrirá en la Tarea 4; aquí solo Sidebar y la página cambian).

- [ ] **Step 1: Bandeja**: columnas panelista · nodo/ciudad · fechas · declarada (`created_at` dd/MM/yyyy) · afectadas (env/rec) · pendientes · **estado** (`IncidentStatusBadge`) · acción "Revisar" (siempre, también resueltas). Selector de filtro encima de la tabla (`open` por defecto, `all`, y los 4 estados). Vacío: `incidents.inbox.empty`.
- [ ] **Step 2: Sidebar**: badge = `pendingManagerCount`.
- [ ] **Step 3: `npm run lint && npm run build`** → OK.
- [ ] **Step 4: Comprobación manual** (`npm run dev`, superadmin, cuenta KENYA tras aplicar el Plan 1): se ven las bajas de Nancy Weru y Petet con su estado; una baja sin muestras (crearla en DEMO2 desde la web) aparece como "Resolved automatically" y abre sin error.
- [ ] **Step 5: Commit** `feat(incidents): bandeja con estado de incidencia, filtro y badge por pendientes del manager`.

---

### Task 4: Detalle: cabecera + resolución final, panel de carga con filtros, líneas y acciones

**Files:**
- Create: `src/components/incidents/IncidentHeader.tsx` — props `{ header: UnavailabilityHeader; onSaveResolution(text): Promise<void> }`. Muestra panelista/código/nodo/ciudad, fechas, motivo (`UNAVAIL_REASON_KEY` existente), `IncidentStatusBadge`, resumen (`auto_summary` parseado `k=v;…` → `t('incidents.summary.'+k, {n})`, o `incidents.summary.none`), y `textarea` + botón Guardar para `final_resolution` (prefijo `incidents.resolution.unavailability_cancelled` traducido si el texto contiene ese código).
- Create: `src/components/incidents/CityLoadPanel.tsx` — extraer de `ProposalReviewPanel.tsx` el bloque "Balance de la ciudad" (tabla nodos × semanas con subcolumnas Env/Rec, semáforo, marcadores 🚫/⭐). Props `{ cityId; bajaStart; bajaEnd; releasedNodeId; highlightNodeIds: string[]; referenceLoad; deviationPercent; onChangeParams(ref, dev): void; rangeEnd: string; onChangeRangeEnd(d): void; selectedWeekStart: string | null; onSelectWeek(weekStart: string | null): void }`. Añade tres controles encima: carga de referencia (number, default 6), desviación % (default 20), fin de rango (date, default fin de mes de la baja + 14 días). Modificar `useCityNodeLoad` para aceptar `(cityId, bajaStart, rangeEnd, referenceLoad, deviationPercent)` y pasar `p_reference_load`/`p_deviation_percent` al RPC.
- Create: `src/components/incidents/IncidentLinesTable.tsx` — props `{ lines; selectedIds; onToggle; onAccept(line); onOtherWeek(line); onCancel(line); busyId: string | null }`. Dos bloques: **pendientes** (muestra = `detail.origin_node.auto_id → detail.destination_node.auto_id`, rol, fecha original, propuesta: `suggested_date` + `suggested_target_node.auto_id` + motivo traducido; 3 botones) y **resueltas** (`auto_resolved`/`manager_resolved`/`info`/`dismissed`: qué se hizo —`final_action` + `final_date` + `final_target_node.auto_id`—, por quién —sistema/manager—, cuándo `applied_at`). Checkbox solo en pendientes.
- Create: `src/components/incidents/WeekPickerDialog.tsx` — props `{ line; weekStart: string | null; suggestion: WeekSuggestion | null; loading; onPickWeek(monday: string); onConfirm(); onClose() }`. Input date (se normaliza al lunes) + texto `incidents.week.proposal` o `incidents.week.no_slot`; "Mover" deshabilitado si `!suggestion?.found`.
- Rewrite: `src/components/incidents/IncidentReviewPanel.tsx` — orquesta: carga header+lines, `useCityNodeLoad` con los filtros, estado del diálogo de semana (`onSelectWeek` del panel de carga abre/actualiza el diálogo si hay una línea "en edición"), acciones → `decide(...)` → recargar header+lines+carga. `busyId` bloquea botones durante la llamada; errores en un `div` rojo con `t('common.error')` + mensaje.
- Delete: `src/components/incidents/ProposalReviewPanel.tsx`, `src/lib/hooks/useReassignmentProposals.ts`; claves i18n huérfanas (ver Tarea 2).

- [ ] **Step 1: Extraer `CityLoadPanel`** del panel viejo y adaptar `useCityNodeLoad` (firma nueva; `ProposalReviewPanel` viejo se actualiza mínimamente para compilar o se borra ya si `IncidentReviewPanel` lo sustituye en el mismo paso).
- [ ] **Step 2: `IncidentHeader`, `IncidentLinesTable`, `WeekPickerDialog`, `IncidentReviewPanel`** según props.
- [ ] **Step 3: Borrar el panel y el hook viejos**; `grep -rn "useReassignmentProposals\|ProposalReviewPanel\|apply_reassignment_proposal\|list_reroute_candidates" src` → vacío.
- [ ] **Step 4: `npm run lint && npm run build`** → OK.
- [ ] **Step 5: Comprobación manual** en dev contra onems-dev: abrir Nancy Weru (KENYA): se ven resueltas automáticas y pendientes; "Otra semana…" sobre una semana saturada → "no hay hueco"; cambiar referencia a 3 → la propuesta del diálogo cambia; aceptar una propuesta → línea pasa a resueltas y, si era la última, estado "Resolved"; doble clic rápido no deja error visible permanente; guardar resolución final → persiste tras F5.
- [ ] **Step 6: Commit** `feat(incidents): detalle de incidencia con propuesta del sistema, otra semana, anular y resolucion final`.

---

### Task 5: Fechas de baja no editables en la pantalla de panelistas

**Files:**
- Modify: `src/components/PanelistUnavailability.tsx` (formulario de edición)
- Modify: `src/lib/hooks/usePanelistUnavailability.ts:85` (`updateUnavailabilityPeriod` solo acepta `notes` y `reason`; ignora/elimina `start_date`/`end_date` del `updates`)

- [ ] **Step 1:** En el modo edición de un periodo existente, los campos de fecha pasan a solo lectura con el aviso `unavailability.dates_locked`; se conserva cancelar y editar notas/motivo.
- [ ] **Step 2: `npm run lint && npm run build`** → OK; comprobación manual: editar una baja en DEMO2 no permite cambiar fechas, sí notas.
- [ ] **Step 3: Commit** `fix(unavailability): las fechas de una baja no se editan (vienen del panelista)`.

---

### Task 6: Cierre: PR a main

- [ ] **Step 1:** `npm run lint && npm run build` en `develop` limpio; `git log origin/main..develop --oneline` para listar lo que va.
- [ ] **Step 2:** Dar al usuario título y descripción del PR (en español, lenguaje claro, con "qué verá el manager" y "qué no cambia"), terminada en `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. El usuario crea y fusiona en https://github.com/IgnacioFernandezSoriano/ONEMS/compare/main...develop.
- [ ] **Step 3:** Tras el deploy de Netlify, verificar que el bundle de producción contiene `apply_manager_decision` (descargar `index-*.js` y `grep`).

## Self-review

- Spec §6 bandeja → Tarea 3; detalle → Tarea 4; 5.7 → Tarea 5; i18n → Tarea 2; superadmin/RLS → Tarea 1. Nombres de RPC coinciden con el Plan 1 (`suggest_for_week`, `apply_manager_decision`, `set_incident_resolution`, `rpc_get_node_load_by_period`).
- Review Focus 1–5 asignados a Tareas 3, 4, 4, 4, 5.
