# Historial del panelista — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Panel lateral «📋 Historial» con todo lo que ha pasado con un panelista y las notas del gestor, abierto desde
las pantallas donde se trata con él.

**Architecture:** Una función en la BD (`panelist_history`) junta las fuentes y devuelve JSON ordenado; tabla
`panelist_note` con dos funciones de escritura. En la web, un hook + un panel lateral + un botón reutilizable, y
enlaces directos nuevos en dos pantallas.

**Tech Stack:** Postgres 17 / Supabase (onems-dev `sehbnpgzqljrsqimwyuz`), React 18 + TS + Vite + Tailwind, vitest.

**Spec:** `docs/superpowers/specs/2026-11-24-historial-panelista-design.md`

**Worktree:** `c:/Users/fernandezi/projects/ONEMS_wt_historial`, rama `feat/historial-panelista` (desde `origin/develop`).

## Global Constraints
- Ver = `has_access(cuenta del panelista, 'panelists', 'view')`; escribir notas = `has_access(..., 'panelists', 'edit')`.
- EXECUTE solo para `authenticated` (nada de `service_role`, `anon`, `PUBLIC`).
- Nunca coordenadas en la respuesta. Nunca datos de otra cuenta.
- Nota: 1–2000 caracteres; borrar solo el autor (o superadmin).
- Página de 50 eventos; recepciones `ok` y `ok_same_city` fuera.
- Todo texto visible por `useTranslation()`; claves en `public/locales/{es,en,fr,ar,pt}.csv` (los 5 ficheros que existen).
- Sin parámetro nuevo en la URL, Incidencias reportadas y Errores de recepción se comportan exactamente como hoy.
- Escritura en onems-dev solo con confirmación de Ignacio. Commit/push solo cuando Ignacio lo pida.
- Calidad: `npm run lint` (0 warnings) y `npm run build` deben pasar.

## Review Focus
- Panelista sin nodo (recién dado de alta) → el historial abre; ciudad/nodo «–», cifras a 0.
- Panelista sin ningún evento → lista vacía con texto «sin actividad», sin error.
- `p_before` en la frontera (dos eventos con el mismo instante) → ninguno se repite ni se pierde al «cargar más».
- `?case=<id>` de un caso inexistente o de otra cuenta → la pantalla carga normal, sin abrir nada ni romper.
- Nota con solo espacios o > 2000 caracteres → rechazada con mensaje traducido, nada guardado.

---

### Task 1: BD — `panelist_note`, `panelist_history`, `panelist_note_add`, `panelist_note_delete`

**Files:**
- Create: `supabase/migrations/20261124220000_panelist_history.sql`
- Create: `supabase/tests/panelist_history.test.sql`
- Runner local: `scratchpad/gps/histtest.sh` = copia de `rptest.sh` con `ROOT=/c/Users/fernandezi/projects/ONEMS_wt_historial`, `DB=onems_test_hist`.

**Interfaces:**
- Produces:
  - `public.panelist_history(p_panelist_id uuid, p_before timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit int DEFAULT 50) RETURNS jsonb`
    → `{"panelist":{"id","code","name","mobile","city","node","pobox","created","status","language"},
       "stats":{"sent_30d","scheduled_30d","receipt_problems_30d","gps_said_no_30d","leave_days_year","pobox_ref","home_ref","ref_needs_review"},
       "events":[{"id","at","type","subtype","status","data","link"}], "next": {"before": ts, "before_id": uuid}|null, "can_write": bool}`.
    `type` ∈ `note|incident|gps|receipt|leave|notice|gps_ref`. `link` = `{"screen":"reported"|"availability"|"receipts","id":uuid}` o null.
    `data` por tipo: note `{body,author,can_delete}`; incident `{category,description}`; gps `{place_kind}`;
    receipt `{reason,tag,role}` (`role` = `receiver`|`sender`); leave `{start,end,reason,review_status}`;
    notice `{body}`; gps_ref `{kind,source,needs_review,review_reason}`.
    Orden `at DESC, id DESC`; paginación por `(at, id) < (p_before, p_before_id)` (con `p_before_id` nulo: `at < p_before`).
  - `public.panelist_note_add(p_panelist_id uuid, p_body text) RETURNS uuid`
  - `public.panelist_note_delete(p_note_id uuid) RETURNS void`
  - Errores: sin permiso → `ERRCODE 42501`; texto inválido → `22023`.

