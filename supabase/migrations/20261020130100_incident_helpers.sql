-- Incidencias de indisponibilidad: funciones auxiliares del motor.
-- Hoy local del panelista, carga semanal de un nodo, umbral de saturacion, huecos (fecha / nodo),
-- aplicar cambio / anulacion sobre una muestra y cola de avisos de cambios de esta semana.
-- Semana = lunes..domingo. Dias de envio = lunes..viernes (isodow 1..5).
-- Todas SECURITY DEFINER + search_path fijo. Solo panelist_local_today es ejecutable por authenticated;
-- el resto son internas (las llaman el motor y los RPC del manager, que hacen su propia guarda multi-tenant).

-- (0) Endurecimiento de la cola (arrastrado de la Tarea 2): authenticated solo lee (RLS por cuenta).
REVOKE ALL ON public.panelist_notification FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.panelist_notification TO authenticated;

-- (1) Hoy en la zona horaria del panelista (mismo mapa pais -> zona que el menu de Telegram).
CREATE OR REPLACE FUNCTION public.panelist_local_today(p_panelist_id uuid)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (now() AT TIME ZONE COALESCE(
           (SELECT CASE upper(trim(p.address_country))
                     WHEN 'KENYA' THEN 'Africa/Nairobi'
                     WHEN 'UNITED STATES' THEN 'America/New_York'
                     WHEN 'USA' THEN 'America/New_York'
                     WHEN 'SPAIN' THEN 'Europe/Madrid'
                     ELSE 'UTC' END
              FROM panelists p WHERE p.id = p_panelist_id),
           'UTC'))::date;
$$;

-- (2) Lunes de la semana de p_date.
CREATE OR REPLACE FUNCTION public.incident_week_start(p_date date)
RETURNS date
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_date - (extract(isodow FROM p_date)::int - 1);
$$;

-- (3) Carga semanal: muestras no canceladas de lunes..domingo donde el nodo es origen O destino.
CREATE OR REPLACE FUNCTION public.incident_node_week_load(p_node_id uuid, p_date date)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::int
    FROM allocation_plan_details a
   WHERE (a.origin_node_id = p_node_id OR a.destination_node_id = p_node_id)
     AND a.fecha_programada BETWEEN incident_week_start(p_date) AND incident_week_start(p_date) + 6
     AND a.status <> 'cancelled';
$$;

-- (4) Umbral de saturacion semanal: referencia * (1 + 1.5 * desviacion/100). NULL -> valores por defecto.
CREATE OR REPLACE FUNCTION public.incident_saturation_threshold(
  p_reference_load numeric DEFAULT 6,
  p_deviation_percent numeric DEFAULT 20)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(p_reference_load, 6) * (1 + 1.5 * COALESCE(p_deviation_percent, 20) / 100);
$$;

-- (5) ¿Cabe una muestra mas en el nodo ese dia? Panelista activo y disponible + carga semanal + 1 <= umbral.
CREATE OR REPLACE FUNCTION public.incident_node_fits(
  p_node_id uuid, p_date date, p_reference_load numeric, p_deviation_percent numeric)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_node_id IS NULL OR p_date IS NULL THEN RETURN false; END IF;
  RETURN COALESCE(is_node_available(p_node_id, p_date), false)
     AND incident_node_week_load(p_node_id, p_date) + 1
         <= incident_saturation_threshold(p_reference_load, p_deviation_percent);
END;
$$;

-- (6) Hueco de fecha para el mismo nodo: d > p_after, en el mes de p_month_anchor, lunes..viernes, que quepa.
--     Reparto: primero el dia con menos muestras no canceladas del nodo (origen o destino), luego el mas temprano.
CREATE OR REPLACE FUNCTION public.incident_find_shift_date(
  p_node_id uuid, p_after date, p_month_anchor date, p_reference_load numeric, p_deviation_percent numeric)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT g.d::date
    FROM generate_series(
           GREATEST(p_after + 1, date_trunc('month', p_month_anchor)::date),
           (date_trunc('month', p_month_anchor) + interval '1 month - 1 day')::date,
           interval '1 day') AS g(d)
   WHERE p_node_id IS NOT NULL AND p_after IS NOT NULL
     AND extract(isodow FROM g.d) BETWEEN 1 AND 5
     AND incident_node_fits(p_node_id, g.d::date, p_reference_load, p_deviation_percent)
   ORDER BY (SELECT count(*) FROM allocation_plan_details a
              WHERE (a.origin_node_id = p_node_id OR a.destination_node_id = p_node_id)
                AND a.fecha_programada = g.d::date
                AND a.status <> 'cancelled') ASC,
            g.d ASC
   LIMIT 1;
