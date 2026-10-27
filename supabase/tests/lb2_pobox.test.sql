-- Load Balancing v2, tarea 4: POBOX en rpc_balance_city_v2 y rpc_balance_cities_pending.
-- Fixture comun: C1 (N1, N2, N3) y C2 (N4); planes Mar27 (2027-03-01..31) y Apr27 (2027-04-01..30), ambos
-- 'active' por defecto. POBOX se activa en account_config de la cuenta 1 (el fixture no trae fila).
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
CREATE FUNCTION pg_temp.mk(p_o text, p_date date, p_status text DEFAULT 'pending',
                           p_plan uuid DEFAULT 'cc000000-0000-0000-0000-000000000001') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', p_plan, o.id, d.id, p_date, p_status
    FROM public.nodes o, public.nodes d
   WHERE o.auto_id = p_o AND d.auto_id = CASE WHEN p_o = 'N4' THEN 'N1' ELSE 'N4' END
  RETURNING id;
$$;
CREATE FUNCTION pg_temp.pobox_on() RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.account_config (account_id, pobox_enabled)
  VALUES ('a0000000-0000-0000-0000-000000000001', true)
  ON CONFLICT (account_id) DO UPDATE SET pobox_enabled = true;
$$;
-- Dias laborables (L-V) de [p_from, p_to] sin ningun envio no cancelado con origen en C1.
CREATE FUNCTION pg_temp.c1_uncovered(p_from date, p_to date) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM generate_series(p_from, p_to, interval '1 day') g(d)
   WHERE EXTRACT(isodow FROM g.d) <= 5
     AND NOT EXISTS (SELECT 1 FROM public.allocation_plan_details a JOIN public.nodes n ON n.id = a.origin_node_id
                      WHERE n.city_id = 'c1000000-0000-0000-0000-000000000001'
                        AND a.fecha_programada = g.d::date AND a.status <> 'cancelled');
$$;

-- ===== Caso 1 (mover): 5 pendientes en N1 el lunes 8/3/2027, periodo L-V 8..12/3. El reparto equitativo
-- (3 nodos x 5 dias, 5 envios) deja dos dias con 2 envios y dos dias vacios; POBOX los cubre MOVIENDO
-- (sin crear filas). Nota: el caso literal del brief (2 envios el 8, nada el 9, periodo 8..9) no llega a
-- POBOX porque la fase de equidad ya pone uno en cada dia (ver informe de la tarea 4).
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.pobox_on();
SELECT pg_temp.mk('N1', '2027-03-08') FROM generate_series(1, 5);
DO $$
DECLARE r jsonb; p jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', false);
  p := r->'pobox';
  PERFORM pg_temp.fail_if(r->'policy'->>'pobox_enabled' IS DISTINCT FROM 'true', 'policy pobox: ' || r::text);
  PERFORM pg_temp.fail_if((p->>'days_missing')::int <> 2 OR (p->>'days_moved')::int <> 2
                          OR (p->>'days_created')::int <> 0 OR (p->>'days_uncovered')::int <> 0,
                          'preview pobox mover: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details
                            WHERE fecha_programada <> '2027-03-08' OR reassigned_at IS NOT NULL) <> 0,
                          'la vista previa escribio');
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if(r->'pobox' IS DISTINCT FROM p, 'apply y preview deben dar las mismas cifras: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 5, 'no se deben crear filas al mover: ' || count(*)) FROM public.allocation_plan_details;
SELECT pg_temp.fail_if(pg_temp.c1_uncovered('2027-03-08', '2027-03-12') <> 0, 'quedan dias sin cubrir');
SELECT pg_temp.fail_if(count(*) <> 2, 'deben quedar 2 envios con motivo pobox_move: ' || count(*))
  FROM public.allocation_plan_details WHERE reassignment_reason = 'pobox_move';
SELECT pg_temp.fail_if(count(*) > 0, 'pobox_move sin traza o fuera de 11-12/3')
  FROM public.allocation_plan_details
 WHERE reassignment_reason = 'pobox_move'
   AND (fecha_programada NOT IN ('2027-03-11', '2027-03-12') OR reassigned_at IS NULL
        OR reassigned_by IS DISTINCT FROM '99000000-0000-0000-0000-000000000099'
        OR original_fecha_programada IS DISTINCT FROM '2027-03-08'
        OR week_number <> EXTRACT(week FROM fecha_programada));
SELECT pg_temp.fail_if(count(*) > 0, 'nombre de panelista origen incoherente con el nodo')
  FROM public.allocation_plan_details a JOIN public.panelists p ON p.node_id = a.origin_node_id
 WHERE a.origin_node_id <> a.original_origin_node_id AND a.origin_panelist_name IS DISTINCT FROM p.name;
SELECT pg_temp.fail_if(count(*) > 0, 'pobox_move no debe cambiar los nodos')
  FROM public.allocation_plan_details a
 WHERE a.reassignment_reason = 'pobox_move'
   AND a.destination_node_id <> 'b4000000-0000-0000-0000-000000000004';
ROLLBACK;

-- ===== Caso 2 (crear + pureza de la vista previa): 1 pendiente el 8/3, periodo 8..10/3. No hay dias con 2
-- envios => se crean 2 envios (9 y 10) en el plan Mar27, origen en C1, destino N4 (unico nodo de otra ciudad).
-- Un plan Mar27b que tambien cubre marzo pero ya va al 100 % (un envio 'sent') no debe elegirse.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.pobox_on();
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status)
VALUES ('cc000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','Mar27b',
        'ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',1,'2027-03-01','2027-04-15','active');