- [ ] **Step 1: tests rojos** en `panelist_history.test.sql` (fixture `fixtures/incident_city.sql` con
  `\set fixture_sin_roles 1`; helpers `as_user`, `raises`, `fail_if` como en `account_access.test.sql`; usuarios:
  AM de A1, PM de A1, MS de A1, AM de A2, superadmin):
  - `am_ve_todo`: como AM de A1, `panelist_history(P1)` devuelve eventos de los 6 tipos sembrados (1 nota,
    1 incidencia `parcel_damaged`, 1 incidencia `gps_location` con `payload.reason='wrong_place'` → `type='gps'`,
    1 `receipt_case` `not_found` como receptor y 1 como remitente culpable, 1 baja, 1 `panelist_notification`
    `manager_notice`, 1 referencia `pobox` activa) y **no** el `receipt_case` `ok`; orden `at` descendente;
    `can_write = true`.
  - `sin_coordenadas`: el texto de la respuesta no contiene `latitude` ni `longitude`.
  - `otra_cuenta`: AM de A2 → `raises` (42501). `ms_sin_panelists`: MS de A1 → `raises`.
  - `apm_solo_lectura`: usuario con rol `allocation_plan_manager` → historial OK, `can_write = false`,
    `panelist_note_add` → `raises`.
  - `paginacion`: 3 notas con el **mismo** `created_at`; `p_limit=>2` → 2 eventos y `next` no nulo; segunda
    llamada con `next.before`/`next.before_id` → el evento restante, sin repetir ids; `next` nulo al final.
  - `notas`: `panelist_note_add(P1, '   ')` y con 2001 caracteres → `raises`; con texto válido → uuid; otro AM no
    puede borrarla (`raises`); el autor sí; superadmin sí.
  - `sin_nodo_y_vacio`: panelista sin nodo ni eventos → `events = []`, `panelist.node` nulo, `stats` a 0.
- [ ] **Step 2:** `bash histtest.sh build && bash histtest.sh test panelist_history` → FAIL (función no existe).
- [ ] **Step 3: migración.** Tabla `panelist_note` (§5.1 del spec, índice `(panelist_id, created_at DESC)`, RLS
  activado sin políticas → solo por funciones). Las tres funciones `SECURITY DEFINER SET search_path = public`,
  `REVOKE ALL … FROM PUBLIC, anon` + `GRANT EXECUTE … TO authenticated`. Autor de la nota: `profiles.full_name`,
  si no `profiles.email`. `stats` con ventana de 30 días en la zona de la cuenta.
- [ ] **Step 4:** `bash histtest.sh mig …/20261124220000_panelist_history.sql && bash histtest.sh test panelist_history account_access` → PASS.
- [ ] **Step 5:** suite completa → solo los 9 fallos previos conocidos.

### Task 2: Web — hook, panel lateral, botón y textos

**Files:**
- Create: `src/lib/panelistHistory.ts` (tipos de la respuesta de Task 1 + funciones puras)
- Create: `src/lib/__tests__/panelistHistory.test.ts`
- Create: `src/hooks/usePanelistHistory.ts`
- Create: `src/components/panelists/PanelistHistoryDrawer.tsx`, `src/components/panelists/PanelistHistoryButton.tsx`
- Modify: `public/locales/{es,en,fr,ar,pt}.csv` (claves `panelist_history.*`)

**Interfaces:**
- Consumes: JSON de Task 1.
- Produces:
  - `type HistoryEventType = 'note'|'incident'|'gps'|'receipt'|'leave'|'notice'|'gps_ref'`
  - `type HistoryFilter = 'all'|'note'|'incident'|'receipt'|'gps'|'leave'|'notice'` (`gps` incluye `gps_ref`)
  - `filterEvents(events: HistoryEvent[], f: HistoryFilter): HistoryEvent[]`
  - `eventTextKey(e: HistoryEvent): string` → clave i18n `panelist_history.event.<type>[.<subtype>]`
  - `linkHref(link: HistoryLink): string` → `/incidents/panelist-reported?incident=<id>`,
    `/incidents/panelist-availability?unavailability=<id>`, `/incidents/receipts?case=<id>`
  - `linkOption(link): AccessOption` → `reported_incidents` | `panelist_availability` | `receipts`
  - `usePanelistHistory(panelistId: string | null)` → `{data, events, loading, error, loadMore, hasMore, addNote(body), deleteNote(id), reload}`
  - `<PanelistHistoryButton panelistId={string} />` (no pinta nada si `!canView('panelists')`); abre `<PanelistHistoryDrawer panelistId onClose />`.

