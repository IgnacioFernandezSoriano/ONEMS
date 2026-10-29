-- Business time del E2E: horas y dias laborables en la HORA LOCAL de la cuenta.
--
-- Hasta ahora los dias laborables se contaban sobre el instante en UTC, de modo que un envio de Kenya
-- (UTC+3) registrado a las 23:30 UTC ya caia en "el dia siguiente" cuando en Nairobi seguia siendo el mismo
-- dia. Esta migracion se construye por secciones.
-- Seccion 1:
--   * calculate_business_hours(inicio, fin, cuenta): horas laborables entre dos instantes, repartidas por
--     dia local; solo suman los dias laborables de la cuenta (is_account_working_day: weekly_schedule +
--     non_working_days; sin cuenta => lunes-viernes). Redondeo a 2 decimales; 0 si fin < inicio; NULL si
--     alguna entrada es NULL.
--   * calculate_business_days (misma firma que antes): cuenta los dias laborables locales d con
--     fecha_local(inicio) <= d < fecha_local(fin); 0 si fin < inicio.
--   * Zona = accounts.timezone de la cuenta; sin cuenta => 'UTC'.

CREATE OR REPLACE FUNCTION public.calculate_business_hours(
  p_start timestamptz, p_end timestamptz, p_account_id uuid)
RETURNS numeric
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE
  v_tz    text;
  v_ini   timestamp;
  v_fin   timestamp;
  v_d     timestamp;
  v_i     integer;
  v_total numeric := 0;
BEGIN
  IF p_start IS NULL OR p_end IS NULL THEN RETURN NULL; END IF;
  IF p_end < p_start THEN RETURN 0; END IF;

  v_tz  := COALESCE((SELECT timezone FROM accounts WHERE id = p_account_id), 'UTC');
  v_ini := p_start AT TIME ZONE v_tz;
  v_fin := p_end   AT TIME ZONE v_tz;

  FOR v_i IN 0..(v_fin::date - v_ini::date) LOOP
    v_d := date_trunc('day', v_ini) + v_i * interval '1 day';
    IF (p_account_id IS NOT NULL AND is_account_working_day(p_account_id, v_d::date))
       OR (p_account_id IS NULL AND extract(isodow FROM v_d) <= 5) THEN
      v_total := v_total + GREATEST(0,
        extract(epoch FROM (LEAST(v_fin, v_d + interval '1 day') - GREATEST(v_ini, v_d))) / 3600.0);
    END IF;
  END LOOP;

  RETURN ROUND(v_total, 2);
END $$;

CREATE OR REPLACE FUNCTION public.calculate_business_days(
  p_start_date timestamptz, p_end_date timestamptz, p_account_id uuid DEFAULT NULL::uuid)
RETURNS integer
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE
  v_tz    text;
  v_ini   date;
  v_fin   date;
  v_d     date;
  v_i     integer;
  v_count integer := 0;
BEGIN
  IF p_start_date IS NULL OR p_end_date IS NULL THEN RETURN NULL; END IF;
  IF p_end_date < p_start_date THEN RETURN 0; END IF;

  v_tz  := COALESCE((SELECT timezone FROM accounts WHERE id = p_account_id), 'UTC');
  v_ini := (p_start_date AT TIME ZONE v_tz)::date;
  v_fin := (p_end_date   AT TIME ZONE v_tz)::date;

  FOR v_i IN 0..(v_fin - v_ini - 1) LOOP
    v_d := v_ini + v_i;
    IF (p_account_id IS NOT NULL AND is_account_working_day(p_account_id, v_d))
       OR (p_account_id IS NULL AND extract(isodow FROM v_d) <= 5) THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END $$;

