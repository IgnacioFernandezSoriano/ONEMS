-- Muestras por compensar (Task 1): registro deferred_samples, generation_source 'compensation' y resumen por ciudad y plan.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;

-- ===== (a) y (b): resumen con actor de la cuenta 1.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
INSERT INTO public.deferred_samples (account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id,
                                     fecha_programada, reason, row_snapshot)
VALUES ('a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000002',
        'b1000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000004',
        '2027-03-10', 'origin_no_panelist', '{}'::jsonb);
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DO $$
DECLARE r jsonb; p jsonb;
BEGIN
  r := public.rpc_deferred_samples_summary('a0000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.fail_if((r->>'pending_total')::int IS DISTINCT FROM 1, 'pending_total: ' || r::text);
  PERFORM pg_temp.fail_if(r->'by_city'->0->>'city_name' IS DISTINCT FROM 'City1', 'city_name: ' || r::text);
  PERFORM pg_temp.fail_if((r->'by_city'->0->>'count')::int IS DISTINCT FROM 1, 'city count');
  PERFORM pg_temp.fail_if(r->'by_city'->0->'waiting_reason' IS DISTINCT FROM 'null'::jsonb, 'waiting_reason NULL: ' || r::text);
  p := r->'by_plan'->0;
  PERFORM pg_temp.fail_if((p->>'total_samples')::int IS DISTINCT FROM 10 OR (p->>'deferred')::int IS DISTINCT FROM 1
                          OR (p->>'scheduled')::int IS DISTINCT FROM 0 OR (p->>'done')::int IS DISTINCT FROM 0
                          OR (p->>'pobox_extra')::int IS DISTINCT FROM 0, 'by_plan (a): ' || p::text);

  -- (b) 2 pendientes + 1 pobox (pendiente) + 1 enviada.
  INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada,
                                              week_number, month, year, status, generation_source) VALUES
    ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11',10,3,2027,'pending','plan'),
    ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-12',10,3,2027,'pending','plan'),
    ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-12',10,3,2027,'pending','pobox'),
    ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-09',10,3,2027,'sent','plan');
  p := public.rpc_deferred_samples_summary('a0000000-0000-0000-0000-000000000001')->'by_plan'->0;
  PERFORM pg_temp.fail_if((p->>'scheduled')::int IS DISTINCT FROM 3 OR (p->>'pobox_extra')::int IS DISTINCT FROM 1
                          OR (p->>'done')::int IS DISTINCT FROM 1 OR (p->>'deferred')::int IS DISTINCT FROM 1, 'by_plan (b): ' || p::text);

  -- waiting_reason mas frecuente por ciudad.
  UPDATE public.deferred_samples SET waiting_reason = 'no_capacity' WHERE plan_id = 'cc000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.fail_if(public.rpc_deferred_samples_summary('a0000000-0000-0000-0000-000000000001')->'by_city'->0->>'waiting_reason'
                          IS DISTINCT FROM 'no_capacity', 'waiting_reason frecuente');
END $$;
ROLLBACK;

-- ===== (c) actor de la cuenta 2 => 42501.
BEGIN;
\ir fixtures/incident_city.sql
SELECT set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
DO $$
BEGIN
  BEGIN
    PERFORM public.rpc_deferred_samples_summary('a0000000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'FAIL cuenta ajena acepto el resumen';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
ROLLBACK;

-- ===== (d) generation_source 'compensation' aceptado en ambas tablas; otro valor rechazado.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada,
                                            week_number, month, year, generation_source)
VALUES ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11',10,3,2027,'compensation');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada,
                                                week_number, month, year, generation_source)
    VALUES ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11',10,3,2027,'otro');
    RAISE EXCEPTION 'FAIL generation_source invalido aceptado';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
SELECT pg_temp.fail_if((SELECT pg_get_constraintdef(oid) NOT LIKE '%compensation%' FROM pg_constraint
                         WHERE conname = 'generated_allocation_plan_details_generation_source_check'), 'CHECK generated_*');
ROLLBACK;

-- ===== Permisos.
SELECT pg_temp.fail_if(has_function_privilege('anon', 'public.rpc_deferred_samples_summary(uuid)', 'EXECUTE'), 'anon summary');
SELECT pg_temp.fail_if(NOT has_function_privilege('authenticated', 'public.rpc_deferred_samples_summary(uuid)', 'EXECUTE'), 'authenticated summary');
