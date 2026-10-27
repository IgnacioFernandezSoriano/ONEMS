-- Muestras por compensar (Task 3): fase R (reintroduccion) de rpc_balance_city_v2 y POBOX que tira del registro
-- antes de crear. Fixture comun: C1 = N1, N2, N3 (P1..P3); C2 = N4 (P4); planes Mar27 (2027-03-01..31) y Apr27
-- (2027-04-01..30), ambos 'active'; actor 99. 2027-03-01 es lunes.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
-- Pendiente del plan (por defecto Mar27).
CREATE FUNCTION pg_temp.mk_to(p_o text, p_d text, p_date date) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
         o.id, d.id, p_date, 'pending'
    FROM public.nodes o, public.nodes d WHERE o.auto_id = p_o AND d.auto_id = p_d
  RETURNING id;
$$;
-- Anotacion en el registro (como la dejaria la fase 0), ruta ciudad del nodo origen -> ciudad del nodo destino.
CREATE FUNCTION pg_temp.mk_ds(p_o text, p_d text, p_date date,
                              p_plan uuid DEFAULT 'cc000000-0000-0000-0000-000000000001') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.deferred_samples
    (account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id, fecha_programada,
     reason, row_snapshot, created_by)
  SELECT 'a0000000-0000-0000-0000-000000000001', p_plan, o.city_id, d.city_id, o.id, d.id, p_date,
         'origin_no_panelist', jsonb_build_object('id', gen_random_uuid()), '99000000-0000-0000-0000-000000000099'
    FROM public.nodes o, public.nodes d WHERE o.auto_id = p_o AND d.auto_id = p_d
  RETURNING id;
$$;
CREATE FUNCTION pg_temp.pobox_on() RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.account_config (account_id, pobox_enabled)
  VALUES ('a0000000-0000-0000-0000-000000000001', true)
  ON CONFLICT (account_id) DO UPDATE SET pobox_enabled = true;
$$;
CREATE FUNCTION pg_temp.matrix_sum(r jsonb, p_key text) RETURNS int LANGUAGE sql AS $$
  SELECT COALESCE(sum((m->>'load_count')::int), 0)::int FROM jsonb_array_elements(r->p_key) m;
$$;

-- ===== Caso 1: 3 anotaciones N1->N4 (Mar27), nodos validos, periodo marzo => se reintroducen las 3.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 3);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'c1 success: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 3, 'c1 reintroduced: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'waiting')::int IS DISTINCT FROM 0, 'c1 waiting: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'removed')::int IS DISTINCT FROM 0, 'c1 removed: ' || r::text);
  -- las reintroducidas entran en matrix_after (y no en matrix_before)
  PERFORM pg_temp.fail_if(pg_temp.matrix_sum(r, 'matrix_after') <> 3, 'c1 matrix_after: ' || r::text);
  PERFORM pg_temp.fail_if(pg_temp.matrix_sum(r, 'matrix_before') <> 0, 'c1 matrix_before: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'stddev_after')::numeric <= 0, 'c1 stddev_after: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 3, 'c1 filas compensation bien formadas: ' || count(*))
  FROM public.allocation_plan_details a
 WHERE a.generation_source = 'compensation' AND a.status = 'pending'
   AND a.account_id = 'a0000000-0000-0000-0000-000000000001'
   AND a.plan_id = 'cc000000-0000-0000-0000-000000000001'
   AND a.origin_node_id = 'b1000000-0000-0000-0000-000000000001'
   AND a.destination_node_id = 'b4000000-0000-0000-0000-000000000004'
   AND a.fecha_programada BETWEEN '2027-03-01' AND '2027-03-31'
   AND EXTRACT(isodow FROM a.fecha_programada) <= 5
   AND a.week_number = EXTRACT(week FROM a.fecha_programada) AND a.month = 3 AND a.year = 2027
   AND a.origin_panelist_id = 'e1000000-0000-0000-0000-000000000001' AND a.origin_panelist_name = 'Pan1'
   AND a.destination_panelist_id = 'e4000000-0000-0000-0000-000000000004' AND a.destination_panelist_name = 'Pan4'
   AND a.original_origin_node_id IS NULL AND a.original_destination_node_id IS NULL;
SELECT pg_temp.fail_if(count(DISTINCT fecha_programada) <> 3, 'c1 tope: un extra por nodo y dia')
  FROM public.allocation_plan_details WHERE generation_source = 'compensation';
