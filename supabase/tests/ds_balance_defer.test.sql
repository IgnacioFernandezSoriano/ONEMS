-- Muestras por compensar (Task 2): fase 0 de rpc_balance_city_v2.
-- Destino sin panelista => otro nodo de la ciudad destino o al registro; ciudad origen sin ningun nodo valido =>
-- al registro; sin dia valido en el periodo y en las fechas del plan (tras buscar en otros meses) => al registro.
-- Fixture comun: C1 = N1, N2, N3 (P1..P3); C2 = N4 (P4); plan Mar27 2027-03-01..31; actor 99.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
CREATE FUNCTION pg_temp.mk_to(p_o text, p_d text, p_date date) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
         o.id, d.id, p_date, 'pending'
    FROM public.nodes o, public.nodes d WHERE o.auto_id = p_o AND d.auto_id = p_d
  RETURNING id;
$$;
CREATE FUNCTION pg_temp.warn_count(r jsonb, p_code text) RETURNS int LANGUAGE sql AS $$
  SELECT COALESCE((SELECT (w->>'count')::int FROM jsonb_array_elements(r->'warnings') w WHERE w->>'code' = p_code), 0);
$$;

-- ===== Caso 1: ciudad origen sin ningun panelista => las 6 muestras se apartan al registro.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id IN ('e1000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002',
                                          'e3000000-0000-0000-0000-000000000003');
CREATE TEMP TABLE c1ids AS SELECT pg_temp.mk_to('N1', 'N4', '2027-03-04') AS id FROM generate_series(1, 6);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', false);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'c1 preview success: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'removed')::int IS DISTINCT FROM 6, 'c1 preview removed: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->'by_reason'->>'origin_no_panelist')::int IS DISTINCT FROM 6, 'c1 preview by_reason: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int IS DISTINCT FROM 0, 'c1 preview movements: ' || r::text);
  PERFORM pg_temp.fail_if(pg_temp.warn_count(r, 'deferred_removed') <> 6, 'c1 preview warning: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.deferred_samples) <> 0, 'c1 la vista previa escribio en el registro');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details
                            WHERE status = 'pending' AND fecha_programada = '2027-03-04' AND reassigned_at IS NULL) <> 6,
                          'c1 la vista previa toco el plan');

  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'removed')::int IS DISTINCT FROM 6, 'c1 apply removed: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int IS DISTINCT FROM 0, 'c1 apply movements: ' || r::text);
  PERFORM pg_temp.fail_if(pg_temp.warn_count(r, 'deferred_removed') <> 6, 'c1 apply warning: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 6, 'c1 registro: 6 filas correctas, hay ' || count(*))
  FROM public.deferred_samples d
 WHERE d.status = 'pending' AND d.reason = 'origin_no_panelist'
   AND d.account_id = 'a0000000-0000-0000-0000-000000000001'
   AND d.plan_id = 'cc000000-0000-0000-0000-000000000001'
   AND d.origin_city_id = 'c1000000-0000-0000-0000-000000000001'
   AND d.dest_city_id = 'c2000000-0000-0000-0000-000000000002'
   AND d.origin_node_id = 'b1000000-0000-0000-0000-000000000001'
   AND d.destination_node_id = 'b4000000-0000-0000-0000-000000000004'
   AND d.fecha_programada = '2027-03-04'
   AND d.created_by = '99000000-0000-0000-0000-000000000099'
   AND d.row_snapshot->>'status' = 'pending'
   AND (d.row_snapshot->>'id')::uuid IN (SELECT id FROM c1ids);
SELECT pg_temp.fail_if((SELECT count(DISTINCT row_snapshot->>'id') FROM public.deferred_samples) <> 6, 'c1 snapshots distintos');
SELECT pg_temp.fail_if(count(*) <> 0, 'c1 quedan pendientes en C1: ' || count(*))
  FROM public.allocation_plan_details a JOIN public.nodes n ON n.id = a.origin_node_id
 WHERE n.city_id = 'c1000000-0000-0000-0000-000000000001' AND a.status = 'pending';
ROLLBACK;

-- ===== Caso 2: destino sin panelista, la ciudad destino tiene otro nodo valido (N5/P5) => se reasigna el destino.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N5');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','P5','Pan5','p5@t.l','5',
   'b5000000-0000-0000-0000-000000000005','active','en');
