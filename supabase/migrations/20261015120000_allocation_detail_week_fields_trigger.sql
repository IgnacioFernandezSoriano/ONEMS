-- Keep week_number / month / year in step with fecha_programada.
--
-- Several paths move a shipment's date without touching the derived fields:
-- rpc_balance_node_load_by_period (Node Load Balancing), reschedule_detail and
-- apply_reassignment_proposal ('shift_date'). The stale values then put the
-- shipment in the wrong week/month in v_node_load_analysis and in the Allocation
-- Plans list. Deriving them in a trigger covers every current and future path.
--
-- week_number = ISO week, month/year = calendar, matching the frontend generator.

CREATE OR REPLACE FUNCTION public.set_allocation_detail_week_fields()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.fecha_programada IS NOT NULL THEN
    NEW.week_number := EXTRACT(WEEK  FROM NEW.fecha_programada)::int;
    NEW.month       := EXTRACT(MONTH FROM NEW.fecha_programada)::int;
    NEW.year        := EXTRACT(YEAR  FROM NEW.fecha_programada)::int;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_allocation_detail_week_fields ON public.allocation_plan_details;

CREATE TRIGGER set_allocation_detail_week_fields
  BEFORE INSERT OR UPDATE OF fecha_programada ON public.allocation_plan_details
  FOR EACH ROW EXECUTE FUNCTION public.set_allocation_detail_week_fields();