SELECT pg_temp.mk('N4', '2027-03-02', 'sent', 'cc000000-0000-0000-0000-000000000003');
SELECT pg_temp.mk('N1', '2027-03-08');
DO $$
DECLARE r jsonb; p jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-10', false);
  p := r->'pobox';
  PERFORM pg_temp.fail_if((p->>'days_missing')::int <> 2 OR (p->>'days_moved')::int <> 0
                          OR (p->>'days_created')::int <> 2 OR (p->>'days_uncovered')::int <> 0,
                          'preview pobox crear: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details) <> 2, 'la vista previa creo filas');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details WHERE reassigned_at IS NOT NULL) <> 0,
                          'la vista previa movio filas');
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-10', true);
  PERFORM pg_temp.fail_if(r->'pobox' IS DISTINCT FROM p, 'apply y preview deben dar las mismas cifras: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 2, 'deben crearse 2 envios pobox: ' || count(*))
  FROM public.allocation_plan_details WHERE generation_source = 'pobox';
SELECT pg_temp.fail_if(count(*) > 0, 'envio pobox mal formado: ' || string_agg(a.id::text, ','))
  FROM public.allocation_plan_details a
 WHERE a.generation_source = 'pobox'
   AND (a.plan_id <> 'cc000000-0000-0000-0000-000000000001'
        OR a.origin_node_id NOT IN (SELECT id FROM public.nodes WHERE city_id = 'c1000000-0000-0000-0000-000000000001')
        OR a.destination_node_id <> 'b4000000-0000-0000-0000-000000000004'
        OR a.status <> 'pending' OR a.account_id <> 'a0000000-0000-0000-0000-000000000001'
        OR a.fecha_programada NOT IN ('2027-03-09', '2027-03-10')
        OR a.week_number <> EXTRACT(week FROM a.fecha_programada) OR a.month <> 3 OR a.year <> 2027
        OR a.origin_panelist_id IS NULL OR a.origin_panelist_name IS NULL
        OR a.destination_panelist_id IS DISTINCT FROM 'e4000000-0000-0000-0000-000000000004'
        OR a.destination_panelist_name IS DISTINCT FROM 'Pan4');
SELECT pg_temp.fail_if(count(DISTINCT fecha_programada) <> 2, 'un envio creado por dia')
  FROM public.allocation_plan_details WHERE generation_source = 'pobox';
-- Origen con menos envios en la semana: N1 ya tiene el del dia 8 => los creados van a N2 y N3.
SELECT pg_temp.fail_if(count(*) > 0, 'origen de un envio creado en N1 (el mas cargado)')
  FROM public.allocation_plan_details WHERE generation_source = 'pobox' AND origin_node_id = 'b1000000-0000-0000-0000-000000000001';
SELECT pg_temp.fail_if(pg_temp.c1_uncovered('2027-03-08', '2027-03-10') <> 0, 'quedan dias sin cubrir');
ROLLBACK;

-- ===== Caso 3 (sin plan activo que cubra el dia): mayo 2027 no tiene plan => 2 dias sin cubrir, aviso.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.pobox_on();
-- Un plan que si cubriria mayo pero esta 'completed' no cuenta.
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status)
VALUES ('cc000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','May27done',
        'ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',1,'2027-05-01','2027-05-31','completed');