SELECT pg_temp.fail_if(count(*) <> 3, 'c1 registro reintroducido y enlazado: ' || count(*))
  FROM public.deferred_samples d
  JOIN public.allocation_plan_details a ON a.id = d.reintroduced_detail_id AND a.generation_source = 'compensation'
 WHERE d.status = 'reintroduced' AND d.reintroduced_at IS NOT NULL AND d.waiting_reason IS NULL;
SELECT pg_temp.fail_if(count(DISTINCT reintroduced_detail_id) <> 3, 'c1 cada anotacion enlaza una fila distinta')
  FROM public.deferred_samples;
-- Segunda aplicacion: nada nuevo (idempotente).
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 0, 'c1 2a reintroduced: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 3, 'c1 2a no debe anadir filas: ' || count(*)) FROM public.allocation_plan_details;
SELECT pg_temp.fail_if(count(*) <> 3, 'c1 2a registro intacto')
  FROM public.deferred_samples WHERE status = 'reintroduced'
   AND reintroduced_detail_id IN (SELECT id FROM public.allocation_plan_details WHERE generation_source = 'compensation');
ROLLBACK;

-- ===== Caso 1b: nodos originales sin panelista => nodo menos cargado de la misma ciudad, con traza original_*.
-- N1 sin panelista (C1 conserva N2, N3); N4 sin panelista y C2 gana N5 (P5).
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N5');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','P5','Pan5','p5@t.l','5',
   'b5000000-0000-0000-0000-000000000005','active','en');
DELETE FROM public.panelists WHERE id IN ('e1000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000004');
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 2);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 2, 'c1b reintroduced: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 2, 'c1b nodos alternativos con traza: ' || count(*))
  FROM public.allocation_plan_details a
 WHERE a.generation_source = 'compensation'
   AND a.origin_node_id IN ('b2000000-0000-0000-0000-000000000002','b3000000-0000-0000-0000-000000000003')
   AND a.original_origin_node_id = 'b1000000-0000-0000-0000-000000000001'
   AND a.destination_node_id = 'b5000000-0000-0000-0000-000000000005'
   AND a.original_destination_node_id = 'b4000000-0000-0000-0000-000000000004'
   AND a.destination_panelist_id = 'e5000000-0000-0000-0000-000000000005' AND a.destination_panelist_name = 'Pan5'
   AND a.origin_panelist_id IS NOT NULL AND a.origin_panelist_name IS NOT NULL;
ROLLBACK;

-- ===== Caso 2 (tope): solo N1 valido en C1; periodo 8..12/3 (5 dias laborables) con 1 pendiente por dia y 8
-- anotaciones => se reintroducen 5 (una por dia, quedan 2 por dia) y 3 esperan con no_capacity. Una segunda
-- aplicacion sobre 15..19/3 reintroduce las 3.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id IN ('e2000000-0000-0000-0000-000000000002','e3000000-0000-0000-0000-000000000003');
SELECT pg_temp.mk_to('N1', 'N4', g::date) FROM generate_series('2027-03-08'::date, '2027-03-12', interval '1 day') g;
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 8);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 5, 'c2 reintroduced: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'waiting')::int IS DISTINCT FROM 3, 'c2 waiting: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->'waiting_by_reason'->>'no_capacity')::int IS DISTINCT FROM 3,
                          'c2 waiting_by_reason: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int IS DISTINCT FROM 0, 'c2 movements: ' || r::text);
  PERFORM pg_temp.fail_if(pg_temp.matrix_sum(r, 'matrix_after') <> 10, 'c2 matrix_after: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 5 OR min(n) <> 2 OR max(n) <> 2, 'c2 deben quedar 2 envios por dia en N1')
  FROM (SELECT fecha_programada, count(*) AS n FROM public.allocation_plan_details
         WHERE origin_node_id = 'b1000000-0000-0000-0000-000000000001' GROUP BY fecha_programada) x;
SELECT pg_temp.fail_if(count(*) <> 5, 'c2 filas compensation: ' || count(*))
  FROM public.allocation_plan_details WHERE generation_source = 'compensation';
SELECT pg_temp.fail_if(count(*) <> 5, 'c2 anotaciones reintroducidas') FROM public.deferred_samples WHERE status = 'reintroduced';
SELECT pg_temp.fail_if(count(*) <> 3, 'c2 anotaciones en espera no_capacity')
  FROM public.deferred_samples WHERE status = 'pending' AND waiting_reason = 'no_capacity';
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-15', '2027-03-19', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 3, 'c2 2a reintroduced: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'waiting')::int IS DISTINCT FROM 0, 'c2 2a waiting: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 8, 'c2 2a todas reintroducidas')
  FROM public.deferred_samples WHERE status = 'reintroduced' AND waiting_reason IS NULL;
