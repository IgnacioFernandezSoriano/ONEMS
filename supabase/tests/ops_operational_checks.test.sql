-- Avisos de operativa del agente (ops_test_checks): nodo POBOX sin envio el proximo dia laborable y ciudad con
-- cartas enviadas hace dias sin ninguna recibida. Solo lectura; protegida con el token del agente.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO ops_test.secret(token_sha256) VALUES (encode(extensions.digest('t0ken-de-prueba','sha256'),'hex'));
-- City2 (solo N4) es POBOX; City1 (N1-N3) no.
UPDATE public.cities SET pobox_enabled = true WHERE id = 'c2000000-0000-0000-0000-000000000002';

-- proximo dia laborable de la cuenta (desde hoy)
CREATE TEMP TABLE _d AS
  SELECT (SELECT g::date FROM generate_series(current_date + 1, current_date + 14, interval '1 day') g
           WHERE public.is_account_working_day('a0000000-0000-0000-0000-000000000001', g::date) ORDER BY g LIMIT 1) AS d;

-- Ciudad City2 destino: 3 cartas enviadas hace 6 dias desde N1, ninguna recibida -> aviso
INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id, sent_at)
SELECT 'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001',
       'b4000000-0000-0000-0000-000000000004', current_date - 6, 'sent', lpad(i::text, 8, '1'), now() - interval '6 days'
  FROM generate_series(1, 3) i;
-- City1 destino: 3 enviadas hace 6 dias pero una recibida ayer -> sin aviso
INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id, sent_at, received_at)
SELECT 'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004',
       'b1000000-0000-0000-0000-000000000001', current_date - 6, CASE WHEN i = 1 THEN 'received' ELSE 'sent' END,
       lpad(i::text, 8, '2'), now() - interval '6 days', CASE WHEN i = 1 THEN now() - interval '1 day' END
  FROM generate_series(1, 3) i;

DO $$
DECLARE r jsonb; v_err text;
BEGIN
  BEGIN
    PERFORM public.ops_test_checks('malo');
    RAISE EXCEPTION 'FAIL: token malo aceptado';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', 'mensaje token: ' || v_err);
  END;

  r := public.ops_test_checks('t0ken-de-prueba');
  -- N4 (City2, POBOX, nodo unico) no tiene envio el proximo dia laborable
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'pobox_no_send') <> 1
                          OR r->'pobox_no_send'->0->>'city' <> 'City2' OR r->'pobox_no_send'->0->>'node' <> 'N4'
                          OR r->'pobox_no_send'->0->>'account' <> 'Acc'
                          OR r->'pobox_no_send'->0->>'day' <> (SELECT d FROM _d)::text, 'pobox_no_send: ' || r::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'no_receipts') <> 1
                          OR r->'no_receipts'->0->>'city' <> 'City2' OR (r->'no_receipts'->0->>'waiting')::int <> 3,
                          'no_receipts: ' || r::text);

  -- con envio programado ese dia, N4 deja de salir
  INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004',
          'b1000000-0000-0000-0000-000000000001', (SELECT d FROM _d), 'pending');
  r := public.ops_test_checks('t0ken-de-prueba');
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'pobox_no_send') <> 0, 'con envio no debe avisar: ' || r::text);
END $$;
ROLLBACK;

DO $$
BEGIN
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_test_checks(text)', 'EXECUTE'), 'anon debe poder llamar');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_test_checks(text)', 'EXECUTE'), 'authenticated no');
END $$;
SELECT 'ops_operational_checks OK';
