-- Deshacer en Allocation Plans: diario por cuenta (20261118150000_plan_undo.sql).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

-- Tres envíos pendientes de la cuenta 1 (D1, D2: N1->N4; D3: N2->N4) y el actor 99 (cuenta 1).
CREATE OR REPLACE FUNCTION pg_temp.seed() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id,
      fecha_programada, status) VALUES
    ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10','pending'),
    ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11','pending'),
    ('d3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b2000000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-000000000004','2027-03-12','pending');
  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000099', true);
END $$;

-- ===== 1) update en bloque de 2 filas y deshacer =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$ BEGIN PERFORM pg_temp.seed(); END $$;
DO $$
DECLARE r jsonb; n int; e record;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  D1 constant uuid := 'd1000000-0000-0000-0000-000000000001';
  D2 constant uuid := 'd2000000-0000-0000-0000-000000000002';
  N3 constant uuid := 'b3000000-0000-0000-0000-000000000003';
  N4 constant uuid := 'b4000000-0000-0000-0000-000000000004';
BEGIN
  n := public.plan_action_update(ARRAY[D1, D2], jsonb_build_object('destination_node_id', N3), 'update');
  PERFORM pg_temp.fail_if(n <> 2, 'update devuelve 2: ' || n);
  SELECT count(*) INTO n FROM public.allocation_plan_details WHERE id IN (D1, D2) AND destination_node_id = N3;
  PERFORM pg_temp.fail_if(n <> 2, 'destino cambiado: ' || n);

  SELECT * INTO e FROM public.plan_undo_log WHERE account_id = A1;
  PERFORM pg_temp.fail_if(e.action <> 'update' OR e.n_rows <> 2 OR e.user_name <> 'Actor'
                          OR e.user_id <> '99000000-0000-0000-0000-000000000099'
                          OR jsonb_array_length(e.before_details) <> 2 OR jsonb_array_length(e.after_details) <> 2,
                          'entrada del diario: ' || row_to_json(e)::text);

  r := public.plan_undo_last(A1);
  PERFORM pg_temp.fail_if(r->>'action' <> 'update' OR (r->>'restored')::int <> 2 OR (r->>'skipped')::int <> 0
                          OR jsonb_array_length(r->'skipped_ids') <> 0, 'resultado: ' || r::text);
  SELECT count(*) INTO n FROM public.allocation_plan_details WHERE id IN (D1, D2) AND destination_node_id = N4;
  PERFORM pg_temp.fail_if(n <> 2, 'destino original restaurado: ' || n);
  SELECT count(*) INTO n FROM public.plan_undo_log WHERE account_id = A1;
  PERFORM pg_temp.fail_if(n <> 0, 'pila vacia: ' || n);
END $$;
ROLLBACK;

-- ===== 2) borrado de 2 envíos + 1 muestra por compensar y deshacer =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$ BEGIN PERFORM pg_temp.seed(); END $$;
DO $$
DECLARE r jsonb; n int; v_before_d jsonb; v_before_f jsonb; v_after_d jsonb; v_after_f jsonb;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  D1 constant uuid := 'd1000000-0000-0000-0000-000000000001';
  D2 constant uuid := 'd2000000-0000-0000-0000-000000000002';
  F1 constant uuid := 'f1000000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO public.deferred_samples (id, account_id, plan_id, origin_city_id, dest_city_id, origin_node_id,
      destination_node_id, fecha_programada, reason, row_snapshot, status, waiting_reason) VALUES
    (F1, A1, 'cc000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
     'c2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001',
     'b4000000-0000-0000-0000-000000000004', '2027-03-15', 'dest_no_panelist', '{"x":1}', 'pending', 'no_dest_panelist');
  SELECT jsonb_agg(to_jsonb(d) ORDER BY d.id) INTO v_before_d FROM public.allocation_plan_details d WHERE d.id IN (D1, D2);
  SELECT jsonb_agg(to_jsonb(f)) INTO v_before_f FROM public.deferred_samples f WHERE f.id = F1;

  r := public.plan_action_delete(ARRAY[D1, D2], ARRAY[F1]);
  PERFORM pg_temp.fail_if((r->>'details')::int <> 2 OR (r->>'deferred')::int <> 1, 'delete: ' || r::text);
  SELECT count(*) INTO n FROM public.allocation_plan_details WHERE id IN (D1, D2);
  PERFORM pg_temp.fail_if(n <> 0, 'envios borrados: ' || n);
  SELECT count(*) INTO n FROM public.deferred_samples WHERE id = F1;
  PERFORM pg_temp.fail_if(n <> 0, 'muestra borrada: ' || n);
  PERFORM pg_temp.fail_if((SELECT n_rows FROM public.plan_undo_log WHERE account_id = A1) <> 3, 'n_rows = 3');

  r := public.plan_undo_last(A1);
  PERFORM pg_temp.fail_if(r->>'action' <> 'delete' OR (r->>'restored')::int <> 3 OR (r->>'skipped')::int <> 0,
                          'deshacer delete: ' || r::text);
  SELECT jsonb_agg(to_jsonb(d) ORDER BY d.id) INTO v_after_d FROM public.allocation_plan_details d WHERE d.id IN (D1, D2);
  SELECT jsonb_agg(to_jsonb(f)) INTO v_after_f FROM public.deferred_samples f WHERE f.id = F1;
  PERFORM pg_temp.fail_if(v_after_d IS DISTINCT FROM v_before_d, 'envios identicos: ' || coalesce(v_after_d::text, 'NULL'));
  PERFORM pg_temp.fail_if(v_after_f IS DISTINCT FROM v_before_f, 'muestra identica: ' || coalesce(v_after_f::text, 'NULL'));
