-- Load Balancing v2: politicas de fechas por cuenta/ciudad, POBOX y dias laborables reales.
--
-- Esta migracion se construye por tareas (ver docs/superpowers/specs/2026-10-27-load-balancing-v2-design.md).
-- Parte 1 (base):
--   * columnas de politica: account_config.date_policy ('weekly'|'daily') y pobox_enabled; las ciudades
--     pueden sobrescribirlas (NULL = hereda de la cuenta); cities.balance_rotation_offset;
--   * allocation_plan_details / generated_allocation_plan_details.generation_source ('plan'|'pobox');
--   * is_account_working_day: dia laborable segun weekly_schedule de la cuenta (day_of_week 0=domingo ..
--     6=sabado; sin filas => lunes-viernes) y non_working_days;
--   * working_day_in_range (misma firma) delega en is_account_working_day en vez de asumir lunes-viernes;
--   * effective_city_policy: politica efectiva de una ciudad; POBOX activo fuerza 'daily'.

ALTER TABLE public.account_config
  ADD COLUMN IF NOT EXISTS date_policy text NOT NULL DEFAULT 'daily',
  ADD COLUMN IF NOT EXISTS pobox_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE public.account_config
  DROP CONSTRAINT IF EXISTS account_config_date_policy_check,
  ADD CONSTRAINT account_config_date_policy_check CHECK (date_policy IN ('weekly','daily'));

ALTER TABLE public.cities
  ADD COLUMN IF NOT EXISTS date_policy text NULL,
  ADD COLUMN IF NOT EXISTS pobox_enabled boolean NULL,
  ADD COLUMN IF NOT EXISTS balance_rotation_offset integer NOT NULL DEFAULT 0;
ALTER TABLE public.cities
  DROP CONSTRAINT IF EXISTS cities_date_policy_check,
  ADD CONSTRAINT cities_date_policy_check CHECK (date_policy IN ('weekly','daily'));

ALTER TABLE public.allocation_plan_details
  ADD COLUMN IF NOT EXISTS generation_source text NOT NULL DEFAULT 'plan';
ALTER TABLE public.allocation_plan_details
  DROP CONSTRAINT IF EXISTS allocation_plan_details_generation_source_check,
  ADD CONSTRAINT allocation_plan_details_generation_source_check CHECK (generation_source IN ('plan','pobox'));

ALTER TABLE public.generated_allocation_plan_details
  ADD COLUMN IF NOT EXISTS generation_source text NOT NULL DEFAULT 'plan';
ALTER TABLE public.generated_allocation_plan_details
  DROP CONSTRAINT IF EXISTS generated_allocation_plan_details_generation_source_check,
  ADD CONSTRAINT generated_allocation_plan_details_generation_source_check CHECK (generation_source IN ('plan','pobox'));

CREATE OR REPLACE FUNCTION public.is_account_working_day(p_account_id uuid, p_date date)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT NOT EXISTS (SELECT 1 FROM public.non_working_days n
                      WHERE n.account_id = p_account_id AND n.postal_center_id IS NULL AND n.date = p_date)
     AND CASE
           WHEN EXISTS (SELECT 1 FROM public.weekly_schedule w WHERE w.account_id = p_account_id)
           THEN EXISTS (SELECT 1 FROM public.weekly_schedule w
                         WHERE w.account_id = p_account_id
                           AND w.day_of_week = EXTRACT(dow FROM p_date)::int
                           AND w.is_working_day)
           ELSE EXTRACT(isodow FROM p_date) <= 5
         END;
$$;

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
     WHERE public.is_account_working_day(p_account_id, d::date)
  )
  SELECT d FROM days
   ORDER BY CASE WHEN d = p_preferred THEN 0 WHEN d > p_preferred THEN 1 ELSE 2 END,
            abs(d - p_preferred)
   LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.effective_city_policy(p_city_id uuid)
RETURNS TABLE(account_id uuid, date_policy text, pobox_enabled boolean)
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT c.account_id,
         CASE WHEN COALESCE(c.pobox_enabled, ac.pobox_enabled, false) THEN 'daily'
              ELSE COALESCE(c.date_policy, ac.date_policy, 'daily') END,
         COALESCE(c.pobox_enabled, ac.pobox_enabled, false)
    FROM public.cities c
    LEFT JOIN public.account_config ac ON ac.account_id = c.account_id
   WHERE c.id = p_city_id;
