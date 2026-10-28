# Tratamiento "Falta de materiales" — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convertir la categoría de incidencia `missing_materials` en un procedimiento guiado que reconcilia stock, recalcula necesidad real (restando material en tránsito), suministra por cascada (central → excedente donante cercano → compra manual), desplaza al panelista entero vía el motor de baja existente, y cierra la baja cuando el panelista confirma recepción.

**Architecture:** Reutiliza el módulo de Stock cableado (`useStockManagement`, `materialCalculator`) y el motor de baja/reasignación (subsistemas B/C, **sin cambios**). Se añade un **ciclo de recepción real** a los envíos de material (`pending → sent → received`), que arregla un bug existente (hoy se acredita stock al enviar y se borra el envío). Las operaciones de stock que cruzan cuenta o que llama n8n pasan por **RPCs `SECURITY DEFINER`** con guarda `assert_same_account`. El tratamiento se orquesta desde el panel de la incidencia (`ReportedIncidentPanel`) mediante un hook nuevo `useMaterialsTreatment`.

**Tech Stack:** React 18 + TypeScript + Vite + Tailwind; Supabase Postgres (migraciones forward-only); i18n por CSV (`public/locales/{en,es,fr,ar}.csv`).

## Global Constraints

- **Base de datos única:** onems-dev, project-ref **`sehbnpgzqljrsqimwyuz`** (org "ONE for Regulators MS"). Antes de aplicar CUALQUIER migración/RPC hay que **nombrar proyecto+ref y pedir confirmación explícita al usuario**; el usuario aplica las escrituras. Nunca inferir la base, nunca `db reset`/`db push`.
- **Migraciones forward-only:** cada cambio es UN fichero nuevo `supabase/migrations/YYYYMMDDHHMMSS_*.sql` posterior al baseline `00000000000000_baseline_prod_schema.sql`. **No tocar el baseline** ni el archivo `migrations_archive_pre_baseline/`.
- **Multi-tenant RLS por `account_id`:** ninguna consulta/política puede exponer datos entre cuentas. RPCs `SECURITY DEFINER` deben llamar `assert_same_account(...)`. `auth.uid()` NULL = service-role (n8n) permitido; no-superadmin = solo su cuenta.
- **i18n:** todo texto visible pasa por `t()`; cada clave nueva se añade a los **4** ficheros CSV con el **mismo conjunto de claves byte-idéntico** (formato `key,translation`, interpolación `{var}`).
- **Puerta de calidad:** no hay tests de frontend automatizados. `npm run lint` (presupuesto `--max-warnings 48`, 0 errores) y `npm run build` (tsc+vite) deben pasar. Para SQL, validar con el replay local (`supabase/tests/replay_baseline.ps1`) antes de proponer aplicar a dev.
- **Reutilizar sin modificar:** el motor de reasignación (`generate_reassignment_proposals`, `apply_reassignment_proposal`, `list_reroute_candidates`) y la pantalla del subsistema C (`ProposalReviewPanel`, `useReassignmentProposals`) se usan **tal cual**. La decisión por muestra la da esa pantalla.
- **Rama:** trabajar en la rama de la feature (`feat/incidencias-reportadas` o worktree derivado). No commitear/pushear salvo petición.

---

## Mapa de ficheros

**Migraciones (crear):**
- `supabase/migrations/20260807100000_materials_treatment_schema.sql` — columnas nuevas + constraints.
- `supabase/migrations/20260807100100_material_shipment_lifecycle_rpcs.sql` — RPCs `send_material_shipment`, `receive_material_shipment`.
- `supabase/migrations/20260807100200_materials_treatment_close.sql` — extiende `receive_material_shipment` para cerrar baja + resolver incidencia; RPC `find_surplus_donors`.
- `supabase/migrations/20260807100300_stock_rls.sql` — activar RLS + políticas por `account_id` en tablas de stock.

**Frontend (modificar):**
- `src/hooks/useStockManagement.ts` — ciclo de recepción vía RPC; eliminar borrado-al-enviar y bugs de columna.
- `src/lib/materialCalculator.ts` — restar material en tránsito en ambos calculadores.
- `src/components/incidents/ReportedIncidentPanel.tsx` — bloque guiado para `missing_materials`.
- `src/components/stock/*` — toggle `is_blocking` en el catálogo de materiales.
- `public/locales/{en,es,fr,ar}.csv` — claves nuevas.

**Frontend (crear):**
- `src/lib/hooks/useMaterialsTreatment.ts` — orquestación del procedimiento.

**Docs (crear):**
- `docs/integrations/2026-08-07-n8n-recepcion-material.md` — contrato bidireccional de recepción.

---

## Fase 1 — Cimientos de stock

### Task 1: Migración de esquema (flags + ciclo de envío)

**Files:**
- Create: `supabase/migrations/20260807100000_materials_treatment_schema.sql`

**Interfaces:**
- Produces: columna `material_catalog.is_blocking boolean`; valor `'materials'` en el CHECK de `panelist_unavailability.reason`; columna `material_shipments.source_panelist_id uuid`; CHECK de `material_shipments.status` en (`pending`,`sent`,`received`,`cancelled`); columna `panelist_incident.linked_material_shipment_id uuid`.

