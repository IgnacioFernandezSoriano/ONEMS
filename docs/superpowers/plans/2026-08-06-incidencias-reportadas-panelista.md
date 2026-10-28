# Incidencias reportadas por el panelista — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tabla + backend + pantalla del manager para gestionar incidencias que el panelista reporta (vía Telegram/n8n, en otro entorno), con tratamiento guiado por categoría y canal de respuesta al panelista.

**Architecture:** Forward-only en `onems-dev`. Nueva tabla `panelist_incident` (RLS por `account_id`) que n8n rellena; RPCs `SECURITY DEFINER` con guarda cross-tenant que ejecutan las acciones reales (recepción manual, invalidar, reprogramar/cancelar, crear baja, actualizar contacto, resolver); pantalla React (página → hook → supabase) en el grupo INCIDENCIAS con detalle de acción por categoría. Bucket de storage privado para fotos. Spec: `docs/superpowers/specs/2026-08-06-incidencias-reportadas-panelista-design.md`.

**Tech Stack:** Supabase Postgres (migración SQL), Deno no aplica (sin edge function), React 18 + TS + Vite + Tailwind, i18n CSV en `public/locales/`.

## Global Constraints

- **Base única:** `onems-dev`, ref `sehbnpgzqljrsqimwyuz`. Antes de aplicar la migración/RPCs en prod, nombrar proyecto+ref y pedir confirmación explícita. Validar antes en el Postgres portable local (`127.0.0.1:5433`, `supabase/tests/replay_baseline.ps1`).
- **Forward-only:** una migración nueva con timestamp posterior al baseline (`YYYYMMDDHHMMSS_desc.sql`). No tocar `00000000000000_baseline_prod_schema.sql` ni el archivo `migrations_archive_pre_baseline/`.
- **Multi-tenant:** toda tabla y RPC aísla por `account_id`. RLS con `current_user_account_id()`/`is_superadmin()` (patrón del repo). RPCs `SECURITY DEFINER` con guarda: `auth.uid()` NULL (service-role/n8n) se permite; usuario autenticado no-superadmin solo su cuenta.
- **i18n:** todo texto visible por `useTranslation()`; añadir claves a los **4** ficheros `public/locales/{en,es,fr,ar}.csv` (formato `key,translation`, interpolación `{var}`). Nunca hardcodear cadenas.
- **Puertas de calidad:** `npm run lint` y `npm run build` deben pasar. No hay tests de frontend.
- **Estilo:** páginas/componentes PascalCase `.tsx`; hooks camelCase `use*`. Seguir el patrón de `PanelistAvailabilityIncidents` + `useReassignmentProposals` + `ProposalReviewPanel`.
- **Códigos de categoría (9, cerrados):** `missing_materials`, `unreadable_label_receipt`, `parcel_damaged`, `parcel_returned`, `how_to_send`, `unavailability_request`, `tag_photo_problem`, `contact_data_change`, `other`.
- **Estados:** `open` → `in_progress` → `resolved` / `dismissed`. Badge = `open` + `in_progress`.
- **Decisiones cerradas (spec §9):** reprogramar/cancelar por **RPC in-line**; cierre por **"Resolver" explícito** (la acción deja `in_progress`); `payload` con **esquema mínimo documentado**; fotos en **Supabase Storage** (bucket privado, la app genera signed URLs, n8n sube).

---

## File Structure

- Create: `supabase/migrations/<ts>_panelist_incident.sql` — tabla, RLS, índices, bucket, RPCs.
- Create: `src/lib/hooks/useReportedIncidents.ts` — datos + acciones.
- Create: `src/pages/incidents/PanelistReportedIncidents.tsx` — bandeja.
- Create: `src/components/incidents/ReportedIncidentPanel.tsx` — detalle + acciones por categoría.
- Modify: `src/lib/types.ts` (o `types_*.ts`) — tipos `ReportedIncident`, `ReportedIncidentCategory`.
- Modify: `src/components/layout/Sidebar.tsx` — entrada de menú encima de "Disponibilidad de panelistas" + badge propio.
- Modify: `src/App.tsx` — ruta `/incidents/panelist-reported`.
- Modify: `public/locales/{en,es,fr,ar}.csv` — claves `reported_incidents.*`.
- Create: `docs/integrations/2026-08-06-n8n-incidencias-reportadas.md` — contrato para n8n.

---

## Task 1: Migración — tabla `panelist_incident`, RLS, índices, bucket de fotos

**Files:**
- Create: `supabase/migrations/<ts>_panelist_incident.sql`

**Interfaces:**
- Produces: tabla `public.panelist_incident` con las columnas de abajo; bucket storage `incident-photos`.

- [ ] **Step 1.1: Confirmar helpers y columnas dependientes contra el baseline**

Antes de escribir, verificar en el baseline (`supabase/migrations/00000000000000_baseline_prod_schema.sql`) que existen: funciones `current_user_account_id()` e `is_superadmin()`; tabla `allocation_plan_details` con columnas `account_id`, `status`, `received_at`, `fecha_programada`; tabla `panelists` con `telegram_id`, `phone` (o el nombre real del teléfono), `language`; tabla `panelist_unavailability` con `account_id`, `panelist_id`, `start_date`, `end_date`, `reason`, `status`. Anotar los nombres reales si difieren (p. ej. si el teléfono se llama distinto) — se usan en las Tasks 2.

- [ ] **Step 1.2: Escribir la migración de tabla**

Crear el fichero con timestamp posterior al baseline. Contenido:

```sql
-- Incidencias reportadas por el panelista (vía Telegram/n8n). Forward-only. NO toca baseline.

CREATE TABLE public.panelist_incident (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  panelist_id uuid NOT NULL,
  category text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  description text,
  photo_url text,
  allocation_plan_detail_id uuid,
  linked_unavailability_id uuid,
  payload jsonb,
  resolution_note text,
  reply_to_panelist text,
  reply_status text NOT NULL DEFAULT 'none',
  reply_sent_at timestamptz,
  created_via text NOT NULL DEFAULT 'telegram',
  reported_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolved_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT panelist_incident_pkey PRIMARY KEY (id),
  CONSTRAINT pi_category_check CHECK (category IN (
    'missing_materials','unreadable_label_receipt','parcel_damaged','parcel_returned',
    'how_to_send','unavailability_request','tag_photo_problem','contact_data_change','other')),
  CONSTRAINT pi_status_check CHECK (status IN ('open','in_progress','resolved','dismissed')),
  CONSTRAINT pi_reply_status_check CHECK (reply_status IN ('none','pending_send','sent')),
  CONSTRAINT pi_panelist_fkey FOREIGN KEY (panelist_id) REFERENCES public.panelists(id) ON DELETE CASCADE,
  CONSTRAINT pi_detail_fkey FOREIGN KEY (allocation_plan_detail_id) REFERENCES public.allocation_plan_details(id) ON DELETE SET NULL,
  CONSTRAINT pi_unavailability_fkey FOREIGN KEY (linked_unavailability_id) REFERENCES public.panelist_unavailability(id) ON DELETE SET NULL,
  CONSTRAINT pi_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES public.profiles(id)
);

CREATE INDEX idx_pi_account_status ON public.panelist_incident(account_id, status);
CREATE INDEX idx_pi_panelist ON public.panelist_incident(panelist_id);
CREATE INDEX idx_pi_detail ON public.panelist_incident(allocation_plan_detail_id);
CREATE INDEX idx_pi_reply_pending ON public.panelist_incident(account_id) WHERE reply_status = 'pending_send';

ALTER TABLE public.panelist_incident ENABLE ROW LEVEL SECURITY;

CREATE POLICY pi_select ON public.panelist_incident
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY pi_insert ON public.panelist_incident
  FOR INSERT WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY pi_update ON public.panelist_incident
  FOR UPDATE USING (account_id = current_user_account_id() OR is_superadmin())
  WITH CHECK (account_id = current_user_account_id() OR is_superadmin());

GRANT SELECT, INSERT, UPDATE ON public.panelist_incident TO authenticated;

-- Bucket privado para fotos adjuntas (n8n sube con service-role; la app genera signed URLs).
INSERT INTO storage.buckets (id, name, public)
VALUES ('incident-photos', 'incident-photos', false)
ON CONFLICT (id) DO NOTHING;
```

- [ ] **Step 1.3: Validar en local (replay del baseline + migraciones)**

Run: `pwsh supabase/tests/replay_baseline.ps1` (o el flujo local equivalente del repo).
Expected: aplica sin error; la tabla `panelist_incident` existe. Comprobar:

```sql
SELECT count(*) FROM information_schema.tables WHERE table_name = 'panelist_incident'; -- 1
SELECT count(*) FROM storage.buckets WHERE id = 'incident-photos';                    -- 1 (si el shim local tiene schema storage; si no, anotarlo)
```
Si el Postgres portable no tiene el schema `storage`, envolver el INSERT del bucket en un guard `DO $$ BEGIN IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name='storage') THEN ... END IF; END $$;` o anotar que el bucket se crea aparte por dashboard.

- [ ] **Step 1.4: Commit**

```bash
git add supabase/migrations/<ts>_panelist_incident.sql
git commit -m "feat(incidents): tabla panelist_incident (reportadas por panelista) + RLS + bucket"
```

---

## Task 2: RPCs de acción

**Files:**
- Modify: `supabase/migrations/<ts>_panelist_incident.sql` (añadir al final; misma migración)

**Interfaces:**
- Produces (firmas exactas que consume el hook de Task 3):
  - `resolve_panelist_incident(p_incident_id uuid, p_status text, p_resolution_note text, p_reply_text text) → void`
  - `mark_detail_received_manual(p_detail_id uuid) → void`
  - `invalidate_detail(p_detail_id uuid, p_note text) → void`
  - `reschedule_detail(p_detail_id uuid, p_new_date date) → void`
  - `cancel_detail(p_detail_id uuid) → void`
  - `update_panelist_contact(p_panelist_id uuid, p_telegram_id text, p_phone text, p_language text) → void`
  - `create_unavailability_from_incident(p_incident_id uuid, p_start date, p_end date, p_reason text) → uuid`

- [ ] **Step 2.1: Escribir un helper de guarda + las RPCs**

Añadir al final de la migración. Patrón de guarda idéntico al de `generate_reassignment_proposals` (auth.uid() NULL → service-role permitido; no-superadmin → su cuenta):

