-- ops_case._find: el panelista se encuentra tambien por su codigo completo (20261111100000), sin saltarse la cuenta.
\set ON_ERROR_STOP on
SET client_min_messages = error;
CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
UPDATE public.panelists SET name = 'Arbe Tester', panelist_code = 'PAN-ACC-001' WHERE panelist_code = 'P1';

DO $$
DECLARE r jsonb;
BEGIN
  -- codigo completo, sin distinguir mayusculas
  r := ops_case._find('pan-acc-001', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> 'PAN-ACC-001' OR NOT (r->0->>'by_name')::boolean, 'codigo: ' || r::text);
  -- codigo dentro de una frase
  r := ops_case._find('es el PAN-ACC-001 de Arbe', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> 'PAN-ACC-001', 'codigo en frase: ' || r::text);
  -- con la cuenta correcta, si; con otra cuenta, no
  r := ops_case._find('PAN-ACC-001', NULL, 'a0000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1, 'codigo cuenta propia: ' || r::text);
  r := ops_case._find('PAN-ACC-001', NULL, 'a0000000-0000-0000-0000-000000000002');
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 0, 'codigo de otra cuenta visible: ' || r::text);
  -- un trozo del codigo no basta
  r := ops_case._find('PAN-ACC', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 0, 'trozo de codigo: ' || r::text);
  -- el nombre sigue funcionando
  r := ops_case._find('arbe tester', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> 'PAN-ACC-001', 'nombre: ' || r::text);
END $$;
ROLLBACK;