DO $$
DECLARE r jsonb; w jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-05-03', '2027-05-04', true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'success: ' || r::text);
  PERFORM pg_temp.fail_if((r->'pobox'->>'days_missing')::int <> 2 OR (r->'pobox'->>'days_uncovered')::int <> 2
                          OR (r->'pobox'->>'days_created')::int <> 0 OR (r->'pobox'->>'days_moved')::int <> 0,
                          'pobox sin plan: ' || r::text);
  SELECT e INTO w FROM jsonb_array_elements(r->'warnings') e WHERE e->>'code' = 'pobox_uncovered';
  PERFORM pg_temp.fail_if(w IS NULL OR (w->>'count')::int <> 2, 'aviso pobox_uncovered: ' || r::text);
  PERFORM pg_temp.fail_if(position('2027-05-03' IN w->>'detail') = 0 OR position('2027-05-04' IN w->>'detail') = 0,
                          'detalle del aviso con las fechas: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) > 0, 'no debe crearse nada sin plan') FROM public.allocation_plan_details;
ROLLBACK;

-- ===== Caso 4 (lista de ciudades con pendientes).
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.mk('N1', '2027-03-08') FROM generate_series(1, 3);
SELECT pg_temp.mk('N2', '2027-03-20');
SELECT pg_temp.mk('N1', '2027-04-02');                 -- fuera del periodo
SELECT pg_temp.mk('N4', '2027-03-10', 'sent');         -- C2: solo no pendientes
SELECT pg_temp.mk('N4', '2027-03-11', 'cancelled');
SELECT pg_temp.fail_if(
  (SELECT array_agg(city_name::text || ':' || pending_count ORDER BY ord)
     FROM public.rpc_balance_cities_pending('a0000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31')
          WITH ORDINALITY x(city_id, city_name, pending_count, ord))
  IS DISTINCT FROM ARRAY['City1:4'], 'lista de ciudades con pendientes');
-- Con POBOX efectivo, una ciudad sin pendientes tambien se lista (puede necesitar envios creados).
SELECT pg_temp.pobox_on();
SELECT pg_temp.fail_if(
  (SELECT array_agg(city_name::text || ':' || pending_count ORDER BY ord)
     FROM public.rpc_balance_cities_pending('a0000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31')
          WITH ORDINALITY x(city_id, city_name, pending_count, ord))
  IS DISTINCT FROM ARRAY['City1:4', 'City2:0'], 'lista con POBOX');
-- Guarda: actor de la cuenta 2 => 42501.
SELECT set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
DO $$
BEGIN
  PERFORM * FROM public.rpc_balance_cities_pending('a0000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31');
  RAISE EXCEPTION 'FAIL actor de otra cuenta no debio listar ciudades';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END $$;
ROLLBACK;

-- ===== Caso 5 (unico nodo disponible ausente el dia sin cubrir): solo N1 es valido (sin panelistas en N2/N3)
-- y P1 esta ausente el 9/3 => el 9 queda sin cubrir; no se mueve ni se crea nada sobre un nodo ausente.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.pobox_on();
DELETE FROM public.panelists WHERE id IN ('e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000003');
INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
VALUES ('e1000000-0000-0000-0000-000000000001', '2027-03-09', '2027-03-09', 'vacation', 'active',
        'a0000000-0000-0000-0000-000000000001');
SELECT pg_temp.mk('N1', '2027-03-08') FROM generate_series(1, 2);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-09', true);
  PERFORM pg_temp.fail_if((r->'pobox'->>'days_missing')::int <> 1 OR (r->'pobox'->>'days_uncovered')::int <> 1
                          OR (r->'pobox'->>'days_moved')::int <> 0 OR (r->'pobox'->>'days_created')::int <> 0,
                          'nodo ausente: ' || r::text);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'warnings') e
                                       WHERE e->>'code' = 'pobox_uncovered' AND e->>'detail' LIKE '%2027-03-09%'),
                          'aviso pobox_uncovered: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 2, 'no debe crearse nada') FROM public.allocation_plan_details;
SELECT pg_temp.fail_if(count(*) > 0, 'envio en el dia de ausencia') FROM public.allocation_plan_details
 WHERE fecha_programada = '2027-03-09';
ROLLBACK;

-- ===== Caso 6 (sin POBOX no se toca nada de lo anterior): mismo setup del caso 2 sin activar POBOX.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.mk('N1', '2027-03-08');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-10', true);
  PERFORM pg_temp.fail_if((r->'pobox'->>'days_missing')::int <> 0 OR (r->'pobox'->>'days_created')::int <> 0,
                          'sin POBOX las cifras van a cero: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 1, 'sin POBOX no se crean envios') FROM public.allocation_plan_details;
ROLLBACK;
