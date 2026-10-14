-- 20260807100200_materials_treatment_close.sql
begin;

create or replace function public.receive_material_shipment(p_shipment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ship     public.material_shipments%rowtype;
  v_item     record;
  v_incident public.panelist_incident%rowtype;
begin
  select * into v_ship from public.material_shipments where id = p_shipment_id for update;
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

  -- Cierre del tratamiento si este envio nace de una incidencia de materiales.
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
$$;

grant execute on function public.receive_material_shipment(uuid) to authenticated, service_role;

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
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_same_account(p_account_id);

  return query
  with receiver as (
    select city_id from public.panelists where id = p_receiver_panelist_id
  )
  select pms.panelist_id,
         p.name::text,
         pms.quantity as available,
         (p.city_id is not distinct from (select city_id from receiver)) as same_city
    from public.panelist_material_stocks pms
    join public.panelists p on p.id = pms.panelist_id
   where pms.account_id = p_account_id
     and pms.material_id = p_material_id
     and pms.panelist_id <> p_receiver_panelist_id
     and pms.quantity > 0
   order by same_city desc, pms.quantity desc;
end;
$$;

grant execute on function public.find_surplus_donors(uuid, uuid, uuid, numeric)
  to authenticated, service_role;

commit;
