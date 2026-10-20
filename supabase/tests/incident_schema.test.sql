-- Esquema de incidencias de indisponibilidad + cola panelist_notification.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/incident_city.sql

INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002','2027-03-10',10,3,2027,'pending');
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status) VALUES
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','2027-03-10','2027-03-12','vacation','active');

DO $$
DECLARE v_status text; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='panelist_unavailability'
     AND column_name IN ('incident_status','auto_summary','final_resolution','resolved_at');
  IF v_n <> 4 THEN RAISE EXCEPTION 'FAIL columnas panelist_unavailability (% de 4)', v_n; END IF;
  SELECT incident_status INTO v_status FROM panelist_unavailability WHERE id='b0000000-0000-0000-0000-000000000001';
  IF v_status IS DISTINCT FROM 'new' THEN RAISE EXCEPTION 'FAIL default incident_status (%)', v_status; END IF;
  RAISE NOTICE 'PASS columnas + default new';
END $$;

DO $$
BEGIN
  BEGIN
    UPDATE panelist_unavailability SET incident_status='bogus' WHERE id='b0000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL incident_status invalido aceptado';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS incident_status check'; END;
END $$;

DO $$
BEGIN
  INSERT INTO panelist_reassignment_proposal
    (id, account_id, unavailability_id, allocation_plan_detail_id, affected_role, sample_status_at_detection, suggested_action, status)
  VALUES ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','origin','pending','reroute','auto_resolved');
  BEGIN
    UPDATE panelist_reassignment_proposal SET status='confirmed' WHERE id='f1000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL status confirmed aceptado';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS status auto_resolved ok, confirmed rechazado'; END;
  UPDATE panelist_reassignment_proposal SET final_action='none', resolution_note='x', applied_at=now()
   WHERE id='f1000000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS final_action none + columnas nuevas';
END $$;

DO $$
BEGIN
  PERFORM original_fecha_programada FROM allocation_plan_details LIMIT 1;
  RAISE NOTICE 'PASS original_fecha_programada';
END $$;

DO $$
BEGIN
  INSERT INTO panelist_notification (account_id, panelist_id, kind)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','plan_change_this_week');
  BEGIN
    INSERT INTO panelist_notification (account_id, panelist_id, kind)
    VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','x');
    RAISE EXCEPTION 'FAIL kind x aceptado';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS kind check'; END;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.panelist_notification'::regclass) THEN
    RAISE EXCEPTION 'FAIL RLS desactivado'; END IF;
  IF has_table_privilege('anon','public.panelist_notification','SELECT') THEN
    RAISE EXCEPTION 'FAIL anon puede SELECT'; END IF;
  RAISE NOTICE 'PASS panelist_notification RLS + anon sin acceso';
END $$;

ROLLBACK;