```sql
-- Guarda cross-tenant reutilizable: lanza si el actor no puede tocar esa cuenta.
CREATE OR REPLACE FUNCTION public.assert_same_account(p_account_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_account_id IS NULL THEN RAISE EXCEPTION 'account not found'; END IF;
  IF auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND (SELECT account_id FROM profiles WHERE id = auth.uid()) IS DISTINCT FROM p_account_id THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;
END; $$;

-- Resolver / actualizar estado + respuesta al panelista.
CREATE OR REPLACE FUNCTION public.resolve_panelist_incident(
  p_incident_id uuid, p_status text,
  p_resolution_note text DEFAULT NULL, p_reply_text text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM panelist_incident WHERE id = p_incident_id;
  PERFORM assert_same_account(v_account);
  IF p_status NOT IN ('open','in_progress','resolved','dismissed') THEN
    RAISE EXCEPTION 'invalid status %', p_status; END IF;
  UPDATE panelist_incident SET
    status = p_status,
    resolution_note = COALESCE(p_resolution_note, resolution_note),
    reply_to_panelist = COALESCE(p_reply_text, reply_to_panelist),
    reply_status = CASE WHEN p_reply_text IS NOT NULL THEN 'pending_send' ELSE reply_status END,
    resolved_by = CASE WHEN p_status IN ('resolved','dismissed') THEN auth.uid() ELSE resolved_by END,
    resolved_at = CASE WHEN p_status IN ('resolved','dismissed') THEN now() ELSE resolved_at END,
    updated_at = now()
  WHERE id = p_incident_id;
END; $$;

-- Registrar recepción a mano (etiqueta ilegible / problema de foto).
CREATE OR REPLACE FUNCTION public.mark_detail_received_manual(p_detail_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM allocation_plan_details WHERE id = p_detail_id;
  PERFORM assert_same_account(v_account);
  UPDATE allocation_plan_details SET status = 'received', received_at = now(), updated_at = now()
  WHERE id = p_detail_id;
END; $$;

-- Invalidar muestra (paquete roto).
CREATE OR REPLACE FUNCTION public.invalidate_detail(p_detail_id uuid, p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM allocation_plan_details WHERE id = p_detail_id;
  PERFORM assert_same_account(v_account);
  UPDATE allocation_plan_details SET status = 'invalid', updated_at = now() WHERE id = p_detail_id;
END; $$;

-- Reprogramar fecha (devuelto al remitente).
CREATE OR REPLACE FUNCTION public.reschedule_detail(p_detail_id uuid, p_new_date date)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM allocation_plan_details WHERE id = p_detail_id;
  PERFORM assert_same_account(v_account);
  IF p_new_date IS NULL THEN RAISE EXCEPTION 'new date required'; END IF;
  UPDATE allocation_plan_details SET fecha_programada = p_new_date, updated_at = now() WHERE id = p_detail_id;
END; $$;

-- Cancelar muestra.
CREATE OR REPLACE FUNCTION public.cancel_detail(p_detail_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM allocation_plan_details WHERE id = p_detail_id;
  PERFORM assert_same_account(v_account);
  UPDATE allocation_plan_details SET status = 'cancelled', updated_at = now() WHERE id = p_detail_id;
END; $$;

-- Actualizar datos de contacto del panelista (solo los no-nulos).
CREATE OR REPLACE FUNCTION public.update_panelist_contact(
  p_panelist_id uuid, p_telegram_id text DEFAULT NULL,
  p_phone text DEFAULT NULL, p_language text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM panelists WHERE id = p_panelist_id;
  PERFORM assert_same_account(v_account);
  UPDATE panelists SET
    telegram_id = COALESCE(p_telegram_id, telegram_id),
    phone = COALESCE(p_phone, phone),
    language = COALESCE(p_language, language),
    updated_at = now()
  WHERE id = p_panelist_id;
END; $$;

-- Crear baja desde una incidencia (petición de baja) → el trigger genera propuestas.
CREATE OR REPLACE FUNCTION public.create_unavailability_from_incident(
  p_incident_id uuid, p_start date, p_end date, p_reason text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid; v_panelist uuid; v_new uuid;
BEGIN
  SELECT account_id, panelist_id INTO v_account, v_panelist
    FROM panelist_incident WHERE id = p_incident_id;
  PERFORM assert_same_account(v_account);
  IF p_start IS NULL OR p_end IS NULL OR p_end < p_start THEN
    RAISE EXCEPTION 'invalid date range'; END IF;
  INSERT INTO panelist_unavailability (account_id, panelist_id, start_date, end_date, reason, status)
  VALUES (v_account, v_panelist, p_start, p_end, p_reason, 'active')
  RETURNING id INTO v_new;  -- el trigger generate_proposals_on_unavailability_trigger dispara el motor
  UPDATE panelist_incident SET linked_unavailability_id = v_new, status = 'in_progress', updated_at = now()
  WHERE id = p_incident_id;
  RETURN v_new;
END; $$;

GRANT EXECUTE ON FUNCTION public.resolve_panelist_incident(uuid,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_detail_received_manual(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_detail(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reschedule_detail(uuid,date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_panelist_contact(uuid,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_unavailability_from_incident(uuid,date,date,text) TO authenticated;
```

Si en Step 1.1 algún nombre de columna resultó distinto (p. ej. el teléfono no es `phone`, o el estado cancelado no es `'cancelled'`), ajustar aquí en consecuencia y anotarlo.

- [ ] **Step 2.2: Validar en local**

Run: `pwsh supabase/tests/replay_baseline.ps1`
Expected: aplica sin error. Prueba mínima con datos del shim (o un panelista/detalle de prueba):

```sql
-- fija estado + genera respuesta pendiente
SELECT resolve_panelist_incident('<incident_uuid>','resolved','ok','Gracias, resuelto');
SELECT status, reply_status FROM panelist_incident WHERE id='<incident_uuid>'; -- resolved, pending_send
```
Expected: `status='resolved'`, `reply_status='pending_send'`.

- [ ] **Step 2.3: Commit**

```bash
git add supabase/migrations/<ts>_panelist_incident.sql
git commit -m "feat(incidents): RPCs de acción para incidencias reportadas (recepción manual, invalidar, reprogramar/cancelar, baja, contacto, resolver)"
```

