-- Muestras por compensar (deferred samples).
--
-- Cuando el balanceo no puede programar una muestra del plan (ciudad de origen o destino sin panelista, o sin
-- dia valido) la muestra no se pierde: se anota en un registro "por compensar" y se reintroduce mas tarde.
-- Esta migracion (parte 1) aporta:
--   * tabla public.deferred_samples (registro) con RLS por account_id;
--   * generation_source admite tambien 'compensation' (muestras creadas al reintroducir) en
--     allocation_plan_details y generated_allocation_plan_details;
--   * rpc_deferred_samples_summary(account): resumen por ciudad de origen y por plan.
-- Las siguientes partes (RPC de registro/reintroduccion) se anexan a este mismo fichero.

CREATE TABLE IF NOT EXISTS public.deferred_samples (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  plan_id uuid NOT NULL,
  origin_city_id uuid NOT NULL,
  dest_city_id uuid NOT NULL,
  origin_node_id uuid NOT NULL,
  destination_node_id uuid NOT NULL,
  fecha_programada date NOT NULL,
  reason text NOT NULL CHECK (reason IN ('origin_no_panelist','dest_no_panelist','no_valid_day')),
  row_snapshot jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','reintroduced')),
  waiting_reason text NULL CHECK (waiting_reason IN ('no_origin_panelist','no_dest_panelist','no_capacity','plan_inactive','outside_period')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NULL,
  reintroduced_at timestamptz NULL,
  reintroduced_detail_id uuid NULL
);

CREATE INDEX IF NOT EXISTS deferred_samples_account_status_idx ON public.deferred_samples (account_id, status);
CREATE INDEX IF NOT EXISTS deferred_samples_origin_city_status_idx ON public.deferred_samples (origin_city_id, status);
CREATE INDEX IF NOT EXISTS deferred_samples_plan_status_idx ON public.deferred_samples (plan_id, status);

ALTER TABLE public.deferred_samples ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS deferred_samples_select ON public.deferred_samples;
CREATE POLICY deferred_samples_select ON public.deferred_samples
  FOR SELECT TO authenticated
  USING (account_id = public.current_user_account_id() OR public.is_superadmin());

-- Escrituras solo por las funciones del balanceo (SECURITY DEFINER): defensa en profundidad ademas de RLS.
REVOKE ALL ON public.deferred_samples FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.deferred_samples FROM anon, authenticated;

-- generation_source: 'plan' | 'pobox' | 'compensation'
ALTER TABLE public.allocation_plan_details
  DROP CONSTRAINT IF EXISTS allocation_plan_details_generation_source_check,
  ADD CONSTRAINT allocation_plan_details_generation_source_check CHECK (generation_source IN ('plan','pobox','compensation'));

ALTER TABLE public.generated_allocation_plan_details
  DROP CONSTRAINT IF EXISTS generated_allocation_plan_details_generation_source_check,
  ADD CONSTRAINT generated_allocation_plan_details_generation_source_check CHECK (generation_source IN ('plan','pobox','compensation'));

-- Resumen del registro por ciudad de origen y por plan.
CREATE OR REPLACE FUNCTION public.rpc_deferred_samples_summary(p_account_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total int;
  v_by_city jsonb;
  v_by_plan jsonb;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin()
     AND p_account_id IS DISTINCT FROM (SELECT p.account_id FROM public.profiles p WHERE p.id = auth.uid()) THEN
    RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_total
    FROM public.deferred_samples d WHERE d.account_id = p_account_id AND d.status = 'pending';

  SELECT COALESCE(jsonb_agg(jsonb_build_object('city_id', x.city_id, 'city_name', x.city_name,
                                               'count', x.cnt, 'waiting_reason', x.waiting_reason)
                            ORDER BY x.city_name), '[]'::jsonb)
    INTO v_by_city
    FROM (
      SELECT d.origin_city_id AS city_id, COALESCE(c.name, '') AS city_name, count(*)::int AS cnt,
             (SELECT d2.waiting_reason FROM public.deferred_samples d2
               WHERE d2.account_id = p_account_id AND d2.status = 'pending'
                 AND d2.origin_city_id = d.origin_city_id AND d2.waiting_reason IS NOT NULL
               GROUP BY d2.waiting_reason ORDER BY count(*) DESC, d2.waiting_reason LIMIT 1) AS waiting_reason
        FROM public.deferred_samples d
        LEFT JOIN public.cities c ON c.id = d.origin_city_id
       WHERE d.account_id = p_account_id AND d.status = 'pending'
       GROUP BY d.origin_city_id, c.name
    ) x;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'plan_id', ap.id, 'plan_name', ap.plan_name, 'total_samples', ap.total_samples,
           'scheduled', (SELECT count(*) FROM public.allocation_plan_details a
                          WHERE a.plan_id = ap.id AND a.status IN ('pending','notified')),
           'done', (SELECT count(*) FROM public.allocation_plan_details a
                     WHERE a.plan_id = ap.id AND a.status IN ('sent','received')),
           'deferred', (SELECT count(*) FROM public.deferred_samples d
                         WHERE d.plan_id = ap.id AND d.status = 'pending'),
           'pobox_extra', (SELECT count(*) FROM public.allocation_plan_details a
                            WHERE a.plan_id = ap.id AND a.generation_source = 'pobox'))
         ORDER BY ap.plan_name), '[]'::jsonb)
    INTO v_by_plan
    FROM public.allocation_plans ap
   WHERE ap.account_id = p_account_id
     AND (EXISTS (SELECT 1 FROM public.allocation_plan_details a WHERE a.plan_id = ap.id)
          OR EXISTS (SELECT 1 FROM public.deferred_samples d WHERE d.plan_id = ap.id AND d.status = 'pending'));

  RETURN jsonb_build_object('pending_total', v_total, 'by_city', v_by_city, 'by_plan', v_by_plan);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_deferred_samples_summary(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_deferred_samples_summary(uuid) TO authenticated, service_role;

-- ============================================================================
-- Parte 2: rpc_balance_city_v2 con la fase 0 (reasignar destino o apartar al registro).
-- ============================================================================
-- Mismo cuerpo que 20261027180000_balance_city_safeupdate.sql con estos cambios (spec 2026-10-28, 3.1):
--   * Fase 0, tras cargar los envios y antes de los objetivos:
--     0a ciudad sin ningun nodo valido => todas sus muestras al registro (origin_no_panelist);
--     0b destino sin panelista activo => otro nodo valido de la ciudad destino (menos recepciones esa semana) o,
--        si no hay, al registro (dest_no_panelist). Sustituye la regla "el destino nunca cambia";
--     0c sin celda compatible en su mes => se busca en los demas meses del periodo dentro de las fechas del plan;
--        si no hay ninguna => al registro (no_valid_day), salvo origen = destino (sigue el aviso de siempre).
--        no_valid_day solo si tampoco hay hueco en el resto del horizonte del plan (R3); si lo hay, se queda.
--     Nunca se aparta una muestra con material_hold, shipment_incident, panelist_incident u one_db enlazados
--     (R2): se queda congelada y se avisa con deferred_blocked.
--     Las apartadas no cuentan en totales, objetivos, desviaciones ni matrices.
--   * Filtro por fechas del plan tambien en el reparto normal (antes solo POBOX).
--   * Al aplicar: INSERT en deferred_samples + DELETE del plan sobre el mismo conjunto, con verificacion de
--     recuento (si no cuadra, se aborta todo); UPDATE de destinos reasignados.
--   * JSON: nueva clave 'deferred' y aviso 'deferred_removed'. La vista previa no escribe nada.
-- Parte 3 (spec 3.2 / 3.2 bis), en esta misma definicion:
--   * Fase R (tras la equidad, antes de POBOX): las anotaciones 'pending' de esta ciudad origen con plan 'active'
--     se colocan en un dia laborable del periodo y del plan, sin ausencia de origen ni destino, ruta ciudad->ciudad
--     (nodo original si es valido ese dia; si no, el menos cargado de la misma ciudad), dia con menos envios del
--     nodo origen. Topes TOTALES (no por ejecucion): como mucho 1 fila 'compensation' por (nodo origen, dia) y 1
--     por (nodo destino, dia), contando las que ya existen. Las que no caben esperan con waiting_reason (solo se
--     escribe al aplicar).
--   * POBOX: los dias sin envios tras la equidad que una anotacion puede servir ya los cubre la fase R (que
--     prefiere los dias vacios de la ciudad); POBOX los informa como days_reintroduced (paso 0) y solo despues
--     mueve excedentes o crea muestras 'pobox'. (Un paso POBOX propio "tirar del registro" seria inalcanzable
--     tras la fase R: cualquier anotacion que pudiera servir ese dia ya la habria colocado la fase R.)
--   * Al aplicar: INSERT de filas 'compensation' + UPDATE del registro a 'reintroduced' con recuento exacto.
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
  -- POBOX
  v_day           date;
  v_wk            date;
  v_mv_id         uuid;
  v_mv_cell       integer;
  v_plan          uuid;
  v_org_node      uuid;
  v_org_cell      integer;
  v_dst_node      uuid;
  v_new_id        uuid;
  v_fb_cell       integer;
  v_pb_missing    integer := 0;
  v_pb_moved      integer := 0;
  v_pb_created    integer := 0;
  v_pb_uncovered  integer := 0;
  v_pb_unc_dates  text[] := '{}';
  -- Muestras por compensar (fase 0)
  v_def_removed    integer := 0;
  v_def_origin     integer := 0;
  v_def_dest       integer := 0;
  v_def_day        integer := 0;
  v_def_reassigned integer := 0;
  v_def_waiting    integer := 0;
  v_def_ins        integer := 0;
  v_def_del        integer := 0;
  v_def_blocked    integer := 0;
  v_def_bad        text;
  -- Reintroduccion (fase R y POBOX)
  v_rc             record;
  v_rc_any         boolean := false;   -- la ciudad tiene anotaciones pendientes (existe lb2_rcand)
  v_r_onode        uuid;
  v_r_dnode        uuid;
  v_r_day          date;
  v_r_cell         integer;
  v_reint          integer := 0;
  v_reint_ins      integer := 0;
  v_reint_upd      integer := 0;
  v_pb_reint       integer := 0;
  v_wait_by        jsonb;
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
      'pobox', jsonb_build_object('days_missing', 0, 'days_moved', 0, 'days_created', 0, 'days_uncovered', 0,
                                  'days_reintroduced', 0),
      'deferred', jsonb_build_object('removed', 0, 'reassigned_dest', 0, 'reintroduced', 0, 'waiting', 0, 'blocked', 0,
                                     'by_reason', jsonb_build_object('origin_no_panelist', 0, 'dest_no_panelist', 0,
                                                                     'no_valid_day', 0),
                                     'waiting_by_reason', jsonb_build_object('no_origin_panelist', 0, 'no_dest_panelist', 0,
                                                                             'no_capacity', 0, 'plan_inactive', 0,
                                                                             'outside_period', 0)));
  END IF;

  -- Guarda de cuenta (igual que rpc_get_node_load_by_day): con sesion de usuario solo miembros de la cuenta
  -- de la ciudad o superadmin; auth.uid() NULL = llamada interna / service_role.
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin()
     AND v_account_id IS DISTINCT FROM (SELECT p.account_id FROM public.profiles p WHERE p.id = auth.uid()) THEN
    RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
  END IF;

  -- Dos aplicaciones concurrentes sobre la misma ciudad se serializan (la segunda calcula sobre lo que dejo la
  -- primera). La vista previa no bloquea. El offset se relee tras el bloqueo.
  IF p_apply_changes THEN
    PERFORM pg_advisory_xact_lock(hashtext(p_city_id::text));
    SELECT c.balance_rotation_offset INTO v_offset FROM public.cities c WHERE c.id = p_city_id;
  END IF;

  SELECT ep.date_policy, ep.pobox_enabled INTO v_date_policy, v_pobox
    FROM public.effective_city_policy(p_city_id) ep;
  v_today := (now() AT TIME ZONE v_tz)::date;
  v_from  := GREATEST(p_start_date, v_today);   -- nunca se programa en el pasado

  DROP TABLE IF EXISTS pg_temp.lb2_nodes, pg_temp.lb2_days, pg_temp.lb2_absent, pg_temp.lb2_cells, pg_temp.lb2_segs, pg_temp.lb2_ship,
                       pg_temp.lb2_new, pg_temp.lb2_pb, pg_temp.lb2_plans, pg_temp.lb2_routes, pg_temp.lb2_dest,
                       pg_temp.lb2_dabsent, pg_temp.lb2_dload, pg_temp.lb2_sdabs,
                       pg_temp.lb2_alt, pg_temp.lb2_altload, pg_temp.lb2_altabs, pg_temp.lb2_defer, pg_temp.lb2_hz,
                       pg_temp.lb2_reint, pg_temp.lb2_rcand, pg_temp.lb2_rload, pg_temp.lb2_rday,
                       pg_temp.lb2_rdest, pg_temp.lb2_rdslot;

  -- ===== 1-2. Nodos de la ciudad (todos, para codigos) y validez (activo + panelista activo).
  CREATE TEMP TABLE pg_temp.lb2_nodes (
    node_id uuid PRIMARY KEY, node_code text, all_rank integer, valid boolean, valid_rank integer,
    panelist_id uuid, panelist_name text
  ) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_nodes (node_id, node_code, all_rank, valid, panelist_id, panelist_name)
  SELECT n.id, n.auto_id, (row_number() OVER (ORDER BY n.auto_id, n.id))::int - 1,
         (n.status = 'active' AND pan.id IS NOT NULL), pan.id, pan.name::text
    FROM public.nodes n
    LEFT JOIN LATERAL (SELECT p.id, p.name FROM public.panelists p
                        WHERE p.node_id = n.id AND p.account_id = v_account_id AND p.status = 'active'
                        ORDER BY p.created_at, p.id LIMIT 1) pan ON true
   WHERE n.city_id = p_city_id AND n.account_id = v_account_id;
  UPDATE pg_temp.lb2_nodes t SET valid_rank = x.r
    FROM (SELECT node_id, (row_number() OVER (ORDER BY all_rank))::int - 1 AS r FROM pg_temp.lb2_nodes WHERE valid) x
   WHERE x.node_id = t.node_id;
  SELECT count(*) INTO v_n_nodes FROM pg_temp.lb2_nodes WHERE valid;

  -- Dias laborables de la cuenta en [v_from, fin].
  CREATE TEMP TABLE pg_temp.lb2_days (d date PRIMARY KEY, week_start date, month_start date) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_days
  SELECT g::date, date_trunc('week', g)::date, date_trunc('month', g)::date
    FROM generate_series(v_from, p_end_date, interval '1 day') g
   WHERE public.is_account_working_day(v_account_id, g::date);

  -- Ausencias activas (cualquier panelista activo del nodo, como la vista diaria).
  CREATE TEMP TABLE pg_temp.lb2_absent (node_id uuid, d date, PRIMARY KEY (node_id, d)) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_absent
  SELECT DISTINCT p.node_id, dd.d
    FROM public.panelist_unavailability u
    JOIN public.panelists p ON p.id = u.panelist_id AND p.account_id = v_account_id AND p.status = 'active'
    JOIN pg_temp.lb2_nodes n ON n.node_id = p.node_id AND n.valid
    JOIN pg_temp.lb2_days dd ON dd.d BETWEEN u.start_date AND u.end_date
   WHERE u.account_id = v_account_id AND u.status = 'active';

  -- ===== 4. Celdas. Tramo = (week_start, month_start).
  CREATE TEMP TABLE pg_temp.lb2_cells (
    cell_id serial PRIMARY KEY, node_id uuid, node_code text, valid_rank integer,
    week_start date, month_start date, cell_date date,
    day_idx integer, node_cells integer,
    current_load integer NOT NULL DEFAULT 0, target integer NOT NULL DEFAULT 0,
    kept integer NOT NULL DEFAULT 0, new_load integer NOT NULL DEFAULT 0,
    fixed integer NOT NULL DEFAULT 0,  -- envios congelados (no movibles) que ya estan en la celda
    -- el dia cae dentro de las fechas del plan de algun envio de la ciudad (si no, la celda no recibe objetivo)
    in_plan boolean NOT NULL DEFAULT true
  ) ON COMMIT DROP;
  IF v_date_policy = 'weekly' THEN
    INSERT INTO pg_temp.lb2_cells (node_id, node_code, valid_rank, week_start, month_start, cell_date)
    SELECT n.node_id, n.node_code, n.valid_rank, d.week_start, d.month_start, min(d.d)
      FROM pg_temp.lb2_nodes n CROSS JOIN pg_temp.lb2_days d
     WHERE n.valid AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_absent a WHERE a.node_id = n.node_id AND a.d = d.d)
     GROUP BY n.node_id, n.node_code, n.valid_rank, d.week_start, d.month_start
     ORDER BY n.valid_rank, d.week_start, d.month_start;
  ELSE
    INSERT INTO pg_temp.lb2_cells (node_id, node_code, valid_rank, week_start, month_start, cell_date)
    SELECT n.node_id, n.node_code, n.valid_rank, d.week_start, d.month_start, d.d
      FROM pg_temp.lb2_nodes n CROSS JOIN pg_temp.lb2_days d
     WHERE n.valid AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_absent a WHERE a.node_id = n.node_id AND a.d = d.d)
     ORDER BY n.valid_rank, d.d;
  END IF;
  CREATE INDEX ON pg_temp.lb2_cells (node_id, cell_date);
  -- Posicion del dia dentro del nodo y del tramo (para repartir los +1 en dias distintos).
  UPDATE pg_temp.lb2_cells c SET day_idx = x.i, node_cells = x.k
    FROM (SELECT cell_id,
                 (row_number() OVER (PARTITION BY node_id, week_start, month_start ORDER BY cell_date))::int - 1 AS i,
                 (count(*) OVER (PARTITION BY node_id, week_start, month_start))::int AS k
            FROM pg_temp.lb2_cells) x
   WHERE x.cell_id = c.cell_id;

  -- ===== 3. Envios pendientes de la ciudad en el periodo (origen en cualquier nodo de la ciudad).
  CREATE TEMP TABLE pg_temp.lb2_ship (
    id uuid PRIMARY KEY, cur_node uuid, cur_code text, cur_rank integer, dest_node uuid, fecha date,
    month_key date, cur_cell integer, new_cell integer, keep boolean NOT NULL DEFAULT false,
    od_conflict boolean NOT NULL DEFAULT false, pobox_move boolean NOT NULL DEFAULT false,
    dest_bad boolean NOT NULL DEFAULT false,
    -- congelado: no se puede mover (destino sin panelista activo, origen = destino sin arreglo o sin celda
    -- valida); se queda donde esta y cuenta como carga fija de su celda actual (si la tiene).
    frozen boolean NOT NULL DEFAULT false,
    dest_city uuid,
    -- fechas del plan del envio; NULL = sin restriccion (el envio ya esta fuera de su plan: dato incoherente que
    -- no se castiga borrandolo)
    plan_start date, plan_end date,
    pl_end date,   -- fin real del plan (para el horizonte de R3 cuando el envio esta fuera de su plan)
    def_blocked boolean NOT NULL DEFAULT false,   -- se apartaria pero tiene dependientes (R2): se queda
    -- fase 0: motivo para apartarlo al registro (NULL = se queda en el plan)
    defer_reason text,
    -- fase 0: destino reasignado dentro de la ciudad destino (dest_node ya es el nuevo)
    new_dest boolean NOT NULL DEFAULT false, new_dest_pid uuid, new_dest_pname text,
    -- muestra reintroducida (generation_source = 'compensation'); comp_frozen = fija en su hueco valido (R7)
    comp boolean NOT NULL DEFAULT false, comp_frozen boolean NOT NULL DEFAULT false
  ) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_ship (id, cur_node, cur_code, cur_rank, dest_node, dest_city, fecha, month_key, dest_bad,
                                plan_start, plan_end, pl_end, comp)
  SELECT a.id, a.origin_node_id, n.node_code, n.all_rank, a.destination_node_id, dn.city_id, a.fecha_programada,
         date_trunc('month', GREATEST(a.fecha_programada, v_from))::date,
         -- destino sin panelista activo: ninguna fecha es valida para el (spec 5.3)
         NOT EXISTS (SELECT 1 FROM public.panelists p
                      WHERE p.node_id = a.destination_node_id AND p.account_id = v_account_id AND p.status = 'active'),
         CASE WHEN a.fecha_programada BETWEEN pl.start_date AND pl.end_date THEN pl.start_date END,
         CASE WHEN a.fecha_programada BETWEEN pl.start_date AND pl.end_date THEN pl.end_date END,
         pl.end_date, a.generation_source = 'compensation'
    FROM public.allocation_plan_details a
    JOIN pg_temp.lb2_nodes n ON n.node_id = a.origin_node_id
    LEFT JOIN public.nodes dn ON dn.id = a.destination_node_id
    LEFT JOIN public.allocation_plans pl ON pl.id = a.plan_id
   WHERE a.account_id = v_account_id
     AND a.status = 'pending'
     AND a.fecha_programada BETWEEN p_start_date AND p_end_date;
  SELECT count(*) INTO v_total FROM pg_temp.lb2_ship;

  -- ===== 0. Muestras por compensar (spec 2026-10-28, 3.1). Orden de prioridad: origen, destino, dia.
  -- 0a. Ciudad sin ningun nodo valido: el origen no se puede reasignar => todas al registro.
  IF v_n_nodes = 0 THEN
    UPDATE pg_temp.lb2_ship SET defer_reason = 'origin_no_panelist' WHERE TRUE;
  END IF;

  -- 0b. Destino sin panelista activo: otro nodo activo con panelista activo de la MISMA ciudad destino (distinto
  -- del nodo origen), el de menos recepciones en la semana ISO del envio (empate: en el periodo, luego codigo);
  -- se prefieren los no ausentes ese dia. Sin alternativa => al registro.
  IF EXISTS (SELECT 1 FROM pg_temp.lb2_ship WHERE dest_bad AND defer_reason IS NULL) THEN
    CREATE TEMP TABLE pg_temp.lb2_alt (
      node_id uuid PRIMARY KEY, city_id uuid, node_code text, panelist_id uuid, panelist_name text
    ) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_alt
    SELECT n.id, n.city_id, n.auto_id, pan.id, pan.name::text
      FROM public.nodes n
      JOIN LATERAL (SELECT p.id, p.name FROM public.panelists p
                     WHERE p.node_id = n.id AND p.account_id = v_account_id AND p.status = 'active'
                     ORDER BY p.created_at, p.id LIMIT 1) pan ON true
     WHERE n.account_id = v_account_id AND n.status = 'active'
       AND n.city_id IN (SELECT DISTINCT s.dest_city FROM pg_temp.lb2_ship s WHERE s.dest_bad AND s.defer_reason IS NULL);

    UPDATE pg_temp.lb2_ship s SET defer_reason = 'dest_no_panelist'
     WHERE s.dest_bad AND s.defer_reason IS NULL
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_alt t WHERE t.city_id = s.dest_city AND t.node_id <> s.cur_node);

    IF EXISTS (SELECT 1 FROM pg_temp.lb2_ship WHERE dest_bad AND defer_reason IS NULL) THEN
      CREATE TEMP TABLE pg_temp.lb2_altload (node_id uuid, d date, n integer) ON COMMIT DROP;
      INSERT INTO pg_temp.lb2_altload
      SELECT a.destination_node_id, a.fecha_programada, count(*)::int
        FROM public.allocation_plan_details a
        JOIN pg_temp.lb2_alt t ON t.node_id = a.destination_node_id
       WHERE a.account_id = v_account_id AND a.status <> 'cancelled'
         AND a.fecha_programada BETWEEN date_trunc('week', p_start_date)::date AND p_end_date + 6
       GROUP BY a.destination_node_id, a.fecha_programada;
      CREATE INDEX ON pg_temp.lb2_altload (node_id, d);
      CREATE TEMP TABLE pg_temp.lb2_altabs (node_id uuid, d date, PRIMARY KEY (node_id, d)) ON COMMIT DROP;
      INSERT INTO pg_temp.lb2_altabs
      SELECT DISTINCT p.node_id, g::date
        FROM public.panelist_unavailability u
        JOIN public.panelists p ON p.id = u.panelist_id AND p.account_id = v_account_id AND p.status = 'active'
        JOIN pg_temp.lb2_alt t ON t.node_id = p.node_id
        CROSS JOIN LATERAL generate_series(GREATEST(u.start_date, p_start_date), LEAST(u.end_date, p_end_date),
                                           interval '1 day') g
       WHERE u.account_id = v_account_id AND u.status = 'active'
         AND u.start_date <= p_end_date AND u.end_date >= p_start_date;

      -- Uno a uno (por fecha) para que la carga de los ya reasignados cuente en los siguientes.
      FOR v_conf IN
        SELECT s.id FROM pg_temp.lb2_ship s WHERE s.dest_bad AND s.defer_reason IS NULL ORDER BY s.fecha, s.id
      LOOP
        SELECT s.fecha, s.cur_node, s.dest_city INTO v_cur FROM pg_temp.lb2_ship s WHERE s.id = v_conf.id;
        v_wk := date_trunc('week', v_cur.fecha)::date;
        SELECT t.node_id, t.panelist_id, t.panelist_name INTO v_other
          FROM pg_temp.lb2_alt t
         WHERE t.city_id = v_cur.dest_city AND t.node_id <> v_cur.cur_node
         ORDER BY EXISTS (SELECT 1 FROM pg_temp.lb2_altabs x WHERE x.node_id = t.node_id AND x.d = v_cur.fecha),
                  (SELECT COALESCE(sum(l.n), 0) FROM pg_temp.lb2_altload l
                    WHERE l.node_id = t.node_id AND l.d BETWEEN v_wk AND v_wk + 6),
                  (SELECT COALESCE(sum(l.n), 0) FROM pg_temp.lb2_altload l
                    WHERE l.node_id = t.node_id AND l.d BETWEEN p_start_date AND p_end_date),
                  t.node_code, t.node_id
         LIMIT 1;
        IF NOT FOUND THEN   -- no deberia ocurrir (filtrado arriba); por seguridad, al registro
          UPDATE pg_temp.lb2_ship SET defer_reason = 'dest_no_panelist' WHERE id = v_conf.id;
          CONTINUE;
        END IF;
        UPDATE pg_temp.lb2_ship
           SET dest_node = v_other.node_id, dest_bad = false, new_dest = true,
               new_dest_pid = v_other.panelist_id, new_dest_pname = v_other.panelist_name
         WHERE id = v_conf.id;
        INSERT INTO pg_temp.lb2_altload VALUES (v_other.node_id, v_cur.fecha, 1);
      END LOOP;
    END IF;
  END IF;
  -- Sin efecto tras 0b (todo destino sin panelista se reasigna o se aparta); se conserva por seguridad.
  UPDATE pg_temp.lb2_ship SET frozen = true WHERE dest_bad AND defer_reason IS NULL;

  -- Ausencias de los nodos DESTINO de esos envios (spec 5.3: no se programa un dia de ausencia ni como origen
  -- ni como destino). Un envio no puede ir a una celda cuya fecha este aqui para su destino.
  CREATE TEMP TABLE pg_temp.lb2_sdabs (node_id uuid, d date, PRIMARY KEY (node_id, d)) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_sdabs
  SELECT DISTINCT p.node_id, dd.d
    FROM public.panelist_unavailability u
    JOIN public.panelists p ON p.id = u.panelist_id AND p.account_id = v_account_id AND p.status = 'active'
    JOIN (SELECT DISTINCT dest_node FROM pg_temp.lb2_ship) sd ON sd.dest_node = p.node_id
    JOIN pg_temp.lb2_days dd ON dd.d BETWEEN u.start_date AND u.end_date
   WHERE u.account_id = v_account_id AND u.status = 'active';

  -- Atrasados: cuentan en el mes de v_from; si ese mes ya no tiene celdas, en el primer mes siguiente que las tenga.
  UPDATE pg_temp.lb2_ship s SET month_key = m.next_month
    FROM (SELECT min(month_start) AS next_month FROM pg_temp.lb2_cells
           WHERE month_start > date_trunc('month', v_from)::date) m
   WHERE s.fecha < v_from AND m.next_month IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_cells c WHERE c.month_start = s.month_key);

  -- R7. Una reintroducida pendiente ('compensation') que esta en un hueco valido se queda FIJA donde esta: no la
  -- mueven ni el reparto equitativo, ni el paso al primer dia del tramo (politica semanal), ni POBOX. Asi los
  -- topes totales de la fase R (1 compensation por (nodo origen, dia) y por (nodo destino, dia)) se mantienen al
  -- repetir el balanceo. Hueco valido: dia laborable del periodo dentro de su plan, nodo origen valido y no
  -- ausente, nodo destino activo con panelista activo, no ausente y distinto del origen. Cuenta como carga fija
  -- (objetivos, desviaciones, matrices, topes) y no se avisa como no_valid_cell. Si deja de estar en un hueco
  -- valido (baja declarada despues, nodo sin panelista...) se trata como cualquier otra muestra movible.
  -- Politica semanal: por esto la reintroducida conserva para siempre su dia real.
  UPDATE pg_temp.lb2_ship s SET frozen = true, comp_frozen = true
   WHERE s.comp AND s.defer_reason IS NULL AND NOT s.frozen AND NOT s.dest_bad
     AND s.plan_start IS NOT NULL                       -- fecha dentro de su plan
     AND s.dest_node <> s.cur_node
     AND EXISTS (SELECT 1 FROM pg_temp.lb2_days dd WHERE dd.d = s.fecha)
     AND EXISTS (SELECT 1 FROM pg_temp.lb2_nodes n WHERE n.node_id = s.cur_node AND n.valid)
     AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_absent x WHERE x.node_id = s.cur_node AND x.d = s.fecha)
     AND EXISTS (SELECT 1 FROM public.nodes dn WHERE dn.id = s.dest_node AND dn.status = 'active')
     AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = s.dest_node AND x.d = s.fecha);

  -- 0c. Sin dia valido. Celda compatible = de otro nodo que el destino, sin ausencia del destino ese dia y dentro
  -- de las fechas del plan. Si el mes del envio no tiene ninguna, se busca en los demas meses del periodo (la
  -- celda compatible mas cercana decide el mes; el reparto normal elige luego la celda dentro de ese mes). Si no
  -- hay en ningun mes => al registro, salvo que el unico obstaculo sea origen = destino (celdas del propio nodo
  -- destino: se mantiene el aviso origin_equals_destination / no_valid_cell, no se borra). Si el periodo no
  -- tiene ningun dia laborable >= hoy (periodo pasado) no se aparta nada por este motivo.
  IF EXISTS (SELECT 1 FROM pg_temp.lb2_days) THEN
    UPDATE pg_temp.lb2_ship s SET month_key = x.m
      FROM (SELECT s2.id,
                   (SELECT c.month_start FROM pg_temp.lb2_cells c
                     WHERE c.node_id <> s2.dest_node
                       AND (s2.plan_start IS NULL OR c.cell_date BETWEEN s2.plan_start AND s2.plan_end)
                       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs a WHERE a.node_id = s2.dest_node AND a.d = c.cell_date)
                     ORDER BY abs(c.cell_date - GREATEST(s2.fecha, v_from)), c.cell_date, c.valid_rank
                     LIMIT 1) AS m
              FROM pg_temp.lb2_ship s2
             WHERE s2.defer_reason IS NULL AND NOT s2.comp_frozen
               AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_cells c
                                WHERE c.month_start = s2.month_key AND c.node_id <> s2.dest_node
                                  AND (s2.plan_start IS NULL OR c.cell_date BETWEEN s2.plan_start AND s2.plan_end)
                                  AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs a
                                                   WHERE a.node_id = s2.dest_node AND a.d = c.cell_date))) x
     WHERE x.id = s.id AND x.m IS NOT NULL;
    UPDATE pg_temp.lb2_ship s SET defer_reason = 'no_valid_day'
     WHERE s.defer_reason IS NULL AND NOT s.comp_frozen
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_cells c
                        WHERE c.month_start = s.month_key AND c.node_id <> s.dest_node
                          AND (s.plan_start IS NULL OR c.cell_date BETWEEN s.plan_start AND s.plan_end)
                          AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs a WHERE a.node_id = s.dest_node AND a.d = c.cell_date))
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_cells c
                        WHERE c.node_id = s.dest_node
                          AND (s.plan_start IS NULL OR c.cell_date BETWEEN s.plan_start AND s.plan_end));
  END IF;

  -- 0c bis (R3). no_valid_day solo borra si no hay NINGUN hueco en el resto del horizonte del plan, no solo en el
  -- periodo de la pantalla: dia laborable en [max(v_from, inicio del plan), fin del plan] con algun nodo valido de
  -- esta ciudad no ausente y algun nodo valido (activo + panelista activo) de la ciudad destino no ausente. Si lo
  -- hay, la muestra se queda donde esta (carga fija, aviso no_valid_cell) para balancear con un periodo mas ancho.
  -- Por combinacion distinta (ciudad destino, horizonte), no por fila.
  IF EXISTS (SELECT 1 FROM pg_temp.lb2_ship WHERE defer_reason = 'no_valid_day') THEN
    CREATE TEMP TABLE pg_temp.lb2_hz (
      dest_city uuid, h_from date, h_to date, has_slot boolean NOT NULL DEFAULT false
    ) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_hz (dest_city, h_from, h_to)
    SELECT DISTINCT s.dest_city, GREATEST(v_from, COALESCE(s.plan_start, v_from)),
           COALESCE(s.plan_end, GREATEST(s.pl_end, p_end_date))
      FROM pg_temp.lb2_ship s WHERE s.defer_reason = 'no_valid_day';
    UPDATE pg_temp.lb2_hz h
       SET has_slot = EXISTS (
             SELECT 1 FROM generate_series(h.h_from, h.h_to, interval '1 day') g
              WHERE public.is_account_working_day(v_account_id, g::date)
                AND EXISTS (SELECT 1 FROM pg_temp.lb2_nodes n
                             WHERE n.valid
                               AND NOT EXISTS (SELECT 1 FROM public.panelist_unavailability u
                                                 JOIN public.panelists p ON p.id = u.panelist_id
                                                  AND p.account_id = v_account_id AND p.status = 'active'
                                                WHERE p.node_id = n.node_id AND u.account_id = v_account_id
                                                  AND u.status = 'active' AND g::date BETWEEN u.start_date AND u.end_date))
                AND EXISTS (SELECT 1 FROM public.nodes dn
                             WHERE dn.city_id = h.dest_city AND dn.account_id = v_account_id AND dn.status = 'active'
                               AND EXISTS (SELECT 1 FROM public.panelists p
                                            WHERE p.node_id = dn.id AND p.account_id = v_account_id AND p.status = 'active')
                               AND NOT EXISTS (SELECT 1 FROM public.panelist_unavailability u
                                                 JOIN public.panelists p ON p.id = u.panelist_id
                                                  AND p.account_id = v_account_id AND p.status = 'active'
                                                WHERE p.node_id = dn.id AND u.account_id = v_account_id
                                                  AND u.status = 'active' AND g::date BETWEEN u.start_date AND u.end_date)))
     WHERE h.h_from <= h.h_to;
    UPDATE pg_temp.lb2_ship s SET defer_reason = NULL, frozen = true
      FROM pg_temp.lb2_hz h
     WHERE s.defer_reason = 'no_valid_day' AND h.has_slot
       AND h.dest_city = s.dest_city
       AND h.h_from = GREATEST(v_from, COALESCE(s.plan_start, v_from))
       AND h.h_to = COALESCE(s.plan_end, GREATEST(s.pl_end, p_end_date));
  END IF;

  -- 0c ter (R2). Nunca se borra una muestra con dependientes que el borrado arrastraria o desenlazaria:
  -- material_hold.allocation_plan_detail_id (CASCADE), shipment_incident.parcel_id (CASCADE),
  -- panelist_incident.allocation_plan_detail_id y one_db.allocation_detail_id (SET NULL). Se queda donde esta
  -- (congelada, carga fija) y se avisa con deferred_blocked. Las propuestas de panelist_reassignment_proposal SI
  -- caen en cascada: se refieren a una muestra que deja de existir en el plan (la anotacion conserva la fila).
  UPDATE pg_temp.lb2_ship s SET defer_reason = NULL, frozen = true, def_blocked = true
   WHERE s.defer_reason IS NOT NULL
     AND s.id IN (SELECT m.allocation_plan_detail_id FROM public.material_hold m
                   WHERE m.allocation_plan_detail_id IN (SELECT c.id FROM pg_temp.lb2_ship c WHERE c.defer_reason IS NOT NULL)
                  UNION
                  SELECT si.parcel_id FROM public.shipment_incident si
                   WHERE si.parcel_id IN (SELECT c.id FROM pg_temp.lb2_ship c WHERE c.defer_reason IS NOT NULL)
                  UNION
                  SELECT pi.allocation_plan_detail_id FROM public.panelist_incident pi
                   WHERE pi.allocation_plan_detail_id IN (SELECT c.id FROM pg_temp.lb2_ship c WHERE c.defer_reason IS NOT NULL)
                  UNION
                  SELECT o.allocation_detail_id FROM public.one_db o
                   WHERE o.allocation_detail_id IN (SELECT c.id FROM pg_temp.lb2_ship c WHERE c.defer_reason IS NOT NULL));
  SELECT count(*) INTO v_def_blocked FROM pg_temp.lb2_ship WHERE def_blocked;

  -- 0d. Las apartadas salen del calculo: no cuentan en totales del mes, objetivos, desviaciones ni matrices.
  CREATE TEMP TABLE pg_temp.lb2_defer (id uuid PRIMARY KEY, reason text NOT NULL) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_defer SELECT s.id, s.defer_reason FROM pg_temp.lb2_ship s WHERE s.defer_reason IS NOT NULL;
  SELECT count(*), count(*) FILTER (WHERE reason = 'origin_no_panelist'),
         count(*) FILTER (WHERE reason = 'dest_no_panelist'), count(*) FILTER (WHERE reason = 'no_valid_day')
    INTO v_def_removed, v_def_origin, v_def_dest, v_def_day
    FROM pg_temp.lb2_defer;
  DELETE FROM pg_temp.lb2_ship WHERE defer_reason IS NOT NULL;
  SELECT count(*) INTO v_def_reassigned FROM pg_temp.lb2_ship WHERE new_dest;
  SELECT count(*) INTO v_def_waiting FROM public.deferred_samples d
   WHERE d.account_id = v_account_id AND d.origin_city_id = p_city_id AND d.status = 'pending';
  v_def_waiting := v_def_waiting + v_def_removed;

  -- Filtro por fechas del plan en el reparto normal: una celda fuera de las fechas del plan de todos los envios
  -- de la ciudad no recibe objetivo (sin restricciones de plan no cambia nada).
  UPDATE pg_temp.lb2_cells c
     SET in_plan = EXISTS (SELECT 1 FROM pg_temp.lb2_ship s
                            WHERE s.plan_start IS NULL OR c.cell_date BETWEEN s.plan_start AND s.plan_end)
   WHERE TRUE;

  -- Celda actual de cada envio (si la tiene).
  IF v_date_policy = 'weekly' THEN
    UPDATE pg_temp.lb2_ship s SET cur_cell = c.cell_id
      FROM pg_temp.lb2_cells c
     WHERE c.node_id = s.cur_node
       AND c.week_start = date_trunc('week', s.fecha)::date
       AND c.month_start = date_trunc('month', s.fecha)::date
       AND c.month_start = s.month_key;
  ELSE
    UPDATE pg_temp.lb2_ship s SET cur_cell = c.cell_id
      FROM pg_temp.lb2_cells c
     WHERE c.node_id = s.cur_node AND c.cell_date = s.fecha;
  END IF;
  UPDATE pg_temp.lb2_cells c SET current_load = x.n
    FROM (SELECT cur_cell, count(*)::int AS n FROM pg_temp.lb2_ship WHERE cur_cell IS NOT NULL GROUP BY cur_cell) x
   WHERE x.cur_cell = c.cell_id;

  -- ===== 5. Objetivos. Tramos con al menos una celda; peso = dias laborables del tramo en el periodo.
  CREATE TEMP TABLE pg_temp.lb2_segs (
    week_start date, month_start date, seg_from date, wdays integer, ncells integer,
    share integer NOT NULL DEFAULT 0, base integer NOT NULL DEFAULT 0, rem integer NOT NULL DEFAULT 0,
    g integer NOT NULL DEFAULT 0, PRIMARY KEY (week_start, month_start)
  ) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_segs (week_start, month_start, seg_from, wdays, ncells)
  SELECT d.week_start, d.month_start, min(d.d), count(*)::int, x.ncells
    FROM pg_temp.lb2_days d
    JOIN (SELECT week_start, month_start, count(*)::int AS ncells FROM pg_temp.lb2_cells WHERE in_plan GROUP BY 1, 2) x
      ON x.week_start = d.week_start AND x.month_start = d.month_start
   WHERE EXISTS (SELECT 1 FROM pg_temp.lb2_ship s
                  WHERE s.plan_start IS NULL OR d.d BETWEEN s.plan_start AND s.plan_end)
   GROUP BY d.week_start, d.month_start, x.ncells;

  -- Envios congelados ANTES de calcular objetivos: destino sin panelista activo (ya marcados) y envios cuyo
  -- mes tiene celdas pero ninguna compatible (todas del nodo destino o en dias de ausencia del destino). Se
  -- quedan donde estan y cuentan como carga fija de su celda actual, si la tienen.
  UPDATE pg_temp.lb2_ship s SET frozen = true
   WHERE NOT s.frozen
     AND EXISTS (SELECT 1 FROM pg_temp.lb2_cells c WHERE c.month_start = s.month_key)
     AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_cells c
                      WHERE c.month_start = s.month_key AND c.node_id <> s.dest_node
                        AND (s.plan_start IS NULL OR c.cell_date BETWEEN s.plan_start AND s.plan_end)
                        AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = s.dest_node AND x.d = c.cell_date));
  UPDATE pg_temp.lb2_cells c SET fixed = x.n
    FROM (SELECT cur_cell, count(*)::int AS n FROM pg_temp.lb2_ship WHERE frozen AND cur_cell IS NOT NULL GROUP BY cur_cell) x
   WHERE x.cur_cell = c.cell_id;

  -- 5a. Total del mes -> tramos (suelo + resto mayor; empate -> tramo mas temprano). El total es la carga
  -- final del mes: envios movibles + envios congelados que ya ocupan una celda del mes (carga fija). Los
  -- congelados fuera de toda celda no cuentan.
  WITH mt AS (SELECT month_key, sum(n)::numeric AS t
                FROM (SELECT month_key, count(*) AS n FROM pg_temp.lb2_ship WHERE NOT frozen GROUP BY month_key
                      UNION ALL
                      SELECT month_start, sum(fixed) FROM pg_temp.lb2_cells WHERE fixed > 0 GROUP BY month_start) u
               GROUP BY month_key),
  w AS (SELECT s.week_start, s.month_start, s.seg_from, mt.t,
               s.wdays * mt.t / sum(s.wdays) OVER (PARTITION BY s.month_start) AS raw
          FROM pg_temp.lb2_segs s JOIN mt ON mt.month_key = s.month_start),
  f AS (SELECT w.*, floor(w.raw)::int AS fl FROM w),
  r AS (SELECT f.*, f.t::int - sum(f.fl) OVER (PARTITION BY f.month_start) AS leftover,
               row_number() OVER (PARTITION BY f.month_start ORDER BY f.raw - f.fl DESC, f.seg_from) AS rk
          FROM f)
  UPDATE pg_temp.lb2_segs s SET share = r.fl + CASE WHEN r.rk <= r.leftover THEN 1 ELSE 0 END
    FROM r WHERE r.week_start = s.week_start AND r.month_start = s.month_start;
  UPDATE pg_temp.lb2_segs SET base = share / ncells, rem = share % ncells WHERE ncells > 0;
  v_had_remainder := EXISTS (SELECT 1 FROM pg_temp.lb2_segs WHERE rem > 0);

  -- 5b. Puntero de rotacion por tramo: empieza en balance_rotation_offset mod N y avanza tantos nodos como +1
  -- se repartieron en los tramos anteriores (asi los +1 no caen siempre en los mismos nodos).
  UPDATE pg_temp.lb2_segs s SET g = x.g
    FROM (SELECT week_start, month_start,
                 ((v_offset + COALESCE(sum(rem) OVER (ORDER BY seg_from ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0))
                   % NULLIF(v_n_nodes, 0))::int AS g
            FROM pg_temp.lb2_segs) x
   WHERE x.week_start = s.week_start AND x.month_start = s.month_start;

  -- 5c. Tramo -> celdas: base para todas; los rem +1 van por orden (vuelta, nodo rotado). La "vuelta" de una
  -- celda desplaza el dia segun el nodo, para que los +1 de nodos distintos caigan en dias distintos.
  WITH q AS (
    SELECT c.cell_id, c.week_start, c.month_start, c.cell_date, s.base, s.rem,
           (((c.valid_rank - s.g) % v_n_nodes) + v_n_nodes) % v_n_nodes AS qn, c.day_idx, c.node_cells
      FROM pg_temp.lb2_cells c JOIN pg_temp.lb2_segs s ON s.week_start = c.week_start AND s.month_start = c.month_start
     WHERE c.in_plan),
  o AS (
    SELECT q.cell_id, q.base, q.rem,
           row_number() OVER (PARTITION BY q.week_start, q.month_start
                              ORDER BY (((q.day_idx - q.qn) % q.node_cells) + q.node_cells) % q.node_cells,
                                       q.qn, q.cell_date) AS ord
      FROM q)
  UPDATE pg_temp.lb2_cells c SET target = o.base + CASE WHEN o.ord <= o.rem THEN 1 ELSE 0 END
    FROM o WHERE o.cell_id = c.cell_id;

  -- 5d. Carga fija: el objetivo de cada celda pasa a ser de envios MOVIBLES = objetivo total - fijos (>= 0).
  -- Si una celda tiene mas fijos que su objetivo, sobran huecos en el mes: se quitan los de nivel final
  -- (fijos + k) mas alto, de modo que cada mes tenga exactamente tantos huecos como envios movibles. Sin
  -- congelados no cambia nada.
  IF EXISTS (SELECT 1 FROM pg_temp.lb2_cells WHERE fixed > 0) THEN
    UPDATE pg_temp.lb2_cells SET target = GREATEST(target - fixed, 0)
     WHERE TRUE;
    WITH mm AS (SELECT month_key, count(*)::int AS m FROM pg_temp.lb2_ship WHERE NOT frozen GROUP BY month_key),
    u AS (SELECT c.cell_id, c.month_start,
                 row_number() OVER (PARTITION BY c.month_start ORDER BY c.fixed + k.k, c.cell_date, c.valid_rank, k.k) AS rn
            FROM pg_temp.lb2_cells c CROSS JOIN LATERAL generate_series(1, c.target) k(k)),
    kp AS (SELECT u.cell_id, count(*)::int AS n
             FROM u LEFT JOIN mm ON mm.month_key = u.month_start
            WHERE u.rn <= COALESCE(mm.m, 0) GROUP BY u.cell_id)
    UPDATE pg_temp.lb2_cells c SET target = COALESCE(kp.n, 0)
      FROM pg_temp.lb2_cells c2 LEFT JOIN kp ON kp.cell_id = c2.cell_id
     WHERE c2.cell_id = c.cell_id;
  END IF;

  -- ===== 6. Asignacion con minimos movimientos.
  -- 6a. En cada celda se quedan hasta 'target' envios (los de fecha mas temprana; sale primero el mas lejano).
  -- Un envio cuyo destino esta ausente ese dia (o no tiene panelista activo) no puede quedarse: es excedente.
  WITH k AS (
    SELECT s.id, c.target,
           row_number() OVER (PARTITION BY s.cur_cell ORDER BY s.fecha, s.id) AS rn
      FROM pg_temp.lb2_ship s JOIN pg_temp.lb2_cells c ON c.cell_id = s.cur_cell
     WHERE NOT s.frozen
       AND c.month_start = s.month_key
       AND (s.plan_start IS NULL OR c.cell_date BETWEEN s.plan_start AND s.plan_end)
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = s.dest_node AND x.d = c.cell_date))
  UPDATE pg_temp.lb2_ship s SET keep = true, new_cell = s.cur_cell
    FROM k WHERE k.id = s.id AND k.rn <= k.target;
  UPDATE pg_temp.lb2_cells c SET kept = x.n
    FROM (SELECT cur_cell, count(*)::int AS n FROM pg_temp.lb2_ship WHERE keep GROUP BY cur_cell) x
   WHERE x.cur_cell = c.cell_id;

  -- 6b. Excedentes (sobrantes de celdas por encima del objetivo + envios fuera de toda celda) contra huecos de
  -- celdas deficitarias del MISMO mes. Ambos lados ordenados por fecha: el emparejamiento ordenado minimiza la
  -- distancia total en dias. Por construccion, en cada mes con celdas hay tantos huecos como excedentes.
  WITH ex AS (
    SELECT s.id, s.month_key,
           row_number() OVER (PARTITION BY s.month_key ORDER BY s.fecha, s.cur_rank, s.id) AS rk
      FROM pg_temp.lb2_ship s WHERE NOT s.keep AND NOT s.frozen),
  sl AS (
    SELECT c.cell_id, c.month_start,
           row_number() OVER (PARTITION BY c.month_start ORDER BY c.cell_date, c.valid_rank, k.k) AS rk
      FROM pg_temp.lb2_cells c CROSS JOIN LATERAL generate_series(1, c.target - c.kept) k(k)
     WHERE c.target > c.kept)
  UPDATE pg_temp.lb2_ship s SET new_cell = sl.cell_id
    FROM ex JOIN sl ON sl.month_start = ex.month_key AND sl.rk = ex.rk
   WHERE s.id = ex.id;

  -- 6c. Celda incompatible con el envio: origen = destino (ruta dentro de la ciudad), destino ausente ese dia o
  -- destino sin panelista activo. Se intercambia la celda con otro excedente del mismo mes compatible en ambos
  -- sentidos. Si no hay: origen = destino => el envio se queda donde esta (aviso origin_equals_destination);
  -- destino ausente => celda compatible mas cercana del mismo mes (la menos cargada), y si no existe o el destino
  -- no tiene panelista activo, el envio se queda donde esta (aviso no_valid_cell). Bucle vacio con datos normales.
  FOR v_conf IN
    SELECT s.id FROM pg_temp.lb2_ship s JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell
     WHERE NOT s.keep
       AND (c.node_id = s.dest_node OR s.dest_bad
            OR EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = s.dest_node AND x.d = c.cell_date)
            OR (s.plan_start IS NOT NULL AND c.cell_date NOT BETWEEN s.plan_start AND s.plan_end))
     ORDER BY s.fecha, s.id
  LOOP
    -- dabs: dia no valido para el envio (destino ausente o fuera de las fechas de su plan)
    SELECT s.new_cell, s.month_key, s.dest_node, s.dest_bad, s.fecha, s.plan_start, s.plan_end, c.node_id, c.cell_date,
           (EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = s.dest_node AND x.d = c.cell_date)
            OR (s.plan_start IS NOT NULL AND c.cell_date NOT BETWEEN s.plan_start AND s.plan_end)) AS dabs
      INTO v_cur FROM pg_temp.lb2_ship s JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell WHERE s.id = v_conf.id;
    -- ya resuelto por un intercambio previo
    CONTINUE WHEN NOT FOUND OR (v_cur.node_id <> v_cur.dest_node AND NOT v_cur.dest_bad AND NOT v_cur.dabs);
    IF v_cur.dest_bad THEN
      UPDATE pg_temp.lb2_ship SET new_cell = NULL WHERE id = v_conf.id;
      CONTINUE;
    END IF;
    SELECT s2.id, s2.new_cell INTO v_other
      FROM pg_temp.lb2_ship s2 JOIN pg_temp.lb2_cells c2 ON c2.cell_id = s2.new_cell
     WHERE NOT s2.keep AND s2.month_key = v_cur.month_key AND s2.id <> v_conf.id AND NOT s2.dest_bad
       AND c2.node_id <> v_cur.dest_node AND s2.dest_node IS DISTINCT FROM v_cur.node_id
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = v_cur.dest_node AND x.d = c2.cell_date)
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = s2.dest_node AND x.d = v_cur.cell_date)
       AND (v_cur.plan_start IS NULL OR c2.cell_date BETWEEN v_cur.plan_start AND v_cur.plan_end)
       AND (s2.plan_start IS NULL OR v_cur.cell_date BETWEEN s2.plan_start AND s2.plan_end)
     ORDER BY abs(c2.cell_date - v_cur.fecha), c2.cell_date
     LIMIT 1;
    IF FOUND THEN
      UPDATE pg_temp.lb2_ship SET new_cell = v_cur.new_cell WHERE id = v_other.id;
      UPDATE pg_temp.lb2_ship SET new_cell = v_other.new_cell WHERE id = v_conf.id;
    ELSIF NOT v_cur.dabs THEN
      UPDATE pg_temp.lb2_ship SET new_cell = NULL, od_conflict = true WHERE id = v_conf.id;
    ELSE
      v_fb_cell := NULL;
      SELECT c3.cell_id INTO v_fb_cell
        FROM pg_temp.lb2_cells c3
       WHERE c3.month_start = v_cur.month_key AND c3.node_id <> v_cur.dest_node
         AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = v_cur.dest_node AND x.d = c3.cell_date)
         AND (v_cur.plan_start IS NULL OR c3.cell_date BETWEEN v_cur.plan_start AND v_cur.plan_end)
       ORDER BY abs(c3.cell_date - v_cur.cell_date),
                (SELECT count(*) FROM pg_temp.lb2_ship x WHERE x.new_cell = c3.cell_id) + c3.fixed, c3.cell_date, c3.valid_rank
       LIMIT 1;
      UPDATE pg_temp.lb2_ship SET new_cell = v_fb_cell WHERE id = v_conf.id;
    END IF;
  END LOOP;

  -- Los que 6c deja sin celda (origen = destino sin intercambio posible; raro, porque tienen celdas
  -- compatibles) se quedan donde estan: tambien cuentan como carga fija en su celda actual para new_load,
  -- matrix_after y stddev_after. No se recalculan los objetivos: repetir la asignacion congelaria en cascada
  -- envios que si se podian mover (su hueco queda libre; ver aviso origin_equals_destination).
  UPDATE pg_temp.lb2_ship SET frozen = true WHERE NOT frozen AND new_cell IS NULL;

  -- ===== 6R. REINTRODUCCION de muestras por compensar (spec 2026-10-28, 3.2). Despues de la equidad y antes de
  -- POBOX. Candidatas: anotaciones 'pending' cuya ciudad origen es esta. Cada una se coloca en un hueco valido:
  --   * dia laborable de la cuenta en [v_from, fin] y en las fechas de su plan (plan 'active');
  --   * nodo origen: el original si es valido y no esta ausente ese dia; si no, el menos cargado de la ciudad;
  --   * nodo destino: el original si es valido y no esta ausente ese dia; si no, el de menos recepciones ese dia
  --     de la ciudad destino de la anotacion (la ruta ciudad->ciudad no cambia); siempre distinto del nodo origen;
  --   * dia con menos envios del nodo origen (empate: menos recepciones del destino ese dia, menos envios de la
  --     ciudad, fecha); topes TOTALES: como maximo 1 fila 'compensation' por (nodo origen, dia) y 1 por (nodo
  --     destino, dia), contando las que ya existen en el plan (repetir el balanceo no las apila).
  -- Las que no caben esperan con un motivo (plan_inactive, outside_period, no_origin_panelist,
  -- no_dest_panelist, no_capacity) que solo se escribe al aplicar. Las anotaciones apartadas en ESTA ejecucion
  -- (fase 0) aun no estan en el registro: no se reintroducen hasta el siguiente balanceo.
  -- (Sin indices: pocas filas; cada objeto temporal cuesta tiempo de catalogo en cada llamada.)
  CREATE TEMP TABLE pg_temp.lb2_reint (
    id uuid NOT NULL, ds_id uuid NOT NULL, plan_id uuid, o_node uuid, d_node uuid, d date,
    o_pid uuid, o_pname text, d_pid uuid, d_pname text, ds_o_node uuid, ds_d_node uuid, cell_id integer
  ) ON COMMIT DROP;

  -- Al aplicar, las anotaciones de la ciudad se bloquean antes de leerlas (ademas del candado por ciudad).
  IF p_apply_changes THEN
    PERFORM 1 FROM public.deferred_samples d
     WHERE d.account_id = v_account_id AND d.origin_city_id = p_city_id AND d.status = 'pending'
       FOR UPDATE;
  END IF;
  v_rc_any := EXISTS (SELECT 1 FROM public.deferred_samples d
                       WHERE d.account_id = v_account_id AND d.origin_city_id = p_city_id AND d.status = 'pending');
  IF v_rc_any THEN
    CREATE TEMP TABLE pg_temp.lb2_rcand (
      ds_id uuid NOT NULL, ord integer, plan_id uuid, o_node uuid, d_node uuid, dest_city uuid,
      ps date, pe date, plan_ok boolean NOT NULL, placed boolean NOT NULL DEFAULT false, waiting text
    ) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_rcand (ds_id, ord, plan_id, o_node, d_node, dest_city, ps, pe, plan_ok)
    SELECT d.id, (row_number() OVER (ORDER BY d.fecha_programada, d.created_at, d.id))::int, d.plan_id,
           d.origin_node_id, d.destination_node_id, d.dest_city_id,
           GREATEST(pl.start_date, v_from), LEAST(pl.end_date, p_end_date), COALESCE(pl.status = 'active', false)
      FROM public.deferred_samples d
      LEFT JOIN public.allocation_plans pl ON pl.id = d.plan_id AND pl.account_id = v_account_id
     WHERE d.account_id = v_account_id AND d.origin_city_id = p_city_id AND d.status = 'pending';
    UPDATE pg_temp.lb2_rcand SET waiting = 'plan_inactive' WHERE NOT plan_ok;
    UPDATE pg_temp.lb2_rcand c SET waiting = 'outside_period'
     WHERE c.waiting IS NULL
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_days dd WHERE dd.d BETWEEN c.ps AND c.pe);
    -- Ciudad origen sin ningun nodo valido: esperan sin construir la fase R.
    IF v_n_nodes = 0 THEN
      UPDATE pg_temp.lb2_rcand SET waiting = 'no_origin_panelist' WHERE waiting IS NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_temp.lb2_rcand WHERE waiting IS NULL) THEN
      -- Rejilla (nodo origen valido, dia laborable sin ausencia) con la carga tras la equidad. cell_id = celda de la
      -- matriz donde cuenta (diaria: la del dia; semanal: la del tramo). Politica semanal: la reintroducida
      -- conserva su dia real (no se lleva al primer dia del tramo; la spec no lo fija) y cuenta en su tramo.
      CREATE TEMP TABLE pg_temp.lb2_rload (
        node_id uuid, d date, vrank integer, cell_id integer,
        base integer NOT NULL DEFAULT 0, added integer NOT NULL DEFAULT 0
      ) ON COMMIT DROP;
      IF v_date_policy = 'weekly' THEN
        INSERT INTO pg_temp.lb2_rload (node_id, d, vrank, cell_id)
        SELECT n.node_id, dd.d, n.valid_rank, c.cell_id
          FROM pg_temp.lb2_nodes n
          CROSS JOIN pg_temp.lb2_days dd
          JOIN pg_temp.lb2_cells c ON c.node_id = n.node_id AND c.week_start = dd.week_start AND c.month_start = dd.month_start
         WHERE n.valid
           AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_absent a WHERE a.node_id = n.node_id AND a.d = dd.d);
      ELSE
        -- diaria: las celdas ya son exactamente (nodo valido, dia laborable sin ausencia)
        INSERT INTO pg_temp.lb2_rload (node_id, d, vrank, cell_id)
        SELECT c.node_id, c.cell_date, c.valid_rank, c.cell_id FROM pg_temp.lb2_cells c;
      END IF;
      -- Envios no cancelados con origen en la ciudad tras la equidad: los del periodo en su nueva celda (los
      -- congelados donde estan) y el resto (no pendientes) donde estan; las apartadas no cuentan. Tope TOTAL
      -- (no por ejecucion): 'added' parte de las filas 'compensation' que YA hay en ese (nodo, dia) y 'base' cuenta
      -- el resto; asi repetir el balanceo sobre el mismo periodo no apila mas de 1 compensation por (nodo, dia).
      -- Una sola sentencia: carga por (nodo, dia) en lb2_rload y carga de la ciudad por dia en lb2_rday.
      CREATE TEMP TABLE pg_temp.lb2_rday (d date NOT NULL, n integer NOT NULL DEFAULT 0) ON COMMIT DROP;
      WITH src AS (
        SELECT COALESCE(c.node_id, s.cur_node) AS node_id, COALESCE(c.cell_date, s.fecha) AS d,
               (a.generation_source = 'compensation') AS comp
          FROM pg_temp.lb2_ship s
          JOIN public.allocation_plan_details a ON a.id = s.id
          LEFT JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell AND NOT s.frozen
        UNION ALL
        SELECT a.origin_node_id, a.fecha_programada, (a.generation_source = 'compensation')
          FROM public.allocation_plan_details a
          JOIN pg_temp.lb2_nodes n ON n.node_id = a.origin_node_id
         WHERE a.account_id = v_account_id AND a.status <> 'cancelled'
           AND a.fecha_programada BETWEEN v_from AND p_end_date
           AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_ship s WHERE s.id = a.id)
           AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_defer x WHERE x.id = a.id)),
      upd AS (
        UPDATE pg_temp.lb2_rload g SET base = x.nb, added = x.nc
          FROM (SELECT node_id, d, (count(*) FILTER (WHERE NOT comp))::int AS nb,
                       (count(*) FILTER (WHERE comp))::int AS nc
                  FROM src GROUP BY node_id, d) x
         WHERE x.node_id = g.node_id AND x.d = g.d
        RETURNING 1)
      INSERT INTO pg_temp.lb2_rday (d, n)
      SELECT dd.d, COALESCE(x.n, 0)
        FROM pg_temp.lb2_days dd
        LEFT JOIN (SELECT d, count(*)::int AS n FROM src GROUP BY d) x ON x.d = dd.d;

      -- Destinos posibles: nodos activos con panelista activo de las ciudades destino de las candidatas.
      CREATE TEMP TABLE pg_temp.lb2_rdest (
        node_id uuid NOT NULL, city_id uuid, node_code text, panelist_id uuid, panelist_name text
      ) ON COMMIT DROP;
      INSERT INTO pg_temp.lb2_rdest
      SELECT n.id, n.city_id, n.auto_id, pan.id, pan.name::text
        FROM public.nodes n
        JOIN LATERAL (SELECT p.id, p.name FROM public.panelists p
                       WHERE p.node_id = n.id AND p.account_id = v_account_id AND p.status = 'active'
                       ORDER BY p.created_at, p.id LIMIT 1) pan ON true
       WHERE n.account_id = v_account_id AND n.status = 'active'
         AND n.city_id IN (SELECT DISTINCT c.dest_city FROM pg_temp.lb2_rcand c WHERE c.waiting IS NULL);
      -- Huecos de destino: (nodo destino valido, dia laborable del periodo sin ausencia). recv = recepciones no
      -- canceladas ese dia (las de esta ciudad en su dia tras la equidad); comp = de ellas, 'compensation' (de
      -- cualquier ciudad origen). Tope TOTAL de recepcion: como mucho 1 compensation por (nodo destino, dia).
      CREATE TEMP TABLE pg_temp.lb2_rdslot (
        city_id uuid, node_id uuid, node_code text, d date,
        recv integer NOT NULL DEFAULT 0, comp integer NOT NULL DEFAULT 0
      ) ON COMMIT DROP;
      INSERT INTO pg_temp.lb2_rdslot (city_id, node_id, node_code, d)
      SELECT t.city_id, t.node_id, t.node_code, dd.d
        FROM pg_temp.lb2_rdest t CROSS JOIN pg_temp.lb2_days dd
       WHERE NOT EXISTS (SELECT 1 FROM public.panelist_unavailability u
                           JOIN public.panelists p ON p.id = u.panelist_id AND p.account_id = v_account_id AND p.status = 'active'
                          WHERE p.node_id = t.node_id AND u.account_id = v_account_id AND u.status = 'active'
                            AND dd.d BETWEEN u.start_date AND u.end_date);
      WITH rc AS (
        SELECT s.dest_node AS node_id, COALESCE(c.cell_date, s.fecha) AS d, (a.generation_source = 'compensation') AS comp
          FROM pg_temp.lb2_ship s
          JOIN public.allocation_plan_details a ON a.id = s.id
          LEFT JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell AND NOT s.frozen
        UNION ALL
        SELECT a.destination_node_id, a.fecha_programada, (a.generation_source = 'compensation')
          FROM public.allocation_plan_details a
         WHERE a.account_id = v_account_id AND a.status <> 'cancelled'
           AND a.destination_node_id IN (SELECT t.node_id FROM pg_temp.lb2_rdest t)
           AND a.fecha_programada BETWEEN v_from AND p_end_date
           AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_ship s WHERE s.id = a.id)
           AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_defer x WHERE x.id = a.id))
      UPDATE pg_temp.lb2_rdslot r SET recv = x.n, comp = x.nc
        FROM (SELECT node_id, d, count(*)::int AS n, (count(*) FILTER (WHERE comp))::int AS nc
                FROM rc GROUP BY node_id, d) x
       WHERE x.node_id = r.node_id AND x.d = r.d;
      -- Estadisticas para que el planificador elija bien las uniones de la busqueda por candidata.
      ANALYZE pg_temp.lb2_rload;
      ANALYZE pg_temp.lb2_rdslot;
      ANALYZE pg_temp.lb2_rday;

      -- Una a una (orden: fecha original, alta) para que la carga de las ya colocadas cuente en las siguientes.
      -- Se elige (nodo origen, dia, nodo destino) a la vez:
      --   * origen: el original si ese dia es valido; si no, cualquier nodo valido de la ciudad ese dia;
      --   * destino: el original si ese dia es valido (y distinto del origen); si no, otro de la ciudad destino;
      --   * topes totales: 0 compensation previas en (origen, dia) y en (destino, dia);
      --   * orden: menos envios del nodo origen ese dia, menos recepciones del destino ese dia, menos envios de la
      --     ciudad ese dia (prefiere los dias vacios), fecha.
      FOR v_rc IN
        SELECT c.ds_id, c.plan_id, c.o_node, c.d_node, c.dest_city, c.ps, c.pe
          FROM pg_temp.lb2_rcand c WHERE c.waiting IS NULL ORDER BY c.ord
      LOOP
        SELECT g.node_id, g.d, g.cell_id, t.node_id INTO v_r_onode, v_r_day, v_r_cell, v_r_dnode
          FROM pg_temp.lb2_rload g
          JOIN pg_temp.lb2_rday y ON y.d = g.d
          JOIN pg_temp.lb2_rdslot t ON t.city_id = v_rc.dest_city AND t.d = g.d AND t.node_id <> g.node_id
          -- el nodo origen / destino original, si ese dia es valido (si lo es, solo se usa el original)
          LEFT JOIN pg_temp.lb2_rload go ON go.node_id = v_rc.o_node AND go.d = g.d
          LEFT JOIN pg_temp.lb2_rdslot td ON td.node_id = v_rc.d_node AND td.d = g.d AND td.node_id <> g.node_id
         WHERE g.d BETWEEN v_rc.ps AND v_rc.pe
           AND g.added = 0                                       -- tope origen: 1 compensation por (nodo, dia)
           AND t.comp = 0                                        -- tope destino: 1 compensation por (nodo, dia)
           AND (g.node_id = v_rc.o_node OR go.node_id IS NULL)
           AND (t.node_id = v_rc.d_node OR td.node_id IS NULL)
         ORDER BY g.base + g.added, t.recv, y.n, g.d, g.vrank, t.node_code, t.node_id
         LIMIT 1;
        IF NOT FOUND THEN
          -- Sin ningun (nodo origen, dia) con hueco: las demas tampoco caben.
          EXIT WHEN NOT EXISTS (SELECT 1 FROM pg_temp.lb2_rload WHERE added = 0);
          CONTINUE;
        END IF;
        INSERT INTO pg_temp.lb2_reint (id, ds_id, plan_id, o_node, d_node, d, o_pid, o_pname, d_pid, d_pname,
                                       ds_o_node, ds_d_node, cell_id)
        SELECT gen_random_uuid(), v_rc.ds_id, v_rc.plan_id, v_r_onode, v_r_dnode, v_r_day, n.panelist_id,
               n.panelist_name, t.panelist_id, t.panelist_name, v_rc.o_node, v_rc.d_node, v_r_cell
          FROM pg_temp.lb2_nodes n, pg_temp.lb2_rdest t
         WHERE n.node_id = v_r_onode AND t.node_id = v_r_dnode;
        UPDATE pg_temp.lb2_rload SET added = added + 1 WHERE node_id = v_r_onode AND d = v_r_day;
        UPDATE pg_temp.lb2_rday SET n = n + 1 WHERE d = v_r_day;
        UPDATE pg_temp.lb2_rdslot SET recv = recv + 1, comp = comp + 1 WHERE node_id = v_r_dnode AND d = v_r_day;
      END LOOP;
      UPDATE pg_temp.lb2_rcand c SET placed = true WHERE c.ds_id IN (SELECT r.ds_id FROM pg_temp.lb2_reint r);

      -- Motivo de espera de las que no se colocaron.
      UPDATE pg_temp.lb2_rcand c
         SET waiting = CASE
               WHEN NOT EXISTS (SELECT 1 FROM pg_temp.lb2_rload g WHERE g.d BETWEEN c.ps AND c.pe)
                 THEN 'no_origin_panelist'
               WHEN NOT EXISTS (SELECT 1 FROM pg_temp.lb2_rload g
                                  JOIN pg_temp.lb2_rdslot t ON t.city_id = c.dest_city AND t.d = g.d
                                                           AND t.node_id <> g.node_id
                                 WHERE g.d BETWEEN c.ps AND c.pe)
                 THEN 'no_dest_panelist'
               ELSE 'no_capacity' END
       WHERE NOT c.placed AND c.waiting IS NULL;
    END IF;
  END IF;   -- v_rc_any

  -- ===== 6P. FASE POBOX (spec seccion 6). Con POBOX efectiva la politica es 'daily': una celda (nodo, dia)
  -- existe si y solo si el nodo es valido y esta disponible ese dia laborable >= v_from.
  CREATE TEMP TABLE pg_temp.lb2_new (
    id uuid PRIMARY KEY, plan_id uuid, origin_node uuid, origin_cell integer, dest_node uuid, d date
  ) ON COMMIT DROP;

  IF v_pobox THEN
    -- Estado tras la equidad: un registro por envio no cancelado con origen en la ciudad. Los pendientes del
    -- periodo (lb2_ship) son movibles y llevan el rango de su plan; el resto es fijo. Ventana: desde el lunes
    -- de la semana de v_from hasta fin + 6 (para contar la carga de semanas completas).
    CREATE TEMP TABLE pg_temp.lb2_pb (
      id uuid PRIMARY KEY, node_id uuid, d date, movable boolean, plan_start date, plan_end date,
      dest_node uuid, dest_bad boolean NOT NULL DEFAULT false,
      reint boolean NOT NULL DEFAULT false,  -- muestra reintroducida en esta ejecucion (fase R)
      comp boolean NOT NULL DEFAULT false    -- fila 'compensation' (ya existente o de esta ejecucion)
    ) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_pb (id, node_id, d, movable, plan_start, plan_end, dest_node, dest_bad, comp)
    SELECT s.id, COALESCE(c.node_id, s.cur_node), COALESCE(c.cell_date, s.fecha), NOT s.frozen, p.start_date, p.end_date,
           s.dest_node, s.dest_bad, s.comp
      FROM pg_temp.lb2_ship s
      LEFT JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell
      JOIN public.allocation_plan_details a ON a.id = s.id
      LEFT JOIN public.allocation_plans p ON p.id = a.plan_id;
    INSERT INTO pg_temp.lb2_pb (id, node_id, d, movable, plan_start, plan_end, dest_node, dest_bad, comp)
    SELECT a.id, a.origin_node_id, a.fecha_programada, false, NULL, NULL, a.destination_node_id, false,
           a.generation_source = 'compensation'
      FROM public.allocation_plan_details a
      JOIN pg_temp.lb2_nodes n ON n.node_id = a.origin_node_id
     WHERE a.account_id = v_account_id
       AND a.status <> 'cancelled'
       AND a.fecha_programada BETWEEN date_trunc('week', v_from)::date AND p_end_date + 6
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_ship s WHERE s.id = a.id)
       -- las que se apartan al registro ya no cubren su dia
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_defer d WHERE d.id = a.id);
    CREATE INDEX ON pg_temp.lb2_pb (d);
    CREATE INDEX ON pg_temp.lb2_pb (node_id, d);

    -- Planes activos de la cuenta que tocan el periodo y su avance (no pendientes / total).
    CREATE TEMP TABLE pg_temp.lb2_plans (
      plan_id uuid PRIMARY KEY, start_date date, end_date date, progress numeric
    ) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_plans
    SELECT p.id, p.start_date, p.end_date,
           COALESCE((SELECT (count(*) FILTER (WHERE x.status <> 'pending'))::numeric / NULLIF(count(*), 0)
                       FROM public.allocation_plan_details x
                      WHERE x.plan_id = p.id AND x.account_id = v_account_id), 0)
      FROM public.allocation_plans p
     WHERE p.account_id = v_account_id AND p.status = 'active'
       AND p.start_date <= p_end_date AND p.end_date >= v_from;

    -- Ciudades que ya son destino de esta ciudad en cada plan (rutas existentes).
    CREATE TEMP TABLE pg_temp.lb2_routes (plan_id uuid, city_id uuid, PRIMARY KEY (plan_id, city_id)) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_routes
    SELECT DISTINCT x.plan_id, dn.city_id
      FROM public.allocation_plan_details x
      JOIN pg_temp.lb2_nodes o ON o.node_id = x.origin_node_id
      JOIN public.nodes dn ON dn.id = x.destination_node_id AND dn.account_id = v_account_id
      JOIN pg_temp.lb2_plans pl ON pl.plan_id = x.plan_id
     WHERE x.account_id = v_account_id AND x.status <> 'cancelled' AND dn.city_id <> p_city_id;

    -- Destinos posibles: nodos activos con panelista activo de OTRA ciudad de la cuenta.
    CREATE TEMP TABLE pg_temp.lb2_dest (
      node_id uuid PRIMARY KEY, city_id uuid, node_code text, panelist_id uuid, panelist_name text
    ) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_dest
    SELECT n.id, n.city_id, n.auto_id, pan.id, pan.name::text
      FROM public.nodes n
      JOIN public.cities c ON c.id = n.city_id AND c.account_id = v_account_id
      JOIN LATERAL (SELECT p.id, p.name FROM public.panelists p
                     WHERE p.node_id = n.id AND p.account_id = v_account_id AND p.status = 'active'
                     ORDER BY p.created_at, p.id LIMIT 1) pan ON true
     WHERE n.account_id = v_account_id AND n.city_id <> p_city_id AND n.status = 'active';
    CREATE TEMP TABLE pg_temp.lb2_dabsent (node_id uuid, d date, PRIMARY KEY (node_id, d)) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_dabsent
    SELECT DISTINCT p.node_id, dd.d
      FROM public.panelist_unavailability u
      JOIN public.panelists p ON p.id = u.panelist_id AND p.account_id = v_account_id AND p.status = 'active'
      JOIN pg_temp.lb2_dest t ON t.node_id = p.node_id
      JOIN pg_temp.lb2_days dd ON dd.d BETWEEN u.start_date AND u.end_date
     WHERE u.account_id = v_account_id AND u.status = 'active';
    -- Recepciones por nodo destino y dia (no canceladas) en la ventana; los envios creados se suman aqui.
    CREATE TEMP TABLE pg_temp.lb2_dload (node_id uuid, d date, n integer) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_dload
    SELECT a.destination_node_id, a.fecha_programada, count(*)::int
      FROM public.allocation_plan_details a
      JOIN pg_temp.lb2_dest t ON t.node_id = a.destination_node_id
     WHERE a.account_id = v_account_id AND a.status <> 'cancelled'
       AND a.fecha_programada BETWEEN date_trunc('week', v_from)::date AND p_end_date + 6
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_defer d WHERE d.id = a.id)
     GROUP BY a.destination_node_id, a.fecha_programada;
    -- Las reintroducidas por la fase R cubren su dia, cargan su nodo origen y su destino (no son movibles).
    INSERT INTO pg_temp.lb2_pb (id, node_id, d, movable, dest_node, reint, comp)
    SELECT r.id, r.o_node, r.d, false, r.d_node, true, true FROM pg_temp.lb2_reint r;
    INSERT INTO pg_temp.lb2_dload SELECT r.d_node, r.d, 1 FROM pg_temp.lb2_reint r;
    CREATE INDEX ON pg_temp.lb2_dload (node_id, d);

    -- Dias sin cubrir tras la equidad (antes de reintroducir), en orden. Mover solo saca de dias con >= 2 y
    -- reintroducir/crear solo cubre el dia tratado, asi que la lista inicial no cambia durante el bucle.
    FOR v_day IN
      SELECT dd.d FROM pg_temp.lb2_days dd
       WHERE NOT EXISTS (SELECT 1 FROM pg_temp.lb2_pb b WHERE b.d = dd.d AND NOT b.reint)
       ORDER BY dd.d
    LOOP
      v_pb_missing := v_pb_missing + 1;
      v_wk := date_trunc('week', v_day)::date;

      -- (0) Ya cubierto por una muestra reintroducida en la fase R (que prefiere los dias vacios de la ciudad):
      -- el dia se cubre compensando la deuda, sin mover ni crear (spec 3.2 bis). Es la unica via por la que POBOX
      -- usa el registro: una anotacion que pudiera servir un dia vacio ya la ha colocado la fase R.
      IF EXISTS (SELECT 1 FROM pg_temp.lb2_pb b WHERE b.d = v_day AND b.reint) THEN
        v_pb_reint := v_pb_reint + 1;
        CONTINUE;
      END IF;

      -- (a) Mover: pendiente del dia mas cercano con >= 2 envios; misma semana primero (atras, luego delante),
      -- despues semanas +-1, +-2...; su nodo debe tener celda ese dia y el dia debe caer en su plan.
      SELECT b.id, cl.cell_id INTO v_mv_id, v_mv_cell
        FROM pg_temp.lb2_pb b
        JOIN (SELECT x.d FROM pg_temp.lb2_pb x WHERE x.d BETWEEN v_from AND p_end_date
               GROUP BY x.d HAVING count(*) >= 2) dc ON dc.d = b.d
        JOIN pg_temp.lb2_cells cl ON cl.node_id = b.node_id AND cl.cell_date = v_day
       WHERE b.movable AND NOT b.dest_bad
         -- una 'compensation' movible no va a un (nodo destino, dia) que ya recibe una (tope R5)
         AND (NOT b.comp
              OR (NOT EXISTS (SELECT 1 FROM pg_temp.lb2_pb x WHERE x.comp AND x.dest_node = b.dest_node AND x.d = v_day)
                  AND NOT EXISTS (SELECT 1 FROM public.allocation_plan_details a
                                   WHERE a.account_id = v_account_id AND a.generation_source = 'compensation'
                                     AND a.status <> 'cancelled' AND a.destination_node_id = b.dest_node
                                     AND a.fecha_programada = v_day
                                     AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_pb y WHERE y.id = a.id))))
         AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = b.dest_node AND x.d = v_day)
         AND v_day BETWEEN COALESCE(b.plan_start, v_day) AND COALESCE(b.plan_end, v_day)
       ORDER BY abs(date_trunc('week', b.d)::date - v_wk), (b.d > v_day), abs(b.d - v_day), b.id
       LIMIT 1;
      IF FOUND THEN
        UPDATE pg_temp.lb2_pb SET d = v_day WHERE id = v_mv_id;
        UPDATE pg_temp.lb2_ship SET new_cell = v_mv_cell, pobox_move = true WHERE id = v_mv_id;
        v_pb_moved := v_pb_moved + 1;
        CONTINUE;
      END IF;

      -- (b) Crear. Plan menos avanzado que cubre el dia (empate: fin mas lejano).
      v_plan := NULL; v_org_node := NULL; v_org_cell := NULL; v_dst_node := NULL;
      SELECT p.plan_id INTO v_plan FROM pg_temp.lb2_plans p
       WHERE v_day BETWEEN p.start_date AND p.end_date
       ORDER BY p.progress, p.end_date DESC, p.plan_id LIMIT 1;
      -- Origen: nodo de la ciudad disponible ese dia con menos envios en la semana (empate: en el periodo).
      SELECT cl.node_id, cl.cell_id INTO v_org_node, v_org_cell
        FROM pg_temp.lb2_cells cl
       WHERE cl.cell_date = v_day
       ORDER BY (SELECT count(*) FROM pg_temp.lb2_pb b WHERE b.node_id = cl.node_id AND b.d BETWEEN v_wk AND v_wk + 6),
                (SELECT count(*) FROM pg_temp.lb2_pb b WHERE b.node_id = cl.node_id AND b.d BETWEEN v_from AND p_end_date),
                cl.valid_rank
       LIMIT 1;
      -- Destino: nodo valido y disponible de otra ciudad; primero ciudades ya emparejadas en el plan, luego menos
      -- recepciones en la semana, luego en el periodo.
      IF v_plan IS NOT NULL THEN
        SELECT t.node_id INTO v_dst_node
          FROM pg_temp.lb2_dest t
         WHERE NOT EXISTS (SELECT 1 FROM pg_temp.lb2_dabsent x WHERE x.node_id = t.node_id AND x.d = v_day)
         ORDER BY EXISTS (SELECT 1 FROM pg_temp.lb2_routes r WHERE r.plan_id = v_plan AND r.city_id = t.city_id) DESC,
                  (SELECT COALESCE(sum(l.n), 0) FROM pg_temp.lb2_dload l
                    WHERE l.node_id = t.node_id AND l.d BETWEEN v_wk AND v_wk + 6),
                  (SELECT COALESCE(sum(l.n), 0) FROM pg_temp.lb2_dload l
                    WHERE l.node_id = t.node_id AND l.d BETWEEN v_from AND p_end_date),
                  t.node_code, t.node_id
         LIMIT 1;
      END IF;

      IF v_plan IS NULL OR v_org_node IS NULL OR v_dst_node IS NULL THEN
        v_pb_uncovered := v_pb_uncovered + 1;
        v_pb_unc_dates := v_pb_unc_dates || v_day::text;
        CONTINUE;
      END IF;

      v_new_id := gen_random_uuid();
      INSERT INTO pg_temp.lb2_new VALUES (v_new_id, v_plan, v_org_node, v_org_cell, v_dst_node, v_day);
      INSERT INTO pg_temp.lb2_pb VALUES (v_new_id, v_org_node, v_day, false, NULL, NULL, v_dst_node, false);
      INSERT INTO pg_temp.lb2_dload VALUES (v_dst_node, v_day, 1);
      v_pb_created := v_pb_created + 1;
    END LOOP;
  END IF;

  UPDATE pg_temp.lb2_cells c SET new_load = x.n
    FROM (SELECT cell, count(*)::int AS n
            FROM (SELECT new_cell AS cell FROM pg_temp.lb2_ship WHERE new_cell IS NOT NULL AND NOT frozen
                  UNION ALL
                  -- carga fija: los congelados cuentan en la celda donde ya estan
                  SELECT cur_cell FROM pg_temp.lb2_ship WHERE frozen AND cur_cell IS NOT NULL
                  UNION ALL
                  SELECT origin_cell FROM pg_temp.lb2_new
                  UNION ALL
                  -- reintroducidas (fase R y POBOX): entran en matrix_after y stddev_after
                  SELECT cell_id FROM pg_temp.lb2_reint WHERE cell_id IS NOT NULL) u
           GROUP BY cell) x
   WHERE x.cell = c.cell_id;
  SELECT count(*) INTO v_reint FROM pg_temp.lb2_reint;

  -- ===== 7. Escritura (solo al aplicar).
  IF p_apply_changes THEN
    -- 7.0 Muestras apartadas: copia completa al registro y borrado del plan, en la misma transaccion y sobre el
    -- mismo conjunto (ids apartados, solo 'pending'). Se bloquean antes las filas; si lo anotado no coincide con
    -- lo calculado o con lo borrado, se aborta TODO el balanceo (nada queda a medias).
    IF v_def_removed > 0 THEN
      PERFORM 1 FROM public.allocation_plan_details a
        JOIN pg_temp.lb2_defer d ON d.id = a.id
       WHERE a.account_id = v_account_id
         FOR UPDATE OF a;
      -- Ya bloqueadas: si alguna dejo de estar pendiente, no tiene nodo destino o gano un dependiente (R2) entre la
      -- lectura y el bloqueo, se aborta nombrando las muestras.
      SELECT string_agg(d.id::text, ', ' ORDER BY d.id) INTO v_def_bad
        FROM pg_temp.lb2_defer d
        LEFT JOIN public.allocation_plan_details a ON a.id = d.id AND a.account_id = v_account_id AND a.status = 'pending'
        LEFT JOIN public.nodes dn ON dn.id = a.destination_node_id
       WHERE dn.id IS NULL;
      IF v_def_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Balanceo abortado: muestras a apartar que ya no estan pendientes o sin nodo destino: %', v_def_bad;
      END IF;
      SELECT string_agg(d.id::text, ', ' ORDER BY d.id) INTO v_def_bad
        FROM pg_temp.lb2_defer d
       WHERE EXISTS (SELECT 1 FROM public.material_hold m WHERE m.allocation_plan_detail_id = d.id)
          OR EXISTS (SELECT 1 FROM public.shipment_incident si WHERE si.parcel_id = d.id)
          OR EXISTS (SELECT 1 FROM public.panelist_incident pi WHERE pi.allocation_plan_detail_id = d.id)
          OR EXISTS (SELECT 1 FROM public.one_db o WHERE o.allocation_detail_id = d.id);
      IF v_def_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Balanceo abortado: muestras a apartar con incidencias, material o lecturas asociadas: %', v_def_bad;
      END IF;
      INSERT INTO public.deferred_samples
        (account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id, fecha_programada,
         reason, row_snapshot, created_by)
      SELECT a.account_id, a.plan_id, p_city_id, dn.city_id, a.origin_node_id, a.destination_node_id,
             a.fecha_programada, d.reason, to_jsonb(a.*), auth.uid()
        FROM pg_temp.lb2_defer d
        JOIN public.allocation_plan_details a ON a.id = d.id
        JOIN public.nodes dn ON dn.id = a.destination_node_id
       WHERE a.account_id = v_account_id AND a.status = 'pending';
      GET DIAGNOSTICS v_def_ins = ROW_COUNT;
      -- OJO: el trigger AFTER DELETE recompute_incidents_on_plan_delete recalcula las bajas activas que tocan
      -- estas filas; borrar la ultima muestra afectada de una baja puede pasar su incidencia a 'auto_resolved'
      -- (los tests desactivan los triggers de incidencias y no lo cubren).
      DELETE FROM public.allocation_plan_details a
       USING pg_temp.lb2_defer d
       WHERE a.id = d.id AND a.account_id = v_account_id AND a.status = 'pending';
      GET DIAGNOSTICS v_def_del = ROW_COUNT;
      IF v_def_ins <> v_def_removed OR v_def_del <> v_def_ins THEN
        RAISE EXCEPTION 'Balanceo abortado: muestras a apartar %, anotadas %, borradas % (reintentar)',
          v_def_removed, v_def_ins, v_def_del;
      END IF;
    END IF;

    -- El panelista origen solo se refresca si cambia el nodo (un cambio solo de fecha lo conserva).
    UPDATE public.allocation_plan_details a
       SET origin_node_id = c.node_id,
           origin_panelist_name = CASE WHEN a.origin_node_id <> c.node_id THEN n.panelist_name
                                       ELSE a.origin_panelist_name END,
           origin_panelist_id = CASE WHEN a.origin_node_id = c.node_id THEN a.origin_panelist_id
                                     WHEN a.origin_panelist_id IS NOT NULL THEN n.panelist_id END,
           fecha_programada = c.cell_date,
           week_number = EXTRACT(week FROM c.cell_date)::int,
           month = EXTRACT(month FROM c.cell_date)::int,
           year = EXTRACT(year FROM c.cell_date)::int,
           original_fecha_programada = COALESCE(a.original_fecha_programada, a.fecha_programada),
           original_origin_node_id = COALESCE(a.original_origin_node_id, a.origin_node_id),
           reassignment_reason = CASE WHEN s.pobox_move THEN 'pobox_move' ELSE 'rebalancing' END,
           reassigned_at = now(),
           reassigned_by = auth.uid(),
           updated_at = now()
      FROM pg_temp.lb2_ship s
      JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell
      JOIN pg_temp.lb2_nodes n ON n.node_id = c.node_id
     WHERE a.id = s.id
       AND a.status = 'pending'
       AND (a.origin_node_id <> c.node_id OR a.fecha_programada <> c.cell_date);
    GET DIAGNOSTICS v_movements_count = ROW_COUNT;

    -- 7.1 Destinos reasignados en la fase 0 (dentro de la ciudad destino). La primera vez se guarda el original.
    IF v_def_reassigned > 0 THEN
      UPDATE public.allocation_plan_details a
         SET destination_node_id = s.dest_node,
             original_destination_node_id = COALESCE(a.original_destination_node_id, a.destination_node_id),
             destination_panelist_id = s.new_dest_pid,
             destination_panelist_name = s.new_dest_pname,
             reassignment_reason = CASE WHEN s.pobox_move THEN 'pobox_move' ELSE 'rebalancing' END,
             reassigned_at = now(),
             reassigned_by = auth.uid(),
             updated_at = now()
        FROM pg_temp.lb2_ship s
       WHERE a.id = s.id AND s.new_dest
         AND a.status = 'pending'
         AND a.destination_node_id <> s.dest_node;
    END IF;

    -- Envios creados por POBOX: muestras normales del plan; la unica traza es generation_source = 'pobox'.
    IF v_pb_created > 0 THEN
      INSERT INTO public.allocation_plan_details
        (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year,
         status, origin_panelist_id, origin_panelist_name, destination_panelist_id, destination_panelist_name,
         generation_source)
      SELECT w.id, v_account_id, w.plan_id, w.origin_node, w.dest_node, w.d,
             EXTRACT(week FROM w.d)::int, EXTRACT(month FROM w.d)::int, EXTRACT(year FROM w.d)::int,
             'pending', o.panelist_id, o.panelist_name, t.panelist_id, t.panelist_name, 'pobox'
        FROM pg_temp.lb2_new w
        JOIN pg_temp.lb2_nodes o ON o.node_id = w.origin_node
        JOIN pg_temp.lb2_dest t ON t.node_id = w.dest_node;
    END IF;

    -- 7.2 Reintroducidas: fila nueva 'compensation' en el plan original y la anotacion pasa a 'reintroduced'
    -- enlazada a ella, en la misma transaccion y con recuento exacto (si no cuadra, se aborta TODO el balanceo).
    -- Los nodos originales de la anotacion se guardan en original_* solo si cambian.
    IF v_reint > 0 THEN
      INSERT INTO public.allocation_plan_details
        (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year,
         status, origin_panelist_id, origin_panelist_name, destination_panelist_id, destination_panelist_name,
         original_origin_node_id, original_destination_node_id, generation_source)
      SELECT r.id, v_account_id, r.plan_id, r.o_node, r.d_node, r.d,
             EXTRACT(week FROM r.d)::int, EXTRACT(month FROM r.d)::int, EXTRACT(year FROM r.d)::int,
             'pending', r.o_pid, r.o_pname, r.d_pid, r.d_pname,
             CASE WHEN r.o_node <> r.ds_o_node
                   AND EXISTS (SELECT 1 FROM public.nodes x WHERE x.id = r.ds_o_node) THEN r.ds_o_node END,
             CASE WHEN r.d_node <> r.ds_d_node
                   AND EXISTS (SELECT 1 FROM public.nodes x WHERE x.id = r.ds_d_node) THEN r.ds_d_node END,
             'compensation'
        FROM pg_temp.lb2_reint r;
      GET DIAGNOSTICS v_reint_ins = ROW_COUNT;
      UPDATE public.deferred_samples d
         SET status = 'reintroduced', reintroduced_at = now(), reintroduced_detail_id = r.id, waiting_reason = NULL
        FROM pg_temp.lb2_reint r
       WHERE d.id = r.ds_id AND d.account_id = v_account_id AND d.status = 'pending';
      GET DIAGNOSTICS v_reint_upd = ROW_COUNT;
      IF v_reint_ins <> v_reint OR v_reint_upd <> v_reint THEN
        RAISE EXCEPTION 'Balanceo abortado: muestras a reintroducir %, insertadas %, anotaciones actualizadas % (reintentar)',
          v_reint, v_reint_ins, v_reint_upd;
      END IF;
    END IF;
    -- Motivo de espera de las anotaciones que no se reintroducen (solo al aplicar).
    IF v_rc_any THEN
      UPDATE public.deferred_samples d
         SET waiting_reason = c.waiting
        FROM pg_temp.lb2_rcand c
       WHERE d.id = c.ds_id AND NOT c.placed AND d.account_id = v_account_id AND d.status = 'pending'
         AND d.waiting_reason IS DISTINCT FROM c.waiting;
    END IF;

    -- Solo si hubo sobrante Y se movio algo: re-aplicar sobre una ciudad ya equilibrada no rota.
    IF v_had_remainder AND v_movements_count > 0 THEN
      UPDATE public.cities SET balance_rotation_offset = balance_rotation_offset + 1 WHERE id = p_city_id;
    END IF;
  ELSE
    SELECT count(*) INTO v_movements_count
      FROM pg_temp.lb2_ship s JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell
     WHERE s.cur_node <> c.node_id OR s.fecha <> c.cell_date;
  END IF;

  -- ===== 8. Resultado.
  SELECT COALESCE(stddev(current_load), 0), COALESCE(stddev(new_load), 0)
    INTO v_stddev_before, v_stddev_after FROM pg_temp.lb2_cells;
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
              FROM pg_temp.lb2_cells GROUP BY node_code, week_start) x;
  ELSE
    SELECT jsonb_agg(jsonb_build_object('node_code', node_code, 'week_num', EXTRACT(week FROM week_start)::int,
                                        'week_start', week_start, 'day', cell_date, 'load_count', current_load)
                     ORDER BY node_code, cell_date),
           jsonb_agg(jsonb_build_object('node_code', node_code, 'week_num', EXTRACT(week FROM week_start)::int,
                                        'week_start', week_start, 'day', cell_date, 'load_count', new_load)
                     ORDER BY node_code, cell_date)
      INTO v_matrix_before, v_matrix_after
      FROM pg_temp.lb2_cells;
  END IF;

  SELECT jsonb_agg(m ORDER BY m->>'from_date', m->>'to_date', m->>'from_node_code', m->>'to_node_code')
    INTO v_movements
    FROM (SELECT jsonb_build_object('from_node_code', s.cur_code, 'from_date', s.fecha,
                                    'to_node_code', c.node_code, 'to_date', c.cell_date, 'count', count(*)) AS m
            FROM pg_temp.lb2_ship s JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell
           WHERE s.cur_node <> c.node_id OR s.fecha <> c.cell_date
           GROUP BY s.cur_code, s.fecha, c.node_code, c.cell_date
           ORDER BY s.fecha, c.cell_date, s.cur_code, c.node_code
           LIMIT 100) sub;

  SELECT jsonb_agg(w) INTO v_warnings
    FROM (SELECT jsonb_build_object('code', 'no_valid_cell', 'count', count(*),
                                    'detail', string_agg(DISTINCT cur_code, ', ' ORDER BY cur_code)) AS w
            FROM pg_temp.lb2_ship WHERE new_cell IS NULL AND NOT od_conflict AND NOT comp_frozen HAVING count(*) > 0
          UNION ALL
          SELECT jsonb_build_object('code', 'origin_equals_destination', 'count', count(*),
                                    'detail', string_agg(DISTINCT cur_code, ', ' ORDER BY cur_code))
            FROM pg_temp.lb2_ship WHERE od_conflict HAVING count(*) > 0
          UNION ALL
          SELECT jsonb_build_object('code', 'pobox_uncovered', 'count', v_pb_uncovered,
                                    'detail', array_to_string(v_pb_unc_dates, ', '))
           WHERE v_pb_uncovered > 0
          UNION ALL
          SELECT jsonb_build_object('code', 'deferred_removed', 'count', v_def_removed,
                                    'detail', concat_ws(', ',
                                      CASE WHEN v_def_origin > 0 THEN 'origin_no_panelist=' || v_def_origin END,
                                      CASE WHEN v_def_dest > 0 THEN 'dest_no_panelist=' || v_def_dest END,
                                      CASE WHEN v_def_day > 0 THEN 'no_valid_day=' || v_def_day END))
           WHERE v_def_removed > 0
          UNION ALL
          SELECT jsonb_build_object('code', 'deferred_blocked', 'count', count(*),
                                    'detail', string_agg(DISTINCT cur_code, ', ' ORDER BY cur_code))
            FROM pg_temp.lb2_ship WHERE def_blocked HAVING count(*) > 0) x;

  IF v_rc_any THEN
    SELECT jsonb_build_object('no_origin_panelist', count(*) FILTER (WHERE waiting = 'no_origin_panelist'),
                              'no_dest_panelist', count(*) FILTER (WHERE waiting = 'no_dest_panelist'),
                              'no_capacity', count(*) FILTER (WHERE waiting = 'no_capacity'),
                              'plan_inactive', count(*) FILTER (WHERE waiting = 'plan_inactive'),
                              'outside_period', count(*) FILTER (WHERE waiting = 'outside_period'))
      INTO v_wait_by
      FROM pg_temp.lb2_rcand WHERE NOT placed;
  ELSE
    v_wait_by := jsonb_build_object('no_origin_panelist', 0, 'no_dest_panelist', 0, 'no_capacity', 0,
                                    'plan_inactive', 0, 'outside_period', 0);
  END IF;

  DROP TABLE IF EXISTS pg_temp.lb2_nodes, pg_temp.lb2_days, pg_temp.lb2_absent, pg_temp.lb2_cells, pg_temp.lb2_segs, pg_temp.lb2_ship,
                       pg_temp.lb2_new, pg_temp.lb2_pb, pg_temp.lb2_plans, pg_temp.lb2_routes, pg_temp.lb2_dest,
                       pg_temp.lb2_dabsent, pg_temp.lb2_dload, pg_temp.lb2_sdabs,
                       pg_temp.lb2_alt, pg_temp.lb2_altload, pg_temp.lb2_altabs, pg_temp.lb2_defer, pg_temp.lb2_hz,
                       pg_temp.lb2_reint, pg_temp.lb2_rcand, pg_temp.lb2_rload, pg_temp.lb2_rday,
                       pg_temp.lb2_rdest, pg_temp.lb2_rdslot;

  RETURN jsonb_build_object('success', true,
    'movements_count', v_movements_count,
    'stddev_before', v_stddev_before, 'stddev_after', v_stddev_after,
    'improvement_percentage', v_improvement,
    'movements', COALESCE(v_movements, '[]'::jsonb),
    'matrix_before', COALESCE(v_matrix_before, '[]'::jsonb),
    'matrix_after', COALESCE(v_matrix_after, '[]'::jsonb),
    'warnings', COALESCE(v_warnings, '[]'::jsonb),
    'policy', jsonb_build_object('date_policy', v_date_policy, 'pobox_enabled', v_pobox),
    -- days_missing = dias sin envios tras la equidad; se cubren moviendo (days_moved), reintroduciendo anotadas
    -- (days_reintroduced: cubiertos por la fase R), creando (days_created) o quedan sin cubrir.
    'pobox', jsonb_build_object('days_missing', v_pb_missing, 'days_moved', v_pb_moved,
                                'days_created', v_pb_created, 'days_uncovered', v_pb_uncovered,
                                'days_reintroduced', v_pb_reint),
    -- reintroduced = anotaciones reintroducidas en esta ejecucion (fase R); waiting = anotaciones pendientes
    -- de la ciudad origen tras esta ejecucion (en la vista previa, incluidas las que se apartarian);
    -- waiting_by_reason = motivo de las anotaciones previas que siguen esperando.
    'deferred', jsonb_build_object('removed', v_def_removed, 'reassigned_dest', v_def_reassigned,
                                   'reintroduced', v_reint, 'waiting', v_def_waiting - v_reint, 'blocked', v_def_blocked,
                                   'by_reason', jsonb_build_object('origin_no_panelist', v_def_origin,
                                                                   'dest_no_panelist', v_def_dest,
                                                                   'no_valid_day', v_def_day),
                                   'waiting_by_reason', v_wait_by),
    'message', CASE WHEN v_total = 0 AND v_pb_created = 0 AND v_reint = 0 THEN 'No shipments found in the specified period'
                    ELSE format('Balanced %s shipments across nodes', v_movements_count) END,
    'error', NULL);