-- Seccion 2: one_db calcula sus medidas por trigger (a partir de sent_at/received_at en UTC y la zona de la cuenta).
--   * sent_at/received_at se guardan tal cual (instante real); sent_at_local/received_at_local son la hora de pared.
--   * total_transit_days = cambios de fecha local; business_* descuentan dias no laborables.
--   * a tiempo: one_db_on_time compara en la unidad del estandar (horas o dias).
ALTER TABLE public.one_db
  ADD COLUMN IF NOT EXISTS total_transit_hours numeric(10,2),
  ADD COLUMN IF NOT EXISTS business_transit_hours numeric(10,2),
  ADD COLUMN IF NOT EXISTS sent_at_local timestamp,
  ADD COLUMN IF NOT EXISTS received_at_local timestamp;

CREATE OR REPLACE FUNCTION public.one_db_compute_transit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_tz text;
BEGIN
  IF NEW.sent_at IS NULL OR NEW.received_at IS NULL THEN
    NEW.total_transit_hours := NULL;
    NEW.total_transit_days := NULL;
    NEW.business_transit_hours := NULL;
    NEW.business_transit_days := NULL;
    NEW.sent_at_local := NULL;
    NEW.received_at_local := NULL;
    RETURN NEW;
  END IF;

  v_tz := COALESCE((SELECT timezone FROM accounts WHERE id = NEW.account_id), 'UTC');
  NEW.sent_at_local     := NEW.sent_at     AT TIME ZONE v_tz;
  NEW.received_at_local := NEW.received_at AT TIME ZONE v_tz;
  NEW.total_transit_hours := ROUND(GREATEST(0, extract(epoch FROM (NEW.received_at - NEW.sent_at)) / 3600.0), 2);
  NEW.total_transit_days  := GREATEST(0, NEW.received_at_local::date - NEW.sent_at_local::date);
  NEW.business_transit_hours := calculate_business_hours(NEW.sent_at, NEW.received_at, NEW.account_id);
  NEW.business_transit_days  := calculate_business_days(NEW.sent_at, NEW.received_at, NEW.account_id);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS one_db_compute_transit ON public.one_db;
CREATE TRIGGER one_db_compute_transit
  BEFORE INSERT OR UPDATE OF sent_at, received_at, account_id ON public.one_db
  FOR EACH ROW EXECUTE FUNCTION public.one_db_compute_transit();