---

## Task 3: Tipos + hook `useReportedIncidents`

**Files:**
- Modify: `src/lib/types.ts`
- Create: `src/lib/hooks/useReportedIncidents.ts`

**Interfaces:**
- Consumes: RPCs de Task 2; tabla de Task 1.
- Produces: `useReportedIncidents()` con `{ inbox, loading, error, openCount, fetchInbox, fetchIncident, resolve, actMarkReceived, actInvalidate, actReschedule, actCancel, actUpdateContact, actCreateUnavailability, signedPhotoUrl }`.

- [ ] **Step 3.1: Añadir tipos**

En `src/lib/types.ts`:

```typescript
export type ReportedIncidentCategory =
  | 'missing_materials' | 'unreadable_label_receipt' | 'parcel_damaged' | 'parcel_returned'
  | 'how_to_send' | 'unavailability_request' | 'tag_photo_problem' | 'contact_data_change' | 'other'

export type ReportedIncidentStatus = 'open' | 'in_progress' | 'resolved' | 'dismissed'

export interface ReportedIncident {
  id: string
  account_id: string
  panelist_id: string
  category: ReportedIncidentCategory
  status: ReportedIncidentStatus
  description: string | null
  photo_url: string | null
  allocation_plan_detail_id: string | null
  linked_unavailability_id: string | null
  payload: Record<string, any> | null
  resolution_note: string | null
  reply_to_panelist: string | null
  reply_status: 'none' | 'pending_send' | 'sent'
  reported_at: string
  // joins para la bandeja
  panelist_name?: string
  panelist_code?: string
}
```

- [ ] **Step 3.2: Escribir el hook**

`src/lib/hooks/useReportedIncidents.ts`, siguiendo `useReassignmentProposals` (todas las funciones en `useCallback`, filtro por `effectiveAccountId`):

```typescript
import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'
import type { ReportedIncident, ReportedIncidentStatus } from '@/lib/types'

export function useReportedIncidents() {
  const { effectiveAccountId } = useAccount()
  const [inbox, setInbox] = useState<ReportedIncident[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchInbox = useCallback(async () => {
    try {
      setLoading(true); setError(null)
      let q = supabase
        .from('panelist_incident')
        .select('*, panelist:panelists ( name, panelist_code )')
        .order('reported_at', { ascending: false })
      if (effectiveAccountId) q = q.eq('account_id', effectiveAccountId)
      const { data, error: e } = await q
      if (e) throw e
      setInbox((data || []).map((r: any) => ({
        ...r, panelist_name: r.panelist?.name ?? '-', panelist_code: r.panelist?.panelist_code ?? '-',
      })))
    } catch (err: any) { setError(err.message); console.error('fetchInbox reported', err) }
    finally { setLoading(false) }
  }, [effectiveAccountId])

  useEffect(() => { fetchInbox() }, [fetchInbox])

  const fetchIncident = useCallback(async (id: string): Promise<ReportedIncident | null> => {
    const { data, error: e } = await supabase
      .from('panelist_incident')
      .select('*, panelist:panelists ( name, panelist_code, telegram_id, phone, language ), detail:allocation_plan_details ( id, fecha_programada, status, origin_node_id, destination_node_id )')
      .eq('id', id).single()
    if (e) throw e
    return data as any
  }, [])

  const resolve = useCallback(async (id: string, status: ReportedIncidentStatus, note?: string, reply?: string) => {
    const { error: e } = await supabase.rpc('resolve_panelist_incident', {
      p_incident_id: id, p_status: status, p_resolution_note: note ?? null, p_reply_text: reply ?? null })
    if (e) throw e
  }, [])

  const actMarkReceived = useCallback(async (detailId: string) => {
    const { error: e } = await supabase.rpc('mark_detail_received_manual', { p_detail_id: detailId }); if (e) throw e }, [])
  const actInvalidate = useCallback(async (detailId: string, note?: string) => {
    const { error: e } = await supabase.rpc('invalidate_detail', { p_detail_id: detailId, p_note: note ?? null }); if (e) throw e }, [])
  const actReschedule = useCallback(async (detailId: string, newDate: string) => {
    const { error: e } = await supabase.rpc('reschedule_detail', { p_detail_id: detailId, p_new_date: newDate }); if (e) throw e }, [])
  const actCancel = useCallback(async (detailId: string) => {
    const { error: e } = await supabase.rpc('cancel_detail', { p_detail_id: detailId }); if (e) throw e }, [])
  const actUpdateContact = useCallback(async (panelistId: string, telegramId?: string, phone?: string, language?: string) => {
    const { error: e } = await supabase.rpc('update_panelist_contact', {
      p_panelist_id: panelistId, p_telegram_id: telegramId ?? null, p_phone: phone ?? null, p_language: language ?? null }); if (e) throw e }, [])
  const actCreateUnavailability = useCallback(async (incidentId: string, start: string, end: string, reason?: string) => {
    const { error: e } = await supabase.rpc('create_unavailability_from_incident', {
      p_incident_id: incidentId, p_start: start, p_end: end, p_reason: reason ?? null }); if (e) throw e }, [])

  const signedPhotoUrl = useCallback(async (path: string): Promise<string | null> => {
    const { data, error: e } = await supabase.storage.from('incident-photos').createSignedUrl(path, 3600)
    if (e) { console.error('signedPhotoUrl', e); return null }
    return data?.signedUrl ?? null
  }, [])

  const openCount = inbox.filter(r => r.status === 'open' || r.status === 'in_progress').length

  return { inbox, loading, error, openCount, fetchInbox, fetchIncident, resolve,
    actMarkReceived, actInvalidate, actReschedule, actCancel, actUpdateContact, actCreateUnavailability, signedPhotoUrl }
}
```

