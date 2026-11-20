-- Carrier Link fase 0, tarea 2: tiempo de equivalencia en el calculo de transito.
-- Spec: docs/superpowers/specs/2026-11-19-carrier-link-design.md (D9, R20)
--
-- Una muestra del transportista (one_db.source = 'carrier') solo mide entre su primera y su ultima lectura; el
-- estandar lleva aparte el tiempo de primer y ultimo tramo (cl_first_mile_time / cl_last_mile_time, en su unidad).
-- Esa "equivalencia" se suma al tiempo medido para que el E2E sea comparable al de panelistas.
--
-- Filas panelist: el calculo es EXACTAMENTE el de 20261029120000_one_db_business_time.sql (cuerpo copiado literal);
-- measured_* quedan NULL y la equivalencia se ignora.
-- Filas carrier: measured_* = lo calculado; los tiempos de transito = medido + equivalencia. Siempre se parte de
-- sent_at/received_at, nunca del valor previo, asi que repetir un UPDATE no acumula.
-- No toca allocation_plans, allocation_plan_details, transfer_to_one_db, el ETL RFID ni
-- recalculate_on_time_delivery_on_sla_change.

-- ---------------------------------------------------------------- calculo de transito en one_db
CREATE OR REPLACE FUNCTION public.one_db_compute_transit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, extensions
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
    NEW.measured_total_hours := NULL;
    NEW.measured_total_days := NULL;
    NEW.measured_business_hours := NULL;
    NEW.measured_business_days := NULL;
    RETURN NEW;
  END IF;

  v_tz := COALESCE((SELECT timezone FROM accounts WHERE id = NEW.account_id), 'UTC');
  NEW.sent_at_local     := NEW.sent_at     AT TIME ZONE v_tz;
  NEW.received_at_local := NEW.received_at AT TIME ZONE v_tz;
  NEW.total_transit_hours := ROUND(GREATEST(0, extract(epoch FROM (NEW.received_at - NEW.sent_at)) / 3600.0), 2);
  NEW.total_transit_days  := GREATEST(0, NEW.received_at_local::date - NEW.sent_at_local::date);
  NEW.business_transit_hours := calculate_business_hours(NEW.sent_at, NEW.received_at, NEW.account_id);
  NEW.business_transit_days  := calculate_business_days(NEW.sent_at, NEW.received_at, NEW.account_id);

  -- Carrier Link: hasta aqui, el calculo de siempre. Solo para muestras del transportista se guarda lo medido y se
  -- suma la equivalencia (primer + ultimo tramo).
  IF NEW.source = 'carrier' THEN
    NEW.measured_total_hours    := NEW.total_transit_hours;
    NEW.measured_total_days     := NEW.total_transit_days;
    NEW.measured_business_hours := NEW.business_transit_hours;
    NEW.measured_business_days  := NEW.business_transit_days;
    NEW.total_transit_hours    := NEW.total_transit_hours    + COALESCE(NEW.equivalence_hours, 0);
    NEW.business_transit_hours := NEW.business_transit_hours + COALESCE(NEW.equivalence_hours, 0);
    NEW.total_transit_days     := NEW.total_transit_days     + COALESCE(NEW.equivalence_days, 0);
    NEW.business_transit_days  := NEW.business_transit_days  + COALESCE(NEW.equivalence_days, 0);
  ELSE
    NEW.measured_total_hours    := NULL;
    NEW.measured_total_days     := NULL;
    NEW.measured_business_hours := NULL;
    NEW.measured_business_days  := NULL;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS one_db_compute_transit ON public.one_db;
CREATE TRIGGER one_db_compute_transit
  BEFORE INSERT OR UPDATE OF sent_at, received_at, account_id, equivalence_hours, equivalence_days ON public.one_db
  FOR EACH ROW EXECUTE FUNCTION public.one_db_compute_transit();