$$;

-- Parte 2 (vista diaria): carga por nodo y dia para la vista dia/mes del balanceo.
-- Una fila por (nodo con ciudad, dia del periodo). SECURITY DEFINER (omite RLS), por eso:
--   * todas las lecturas se filtran por p_account_id;
--   * guarda: con sesion de usuario (auth.uid() no nulo) solo se permite a miembros de p_account_id o a
--     superadmin (mismo patron que generate_reassignment_proposals / list_reroute_candidates); con
--     auth.uid() NULL (llamadas internas / service_role) se permite, como en esas funciones;
--   * se revoca EXECUTE a PUBLIC/anon para que una peticion anonima (uid NULL) no la alcance.
CREATE OR REPLACE FUNCTION public.rpc_get_node_load_by_day(p_account_id uuid, p_start_date date, p_end_date date)
RETURNS TABLE(city_id uuid, city_name text, node_id uuid, node_code text, panelist_name text, day date,
              shipment_count integer, pending_count integer, is_working_day boolean, is_unavailable boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin()
     AND p_account_id IS DISTINCT FROM (SELECT p.account_id FROM public.profiles p WHERE p.id = auth.uid()) THEN
    RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH days AS (
    SELECT d::date AS d, public.is_account_working_day(p_account_id, d::date) AS wd
      FROM generate_series(p_start_date, p_end_date, interval '1 day') d
  ),
  nds AS (
    SELECT n.id, n.auto_id, c.id AS cid, c.name AS cname,
           (SELECT pa.name::text FROM public.panelists pa
             WHERE pa.node_id = n.id AND pa.account_id = p_account_id AND pa.status = 'active'
             ORDER BY pa.created_at LIMIT 1) AS pname
      FROM public.nodes n
      JOIN public.cities c ON c.id = n.city_id AND c.account_id = p_account_id
     WHERE n.account_id = p_account_id
  ),
  ship AS (
    SELECT a.origin_node_id AS nid, a.fecha_programada AS d,
           count(*)::int AS total, (count(*) FILTER (WHERE a.status = 'pending'))::int AS pend
      FROM public.allocation_plan_details a
     WHERE a.account_id = p_account_id
       AND a.fecha_programada BETWEEN p_start_date AND p_end_date
     GROUP BY a.origin_node_id, a.fecha_programada
  ),
  una AS (
    SELECT DISTINCT pa.node_id AS nid, dd.d
      FROM public.panelist_unavailability u
      JOIN public.panelists pa ON pa.id = u.panelist_id AND pa.account_id = p_account_id AND pa.status = 'active'
      JOIN days dd ON dd.d BETWEEN u.start_date AND u.end_date
     WHERE u.account_id = p_account_id AND u.status = 'active' AND pa.node_id IS NOT NULL
  )
  SELECT nds.cid, nds.cname, nds.id, nds.auto_id, nds.pname, days.d,
         COALESCE(ship.total, 0), COALESCE(ship.pend, 0), days.wd, (una.nid IS NOT NULL)
    FROM nds
    CROSS JOIN days
    LEFT JOIN ship ON ship.nid = nds.id AND ship.d = days.d
    LEFT JOIN una  ON una.nid  = nds.id AND una.d  = days.d
   ORDER BY nds.cname, nds.auto_id, days.d;
END;
$$;
REVOKE ALL ON FUNCTION public.rpc_get_node_load_by_day(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_node_load_by_day(uuid, date, date) TO authenticated, service_role;

-- Parte 3 (balanceo por ciudad v2): rpc_balance_city_v2 reparte los envios pendientes de una ciudad de forma
-- equitativa por dia, semana y nodo (spec seccion 5). Cambia fecha_programada y nodo ORIGEN (misma ciudad);
-- nunca el destino. Pasos:
--   1. Cuenta, zona horaria, v_from = GREATEST(inicio, hoy de la cuenta), politica efectiva de la ciudad.
--   2. Nodos validos: activos y con panelista activo. Ausente = panelist_unavailability 'active' que cubre el dia.
--   3. Envios: pending con origen en CUALQUIER nodo de la ciudad y fecha dentro de [inicio, fin].
--   4. Celdas: 'daily' = nodo valido x dia laborable >= v_from sin ausencia; 'weekly' = nodo valido x tramo
--      (semana ISO dentro de un mes) con fecha = primer dia laborable >= v_from libre de ausencia del nodo.
--      El tramo es la semana ISO cortada por mes para no mover nunca envios de un mes a otro (regla 5).
--   5. Objetivos por mes: total del mes (los atrasados cuentan en el mes de v_from) repartido entre sus tramos
--      por dias laborables (resto mayor) y cada tramo entre sus celdas (suelo + sobrante rotativo que empieza
--      en el nodo balance_rotation_offset mod N y continua de tramo en tramo; dentro del nodo los +1 caen en
--      dias distintos).
--   6. Minimos movimientos: se quedan los envios de cada celda hasta su objetivo (los de fecha mas temprana);
--      el resto, mas los que estan fuera de toda celda, se emparejan por orden de fecha con los huecos de las
--      celdas deficitarias del mismo mes (emparejamiento ordenado = menor distancia total en dias). Si el mes
--      no tiene celdas, los envios se quedan y se avisa (no_valid_cell).
--   7. Solo con p_apply_changes: UPDATE de los movidos (traza + reassignment_reason = 'rebalancing') y avance
--      de cities.balance_rotation_offset si hubo sobrante. La vista previa no escribe nada.
--   8. Desviacion tipica antes/despues sobre la carga de las celdas y matrices.
-- SECURITY DEFINER (escribe en cities/allocation_plan_details sin depender de RLS): todas las lecturas se
-- filtran por la cuenta de la ciudad y la guarda de cuenta es la misma que rpc_get_node_load_by_day.
CREATE OR REPLACE FUNCTION public.rpc_balance_city_v2(
  p_city_id uuid, p_start_date date, p_end_date date, p_apply_changes boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_account_id    uuid;
  v_tz            text;
  v_today         date;
  v_from          date;
  v_offset        integer;
  v_date_policy   text;
  v_pobox         boolean;
  v_n_nodes       integer;
  v_had_remainder boolean := false;
  v_total         integer;
  v_stddev_before numeric := 0;
  v_stddev_after  numeric := 0;
  v_improvement   numeric := 0;
  v_movements     jsonb;
  v_movements_count integer := 0;
  v_matrix_before jsonb;
  v_matrix_after  jsonb;
  v_warnings      jsonb;
  v_conf          record;
  v_cur           record;
  v_other         record;
BEGIN
  SELECT c.account_id, COALESCE(a.timezone, 'UTC'), c.balance_rotation_offset
    INTO v_account_id, v_tz, v_offset
    FROM public.cities c JOIN public.accounts a ON a.id = c.account_id
   WHERE c.id = p_city_id;

  IF v_account_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'City not found', 'message', 'City not found',
      'movements_count', 0, 'stddev_before', 0, 'stddev_after', 0, 'improvement_percentage', 0,
      'movements', '[]'::jsonb, 'matrix_before', '[]'::jsonb, 'matrix_after', '[]'::jsonb, 'warnings', '[]'::jsonb,
      'policy', jsonb_build_object('date_policy', NULL, 'pobox_enabled', NULL),
      'pobox', jsonb_build_object('days_missing', 0, 'days_moved', 0, 'days_created', 0, 'days_uncovered', 0));
  END IF;

  -- Guarda de cuenta (igual que rpc_get_node_load_by_day): con sesion de usuario solo miembros de la cuenta
  -- de la ciudad o superadmin; auth.uid() NULL = llamada interna / service_role.
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin()
     AND v_account_id IS DISTINCT FROM (SELECT p.account_id FROM public.profiles p WHERE p.id = auth.uid()) THEN
    RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
  END IF;

  SELECT ep.date_policy, ep.pobox_enabled INTO v_date_policy, v_pobox
    FROM public.effective_city_policy(p_city_id) ep;
  v_today := (now() AT TIME ZONE v_tz)::date;
  v_from  := GREATEST(p_start_date, v_today);   -- nunca se programa en el pasado

  DROP TABLE IF EXISTS lb2_nodes, lb2_days, lb2_absent, lb2_cells, lb2_segs, lb2_ship;

  -- ===== 1-2. Nodos de la ciudad (todos, para codigos) y validez (activo + panelista activo).
  CREATE TEMP TABLE lb2_nodes (
    node_id uuid PRIMARY KEY, node_code text, all_rank integer, valid boolean, valid_rank integer,
    panelist_id uuid, panelist_name text
  ) ON COMMIT DROP;
  INSERT INTO lb2_nodes (node_id, node_code, all_rank, valid, panelist_id, panelist_name)
  SELECT n.id, n.auto_id, (row_number() OVER (ORDER BY n.auto_id, n.id))::int - 1,
         (n.status = 'active' AND pan.id IS NOT NULL), pan.id, pan.name::text
    FROM public.nodes n
    LEFT JOIN LATERAL (SELECT p.id, p.name FROM public.panelists p
                        WHERE p.node_id = n.id AND p.account_id = v_account_id AND p.status = 'active'
                        ORDER BY p.created_at, p.id LIMIT 1) pan ON true
   WHERE n.city_id = p_city_id AND n.account_id = v_account_id;
  UPDATE lb2_nodes t SET valid_rank = x.r
    FROM (SELECT node_id, (row_number() OVER (ORDER BY all_rank))::int - 1 AS r FROM lb2_nodes WHERE valid) x
   WHERE x.node_id = t.node_id;
  SELECT count(*) INTO v_n_nodes FROM lb2_nodes WHERE valid;

  -- Dias laborables de la cuenta en [v_from, fin].
  CREATE TEMP TABLE lb2_days (d date PRIMARY KEY, week_start date, month_start date) ON COMMIT DROP;
  INSERT INTO lb2_days
  SELECT g::date, date_trunc('week', g)::date, date_trunc('month', g)::date
    FROM generate_series(v_from, p_end_date, interval '1 day') g
   WHERE public.is_account_working_day(v_account_id, g::date);

  -- Ausencias activas (cualquier panelista activo del nodo, como la vista diaria).
  CREATE TEMP TABLE lb2_absent (node_id uuid, d date, PRIMARY KEY (node_id, d)) ON COMMIT DROP;
  INSERT INTO lb2_absent
  SELECT DISTINCT p.node_id, dd.d
    FROM public.panelist_unavailability u
    JOIN public.panelists p ON p.id = u.panelist_id AND p.account_id = v_account_id AND p.status = 'active'
    JOIN lb2_nodes n ON n.node_id = p.node_id AND n.valid
    JOIN lb2_days dd ON dd.d BETWEEN u.start_date AND u.end_date
   WHERE u.account_id = v_account_id AND u.status = 'active';

  -- ===== 4. Celdas. Tramo = (week_start, month_start).
  CREATE TEMP TABLE lb2_cells (
    cell_id serial PRIMARY KEY, node_id uuid, node_code text, valid_rank integer,
    week_start date, month_start date, cell_date date,
    day_idx integer, node_cells integer,
    current_load integer NOT NULL DEFAULT 0, target integer NOT NULL DEFAULT 0,
    kept integer NOT NULL DEFAULT 0, new_load integer NOT NULL DEFAULT 0
  ) ON COMMIT DROP;
  IF v_date_policy = 'weekly' THEN
    INSERT INTO lb2_cells (node_id, node_code, valid_rank, week_start, month_start, cell_date)
    SELECT n.node_id, n.node_code, n.valid_rank, d.week_start, d.month_start, min(d.d)
      FROM lb2_nodes n CROSS JOIN lb2_days d
     WHERE n.valid AND NOT EXISTS (SELECT 1 FROM lb2_absent a WHERE a.node_id = n.node_id AND a.d = d.d)
     GROUP BY n.node_id, n.node_code, n.valid_rank, d.week_start, d.month_start
     ORDER BY n.valid_rank, d.week_start, d.month_start;
  ELSE
    INSERT INTO lb2_cells (node_id, node_code, valid_rank, week_start, month_start, cell_date)
    SELECT n.node_id, n.node_code, n.valid_rank, d.week_start, d.month_start, d.d
      FROM lb2_nodes n CROSS JOIN lb2_days d
     WHERE n.valid AND NOT EXISTS (SELECT 1 FROM lb2_absent a WHERE a.node_id = n.node_id AND a.d = d.d)
     ORDER BY n.valid_rank, d.d;
  END IF;
  CREATE INDEX ON lb2_cells (node_id, cell_date);
  -- Posicion del dia dentro del nodo y del tramo (para repartir los +1 en dias distintos).
  UPDATE lb2_cells c SET day_idx = x.i, node_cells = x.k
    FROM (SELECT cell_id,
                 (row_number() OVER (PARTITION BY node_id, week_start, month_start ORDER BY cell_date))::int - 1 AS i,
                 (count(*) OVER (PARTITION BY node_id, week_start, month_start))::int AS k
            FROM lb2_cells) x
   WHERE x.cell_id = c.cell_id;

  -- ===== 3. Envios pendientes de la ciudad en el periodo (origen en cualquier nodo de la ciudad).
  CREATE TEMP TABLE lb2_ship (
    id uuid PRIMARY KEY, cur_node uuid, cur_code text, cur_rank integer, dest_node uuid, fecha date,
    month_key date, cur_cell integer, new_cell integer, keep boolean NOT NULL DEFAULT false,
    od_conflict boolean NOT NULL DEFAULT false
  ) ON COMMIT DROP;
  INSERT INTO lb2_ship (id, cur_node, cur_code, cur_rank, dest_node, fecha, month_key)
  SELECT a.id, a.origin_node_id, n.node_code, n.all_rank, a.destination_node_id, a.fecha_programada,
         date_trunc('month', GREATEST(a.fecha_programada, v_from))::date
    FROM public.allocation_plan_details a
    JOIN lb2_nodes n ON n.node_id = a.origin_node_id
   WHERE a.account_id = v_account_id
     AND a.status = 'pending'
     AND a.fecha_programada BETWEEN p_start_date AND p_end_date;
  SELECT count(*) INTO v_total FROM lb2_ship;

  -- Atrasados: cuentan en el mes de v_from; si ese mes ya no tiene celdas, en el primer mes siguiente que las tenga.
  UPDATE lb2_ship s SET month_key = m.next_month
    FROM (SELECT min(month_start) AS next_month FROM lb2_cells
           WHERE month_start > date_trunc('month', v_from)::date) m
   WHERE s.fecha < v_from AND m.next_month IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM lb2_cells c WHERE c.month_start = s.month_key);

  -- Celda actual de cada envio (si la tiene).
  IF v_date_policy = 'weekly' THEN
    UPDATE lb2_ship s SET cur_cell = c.cell_id
      FROM lb2_cells c
     WHERE c.node_id = s.cur_node
       AND c.week_start = date_trunc('week', s.fecha)::date
       AND c.month_start = date_trunc('month', s.fecha)::date
       AND c.month_start = s.month_key;
  ELSE
    UPDATE lb2_ship s SET cur_cell = c.cell_id
      FROM lb2_cells c
     WHERE c.node_id = s.cur_node AND c.cell_date = s.fecha;
  END IF;
  UPDATE lb2_cells c SET current_load = x.n
    FROM (SELECT cur_cell, count(*)::int AS n FROM lb2_ship WHERE cur_cell IS NOT NULL GROUP BY cur_cell) x
   WHERE x.cur_cell = c.cell_id;

  -- ===== 5. Objetivos. Tramos con al menos una celda; peso = dias laborables del tramo en el periodo.
  CREATE TEMP TABLE lb2_segs (
    week_start date, month_start date, seg_from date, wdays integer, ncells integer,
    share integer NOT NULL DEFAULT 0, base integer NOT NULL DEFAULT 0, rem integer NOT NULL DEFAULT 0,
    g integer NOT NULL DEFAULT 0, PRIMARY KEY (week_start, month_start)
  ) ON COMMIT DROP;
  INSERT INTO lb2_segs (week_start, month_start, seg_from, wdays, ncells)
  SELECT d.week_start, d.month_start, min(d.d), count(*)::int, x.ncells
    FROM lb2_days d
    JOIN (SELECT week_start, month_start, count(*)::int AS ncells FROM lb2_cells GROUP BY 1, 2) x
      ON x.week_start = d.week_start AND x.month_start = d.month_start
   GROUP BY d.week_start, d.month_start, x.ncells;

  -- 5a. Total del mes -> tramos (suelo + resto mayor; empate -> tramo mas temprano).
  WITH mt AS (SELECT month_key, count(*)::numeric AS t FROM lb2_ship GROUP BY month_key),
  w AS (SELECT s.week_start, s.month_start, s.seg_from, mt.t,
               s.wdays * mt.t / sum(s.wdays) OVER (PARTITION BY s.month_start) AS raw
          FROM lb2_segs s JOIN mt ON mt.month_key = s.month_start),
  f AS (SELECT w.*, floor(w.raw)::int AS fl FROM w),
  r AS (SELECT f.*, f.t::int - sum(f.fl) OVER (PARTITION BY f.month_start) AS leftover,
               row_number() OVER (PARTITION BY f.month_start ORDER BY f.raw - f.fl DESC, f.seg_from) AS rk
          FROM f)
  UPDATE lb2_segs s SET share = r.fl + CASE WHEN r.rk <= r.leftover THEN 1 ELSE 0 END
    FROM r WHERE r.week_start = s.week_start AND r.month_start = s.month_start;
  UPDATE lb2_segs SET base = share / ncells, rem = share % ncells WHERE ncells > 0;
  v_had_remainder := EXISTS (SELECT 1 FROM lb2_segs WHERE rem > 0);

  -- 5b. Puntero de rotacion por tramo: empieza en balance_rotation_offset mod N y avanza tantos nodos como +1
  -- se repartieron en los tramos anteriores (asi los +1 no caen siempre en los mismos nodos).
  UPDATE lb2_segs s SET g = x.g
    FROM (SELECT week_start, month_start,
                 ((v_offset + COALESCE(sum(rem) OVER (ORDER BY seg_from ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0))
                   % NULLIF(v_n_nodes, 0))::int AS g
            FROM lb2_segs) x
   WHERE x.week_start = s.week_start AND x.month_start = s.month_start;

  -- 5c. Tramo -> celdas: base para todas; los rem +1 van por orden (vuelta, nodo rotado). La "vuelta" de una
  -- celda desplaza el dia segun el nodo, para que los +1 de nodos distintos caigan en dias distintos.
  WITH q AS (
    SELECT c.cell_id, c.week_start, c.month_start, c.cell_date, s.base, s.rem,
           (((c.valid_rank - s.g) % v_n_nodes) + v_n_nodes) % v_n_nodes AS qn, c.day_idx, c.node_cells
      FROM lb2_cells c JOIN lb2_segs s ON s.week_start = c.week_start AND s.month_start = c.month_start),
  o AS (
    SELECT q.cell_id, q.base, q.rem,
           row_number() OVER (PARTITION BY q.week_start, q.month_start
                              ORDER BY (((q.day_idx - q.qn) % q.node_cells) + q.node_cells) % q.node_cells,
                                       q.qn, q.cell_date) AS ord
      FROM q)
  UPDATE lb2_cells c SET target = o.base + CASE WHEN o.ord <= o.rem THEN 1 ELSE 0 END
    FROM o WHERE o.cell_id = c.cell_id;

  -- ===== 6. Asignacion con minimos movimientos.
  -- 6a. En cada celda se quedan hasta 'target' envios (los de fecha mas temprana; sale primero el mas lejano).
  WITH k AS (
    SELECT s.id, c.target,
           row_number() OVER (PARTITION BY s.cur_cell ORDER BY s.fecha, s.id) AS rn
      FROM lb2_ship s JOIN lb2_cells c ON c.cell_id = s.cur_cell)
  UPDATE lb2_ship s SET keep = true, new_cell = s.cur_cell
    FROM k WHERE k.id = s.id AND k.rn <= k.target;
  UPDATE lb2_cells c SET kept = x.n
    FROM (SELECT cur_cell, count(*)::int AS n FROM lb2_ship WHERE keep GROUP BY cur_cell) x
   WHERE x.cur_cell = c.cell_id;

  -- 6b. Excedentes (sobrantes de celdas por encima del objetivo + envios fuera de toda celda) contra huecos de
  -- celdas deficitarias del MISMO mes. Ambos lados ordenados por fecha: el emparejamiento ordenado minimiza la
  -- distancia total en dias. Por construccion, en cada mes con celdas hay tantos huecos como excedentes.
  WITH ex AS (
    SELECT s.id, s.month_key,
           row_number() OVER (PARTITION BY s.month_key ORDER BY s.fecha, s.cur_rank, s.id) AS rk
      FROM lb2_ship s WHERE NOT s.keep),
  sl AS (
    SELECT c.cell_id, c.month_start,
           row_number() OVER (PARTITION BY c.month_start ORDER BY c.cell_date, c.valid_rank, k.k) AS rk
      FROM lb2_cells c CROSS JOIN LATERAL generate_series(1, c.target - c.kept) k(k)
     WHERE c.target > c.kept)
  UPDATE lb2_ship s SET new_cell = sl.cell_id
    FROM ex JOIN sl ON sl.month_start = ex.month_key AND sl.rk = ex.rk
   WHERE s.id = ex.id;

  -- 6c. Un envio nunca puede quedar con origen = destino (rutas dentro de la ciudad): se intercambia la celda con
  -- otro excedente del mismo mes compatible; si no hay ninguno, el envio se queda donde esta y se avisa.
  FOR v_conf IN
    SELECT s.id FROM lb2_ship s JOIN lb2_cells c ON c.cell_id = s.new_cell
     WHERE NOT s.keep AND c.node_id = s.dest_node
  LOOP
    SELECT s.new_cell, s.month_key, s.dest_node, s.fecha, c.node_id
      INTO v_cur FROM lb2_ship s JOIN lb2_cells c ON c.cell_id = s.new_cell WHERE s.id = v_conf.id;
    CONTINUE WHEN v_cur.node_id IS DISTINCT FROM v_cur.dest_node;  -- ya resuelto por un intercambio previo
    SELECT s2.id, s2.new_cell INTO v_other
      FROM lb2_ship s2 JOIN lb2_cells c2 ON c2.cell_id = s2.new_cell
     WHERE NOT s2.keep AND s2.month_key = v_cur.month_key AND s2.id <> v_conf.id
       AND c2.node_id <> v_cur.dest_node AND s2.dest_node IS DISTINCT FROM v_cur.node_id
     ORDER BY abs(c2.cell_date - v_cur.fecha), c2.cell_date
     LIMIT 1;
    IF FOUND THEN
      UPDATE lb2_ship SET new_cell = v_cur.new_cell WHERE id = v_other.id;
      UPDATE lb2_ship SET new_cell = v_other.new_cell WHERE id = v_conf.id;
    ELSE
      UPDATE lb2_ship SET new_cell = NULL, od_conflict = true WHERE id = v_conf.id;
    END IF;
  END LOOP;

  -- ===== FASE POBOX (Tarea 4) =====
  -- Aqui ira POBOX: sobre la asignacion ya equilibrada (lb2_ship.new_cell / lb2_cells.cell_date), cubrir cada
  -- dia laborable sin envio de origen moviendo excedentes y, si no alcanza, creando envios. Debe rellenar las
  -- cifras de 'pobox' del JSON (en esta tarea se devuelven a cero) y respetar p_apply_changes.

  UPDATE lb2_cells c SET new_load = x.n
    FROM (SELECT new_cell, count(*)::int AS n FROM lb2_ship WHERE new_cell IS NOT NULL GROUP BY new_cell) x
   WHERE x.new_cell = c.cell_id;

  -- ===== 7. Escritura (solo al aplicar).
  IF p_apply_changes THEN
    UPDATE public.allocation_plan_details a
       SET origin_node_id = c.node_id,
           origin_panelist_name = n.panelist_name,
           origin_panelist_id = CASE WHEN a.origin_panelist_id IS NOT NULL THEN n.panelist_id END,
           fecha_programada = c.cell_date,
           week_number = EXTRACT(week FROM c.cell_date)::int,
           month = EXTRACT(month FROM c.cell_date)::int,
           year = EXTRACT(year FROM c.cell_date)::int,
           original_fecha_programada = COALESCE(a.original_fecha_programada, a.fecha_programada),
           original_origin_node_id = COALESCE(a.original_origin_node_id, a.origin_node_id),
           reassignment_reason = 'rebalancing',
           reassigned_at = now(),
           reassigned_by = auth.uid(),
           updated_at = now()
      FROM lb2_ship s
      JOIN lb2_cells c ON c.cell_id = s.new_cell
      JOIN lb2_nodes n ON n.node_id = c.node_id
     WHERE a.id = s.id
       AND a.status = 'pending'
       AND (a.origin_node_id <> c.node_id OR a.fecha_programada <> c.cell_date);
    GET DIAGNOSTICS v_movements_count = ROW_COUNT;

    IF v_had_remainder THEN
      UPDATE public.cities SET balance_rotation_offset = balance_rotation_offset + 1 WHERE id = p_city_id;
    END IF;
  ELSE
    SELECT count(*) INTO v_movements_count
      FROM lb2_ship s JOIN lb2_cells c ON c.cell_id = s.new_cell
     WHERE s.cur_node <> c.node_id OR s.fecha <> c.cell_date;
  END IF;

  -- ===== 8. Resultado.
  SELECT COALESCE(stddev(current_load), 0), COALESCE(stddev(new_load), 0)
    INTO v_stddev_before, v_stddev_after FROM lb2_cells;
  v_improvement := CASE WHEN v_stddev_before > 0
                        THEN (v_stddev_before - v_stddev_after) / v_stddev_before * 100 ELSE 0 END;

  IF v_date_policy = 'weekly' THEN
    SELECT jsonb_agg(jsonb_build_object('node_code', node_code, 'week_num', EXTRACT(week FROM week_start)::int,
                                        'week_start', week_start, 'day', NULL, 'load_count', lb)
                     ORDER BY node_code, week_start),
           jsonb_agg(jsonb_build_object('node_code', node_code, 'week_num', EXTRACT(week FROM week_start)::int,
                                        'week_start', week_start, 'day', NULL, 'load_count', la)
                     ORDER BY node_code, week_start)
      INTO v_matrix_before, v_matrix_after
      FROM (SELECT node_code, week_start, sum(current_load)::int AS lb, sum(new_load)::int AS la
              FROM lb2_cells GROUP BY node_code, week_start) x;
  ELSE
    SELECT jsonb_agg(jsonb_build_object('node_code', node_code, 'week_num', EXTRACT(week FROM week_start)::int,
                                        'week_start', week_start, 'day', cell_date, 'load_count', current_load)
                     ORDER BY node_code, cell_date),
           jsonb_agg(jsonb_build_object('node_code', node_code, 'week_num', EXTRACT(week FROM week_start)::int,
                                        'week_start', week_start, 'day', cell_date, 'load_count', new_load)
                     ORDER BY node_code, cell_date)
      INTO v_matrix_before, v_matrix_after
      FROM lb2_cells;
  END IF;

  SELECT jsonb_agg(m ORDER BY m->>'from_date', m->>'to_date', m->>'from_node_code', m->>'to_node_code')
    INTO v_movements
    FROM (SELECT jsonb_build_object('from_node_code', s.cur_code, 'from_date', s.fecha,
                                    'to_node_code', c.node_code, 'to_date', c.cell_date, 'count', count(*)) AS m
            FROM lb2_ship s JOIN lb2_cells c ON c.cell_id = s.new_cell
           WHERE s.cur_node <> c.node_id OR s.fecha <> c.cell_date
           GROUP BY s.cur_code, s.fecha, c.node_code, c.cell_date
           ORDER BY s.fecha, c.cell_date, s.cur_code, c.node_code
           LIMIT 100) sub;

  SELECT jsonb_agg(w) INTO v_warnings
    FROM (SELECT jsonb_build_object('code', 'no_valid_cell', 'count', count(*),
                                    'detail', string_agg(DISTINCT cur_code, ', ' ORDER BY cur_code)) AS w
            FROM lb2_ship WHERE new_cell IS NULL AND NOT od_conflict HAVING count(*) > 0
          UNION ALL
          SELECT jsonb_build_object('code', 'origin_equals_destination', 'count', count(*),
                                    'detail', string_agg(DISTINCT cur_code, ', ' ORDER BY cur_code))
            FROM lb2_ship WHERE od_conflict HAVING count(*) > 0) x;

  DROP TABLE IF EXISTS lb2_nodes, lb2_days, lb2_absent, lb2_cells, lb2_segs, lb2_ship;

  RETURN jsonb_build_object('success', true,
    'movements_count', v_movements_count,
    'stddev_before', v_stddev_before, 'stddev_after', v_stddev_after,
    'improvement_percentage', v_improvement,
    'movements', COALESCE(v_movements, '[]'::jsonb),
    'matrix_before', COALESCE(v_matrix_before, '[]'::jsonb),
    'matrix_after', COALESCE(v_matrix_after, '[]'::jsonb),
    'warnings', COALESCE(v_warnings, '[]'::jsonb),
    'policy', jsonb_build_object('date_policy', v_date_policy, 'pobox_enabled', v_pobox),
    'pobox', jsonb_build_object('days_missing', 0, 'days_moved', 0, 'days_created', 0, 'days_uncovered', 0),
    'message', CASE WHEN v_total = 0 THEN 'No shipments found in the specified period'
                    ELSE format('Balanced %s shipments across nodes', v_movements_count) END,
    'error', NULL);
END;
$function$;
REVOKE ALL ON FUNCTION public.rpc_balance_city_v2(uuid, date, date, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_balance_city_v2(uuid, date, date, boolean) TO authenticated, service_role;