END $$;
ROLLBACK;

-- ===== 2b) deshacer un borrado cuando ya existe una fila con el mismo id => se salta =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$ BEGIN PERFORM pg_temp.seed(); END $$;
DO $$
DECLARE r jsonb;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  D1 constant uuid := 'd1000000-0000-0000-0000-000000000001';
  D2 constant uuid := 'd2000000-0000-0000-0000-000000000002';
BEGIN
  r := public.plan_action_delete(ARRAY[D1, D2], ARRAY[]::uuid[]);
  -- el balanceo vuelve a crear D1 con otro destino
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id,
      fecha_programada, status) VALUES
    (D1,'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b1000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000003','2027-03-20','pending');
  r := public.plan_undo_last(A1);
  PERFORM pg_temp.fail_if((r->>'restored')::int <> 1 OR (r->>'skipped')::int <> 1
                          OR NOT (r->'skipped_ids') @> to_jsonb(ARRAY[D1]), 'salta D1: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT fecha_programada FROM public.allocation_plan_details WHERE id = D1) <> '2027-03-20',
                          'D1 nueva intacta');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE id = D2), 'D2 restaurada');
END $$;
ROLLBACK;

-- ===== 2c) deshacer un borrado cuando el plan de una muestra ya no existe => esa se salta, el resto vuelve =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$ BEGIN PERFORM pg_temp.seed(); END $$;
DO $$
DECLARE r jsonb;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  D1 constant uuid := 'd1000000-0000-0000-0000-000000000001';
  F3 constant uuid := 'f3000000-0000-0000-0000-000000000003';
BEGIN
  INSERT INTO public.deferred_samples (id, account_id, plan_id, origin_city_id, dest_city_id, origin_node_id,
      destination_node_id, fecha_programada, reason, row_snapshot) VALUES
    (F3, A1, 'cc000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001',
     'c2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001',
     'b4000000-0000-0000-0000-000000000004', '2027-04-15', 'dest_no_panelist', '{}');
  r := public.plan_action_delete(ARRAY[D1], ARRAY[F3]);
  DELETE FROM public.allocation_plans WHERE id = 'cc000000-0000-0000-0000-000000000002';
  r := public.plan_undo_last(A1);
  PERFORM pg_temp.fail_if((r->>'restored')::int <> 1 OR (r->>'skipped')::int <> 1
                          OR NOT (r->'skipped_ids') @> to_jsonb(ARRAY[F3]), 'salta F3: ' || r::text);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE id = D1), 'D1 restaurada');
END $$;
ROLLBACK;

