-- Muestras por compensar (Task 4): la vista del plan incluye filas sinteticas 'deferred' del registro pendiente.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada,
                                            week_number, month, year, status, generation_source) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11',10,3,2027,'pending','plan');
-- Columnas de la fila real antes de la sintetica.
CREATE TEMP TABLE before_real AS
  SELECT id, status, week_number, origin_city_name, destination_city_name, origin_panelist_name, origin_availability_status
  FROM public.v_allocation_details_with_availability WHERE id = 'd1000000-0000-0000-0000-000000000001';

INSERT INTO public.deferred_samples (id, account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id,
                                     fecha_programada, reason, row_snapshot)
VALUES ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000002',
        'b1000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000004',
        '2027-03-10', 'origin_no_panelist', '{}'::jsonb);
DO $$
DECLARE r record; n int;
BEGIN
  SELECT count(*) INTO n FROM public.v_allocation_details_with_availability WHERE status = 'deferred';
  PERFORM pg_temp.fail_if(n <> 1, 'filas deferred esperadas 1, hay ' || n);
  SELECT * INTO r FROM public.v_allocation_details_with_availability WHERE status = 'deferred';
  PERFORM pg_temp.fail_if(r.id IS DISTINCT FROM 'd2000000-0000-0000-0000-000000000002'::uuid, 'id');
  PERFORM pg_temp.fail_if(r.plan_id IS DISTINCT FROM 'cc000000-0000-0000-0000-000000000001'::uuid, 'plan_id');
  PERFORM pg_temp.fail_if(r.account_id IS DISTINCT FROM 'a0000000-0000-0000-0000-000000000001'::uuid, 'account_id');
  PERFORM pg_temp.fail_if(r.origin_node_id IS DISTINCT FROM 'b1000000-0000-0000-0000-000000000001'::uuid
                          OR r.destination_node_id IS DISTINCT FROM 'b4000000-0000-0000-0000-000000000004'::uuid, 'nodos');
  PERFORM pg_temp.fail_if(r.fecha_programada IS DISTINCT FROM '2027-03-10'::date, 'fecha');
  PERFORM pg_temp.fail_if(r.week_number IS DISTINCT FROM 10 OR r.month IS DISTINCT FROM 3 OR r.year IS DISTINCT FROM 2027, 'semana/mes/anio');
  PERFORM pg_temp.fail_if(r.origin_city_name IS DISTINCT FROM 'City1', 'origin_city_name');
  PERFORM pg_temp.fail_if(r.destination_city_name IS DISTINCT FROM 'City2', 'destination_city_name');
  PERFORM pg_temp.fail_if(r.origin_panelist_name IS DISTINCT FROM 'Pan1', 'origin_panelist_name');
  -- La fila real no se duplica ni cambia.
  SELECT count(*) INTO n FROM public.v_allocation_details_with_availability WHERE id = 'd1000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.fail_if(n <> 1, 'fila real duplicada: ' || n);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM before_real b JOIN public.v_allocation_details_with_availability v USING (id)
     WHERE b.status IS NOT DISTINCT FROM v.status AND b.week_number IS NOT DISTINCT FROM v.week_number
       AND b.origin_city_name IS NOT DISTINCT FROM v.origin_city_name AND b.destination_city_name IS NOT DISTINCT FROM v.destination_city_name
       AND b.origin_panelist_name IS NOT DISTINCT FROM v.origin_panelist_name
       AND b.origin_availability_status IS NOT DISTINCT FROM v.origin_availability_status), 'fila real cambiada');
  -- Reintroducida => sin fila sintetica.
  UPDATE public.deferred_samples SET status = 'reintroduced' WHERE id = 'd2000000-0000-0000-0000-000000000002';
  SELECT count(*) INTO n FROM public.v_allocation_details_with_availability WHERE status = 'deferred';
  PERFORM pg_temp.fail_if(n <> 0, 'tras reintroducir sigue la sintetica');
END $$;
ROLLBACK;
