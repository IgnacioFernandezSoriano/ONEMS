-- Carrier Link fase 0, tarea 2: tiempo de equivalencia en el calculo de transito (one_db_compute_transit),
-- cl_equivalence(standard_id) y propagacion al cambiar un estandar (cl_equivalence_on_sla_change).
-- Las filas source='panelist' deben quedar exactamente como antes (mismo calculo, measured_* NULL).
\set ON_ERROR_STOP on
SET client_min_messages = error;
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;

-- Helper: inserta una fila en one_db de la ruta Kericho -> Garissa (fixture Kenya) con el producto indicado.
CREATE FUNCTION pg_temp.row(p_tag text, p_source text, p_product text, p_sent timestamptz, p_recv timestamptz,
                            p_eq_h numeric, p_eq_d integer) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.one_db (account_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name,
                             sent_at, received_at, source_data_snapshot, source, carrier_id, equivalence_hours, equivalence_days)
  VALUES ('a0000000-0000-0000-0000-000000000003', p_tag, 'P', 'KENYA POST', p_product, 'Kericho', 'Garissa',
          p_sent, p_recv, '{}', p_source,
          CASE WHEN p_source = 'carrier' THEN 'ca000000-0000-0000-0000-000000000003'::uuid END, p_eq_h, p_eq_d);
$$;

-- ===== E1: fila panelist = calculo de siempre; measured_* NULL; la equivalencia se ignora aunque venga informada
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.row('P1', 'panelist', 'Economy delivery within 48hrs', '2026-10-27 13:44:18Z', '2026-10-29 07:40:57Z', NULL, NULL);
SELECT pg_temp.row('P2', 'panelist', 'Economy delivery within 48hrs', '2026-10-29 13:00:00Z', '2026-11-02 07:00:00Z', 24, 1);
SELECT pg_temp.fail_if(EXISTS (
  SELECT 1 FROM one_db o
   WHERE o.business_transit_hours IS DISTINCT FROM calculate_business_hours(o.sent_at, o.received_at, o.account_id)
      OR o.business_transit_days  IS DISTINCT FROM calculate_business_days(o.sent_at, o.received_at, o.account_id)
      OR o.total_transit_days     IS DISTINCT FROM (o.received_at_local::date - o.sent_at_local::date)
      OR o.total_transit_hours    IS DISTINCT FROM ROUND(extract(epoch FROM (o.received_at - o.sent_at)) / 3600.0, 2)
      OR o.measured_total_hours IS NOT NULL OR o.measured_total_days IS NOT NULL
      OR o.measured_business_hours IS NOT NULL OR o.measured_business_days IS NOT NULL), 'E1 panelist distinto del calculo base');
-- valores literales conocidos (mismos que one_db_business_time T3 / T1b)
SELECT pg_temp.fail_if((SELECT (total_transit_hours, business_transit_hours, total_transit_days, business_transit_days)
                          FROM one_db WHERE tag_id = 'P1') IS DISTINCT FROM (41.94::numeric(10,2), 41.94::numeric(10,2), 2, 2), 'E1 P1 literales');
SELECT pg_temp.fail_if((SELECT (total_transit_hours, business_transit_hours, total_transit_days, business_transit_days)
                          FROM one_db WHERE tag_id = 'P2') IS DISTINCT FROM (90.00::numeric(10,2), 42.00::numeric(10,2), 4, 2), 'E1 P2 literales (equivalencia ignorada)');
-- un UPDATE de la equivalencia en una fila panelist tampoco cambia nada
UPDATE one_db SET equivalence_hours = 48, equivalence_days = 2 WHERE tag_id = 'P1';
SELECT pg_temp.fail_if((SELECT (business_transit_hours, business_transit_days, measured_business_hours)
                          FROM one_db WHERE tag_id = 'P1') IS DISTINCT FROM (41.94::numeric(10,2), 2, NULL::numeric), 'E1 P1 tras UPDATE equivalencia');
ROLLBACK;

-- ===== E1b: fila panelist por el camino real (transfer_to_one_db) = calculo base, source panelist, measured NULL
BEGIN;
\ir fixtures/one_db_kenya.sql
INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status, tag_id, sent_at)
VALUES ('a0000000-0000-0000-0000-000000000003', 'cc000000-0000-0000-0000-000000000003', 'b1000000-0000-0000-0000-000000000003',
        'b2000000-0000-0000-0000-000000000003', '2026-10-27', 44, 10, 2026, 'sent', '00010305', '2026-10-27 13:44:18Z');
