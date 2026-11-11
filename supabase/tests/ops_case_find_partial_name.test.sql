-- ops_case._find: coincidencia parcial de nombre (20261111110000).
\set ON_ERROR_STOP on
SET client_min_messages = error;
CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
UPDATE public.panelists SET name = 'Samwel' WHERE panelist_code = 'P1';
UPDATE public.panelists SET name = 'Samwel Otieno Kip' WHERE panelist_code = 'P2';

DO $$
DECLARE r jsonb;
BEGIN
  -- completa gana: «Samwel Otieno» solo da P2 (by_name), no la parcial P1
  r := ops_case._find('Samwel Otieno', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> 'P2' OR NOT (r->0->>'by_name')::boolean, 'completa: ' || r::text);
  -- sin completa: «Samwel Mettet» da las dos parciales, by_name false, partial true
  r := ops_case._find('Samwel Mettet', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 2, 'parcial dos: ' || r::text);
  PERFORM pg_temp.fail_if((r->0->>'by_name')::boolean OR NOT (r->0->>'partial')::boolean, 'parcial marcada: ' || r::text);
  -- palabras cortas o numeros no dan parcial
  r := ops_case._find('de la 1234', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 0, 'cortas: ' || r::text);
  -- la cuenta sigue mandando
  r := ops_case._find('Samwel Mettet', NULL, 'a0000000-0000-0000-0000-000000000002');
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 0, 'otra cuenta: ' || r::text);
  -- el codigo sigue funcionando
  r := ops_case._find('p2', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> 'P2', 'codigo: ' || r::text);
END $$;
ROLLBACK;