-- ===== 3) edit y despues el bot marca enviada => la fila se salta =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$ BEGIN PERFORM pg_temp.seed(); END $$;
DO $$
DECLARE r jsonb; n int;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  D1 constant uuid := 'd1000000-0000-0000-0000-000000000001';
BEGIN
  n := public.plan_action_update(ARRAY[D1], '{"fecha_programada":"2027-03-20","tag_id":"12345678"}', 'edit');
  PERFORM pg_temp.fail_if(n <> 1, 'edit devuelve 1: ' || n);
  UPDATE public.allocation_plan_details SET status = 'sent', sent_at = now() WHERE id = D1;
  r := public.plan_undo_last(A1);
  PERFORM pg_temp.fail_if(r->>'action' <> 'edit' OR (r->>'restored')::int <> 0 OR (r->>'skipped')::int <> 1
                          OR NOT (r->'skipped_ids') @> to_jsonb(ARRAY[D1]), 'skipped: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = D1) <> 'sent', 'sigue sent');
  PERFORM pg_temp.fail_if((SELECT fecha_programada FROM public.allocation_plan_details WHERE id = D1) <> '2027-03-20',
                          'fecha editada intacta');
  SELECT count(*) INTO n FROM public.plan_undo_log WHERE account_id = A1;
  PERFORM pg_temp.fail_if(n <> 0, 'la entrada se quita igualmente: ' || n);
END $$;
ROLLBACK;

-- ===== 4) 6 acciones => quedan 5; se deshacen de la 6a a la 2a; la 7a pulsacion devuelve NULL =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$ BEGIN PERFORM pg_temp.seed(); END $$;
DO $$
DECLARE r jsonb; n int; i int;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  D1 constant uuid := 'd1000000-0000-0000-0000-000000000001';
BEGIN
  FOR i IN 1..6 LOOP
    PERFORM public.plan_action_update(ARRAY[D1],
      jsonb_build_object('fecha_programada', make_date(2027, 3, 10 + i)), 'edit');
  END LOOP;
  SELECT count(*) INTO n FROM public.plan_undo_log WHERE account_id = A1;
  PERFORM pg_temp.fail_if(n <> 5, '5 entradas: ' || n);

  FOR i IN REVERSE 6..2 LOOP
    r := public.plan_undo_last(A1);
    PERFORM pg_temp.fail_if(r IS NULL OR (r->>'restored')::int <> 1, 'deshacer accion ' || i || ': ' || coalesce(r::text, 'NULL'));
    -- tras deshacer la accion i, la fecha es la que dejo la accion i-1
    PERFORM pg_temp.fail_if((SELECT fecha_programada FROM public.allocation_plan_details WHERE id = D1)
                            <> make_date(2027, 3, 10 + i - 1), 'orden al deshacer ' || i);
  END LOOP;
  r := public.plan_undo_last(A1);
  PERFORM pg_temp.fail_if(r IS NOT NULL, 'pila vacia => NULL: ' || coalesce(r::text, 'NULL'));
  PERFORM pg_temp.fail_if((SELECT fecha_programada FROM public.allocation_plan_details WHERE id = D1) <> '2027-03-11',
                          'la 1a accion ya no se puede deshacer');
END $$;
ROLLBACK;

-- ===== 5) create y deshacer =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$ BEGIN PERFORM pg_temp.seed(); END $$;
DO $$
DECLARE r jsonb; v_id uuid;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
BEGIN
  v_id := public.plan_action_create(jsonb_build_object(
    'account_id', A1, 'plan_id', 'cc000000-0000-0000-0000-000000000001',
    'origin_node_id', 'b1000000-0000-0000-0000-000000000001',
    'destination_node_id', 'b4000000-0000-0000-0000-000000000004', 'fecha_programada', '2027-03-22'));
  PERFORM pg_temp.fail_if(v_id IS NULL, 'id devuelto');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v_id) <> 'pending',
                          'defaults aplicados');
  r := public.plan_undo_last(A1);
  PERFORM pg_temp.fail_if(r->>'action' <> 'create' OR (r->>'restored')::int <> 1, 'deshacer create: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE id = v_id), 'fila borrada');
END $$;
ROLLBACK;

-- ===== 6) otra cuenta no puede tocar ni deshacer =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$ BEGIN PERFORM pg_temp.seed(); END $$;
DO $$
DECLARE ok boolean; n int;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  D1 constant uuid := 'd1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.plan_action_update(ARRAY[D1], '{"fecha_programada":"2027-03-25"}', 'edit');
  PERFORM set_config('request.jwt.claim.sub', '98000000-0000-0000-0000-000000000098', true);

  ok := false;
  BEGIN PERFORM public.plan_action_update(ARRAY[D1], '{"fecha_programada":"2027-03-26"}', 'edit');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.fail_if(NOT ok, 'update de otra cuenta');
  ok := false;
  BEGIN PERFORM public.plan_action_delete(ARRAY[D1], ARRAY[]::uuid[]);
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.fail_if(NOT ok, 'delete de otra cuenta');
  ok := false;
  BEGIN PERFORM public.plan_undo_last(A1);
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.fail_if(NOT ok, 'deshacer de otra cuenta');
  ok := false;
  BEGIN PERFORM public.plan_action_create(jsonb_build_object(
    'account_id', A1, 'plan_id', 'cc000000-0000-0000-0000-000000000001',
    'origin_node_id', 'b1000000-0000-0000-0000-000000000001',
    'destination_node_id', 'b4000000-0000-0000-0000-000000000004', 'fecha_programada', '2027-03-22'));
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.fail_if(NOT ok, 'create en otra cuenta');

  PERFORM pg_temp.fail_if((SELECT fecha_programada FROM public.allocation_plan_details WHERE id = D1) <> '2027-03-25',
                          'D1 intacta');
  SELECT count(*) INTO n FROM public.plan_undo_log WHERE account_id = A1;
  PERFORM pg_temp.fail_if(n <> 1, 'pila intacta: ' || n);
END $$;
ROLLBACK;