SELECT pg_temp.fail_if(count(*) <> 3 OR count(DISTINCT fecha_programada) <> 3, 'c2 2a tres nuevas en 15..19, una por dia')
  FROM public.allocation_plan_details
 WHERE generation_source = 'compensation' AND fecha_programada BETWEEN '2027-03-15' AND '2027-03-19';
ROLLBACK;

-- ===== Caso 3a (motivo de espera): la ciudad destino C2 no tiene panelista => no_dest_panelist, nada insertado.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id = 'e4000000-0000-0000-0000-000000000004';
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 2);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', false);
  PERFORM pg_temp.fail_if((r->'deferred'->'waiting_by_reason'->>'no_dest_panelist')::int IS DISTINCT FROM 2,
                          'c3a preview: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.deferred_samples WHERE waiting_reason IS NOT NULL) <> 0,
                          'c3a la vista previa escribio waiting_reason');
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 0
                          OR (r->'deferred'->>'waiting')::int IS DISTINCT FROM 2, 'c3a apply: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 2, 'c3a waiting_reason no_dest_panelist')
  FROM public.deferred_samples WHERE status = 'pending' AND waiting_reason = 'no_dest_panelist';
SELECT pg_temp.fail_if(count(*) <> 0, 'c3a no debe insertarse nada') FROM public.allocation_plan_details;
ROLLBACK;

-- ===== Caso 3b: plan 'completed' => plan_inactive; anotacion de Apr27 con periodo marzo => outside_period.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
UPDATE public.allocation_plans SET status = 'completed' WHERE id = 'cc000000-0000-0000-0000-000000000001';
CREATE TEMP TABLE c3b AS
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') AS inactive_id,
       pg_temp.mk_ds('N1', 'N4', '2027-04-05', 'cc000000-0000-0000-0000-000000000002') AS outside_id;
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 0
                          OR (r->'deferred'->'waiting_by_reason'->>'plan_inactive')::int IS DISTINCT FROM 1
                          OR (r->'deferred'->'waiting_by_reason'->>'outside_period')::int IS DISTINCT FROM 1, 'c3b: ' || r::text);
END $$;
SELECT pg_temp.fail_if((SELECT waiting_reason FROM public.deferred_samples WHERE id = (SELECT inactive_id FROM c3b))
                       IS DISTINCT FROM 'plan_inactive', 'c3b plan_inactive');
SELECT pg_temp.fail_if((SELECT waiting_reason FROM public.deferred_samples WHERE id = (SELECT outside_id FROM c3b))
                       IS DISTINCT FROM 'outside_period', 'c3b outside_period');
SELECT pg_temp.fail_if(count(*) <> 0, 'c3b no debe insertarse nada') FROM public.allocation_plan_details;
ROLLBACK;

-- ===== Caso 3c: la ciudad origen no tiene ningun panelista => no_origin_panelist.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id IN ('e1000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002',
                                          'e3000000-0000-0000-0000-000000000003');
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 0, 'c3c: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 1, 'c3c no_origin_panelist')
  FROM public.deferred_samples WHERE status = 'pending' AND waiting_reason = 'no_origin_panelist';
SELECT pg_temp.fail_if(count(*) <> 0, 'c3c no debe insertarse nada') FROM public.allocation_plan_details;
ROLLBACK;

-- ===== Caso 4 (POBOX tira del registro): POBOX activo; periodo 8..9/3; 1 pendiente el 8, nada el 9; 1 anotacion
-- C1->C2 de Mar27 => el 9 queda cubierto por una fila 'compensation' (no 'pobox').
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.pobox_on();
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-08');
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-09', true);
  PERFORM pg_temp.fail_if((r->'pobox'->>'days_missing')::int IS DISTINCT FROM 1
                          OR (r->'pobox'->>'days_reintroduced')::int IS DISTINCT FROM 1
                          OR (r->'pobox'->>'days_created')::int IS DISTINCT FROM 0
                          OR (r->'pobox'->>'days_moved')::int IS DISTINCT FROM 0
                          OR (r->'pobox'->>'days_uncovered')::int IS DISTINCT FROM 0, 'c4 pobox: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 1, 'c4 reintroduced: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 1, 'c4 el 9 cubierto por compensation')
  FROM public.allocation_plan_details WHERE fecha_programada = '2027-03-09' AND generation_source = 'compensation';
