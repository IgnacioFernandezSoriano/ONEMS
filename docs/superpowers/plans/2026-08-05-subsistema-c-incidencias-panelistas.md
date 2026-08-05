# Subsistema C — Incidencias / Disponibilidad de panelistas — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar al manager una pantalla para revisar y resolver (individual o por selección) las propuestas de reasignación que el motor B genera al crear una baja de panelista, y sentar el marco de menú "Incidencias".

**Architecture:** Frontend React (patrón página → hook → supabase) sobre el backend de B ya vivo. Única pieza de BD nueva: una RPC de solo lectura `list_reroute_candidates`. Las mutaciones del plan siguen yendo por las RPC `apply_reassignment_proposal` existentes; el cierre de incidencia es un `update` de `panelist_unavailability.review_status`.

**Tech Stack:** React 18 + TypeScript + Vite + Tailwind + react-router-dom; `@supabase/supabase-js`; Postgres (Supabase `onems-dev`, ref `sehbnpgzqljrsqimwyuz`); Deno (no aplica aquí). i18n propio (`useTranslation`).

## Global Constraints

- **Una sola BD:** `onems-dev`, ref `sehbnpgzqljrsqimwyuz`. Migraciones **forward-only** con timestamp posterior al baseline; nunca tocar `00000000000000_baseline_prod_schema.sql` ni `migrations_archive_pre_baseline/`. No ejecutar `db reset`/`db push` contra remoto.
- **Multi-tenant:** todo por RLS/`account_id`. El frontend nunca escribe `allocation_plan_details` directamente: siempre vía RPC `SECURITY DEFINER` con guard cross-tenant.
- **i18n obligatorio:** todo texto visible pasa por `useTranslation()`. Cada clave nueva se añade a los **4** ficheros: `src/locales/{en,es,fr,ar}/`. El árabe es RTL.
- **Puerta de calidad:** `npm run lint` (`--max-warnings 0`) y `npm run build` deben pasar. No hay tests de frontend; para BD, validar con el Postgres portable local (`supabase/tests/replay.ps1`).
- **Nombre visible de nodo** = `nodes.auto_id` (text). La ciudad tiene `cities.name`. `nodes` no tiene columna `name`.
- **Convenciones:** páginas/componentes PascalCase `.tsx`; hooks camelCase `use…`. No crear ficheros `*.backup/_old`. Rama `develop`; no commitear/pushear salvo que el usuario lo pida (lo gestiona el flujo SDD por tarea).
- **Cuenta activa:** usar `effectiveAccountId` de `useAccount()` (superadmin no tiene cuenta propia).

---

## Estructura de ficheros

- **Crear** `supabase/migrations/20260805HHMMSS_list_reroute_candidates.sql` — RPC de solo lectura.
- **Crear** `supabase/tests/list_reroute_candidates.test.sql` — test local (BEGIN/ROLLBACK).
- **Modificar** `src/locales/{en,es,fr,ar}/*.json` — claves `incidents.*` (fichero de namespace a elegir en Task 1-i18n; ver Task 2).
- **Crear** `src/lib/hooks/useReassignmentProposals.ts` — datos + acciones.
- **Modificar** `src/lib/types.ts` — tipos `ReassignmentProposal*`.
- **Crear** `src/pages/incidents/PanelistAvailabilityIncidents.tsx` — página (nivel 1 bandeja + navegación a nivel 2).
- **Crear** `src/components/incidents/ProposalReviewPanel.tsx` — detalle nivel 2 (tabla propuestas + acciones + override + dar por estudiado).
- **Modificar** `src/App.tsx` — ruta `/incidents/panelist-availability`.
- **Modificar** `src/components/layout/Sidebar.tsx` — grupo `INCIDENCIAS` + ítem con badge.
- **Modificar** `docs/database/2026-08-04-deploy-motor-reasignacion.md` (o nuevo runbook) — paso de despliegue de la RPC.

---

## Task 1: Migración `list_reroute_candidates` + test local

**Files:**
- Create: `supabase/migrations/20260805HHMMSS_list_reroute_candidates.sql`
- Test: `supabase/tests/list_reroute_candidates.test.sql`

**Interfaces:**
- Consumes: tablas `allocation_plan_details`, `nodes`, `profiles`; funciones `is_node_available(uuid,date)`, `is_superadmin()`.
- Produces: `list_reroute_candidates(p_detail_id uuid, p_role text) RETURNS TABLE(node_id uuid, node_name text, city_id uuid, is_available boolean)`.

> Nota: usar el timestamp real al crear el fichero (formato `YYYYMMDDHHMMSS`, posterior a `20260804121000`). Sustituir `HHMMSS` por la hora de creación.

- [ ] **Step 1: Escribir la migración**

Contenido completo del fichero de migración:

