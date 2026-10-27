-- Load Balancing v2, tarea 3: rpc_balance_city_v2 (reparto equitativo por dia, semana y nodo; sin POBOX).
-- Ciudad C1 con nodos N1, N2, N3 (panelistas P1..P3) del fixture comun. Fechas en 2027 para que "hoy" no
-- recorte el periodo, salvo el caso 3 (politica weekly con periodo que empieza en el pasado).
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
CREATE FUNCTION pg_temp.mk(p_o text, p_date date) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
         o.id, d.id, p_date, 'pending'
    FROM public.nodes o, public.nodes d WHERE o.auto_id = p_o AND d.auto_id = 'N4'
  RETURNING id;
$$;
-- Carga por (nodo de C1, dia laborable L-V) del periodo, incluidas las celdas vacias.
CREATE FUNCTION pg_temp.grid(p_from date, p_to date)
RETURNS TABLE(code text, d date, n bigint) LANGUAGE sql AS $$
  SELECT nd.auto_id, g.d::date, count(a.id)
    FROM public.nodes nd
    CROSS JOIN generate_series(p_from, p_to, interval '1 day') g(d)
    LEFT JOIN public.allocation_plan_details a ON a.origin_node_id = nd.id AND a.fecha_programada = g.d::date
   WHERE nd.city_id = 'c1000000-0000-0000-0000-000000000001' AND EXTRACT(isodow FROM g.d) <= 5
   GROUP BY nd.auto_id, g.d;
$$;

-- ===== Caso 1 (daily): 30 pendientes en N1 el 4/3/2027; periodo 4/3..19/3 (12 dias laborables x 3 nodos).
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.mk('N1', '2027-03-04') FROM generate_series(1, 30);
UPDATE public.allocation_plan_details SET origin_panelist_name = 'Original';
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-04', '2027-03-19', false);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'preview success: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int = 0, 'preview deberia anunciar movimientos: ' || r::text);
  PERFORM pg_temp.fail_if(r->'policy'->>'date_policy' IS DISTINCT FROM 'daily', 'policy: ' || r::text);
  PERFORM pg_temp.fail_if((r->'pobox'->>'days_missing')::int IS DISTINCT FROM 0, 'pobox: ' || r::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'matrix_before') <> 36, 'matrix_before 36 celdas: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details
                            WHERE fecha_programada <> '2027-03-04' OR reassigned_at IS NOT NULL) <> 0,
                          'preview movio envios');
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-04', '2027-03-19', true);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int = 0, 'apply no movio nada: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int <>
                          (SELECT count(*) FROM public.allocation_plan_details WHERE reassigned_at IS NOT NULL),
                          'movements_count no cuadra con filas movidas: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'stddev_after')::numeric >= (r->>'stddev_before')::numeric, 'stddev no mejora: ' || r::text);
END $$;
SELECT pg_temp.fail_if(max(n) - min(n) > 1, 'reparto por (nodo, dia) desigual: ' || string_agg(code || ' ' || d || '=' || n, ', '))
  FROM pg_temp.grid('2027-03-04', '2027-03-19');
SELECT pg_temp.fail_if(max(n) - min(n) > 1, 'reparto por nodo desigual')
  FROM (SELECT origin_node_id, count(*) n FROM public.allocation_plan_details GROUP BY origin_node_id) x;
SELECT pg_temp.fail_if(count(*) > 0, 'fuera del periodo, fin de semana o pasado: ' || count(*))
  FROM public.allocation_plan_details
 WHERE fecha_programada NOT BETWEEN '2027-03-04' AND '2027-03-19'
    OR EXTRACT(isodow FROM fecha_programada) > 5 OR fecha_programada < current_date;
SELECT pg_temp.fail_if(count(*) > 0, 'movidos sin traza completa: ' || count(*))
  FROM public.allocation_plan_details
 WHERE (origin_node_id <> 'b1000000-0000-0000-0000-000000000001' OR fecha_programada <> '2027-03-04')
   AND (reassigned_at IS NULL OR reassigned_by IS DISTINCT FROM '99000000-0000-0000-0000-000000000099'
        OR reassignment_reason IS DISTINCT FROM 'rebalancing'
        OR original_fecha_programada IS DISTINCT FROM '2027-03-04'
        OR original_origin_node_id IS DISTINCT FROM 'b1000000-0000-0000-0000-000000000001'
        OR week_number <> EXTRACT(week FROM fecha_programada) OR month <> 3 OR year <> 2027);