SELECT pg_temp.fail_if(count(*) <> 0, 'c4 no debe crearse pobox') FROM public.allocation_plan_details WHERE generation_source = 'pobox';
SELECT pg_temp.fail_if(count(*) <> 1, 'c4 anotacion reintroducida')
  FROM public.deferred_samples d JOIN public.allocation_plan_details a ON a.id = d.reintroduced_detail_id
 WHERE d.status = 'reintroduced' AND a.fecha_programada = '2027-03-09';
ROLLBACK;

-- ===== Caso 4b: mismo montaje sin anotaciones => POBOX crea una fila 'pobox' (regresion de lb2_pobox caso 2).
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.pobox_on();
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-08');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-09', true);
  PERFORM pg_temp.fail_if((r->'pobox'->>'days_missing')::int IS DISTINCT FROM 1
                          OR (r->'pobox'->>'days_reintroduced')::int IS DISTINCT FROM 0
                          OR (r->'pobox'->>'days_created')::int IS DISTINCT FROM 1, 'c4b pobox: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 0, 'c4b reintroduced: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 1, 'c4b el 9 cubierto por pobox')
  FROM public.allocation_plan_details WHERE fecha_programada = '2027-03-09' AND generation_source = 'pobox';
SELECT pg_temp.fail_if(count(*) <> 0, 'c4b sin compensation') FROM public.allocation_plan_details WHERE generation_source = 'compensation';
ROLLBACK;

-- ===== Caso 5: la vista previa de los casos 1 y 4 no escribe nada en ninguna de las dos tablas.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 3);
DO $$
DECLARE r jsonb; r2 jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', false);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 3, 'c5 preview reintroduced: ' || r::text);
  PERFORM pg_temp.fail_if(pg_temp.matrix_sum(r, 'matrix_after') <> 3, 'c5 preview matrix_after: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details) <> 0, 'c5 la vista previa inserto filas');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.deferred_samples
                            WHERE status <> 'pending' OR reintroduced_at IS NOT NULL OR reintroduced_detail_id IS NOT NULL
                               OR waiting_reason IS NOT NULL) <> 0, 'c5 la vista previa toco el registro');
  r2 := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if(r2->'deferred' IS DISTINCT FROM r->'deferred', 'c5 preview y apply distintos: ' || r::text || ' / ' || r2::text);
  PERFORM pg_temp.fail_if(r2->'matrix_after' IS DISTINCT FROM r->'matrix_after', 'c5 matrix_after preview vs apply');
END $$;
ROLLBACK;
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.pobox_on();
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-08');
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04');
DO $$
DECLARE r jsonb; r2 jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-09', false);
  PERFORM pg_temp.fail_if((r->'pobox'->>'days_reintroduced')::int IS DISTINCT FROM 1, 'c5 preview pobox: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details) <> 1, 'c5 la vista previa POBOX inserto filas');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details WHERE reassigned_at IS NOT NULL) <> 0,
                          'c5 la vista previa POBOX movio filas');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.deferred_samples
                            WHERE status <> 'pending' OR reintroduced_detail_id IS NOT NULL OR waiting_reason IS NOT NULL) <> 0,
                          'c5 la vista previa POBOX toco el registro');
  r2 := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-09', true);
  PERFORM pg_temp.fail_if(r2->'pobox' IS DISTINCT FROM r->'pobox', 'c5 pobox preview vs apply: ' || r2::text);
END $$;
ROLLBACK;

-- ===== Caso 6: concurrencia/atomicidad. Si la actualizacion del registro no cuadra (un trigger la anula), se
-- aborta TODO: ni filas compensation ni registro cambiado.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 2);
CREATE FUNCTION pg_temp.skip_upd() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END $$;
CREATE TRIGGER skip_ds_upd BEFORE UPDATE ON public.deferred_samples FOR EACH ROW EXECUTE FUNCTION pg_temp.skip_upd();
DO $$
DECLARE r jsonb; ok boolean := false;
BEGIN
  BEGIN
    r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%reintroduc%';
    PERFORM pg_temp.fail_if(NOT ok, 'c6 error inesperado: ' || SQLERRM);
  END;
  PERFORM pg_temp.fail_if(NOT ok, 'c6 debia abortar');
END $$;
SELECT pg_temp.fail_if(count(*) <> 0, 'c6 quedaron filas compensation') FROM public.allocation_plan_details;
SELECT pg_temp.fail_if(count(*) <> 2, 'c6 registro cambiado') FROM public.deferred_samples WHERE status = 'pending';
ROLLBACK;

