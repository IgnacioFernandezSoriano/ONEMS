-- 2026-10-28: etiquetas homogéneas en emisión y recepción + recepción por bot que no se podía registrar.
--
-- Problema 1: cada panelista escribía la etiqueta a su manera ("10758", "00010758", "000010758") y el sistema
--             guardaba el texto tal cual, así que origen y destino nunca coincidían.
-- Problema 2: el trigger transfer_to_one_db, al faltar destination_panelist_id, hacía UPDATE status='invalid'
--             (y 'transfer_error' en el EXCEPTION), estados que el CHECK de la tabla no admite: el UPDATE de
--             la recepción fallaba entero y no quedaba nada grabado.
--
-- Solución:
--   a) normalize_tag(): forma canónica única (solo letras/dígitos, mayúsculas; si es numérica, sin ceros a la
--      izquierda y rellenada a 8 dígitos; sin dígitos o vacía => NULL = inválida).
--   b) Trigger BEFORE INSERT/UPDATE OF tag_id que aplica la forma canónica a TODO lo que se escribe
--      (bot, pantalla, importaciones) y rechaza etiquetas inválidas. idtag conserva lo que escribió la persona.
--   c) transfer_to_one_db: resuelve el panelista de origen/destino desde el nodo si falta, nunca pone un estado
--      fuera del CHECK (deja validation_errors / transfer_error_message y conserva 'received').
--   d) Corrección única de las etiquetas ya guardadas.

-- ---------------------------------------------------------------------------------------------------------
-- a) Forma canónica de una etiqueta
-- ---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.normalize_tag(p_raw text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
           WHEN c = '' OR c !~ '[0-9]' THEN NULL                 -- vacía o sin ningún dígito: no es una etiqueta
           WHEN c ~ '^[0-9]+$' THEN
             CASE WHEN ltrim(c, '0') = '' THEN NULL              -- solo ceros
                  WHEN length(ltrim(c, '0')) >= 8 THEN ltrim(c, '0')
                  ELSE lpad(ltrim(c, '0'), 8, '0') END
           ELSE c
         END
  FROM (SELECT upper(regexp_replace(coalesce(p_raw, ''), '[^A-Za-z0-9]', '', 'g'))) s(c);
$$;

COMMENT ON FUNCTION public.normalize_tag(text) IS
  'Forma canónica de una etiqueta de envío: solo letras y dígitos en mayúsculas; si es numérica, sin ceros a la izquierda y rellenada a 8 dígitos. NULL si no es una etiqueta válida.';

GRANT EXECUTE ON FUNCTION public.normalize_tag(text) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------
-- b) Toda etiqueta escrita en allocation_plan_details queda en forma canónica
-- ---------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tg_normalize_allocation_tag()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_canon text;
BEGIN
  IF NEW.tag_id IS NULL OR btrim(NEW.tag_id) = '' THEN
    NEW.tag_id := NULL;
    RETURN NEW;
  END IF;
  v_canon := public.normalize_tag(NEW.tag_id);
  IF v_canon IS NULL THEN
    RAISE EXCEPTION 'Etiqueta no válida: "%"', NEW.tag_id USING ERRCODE = 'check_violation';
  END IF;
  -- idtag conserva lo que escribió la persona (solo si nadie lo ha rellenado ya)
  IF NEW.idtag IS NULL THEN
    NEW.idtag := btrim(NEW.tag_id);
  END IF;
  NEW.tag_id := v_canon;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS normalize_allocation_tag ON public.allocation_plan_details;
CREATE TRIGGER normalize_allocation_tag
  BEFORE INSERT OR UPDATE OF tag_id ON public.allocation_plan_details
  FOR EACH ROW EXECUTE FUNCTION public.tg_normalize_allocation_tag();

-- ---------------------------------------------------------------------------------------------------------
-- c) transfer_to_one_db: nunca deja la fila en un estado que el CHECK no admite
-- ---------------------------------------------------------------------------------------------------------
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
  v_origin_pid UUID := NEW.origin_panelist_id;
  v_origin_pname TEXT := NEW.origin_panelist_name;
  v_dest_pid UUID := NEW.destination_panelist_id;
  v_dest_pname TEXT := NEW.destination_panelist_name;
BEGIN
  IF NEW.status = 'received' AND (OLD.status IS NULL OR OLD.status != 'received') AND NEW.transferred_to_one_db_at IS NULL THEN

    -- 2026-10-28: las filas generadas por el plan no llevan los panelistas; se resuelven desde el nodo.
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
      -- Este UPDATE vuelve a disparar el trigger, pero con OLD.status = 'received' ya no entra aquí.
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
      -- Antes: status = 'invalid' (no admitido por el CHECK => fallaba toda la recepción).
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

      SELECT ds.standard_time INTO v_delivery_standard
        FROM delivery_standards ds
       WHERE ds.carrier_id = v_carrier_id
         AND ds.product_id = v_product_id
         AND ds.origin_city_id = v_origin_city_id
         AND ds.destination_city_id = v_destination_city_id
       LIMIT 1;

      IF v_delivery_standard IS NOT NULL THEN
        v_on_time_delivery := (v_business_transit_days <= v_delivery_standard);
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
      -- Antes: status = 'transfer_error' (tampoco admitido por el CHECK).
      UPDATE allocation_plan_details
         SET transfer_error_message = SQLERRM
       WHERE id = NEW.id;
      RAISE WARNING 'Transfer to ONE_DB failed for allocation_detail_id %: %', NEW.id, SQLERRM;
    END;

  END IF;

  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------------------------------------------
-- d) Etiquetas ya guardadas: a forma canónica (las que no se pueden normalizar se dejan y se listan aparte)
-- ---------------------------------------------------------------------------------------------------------
UPDATE public.allocation_plan_details
   SET tag_id = public.normalize_tag(tag_id)
 WHERE tag_id IS NOT NULL
   AND public.normalize_tag(tag_id) IS NOT NULL
   AND public.normalize_tag(tag_id) IS DISTINCT FROM tag_id;