-- El panelista origen se refresca solo si cambio el nodo; si solo cambio la fecha se conserva (todos los envios
-- se crearon con origin_panelist_name = 'Original').
SELECT pg_temp.fail_if(count(*) > 0, 'nombre de panelista origen no actualizado al cambiar de nodo')
  FROM public.allocation_plan_details a JOIN public.panelists p ON p.node_id = a.origin_node_id
 WHERE a.origin_node_id <> a.original_origin_node_id AND a.origin_panelist_name IS DISTINCT FROM p.name;
SELECT pg_temp.fail_if(count(*) = 0, 'el caso deberia tener envios movidos solo de fecha')
  FROM public.allocation_plan_details a
 WHERE a.reassigned_at IS NOT NULL AND a.origin_node_id = a.original_origin_node_id;
SELECT pg_temp.fail_if(count(*) > 0, 'cambio solo de fecha no debe tocar el panelista origen')
  FROM public.allocation_plan_details a
 WHERE a.origin_node_id = 'b1000000-0000-0000-0000-000000000001' AND a.origin_panelist_name IS DISTINCT FROM 'Original';
SELECT pg_temp.fail_if(count(*) > 0, 'el destino no debe cambiar')
  FROM public.allocation_plan_details WHERE destination_node_id <> 'b4000000-0000-0000-0000-000000000004';
ROLLBACK;

-- ===== Caso 2 (minimos movimientos): 36 envios ya repartidos 1 por celda => 0 movimientos.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.mk(g.code, g.d) FROM pg_temp.grid('2027-03-04', '2027-03-19') g;
DO $$
DECLARE r jsonb;
BEGIN
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details) <> 36, 'setup 36');
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-04', '2027-03-19', true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true OR (r->>'movements_count')::int <> 0,
                          'ya equilibrado no debe mover: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details WHERE reassigned_at IS NOT NULL) <> 0,
                          'filas tocadas');
END $$;
ROLLBACK;

-- ===== Caso 3 (weekly + periodo que empieza en el pasado).
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
UPDATE public.cities SET date_policy = 'weekly' WHERE id = 'c1000000-0000-0000-0000-000000000001';
SELECT pg_temp.mk('N1', current_date + 2 + (i * 14) / 8) FROM generate_series(0, 8) i;
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', current_date - 3, current_date + 18, true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'weekly success: ' || r::text);
  PERFORM pg_temp.fail_if(r->'policy'->>'date_policy' IS DISTINCT FROM 'weekly', 'policy weekly: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM jsonb_array_elements(r->'matrix_after') e WHERE e->>'day' IS NOT NULL),
                          'weekly: day debe ser null en la matriz: ' || r::text);
END $$;
-- Fechas validas: primer dia laborable >= hoy de cada semana ISO del periodo. Si una semana cruza de mes, el
-- balanceador no mueve envios entre meses (spec 5.5): cada tramo semana-mes tiene su propio primer dia.
SELECT pg_temp.fail_if(count(*) > 0, 'weekly: fechas fuera del primer dia laborable de la semana: '
                                     || string_agg(fecha_programada::text, ','))
  FROM public.allocation_plan_details
 WHERE fecha_programada NOT IN (
         SELECT min(g.d::date) FROM generate_series(current_date, current_date + 18, interval '1 day') g(d)
          WHERE EXTRACT(isodow FROM g.d) <= 5
          GROUP BY date_trunc('week', g.d), date_trunc('month', g.d));
SELECT pg_temp.fail_if(count(*) > 0, 'weekly: fechas en el pasado') FROM public.allocation_plan_details
 WHERE fecha_programada < current_date;
SELECT pg_temp.fail_if(count(*) <> 9, 'weekly: se perdieron envios') FROM public.allocation_plan_details;
ROLLBACK;

-- ===== Caso 4 (ausencias y nodo sin panelista).
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
VALUES ('e2000000-0000-0000-0000-000000000002', '2027-03-08', '2027-03-12', 'vacation', 'active',
        'a0000000-0000-0000-0000-000000000001');
DELETE FROM public.panelists WHERE id = 'e3000000-0000-0000-0000-000000000003';
SELECT pg_temp.mk('N1', '2027-03-08') FROM generate_series(1, 20);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'ausencias success: ' || r::text);
  PERFORM pg_temp.fail_if(r->'stddev_before' IS NULL OR r->'stddev_after' IS NULL, 'stddev no informada: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'stddev_after')::numeric >= (r->>'stddev_before')::numeric, 'stddev no mejora: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) > 0, 'envios en N3 (sin panelista)') FROM public.allocation_plan_details
 WHERE origin_node_id = 'b3000000-0000-0000-0000-000000000003';
