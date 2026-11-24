-- Pruebas diarias del agente: la incidencia GPS del panelista de prueba es esperada (20261123180200).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE r jsonb; n int; i_gps uuid; i_gps_old uuid; i_gps_p2 uuid; i_gps_acc2 uuid; i_dmg uuid; i_other uuid;
  A constant uuid := 'a0000000-0000-0000-0000-000000000001';
  A2 constant uuid := 'a0000000-0000-0000-0000-000000000002';
  P1 constant uuid := 'e1000000-0000-0000-0000-000000000001';
  P2 constant uuid := 'e2000000-0000-0000-0000-000000000002';
  Q constant uuid := 'e9000000-0000-0000-0000-000000000009';
BEGIN
  -- config del agente apuntando a la fixture (P1 = panelista de prueba)
  UPDATE public.panelists SET telegram_id = '1001' WHERE id = P1;
  DELETE FROM ops_test.config;
  INSERT INTO ops_test.config VALUES (1, A, P1, '1001', P2, '73915086', '73915087', DATE '2020-01-06', 'OPS', 3);
  DELETE FROM ops_test.secret;
  INSERT INTO ops_test.secret VALUES (encode(extensions.digest('tok', 'sha256'), 'hex'));
  UPDATE ops_test.state SET prepared_at = now() - interval '10 minutes', plan_id = NULL WHERE id = 1;
  INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, status, language)
  VALUES (Q, A2, 'Q1', 'Otro', 'q@t.l', '9', 'active', 'en');

  -- incidencias
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status, description, payload, created_via)
  VALUES (A, P1, 'gps_location', 'open', 'gps', '{"details":[]}', 'telegram') RETURNING id INTO i_gps;
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status, description, payload, created_via, created_at)
  VALUES (A, P1, 'gps_location', 'open', 'gps vieja', '{"details":[]}', 'telegram', now() - interval '2 days')
  RETURNING id INTO i_gps_old;
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status, description, payload, created_via)
  VALUES (A, P2, 'gps_location', 'open', 'gps otro panelista', '{"details":[]}', 'telegram') RETURNING id INTO i_gps_p2;
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status, description, payload, created_via)
  VALUES (A2, Q, 'gps_location', 'open', 'gps otra cuenta', '{"details":[]}', 'telegram') RETURNING id INTO i_gps_acc2;
  INSERT INTO public.incident_message (account_id, panelist_id, incident_kind, incident_id, direction, author, body, status)
  VALUES (A, P1, 'reported', i_gps, 'internal', 'system', 'hola', 'sent');

  -- gps_esperada
  PERFORM pg_temp.fail_if(NOT i_gps IN (SELECT ops_test._expected_incidents()), 'GPS del panelista de prueba esperada');
  PERFORM pg_temp.fail_if(i_gps_old IN (SELECT ops_test._expected_incidents()), 'GPS anterior a la preparacion no');
  PERFORM pg_temp.fail_if(i_gps_p2 IN (SELECT ops_test._expected_incidents()), 'GPS de otro panelista no');
  PERFORM pg_temp.fail_if(i_gps_acc2 IN (SELECT ops_test._expected_incidents()), 'GPS de otra cuenta no');
  r := public.ops_test_status('tok');
  -- solo la de P2 cuenta como no esperada (es de la cuenta de prueba y posterior a la preparacion)
  PERFORM pg_temp.fail_if(NOT (r->'unexpected') @> '["1 incidencias no esperadas (panelist_incident)"]'::jsonb,
                          'solo 1 no esperada (P2): ' || r::text);
  -- la GPS sola NO cuenta como "se creo la incidencia de paquete danado"
  PERFORM pg_temp.fail_if((r->>'incident')::boolean IS NOT FALSE, 'incident=false sin parcel_damaged: ' || r::text);

  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status, description, created_via)
  VALUES (A, P1, 'parcel_damaged', 'open', 'dmg', 'telegram') RETURNING id INTO i_dmg;
  r := public.ops_test_status('tok');
  PERFORM pg_temp.fail_if((r->>'incident')::boolean IS NOT TRUE, 'incident=true con parcel_damaged: ' || r::text);
  -- otra categoria del panelista de prueba sigue siendo inesperada
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status, description, created_via)
  VALUES (A, P1, 'other', 'open', 'otra', 'telegram') RETURNING id INTO i_other;
  PERFORM pg_temp.fail_if(i_other IN (SELECT ops_test._expected_incidents()), 'otra categoria no esperada');

  -- reset_la_borra
  DELETE FROM public.panelist_incident WHERE id IN (i_gps_p2, i_other);
  r := ops_test._reset();
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_incident WHERE id IN (i_gps, i_dmg)), 'reset borra GPS y dmg');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.incident_message WHERE incident_id = i_gps), 'reset borra mensajes');
  -- otra_cuenta_intacta / anterior intacta
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.panelist_incident WHERE id = i_gps_acc2), 'otra cuenta intacta');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.panelist_incident WHERE id = i_gps_old), 'anterior intacta');
END $$;
ROLLBACK;