-- ===== 7) parches no permitidos y llamadas vacias =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$ BEGIN PERFORM pg_temp.seed(); END $$;
DO $$
DECLARE ok boolean; n int; r jsonb; v_patch jsonb;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  D1 constant uuid := 'd1000000-0000-0000-0000-000000000001';
BEGIN
  FOREACH v_patch IN ARRAY ARRAY['{"status":"sent"}'::jsonb, '{"status":"received"}', '{"foo":1}', '{"id":"d2000000-0000-0000-0000-000000000002"}',
                                 '{"account_id":"a0000000-0000-0000-0000-000000000002"}'] LOOP
    ok := false;
    BEGIN PERFORM public.plan_action_update(ARRAY[D1], v_patch, 'edit');
    EXCEPTION WHEN OTHERS THEN ok := true; END;
    PERFORM pg_temp.fail_if(NOT ok, 'parche rechazado: ' || v_patch::text);
  END LOOP;
  ok := false;
  BEGIN PERFORM public.plan_action_update(ARRAY[D1], '{"fecha_programada":"2027-03-25"}', 'delete');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.fail_if(NOT ok, 'p_action invalido');

  -- cancelar si se permite
  n := public.plan_action_update(ARRAY[D1], '{"status":"cancelled"}', 'cancel');
  PERFORM pg_temp.fail_if(n <> 1, 'cancel: ' || n);

  -- llamadas vacias: 0 y sin entrada nueva
  PERFORM pg_temp.fail_if(public.plan_action_update(ARRAY[]::uuid[], '{"fecha_programada":"2027-03-25"}', 'update') <> 0,
                          'update vacio');
  r := public.plan_action_delete(ARRAY[]::uuid[], ARRAY[]::uuid[]);
  PERFORM pg_temp.fail_if(r <> '{"details":0,"deferred":0}'::jsonb, 'delete vacio: ' || r::text);
  SELECT count(*) INTO n FROM public.plan_undo_log WHERE account_id = A1;
  PERFORM pg_temp.fail_if(n <> 1, 'solo la entrada del cancel: ' || n);
END $$;
ROLLBACK;

-- ===== 8) las muestras ya reintroducidas no se borran =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$ BEGIN PERFORM pg_temp.seed(); END $$;
DO $$
DECLARE r jsonb; n int;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  F2 constant uuid := 'f2000000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO public.deferred_samples (id, account_id, plan_id, origin_city_id, dest_city_id, origin_node_id,
      destination_node_id, fecha_programada, reason, row_snapshot, status, reintroduced_at) VALUES
    (F2, A1, 'cc000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
     'c2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001',
     'b4000000-0000-0000-0000-000000000004', '2027-03-15', 'dest_no_panelist', '{}', 'reintroduced', now());
  r := public.plan_action_delete(ARRAY[]::uuid[], ARRAY[F2]);
  PERFORM pg_temp.fail_if((r->>'deferred')::int <> 0, 'reintroduced no se borra: ' || r::text);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.deferred_samples WHERE id = F2), 'F2 sigue');
  SELECT count(*) INTO n FROM public.plan_undo_log WHERE account_id = A1;
  PERFORM pg_temp.fail_if(n <> 0, 'sin entrada si no borra nada: ' || n);
END $$;
ROLLBACK;

-- ===== 9) Permisos y RLS =====
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.plan_action_update(uuid[],jsonb,text)', 'public.plan_action_delete(uuid[],uuid[])',
                           'public.plan_action_create(jsonb)', 'public.plan_undo_last(uuid)'] LOOP
    PERFORM pg_temp.fail_if(NOT has_function_privilege('authenticated', f, 'EXECUTE'), 'authenticated EXECUTE ' || f);
    PERFORM pg_temp.fail_if(has_function_privilege('anon', f, 'EXECUTE'), 'anon sin EXECUTE ' || f);
  END LOOP;
  PERFORM pg_temp.fail_if(NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.plan_undo_log'::regclass), 'RLS activada');
  PERFORM pg_temp.fail_if(NOT has_table_privilege('authenticated', 'public.plan_undo_log', 'SELECT'), 'authenticated SELECT');
  PERFORM pg_temp.fail_if(has_table_privilege('authenticated', 'public.plan_undo_log', 'INSERT')
                          OR has_table_privilege('authenticated', 'public.plan_undo_log', 'UPDATE')
                          OR has_table_privilege('authenticated', 'public.plan_undo_log', 'DELETE'), 'authenticated sin escritura');
  PERFORM pg_temp.fail_if(has_table_privilege('anon', 'public.plan_undo_log', 'SELECT'), 'anon sin SELECT');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM pg_policies WHERE tablename = 'plan_undo_log') <> 1, 'una sola politica');
  PERFORM pg_temp.fail_if(to_regprocedure('public.delete_deferred_samples(uuid[])') IS NOT NULL, 'delete_deferred_samples no existe');
END $$;