Nota: `photo_url` puede guardar la **ruta** dentro del bucket (para `createSignedUrl`) o una URL completa; el detalle (Task 5) usa `signedPhotoUrl` cuando parezca una ruta de bucket.

- [ ] **Step 3.3: Verificar compilación**

Run: `npm run build`
Expected: compila sin errores de tipos.

- [ ] **Step 3.4: Commit**

```bash
git add src/lib/types.ts src/lib/hooks/useReportedIncidents.ts
git commit -m "feat(incidents): tipos + hook useReportedIncidents"
```

---

## Task 4: Menú, ruta y bandeja

**Files:**
- Modify: `src/components/layout/Sidebar.tsx`
- Modify: `src/App.tsx`
- Create: `src/pages/incidents/PanelistReportedIncidents.tsx`

**Interfaces:**
- Consumes: `useReportedIncidents` (Task 3), claves i18n `reported_incidents.*` (Task 6).

- [ ] **Step 4.1: Entrada de menú encima de "Disponibilidad de panelistas"**

En `src/components/layout/Sidebar.tsx`, grupo `t('incidents.menu_group')` (items alrededor de la línea 346): **insertar la nueva entrada ANTES** de la de `panelist-availability`:

```tsx
{
  path: '/incidents/panelist-reported',
  label: t('reported_incidents.menu'),
  icon: MessageSquareWarning, // importar de lucide-react; si no existe, usar Inbox
  roles: ['admin', 'superadmin'],
  tooltip: t('reported_incidents.badge_tooltip'),
},
{
  path: '/incidents/panelist-availability',
  // ...existente sin cambios...
},
```

Importar el icono nuevo en el bloque de imports de `lucide-react` (líneas 6-38). Añadir el badge propio junto al de disponibilidad (línea ~593): traer `openCount` del nuevo hook y renderizar:

```tsx
const { pendingCount } = useReassignmentProposals()
const { openCount } = useReportedIncidents()
// ...
{item.path === '/incidents/panelist-reported' && openCount > 0 && isExpanded && (
  <span className="ml-auto text-xs bg-red-100 text-red-700 px-2 py-0.5 rounded-full font-medium">{openCount}</span>
)}
```

- [ ] **Step 4.2: Ruta protegida en App.tsx**

En `src/App.tsx`: importar la página (junto a la línea 54) y añadir la ruta junto a la de `/incidents/panelist-availability` (línea ~484), calcando el `ProtectedRoute allowedRoles={['superadmin','admin']}`:

```tsx
import { PanelistReportedIncidents } from './pages/incidents/PanelistReportedIncidents'
// ...
<Route
  path="/incidents/panelist-reported"
  element={
    <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
      <PanelistReportedIncidents />
    </ProtectedRoute>
  }
/>
```

- [ ] **Step 4.3: Página de bandeja**

`src/pages/incidents/PanelistReportedIncidents.tsx`, calcando `PanelistAvailabilityIncidents` (lista → detalle con estado `selected`), con filtros por categoría y estado:

```tsx
import { useState, useMemo } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { useReportedIncidents } from '@/lib/hooks/useReportedIncidents'
import { ReportedIncidentPanel } from '@/components/incidents/ReportedIncidentPanel'
import type { ReportedIncidentCategory, ReportedIncidentStatus } from '@/lib/types'

const CATEGORIES: ReportedIncidentCategory[] = [
  'missing_materials','unreadable_label_receipt','parcel_damaged','parcel_returned',
  'how_to_send','unavailability_request','tag_photo_problem','contact_data_change','other']

export function PanelistReportedIncidents() {
  const { t } = useTranslation()
  const { inbox, loading, error, fetchInbox } = useReportedIncidents()
  const [selected, setSelected] = useState<string | null>(null)
  const [catFilter, setCatFilter] = useState<ReportedIncidentCategory | 'all'>('all')
  const [statusFilter, setStatusFilter] = useState<ReportedIncidentStatus | 'open_active'>('open_active')

  const rows = useMemo(() => inbox.filter(r =>
    (catFilter === 'all' || r.category === catFilter) &&
    (statusFilter === 'open_active' ? (r.status === 'open' || r.status === 'in_progress') : r.status === statusFilter)
  ), [inbox, catFilter, statusFilter])

  if (loading) return <div className="p-6">{t('common.loading')}</div>
  if (error) return <div className="p-6 text-red-600">{t('common.error')}: {error}</div>
  if (selected) return (
    <div className="p-6">
      <ReportedIncidentPanel incidentId={selected} onBack={() => { setSelected(null); fetchInbox() }} />
    </div>
  )

  return (
    <div className="p-6">
      <h2 className="text-xl font-bold mb-4">{t('reported_incidents.title')}</h2>
      <div className="flex gap-3 mb-4">
        <select className="border rounded px-2 py-1 text-sm" value={catFilter} onChange={e => setCatFilter(e.target.value as any)}>
          <option value="all">{t('reported_incidents.filter.all_categories')}</option>
          {CATEGORIES.map(c => <option key={c} value={c}>{t(`reported_incidents.category.${c}`)}</option>)}
        </select>
        <select className="border rounded px-2 py-1 text-sm" value={statusFilter} onChange={e => setStatusFilter(e.target.value as any)}>
          <option value="open_active">{t('reported_incidents.filter.open_active')}</option>
          <option value="resolved">{t('reported_incidents.status.resolved')}</option>
          <option value="dismissed">{t('reported_incidents.status.dismissed')}</option>
        </select>
      </div>
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('reported_incidents.col.panelist')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('reported_incidents.col.category')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('reported_incidents.col.status')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('reported_incidents.col.reported_at')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {rows.length > 0 ? rows.map(r => (
                <tr key={r.id} className="hover:bg-gray-50">
                  <td className="px-6 py-4 text-sm"><div className="font-medium">{r.panelist_name}</div><div className="text-gray-500 text-xs font-mono">{r.panelist_code}</div></td>
                  <td className="px-6 py-4 text-sm">{t(`reported_incidents.category.${r.category}`)}</td>
                  <td className="px-6 py-4 text-sm">{t(`reported_incidents.status.${r.status}`)}</td>
                  <td className="px-6 py-4 text-sm">{r.reported_at?.slice(0,10)}</td>
                  <td className="px-6 py-4 text-sm"><button onClick={() => setSelected(r.id)} className="text-blue-600 hover:text-blue-800">{t('reported_incidents.open')}</button></td>
                </tr>
              )) : (
                <tr><td colSpan={5} className="px-6 py-4 text-center text-gray-500">{t('reported_incidents.empty')}</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
```