SELECT pg_temp.fail_if(count(*) > 0, 'envios en N2 (ausente)') FROM public.allocation_plan_details
 WHERE origin_node_id = 'b2000000-0000-0000-0000-000000000002';
SELECT pg_temp.fail_if(count(*) <> 20, 'no estan todos en N1') FROM public.allocation_plan_details
 WHERE origin_node_id = 'b1000000-0000-0000-0000-000000000001';
SELECT pg_temp.fail_if(max(n) <> 4 OR min(n) <> 4, 'N1 deberia tener 4 por dia')
  FROM pg_temp.grid('2027-03-08', '2027-03-12') WHERE code = 'N1';
ROLLBACK;

-- Caso 4b: P1 tambien ausente esa semana => no hay ninguna celda valida: no se mueve nada y se avisa.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
VALUES ('e2000000-0000-0000-0000-000000000002', '2027-03-08', '2027-03-12', 'vacation', 'active', 'a0000000-0000-0000-0000-000000000001'),
       ('e1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', 'vacation', 'active', 'a0000000-0000-0000-0000-000000000001');
DELETE FROM public.panelists WHERE id = 'e3000000-0000-0000-0000-000000000003';
SELECT pg_temp.mk('N1', '2027-03-08') FROM generate_series(1, 20);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'sin celdas success: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int <> 0, 'sin celdas no debe mover: ' || r::text);
  PERFORM pg_temp.fail_if(r->'warnings'->0->>'code' IS DISTINCT FROM 'no_valid_cell', 'aviso code: ' || r::text);
  PERFORM pg_temp.fail_if((r->'warnings'->0->>'count')::int IS DISTINCT FROM 20, 'aviso count: ' || r::text);
  PERFORM pg_temp.fail_if(position('N1' IN r->'warnings'->0->>'detail') = 0, 'aviso detail: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 20, 'se movio algo') FROM public.allocation_plan_details
 WHERE origin_node_id = 'b1000000-0000-0000-0000-000000000001' AND fecha_programada = '2027-03-08' AND reassigned_at IS NULL;
ROLLBACK;

-- ===== Caso 5 (sobrante rotativo): 7 envios, 3 nodos, 1 dia laborable.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
CREATE TEMP TABLE plus_one(run int, code text);
SELECT pg_temp.mk('N1', '2027-03-08') FROM generate_series(1, 7);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-08', false);
  PERFORM pg_temp.fail_if((SELECT balance_rotation_offset FROM public.cities WHERE id = 'c1000000-0000-0000-0000-000000000001') <> 0,
                          'la vista previa no debe avanzar la rotacion');
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-08', true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'rot 1: ' || r::text);
END $$;
INSERT INTO plus_one SELECT 1, n.auto_id FROM public.allocation_plan_details a JOIN public.nodes n ON n.id = a.origin_node_id
 GROUP BY n.auto_id HAVING count(*) = 3;
SELECT pg_temp.fail_if((SELECT count(*) FROM plus_one WHERE run = 1) <> 1, 'run 1: un nodo con 3');
SELECT pg_temp.fail_if((SELECT balance_rotation_offset FROM public.cities WHERE id = 'c1000000-0000-0000-0000-000000000001') <> 1,
                       'offset tras 1 apply');
DELETE FROM public.allocation_plan_details;
SELECT pg_temp.mk('N1', '2027-03-08') FROM generate_series(1, 7);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-08', false);
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-08', true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'rot 2: ' || r::text);
END $$;
INSERT INTO plus_one SELECT 2, n.auto_id FROM public.allocation_plan_details a JOIN public.nodes n ON n.id = a.origin_node_id
 GROUP BY n.auto_id HAVING count(*) = 3;
SELECT pg_temp.fail_if((SELECT count(*) FROM plus_one WHERE run = 2) <> 1, 'run 2: un nodo con 3');
SELECT pg_temp.fail_if((SELECT code FROM plus_one WHERE run = 1) = (SELECT code FROM plus_one WHERE run = 2),
                       'el +1 fue al mismo nodo en las dos ejecuciones');
SELECT pg_temp.fail_if((SELECT balance_rotation_offset FROM public.cities WHERE id = 'c1000000-0000-0000-0000-000000000001') <> 2,
                       'offset tras 2 apply');
-- Sin sobrante (6 envios / 3 celdas) el offset no avanza.
DELETE FROM public.allocation_plan_details;
SELECT pg_temp.mk('N1', '2027-03-08') FROM generate_series(1, 6);
SELECT public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-08', true);
SELECT pg_temp.fail_if((SELECT balance_rotation_offset FROM public.cities WHERE id = 'c1000000-0000-0000-0000-000000000001') <> 2,
                       'sin sobrante el offset no debe avanzar');
ROLLBACK;

-- ===== Caso 6 (meses): 10 en marzo y 2 en abril; el balanceo conserva el total de cada mes.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.mk('N1', '2027-03-10') FROM generate_series(1, 10);
SELECT pg_temp.mk('N1', '2027-04-14') FROM generate_series(1, 2);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-04-30', true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true OR (r->>'movements_count')::int = 0,
                          'meses: ' || r::text);