-- ===== Ronda de correcciones 1 (casos 6d..12). Comprobacion comun: ninguna fila compensation fuera de dia
-- laborable o de su plan; como mucho 1 compensation por (nodo origen, dia) y por (nodo destino, dia).
CREATE FUNCTION pg_temp.comp_caps_ok() RETURNS boolean LANGUAGE sql AS $$
  SELECT NOT EXISTS (SELECT 1 FROM public.allocation_plan_details
                      WHERE generation_source = 'compensation' AND status <> 'cancelled'
                      GROUP BY origin_node_id, fecha_programada HAVING count(*) > 1)
     AND NOT EXISTS (SELECT 1 FROM public.allocation_plan_details
                      WHERE generation_source = 'compensation' AND status <> 'cancelled'
                      GROUP BY destination_node_id, fecha_programada HAVING count(*) > 1)
     AND NOT EXISTS (SELECT 1 FROM public.allocation_plan_details a JOIN public.allocation_plans p ON p.id = a.plan_id
                      WHERE a.generation_source = 'compensation'
                        AND (EXTRACT(isodow FROM a.fecha_programada) > 5
                             OR a.fecha_programada NOT BETWEEN p.start_date AND p.end_date));
$$;

-- ===== Caso 6d (destino ausente): P4 ausente el 9 y el 10; periodo 8..12/3; 5 anotaciones => ninguna esos dias;
-- con el tope de recepcion (1 por nodo destino y dia) caben 3 (8, 11, 12) y 2 esperan no_capacity.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
VALUES ('e4000000-0000-0000-0000-000000000004', '2027-03-09', '2027-03-10', 'vacation', 'active', 'a0000000-0000-0000-0000-000000000001');
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 5);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 3
                          OR (r->'deferred'->'waiting_by_reason'->>'no_capacity')::int IS DISTINCT FROM 2, 'c6d: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 0, 'c6d compensation en dia de ausencia del destino')
  FROM public.allocation_plan_details WHERE generation_source = 'compensation' AND fecha_programada IN ('2027-03-09', '2027-03-10');
SELECT pg_temp.fail_if(NOT pg_temp.comp_caps_ok(), 'c6d topes');
ROLLBACK;

-- ===== Caso 7 (origen ausente): N1 unico nodo valido, P1 ausente 8 y 9; periodo 8..12; 5 anotaciones => van al
-- 10, 11 y 12; 2 esperan.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id IN ('e2000000-0000-0000-0000-000000000002','e3000000-0000-0000-0000-000000000003');
INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
VALUES ('e1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-09', 'vacation', 'active', 'a0000000-0000-0000-0000-000000000001');
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 5);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 3
                          OR (r->'deferred'->>'waiting')::int IS DISTINCT FROM 2, 'c7: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 0, 'c7 compensation en dia de ausencia del origen')
  FROM public.allocation_plan_details WHERE generation_source = 'compensation' AND fecha_programada IN ('2027-03-08', '2027-03-09');
SELECT pg_temp.fail_if(NOT pg_temp.comp_caps_ok(), 'c7 topes');
ROLLBACK;

-- ===== Caso 8 (plan que termina a mitad del periodo): Mar27 termina el 10/3; periodo 8..12; 5 anotaciones =>
-- nada despues del 10.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
UPDATE public.allocation_plans SET end_date = '2027-03-10' WHERE id = 'cc000000-0000-0000-0000-000000000001';
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 5);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 3
                          OR (r->'deferred'->>'waiting')::int IS DISTINCT FROM 2, 'c8: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 0, 'c8 compensation despues del fin del plan')
  FROM public.allocation_plan_details WHERE generation_source = 'compensation' AND fecha_programada > '2027-03-10';
SELECT pg_temp.fail_if(NOT pg_temp.comp_caps_ok(), 'c8 topes');
ROLLBACK;