- [ ] **Step 4.4: Verificar build**

Run: `npm run build` && `npm run lint`
Expected: pasan. La ruta `/incidents/panelist-reported` carga la bandeja vacía sin error.

- [ ] **Step 4.5: Commit**

```bash
git add src/components/layout/Sidebar.tsx src/App.tsx src/pages/incidents/PanelistReportedIncidents.tsx
git commit -m "feat(incidents): menú + ruta + bandeja de incidencias reportadas"
```

---

## Task 5: Detalle con acciones por categoría

**Files:**
- Create: `src/components/incidents/ReportedIncidentPanel.tsx`

**Interfaces:**
- Consumes: `useReportedIncidents` (Task 3), claves i18n (Task 6).

- [ ] **Step 5.1: Componente de detalle**

Estructura: carga la incidencia con `fetchIncident`; cabecera (panelista + envío señalado si `allocation_plan_detail_id` + foto vía `signedPhotoUrl`); **bloque de acción según `category`** (el "playbook"); zona **Resolver** (nota interna + respuesta al panelista → `resolve(id,'resolved',note,reply)`). Cada acción real deja la incidencia en `in_progress` (la RPC de acción no cambia el estado de la incidencia salvo `create_unavailability_from_incident`; el resto lo marca la UI llamando `resolve(id,'in_progress',...)` tras la acción, o el manager pulsa Resolver directamente).

```tsx
import { useEffect, useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { useReportedIncidents } from '@/lib/hooks/useReportedIncidents'
import type { ReportedIncident } from '@/lib/types'

export function ReportedIncidentPanel({ incidentId, onBack }: { incidentId: string; onBack: () => void }) {
  const { t } = useTranslation()
  const { fetchIncident, resolve, actMarkReceived, actInvalidate, actReschedule, actCancel,
          actUpdateContact, actCreateUnavailability, signedPhotoUrl } = useReportedIncidents()
  const [inc, setInc] = useState<ReportedIncident | null>(null)
  const [photo, setPhoto] = useState<string | null>(null)
  const [note, setNote] = useState('')
  const [reply, setReply] = useState('')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)

  const load = async () => { const d = await fetchIncident(incidentId); setInc(d) }
  useEffect(() => { load() }, [incidentId])
  useEffect(() => {
    const p = (inc as any)?.photo_url
    if (p && !/^https?:\/\//.test(p)) signedPhotoUrl(p).then(setPhoto)
    else setPhoto(p ?? null)
  }, [inc, signedPhotoUrl])

  const run = async (fn: () => Promise<void>, okKey: string) => {
    setBusy(true); setMsg(null)
    try { await fn(); await resolve(incidentId, 'in_progress'); await load(); setMsg(t(okKey)) }
    catch (e: any) { setMsg(t('common.error') + ': ' + e.message) }
    finally { setBusy(false) }
  }

  const doResolve = async (status: 'resolved' | 'dismissed') => {
    setBusy(true); setMsg(null)
    try { await resolve(incidentId, status, note || undefined, reply || undefined); onBack() }
    catch (e: any) { setMsg(t('common.error') + ': ' + e.message); setBusy(false) }
  }

  if (!inc) return <div>{t('common.loading')}</div>
  const detailId = inc.allocation_plan_detail_id

  return (
    <div className="max-w-3xl">
      <button onClick={onBack} className="text-blue-600 mb-4">← {t('reported_incidents.back')}</button>
      <h3 className="text-lg font-bold mb-2">{t(`reported_incidents.category.${inc.category}`)}</h3>
      <div className="text-sm text-gray-600 mb-4">
        <div>{inc.panelist_name} · <span className="font-mono">{inc.panelist_code}</span></div>
        {detailId && <div>{t('reported_incidents.linked_shipment')}: <span className="font-mono">{detailId.slice(0,8)}</span></div>}
      </div>
      {inc.description && <p className="bg-gray-50 rounded p-3 text-sm mb-3">{inc.description}</p>}
      {photo && <img src={photo} alt="" className="max-w-xs rounded border mb-3" />}

      {/* ── Bloque de acción por categoría (playbook) ── */}
      <div className="border rounded p-4 mb-4">
        {inc.category === 'unreadable_label_receipt' || inc.category === 'tag_photo_problem' ? (
          <button disabled={busy || !detailId} className="btn-primary"
            onClick={() => run(() => actMarkReceived(detailId!), 'reported_incidents.done.received')}>
            {t('reported_incidents.action.mark_received')}
          </button>
        ) : inc.category === 'parcel_damaged' ? (
          <button disabled={busy || !detailId} className="btn-primary"
            onClick={() => run(() => actInvalidate(detailId!, note), 'reported_incidents.done.invalidated')}>
            {t('reported_incidents.action.invalidate')}
          </button>
        ) : inc.category === 'parcel_returned' || inc.category === 'missing_materials' ? (
          <ReturnedOrMaterialsActions busy={busy} hasDetail={!!detailId}
            onReschedule={(d) => run(() => actReschedule(detailId!, d), 'reported_incidents.done.rescheduled')}
            onCancel={() => run(() => actCancel(detailId!), 'reported_incidents.done.cancelled')} t={t} />
        ) : inc.category === 'unavailability_request' ? (
          <UnavailabilityAction busy={busy}
            onCreate={(s,e,r) => run(() => actCreateUnavailability(incidentId, s, e, r), 'reported_incidents.done.baja')} t={t} />
        ) : inc.category === 'contact_data_change' ? (
          <ContactAction busy={busy} payload={inc.payload}
            onApply={(tg,ph,lang) => run(() => actUpdateContact(inc.panelist_id, tg, ph, lang), 'reported_incidents.done.contact')} t={t} />
        ) : (
          <p className="text-sm text-gray-500">{t('reported_incidents.action.support_only')}</p>
        )}
        {msg && <p className="text-sm mt-2">{msg}</p>}
      </div>

      {/* ── Resolver + respuesta al panelista ── */}
      <div className="border rounded p-4">
        <label className="block text-sm font-medium mb-1">{t('reported_incidents.resolution_note')}</label>
        <textarea className="w-full border rounded p-2 text-sm mb-3" rows={2} value={note} onChange={e => setNote(e.target.value)} />
        <label className="block text-sm font-medium mb-1">{t('reported_incidents.reply_to_panelist')}</label>
        <textarea className="w-full border rounded p-2 text-sm mb-3" rows={2} value={reply} onChange={e => setReply(e.target.value)} />
        <div className="flex gap-2">
          <button disabled={busy} className="btn-primary" onClick={() => doResolve('resolved')}>{t('reported_incidents.resolve')}</button>
          <button disabled={busy} className="btn-secondary" onClick={() => doResolve('dismissed')}>{t('reported_incidents.dismiss')}</button>
        </div>
      </div>
    </div>
  )
}
```