- [ ] **Step 1: Escribir la migración**

```sql
-- 20260807100000_materials_treatment_schema.sql
-- Cimientos del tratamiento "falta de materiales": flag bloqueante,
-- razon de baja por materiales, ciclo de recepcion de envios, enlace incidencia<->envio.

begin;

-- 1) Flag de material bloqueante de envio (la etiqueta RFID se marca true).
alter table public.material_catalog
  add column if not exists is_blocking boolean not null default false;

-- 2) Razon nueva 'materials' para la baja generada por falta de material.
alter table public.panelist_unavailability
  drop constraint if exists panelist_unavailability_reason_check;
alter table public.panelist_unavailability
  add constraint panelist_unavailability_reason_check
  check (reason in ('vacation','sick_leave','personal','training','other','materials'));

-- 3) Origen del envio: NULL = almacen central del regulador; si no, panelista donante.
alter table public.material_shipments
  add column if not exists source_panelist_id uuid references public.panelists(id);

-- 4) Ciclo de estado real del envio. Normalizar legados antes de imponer el CHECK.
update public.material_shipments set status = 'received'  where status = 'delivered';
update public.material_shipments set status = 'pending'   where status is null;
-- Cualquier estado fuera del ciclo se lleva a 'pending' para no romper el CHECK.
update public.material_shipments
  set status = 'pending'
  where status not in ('pending','sent','received','cancelled');
alter table public.material_shipments
  drop constraint if exists material_shipments_status_check;
alter table public.material_shipments
  add constraint material_shipments_status_check
  check (status in ('pending','sent','received','cancelled'));

-- 5) Enlace directo incidencia -> envio de material generado por su tratamiento.
alter table public.panelist_incident
  add column if not exists linked_material_shipment_id uuid references public.material_shipments(id);

commit;
```

- [ ] **Step 2: Validar en el Postgres local (sin tocar dev)**

Run: `powershell -File supabase/tests/replay_baseline.ps1`
Expected: aplica baseline + todas las migraciones incluida la nueva sin error. Si el script no cubre las migraciones nuevas automáticamente, aplicar el fichero a mano contra `127.0.0.1:5433` y verificar:

```sql
select column_name from information_schema.columns
 where table_name='material_shipments' and column_name='source_panelist_id';
-- Expected: 1 fila.
select pg_get_constraintdef(oid) from pg_constraint
 where conname='panelist_unavailability_reason_check';
-- Expected: incluye 'materials'.
```

- [ ] **Step 3: Confirmar con el usuario y aplicar a dev**

Presentar al usuario: proyecto **onems-dev / `sehbnpgzqljrsqimwyuz`**, esta migración, y pedir confirmación explícita. Solo tras el "sí", aplicar vía `apply_migration` (MCP) o SQL Editor. No aplicar sin confirmación.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260807100000_materials_treatment_schema.sql
git commit -m "feat(stock): esquema base tratamiento falta de material (is_blocking, reason materials, ciclo envio, enlace incidencia)"
```

---

### Task 2: RPCs de ciclo de vida del envío (enviar / recibir)

**Files:**
- Create: `supabase/migrations/20260807100100_material_shipment_lifecycle_rpcs.sql`

**Interfaces:**
- Consumes: `assert_same_account(uuid)` (existe, del baseline de incidencias); tablas `material_shipments`, `material_shipment_items`, `material_stocks`, `panelist_material_stocks`, `material_movements`.
- Produces: `send_material_shipment(p_shipment_id uuid) RETURNS void`; `receive_material_shipment(p_shipment_id uuid) RETURNS void` (versión base; se extiende en Task 8).

- [ ] **Step 1: Escribir la migración**

Reglas: `send` descuenta el **origen** (central si `source_panelist_id IS NULL`, si no el donante) y marca `sent`, **sin acreditar al receptor**. `receive` acredita al receptor, marca `received`, fija `received_date` y `quantity_received`. Ambas idempotentes por estado.

```sql
-- 20260807100100_material_shipment_lifecycle_rpcs.sql
begin;