UPDATE public.allocation_plan_details SET status = 'received', received_at = '2026-10-29 07:40:57Z' WHERE tag_id = '00010305';
SELECT pg_temp.fail_if((SELECT (source, total_transit_hours, business_transit_hours, total_transit_days, business_transit_days, on_time_delivery,
                                measured_business_hours, equivalence_hours) FROM one_db)
                       IS DISTINCT FROM ('panelist'::text, 41.94::numeric(10,2), 41.94::numeric(10,2), 2, 2, true, NULL::numeric, NULL::numeric), 'E1b transfer panelist');
ROLLBACK;

-- ===== E2: fila carrier con equivalencia 24 h / 1 dia = medido + equivalencia; y nunca se acumula
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.row('C1', 'carrier', 'Economy delivery within 48hrs', '2026-10-27 13:44:18Z', '2026-10-29 07:40:57Z', 24, 1);
SELECT pg_temp.fail_if((SELECT (measured_total_hours, measured_business_hours, measured_total_days, measured_business_days)
                          FROM one_db WHERE tag_id = 'C1') IS DISTINCT FROM (41.94::numeric, 41.94::numeric, 2, 2), 'E2 measured_*');
SELECT pg_temp.fail_if((SELECT (total_transit_hours, business_transit_hours, total_transit_days, business_transit_days)
                          FROM one_db WHERE tag_id = 'C1') IS DISTINCT FROM (65.94::numeric(10,2), 65.94::numeric(10,2), 3, 3), 'E2 medido + equivalencia');
SELECT pg_temp.fail_if(EXISTS (SELECT 1 FROM one_db WHERE tag_id = 'C1' AND (
         business_transit_hours IS DISTINCT FROM measured_business_hours + 24 OR business_transit_days IS DISTINCT FROM measured_business_days + 1
      OR total_transit_hours IS DISTINCT FROM measured_total_hours + 24 OR total_transit_days IS DISTINCT FROM measured_total_days + 1)), 'E2 relacion medido+eq');
-- repetir el mismo UPDATE (y tocar received_at con el mismo valor) no acumula
UPDATE one_db SET equivalence_hours = 24, equivalence_days = 1 WHERE tag_id = 'C1';
UPDATE one_db SET equivalence_hours = 24, equivalence_days = 1 WHERE tag_id = 'C1';
UPDATE one_db SET received_at = received_at WHERE tag_id = 'C1';
SELECT pg_temp.fail_if((SELECT (business_transit_hours, business_transit_days, total_transit_hours, total_transit_days)
                          FROM one_db WHERE tag_id = 'C1') IS DISTINCT FROM (65.94::numeric(10,2), 3, 65.94::numeric(10,2), 3), 'E2 no acumula');
-- cambiar la equivalencia sustituye (no suma) y NULL = 0
UPDATE one_db SET equivalence_hours = 12, equivalence_days = 0 WHERE tag_id = 'C1';
SELECT pg_temp.fail_if((SELECT (business_transit_hours, business_transit_days) FROM one_db WHERE tag_id = 'C1')
                       IS DISTINCT FROM (53.94::numeric(10,2), 2), 'E2 eq 12/0');
UPDATE one_db SET equivalence_hours = NULL, equivalence_days = NULL WHERE tag_id = 'C1';
SELECT pg_temp.fail_if((SELECT (business_transit_hours, business_transit_days, measured_business_hours) FROM one_db WHERE tag_id = 'C1')
                       IS DISTINCT FROM (41.94::numeric(10,2), 2, 41.94::numeric), 'E2 eq NULL = medido');
ROLLBACK;

-- ===== E3: cl_equivalence: dias 0 + 1 => (24, 1); horas 6 + 6 => (12, 1); por defecto (0, 0)
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.fail_if((SELECT (eq_hours, eq_days) FROM public.cl_equivalence('d2000000-0000-0000-0000-000000000003'))
                       IS DISTINCT FROM (0::numeric, 0), 'E3 defecto (0,0)');