Definir en el mismo fichero los sub-componentes `ReturnedOrMaterialsActions` (input de fecha + botón reprogramar + botón cancelar), `UnavailabilityAction` (dos inputs date + reason + botón) y `ContactAction` (muestra `payload` con los nuevos datos y campos editables telegram/phone/language + botón aplicar). Usar clases Tailwind del proyecto; si `btn-primary`/`btn-secondary` no son clases globales, sustituir por las utilidades usadas en `ProposalReviewPanel.tsx` (revisarlo como referencia de estilo de botones).

- [ ] **Step 5.2: Verificar build + lint**

Run: `npm run build` && `npm run lint`
Expected: pasan (0 warnings permitidos según `--max-warnings`). Revisar que no queda texto hardcodeado sin `t()`.

- [ ] **Step 5.3: Commit**

```bash
git add src/components/incidents/ReportedIncidentPanel.tsx
git commit -m "feat(incidents): detalle con acciones guiadas por categoría + resolver/responder"
```

---

## Task 6: i18n — claves `reported_incidents.*` en los 4 CSV

**Files:**
- Modify: `public/locales/en.csv`, `es.csv`, `fr.csv`, `ar.csv`

**Interfaces:**
- Consumes: nada. Produces: las claves que usan Tasks 4 y 5.

- [ ] **Step 6.1: Añadir el bloque de claves a los 4 ficheros**

Mismas claves en los 4; traducir el valor. Claves (valor ES de ejemplo):

```
reported_incidents.menu,Incidencias reportadas
reported_incidents.title,Incidencias reportadas por panelistas
reported_incidents.badge_tooltip,Incidencias abiertas por atender
reported_incidents.open,Abrir
reported_incidents.back,Volver a la lista
reported_incidents.empty,No hay incidencias
reported_incidents.linked_shipment,Envío señalado
reported_incidents.resolution_note,Nota de resolución (interna)
reported_incidents.reply_to_panelist,Respuesta al panelista
reported_incidents.resolve,Resolver
reported_incidents.dismiss,Descartar
reported_incidents.col.panelist,Panelista
reported_incidents.col.category,Categoría
reported_incidents.col.status,Estado
reported_incidents.col.reported_at,Fecha
reported_incidents.filter.all_categories,Todas las categorías
reported_incidents.filter.open_active,Abiertas / en curso
reported_incidents.status.open,Abierta
reported_incidents.status.in_progress,En curso
reported_incidents.status.resolved,Resuelta
reported_incidents.status.dismissed,Descartada
reported_incidents.category.missing_materials,Falta de materiales
reported_incidents.category.unreadable_label_receipt,Etiqueta ilegible (recepción)
reported_incidents.category.parcel_damaged,Envío roto o golpeado
reported_incidents.category.parcel_returned,Envío devuelto al remitente
reported_incidents.category.how_to_send,No sé cómo hacer el envío
reported_incidents.category.unavailability_request,Petición de baja
reported_incidents.category.tag_photo_problem,Problema con la foto del tag
reported_incidents.category.contact_data_change,Cambio de datos de contacto
reported_incidents.category.other,Otros
reported_incidents.action.mark_received,Registrar recepción manual
reported_incidents.action.invalidate,Invalidar muestra
reported_incidents.action.reschedule,Reprogramar
reported_incidents.action.cancel,Cancelar envío
reported_incidents.action.create_baja,Crear baja
reported_incidents.action.apply_contact,Aplicar cambios de contacto
reported_incidents.action.support_only,Esta incidencia se resuelve respondiendo al panelista.
reported_incidents.field.new_date,Nueva fecha
reported_incidents.field.start,Inicio
reported_incidents.field.end,Fin
reported_incidents.field.reason,Motivo
reported_incidents.field.telegram,Telegram
reported_incidents.field.phone,Teléfono
reported_incidents.field.language,Idioma
reported_incidents.done.received,Recepción registrada
reported_incidents.done.invalidated,Muestra invalidada
reported_incidents.done.rescheduled,Envío reprogramado
reported_incidents.done.cancelled,Envío cancelado
reported_incidents.done.baja,Baja creada
reported_incidents.done.contact,Datos actualizados
```

