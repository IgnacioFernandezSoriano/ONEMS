-- Balanceo de carga por periodo: fechas seguras.
--
-- Antes, rpc_balance_node_load_by_period construia las celdas nodo x semana desde el LUNES de la semana
-- en que empieza el periodo (date_trunc('week', p_start_date)). Con un periodo "octubre" (1/10, jueves) la
-- primera celda era la semana del 28/09: la funcion movia envios pendientes a una fecha anterior al plan y
-- anterior a hoy (2026-10-26: 9 envios de Kenya al 28/09, que aparecieron como "4 semanas atrasados").
-- Tampoco respetaba fines de semana ni dias no laborables de la cuenta, ni dejaba quien lo ejecuto.
--
-- Ahora:
--   * no se programa nada antes de GREATEST(p_start_date, hoy en la zona horaria de la cuenta);
--   * la fecha nueva cae siempre dentro de [inicio efectivo, p_end_date];
--   * se evita sabado, domingo y non_working_days de la cuenta (se busca el dia laborable mas cercano dentro
--     de la celda; si la celda no tiene ninguno, la celda no existe);
--   * se guardan reassigned_by = auth.uid() y original_fecha_programada / original_origin_node_id (solo la
--     primera vez, para no perder el valor del plan).
-- La firma y la forma del JSON devuelto no cambian (el frontend no se toca).

CREATE OR REPLACE FUNCTION public.working_day_in_range(
  p_account_id uuid, p_preferred date, p_from date, p_to date)