-- ===== Caso 9 (politica semanal): 4 pendientes el 8/3 y 4 anotaciones, periodo 8..19/3 => las 4 se reintroducen
-- en dias laborables del periodo y del plan, respetando los topes.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
UPDATE public.cities SET date_policy = 'weekly' WHERE id = 'c1000000-0000-0000-0000-000000000001';
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-08') FROM generate_series(1, 4);
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 4);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-19', true);
  PERFORM pg_temp.fail_if(r->'policy'->>'date_policy' IS DISTINCT FROM 'weekly', 'c9 policy: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 4, 'c9 reintroduced: ' || r::text);
  PERFORM pg_temp.fail_if(pg_temp.matrix_sum(r, 'matrix_after') <> 8, 'c9 matrix_after: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 4, 'c9 compensation en el periodo')
  FROM public.allocation_plan_details WHERE generation_source = 'compensation' AND fecha_programada BETWEEN '2027-03-08' AND '2027-03-19';
SELECT pg_temp.fail_if(NOT pg_temp.comp_caps_ok(), 'c9 topes');
ROLLBACK;

-- ===== Caso 10 (otra cuenta): una anotacion de la cuenta 2 (aunque apunte a C1) nunca se reintroduce ni se toca.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
INSERT INTO public.deferred_samples (account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id,
                                     fecha_programada, reason, row_snapshot)
VALUES ('a0000000-0000-0000-0000-000000000002', 'cc000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
        'c2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000004',
        '2027-03-04', 'origin_no_panelist', '{}');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 0
                          OR (r->'deferred'->>'waiting')::int IS DISTINCT FROM 0, 'c10: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 0, 'c10 se inserto algo') FROM public.allocation_plan_details;
SELECT pg_temp.fail_if(count(*) <> 1, 'c10 la anotacion de la cuenta 2 cambio')
  FROM public.deferred_samples WHERE status = 'pending' AND waiting_reason IS NULL AND reintroduced_detail_id IS NULL;
ROLLBACK;

-- ===== Caso 11 (R4, tope total): como el caso 2 (N1 unico, 1 pendiente por dia 8..12, 8 anotaciones). Tras la
-- primera aplicacion cada (N1, dia) ya tiene su compensation: aplicar otra vez el MISMO periodo no anade nada.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id IN ('e2000000-0000-0000-0000-000000000002','e3000000-0000-0000-0000-000000000003');
SELECT pg_temp.mk_to('N1', 'N4', g::date) FROM generate_series('2027-03-08'::date, '2027-03-12', interval '1 day') g;
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 8);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 5, 'c11 1a: ' || r::text);
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', false);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 0, 'c11 2a preview: ' || r::text);
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 0
                          OR (r->'deferred'->>'waiting')::int IS DISTINCT FROM 3
                          OR (r->'deferred'->'waiting_by_reason'->>'no_capacity')::int IS DISTINCT FROM 3, 'c11 2a apply: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 10, 'c11 la segunda aplicacion anadio filas: ' || count(*)) FROM public.allocation_plan_details;
SELECT pg_temp.fail_if(NOT pg_temp.comp_caps_ok(), 'c11 topes');
ROLLBACK;

-- ===== Caso 12 (R5, tope de recepcion): C1 (N1) y C3 (N6) envian anotaciones al mismo destino N4 en 8..12/3.
-- Tras balancear C1 (5 reintroducidas, una por dia) N4 ya recibe 1 compensation cada dia: C3 no anade ninguna.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City3','C3');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000003','N6');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','P6','Pan6','p6@t.l','6',
   'b6000000-0000-0000-0000-000000000006','active','en');
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 5);
SELECT pg_temp.mk_ds('N6', 'N4', '2027-03-04') FROM generate_series(1, 5);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 5, 'c12 C1: ' || r::text);
  r := public.rpc_balance_city_v2('c3000000-0000-0000-0000-000000000003', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 0
                          OR (r->'deferred'->'waiting_by_reason'->>'no_capacity')::int IS DISTINCT FROM 5, 'c12 C3: ' || r::text);
END $$;
SELECT pg_temp.fail_if(NOT pg_temp.comp_caps_ok(), 'c12 mas de una compensation por (nodo destino, dia)');
SELECT pg_temp.fail_if(count(*) <> 5, 'c12 total compensation') FROM public.allocation_plan_details WHERE generation_source = 'compensation';
ROLLBACK;

-- ===== Ronda de correcciones 2 (R7: una 'compensation' en hueco valido queda fija).

-- ===== Caso 13a (semanal, aplicar dos veces): N1 unico nodo, politica semanal, periodo 8..12/3, 8 anotaciones.
-- 1a: 5 reintroducidas (L-V). 2a sobre el mismo periodo: 0 nuevas y las 5 siguen en su dia (no se juntan el lunes).
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
UPDATE public.cities SET date_policy = 'weekly' WHERE id = 'c1000000-0000-0000-0000-000000000001';
DELETE FROM public.panelists WHERE id IN ('e2000000-0000-0000-0000-000000000002','e3000000-0000-0000-0000-000000000003');
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 8);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 5, 'c13a 1a: ' || r::text);
END $$;
CREATE TEMP TABLE c13a AS SELECT id, fecha_programada FROM public.allocation_plan_details WHERE generation_source = 'compensation';
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 0
                          OR (r->'deferred'->>'waiting')::int IS DISTINCT FROM 3, 'c13a 2a: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int IS DISTINCT FROM 0, 'c13a 2a movimientos: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM jsonb_array_elements(r->'warnings') w WHERE w->>'code' = 'no_valid_cell'),
                          'c13a 2a no debe avisar no_valid_cell: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 5, 'c13a 2a anadio filas: ' || count(*)) FROM public.allocation_plan_details;
