-- ops_case._find: codigo con cualquier formato y Telegram del panelista (20261117100000), sin saltarse la cuenta.
\set ON_ERROR_STOP on
SET client_min_messages = error;
CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;
CREATE OR REPLACE FUNCTION pg_temp.one(p_q text, p_code text, p_acc uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r jsonb := ops_case._find(p_q, NULL, p_acc);
BEGIN
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> p_code
                          OR NOT (r->0->>'by_id')::boolean OR NOT (r->0->>'by_name')::boolean,
                          format('%s -> %s', p_q, r));
END $$;

BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
UPDATE public.panelists SET name = 'José Kyalo', panelist_code = 'PAN-KEN-047', telegram_id = '8525727045'
 WHERE panelist_code = 'P1';
UPDATE public.panelists SET name = 'Cheikh Seck', panelist_code = 'PAN-NOID-002', telegram_id = '@Cheikh_kara'
 WHERE panelist_code = 'P2';

DO $$
DECLARE r jsonb;
BEGIN
  -- el codigo en cualquier formato
  PERFORM pg_temp.one('PAN-KEN-047', 'PAN-KEN-047');
  PERFORM pg_temp.one('pan ken 047', 'PAN-KEN-047');
  PERFORM pg_temp.one('KEN-047', 'PAN-KEN-047');
  PERFORM pg_temp.one('ken047', 'PAN-KEN-047');
  PERFORM pg_temp.one('(PAN-KEN-047).', 'PAN-KEN-047');
  PERFORM pg_temp.one('es el panelista PAN-KEN-047, de Kericho', 'PAN-KEN-047');
  -- el Telegram: numero, @usuario con o sin @
  PERFORM pg_temp.one('8525727045', 'PAN-KEN-047');
  PERFORM pg_temp.one('su telegram es 8525727045', 'PAN-KEN-047');
  PERFORM pg_temp.one('@cheikh_kara', 'PAN-NOID-002');
  PERFORM pg_temp.one('Cheikh_kara', 'PAN-NOID-002');
  -- el codigo o el Telegram mandan sobre un nombre que coincide con otro panelista
  PERFORM pg_temp.one('Cheikh Seck PAN-KEN-047', 'PAN-KEN-047');
  -- nombre sin tildes y con signos
  r := ops_case._find('Jose Kyalo,', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1 OR r->0->>'code' <> 'PAN-KEN-047'
                          OR (r->0->>'by_id')::boolean OR NOT (r->0->>'by_name')::boolean, 'tildes: ' || r::text);
  -- un trozo no basta: ni el numero suelto, ni otro numero mas largo, ni el codigo sin cifras
  r := ops_case._find('047', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 0, 'numero suelto: ' || r::text);
  r := ops_case._find('PAN-KEN-0470', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 0, 'codigo mas largo: ' || r::text);
  r := ops_case._find('85257270450', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 0, 'telegram mas largo: ' || r::text);
  r := ops_case._find('cheikh', NULL, NULL);
  PERFORM pg_temp.fail_if(r->0->>'code' <> 'PAN-NOID-002' OR (r->0->>'by_id')::boolean, 'palabra no es usuario: ' || r::text);
  -- la cuenta se respeta
  PERFORM pg_temp.one('KEN-047', 'PAN-KEN-047', 'a0000000-0000-0000-0000-000000000001');
  r := ops_case._find('8525727045', NULL, 'a0000000-0000-0000-0000-000000000002');
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 0, 'telegram de otra cuenta visible: ' || r::text);
END $$;
ROLLBACK;