```sql
-- RPC de solo lectura: candidatos de reencaminado para una muestra y un rol.
-- Devuelve los nodos de la misma ciudad que el nodo actual del rol (distintos de él,
-- activos), con is_available evaluado en la fecha de la muestra. NO filtra los no
-- disponibles: la UI los muestra deshabilitados. No muta nada.
CREATE OR REPLACE FUNCTION public.list_reroute_candidates(p_detail_id uuid, p_role text)
RETURNS TABLE(node_id uuid, node_name text, city_id uuid, is_available boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_id uuid;
  v_current_node uuid;
  v_city_id uuid;
  v_date date;
  v_actor uuid := auth.uid();
  v_actor_account uuid;
BEGIN
  IF p_role NOT IN ('origin','destination') THEN
    RAISE EXCEPTION 'Invalid role %, expected origin or destination', p_role;
  END IF;

  SELECT apd.account_id,
         CASE WHEN p_role = 'origin' THEN apd.origin_node_id ELSE apd.destination_node_id END,
         apd.fecha_programada
    INTO v_account_id, v_current_node, v_date
  FROM allocation_plan_details apd
  WHERE apd.id = p_detail_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Detail % not found', p_detail_id; END IF;

  -- Guarda multi-tenant: usuario autenticado solo su cuenta; superadmin / service-role (NULL) pasan.
  IF v_actor IS NOT NULL AND NOT is_superadmin() THEN
    SELECT account_id INTO v_actor_account FROM profiles WHERE id = v_actor;
    IF v_actor_account IS DISTINCT FROM v_account_id THEN
      RAISE EXCEPTION 'Cross-tenant access denied';
    END IF;
  END IF;

  SELECT n.city_id INTO v_city_id FROM nodes n WHERE n.id = v_current_node;

  RETURN QUERY
  SELECT n.id, n.auto_id::text, n.city_id, is_node_available(n.id, v_date)
  FROM nodes n
  WHERE n.city_id = v_city_id
    AND n.id <> v_current_node
    AND n.status = 'active'
  ORDER BY n.auto_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_reroute_candidates(uuid, text) TO authenticated;
```

- [ ] **Step 2: Escribir el test local**

Contenido completo de `supabase/tests/list_reroute_candidates.test.sql` (mismo estilo que `generate_reassignment_proposals.test.sql`):

```sql
-- Cubre list_reroute_candidates: candidatos por ciudad/rol, exclusión del nodo propio,
-- flag is_available, validación de rol y guarda cross-tenant. Se ejecuta como postgres.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO public.accounts (id, name, slug) VALUES
  ('a0000000-0000-0000-0000-000000000001','Acc','acc');
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Reg','R1');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City1','C1'),
  ('c2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City2','C2');
-- N1 nodo actual (origin), N2 mismo city disponible, N4 mismo city con panelista de baja (no disponible),
-- N3 en otra ciudad (no debe salir).
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N1'),
  ('b2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N2'),
  ('b4000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N4'),
  ('b3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N3');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','P1','Pan1','p1@t.l','1','b1000000-0000-0000-0000-000000000001','active','en'),
  ('e2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','P2','Pan2','p2@t.l','2','b2000000-0000-0000-0000-000000000002','active','en'),
  ('e4000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','P4','Pan4','p4@t.l','4','b4000000-0000-0000-0000-000000000004','active','en');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','CA','Carrier');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR','Prod',48);
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('cc000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Plan','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-09-01','2026-09-30');
-- Muestra origin en N1, fecha 2026-09-10.
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000003','2026-09-10',37,9,2026,'pending');
-- P4 (nodo N4) está de baja el 2026-09-10 -> N4 no disponible ese día.
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status) VALUES
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000004','2026-09-10','2026-09-10','vacation','active');

-- Candidatos para el rol origin: deben ser N2 y N4 (misma ciudad, no N1, no N3). N2 disponible, N4 no.
DO $$
DECLARE v_count integer; v_n2_avail boolean; v_n4_avail boolean; v_has_n1 integer; v_has_n3 integer;
BEGIN
  SELECT count(*) INTO v_count FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','origin');
  IF v_count <> 2 THEN RAISE EXCEPTION 'FAIL: esperaba 2 candidatos, obtuve %', v_count; END IF;

  SELECT is_available INTO v_n2_avail FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','origin') WHERE node_id='b2000000-0000-0000-0000-000000000002';
  SELECT is_available INTO v_n4_avail FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','origin') WHERE node_id='b4000000-0000-0000-0000-000000000004';
  IF v_n2_avail IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: N2 debería estar disponible'; END IF;
  IF v_n4_avail IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL: N4 debería estar NO disponible'; END IF;

  SELECT count(*) INTO v_has_n1 FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','origin') WHERE node_id='b1000000-0000-0000-0000-000000000001';
  SELECT count(*) INTO v_has_n3 FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','origin') WHERE node_id='b3000000-0000-0000-0000-000000000003';
  IF v_has_n1 <> 0 THEN RAISE EXCEPTION 'FAIL: N1 (nodo propio) no debe aparecer'; END IF;
  IF v_has_n3 <> 0 THEN RAISE EXCEPTION 'FAIL: N3 (otra ciudad) no debe aparecer'; END IF;
  RAISE NOTICE 'PASS: candidatos correctos, is_available correcto, exclusiones correctas';
END $$;

-- Rol inválido -> excepción.
DO $$
BEGIN
  BEGIN
    PERFORM * FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','bogus');
    RAISE EXCEPTION 'FAIL: rol inválido debería fallar';
  EXCEPTION WHEN OTHERS THEN
    IF position('Invalid role' in SQLERRM) > 0 THEN RAISE NOTICE 'PASS: rol inválido rechazado';
    ELSE RAISE EXCEPTION 'FAIL: error inesperado: %', SQLERRM; END IF;
  END;
END $$;

-- Guarda cross-tenant.
INSERT INTO public.accounts (id, name, slug) VALUES
  ('a0000000-0000-0000-0000-000000000002','AccB','accb');
INSERT INTO auth.users (id, email) VALUES
  ('99999999-0000-0000-0000-000000000009','user.b@test.local');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('99999999-0000-0000-0000-000000000009','user.b@test.local','UserB','user','a0000000-0000-0000-0000-000000000002');
GRANT USAGE ON SCHEMA public TO authenticated;
CREATE OR REPLACE FUNCTION pg_temp.login(p_uid text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
END $$;
SET ROLE authenticated;
SELECT pg_temp.login('99999999-0000-0000-0000-000000000009');
DO $$
BEGIN
  BEGIN
    PERFORM * FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','origin');
    RAISE EXCEPTION 'FAIL guarda: se permitió acceso cross-tenant';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'Cross-tenant access denied' THEN RAISE NOTICE 'PASS: guarda cross-tenant';
    ELSE RAISE EXCEPTION 'FAIL guarda: error inesperado: %', SQLERRM; END IF;
  END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);

ROLLBACK;
```