SELECT pg_temp.fail_if(count(*) <> 5, 'c13a las compensation cambiaron de dia')
  FROM public.allocation_plan_details a JOIN c13a c ON c.id = a.id AND c.fecha_programada = a.fecha_programada;
SELECT pg_temp.fail_if(count(DISTINCT fecha_programada) <> 5, 'c13a deben seguir en 5 dias distintos') FROM c13a;
SELECT pg_temp.fail_if(NOT pg_temp.comp_caps_ok(), 'c13a topes');
ROLLBACK;

-- ===== Caso 13b (diaria, el reparto querria mover): N1 unico nodo, periodo 8..12/3, 3 anotaciones => 8, 9 y 10.
-- Despues llegan 2 pendientes mas el dia 8: el reparto mueve esas (a 11 y 12), no las compensation.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id IN ('e2000000-0000-0000-0000-000000000002','e3000000-0000-0000-0000-000000000003');
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 3);
DO $$
BEGIN
  PERFORM pg_temp.fail_if((public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true)
                           ->'deferred'->>'reintroduced')::int IS DISTINCT FROM 3, 'c13b 1a');
END $$;
CREATE TEMP TABLE c13b AS SELECT id, fecha_programada FROM public.allocation_plan_details WHERE generation_source = 'compensation';
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-08') FROM generate_series(1, 2);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 0, 'c13b 2a: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM jsonb_array_elements(r->'warnings') w WHERE w->>'code' = 'no_valid_cell'),
                          'c13b 2a no debe avisar no_valid_cell: ' || r::text);
  -- carga final 1 por dia (las compensation cuentan como carga fija)
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM jsonb_array_elements(r->'matrix_after') m WHERE (m->>'load_count')::int <> 1),
                          'c13b matrix_after: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 3, 'c13b las compensation se movieron')
  FROM public.allocation_plan_details a JOIN c13b c ON c.id = a.id AND c.fecha_programada = a.fecha_programada
 WHERE a.reassigned_at IS NULL;
SELECT pg_temp.fail_if(count(*) <> 2, 'c13b las pendientes nuevas deben ir a 11 y 12')
  FROM public.allocation_plan_details WHERE generation_source = 'plan' AND fecha_programada IN ('2027-03-11', '2027-03-12');
SELECT pg_temp.fail_if(NOT pg_temp.comp_caps_ok(), 'c13b topes');
ROLLBACK;

-- ===== Caso 13c (baja declarada despues): como 13b tras la 1a aplicacion (8, 9, 10); P1 declara baja el 8 => la
-- compensation del 8 ya no esta en un hueco valido: se mueve (a 11 o 12); las del 9 y 10 no se tocan.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DELETE FROM public.panelists WHERE id IN ('e2000000-0000-0000-0000-000000000002','e3000000-0000-0000-0000-000000000003');
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-04') FROM generate_series(1, 3);
DO $$
BEGIN
  PERFORM pg_temp.fail_if((public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true)
                           ->'deferred'->>'reintroduced')::int IS DISTINCT FROM 3, 'c13c 1a');
END $$;
CREATE TEMP TABLE c13c AS SELECT id, fecha_programada FROM public.allocation_plan_details WHERE generation_source = 'compensation';
SELECT pg_temp.fail_if((SELECT array_agg(fecha_programada ORDER BY fecha_programada) FROM c13c)
                       IS DISTINCT FROM ARRAY['2027-03-08','2027-03-09','2027-03-10']::date[], 'c13c dias de partida');
INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
VALUES ('e1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-08', 'vacation', 'active', 'a0000000-0000-0000-0000-000000000001');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int IS DISTINCT FROM 1, 'c13c 2a movimientos: ' || r::text);
END $$;
SELECT pg_temp.fail_if((SELECT a.fecha_programada FROM public.allocation_plan_details a JOIN c13c c ON c.id = a.id
                         WHERE c.fecha_programada = '2027-03-08') NOT IN ('2027-03-11', '2027-03-12'),
                       'c13c la compensation del dia de baja debia moverse a 11 o 12');
SELECT pg_temp.fail_if(count(*) <> 2, 'c13c las otras dos no debian moverse')
  FROM public.allocation_plan_details a JOIN c13c c ON c.id = a.id AND c.fecha_programada = a.fecha_programada
 WHERE c.fecha_programada IN ('2027-03-09', '2027-03-10');