- [ ] **Step 1: tests rojos** (vitest) en `panelistHistory.test.ts`: `filterEvents` (gps incluye gps_ref; all
  devuelve todo), `linkHref` de los tres destinos, `eventTextKey` para incidente con categoría y para recepción
  remitente vs receptor, `linkOption`.
- [ ] **Step 2:** `npm test -- panelistHistory` → FAIL.
- [ ] **Step 3:** implementar `panelistHistory.ts`, el hook (RPC `panelist_history`, `panelist_note_add`,
  `panelist_note_delete`; recarga tras añadir/borrar; errores 42501/22023 a mensajes traducidos) y los dos
  componentes según §5.3 del spec (derecha ~60 % en escritorio, completo en móvil; ✕ y Esc cierran; caja de nota
  solo con `can_write`; «ver ›» con `target="_blank"` y solo si `canView(linkOption(link))`; borrar nota propia con
  `confirm`). RTL: usar clases lógicas (`ms-`/`me-`, `start`/`end`) para que el árabe salga a la izquierda.
  Claves CSV en los 5 ficheros (textos ES/EN/FR/AR/PT; PT = EN si no hay traducción revisada).
- [ ] **Step 4:** `npm test` → PASS; `npm run lint` → 0 warnings; `npm run build` → OK.

### Task 3: Web — botón en las pantallas y enlaces directos

**Files:**
- Modify: `src/components/incidents/ReportedIncidentHeader.tsx`, `src/pages/incidents/PanelistAvailabilityIncidents.tsx`
  (detalle), `src/components/incidents/receipts/ReceiptCaseDialog.tsx`, `src/components/incidents/receipts/ReceiptRepeatPanelists.tsx`,
  `src/pages/Panelists.tsx` (fila).
- Modify: `src/pages/incidents/PanelistReportedIncidents.tsx` (`?incident=<id>`), `src/pages/incidents/ReceiptErrors.tsx` (`?case=<id>`).

**Interfaces:**
- Consumes: `<PanelistHistoryButton panelistId>` de Task 2; `linkHref` de Task 2 (mismos parámetros).

- [ ] **Step 1:** añadir `<PanelistHistoryButton>` junto al nombre del panelista en las 5 ubicaciones.
- [ ] **Step 2:** `?incident=<id>`: al cargar, si la incidencia está en la lista, seleccionarla (mismo patrón que
  `?unavailability=` en `PanelistAvailabilityIncidents.tsx:29-39`); si no está, no hacer nada.
- [ ] **Step 3:** `?case=<id>`: cargar ese caso por id (de la cuenta actual; RLS lo garantiza) y abrir
  `ReceiptCaseDialog` aunque sea de otro día; si no existe, no hacer nada.
- [ ] **Step 4:** `npm run lint`, `npm run build` → OK. Prueba en `npm run dev` con DEMO2: el botón aparece en las
  5 pantallas, el panel abre y cierra sin perder la pantalla, «ver ›» abre pestaña nueva en el elemento correcto,
  añadir/borrar nota, «cargar más», árabe en RTL.

### Task 4: Puesta en marcha
- [ ] **Step 1:** confirmación de Ignacio → `apply_migration` en onems-dev; verificar md5 vivo = fichero y
  `panelist_history` de un panelista de DEMO2 (solo lectura con usuario superadmin simulado no es posible por MCP:
  comprobar existencia, grants y que `anon` no tiene EXECUTE).
- [ ] **Step 2:** con permiso de Ignacio: commit + push de la rama, PR a `develop` (Netlify dev) y prueba de Ignacio
  en DEMO2; después PR a `main` avisando antes qué verán Kenya/Senegal (el botón «📋 Historial» en esas pantallas).
- [ ] **Step 3:** memoria (`gps-declaracion.md` o memoria nueva `historial-panelista.md`) actualizada.