END;
$function$;
REVOKE ALL ON FUNCTION public.rpc_balance_city_v2(uuid, date, date, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_balance_city_v2(uuid, date, date, boolean) TO authenticated, service_role;


-- ===== Task 4: el progreso del plan cuenta las muestras por compensar.
-- Se re-crea la vista (definicion VIVA verbatim) + UNION ALL de filas sinteticas de deferred_samples pendientes
-- (status 'deferred', id = id del registro). NO se cambia propietario, security_invoker ni grants de la vista.
CREATE OR REPLACE VIEW public.v_allocation_details_with_availability AS
 SELECT apd.id,
    apd.account_id,
    apd.plan_id,
    apd.origin_node_id,
    apd.destination_node_id,
    apd.fecha_programada,
    apd.week_number,
    apd.month,
    apd.year,
    apd.status,
    COALESCE(( SELECT panelists.name
           FROM panelists
          WHERE panelists.id = apd.origin_panelist_id), op.name) AS origin_panelist_name,
    COALESCE(( SELECT panelists.name
           FROM panelists
          WHERE panelists.id = apd.destination_panelist_id), dp.name) AS destination_panelist_name,
    apd.sent_date,
    apd.delivery_date,
    apd.created_at,
    apd.updated_at,
    apd.idtag,
    apd.tag_id,
    apd.origin_panelist_id,
    apd.destination_panelist_id,
    apd.assigned_at,
    apd.sent_at,
    apd.delivered_at,
    apd.original_origin_node_id,
    apd.original_destination_node_id,
    apd.reassignment_reason,
    apd.reassigned_at,
    apd.reassigned_by,
    on_node.city_id AS origin_city_id,
    on_city.name AS origin_city_name,
    op.status AS origin_panelist_status,
        CASE
            WHEN op.id IS NULL THEN 'unassigned'::text
            WHEN (EXISTS ( SELECT 1
               FROM panelist_unavailability pu
              WHERE pu.panelist_id = op.id AND pu.status::text = 'active'::text AND apd.fecha_programada >= pu.start_date AND apd.fecha_programada <= pu.end_date)) THEN 'unavailable'::text
            WHEN op.status::text = 'active'::text THEN 'available'::text
            ELSE 'inactive'::text
        END AS origin_availability_status,
    ( SELECT pu.reason
           FROM panelist_unavailability pu
          WHERE pu.panelist_id = op.id AND pu.status::text = 'active'::text AND apd.fecha_programada >= pu.start_date AND apd.fecha_programada <= pu.end_date
         LIMIT 1) AS origin_unavailability_reason,
    dn_node.city_id AS destination_city_id,
    dn_city.name AS destination_city_name,
    dp.status AS destination_panelist_status,
        CASE
            WHEN dp.id IS NULL THEN 'unassigned'::text
            WHEN (EXISTS ( SELECT 1
               FROM panelist_unavailability pu
              WHERE pu.panelist_id = dp.id AND pu.status::text = 'active'::text AND apd.fecha_programada >= pu.start_date AND apd.fecha_programada <= pu.end_date)) THEN 'unavailable'::text
            WHEN dp.status::text = 'active'::text THEN 'available'::text
            ELSE 'inactive'::text
        END AS destination_availability_status,
    ( SELECT pu.reason
           FROM panelist_unavailability pu
          WHERE pu.panelist_id = dp.id AND pu.status::text = 'active'::text AND apd.fecha_programada >= pu.start_date AND apd.fecha_programada <= pu.end_date
         LIMIT 1) AS destination_unavailability_reason
   FROM allocation_plan_details apd
     LEFT JOIN nodes on_node ON apd.origin_node_id = on_node.id
     LEFT JOIN cities on_city ON on_node.city_id = on_city.id
     LEFT JOIN panelists op ON on_node.id = op.node_id AND (op.status::text = ANY (ARRAY['active'::character varying, 'unavailable_temp'::character varying]::text[]))
     LEFT JOIN nodes dn_node ON apd.destination_node_id = dn_node.id
     LEFT JOIN cities dn_city ON dn_node.city_id = dn_city.id
     LEFT JOIN panelists dp ON dn_node.id = dp.node_id AND (dp.status::text = ANY (ARRAY['active'::character varying, 'unavailable_temp'::character varying]::text[]))
UNION ALL
 SELECT ds.id,
    ds.account_id,
    ds.plan_id,
    ds.origin_node_id,
    ds.destination_node_id,
    ds.fecha_programada,
    EXTRACT(week FROM ds.fecha_programada)::integer,
    EXTRACT(month FROM ds.fecha_programada)::integer,
    EXTRACT(year FROM ds.fecha_programada)::integer,
    'deferred'::text,
    op.name,
    dp.name,
    NULL::timestamp with time zone,
    NULL::timestamp with time zone,
    NULL::timestamp with time zone,
    NULL::timestamp with time zone,
    NULL::text,
    NULL::character varying(100),
    NULL::uuid,
    NULL::uuid,
    NULL::timestamp with time zone,
    NULL::timestamp with time zone,
    NULL::timestamp with time zone,
    NULL::uuid,
    NULL::uuid,
    NULL::text,
    NULL::timestamp with time zone,
    NULL::uuid,
    on_node.city_id,
    on_city.name,
    op.status,
            CASE
            WHEN op.id IS NULL THEN 'unassigned'::text
            WHEN (EXISTS ( SELECT 1 FROM panelist_unavailability pu WHERE pu.panelist_id = op.id AND pu.status::text = 'active'::text AND ds.fecha_programada >= pu.start_date AND ds.fecha_programada <= pu.end_date)) THEN 'unavailable'::text
            WHEN op.status::text = 'active'::text THEN 'available'::text
            ELSE 'inactive'::text
        END,
    ( SELECT pu.reason FROM panelist_unavailability pu WHERE pu.panelist_id = op.id AND pu.status::text = 'active'::text AND ds.fecha_programada >= pu.start_date AND ds.fecha_programada <= pu.end_date LIMIT 1),
    dn_node.city_id,
    dn_city.name,
    dp.status,
            CASE
            WHEN dp.id IS NULL THEN 'unassigned'::text
            WHEN (EXISTS ( SELECT 1 FROM panelist_unavailability pu WHERE pu.panelist_id = dp.id AND pu.status::text = 'active'::text AND ds.fecha_programada >= pu.start_date AND ds.fecha_programada <= pu.end_date)) THEN 'unavailable'::text
            WHEN dp.status::text = 'active'::text THEN 'available'::text
            ELSE 'inactive'::text
        END,
    ( SELECT pu.reason FROM panelist_unavailability pu WHERE pu.panelist_id = dp.id AND pu.status::text = 'active'::text AND ds.fecha_programada >= pu.start_date AND ds.fecha_programada <= pu.end_date LIMIT 1)
   FROM deferred_samples ds
     LEFT JOIN nodes on_node ON ds.origin_node_id = on_node.id
     LEFT JOIN cities on_city ON on_node.city_id = on_city.id
     LEFT JOIN panelists op ON on_node.id = op.node_id AND (op.status::text = ANY (ARRAY['active'::character varying, 'unavailable_temp'::character varying]::text[]))
     LEFT JOIN nodes dn_node ON ds.destination_node_id = dn_node.id
     LEFT JOIN cities dn_city ON dn_node.city_id = dn_city.id
     LEFT JOIN panelists dp ON dn_node.id = dp.node_id AND (dp.status::text = ANY (ARRAY['active'::character varying, 'unavailable_temp'::character varying]::text[]))
  WHERE ds.status = 'pending';
