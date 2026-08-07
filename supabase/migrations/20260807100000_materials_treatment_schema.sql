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
