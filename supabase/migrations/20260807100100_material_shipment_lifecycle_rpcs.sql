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
  select * into v_ship from public.material_shipments where id = p_shipment_id for update;
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
end;
$$;

grant execute on function public.send_material_shipment(uuid)    to authenticated, service_role;
grant execute on function public.receive_material_shipment(uuid) to authenticated, service_role;

commit;