END $$;
SELECT pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details WHERE fecha_programada BETWEEN '2027-03-01' AND '2027-03-31') <> 10,
                       'marzo debe seguir con 10');
SELECT pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details WHERE fecha_programada BETWEEN '2027-04-01' AND '2027-04-30') <> 2,
                       'abril debe seguir con 2');
ROLLBACK;

-- ===== Caso 7 (atrasados): pendientes con fecha anterior a hoy dentro del periodo solo se mueven hacia delante.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.mk('N1', current_date - 5) FROM generate_series(1, 4);
SELECT pg_temp.mk('N2', current_date - 1) FROM generate_series(1, 2);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', current_date - 5, current_date + 10, true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true OR (r->>'movements_count')::int <> 6,
                          'atrasados: los 6 deben moverse: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) > 0, 'atrasados: quedan fechas en el pasado: ' || string_agg(fecha_programada::text, ','))
  FROM public.allocation_plan_details WHERE fecha_programada < current_date;
SELECT pg_temp.fail_if(count(*) <> 6, 'atrasados: se perdieron envios') FROM public.allocation_plan_details
 WHERE fecha_programada BETWEEN current_date AND current_date + 10;
ROLLBACK;

-- ===== Caso 8 (ausencia del DESTINO): P4 (N4, ciudad C2, destino de todos los envios) ausente el 10/3/2027.
-- El balanceo no puede programar ningun envio ese dia (spec 5.3: ni como origen ni como destino); los demas dias
-- siguen permitidos. Los 2 que ya estaban el 10 (en N2) deben salir de ese dia.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
VALUES ('e4000000-0000-0000-0000-000000000004', '2027-03-10', '2027-03-10', 'vacation', 'active',
        'a0000000-0000-0000-0000-000000000001');
SELECT pg_temp.mk('N1', '2027-03-08') FROM generate_series(1, 15);
SELECT pg_temp.mk('N2', '2027-03-10') FROM generate_series(1, 2);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'destino ausente success: ' || r::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'warnings') <> 0, 'no deberia haber avisos: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) > 0, 'envios el dia de ausencia del destino: ' || count(*))
  FROM public.allocation_plan_details WHERE fecha_programada = '2027-03-10';
SELECT pg_temp.fail_if(count(*) <> 17, 'se perdieron envios') FROM public.allocation_plan_details
 WHERE fecha_programada IN ('2027-03-08', '2027-03-09', '2027-03-11', '2027-03-12');
SELECT pg_temp.fail_if(count(DISTINCT fecha_programada) <> 4, 'los otros 4 dias deben seguir usandose')
  FROM public.allocation_plan_details;
ROLLBACK;

-- Caso 8b: el destino N4 ya no tiene panelista activo => ninguna fecha es valida: los envios se quedan y se avisa.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
UPDATE public.panelists SET status = 'inactive' WHERE id = 'e4000000-0000-0000-0000-000000000004';
SELECT pg_temp.mk('N1', '2027-03-08') FROM generate_series(1, 6);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int <> 0, 'destino sin panelista: no debe mover: ' || r::text);
  PERFORM pg_temp.fail_if(r->'warnings'->0->>'code' IS DISTINCT FROM 'no_valid_cell'
                          OR (r->'warnings'->0->>'count')::int <> 6, 'aviso no_valid_cell: ' || r::text);
END $$;
ROLLBACK;

-- ===== Guarda: actor 98 (cuenta 2) sobre una ciudad de la cuenta 1 => 42501, y nada cambia.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.mk('N1', '2027-03-08') FROM generate_series(1, 6);
SELECT set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
DO $$
BEGIN
  PERFORM public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  RAISE EXCEPTION 'FAIL actor de otra cuenta no debio poder balancear';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END $$;
SELECT pg_temp.fail_if(count(*) > 0, 'la guarda dejo mover envios') FROM public.allocation_plan_details WHERE reassigned_at IS NOT NULL;
ROLLBACK;