DELETE FROM public.panelists WHERE id = 'e4000000-0000-0000-0000-000000000004';
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-04') FROM generate_series(1, 2);
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-05') FROM generate_series(1, 2);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', false);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reassigned_dest')::int IS DISTINCT FROM 4, 'c2 preview reassigned: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details
                            WHERE destination_node_id = 'b4000000-0000-0000-0000-000000000004' AND reassigned_at IS NULL) <> 4,
                          'c2 la vista previa toco el plan');
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reassigned_dest')::int IS DISTINCT FROM 4, 'c2 apply reassigned: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'removed')::int IS DISTINCT FROM 0, 'c2 apply removed: ' || r::text);
  PERFORM pg_temp.fail_if(pg_temp.warn_count(r, 'no_valid_cell') <> 0, 'c2 no debe avisar no_valid_cell: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 4, 'c2 destinos reasignados con traza: ' || count(*))
  FROM public.allocation_plan_details
 WHERE destination_node_id = 'b5000000-0000-0000-0000-000000000005'
   AND original_destination_node_id = 'b4000000-0000-0000-0000-000000000004'
   AND destination_panelist_id = 'e5000000-0000-0000-0000-000000000005'
   AND destination_panelist_name = 'Pan5'
   AND reassignment_reason = 'rebalancing'
   AND reassigned_by = '99000000-0000-0000-0000-000000000099' AND reassigned_at IS NOT NULL
   AND status = 'pending';
SELECT pg_temp.fail_if(count(*) <> 0, 'c2 registro deberia estar vacio') FROM public.deferred_samples;
ROLLBACK;

-- ===== Caso 3: destino sin panelista y la ciudad destino no tiene otro nodo valido => al registro.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id = 'e4000000-0000-0000-0000-000000000004';
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-04') FROM generate_series(1, 3);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'removed')::int IS DISTINCT FROM 3
                          OR (r->'deferred'->'by_reason'->>'dest_no_panelist')::int IS DISTINCT FROM 3, 'c3 apply: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 3, 'c3 registro dest_no_panelist: ' || count(*)) FROM public.deferred_samples
 WHERE reason = 'dest_no_panelist' AND status = 'pending' AND dest_city_id = 'c2000000-0000-0000-0000-000000000002';
SELECT pg_temp.fail_if(count(*) <> 0, 'c3 quedan filas en el plan') FROM public.allocation_plan_details;
ROLLBACK;

-- ===== Caso 4a: sin dia valido. P1 ausente todo el plan (marzo), N1 unico nodo valido => al registro.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id IN ('e2000000-0000-0000-0000-000000000002','e3000000-0000-0000-0000-000000000003');
INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
VALUES ('e1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', 'vacation', 'active', 'a0000000-0000-0000-0000-000000000001');
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-10') FROM generate_series(1, 2);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'removed')::int IS DISTINCT FROM 2
                          OR (r->'deferred'->'by_reason'->>'no_valid_day')::int IS DISTINCT FROM 2, 'c4a apply: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 2, 'c4a registro no_valid_day') FROM public.deferred_samples WHERE reason = 'no_valid_day';
SELECT pg_temp.fail_if(count(*) <> 0, 'c4a quedan filas en el plan') FROM public.allocation_plan_details;
ROLLBACK;

-- Caso 4b: ausencia solo 8..12/3 => otra semana de marzo, nada al registro.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id IN ('e2000000-0000-0000-0000-000000000002','e3000000-0000-0000-0000-000000000003');
INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
VALUES ('e1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', 'vacation', 'active', 'a0000000-0000-0000-0000-000000000001');
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-10') FROM generate_series(1, 2);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'removed')::int IS DISTINCT FROM 0, 'c4b removed: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 2, 'c4b deben quedar 2 en marzo fuera de 8..12 en dia laborable: ' || count(*))
  FROM public.allocation_plan_details
 WHERE fecha_programada BETWEEN '2027-03-01' AND '2027-03-31' AND fecha_programada NOT BETWEEN '2027-03-08' AND '2027-03-12'
   AND EXTRACT(isodow FROM fecha_programada) <= 5 AND status = 'pending';
SELECT pg_temp.fail_if(count(*) <> 0, 'c4b registro deberia estar vacio') FROM public.deferred_samples;
ROLLBACK;

-- Caso 4c: ausencia 8..31/3 y plan ampliado a 30/4; periodo 8/3..30/4 => en marzo no hay celdas: pasan a abril.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id IN ('e2000000-0000-0000-0000-000000000002','e3000000-0000-0000-0000-000000000003');
INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
VALUES ('e1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-31', 'vacation', 'active', 'a0000000-0000-0000-0000-000000000001');
UPDATE public.allocation_plans SET end_date = '2027-04-30' WHERE id = 'cc000000-0000-0000-0000-000000000001';
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-10') FROM generate_series(1, 2);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-04-30', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'removed')::int IS DISTINCT FROM 0, 'c4c removed: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 2, 'c4c deben pasar a abril: ' || string_agg(fecha_programada::text, ','))
  FROM public.allocation_plan_details
 WHERE fecha_programada BETWEEN '2027-04-01' AND '2027-04-30' AND EXTRACT(isodow FROM fecha_programada) <= 5
   AND original_fecha_programada = '2027-03-10' AND reassignment_reason = 'rebalancing';