EN: traducción real. FR/AR: autogeneradas (repaso nativo pendiente antes de prod — nota conocida del proyecto). Verificar que cada fichero mantiene su cabecera/formato `key,translation` y no hay comas sin escapar en los valores (envolver en comillas si el valor lleva coma).

- [ ] **Step 6.2: Verificar que no falta ninguna clave usada**

Run: `npm run build` y cargar la pantalla en `npm run dev`, cambiando idioma. Expected: sin claves crudas (`reported_incidents.xxx`) visibles.

- [ ] **Step 6.3: Commit**

```bash
git add public/locales/en.csv public/locales/es.csv public/locales/fr.csv public/locales/ar.csv
git commit -m "i18n(incidents): claves reported_incidents.* en los 4 idiomas"
```

---

## Task 7: Documento de contrato para n8n

**Files:**
- Create: `docs/integrations/2026-08-06-n8n-incidencias-reportadas.md`

- [ ] **Step 7.1: Escribir el contrato**

Calcar la estructura del doc de subsistema C (`docs/integrations/2026-08-05-n8n-telegram-subsistema-c.md`). Debe incluir:

- **Base:** `onems-dev` / `sehbnpgzqljrsqimwyuz`; regla multi-tenant (service-role salta RLS → filtrar/derivar `account_id`); nunca escribir el plan a mano (usar RPCs).
- **INSERT de alta** desde Telegram en `panelist_incident`: columnas que rellena n8n — `account_id` (derivado del panelista), `panelist_id`, `category` (uno de los 9 códigos, listarlos), `description`, `photo_url` (ruta en el bucket `incident-photos` tras subir la foto), `allocation_plan_detail_id` (el envío que el panelista señala), `payload` (esquema mínimo por categoría, ver abajo).
- **Esquema de `payload` por categoría:** `contact_data_change` → `{telegram_id?, phone?, language?}`; `missing_materials` → `{materials?: [{name, quantity}]}`; resto → libre/omitible.
- **Subida de foto:** al bucket privado `incident-photos` con service-role; guardar la **ruta** (no URL pública) en `photo_url`; la app del manager genera signed URLs.
- **Canal de vuelta:** `SELECT id, panelist_id, reply_to_panelist FROM panelist_incident WHERE reply_status='pending_send' AND account_id=<ACCOUNT>`; enviar por Telegram en el `language` del panelista; luego `UPDATE panelist_incident SET reply_status='sent', reply_sent_at=now() WHERE id=<id>`.
- **Nota:** la bandeja del manager no es tiempo real (F5 tras alta).
- **Seguridad:** sacar la API key de n8n de los docs a un secreto (recordatorio de la decisión §1.b del spec).

- [ ] **Step 7.2: Commit**

```bash
git add docs/integrations/2026-08-06-n8n-incidencias-reportadas.md
git commit -m "docs(incidents): contrato n8n/Telegram para incidencias reportadas"
```

---

## Cierre

- Backend (Tasks 1-2): validado en local; **desplegar por SQL Editor web** con confirmación explícita de proyecto+ref (`onems-dev`/`sehbnpgzqljrsqimwyuz`), como el resto del proyecto. Registrar versión en `supabase_migrations.schema_migrations` si se aplica por web.
- Bucket `incident-photos`: si no se crea vía migración (schema `storage`), crearlo por dashboard.
- Frontend (Tasks 3-6): `npm run lint` + `npm run build` verdes.
- Contrato (Task 7): entregar a quien monte n8n en el otro entorno.
- Push a `develop` solo si el usuario lo pide.

## Self-review (hecho)

- **Cobertura del spec:** las 9 categorías → Task 5 (acción) + Task 6 (i18n); tabla → Task 1; RPCs (§4) → Task 2; pantalla/menú (§5) → Tasks 4-5; canal de vuelta (§6) → columnas Task 1 + `resolve` Task 3 + contrato Task 7; contrato (§7) → Task 7; decisiones §9 → RPC in-line (Task 2 `reschedule/cancel`), resolver explícito (Task 5 `doResolve`), payload documentado (Task 7), fotos en Storage (Task 1 bucket + Task 3 `signedPhotoUrl`).
- **Consistencia de tipos:** firmas de RPC en Task 2 == llamadas del hook en Task 3 == uso en Task 5. `openCount` (hook) == badge (Sidebar Task 4).
- **Sin placeholders:** todo el código va escrito; los únicos puntos "a confirmar" son nombres reales de columnas (Step 1.1) y clases de botón (Step 5.1), con instrucción explícita de verificarlos contra el repo — no son huecos, son validaciones.