$$;

-- (7) Nodo alternativo de la misma ciudad y cuenta (activo, distinto del excluido) que quepa ese dia.
--     Orden: menor carga semanal, luego auto_id.
CREATE OR REPLACE FUNCTION public.incident_find_node(
  p_city_id uuid, p_exclude_node_id uuid, p_date date, p_reference_load numeric, p_deviation_percent numeric)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT n.id
    FROM nodes n
    JOIN cities c ON c.id = n.city_id AND c.account_id = n.account_id
   WHERE n.city_id = p_city_id
     AND n.id IS DISTINCT FROM p_exclude_node_id
     AND COALESCE(n.status, 'active') = 'active'
     AND incident_node_fits(n.id, p_date, p_reference_load, p_deviation_percent)
   ORDER BY incident_node_week_load(n.id, p_date) ASC, n.auto_id ASC
   LIMIT 1;
$$;

-- (8) Cola de avisos "cambio en tu plan de esta semana".
CREATE OR REPLACE FUNCTION public.incident_enqueue_plan_change(
  p_detail_id uuid, p_change text, p_old_date date, p_new_date date, p_exclude_panelist_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_start date := date_trunc('week', current_date)::date;
  v_d record;
  v_orig record;
  v_dest record;
  v_payload jsonb;
  v_count integer := 0;
BEGIN
  IF p_change IS NULL OR p_change NOT IN ('shift_date','reroute_origin','reroute_destination','cancel','revert') THEN
    RAISE EXCEPTION 'Unknown plan change %', p_change;
  END IF;
  IF COALESCE(current_setting('onems.suppress_notifications', true), '') = 'on' THEN RETURN 0; END IF;
  IF NOT (COALESCE(p_old_date BETWEEN v_week_start AND v_week_start + 6, false)
          OR COALESCE(p_new_date BETWEEN v_week_start AND v_week_start + 6, false)) THEN
    RETURN 0;
  END IF;

  SELECT a.id, a.account_id, a.fecha_programada, a.origin_node_id, a.destination_node_id,
         no.auto_id AS origin_code, nd.auto_id AS destination_code,
         pr.description AS product_description, ca.name AS carrier_name
    INTO v_d
    FROM allocation_plan_details a
    JOIN nodes no ON no.id = a.origin_node_id
    JOIN nodes nd ON nd.id = a.destination_node_id
    LEFT JOIN allocation_plans ap ON ap.id = a.plan_id
    LEFT JOIN products pr ON pr.id = ap.product_id
    LEFT JOIN carriers ca ON ca.id = ap.carrier_id
   WHERE a.id = p_detail_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  -- Panelista activo de cada nodo (mismo criterio que get_panelist_for_node).
  SELECT p.id, p.name, p.address_line1, p.address_line2, p.postal_code, p.address_city
    INTO v_orig FROM panelists p
   WHERE p.id = (SELECT g.panelist_id FROM get_panelist_for_node(v_d.origin_node_id, v_d.fecha_programada) g);
  SELECT p.id, p.name, p.address_line1, p.address_line2, p.postal_code, p.address_city
    INTO v_dest FROM panelists p
   WHERE p.id = (SELECT g.panelist_id FROM get_panelist_for_node(v_d.destination_node_id, v_d.fecha_programada) g);

  v_payload := jsonb_build_object(
    'detail_id', v_d.id,
    'change', p_change,
    'old_date', p_old_date,
    'new_date', p_new_date,
    'scheduled_date', v_d.fecha_programada,
    'origin_node_code', v_d.origin_code,
    'destination_node_code', v_d.destination_code,
    'origin_panelist_name', v_orig.name,
    'destination_panelist_name', v_dest.name,
    'destination_address', jsonb_build_object(
      'address_line1', v_dest.address_line1,
      'address_line2', v_dest.address_line2,
      'postal_code', v_dest.postal_code,
      'city', v_dest.address_city),
    'product_description', v_d.product_description,
    'carrier_name', v_d.carrier_name);

  -- Receptor: solo en cambio de destino (nuevo receptor).
  IF p_change = 'reroute_destination'
     AND v_dest.id IS NOT NULL AND v_dest.id IS DISTINCT FROM p_exclude_panelist_id THEN
    INSERT INTO panelist_notification (account_id, panelist_id, kind, payload)
    VALUES (v_d.account_id, v_dest.id, 'plan_change_this_week', v_payload || jsonb_build_object('recipient_role', 'receiver'));
    v_count := v_count + 1;
  END IF;

  -- Emisor: en todos los cambios (en reroute_origin es el nuevo emisor; en reroute_destination lleva la direccion nueva).
  IF v_orig.id IS NOT NULL AND v_orig.id IS DISTINCT FROM p_exclude_panelist_id THEN
    INSERT INTO panelist_notification (account_id, panelist_id, kind, payload)
    VALUES (v_d.account_id, v_orig.id, 'plan_change_this_week', v_payload || jsonb_build_object('recipient_role', 'sender'));
    v_count := v_count + 1;
  END IF;

  RETURN v_count;
END;
$$;

-- (9) Aplicar un cambio de fecha y/o nodo a la muestra de una linea pendiente.
CREATE OR REPLACE FUNCTION public.incident_apply_change(
  p_proposal_id uuid, p_new_date date, p_new_node_id uuid, p_mode text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_prop record;
  v_d record;
  v_exclude uuid;
  v_eff_date date;
  v_date_changed boolean;
  v_node_city uuid;
  v_new_city uuid;
  v_new_account uuid;
  v_pan record;
  v_change text;
BEGIN
  IF p_mode IS NULL OR p_mode NOT IN ('auto','manager') THEN RAISE EXCEPTION 'Unknown mode %', p_mode; END IF;

  SELECT * INTO v_prop FROM panelist_reassignment_proposal WHERE id = p_proposal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proposal % not found', p_proposal_id; END IF;
  IF v_prop.status <> 'pending' THEN RAISE EXCEPTION 'Proposal % already %', p_proposal_id, v_prop.status; END IF;

  SELECT * INTO v_d FROM allocation_plan_details WHERE id = v_prop.allocation_plan_detail_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sample % not found', v_prop.allocation_plan_detail_id; END IF;
  IF v_d.status NOT IN ('pending','notified') THEN
    RAISE EXCEPTION 'Sample % is % and cannot be changed', v_d.id, v_d.status;
  END IF;

  v_date_changed := p_new_date IS NOT NULL AND p_new_date IS DISTINCT FROM v_d.fecha_programada;
  IF p_new_node_id IS NULL AND NOT v_date_changed THEN
    RAISE EXCEPTION 'Nothing to apply for proposal %', p_proposal_id;
  END IF;
  v_eff_date := CASE WHEN v_date_changed THEN p_new_date ELSE v_d.fecha_programada END;

  IF p_new_node_id IS NOT NULL THEN
    -- Nunca a otra cuenta ni a otra ciudad.
    SELECT n.city_id INTO v_node_city FROM nodes n
     WHERE n.id = CASE WHEN v_prop.affected_role = 'origin' THEN v_d.origin_node_id ELSE v_d.destination_node_id END;
    SELECT n.city_id, n.account_id INTO v_new_city, v_new_account FROM nodes n WHERE n.id = p_new_node_id;
    IF v_new_account IS DISTINCT FROM v_d.account_id OR v_new_city IS DISTINCT FROM v_node_city THEN
      RAISE EXCEPTION 'Target node % not in the same account/city', p_new_node_id;
    END IF;
    SELECT * INTO v_pan FROM get_panelist_for_node(p_new_node_id, v_eff_date);

    IF v_prop.affected_role = 'origin' THEN
      UPDATE allocation_plan_details
         SET original_origin_node_id = COALESCE(original_origin_node_id, origin_node_id),
             origin_node_id = p_new_node_id,
             origin_panelist_name = v_pan.panelist_name,
             origin_panelist_id = CASE WHEN origin_panelist_id IS NULL THEN NULL ELSE v_pan.panelist_id END
       WHERE id = v_d.id;
    ELSE
      UPDATE allocation_plan_details
         SET original_destination_node_id = COALESCE(original_destination_node_id, destination_node_id),
             destination_node_id = p_new_node_id,
             destination_panelist_name = v_pan.panelist_name,
             destination_panelist_id = CASE WHEN destination_panelist_id IS NULL THEN NULL ELSE v_pan.panelist_id END
       WHERE id = v_d.id;
    END IF;
  END IF;

  IF v_date_changed THEN
    UPDATE allocation_plan_details
       SET original_fecha_programada = COALESCE(original_fecha_programada, fecha_programada),
           fecha_programada = p_new_date
     WHERE id = v_d.id;
  END IF;

  UPDATE allocation_plan_details
     SET status = CASE WHEN status = 'notified' THEN 'pending' ELSE status END,
         reassignment_reason = 'panelist_unavailable',
         reassigned_at = now(),
         reassigned_by = v_actor,
         updated_at = now()
   WHERE id = v_d.id;

  UPDATE panelist_reassignment_proposal
     SET status = CASE p_mode WHEN 'auto' THEN 'auto_resolved' ELSE 'manager_resolved' END,
         final_action = CASE WHEN p_new_node_id IS NOT NULL THEN 'reroute' ELSE 'shift_date' END,
         final_target_node_id = p_new_node_id,
         final_date = CASE WHEN v_date_changed THEN p_new_date ELSE NULL END,
         applied_at = now(),
         confirmed_by = CASE WHEN p_mode = 'manager' THEN v_actor ELSE confirmed_by END,
         confirmed_at = CASE WHEN p_mode = 'manager' THEN now() ELSE confirmed_at END,
         updated_at = now()
   WHERE id = p_proposal_id;

  -- Aviso: el panelista de la baja no se avisa. Si cambian nodo y fecha, manda la semantica de nodo.
  SELECT u.panelist_id INTO v_exclude FROM panelist_unavailability u WHERE u.id = v_prop.unavailability_id;
  v_change := CASE
                WHEN p_new_node_id IS NOT NULL AND v_prop.affected_role = 'origin' THEN 'reroute_origin'
                WHEN p_new_node_id IS NOT NULL THEN 'reroute_destination'
                ELSE 'shift_date' END;
  PERFORM incident_enqueue_plan_change(v_d.id, v_change, v_d.fecha_programada, v_eff_date, v_exclude);
END;
$$;

-- (10) Anular la muestra de una linea pendiente.
CREATE OR REPLACE FUNCTION public.incident_apply_cancel(p_proposal_id uuid, p_mode text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_prop record;
  v_d record;
  v_exclude uuid;
BEGIN
  IF p_mode IS NULL OR p_mode NOT IN ('auto','manager') THEN RAISE EXCEPTION 'Unknown mode %', p_mode; END IF;

  SELECT * INTO v_prop FROM panelist_reassignment_proposal WHERE id = p_proposal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proposal % not found', p_proposal_id; END IF;
  IF v_prop.status <> 'pending' THEN RAISE EXCEPTION 'Proposal % already %', p_proposal_id, v_prop.status; END IF;

  SELECT * INTO v_d FROM allocation_plan_details WHERE id = v_prop.allocation_plan_detail_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sample % not found', v_prop.allocation_plan_detail_id; END IF;
  IF v_d.status NOT IN ('pending','notified') THEN
    RAISE EXCEPTION 'Sample % is % and cannot be cancelled', v_d.id, v_d.status;
  END IF;

  UPDATE allocation_plan_details
     SET status = 'cancelled',
         reassignment_reason = 'panelist_unavailable',
         reassigned_at = now(),
         reassigned_by = v_actor,
         updated_at = now()
   WHERE id = v_d.id;

  UPDATE panelist_reassignment_proposal
     SET status = CASE p_mode WHEN 'auto' THEN 'auto_resolved' ELSE 'manager_resolved' END,
         final_action = 'cancel',
         final_target_node_id = NULL,
         final_date = NULL,
         applied_at = now(),
         confirmed_by = CASE WHEN p_mode = 'manager' THEN v_actor ELSE confirmed_by END,
         confirmed_at = CASE WHEN p_mode = 'manager' THEN now() ELSE confirmed_at END,
         updated_at = now()
   WHERE id = p_proposal_id;

  SELECT u.panelist_id INTO v_exclude FROM panelist_unavailability u WHERE u.id = v_prop.unavailability_id;
  PERFORM incident_enqueue_plan_change(v_d.id, 'cancel', v_d.fecha_programada, NULL, v_exclude);
END;
$$;

-- (11) Permisos: solo panelist_local_today para authenticated; el resto interno.
REVOKE ALL ON FUNCTION public.panelist_local_today(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.panelist_local_today(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.incident_week_start(date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_node_week_load(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_saturation_threshold(numeric, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_node_fits(uuid, date, numeric, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_find_shift_date(uuid, date, date, numeric, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_find_node(uuid, uuid, date, numeric, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_enqueue_plan_change(uuid, text, date, date, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_apply_change(uuid, date, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.incident_apply_cancel(uuid, text) FROM PUBLIC, anon, authenticated;