SELECT pg_temp.fail_if(count(*) <> 0, 'c13c compensation en el dia de baja')
  FROM public.allocation_plan_details WHERE fecha_programada = '2027-03-08';
SELECT pg_temp.fail_if(NOT pg_temp.comp_caps_ok(), 'c13c topes');
ROLLBACK;

-- ===== Caso 13d (POBOX no mueve una compensation a un (destino, dia) que ya recibe una): POBOX activo; 5
-- compensation N1->N4 el 8/3 con P1 de baja ese dia (fuera de hueco valido => movibles). Sin mas, el reparto deja
-- 8, 11 y 12 vacios y POBOX los cubre moviendo compensation. Si N4 ya recibe una compensation (de C3) esos dias,
-- POBOX no puede mover las de C1 alli: crea.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.pobox_on();
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City3','C3');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000003','N6');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','P6','Pan6','p6@t.l','6',
   'b6000000-0000-0000-0000-000000000006','active','en');
INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
VALUES ('e1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-08', 'vacation', 'active', 'a0000000-0000-0000-0000-000000000001');
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, generation_source)
SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
       o.id, 'b4000000-0000-0000-0000-000000000004', d::date, 'pending', 'compensation'
  FROM (SELECT id FROM public.nodes WHERE auto_id = 'N1') o, unnest(ARRAY['2027-03-08','2027-03-08','2027-03-08','2027-03-08','2027-03-08']) d;
-- C3 -> N4 compensation los dias 8, 11 y 12
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, generation_source)
SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
       'b6000000-0000-0000-0000-000000000006', 'b4000000-0000-0000-0000-000000000004', d::date, 'pending', 'compensation'
  FROM unnest(ARRAY['2027-03-08','2027-03-11','2027-03-12']) d;
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12', true);
  PERFORM pg_temp.fail_if((r->'pobox'->>'days_missing')::int IS DISTINCT FROM 3
                          OR (r->'pobox'->>'days_moved')::int IS DISTINCT FROM 0, 'c13d pobox: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) > 0, 'c13d POBOX movio una compensation a un (destino, dia) que ya recibe una')
  FROM public.allocation_plan_details WHERE generation_source = 'compensation' AND reassignment_reason = 'pobox_move';
-- (El montaje parte de 5 compensation apiladas en (N1, 8/3), ya fuera de tope; aqui solo se comprueba POBOX.)
SELECT pg_temp.fail_if(count(*) <> 3 OR max(n) <> 1, 'c13d N4 debe recibir solo la compensation de C3 los dias 8, 11 y 12')
  FROM (SELECT fecha_programada, count(*) AS n FROM public.allocation_plan_details
         WHERE generation_source = 'compensation' AND destination_node_id = 'b4000000-0000-0000-0000-000000000004'
           AND fecha_programada IN ('2027-03-08', '2027-03-11', '2027-03-12')
         GROUP BY fecha_programada) x;
SELECT pg_temp.fail_if(count(*) <> 3, 'c13d POBOX debia crear en 8, 11 y 12')
  FROM public.allocation_plan_details WHERE generation_source = 'pobox';
ROLLBACK;

-- ===== Fix wave (R9). Caso 14: la fase R nunca coloca una compensation HOY (hoy de la cuenta): n8n ya pudo enviar
-- los avisos del dia y la muestra quedaria sin notificar. Fechas relativas a hoy; periodo hoy..hoy+7 con un plan
-- que lo cubre. Si hoy es fin de semana la comprobacion sigue siendo valida.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
CREATE TEMP TABLE c14 AS
SELECT (now() AT TIME ZONE COALESCE(a.timezone, 'UTC'))::date AS today
  FROM public.accounts a WHERE a.id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status)
SELECT 'cc000000-0000-0000-0000-000000000014', 'a0000000-0000-0000-0000-000000000001', 'Now',
       'ca000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001', 10, today - 30, today + 60, 'active'
  FROM c14;
SELECT pg_temp.mk_ds('N1', 'N4', (SELECT today - 3 FROM c14), 'cc000000-0000-0000-0000-000000000014') FROM generate_series(1, 3);
DO $$
DECLARE r jsonb; v_today date := (SELECT today FROM c14);
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', v_today, v_today + 7, true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 3, 'c14 reintroduced: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) > 0, 'c14 compensation hoy o antes: ' || string_agg(fecha_programada::text, ','))
  FROM public.allocation_plan_details
 WHERE generation_source = 'compensation' AND fecha_programada <= (SELECT today FROM c14);
SELECT pg_temp.fail_if(NOT pg_temp.comp_caps_ok(), 'c14 topes');
ROLLBACK;