create or replace function public.send_material_shipment(p_shipment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ship   public.material_shipments%rowtype;
  v_item   record;
begin
  select * into v_ship from public.material_shipments where id = p_shipment_id;
  if not found then raise exception 'shipment % not found', p_shipment_id; end if;
  perform public.assert_same_account(v_ship.account_id);

  if v_ship.status <> 'pending' then
    return; -- idempotente: ya enviado/recibido/cancelado
  end if;

  for v_item in
    select material_id, quantity_sent
      from public.material_shipment_items
     where material_shipment_id = p_shipment_id
  loop
    if v_ship.source_panelist_id is null then
      -- Origen: almacen central del regulador.
      update public.material_stocks
         set quantity = greatest(0, quantity - v_item.quantity_sent),
             last_updated = now()
       where account_id = v_ship.account_id
         and material_id = v_item.material_id;
    else
      -- Origen: panelista donante.
      update public.panelist_material_stocks
         set quantity = greatest(0, quantity - v_item.quantity_sent),
             last_updated = now()
       where account_id = v_ship.account_id
         and panelist_id = v_ship.source_panelist_id
         and material_id = v_item.material_id;
    end if;

    insert into public.material_movements
      (account_id, material_id, movement_type, quantity, reference_id, notes, created_by)
    values
      (v_ship.account_id, v_item.material_id, 'dispatch', v_item.quantity_sent,
       p_shipment_id,
       case when v_ship.source_panelist_id is null
            then 'Dispatch central -> panelista'
            else 'Dispatch donante -> panelista' end,
       auth.uid());
  end loop;

  update public.material_shipments
     set status = 'sent', shipment_date = coalesce(shipment_date, now())
   where id = p_shipment_id;
end;
$$;

create or replace function public.receive_material_shipment(p_shipment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ship public.material_shipments%rowtype;
  v_item record;
begin
  select * into v_ship from public.material_shipments where id = p_shipment_id;
  if not found then raise exception 'shipment % not found', p_shipment_id; end if;
  perform public.assert_same_account(v_ship.account_id);

  if v_ship.status = 'received' then return; end if;         -- idempotente
  if v_ship.status not in ('pending','sent') then
    raise exception 'shipment % in status % cannot be received', p_shipment_id, v_ship.status;
  end if;

  for v_item in
    select id, material_id, quantity_sent
      from public.material_shipment_items
     where material_shipment_id = p_shipment_id
  loop
    insert into public.panelist_material_stocks
      (account_id, panelist_id, material_id, quantity, last_updated)
    values
      (v_ship.account_id, v_ship.panelist_id, v_item.material_id, v_item.quantity_sent, now())
    on conflict (account_id, panelist_id, material_id)
    do update set quantity = public.panelist_material_stocks.quantity + excluded.quantity,
                  last_updated = now();

    update public.material_shipment_items
       set quantity_received = v_item.quantity_sent, updated_at = now()
     where id = v_item.id;

    insert into public.material_movements
      (account_id, material_id, movement_type, quantity, reference_id, notes, created_by)
    values
      (v_ship.account_id, v_item.material_id, 'receipt', v_item.quantity_sent,
       p_shipment_id, 'Recepcion confirmada por panelista', auth.uid());
  end loop;

  update public.material_shipments
     set status = 'received', received_date = now()
   where id = p_shipment_id;
end;
$$;

grant execute on function public.send_material_shipment(uuid)    to authenticated, service_role;
grant execute on function public.receive_material_shipment(uuid) to authenticated, service_role;

commit;
```

- [ ] **Step 2: Validar en local**

Aplicar contra `127.0.0.1:5433`. Sembrar un envío `pending` con 1 item, ejecutar `send_material_shipment` y comprobar: `status='sent'`, stock de origen decrementado, stock del receptor **sin cambios**, movimiento `dispatch` creado. Luego `receive_material_shipment` → `status='received'`, `received_date` no nulo, stock del receptor incrementado, movimiento `receipt`.

- [ ] **Step 3: Confirmar proyecto+ref con el usuario y aplicar a dev.**

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260807100100_material_shipment_lifecycle_rpcs.sql
git commit -m "feat(stock): RPCs send/receive con ciclo de recepcion real (credito al recibir, no al enviar)"
```

---

### Task 3: Refactor de `useStockManagement` al ciclo de recepción

**Files:**
- Modify: `src/hooks/useStockManagement.ts`

**Interfaces:**
- Consumes: RPCs `send_material_shipment`, `receive_material_shipment` (Task 2).
- Produces: `markShipmentSent(shipmentId)`, `markShipmentReceived(shipmentId)` en el objeto devuelto por el hook; `updateShipmentStatus`/`confirmShipment` dejan de borrar y de acreditar al enviar.

- [ ] **Step 1: Añadir `markShipmentSent` y `markShipmentReceived` que delegan en las RPCs**

Sustituir el crédito+borrado inline por llamadas a RPC (fuente única de verdad server-side, reutilizable por n8n):

```ts
const markShipmentSent = async (shipmentId: string) => {
  const { error } = await supabase.rpc('send_material_shipment', { p_shipment_id: shipmentId })
  if (error) throw error
  await loadData()
}

const markShipmentReceived = async (shipmentId: string) => {
  const { error } = await supabase.rpc('receive_material_shipment', { p_shipment_id: shipmentId })
  if (error) throw error
  await loadData()
}
```

- [ ] **Step 2: Eliminar el borrado-al-enviar y el crédito-al-enviar**

En `updateShipmentStatus`: eliminar todo el bloque `if (status === 'sent' && shipment.items) { ... }` (líneas ~424-509, que decrementa/acredita y **borra** el envío). Dejar que esa función solo actualice `status`/fechas simples, o marcarla como deprecada delegando en `markShipmentSent`/`markShipmentReceived`. En `confirmShipment`: eliminar la acreditación inline y los `delete` finales; si se conserva la lógica de "items retirados → nuevo envío pendiente", corregir el bug de columna (ver Step 3).

- [ ] **Step 3: Corregir los bugs de columna `shipment_id` → `material_shipment_id`**

Líneas `useStockManagement.ts:503` (`.delete().eq('shipment_id', shipmentId)`) y `:686-689` (insert con `shipment_id: newShipment.id`) y `:752` (`deleteShipment` usa `.eq('shipment_id', ...)`). La columna real es `material_shipment_id`. Corregir las tres. (Si el borrado desaparece con el Step 2, verificar que `deleteShipment` sigue usando `material_shipment_id`.)

- [ ] **Step 4: Exportar las nuevas funciones**

Añadir `markShipmentSent, markShipmentReceived` al `return { ... }` del hook.

- [ ] **Step 5: Verificar lint + build**

Run: `npm run lint` — Expected: 0 errores, ≤48 warnings.
Run: `npm run build` — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/hooks/useStockManagement.ts
git commit -m "fix(stock): recepcion real via RPC; elimina borrado-al-enviar y bug shipment_id"
```

---

### Task 4: Restar material en tránsito en los calculadores de necesidad

**Files:**
- Modify: `src/lib/materialCalculator.ts`

**Interfaces:**
- Produces: `calculateMaterialRequirements` y `calculatePanelistRequirements` descuentan, además del stock del panelista, las cantidades ya en camino (envíos en `pending`/`sent` no recibidos) para ese panelista+material.

- [ ] **Step 1: Añadir un helper que sume el en-tránsito por panelista+material**

Consulta reutilizable (misma cuenta, materiales en juego, panelistas en juego):

```ts
async function getInTransitMap(
  accountId: string, panelistIds: string[], materialIds: string[]
): Promise<Record<string, number>> {
  const map: Record<string, number> = {}
  if (panelistIds.length === 0 || materialIds.length === 0) return map
  const { data } = await supabase
    .from('material_shipments')
    .select('panelist_id, status, items:material_shipment_items(material_id, quantity_sent)')
    .eq('account_id', accountId)
    .in('panelist_id', panelistIds)
    .in('status', ['pending', 'sent'])   // en camino, aún no recibido ni cancelado
  ;(data || []).forEach((s: any) => {
    ;(s.items || []).forEach((it: any) => {
      if (!materialIds.includes(it.material_id)) return
      const key = `${s.panelist_id}_${it.material_id}`
      map[key] = (map[key] || 0) + Number(it.quantity_sent)
    })
  })
  return map
}
```

- [ ] **Step 2: Restar el en-tránsito en `calculatePanelistRequirements`**

Tras construir `panelistStockMap` (paso 6 de la función), obtener `inTransitMap = await getInTransitMap(accountId, panelistIds, materialIds)`. En el paso 8, al calcular `netQuantity`, restar también el en-tránsito:

```ts
const inTransit = inTransitMap[`${panelistId}_${materialId}`] || 0
const netQuantity = Math.max(0, matData.quantity - panelistStock - inTransit)
```

- [ ] **Step 3: Restar el en-tránsito en `calculateMaterialRequirements`**

Análogo: calcular `inTransitMap` y en el paso 9 restar el en-tránsito por `detail.origin_panelist_id + materialId` al `quantityNeededForThisDetail`. Ojo: aquí la necesidad se agrega por detalle; restar el en-tránsito **una sola vez por panelista+material** (llevar un `Set` de claves ya descontadas) para no doble-contar entre detalles.

- [ ] **Step 4: Verificar lint + build**

Run: `npm run lint` — Expected: 0 errores, ≤48 warnings.
Run: `npm run build` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/materialCalculator.ts
git commit -m "feat(stock): restar material en transito al calcular necesidad (idempotencia de reposicion)"
```

---

### Task 5: Toggle `is_blocking` en el catálogo de materiales

**Files:**
- Modify: el componente del catálogo de materiales bajo `src/components/stock/` (localizar el que lista `material_catalog`, p.ej. `MaterialCatalogTab.tsx`; si no existe una columna editable, añadir la celda toggle).
- Modify: `public/locales/{en,es,fr,ar}.csv`

**Interfaces:**
- Consumes: tabla `material_catalog` (columna `is_blocking` de Task 1).
- Produces: el manager puede marcar/desmarcar un material como bloqueante desde la UI.

- [ ] **Step 1: Localizar el componente del catálogo**

Run: `grep -rl "material_catalog" src/components/stock` — abrir el que renderiza la tabla de materiales. Añadir una columna "Bloqueante" con un checkbox por fila.

- [ ] **Step 2: Añadir el update**

```ts
const toggleBlocking = async (materialId: string, value: boolean) => {
  const { error } = await supabase
    .from('material_catalog')
    .update({ is_blocking: value })
    .eq('id', materialId)
  if (error) throw error
  await reload()  // o el reload del hook correspondiente
}
```

Encabezado y tooltip con claves i18n `stock.material.blocking` y `stock.material.blocking_hint`.

- [ ] **Step 3: Añadir claves i18n a los 4 CSV** (mismo conjunto en en/es/fr/ar):

```
stock.material.blocking,Blocking
stock.material.blocking_hint,A blocking material (e.g. RFID tag) stops any product that requires it from being shipped
```
(traducir el valor en es/fr/ar; la clave es idéntica en los 4).

- [ ] **Step 4: Verificar lint + build.**

- [ ] **Step 5: Commit**

```bash
git add src/components/stock public/locales
git commit -m "feat(stock): toggle is_blocking en catalogo de materiales + i18n"
```

---

## Fase 2 — Tratamiento base de "falta de material"

### Task 6: Extender `receive_material_shipment` para cerrar la baja y resolver la incidencia; RPC `find_surplus_donors`

**Files:**
- Create: `supabase/migrations/20260807100200_materials_treatment_close.sql`

**Interfaces:**
- Consumes: `panelist_incident.linked_material_shipment_id` + `linked_unavailability_id` (Task 1 / baseline incidencias); `resolve_panelist_incident` (baseline); mecanismo de cierre de baja = `UPDATE panelist_unavailability SET status='cancelled'`.
- Produces: `receive_material_shipment` (CREATE OR REPLACE) que, si el envío está enlazado a una incidencia con baja, cierra la baja y resuelve la incidencia; `find_surplus_donors(p_account_id, p_receiver_panelist_id, p_material_id, p_quantity) RETURNS TABLE(...)`.

- [ ] **Step 1: Redefinir `receive_material_shipment` añadiendo el cierre**

Copiar el cuerpo de Task 2 y añadir, tras marcar `received`, el bloque de cierre:

```sql
-- ...tras: update material_shipments set status='received', received_date=now() ...

-- Cierre del tratamiento si este envio nace de una incidencia de materiales.
declare
  v_incident public.panelist_incident%rowtype;
begin
  select * into v_incident
    from public.panelist_incident
   where linked_material_shipment_id = p_shipment_id
   limit 1;

  if found then
    -- Cerrar la baja por materiales (dispara el undo del motor: revierte reroutes,
    -- descarta propuestas pendientes). status 'cancelled' es el unico valor no-active.
    if v_incident.linked_unavailability_id is not null then
      update public.panelist_unavailability
         set status = 'cancelled', updated_at = now()
       where id = v_incident.linked_unavailability_id
         and status = 'active';
    end if;
    -- Resolver la incidencia con respuesta pendiente de envio al panelista.
    perform public.resolve_panelist_incident(
      v_incident.id, 'resolved',
      'Material recibido; disponibilidad restaurada.', null);
  end if;
end;
```

(Integrar dentro de la función; mantener `security definer`, `search_path=public`, y el `grant execute`.)

- [ ] **Step 2: Añadir `find_surplus_donors`**

Excedente de un donante = su stock del material − su necesidad propia según su plan (aprox: stock − Σ requisitos de sus muestras pendientes). Para no reimplementar el calculador en SQL, la versión base define excedente como **stock actual del donante por encima de un umbral 0** menos lo que ya tiene comprometido en envíos en tránsito; el ajuste fino por plan se hace en el hook (Task 7) que ya tiene el calculador. Esta RPC devuelve candidatos con su stock y una marca de cercanía:

```sql
create or replace function public.find_surplus_donors(
  p_account_id uuid,
  p_receiver_panelist_id uuid,
  p_material_id uuid,
  p_quantity numeric
) returns table (
  panelist_id uuid,
  panelist_name text,
  available numeric,
  same_city boolean
)
language sql
security definer
set search_path = public
as $$
  with receiver as (
    select city_id from public.panelists where id = p_receiver_panelist_id
  )
  select pms.panelist_id,
         p.name,
         pms.quantity as available,
         (p.city_id is not distinct from (select city_id from receiver)) as same_city
    from public.panelist_material_stocks pms
    join public.panelists p on p.id = pms.panelist_id
   where pms.account_id = p_account_id
     and pms.material_id = p_material_id
     and pms.panelist_id <> p_receiver_panelist_id
     and pms.quantity > 0
   order by same_city desc, pms.quantity desc;
$$;

grant execute on function public.find_surplus_donors(uuid, uuid, uuid, numeric)
  to authenticated, service_role;
```

Llamar `assert_same_account(p_account_id)` al inicio no es posible en función SQL pura; envolver en `plpgsql` con `perform public.assert_same_account(p_account_id);` antes del `return query` **o** confiar en RLS. Elegir plpgsql con la guarda para mantener el patrón del proyecto.

- [ ] **Step 3: Validar en local** (sembrar incidencia+baja+envío enlazado; `receive_material_shipment` → baja `cancelled`, incidencia `resolved`). Verificar `find_surplus_donors` ordena `same_city` primero.

- [ ] **Step 4: Confirmar proyecto+ref con el usuario y aplicar a dev.**

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260807100200_materials_treatment_close.sql
git commit -m "feat(materials): cierre de baja+incidencia al recibir; RPC find_surplus_donors (cercania por ciudad)"
```

---

### Task 7: Hook `useMaterialsTreatment` (orquestación del procedimiento)

**Files:**
- Create: `src/lib/hooks/useMaterialsTreatment.ts`

**Interfaces:**
- Consumes: `calculatePanelistRequirements` (materialCalculator), `useStockManagement` (`createShipment`, `markShipmentSent`), RPCs `create_unavailability_from_incident`, `find_surplus_donors`, tabla `material_catalog` (`is_blocking`), `panelist_incident`.
- Produces: funciones `reconcileStock`, `recomputeNeed`, `resolveSupply`, `createDisplacementBaja`, expuestas para que el panel las llame paso a paso.

- [ ] **Step 1: Definir tipos y esqueleto**

```ts
export interface NeedLine {
  material_id: string; material_code: string; material_name: string
  unit_measure: string; quantity_needed: number; is_blocking: boolean
}
export interface SupplyPlan {
  fromCentral: { material_id: string; quantity: number }[]
  fromDonor:   { material_id: string; quantity: number; donor_panelist_id: string; donor_name: string }[]
  toPurchase:  { material_id: string; quantity: number }[]
}
```

- [ ] **Step 2: `reconcileStock` (Paso 1 — ajuste directo por el manager)**

El manager fija el stock real observado (el valor vive en Supabase y n8n lo consulta; no exige diálogo bloqueante). Reutiliza el ajuste con auditoría existente:

```ts
const reconcileStock = async (panelistId: string, materialId: string, realQty: number) => {
  const { error: e1 } = await supabase.from('panelist_material_stocks').upsert({
    account_id: accountId, panelist_id: panelistId, material_id: materialId,
    quantity: realQty, last_updated: new Date().toISOString()
  }, { onConflict: 'account_id,panelist_id,material_id' })
  if (e1) throw e1
  await supabase.from('material_movements').insert({
    account_id: accountId, material_id: materialId, movement_type: 'adjustment',
    quantity: realQty, notes: 'Reconciliacion por incidencia de materiales', created_by: profile?.id
  })
}
```

- [ ] **Step 3: `recomputeNeed` (Paso 2+3 — necesidad total, marca bloqueante)**

Llama `calculatePanelistRequirements(accountId, start, end)` (ventana = su plan vigente), filtra la fila del panelista, y enriquece cada material con `is_blocking` leído de `material_catalog`. Devuelve `NeedLine[]`. (El en-tránsito ya lo resta el calculador tras Task 4.)

- [ ] **Step 4: `resolveSupply` (Paso 4 — cascada central → donante → compra)**

Para cada `NeedLine` con `quantity_needed>0`: leer stock central (`material_stocks`); lo que cubra → `fromCentral`. El déficit restante → `find_surplus_donors(...)`, tomar del mejor donante (mismo `same_city desc, available desc`) hasta cubrir → `fromDonor`. Lo que aún falte → `toPurchase`. Devolver `SupplyPlan` (sin ejecutar todavía; el panel lo muestra para confirmar).

- [ ] **Step 5: `executeSupply` — crea los envíos (todo lo que falta en el MISMO envío por receptor)**

Bloqueante + sustituible van juntos. Crear **un** `createShipment` central→panelista con todos los items `fromCentral`, y **un** envío por donante con sus items `fromDonor` (usando `source_panelist_id`; requiere ampliar `createShipment` para aceptar `source_panelist_id` — ver Step 6). Marcar cada envío `sent` con `markShipmentSent`. `toPurchase` solo se registra/informa (PDF/manual, no se automatiza). Devolver el `shipment_id` del envío central para enlazarlo a la incidencia.

- [ ] **Step 6: Ampliar `createShipment` para `source_panelist_id`**

En `useStockManagement.createShipment`, aceptar `source_panelist_id?: string` en el objeto y escribirlo en el insert de `material_shipments`. (Modificación mínima; no rompe llamadas existentes.)

- [ ] **Step 7: `createDisplacementBaja` (Paso 5 — baja panelista entero)**

```ts
const createDisplacementBaja = async (incidentId: string, expectedDate: string) => {
  const today = new Date().toISOString().slice(0, 10)
  const { data, error } = await supabase.rpc('create_unavailability_from_incident', {
    p_incident_id: incidentId, p_start: today, p_end: expectedDate, p_reason: 'materials'
  })
  if (error) throw error
  return data as string // unavailability_id
}
```

Tras crear la baja, enlazar el envío central a la incidencia:
```ts
await supabase.from('panelist_incident')
  .update({ linked_material_shipment_id: shipmentId })
  .eq('id', incidentId)
```
El motor genera las propuestas (subsistema C). La decisión por muestra la da `ProposalReviewPanel` (sin cambios).

- [ ] **Step 8: Verificar lint + build.**

- [ ] **Step 9: Commit**

```bash
git add src/lib/hooks/useMaterialsTreatment.ts src/hooks/useStockManagement.ts
git commit -m "feat(materials): hook de orquestacion (reconciliar, recalcular, cascada, baja panelista entero)"
```

---

### Task 8: Bloque guiado `missing_materials` en `ReportedIncidentPanel`

**Files:**
- Modify: `src/components/incidents/ReportedIncidentPanel.tsx`
- Modify: `public/locales/{en,es,fr,ar}.csv`

**Interfaces:**
- Consumes: `useMaterialsTreatment` (Task 7); el envío `expected_date` estimado por lead time (`stock_settings.shipment_lead_time_days`/`purchase_lead_time_days`).
- Produces: un asistente de 5 pasos dentro del panel para incidencias `missing_materials`, y un enlace a la bandeja del subsistema C ("Disponibilidad de panelistas") para resolver muestras.

- [ ] **Step 1: Añadir un sub-componente `MissingMaterialsActions`**

En el `switch (inc.category)` del panel, para `missing_materials` renderizar el asistente (sustituyendo el bloque genérico actual de reschedule/cancel). Pasos con estado local:
1. **Reconciliación:** por material del reporte (`payload.materials`), input de "stock real" → botón que llama `reconcileStock`.
2. **Recalcular:** botón → `recomputeNeed` → tabla de `NeedLine` marcando los bloqueantes.
3. **Suministro:** botón → `resolveSupply` → mostrar `SupplyPlan` (central/donante/compra) → botón "Ejecutar suministro" → `executeSupply` (guarda `shipmentId`).
4. **Ventana + baja:** calcular `expectedDate = hoy + lead time` (compra si hubo `toPurchase`, si no envío); botón "Crear baja y desplazar" → `createDisplacementBaja(incidentId, expectedDate)` + enlazar envío.
5. **Cierre:** nota informativa "la baja se cierra al confirmar recepción (n8n)"; enlace a `/incidents/panelist-availability` para resolver las muestras en el subsistema C.

- [ ] **Step 2: Estilos**

Reutilizar `BTN_PRIMARY`/`BTN_SECONDARY` ya definidos en el fichero. No introducir clases globales nuevas.

- [ ] **Step 3: Claves i18n (4 CSV, mismo conjunto)** — prefijo `reported_incidents.materials.*`:

```
reported_incidents.materials.step1_title,Reconcile stock
reported_incidents.materials.real_qty,Real quantity
reported_incidents.materials.step2_title,Recompute needs
reported_incidents.materials.blocking_badge,Blocking
reported_incidents.materials.step3_title,Supply
reported_incidents.materials.from_central,From central stock
reported_incidents.materials.from_donor,From donor {name}
reported_incidents.materials.to_purchase,Needs purchase (manual/PDF)
reported_incidents.materials.execute_supply,Execute supply
reported_incidents.materials.step4_title,Displacement window
reported_incidents.materials.create_baja,Create leave and displace samples
reported_incidents.materials.step5_title,Close on reception
reported_incidents.materials.go_to_availability,Resolve samples in panelist availability
reported_incidents.materials.close_hint,The leave closes automatically when the panelist confirms reception.
```
(traducir valores en es/fr/ar; claves idénticas).

- [ ] **Step 4: Verificar lint + build.**

- [ ] **Step 5: Commit**

```bash
git add src/components/incidents/ReportedIncidentPanel.tsx public/locales
git commit -m "feat(incidents): asistente guiado missing_materials (reconciliar->suministrar->baja->cierre) + i18n"
```

---

## Fase 3 — Excedente donante (afinado)

### Task 9: Ajustar excedente donante por plan propio + preferencia de ciudad

**Files:**
- Modify: `src/lib/hooks/useMaterialsTreatment.ts`

**Interfaces:**
- Consumes: `find_surplus_donors` (Task 6), `calculatePanelistRequirements`.
- Produces: `resolveSupply` calcula el excedente **real** del donante (`stock − necesidad de su propio plan`), no solo `stock>0`, y respeta la preferencia de ciudad ya ordenada por la RPC.

- [ ] **Step 1: Cruzar candidatos con su propia necesidad**

En `resolveSupply`, tras `find_surplus_donors`, para cada candidato calcular su necesidad propia del material (reusar `calculatePanelistRequirements` una vez y mapear por panelista+material). Excedente donante = `available − necesidad_propia`. Descartar candidatos con excedente ≤ 0. Sin margen de seguridad (decisión #4 del spec): se puede tomar todo el excedente.

- [ ] **Step 2: Mantener el orden de cercanía**

La RPC ya devuelve `same_city desc, available desc`; conservar ese orden al elegir donante (ciudades mejor conectadas primero). Documentar en comentario que el "tier A" de ciudad queda como mejora futura (requiere catálogo `cities` con tipo).

- [ ] **Step 3: Verificar lint + build.**

- [ ] **Step 4: Commit**

```bash
git add src/lib/hooks/useMaterialsTreatment.ts
git commit -m "feat(materials): excedente donante = stock - necesidad propia; preferencia por ciudad"
```

---

## Fase 4 — Diálogo n8n de recepción

### Task 10: Contrato de recepción n8n + verificación del canal de vuelta

**Files:**
- Create: `docs/integrations/2026-08-07-n8n-recepcion-material.md`

**Interfaces:**
- Consumes: `receive_material_shipment(p_shipment_id)` (idempotente, service-role permitido); campos `panelist_incident.reply_to_panelist`/`reply_status`.
- Produces: documento de contrato bidireccional (ONEMS↔n8n) para: (a) notificar "material en camino", (b) recibir confirmación de recepción del panelista, (c) consulta de stock por n8n.

- [ ] **Step 1: Redactar el contrato**

Secciones: disparadores, payloads, y las llamadas exactas que n8n hace:
- **Aviso "en camino":** cuando un envío pasa a `sent`, ONEMS deja `reply_to_panelist` + `reply_status='pending_send'`; n8n lo envía por Telegram (patrón ya existente en el contrato de incidencias `docs/integrations/2026-08-06-n8n-incidencias-reportadas.md`).
- **Confirmación de recepción:** n8n llama `supabase.rpc('receive_material_shipment', { p_shipment_id })` con la service-role key. Idempotente: reintentos seguros. Efecto documentado: acredita stock, cierra baja, resuelve incidencia.
- **Consulta de stock:** n8n lee `panelist_material_stocks` (filtrado por `account_id`) para la reconciliación del Paso 1.
- **Seguridad:** la key de n8n debe ser un secreto (no en docs); apuntar a la tarea de RLS (Task 11) — hasta activarla, el service-role bypassa RLS pero las lecturas anon no deben exponerse.

- [ ] **Step 2: Verificar que `receive_material_shipment` tiene `grant ... to service_role`** (Task 2/6). Si falta, añadir en una migración de corrección.

- [ ] **Step 3: Commit**

```bash
git add docs/integrations/2026-08-07-n8n-recepcion-material.md
git commit -m "docs(materials): contrato n8n de recepcion (en-camino, confirmacion idempotente, consulta stock)"
```

---

## Transversal — Seguridad

### Task 11: Activar RLS por `account_id` en las tablas de stock

**Files:**
- Create: `supabase/migrations/20260807100300_stock_rls.sql`

**Interfaces:**
- Consumes: helpers `current_user_account_id()` / `is_superadmin()` (existentes).
- Produces: RLS activada con políticas por `account_id` en `material_stocks`, `panelist_material_stocks`, `material_movements`, `material_shipments`, `material_shipment_items`, `stock_settings`, `material_requirements_periods`, `stock_alerts`, `material_catalog`, `product_materials`.

- [ ] **Step 1: Escribir políticas por tabla (patrón del proyecto)**

Para cada tabla, `enable row level security` + política `using (account_id = current_user_account_id() or is_superadmin())` para SELECT/INSERT/UPDATE/DELETE. `service_role` bypassa RLS por defecto (n8n sigue funcionando). Ejemplo:

```sql
alter table public.material_shipments enable row level security;
create policy material_shipments_rls on public.material_shipments
  using (account_id = current_user_account_id() or is_superadmin())
  with check (account_id = current_user_account_id() or is_superadmin());
```
Repetir por cada tabla. Verificar el nombre exacto de los helpers en una migración existente antes de escribir (`grep current_user_account_id supabase/migrations`).

- [ ] **Step 2: Validar en local que las lecturas del frontend siguen funcionando**

Aplicar en el Postgres local; con un rol de cuenta concreta, comprobar que `select` sobre cada tabla devuelve solo su `account_id` y que un `account_id` ajeno no aparece. Comprobar que el frontend (dev) sigue cargando el módulo de stock sin romper (no auto-aplicar a dev hasta confirmar).

- [ ] **Step 3: Confirmar proyecto+ref con el usuario y aplicar a dev.** Riesgo alto (puede cortar accesos): revisar con el usuario antes de aplicar; tener a mano el rollback (`disable row level security`).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260807100300_stock_rls.sql
git commit -m "security(stock): activar RLS por account_id en tablas de stock"
```

---

## Self-review (cobertura del spec)

- **G1 ciclo de recepción + resta en-tránsito + bug delete-on-send/columna** → Tasks 1,2,3,4.
- **G2 flag bloqueante** → Tasks 1,5.
- **G3 donante-excedente cercano** → Tasks 6,9.
- **G4 ventana por lead time** → Task 8 (paso 4).
- **G5 puente incidencia→baja** → Tasks 6,7 (`create_unavailability_from_incident` + enlace + cierre).
- **G7 diálogo n8n** → Task 10.
- **Decisión #1 panelista entero, motor sin cambios** → Task 7/8 (usa el motor tal cual; subsistema C resuelve por muestra).
- **Decisión #2 cierre por recepción** → Task 6 (`receive_material_shipment` cierra baja).
- **Decisión #3 is_blocking** → Tasks 1,5.
- **Decisión #4 cascada sin margen** → Tasks 6,9.
- **Seguridad RLS** → Task 11.
- **§7 cerradas:** reconciliación = ajuste directo del manager (n8n consulta) → Task 7 Step 2; cercanía = ciudad preferente → Task 6/9; sustituible en mismo envío → Task 7 Step 5.
```