CREATE OR REPLACE FUNCTION public.one_db_on_time(
  p_business_hours numeric, p_business_days integer, p_standard_time numeric, p_time_unit text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_standard_time IS NULL THEN NULL
    WHEN p_time_unit = 'days' THEN p_business_days <= p_standard_time
    ELSE p_business_hours <= p_standard_time
  END
$$;

-- transfer_to_one_db: mismo flujo y validaciones que la version viva, pero sin calcular dias ni desplazar
-- fechas aqui: se inserta el instante tal cual y el trigger de one_db deriva el resto.
CREATE OR REPLACE FUNCTION public.transfer_to_one_db()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_errors TEXT[] := '{}';
  v_account_id UUID;
  v_plan_name TEXT;
  v_carrier_id UUID;
  v_product_id UUID;
  v_carrier_name TEXT;
  v_product_name TEXT;
  v_origin_city_id UUID;
  v_destination_city_id UUID;
  v_origin_city_name TEXT;
  v_destination_city_name TEXT;
  v_new_id UUID;
  v_business_hours NUMERIC;
  v_business_days INTEGER;
  v_delivery_standard NUMERIC;
  v_time_unit TEXT;
  v_origin_pid UUID := NEW.origin_panelist_id;
  v_origin_pname TEXT := NEW.origin_panelist_name;
  v_dest_pid UUID := NEW.destination_panelist_id;
  v_dest_pname TEXT := NEW.destination_panelist_name;
BEGIN
  IF NEW.status = 'received' AND (OLD.status IS NULL OR OLD.status != 'received') AND NEW.transferred_to_one_db_at IS NULL THEN

    IF v_origin_pid IS NULL AND NEW.origin_node_id IS NOT NULL THEN
      SELECT p.id, p.name INTO v_origin_pid, v_origin_pname
        FROM panelists p
       WHERE p.node_id = NEW.origin_node_id AND p.account_id = NEW.account_id
       ORDER BY (p.status = 'active') DESC, p.id
       LIMIT 1;
    END IF;
    IF v_dest_pid IS NULL AND NEW.destination_node_id IS NOT NULL THEN
      SELECT p.id, p.name INTO v_dest_pid, v_dest_pname
        FROM panelists p
       WHERE p.node_id = NEW.destination_node_id AND p.account_id = NEW.account_id
       ORDER BY (p.status = 'active') DESC, p.id
       LIMIT 1;
    END IF;
    IF v_origin_pid IS DISTINCT FROM NEW.origin_panelist_id OR v_dest_pid IS DISTINCT FROM NEW.destination_panelist_id THEN
      UPDATE allocation_plan_details
         SET origin_panelist_id = COALESCE(origin_panelist_id, v_origin_pid),
             origin_panelist_name = COALESCE(origin_panelist_name, v_origin_pname),
             destination_panelist_id = COALESCE(destination_panelist_id, v_dest_pid),
             destination_panelist_name = COALESCE(destination_panelist_name, v_dest_pname)
       WHERE id = NEW.id;
    END IF;

    v_errors := '{}';

    IF NEW.sent_at IS NULL THEN
      v_errors := array_append(v_errors, 'Missing sent date');
    END IF;

    IF NEW.received_at IS NULL THEN
      v_errors := array_append(v_errors, 'Missing received date');
    END IF;

    IF NEW.sent_at IS NOT NULL AND NEW.received_at IS NOT NULL AND NEW.sent_at > NEW.received_at THEN
      v_errors := array_append(v_errors, 'Sent date is after received date');
    END IF;

    IF NEW.tag_id IS NULL OR trim(NEW.tag_id) = '' THEN
      v_errors := array_append(v_errors, 'Missing Tag ID');
    END IF;

    IF v_origin_pid IS NULL THEN
      v_errors := array_append(v_errors, 'Missing origin panelist');
    END IF;

    IF v_dest_pid IS NULL THEN
      v_errors := array_append(v_errors, 'Missing destination panelist');
    END IF;

    IF array_length(v_errors, 1) > 0 THEN
      UPDATE allocation_plan_details
         SET validation_errors = v_errors
       WHERE id = NEW.id;
      RETURN NEW;
    END IF;

    BEGIN
      SELECT ap.account_id, ap.plan_name, ap.carrier_id, ap.product_id
        INTO v_account_id, v_plan_name, v_carrier_id, v_product_id
        FROM allocation_plans ap
       WHERE ap.id = NEW.plan_id;

      SELECT c.name INTO v_carrier_name FROM carriers c WHERE c.id = v_carrier_id;
      SELECT p.description INTO v_product_name FROM products p WHERE p.id = v_product_id;

      SELECT n.city_id INTO v_origin_city_id FROM nodes n WHERE n.id = NEW.origin_node_id;
      SELECT n.city_id INTO v_destination_city_id FROM nodes n WHERE n.id = NEW.destination_node_id;

      SELECT c.name INTO v_origin_city_name FROM cities c WHERE c.id = v_origin_city_id;
      SELECT c.name INTO v_destination_city_name FROM cities c WHERE c.id = v_destination_city_id;

      SELECT ds.standard_time, ds.time_unit INTO v_delivery_standard, v_time_unit
        FROM delivery_standards ds
       WHERE ds.carrier_id = v_carrier_id
         AND ds.product_id = v_product_id
         AND ds.origin_city_id = v_origin_city_id
         AND ds.destination_city_id = v_destination_city_id
       LIMIT 1;

      -- El trigger one_db_compute_transit rellena horas/dias/locales a partir de sent_at/received_at
      INSERT INTO one_db (
        account_id, allocation_detail_id, tag_id, plan_name, carrier_name, product_name,
        origin_city_name, destination_city_name, sent_at, received_at, source_data_snapshot
      ) VALUES (
        v_account_id, NEW.id, NEW.tag_id, v_plan_name, v_carrier_name, v_product_name,
        v_origin_city_name, v_destination_city_name, NEW.sent_at, NEW.received_at,
        to_jsonb(NEW)
      )
      RETURNING id, business_transit_hours, business_transit_days
        INTO v_new_id, v_business_hours, v_business_days;

      UPDATE one_db
         SET on_time_delivery = one_db_on_time(v_business_hours, v_business_days, v_delivery_standard, v_time_unit)
       WHERE id = v_new_id;

      UPDATE allocation_plan_details
         SET transferred_to_one_db_at = NOW(),
             validation_errors = NULL,
             transfer_error_message = NULL
       WHERE id = NEW.id;

    EXCEPTION WHEN OTHERS THEN
      UPDATE allocation_plan_details
         SET transfer_error_message = SQLERRM
       WHERE id = NEW.id;
      RAISE WARNING 'Transfer to ONE_DB failed for allocation_detail_id %: %', NEW.id, SQLERRM;
    END;

  END IF;

  RETURN NEW;
END;
$function$;

-- Al cambiar un estandar se recalcula "a tiempo" de los envios de esa ruta. Corrige el casado de producto:
-- one_db.product_name guarda products.description (no products.code).
CREATE OR REPLACE FUNCTION public.recalculate_on_time_delivery_on_sla_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  UPDATE one_db
     SET on_time_delivery = one_db_on_time(one_db.business_transit_hours, one_db.business_transit_days, NEW.standard_time, NEW.time_unit)
   WHERE one_db.account_id = NEW.account_id
     AND one_db.carrier_name IN (SELECT name FROM carriers WHERE id = NEW.carrier_id)
     AND one_db.product_name IN (SELECT description FROM products WHERE id = NEW.product_id)
     AND one_db.origin_city_name IN (SELECT name FROM cities WHERE id = NEW.origin_city_id)
     AND one_db.destination_city_name IN (SELECT name FROM cities WHERE id = NEW.destination_city_id);
  RETURN NEW;
END;
$function$;

-- Seccion 3: correccion de los datos existentes de one_db.
--   Las filas antiguas tienen sent_at/received_at desplazados por el offset de la cuenta (el transfer viejo lo
--   restaba) y NULL en las columnas nuevas. one_db_backfill_transit():
--     (a) copia sent_at/received_at del detalle (allocation_plan_details) cuando existe, tiene ambas fechas y difieren;
--     (b) UPDATE ... SET sent_at = sent_at para que el trigger recalcule todas las medidas (devuelve estas filas);
--     (c) recalcula on_time_delivery: por ids si la fila tiene detalle; por nombres (acotado por cuenta) si no.
--         Filas sin estandar => NULL.
CREATE OR REPLACE FUNCTION public.one_db_backfill_transit()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows integer;
BEGIN
  -- (a) fechas reales desde el detalle (ambas a la vez: respeta one_db_valid_timestamps)
  UPDATE one_db o
     SET sent_at = d.sent_at, received_at = d.received_at
    FROM allocation_plan_details d
   WHERE d.id = o.allocation_detail_id
     AND d.sent_at IS NOT NULL AND d.received_at IS NOT NULL AND d.sent_at <= d.received_at
     AND (o.sent_at IS DISTINCT FROM d.sent_at OR o.received_at IS DISTINCT FROM d.received_at);

  -- (b) el trigger one_db_compute_transit recalcula horas/dias/locales de todas las filas
  UPDATE one_db SET sent_at = sent_at;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  -- (c1) filas con detalle: estandar por ids
  UPDATE one_db o
     SET on_time_delivery = one_db_on_time(o.business_transit_hours, o.business_transit_days, ds.standard_time, ds.time_unit)
    FROM one_db o4  -- re-join de la fila: un JOIN del FROM no puede referenciar el destino del UPDATE ("o")
    JOIN allocation_plan_details d ON d.id = o4.allocation_detail_id
    LEFT JOIN allocation_plans ap ON ap.id = d.plan_id AND ap.account_id = o4.account_id
    LEFT JOIN nodes onode ON onode.id = d.origin_node_id
    LEFT JOIN nodes dnode ON dnode.id = d.destination_node_id
    LEFT JOIN LATERAL (
      SELECT s.standard_time, s.time_unit
        FROM delivery_standards s
       WHERE s.account_id = o4.account_id
         AND s.carrier_id = ap.carrier_id
         AND s.product_id = ap.product_id
         AND s.origin_city_id = onode.city_id
         AND s.destination_city_id = dnode.city_id
       ORDER BY s.created_at, s.id
       LIMIT 1
    ) ds ON true
   WHERE o.id = o4.id;

  -- (c2) filas sin detalle: estandar por nombres dentro de la cuenta
  UPDATE one_db o
     SET on_time_delivery = one_db_on_time(o.business_transit_hours, o.business_transit_days, ds.standard_time, ds.time_unit)
    FROM (SELECT o2.id AS oid FROM one_db o2
           WHERE NOT EXISTS (SELECT 1 FROM allocation_plan_details d WHERE d.id = o2.allocation_detail_id)) nd
    LEFT JOIN LATERAL (
      SELECT s.standard_time, s.time_unit
        FROM delivery_standards s
        JOIN carriers c  ON c.id  = s.carrier_id
        JOIN products p  ON p.id  = s.product_id
        JOIN cities co   ON co.id = s.origin_city_id
        JOIN cities cd   ON cd.id = s.destination_city_id
        JOIN one_db o3   ON o3.id = nd.oid  -- re-join de la fila: el LATERAL no ve "o" (destino del UPDATE) en un FROM con subconsulta
       WHERE s.account_id = o3.account_id
         AND btrim(c.name) = btrim(o3.carrier_name)
         AND btrim(p.description) = btrim(o3.product_name)
         AND btrim(co.name) = btrim(o3.origin_city_name)
         AND btrim(cd.name) = btrim(o3.destination_city_name)
       ORDER BY s.created_at, s.id
       LIMIT 1
    ) ds ON true
   WHERE o.id = nd.oid;

  RETURN v_rows;
END $$;

-- Funcion de mantenimiento: no debe ser un RPC publico (SECURITY DEFINER + PostgREST).
REVOKE ALL ON FUNCTION public.one_db_backfill_transit() FROM PUBLIC, anon, authenticated;

-- Aparte: al editar un estandar, el recalculo de one_db debe correr con permisos propios; con RLS un admin de
-- cuenta (no superadmin) no veia las filas de one_db y la actualizacion era un no-op silencioso.
-- Se reemite la definicion de la seccion 2 anadiendo solo SECURITY DEFINER y SET search_path.
CREATE OR REPLACE FUNCTION public.recalculate_on_time_delivery_on_sla_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  UPDATE one_db
     SET on_time_delivery = one_db_on_time(one_db.business_transit_hours, one_db.business_transit_days, NEW.standard_time, NEW.time_unit)
   WHERE one_db.account_id = NEW.account_id
     AND EXISTS (SELECT 1 FROM carriers cx WHERE cx.id = NEW.carrier_id AND cx.account_id = NEW.account_id)
     AND btrim(one_db.carrier_name) IN (SELECT btrim(name) FROM carriers WHERE id = NEW.carrier_id)
     AND btrim(one_db.product_name) IN (SELECT btrim(description) FROM products WHERE id = NEW.product_id)
     AND btrim(one_db.origin_city_name) IN (SELECT btrim(name) FROM cities WHERE id = NEW.origin_city_id)
     AND btrim(one_db.destination_city_name) IN (SELECT btrim(name) FROM cities WHERE id = NEW.destination_city_id);
  RETURN NEW;
END;
$function$;

-- Aparte: con el recalculo SECURITY DEFINER, la politica de INSERT dejaba a cualquier admin crear estandares con
-- un account_id ajeno. Se acota a su propia cuenta (superadmin sin limite); se mantienen los roles (public).
DROP POLICY IF EXISTS delivery_standards_insert ON public.delivery_standards;
CREATE POLICY delivery_standards_insert ON public.delivery_standards AS PERMISSIVE FOR INSERT TO public
  WITH CHECK (current_user_role() = 'superadmin'
              OR (current_user_role() = 'admin' AND account_id = current_user_account_id()));

SELECT public.one_db_backfill_transit();