-- ---------------------------------------------------------------- equivalencia de un estandar
-- t = primer tramo + ultimo tramo, en la unidad del estandar. Dias -> (t*24 h, round(t) dias); horas -> (t, round(t/24)).
CREATE OR REPLACE FUNCTION public.cl_equivalence(p_standard_id uuid)
RETURNS TABLE (eq_hours numeric, eq_days integer)
LANGUAGE sql
STABLE
SET search_path = public, extensions
AS $$
  SELECT CASE WHEN ds.time_unit = 'days' THEN t * 24 ELSE t END,
         (CASE WHEN ds.time_unit = 'days' THEN round(t) ELSE round(t / 24.0) END)::integer
    FROM public.delivery_standards ds
   CROSS JOIN LATERAL (SELECT ds.cl_first_mile_time + ds.cl_last_mile_time AS t) x
   WHERE ds.id = p_standard_id;
$$;

REVOKE ALL ON FUNCTION public.cl_equivalence(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_equivalence(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------- propagacion al cambiar un estandar
-- AFTER INSERT OR UPDATE en delivery_standards. Para las filas source = 'carrier' de la ruta del estandar:
--   1) fija equivalence_hours/days (dispara one_db_compute_transit: medido + equivalencia, desde sent/received);
--   2) recalcula on_time_delivery con esos tiempos y el estandar (one_db_on_time), aqui mismo.
-- El paso 2 no se delega en trigger_recalculate_on_time_on_sla_change: esa funcion no garantiza permisos propios
-- (en el repo puede ser SECURITY INVOKER y la unica politica UPDATE de one_db es de superadmin), asi que para un
-- editor no superadmin podria tocar 0 filas y dejar on_time viejo con tiempos nuevos. Ese trigger se sigue
-- ejecutando despues (orden alfabetico) y, si llega a las filas, escribe el mismo valor.
-- Ruta: transportista por carrier_id, cuenta, y producto/ciudades por nombre con btrim (la funcion existente compara
-- sin btrim; aqui se normalizan espacios, y como el on_time de estas filas se calcula aqui es coherente).
-- SECURITY DEFINER: actua sobre one_db sin depender de la RLS del editor del estandar.
CREATE OR REPLACE FUNCTION public.cl_equivalence_on_sla_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_h numeric;
  v_d integer;
BEGIN
  SELECT e.eq_hours, e.eq_days INTO v_h, v_d FROM public.cl_equivalence(NEW.id) e;

  UPDATE public.one_db
     SET equivalence_hours = v_h,
         equivalence_days  = v_d
   WHERE one_db.source = 'carrier'
     AND one_db.account_id = NEW.account_id
     AND one_db.carrier_id = NEW.carrier_id
     AND EXISTS (SELECT 1 FROM carriers cx WHERE cx.id = NEW.carrier_id AND cx.account_id = NEW.account_id)
     AND btrim(one_db.product_name) IN (SELECT btrim(description) FROM products WHERE id = NEW.product_id)
     AND btrim(one_db.origin_city_name) IN (SELECT btrim(name) FROM cities WHERE id = NEW.origin_city_id)
     AND btrim(one_db.destination_city_name) IN (SELECT btrim(name) FROM cities WHERE id = NEW.destination_city_id)
     AND (one_db.equivalence_hours IS DISTINCT FROM v_h OR one_db.equivalence_days IS DISTINCT FROM v_d);

  UPDATE public.one_db
     SET on_time_delivery = one_db_on_time(one_db.business_transit_hours, one_db.business_transit_days, NEW.standard_time, NEW.time_unit)
   WHERE one_db.source = 'carrier'
     AND one_db.account_id = NEW.account_id
     AND one_db.carrier_id = NEW.carrier_id
     AND EXISTS (SELECT 1 FROM carriers cx WHERE cx.id = NEW.carrier_id AND cx.account_id = NEW.account_id)
     AND btrim(one_db.product_name) IN (SELECT btrim(description) FROM products WHERE id = NEW.product_id)
     AND btrim(one_db.origin_city_name) IN (SELECT btrim(name) FROM cities WHERE id = NEW.origin_city_id)
     AND btrim(one_db.destination_city_name) IN (SELECT btrim(name) FROM cities WHERE id = NEW.destination_city_id);
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION public.cl_equivalence_on_sla_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS cl_equivalence_on_sla_change ON public.delivery_standards;
CREATE TRIGGER cl_equivalence_on_sla_change
  AFTER INSERT OR UPDATE ON public.delivery_standards
  FOR EACH ROW EXECUTE FUNCTION public.cl_equivalence_on_sla_change();