SELECT pg_temp.fail_if(count(*) <> 0, 'c4c registro deberia estar vacio') FROM public.deferred_samples;
ROLLBACK;

-- Caso 4d: filtro por fechas del plan tambien en el reparto normal. Plan Mar27 acaba el 19/3; periodo 15..26/3:
-- los 9 envios de N1 del 15/3 se reparten solo entre 15..19/3 (3 nodos x 5 dias), nunca la semana del 22.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
UPDATE public.allocation_plans SET end_date = '2027-03-19' WHERE id = 'cc000000-0000-0000-0000-000000000001';
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-15') FROM generate_series(1, 9);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-15', '2027-03-26', true);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int = 0 OR (r->'deferred'->>'removed')::int IS DISTINCT FROM 0, 'c4d: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) > 0, 'c4d fuera de las fechas del plan: ' || string_agg(fecha_programada::text, ','))
  FROM public.allocation_plan_details WHERE fecha_programada > '2027-03-19';
SELECT pg_temp.fail_if(count(*) <> 9, 'c4d se perdieron envios') FROM public.allocation_plan_details;
ROLLBACK;

-- ===== Caso 5: vista previa pura y atomicidad del borrado + anotacion.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id IN ('e1000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002',
                                          'e3000000-0000-0000-0000-000000000003');
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-04') FROM generate_series(1, 6);
SELECT public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', false) IS NOT NULL;
SELECT pg_temp.fail_if((SELECT count(*) FROM public.deferred_samples) <> 0, 'c5 la vista previa escribio en el registro');
SELECT pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details WHERE status = 'pending') <> 6, 'c5 la vista previa borro');
SELECT pg_temp.fail_if((SELECT balance_rotation_offset FROM public.cities WHERE id = 'c1000000-0000-0000-0000-000000000001') <> 0,
                       'c5 la vista previa movio la rotacion');
-- (a) fallo forzado en el DELETE despues del INSERT al registro: se deshace todo.
CREATE FUNCTION pg_temp.boom() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'boom registro=%', (SELECT count(*) FROM public.deferred_samples); END $$;
CREATE TRIGGER t_boom BEFORE DELETE ON public.allocation_plan_details FOR EACH ROW EXECUTE FUNCTION pg_temp.boom();
DO $$
DECLARE v_err text;
BEGIN
  BEGIN
    PERFORM public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  EXCEPTION WHEN others THEN v_err := SQLERRM;
  END;
  PERFORM pg_temp.fail_if(v_err IS DISTINCT FROM 'boom registro=6', 'c5a se esperaba el fallo tras anotar 6: ' || COALESCE(v_err, 'sin error'));
END $$;
SELECT pg_temp.fail_if((SELECT count(*) FROM public.deferred_samples) <> 0, 'c5a el registro no se deshizo');
SELECT pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details WHERE status = 'pending') <> 6, 'c5a el plan cambio');
DROP TRIGGER t_boom ON public.allocation_plan_details;
-- (b) el DELETE no borra lo anotado (un trigger lo salta) => la funcion detecta el descuadre y deshace todo.
CREATE FUNCTION pg_temp.skip_del() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END $$;
CREATE TRIGGER t_skip BEFORE DELETE ON public.allocation_plan_details FOR EACH ROW EXECUTE FUNCTION pg_temp.skip_del();
DO $$
DECLARE v_err text;
BEGIN
  BEGIN
    PERFORM public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  EXCEPTION WHEN others THEN v_err := SQLERRM;
  END;
  PERFORM pg_temp.fail_if(v_err IS NULL, 'c5b el descuadre registro/borrado no fallo');
END $$;
SELECT pg_temp.fail_if((SELECT count(*) FROM public.deferred_samples) <> 0, 'c5b el registro no se deshizo');
SELECT pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details WHERE status = 'pending') <> 6, 'c5b el plan cambio');
DROP TRIGGER t_skip ON public.allocation_plan_details;
-- (c) solo 'pending': una fila 'notified' del mismo nodo no se toca.
UPDATE public.allocation_plan_details SET status = 'notified'
 WHERE id = (SELECT id FROM public.allocation_plan_details ORDER BY id LIMIT 1);
SELECT public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true) IS NOT NULL;
SELECT pg_temp.fail_if((SELECT count(*) FROM public.deferred_samples) <> 5, 'c5c deben anotarse solo las 5 pendientes');
SELECT pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details WHERE status = 'notified') <> 1, 'c5c la notificada se toco');
ROLLBACK;