- [ ] **Step 3: Aplicar el baseline + migraciones + este test en el Postgres portable local**

Run (PowerShell, desde la raíz del repo):
```
supabase/tests/replay.ps1
```
Luego ejecutar el test contra la BD local `onems_test` (puerto 5433, user postgres):
```
& "C:\Users\fernandezi\pgportable\bin\psql.exe" -h 127.0.0.1 -p 5433 -U postgres -d onems_test -v ON_ERROR_STOP=1 -f supabase/tests/list_reroute_candidates.test.sql
```
Expected: solo líneas `PASS: …`, sin `FAIL` ni error. Si `replay.ps1` no incluye el nuevo `.test.sql` automáticamente, ejecutarlo aparte como arriba.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260805*_list_reroute_candidates.sql supabase/tests/list_reroute_candidates.test.sql
git commit -m "feat(incidents): RPC list_reroute_candidates + test local"
```

---

## Task 2: Claves i18n (EN/ES/FR/AR)

**Files:**
- Modify: `src/locales/en/*.json`, `src/locales/es/*.json`, `src/locales/fr/*.json`, `src/locales/ar/*.json`

**Interfaces:**
- Produces: claves bajo `incidents.*` disponibles vía `t('incidents.…')` para Tasks 3–5.

> Antes de escribir, el implementador debe localizar cómo se cargan los locales (`src/locales/<lang>/` — comprobar si hay un `index` que agrega ficheros por namespace, o un único `common.json`). Añadir las claves al fichero que corresponda al patrón existente (probablemente un namespace nuevo `incidents.json` si el proyecto separa por ficheros, o al fichero común si es monolítico). **Las mismas claves deben existir en los 4 idiomas.**

- [ ] **Step 1: Añadir el bloque de claves en los 4 idiomas**

Claves mínimas (valores EN de referencia; traducir a ES/FR/AR):

```
incidents.menu_group              = "Incidents"
incidents.panelist_availability   = "Panelist availability"
incidents.title                   = "Panelist availability incidents"
incidents.pending_badge_tooltip   = "Unavailability records pending review"
incidents.inbox.panelist          = "Panelist"
incidents.inbox.node              = "Node / city"
incidents.inbox.dates             = "Unavailability dates"
incidents.inbox.affected          = "Affected samples"
incidents.inbox.breakdown         = "Send / receive"
incidents.inbox.pending           = "Pending"
incidents.inbox.review            = "Review"
incidents.inbox.empty             = "No pending incidents"
incidents.detail.back             = "Back to list"
incidents.detail.mark_reviewed    = "Mark as studied"
incidents.detail.mark_reviewed_disabled = "Resolve every proposal first"
incidents.detail.sample           = "Sample"
incidents.detail.role             = "Role"
incidents.detail.role_origin      = "Send"
incidents.detail.role_destination = "Receive"
incidents.detail.sample_status    = "Sample status"
incidents.detail.suggested_action = "Suggested action"
incidents.detail.suggestion       = "Suggestion"
incidents.detail.reason           = "Reason"
incidents.detail.proposal_status  = "Status"
incidents.detail.actions          = "Actions"
incidents.action.confirm          = "Confirm"
incidents.action.change           = "Change…"
incidents.action.dismiss          = "Dismiss"
incidents.action.confirm_selected = "Confirm selected"
incidents.action.dismiss_selected = "Dismiss selected"
incidents.action.selected_count   = "{{count}} selected"
incidents.override.title          = "Change resolution"
incidents.override.choose_action  = "Final action"
incidents.override.reroute        = "Reroute to another node"
incidents.override.shift_date     = "Change date"
incidents.override.cancel_sample  = "Cancel sample"
incidents.override.target_node    = "Target node"
incidents.override.node_unavailable = "(no panelist available)"
incidents.override.new_date       = "New date"
incidents.override.apply          = "Apply"
incidents.override.cancel         = "Cancel"
incidents.act.reroute             = "Reroute"
incidents.act.shift_date          = "Shift date"
incidents.act.cancel              = "Cancel"
incidents.act.none                = "Informative"
incidents.status.pending          = "Pending"
incidents.status.confirmed        = "Confirmed"
incidents.status.dismissed        = "Dismissed"
```

(ES ejemplos: `incidents.menu_group="Incidencias"`, `panelist_availability="Disponibilidad de panelistas"`, `title="Incidencias de disponibilidad de panelistas"`, `action.confirm="Confirmar"`, `action.change="Cambiar…"`, `action.dismiss="Descartar"`, `detail.mark_reviewed="Dar por estudiado"`, etc. Traducir todas a ES, FR y AR con el mismo conjunto de claves.)

- [ ] **Step 2: Verificar que las 4 lenguas tienen exactamente las mismas claves**

Run:
```
npm run build
```
Expected: build sin errores (TypeScript + Vite). Revisar que no falte ninguna clave en ningún idioma (mismo set en los 4 ficheros).

- [ ] **Step 3: Commit**

```bash
git add src/locales
git commit -m "i18n(incidents): claves del subsistema C en EN/ES/FR/AR"
```

---

## Task 3: Tipos + hook `useReassignmentProposals`

**Files:**
- Modify: `src/lib/types.ts`
- Create: `src/lib/hooks/useReassignmentProposals.ts`

**Interfaces:**
- Consumes: tabla `panelist_reassignment_proposal`, `panelist_unavailability`, `allocation_plan_details`, `nodes`, `cities`, `panelists`; RPCs `apply_reassignment_proposal`, `list_reroute_candidates`; `useAccount().effectiveAccountId`.
- Produces: hook `useReassignmentProposals()` con la API descrita abajo; tipos `ReassignmentProposal`, `IncidentInboxRow`, `RerouteCandidate`.

- [ ] **Step 1: Añadir tipos en `src/lib/types.ts`**

```ts
export type ProposalAction = 'reroute' | 'shift_date' | 'cancel' | 'none'
export type ProposalStatus = 'pending' | 'confirmed' | 'dismissed'
export type AffectedRole = 'origin' | 'destination'

export interface ReassignmentProposal {
  id: string
  account_id: string
  unavailability_id: string
  allocation_plan_detail_id: string
  affected_role: AffectedRole
  sample_status_at_detection: string | null
  suggested_action: ProposalAction
  suggested_target_node_id: string | null
  suggested_date: string | null
  suggested_reason: string | null
  final_action: string | null
  final_target_node_id: string | null
  final_date: string | null
  status: ProposalStatus
  confirmed_by: string | null
  confirmed_at: string | null
  created_at: string
  updated_at: string
  // joins (opcionales, poblados por el hook)
  detail?: { id: string; fecha_programada: string; status: string; origin_node_id: string; destination_node_id: string } | null
  suggested_target_node?: { id: string; auto_id: string } | null
}

export interface IncidentInboxRow {
  unavailability_id: string
  panelist_name: string
  panelist_code: string
  node_label: string
  city_name: string
  start_date: string
  end_date: string
  affected_count: number
  origin_count: number
  destination_count: number
  pending_count: number
}

export interface RerouteCandidate {
  node_id: string
  node_name: string
  city_id: string
  is_available: boolean
}
```

- [ ] **Step 2: Crear el hook `src/lib/hooks/useReassignmentProposals.ts`**

Estructura (patrón de los hooks existentes; usa `supabase` de `@/lib/supabase` y `useAccount`). Puntos clave — las llamadas RPC deben ser **exactamente** estas:

```ts
import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'
import type { ReassignmentProposal, IncidentInboxRow, RerouteCandidate } from '@/lib/types'

export function useReassignmentProposals() {
  const { effectiveAccountId } = useAccount()
  const [inbox, setInbox] = useState<IncidentInboxRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // Nivel 1: bajas pending_review con propuestas y contadores.
  const fetchInbox = useCallback(async () => {
    try {
      setLoading(true); setError(null)
      // Traer propuestas de la cuenta activa con joins a baja/panelista/nodo/ciudad,
      // y agregarlas por unavailability_id en JS.
      let q = supabase
        .from('panelist_reassignment_proposal')
        .select(`
          id, unavailability_id, affected_role, status,
          unavailability:panelist_unavailability!inner (
            id, start_date, end_date, review_status,
            panelist:panelists ( name, panelist_code, node:nodes ( auto_id, city:cities ( name ) ) )
          )
        `)
      if (effectiveAccountId) q = q.eq('account_id', effectiveAccountId)
      const { data, error: e } = await q
      if (e) throw e
      // Filtrar a review_status='pending_review' y agregar contadores por baja.
      const byBaja = new Map<string, IncidentInboxRow>()
      for (const row of (data || []) as any[]) {
        const u = row.unavailability
        if (!u || u.review_status !== 'pending_review') continue
        let agg = byBaja.get(u.id)
        if (!agg) {
          agg = {
            unavailability_id: u.id,
            panelist_name: u.panelist?.name ?? '-',
            panelist_code: u.panelist?.panelist_code ?? '-',
            node_label: u.panelist?.node?.auto_id ?? '-',
            city_name: u.panelist?.node?.city?.name ?? '-',
            start_date: u.start_date, end_date: u.end_date,
            affected_count: 0, origin_count: 0, destination_count: 0, pending_count: 0,
          }
          byBaja.set(u.id, agg)
        }
        agg.affected_count++
        if (row.affected_role === 'origin') agg.origin_count++; else agg.destination_count++
        if (row.status === 'pending') agg.pending_count++
      }
      setInbox(Array.from(byBaja.values()))
    } catch (err: any) { setError(err.message); console.error('fetchInbox', err) }
    finally { setLoading(false) }
  }, [effectiveAccountId])

  useEffect(() => { fetchInbox() }, [fetchInbox])

  // Nivel 2: propuestas de una baja concreta.
  const fetchProposals = async (unavailabilityId: string): Promise<ReassignmentProposal[]> => {
    const { data, error: e } = await supabase
      .from('panelist_reassignment_proposal')
      .select(`
        *,
        detail:allocation_plan_details ( id, fecha_programada, status, origin_node_id, destination_node_id ),
        suggested_target_node:nodes!prp_target_node_fkey ( id, auto_id )
      `)
      .eq('unavailability_id', unavailabilityId)
      .order('affected_role').order('created_at')
    if (e) throw e
    return (data || []) as any
  }

  const confirmProposal = async (p: ReassignmentProposal) => {
    const { error: e } = await supabase.rpc('apply_reassignment_proposal', {
      p_proposal_id: p.id,
      p_final_action: p.suggested_action,
      p_final_target_node_id: p.suggested_target_node_id,
      p_final_date: p.suggested_date,
    })
    if (e) throw e
  }

  const overrideProposal = async (
    id: string,
    action: 'reroute' | 'shift_date' | 'cancel',
    nodeId?: string | null,
    date?: string | null,
  ) => {
    // reroute/shift_date/cancel manuales se envían como 'manual' salvo cancel, que va como 'cancel'.
    const finalAction = action === 'cancel' ? 'cancel' : 'manual'
    const { error: e } = await supabase.rpc('apply_reassignment_proposal', {
      p_proposal_id: id,
      p_final_action: finalAction,
      p_final_target_node_id: action === 'reroute' ? (nodeId ?? null) : null,
      p_final_date: action === 'shift_date' ? (date ?? null) : null,
    })
    if (e) throw e
  }

  const dismissProposal = async (id: string) => {
    const { error: e } = await supabase.rpc('apply_reassignment_proposal', {
      p_proposal_id: id, p_final_action: 'none', p_final_target_node_id: null, p_final_date: null,
    })
    if (e) throw e
  }

  const confirmMany = async (props: ReassignmentProposal[]) => {
    for (const p of props) { if (p.status === 'pending') await confirmProposal(p) }
  }
  const dismissMany = async (ids: string[]) => {
    for (const id of ids) await dismissProposal(id)
  }

  const listRerouteCandidates = async (detailId: string, role: 'origin' | 'destination'): Promise<RerouteCandidate[]> => {
    const { data, error: e } = await supabase.rpc('list_reroute_candidates', { p_detail_id: detailId, p_role: role })
    if (e) throw e
    return (data || []) as RerouteCandidate[]
  }

  const markReviewed = async (unavailabilityId: string) => {
    const { data: { user } } = await supabase.auth.getUser()
    const { error: e } = await supabase
      .from('panelist_unavailability')
      .update({ review_status: 'reviewed', updated_by: user?.id ?? null })
      .eq('id', unavailabilityId)
    if (e) throw e
    await fetchInbox()
  }

  const pendingCount = inbox.length

  return {
    inbox, loading, error, pendingCount,
    fetchInbox, fetchProposals,
    confirmProposal, overrideProposal, dismissProposal, confirmMany, dismissMany,
    listRerouteCandidates, markReviewed,
  }
}
```

> **Nota FK del join:** el constraint real es `prp_target_node_fkey` (verificado en `20260804120000_reassignment_proposals_schema.sql`, línea `CONSTRAINT prp_target_node_fkey FOREIGN KEY (suggested_target_node_id) REFERENCES public.nodes(id)`). Si aun así el join por nombre de FK fallara en runtime, fallback: resolver los nombres de nodo en JS con una segunda query a `nodes` por ids.

- [ ] **Step 3: Verificar compilación**

Run: `npm run lint && npm run build`
Expected: 0 warnings, build OK.

- [ ] **Step 4: Commit**

```bash
git add src/lib/types.ts src/lib/hooks/useReassignmentProposals.ts
git commit -m "feat(incidents): tipos + hook useReassignmentProposals"
```

---

## Task 4: Menú `INCIDENCIAS` + ruta + página bandeja (nivel 1)

**Files:**
- Modify: `src/components/layout/Sidebar.tsx`
- Modify: `src/App.tsx`
- Create: `src/pages/incidents/PanelistAvailabilityIncidents.tsx`

**Interfaces:**
- Consumes: `useReassignmentProposals()` (Task 3), claves i18n (Task 2), `ProposalReviewPanel` (Task 5 — importar; hasta que exista, el detalle muestra un placeholder mínimo NO — ver nota).
- Produces: ruta `/incidents/panelist-availability`; grupo de menú `INCIDENCIAS`.

> Orden: esta tarea deja la bandeja (nivel 1) funcional y navega a un detalle. El componente de detalle `ProposalReviewPanel` se construye en Task 5. Para que Task 4 sea testable de forma independiente, la página importa `ProposalReviewPanel` y Task 5 lo crea; por tanto **crear en esta tarea un stub mínimo** `src/components/incidents/ProposalReviewPanel.tsx` que renderice solo la cabecera + botón "volver" (sin la tabla), y Task 5 lo completa. El stub debe compilar y usar `useTranslation`.

- [ ] **Step 1: Grupo de menú `INCIDENCIAS` en `Sidebar.tsx`**

Importar un icono de alerta de `lucide-react` (p.ej. `AlertTriangle`) en el bloque de imports. Añadir, al final del array `allModulesMenuGroups` (después del grupo Administración o antes; da igual el orden visual, elegir tras E2E), un grupo nuevo. El badge lo aporta `useReassignmentProposals().pendingCount`:

```tsx
// cerca del top del componente Sidebar():
const { pendingCount } = useReassignmentProposals()
```

```tsx
// nuevo grupo en allModulesMenuGroups (no lleva label 'E2E' ni 'DIAGNOSIS' -> visible siempre):
{
  label: t('incidents.menu_group'),
  items: [
    {
      path: '/incidents/panelist-availability',
      label: t('incidents.panelist_availability'),
      icon: AlertTriangle,
      roles: ['admin', 'superadmin'],
      tooltip: t('incidents.pending_badge_tooltip'),
    },
  ],
},
```

Renderizar el badge junto al label del ítem (solo si `pendingCount > 0`). En el bloque `<Link>` de ítems sin hijos, añadir tras el `<span>{item.label}</span>`:

```tsx
{item.path === '/incidents/panelist-availability' && pendingCount > 0 && isExpanded && (
  <span className="ml-auto text-xs bg-red-100 text-red-700 px-2 py-0.5 rounded-full font-medium">
    {pendingCount}
  </span>
)}
```

> Importar el hook: `import { useReassignmentProposals } from '../../lib/hooks/useReassignmentProposals'`. Verificar que no rompe cuando no hay cuenta activa (el hook ya tolera `effectiveAccountId` nulo devolviendo lista vacía).

- [ ] **Step 2: Ruta en `App.tsx`**

Import: `import { PanelistAvailabilityIncidents } from './pages/incidents/PanelistAvailabilityIncidents'`.
Dentro del `<Routes>` protegido, añadir:

```tsx
<Route
  path="/incidents/panelist-availability"
  element={
    <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
      <PanelistAvailabilityIncidents />
    </ProtectedRoute>
  }
/>
```

- [ ] **Step 3: Crear stub `src/components/incidents/ProposalReviewPanel.tsx`**

```tsx
import { useTranslation } from '@/hooks/useTranslation'

export function ProposalReviewPanel({ unavailabilityId, onBack }: { unavailabilityId: string; onBack: () => void }) {
  const { t } = useTranslation()
  return (
    <div>
      <button onClick={onBack} className="text-blue-600 hover:text-blue-800 mb-4">← {t('incidents.detail.back')}</button>
      <p className="text-gray-500">Detalle en construcción ({unavailabilityId}).</p>
    </div>
  )
}
```

- [ ] **Step 4: Crear la página bandeja `src/pages/incidents/PanelistAvailabilityIncidents.tsx`**

```tsx
import { useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { useReassignmentProposals } from '@/lib/hooks/useReassignmentProposals'
import { ProposalReviewPanel } from '@/components/incidents/ProposalReviewPanel'

export function PanelistAvailabilityIncidents() {
  const { t } = useTranslation()
  const { inbox, loading, error, fetchInbox } = useReassignmentProposals()
  const [selected, setSelected] = useState<string | null>(null)

  if (loading) return <div className="p-6">Loading...</div>
  if (error) return <div className="p-6 text-red-600">Error: {error}</div>

  if (selected) {
    return (
      <div className="p-6">
        <ProposalReviewPanel unavailabilityId={selected} onBack={() => { setSelected(null); fetchInbox() }} />
      </div>
    )
  }

  return (
    <div className="p-6">
      <h2 className="text-xl font-bold mb-6">{t('incidents.title')}</h2>
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.panelist')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.node')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.dates')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.affected')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.breakdown')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.pending')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.review')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {inbox.length > 0 ? inbox.map((row) => (
                <tr key={row.unavailability_id} className="hover:bg-gray-50">
                  <td className="px-6 py-4 text-sm">
                    <div className="font-medium">{row.panelist_name}</div>
                    <div className="text-gray-500 text-xs font-mono">{row.panelist_code}</div>
                  </td>
                  <td className="px-6 py-4 text-sm">{row.node_label} · {row.city_name}</td>
                  <td className="px-6 py-4 text-sm">{row.start_date} – {row.end_date}</td>
                  <td className="px-6 py-4 text-sm">{row.affected_count}</td>
                  <td className="px-6 py-4 text-sm">{row.origin_count} / {row.destination_count}</td>
                  <td className="px-6 py-4 text-sm">{row.pending_count}</td>
                  <td className="px-6 py-4 text-sm">
                    <button onClick={() => setSelected(row.unavailability_id)} className="text-blue-600 hover:text-blue-800">
                      {t('incidents.inbox.review')}
                    </button>
                  </td>
                </tr>
              )) : (
                <tr><td colSpan={7} className="px-6 py-4 text-center text-gray-500">{t('incidents.inbox.empty')}</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
```

- [ ] **Step 5: Verificar**

Run: `npm run lint && npm run build`
Expected: 0 warnings, build OK. Manualmente (si hay `npm run dev`): el ítem "Incidencias" aparece, la bandeja lista las bajas pending_review con propuestas, "Revisar" abre el stub.

- [ ] **Step 6: Commit**

```bash
git add src/components/layout/Sidebar.tsx src/App.tsx src/pages/incidents/PanelistAvailabilityIncidents.tsx src/components/incidents/ProposalReviewPanel.tsx
git commit -m "feat(incidents): grupo de menú, ruta y bandeja (nivel 1)"
```

---

## Task 5: Detalle nivel 2 — tabla de propuestas, acciones y "dar por estudiado"

**Files:**
- Modify: `src/components/incidents/ProposalReviewPanel.tsx` (reemplaza el stub por la versión completa)

**Interfaces:**
- Consumes: `useReassignmentProposals()`, tipos de Task 3, claves i18n de Task 2.
- Produces: componente `ProposalReviewPanel` completo.

- [ ] **Step 1: Implementar el panel completo**

Reemplazar el stub. Requisitos (patrón de checkboxes/selección igual que `PanelistUnavailability.tsx`):

- Al montar, `fetchProposals(unavailabilityId)` → estado `proposals`.
- Estado `selectedIds: Set<string>` con seleccionar-todo (solo sobre filas `pending`) y seleccionar-una.
- Tabla con columnas: checkbox, muestra (`detail.fecha_programada` + id corto), rol (`incidents.detail.role_origin/destination`), estado muestra, acción sugerida (badge con `incidents.act.*`), sugerencia (nombre nodo `suggested_target_node?.auto_id` o `suggested_date`), motivo, estado propuesta (badge `incidents.status.*`), acciones.
- Filas no `pending`: atenuadas, sin checkbox ni acciones; muestran `final_action`.
- **Acciones por fila (pending):** `Confirmar` → `confirmProposal(p)`; `Cambiar…` → abre modal override; `Descartar` → `dismissProposal(p.id)`. Tras cada una, refrescar `fetchProposals` y recalcular.
- **Barra de selección** (cuando `selectedIds.size > 0`): `Confirmar seleccionadas` → `confirmMany(proposals.filter(p => selectedIds.has(p.id)))`; `Descartar seleccionadas` → `dismissMany([...selectedIds])`; limpiar selección. Refrescar al terminar.
- **Modal override** (`Cambiar…`): selector de acción final:
  - `reroute`: al elegirlo, cargar `listRerouteCandidates(p.allocation_plan_detail_id, p.affected_role)` en un `<select>`; cada opción muestra `node_name` y, si `!is_available`, sufijo `incidents.override.node_unavailable` (no deshabilitar; el manager decide). Enviar `overrideProposal(p.id, 'reroute', nodeId)`.
  - `shift_date`: `<input type="date">` → `overrideProposal(p.id, 'shift_date', null, date)`.
  - `cancel_sample`: sin más campos → `overrideProposal(p.id, 'cancel')`.
- **Cabecera:** botón `Dar por estudiado` → `markReviewed(unavailabilityId)` y luego `onBack()`. **Deshabilitado** si `proposals.some(p => p.status === 'pending')`, con tooltip `incidents.detail.mark_reviewed_disabled`.
- Todo el texto por `t(...)`. Manejo de error con `alert`/estado como en el resto de la app.

Referencia de estilo/estructura: `src/components/PanelistUnavailability.tsx` (checkboxes, barra de selección, badges, modal). No copiar literal: adaptar a propuestas.

> El implementador debe escribir el componente completo siguiendo estos requisitos y el patrón referenciado. Verificar que `apply_reassignment_proposal` con `p_final_action='manual'` y `nodeId` correcto según rol funciona (la RPC ya distingue origin/destination internamente).

- [ ] **Step 2: Verificar**

Run: `npm run lint && npm run build`
Expected: 0 warnings, build OK. Manual (si hay dev + la baja e2e de prueba `ed403820-…` sigue con propuestas pending): confirmar una, descartar otra, override reroute con candidatos, y comprobar que "Dar por estudiado" solo se habilita cuando no quedan pendientes.

- [ ] **Step 3: Commit**

```bash
git add src/components/incidents/ProposalReviewPanel.tsx
git commit -m "feat(incidents): detalle nivel 2 con acciones individual/selección y cierre"
```

---

## Task 6: Runbook de despliegue de la RPC

**Files:**
- Modify: `docs/database/2026-08-04-deploy-motor-reasignacion.md` (añadir sección) o Create: `docs/database/2026-08-05-deploy-list-reroute-candidates.md`

**Interfaces:**
- Consumes: la migración de Task 1.
- Produces: pasos web para desplegar `list_reroute_candidates` en `onems-dev`.

- [ ] **Step 1: Escribir el paso de despliegue**

Documentar (estilo del runbook existente): confirmar proyecto `onems-dev` (ref `sehbnpgzqljrsqimwyuz`); SQL Editor → New query → pegar el contenido de `20260805*_list_reroute_candidates.sql` → Run → *Success. No rows returned*; verificación:

```sql
select count(*) as ok from pg_proc where proname = 'list_reroute_candidates';  -- ok = 1
```

Incluir nota: como se aplica por SQL Editor (no CLI), registrar la versión en `supabase_migrations.schema_migrations` si en el futuro se usa el CLI (mismo criterio que las 3 migraciones de B).

- [ ] **Step 2: Commit**

```bash
git add docs/database/
git commit -m "docs(incidents): runbook de despliegue de list_reroute_candidates"
```

---

## Self-Review (autor del plan)

**Cobertura del spec:**
- §3 RPC `list_reroute_candidates` → Task 1. ✅
- §4 grupo de menú + badge → Task 4. ✅
- §5.1 bandeja nivel 1 → Task 4. ✅
- §5.2/5.3 detalle + acciones individual/selección + override → Task 5. ✅
- §5.4 "dar por estudiado" con gating → Task 5. ✅
- §6 hook → Task 3. ✅
- §7 i18n 4 idiomas → Task 2. ✅
- §8 seguridad (RPC guard, sin escritura directa) → Task 1 (guard) + Task 3/5 (solo RPC). ✅
- §9 validación local + lint/build → Tasks 1/2/3/4/5. ✅
- §10 runbook → Task 6. ✅

**Consistencia de tipos:** el hook (Task 3) fija las firmas (`confirmProposal(p)`, `overrideProposal(id, action, nodeId?, date?)`, `listRerouteCandidates(detailId, role)`, `markReviewed(id)`); Tasks 4 y 5 las consumen tal cual. La RPC (Task 1) usa `(p_detail_id, p_role)` y el hook la invoca con esas claves. ✅

**Orden de dependencias:** Task 1 (BD) y Task 2 (i18n) son independientes; Task 3 depende de tipos; Task 4 crea stub del panel para ser testable sola; Task 5 completa el panel. Correcto.

**Riesgo señalado:** nombre del constraint FK para el join `suggested_target_node` — la nota en Task 3 Step 2 indica verificarlo y el fallback (resolver nombres en JS). ✅
