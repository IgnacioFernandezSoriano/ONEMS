-- El calculo de 'a tiempo' comparaba dias laborables con standard_time sin mirar time_unit:
-- un estandar de 6 horas se leia como 6 dias. Ahora se convierte a dias (horas/24), igual que
-- useComplianceData/useJKPerformance. Resto de la funcion identico a la version viva.
CREATE OR REPLACE FUNCTION public.transfer_to_one_db()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_errors TEXT[] := '{}';
  v_account_id UUID;
  v_account_timezone TEXT;
  v_plan_name TEXT;
  v_carrier_id UUID;
  v_product_id UUID;
  v_carrier_name TEXT;
  v_product_name TEXT;
  v_origin_city_id UUID;
  v_destination_city_id UUID;
  v_origin_city_name TEXT;
  v_destination_city_name TEXT;
  v_total_transit_days INTEGER;
  v_business_transit_days INTEGER;
  v_on_time_delivery BOOLEAN := NULL;
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
      SELECT ap.account_id, ap.plan_name, ap.carrier_id, ap.product_id, a.timezone
        INTO v_account_id, v_plan_name, v_carrier_id, v_product_id, v_account_timezone
        FROM allocation_plans ap
        JOIN accounts a ON a.id = ap.account_id
       WHERE ap.id = NEW.plan_id;

      IF v_account_timezone IS NULL THEN
        v_account_timezone := 'UTC';
      END IF;

      SELECT c.name INTO v_carrier_name FROM carriers c WHERE c.id = v_carrier_id;
      SELECT p.description INTO v_product_name FROM products p WHERE p.id = v_product_id;

      SELECT n.city_id INTO v_origin_city_id FROM nodes n WHERE n.id = NEW.origin_node_id;
      SELECT n.city_id INTO v_destination_city_id FROM nodes n WHERE n.id = NEW.destination_node_id;

      SELECT c.name INTO v_origin_city_name FROM cities c WHERE c.id = v_origin_city_id;
      SELECT c.name INTO v_destination_city_name FROM cities c WHERE c.id = v_destination_city_id;

      v_total_transit_days := EXTRACT(DAY FROM (NEW.received_at - NEW.sent_at))::INTEGER;
      v_business_transit_days := calculate_business_days(NEW.sent_at, NEW.received_at, v_account_id);

      SELECT ds.standard_time, ds.time_unit INTO v_delivery_standard, v_time_unit
        FROM delivery_standards ds
       WHERE ds.carrier_id = v_carrier_id
         AND ds.product_id = v_product_id
         AND ds.origin_city_id = v_origin_city_id
         AND ds.destination_city_id = v_destination_city_id
       LIMIT 1;

      IF v_delivery_standard IS NOT NULL THEN
        -- El estandar puede estar en horas o en dias; se pasa a dias (igual que los informes)
        v_on_time_delivery := (v_business_transit_days <=
          CASE WHEN v_time_unit = 'days' THEN v_delivery_standard ELSE v_delivery_standard / 24.0 END);
      END IF;

      INSERT INTO one_db (
        account_id, allocation_detail_id, tag_id, plan_name, carrier_name, product_name,
        origin_city_name, destination_city_name, sent_at, received_at,
        total_transit_days, business_transit_days, on_time_delivery, source_data_snapshot
      ) VALUES (
        v_account_id, NEW.id, NEW.tag_id, v_plan_name, v_carrier_name, v_product_name,
        v_origin_city_name, v_destination_city_name,
        (NEW.sent_at AT TIME ZONE 'UTC' AT TIME ZONE v_account_timezone),
        (NEW.received_at AT TIME ZONE 'UTC' AT TIME ZONE v_account_timezone),
        v_total_transit_days, v_business_transit_days, v_on_time_delivery,
        to_jsonb(NEW)
      );

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