RETURNS date
LANGUAGE sql STABLE
SET search_path = public
AS $$
  -- Dia laborable de la cuenta mas cercano a p_preferred dentro de [p_from, p_to]:
  -- primero el propio p_preferred, luego hacia delante, luego hacia atras. NULL si no hay ninguno.
  WITH days AS (
    SELECT d::date AS d
      FROM generate_series(p_from, p_to, interval '1 day') d
     WHERE EXTRACT(isodow FROM d) <= 5
       AND NOT EXISTS (SELECT 1 FROM public.non_working_days n
                        WHERE n.account_id = p_account_id AND n.date = d::date)
  )
  SELECT d FROM days
   ORDER BY CASE WHEN d = p_preferred THEN 0 WHEN d > p_preferred THEN 1 ELSE 2 END,
            abs(d - p_preferred)
   LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.rpc_balance_node_load_by_period(
  p_city_id uuid, p_start_date date, p_end_date date, p_apply_changes boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_account_id UUID;
  v_tz TEXT;
  v_today DATE;
  v_from DATE;
  v_total_shipments INTEGER;
  v_total_cells INTEGER;
  v_target_per_cell INTEGER;
  v_remainder INTEGER;
  v_stddev_before NUMERIC;
  v_stddev_after NUMERIC;
  v_movements JSONB := '[]'::JSONB;
  v_movements_count INTEGER := 0;
  v_improvement NUMERIC;
  v_matrix_before JSONB;
  v_matrix_after JSONB;
  v_cell_index INTEGER := 0;
  v_shipments_assigned INTEGER := 0;
  v_current_cell_target INTEGER;
BEGIN
  SELECT c.account_id, COALESCE(a.timezone, 'UTC')
    INTO v_account_id, v_tz
    FROM public.cities c JOIN public.accounts a ON a.id = c.account_id
   WHERE c.id = p_city_id;

  IF v_account_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'City not found', 'movements_count', 0,
      'stddev_before', 0, 'stddev_after', 0, 'improvement_percentage', 0, 'movements', '[]'::jsonb,
      'matrix_before', '[]'::jsonb, 'matrix_after', '[]'::jsonb, 'message', 'City not found');
  END IF;

  v_today := (now() AT TIME ZONE v_tz)::date;
  v_from  := GREATEST(p_start_date, v_today);   -- nunca se programa en el pasado

  DROP TABLE IF EXISTS temp_cells;
  DROP TABLE IF EXISTS temp_shipments;

  -- Celdas nodo x semana. Solo semanas con al menos un dia laborable dentro de [v_from, p_end_date].
  CREATE TEMP TABLE temp_cells (
    cell_id SERIAL PRIMARY KEY,
    node_id UUID,
    node_code TEXT,
    week_num INTEGER,
    week_start DATE,      -- lunes ISO de la semana (para conservar el dia de la semana del envio)
    week_end DATE,
    cell_from DATE,       -- limites efectivos de la celda
    cell_to DATE,
    current_load INTEGER,
    target_load INTEGER,
    new_load INTEGER DEFAULT 0
  ) ON COMMIT DROP;

  INSERT INTO temp_cells (node_id, node_code, week_num, week_start, week_end, cell_from, cell_to, current_load)
  SELECT n.id, n.auto_id, w.week_num, ws.week_start, w.week_end, w.cell_from, w.cell_to,
         COUNT(DISTINCT apd.id)
    FROM public.nodes n
   CROSS JOIN (
     SELECT generate_series(date_trunc('week', v_from::timestamp),
                            date_trunc('week', p_end_date::timestamp),
                            '1 week'::interval)::date AS week_start) ws
   CROSS JOIN LATERAL (
     SELECT (ws.week_start + 6)::date AS week_end,
            EXTRACT(WEEK FROM ws.week_start)::int AS week_num,
            GREATEST(ws.week_start, v_from) AS cell_from,
            LEAST((ws.week_start + 6)::date, p_end_date) AS cell_to) w
    LEFT JOIN public.allocation_plan_details apd
      ON apd.origin_node_id = n.id
     AND apd.fecha_programada BETWEEN w.cell_from AND w.cell_to
     AND apd.status = 'pending'
   WHERE n.city_id = p_city_id
     AND n.account_id = v_account_id
     AND w.cell_from <= w.cell_to
     AND public.working_day_in_range(v_account_id, w.cell_from, w.cell_from, w.cell_to) IS NOT NULL
   GROUP BY n.id, n.auto_id, w.week_num, ws.week_start, w.week_end, w.cell_from, w.cell_to
   ORDER BY n.auto_id, ws.week_start;

  -- Envios a repartir: pendientes del periodo pedido (si el periodo empieza en el pasado, los atrasados
  -- tambien entran y se mueven hacia delante, nunca hacia atras).
  CREATE TEMP TABLE temp_shipments (
    shipment_id UUID PRIMARY KEY,
    current_node_id UUID,
    current_week_num INTEGER,
    fecha_programada DATE,
    assigned_cell_id INTEGER,
    new_date DATE,
    row_num INTEGER
  ) ON COMMIT DROP;

  INSERT INTO temp_shipments (shipment_id, current_node_id, current_week_num, fecha_programada, row_num)
  SELECT apd.id, apd.origin_node_id, EXTRACT(WEEK FROM apd.fecha_programada)::int, apd.fecha_programada,
         ROW_NUMBER() OVER (ORDER BY apd.fecha_programada, apd.id)
    FROM public.allocation_plan_details apd
    JOIN public.nodes n ON n.id = apd.origin_node_id
   WHERE n.city_id = p_city_id
     AND apd.account_id = v_account_id
     AND apd.fecha_programada BETWEEN p_start_date AND p_end_date
     AND apd.status = 'pending';

  SELECT COUNT(*), COALESCE(STDDEV(current_load), 0)
    INTO v_total_cells, v_stddev_before
    FROM temp_cells;
  SELECT COUNT(*) INTO v_total_shipments FROM temp_shipments;

  SELECT jsonb_agg(jsonb_build_object('node_code', node_code, 'week_num', week_num, 'load_count', current_load)
                   ORDER BY node_code, week_num)
    INTO v_matrix_before FROM temp_cells;

  IF COALESCE(v_total_shipments, 0) = 0 OR COALESCE(v_total_cells, 0) = 0 THEN
    RETURN jsonb_build_object('success', true,
      'message', CASE WHEN COALESCE(v_total_cells, 0) = 0
                      THEN 'No working days left in the specified period'
                      ELSE 'No shipments found in the specified period' END,
      'movements_count', 0, 'stddev_before', 0, 'stddev_after', 0, 'improvement_percentage', 0,
      'movements', '[]'::jsonb,
      'matrix_before', COALESCE(v_matrix_before, '[]'::jsonb),
      'matrix_after', COALESCE(v_matrix_before, '[]'::jsonb));
  END IF;

  v_target_per_cell := FLOOR(v_total_shipments::numeric / v_total_cells::numeric);
  v_remainder := v_total_shipments - (v_target_per_cell * v_total_cells);

  UPDATE temp_cells
     SET target_load = CASE WHEN cell_id <= v_remainder THEN v_target_per_cell + 1 ELSE v_target_per_cell END
   WHERE TRUE;

  FOR v_cell_index IN SELECT cell_id FROM temp_cells ORDER BY cell_id LOOP
    SELECT target_load INTO v_current_cell_target FROM temp_cells WHERE cell_id = v_cell_index;
    UPDATE temp_shipments
       SET assigned_cell_id = v_cell_index
     WHERE assigned_cell_id IS NULL
       AND row_num > v_shipments_assigned
       AND row_num <= v_shipments_assigned + v_current_cell_target;
    v_shipments_assigned := v_shipments_assigned + v_current_cell_target;
    UPDATE temp_cells SET new_load = v_current_cell_target WHERE cell_id = v_cell_index;
    EXIT WHEN v_shipments_assigned >= v_total_shipments;
  END LOOP;

  -- Fecha nueva: mismo dia de la semana que tenia el envio, acotada a la celda y movida al dia laborable
  -- mas cercano. Si no hay dia valido (no deberia: la celda existe porque lo tiene), no se mueve.
  UPDATE temp_shipments ts
     SET new_date = public.working_day_in_range(
           v_account_id,
           (c.week_start + (ts.fecha_programada - date_trunc('week', ts.fecha_programada)::date))::date,
           c.cell_from, c.cell_to)
    FROM temp_cells c
   WHERE c.cell_id = ts.assigned_cell_id;

  IF p_apply_changes THEN
    UPDATE public.allocation_plan_details apd
       SET origin_node_id = c.node_id,
           fecha_programada = ts.new_date,
           original_fecha_programada = COALESCE(apd.original_fecha_programada, apd.fecha_programada),
           original_origin_node_id = COALESCE(apd.original_origin_node_id, apd.origin_node_id),
           reassignment_reason = 'rebalancing',
           reassigned_at = NOW(),
           reassigned_by = auth.uid(),
           updated_at = NOW()
      FROM temp_shipments ts
      JOIN temp_cells c ON c.cell_id = ts.assigned_cell_id
     WHERE apd.id = ts.shipment_id
       AND ts.new_date IS NOT NULL
       AND (apd.origin_node_id <> c.node_id OR apd.fecha_programada <> ts.new_date);
    GET DIAGNOSTICS v_movements_count = ROW_COUNT;
  ELSE
    SELECT COUNT(*) INTO v_movements_count
      FROM temp_shipments ts JOIN temp_cells c ON c.cell_id = ts.assigned_cell_id
     WHERE ts.new_date IS NOT NULL
       AND (ts.current_node_id <> c.node_id OR ts.fecha_programada <> ts.new_date);
  END IF;

  SELECT COALESCE(STDDEV(new_load), 0) INTO v_stddev_after FROM temp_cells;
  v_improvement := CASE WHEN v_stddev_before > 0
                        THEN (v_stddev_before - v_stddev_after) / v_stddev_before * 100 ELSE 0 END;

  SELECT jsonb_agg(jsonb_build_object('node_code', node_code, 'week_num', week_num, 'load_count', new_load)
                   ORDER BY node_code, week_num)
    INTO v_matrix_after FROM temp_cells;

  SELECT jsonb_agg(movement) INTO v_movements
    FROM (SELECT jsonb_build_object('from_node_code', ts.current_node_id, 'from_week', ts.current_week_num,
                                    'to_node_code', c.node_code, 'to_week', c.week_num, 'count', COUNT(*)) AS movement
            FROM temp_shipments ts JOIN temp_cells c ON c.cell_id = ts.assigned_cell_id
           WHERE ts.new_date IS NOT NULL
             AND (ts.current_node_id <> c.node_id OR ts.fecha_programada <> ts.new_date)
           GROUP BY ts.current_node_id, ts.current_week_num, c.node_code, c.week_num
           ORDER BY ts.current_week_num, c.week_num
           LIMIT 100) sub;

  DROP TABLE IF EXISTS temp_cells;
  DROP TABLE IF EXISTS temp_shipments;

  RETURN jsonb_build_object('success', true,
    'movements_count', v_movements_count,
    'stddev_before', v_stddev_before, 'stddev_after', v_stddev_after,
    'improvement_percentage', v_improvement,
    'movements', COALESCE(v_movements, '[]'::jsonb),
    'matrix_before', v_matrix_before, 'matrix_after', v_matrix_after,
    'message', format('Balanced %s shipments across nodes', v_movements_count));
END;
$function$;