UPDATE public.delivery_standards SET cl_first_mile_time = 0, cl_last_mile_time = 1 WHERE id = 'd2000000-0000-0000-0000-000000000003';
SELECT pg_temp.fail_if((SELECT (eq_hours, eq_days) FROM public.cl_equivalence('d2000000-0000-0000-0000-000000000003'))
                       IS DISTINCT FROM (24::numeric, 1), 'E3 dias (24,1)');
UPDATE public.delivery_standards SET cl_first_mile_time = 6, cl_last_mile_time = 6 WHERE id = 'd1000000-0000-0000-0000-000000000003';
SELECT pg_temp.fail_if((SELECT (eq_hours, eq_days) FROM public.cl_equivalence('d1000000-0000-0000-0000-000000000003'))
                       IS DISTINCT FROM (12::numeric, 1), 'E3 horas (12,1)');
-- anon no puede ejecutarla
SELECT pg_temp.fail_if(has_function_privilege('anon', 'public.cl_equivalence(uuid)', 'EXECUTE'), 'E3 anon con EXECUTE');
ROLLBACK;

-- ===== E4: cambiar cl_last_mile_time del estandar actualiza la fila carrier de la ruta y su on_time pasa a false;
--          la fila panelist de la misma ruta no cambia; la fila carrier de otro producto tampoco.
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.row('C1', 'carrier',  'Economy delivery within 48hrs', '2026-10-27 13:44:18Z', '2026-10-29 07:40:57Z', 0, 0);
SELECT pg_temp.row('P1', 'panelist', 'Economy delivery within 48hrs', '2026-10-27 13:44:18Z', '2026-10-29 07:40:57Z', NULL, NULL);
SELECT pg_temp.row('C2', 'carrier',  'Prod dias',                     '2026-10-27 13:44:18Z', '2026-10-29 07:40:57Z', 0, 0);
-- dispara el recalculo de on_time (estandar 48 h) sin cambiar tiempos: 41.94 h => a tiempo
UPDATE public.delivery_standards SET standard_time = 48 WHERE id = 'd1000000-0000-0000-0000-000000000003';
SELECT pg_temp.fail_if((SELECT on_time_delivery FROM one_db WHERE tag_id = 'C1') IS DISTINCT FROM true, 'E4 C1 previo a tiempo');
SELECT pg_temp.fail_if((SELECT on_time_delivery FROM one_db WHERE tag_id = 'P1') IS DISTINCT FROM true, 'E4 P1 previo a tiempo');
-- ultimo tramo 12 h => equivalencia 12 h / 1 dia; 53.94 h > 48 => tarde
UPDATE public.delivery_standards SET cl_last_mile_time = 12 WHERE id = 'd1000000-0000-0000-0000-000000000003';
SELECT pg_temp.fail_if((SELECT (equivalence_hours, equivalence_days, business_transit_hours, measured_business_hours, on_time_delivery)
                          FROM one_db WHERE tag_id = 'C1')
                       IS DISTINCT FROM (12::numeric, 1, 53.94::numeric(10,2), 41.94::numeric, false), 'E4 C1 equivalente y tarde');
SELECT pg_temp.fail_if((SELECT (equivalence_hours, equivalence_days, business_transit_hours, business_transit_days, measured_business_hours, on_time_delivery)
                          FROM one_db WHERE tag_id = 'P1')
                       IS DISTINCT FROM (NULL::numeric, NULL::integer, 41.94::numeric(10,2), 2, NULL::numeric, true), 'E4 P1 sin cambios');
SELECT pg_temp.fail_if((SELECT (equivalence_hours, business_transit_hours) FROM one_db WHERE tag_id = 'C2')
                       IS DISTINCT FROM (0::numeric, 41.94::numeric(10,2)), 'E4 C2 otro producto sin cambios');
-- volver a 0 recupera el medido (no acumula) y vuelve a tiempo
UPDATE public.delivery_standards SET cl_last_mile_time = 0 WHERE id = 'd1000000-0000-0000-0000-000000000003';
SELECT pg_temp.fail_if((SELECT (business_transit_hours, business_transit_days, on_time_delivery) FROM one_db WHERE tag_id = 'C1')
                       IS DISTINCT FROM (41.94::numeric(10,2), 2, true), 'E4 C1 vuelta a 0');
ROLLBACK;
