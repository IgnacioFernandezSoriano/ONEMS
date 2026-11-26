-- Paquete ampliado de ops_case._data: near_tags, expected_for_panelist, sender_series, details.cancellation_reason.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
-- Cuenta 2: ciudad + nodo propios y una linea 00011419 (el plan se reutiliza, solo importa account_id)
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','RegX','RX');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','CityX','CX');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000002','c3000000-0000-0000-0000-000000000003','NX');
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, sent_at, tag_id)
VALUES (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000002', 'cc000000-0000-0000-0000-000000000001',
        'b5000000-0000-0000-0000-000000000005', 'b5000000-0000-0000-0000-000000000005', current_date, 'sent', now() - interval '1 day', '00011419');
-- Cuenta 1: tres lineas desde N1
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, sent_at, tag_id,
   cancellation_reason, cancelled_at, origin_panelist_id, destination_panelist_id)
SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
       'b1000000-0000-0000-0000-000000000001', d.nid, current_date, v.st, now() - v.ago, v.tag,
       v.rsn, CASE WHEN v.st = 'cancelled' THEN now() END,
       'e1000000-0000-0000-0000-000000000001', d.pid
  FROM (VALUES ('cancelled', '00014118', 'not_received_timeout', interval '20 days', 'N4'),
               ('sent',      '00011415', NULL,                   interval '3 days',  'N4'),
               ('sent',      '00011417', NULL,                   interval '2 days',  'N2')) v(st, tag, rsn, ago, dn)
  JOIN (SELECT n.id nid, n.auto_id, (SELECT id FROM public.panelists WHERE node_id = n.id LIMIT 1) pid FROM public.nodes n
         WHERE n.account_id = 'a0000000-0000-0000-0000-000000000001') d ON d.auto_id = v.dn;

DO $$
DECLARE r jsonb; r2 jsonb; t text[];
BEGIN
  r := ops_case._data('e4000000-0000-0000-0000-000000000004', '00011418', NULL, NULL);
  -- near_tags
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'near_tags') <> 3, 'near_tags n ' || (r->'near_tags')::text);
  PERFORM pg_temp.fail_if((SELECT x->>'kind' FROM jsonb_array_elements(r->'near_tags') x WHERE x->>'tag' = '00014118') IS DISTINCT FROM 'swap', 'kind swap');
  PERFORM pg_temp.fail_if((SELECT (x->>'same_city')::boolean FROM jsonb_array_elements(r->'near_tags') x WHERE x->>'tag' = '00014118') IS DISTINCT FROM true, 'swap same_city');
  PERFORM pg_temp.fail_if((SELECT x->>'cancellation_reason' FROM jsonb_array_elements(r->'near_tags') x WHERE x->>'tag' = '00014118') IS DISTINCT FROM 'not_received_timeout', 'near reason');
  PERFORM pg_temp.fail_if((SELECT x->>'kind' FROM jsonb_array_elements(r->'near_tags') x WHERE x->>'tag' = '00011415') IS DISTINCT FROM 'one_digit', 'kind one_digit');
  PERFORM pg_temp.fail_if((SELECT (x->>'same_city')::boolean FROM jsonb_array_elements(r->'near_tags') x WHERE x->>'tag' = '00011415') IS DISTINCT FROM true, '11415 same_city');
  PERFORM pg_temp.fail_if((SELECT (x->>'same_city')::boolean FROM jsonb_array_elements(r->'near_tags') x WHERE x->>'tag' = '00011417') IS DISTINCT FROM false, '11417 not same_city');
  PERFORM pg_temp.fail_if((SELECT x->>'origin_code' FROM jsonb_array_elements(r->'near_tags') x WHERE x->>'tag' = '00011417') IS DISTINCT FROM 'P1', 'origin_code');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM jsonb_array_elements(r->'near_tags') x WHERE x->>'tag' = '00011419'), 'cuenta 2 filtrada');
  PERFORM pg_temp.fail_if((r->'near_tags'->0->>'same_city')::boolean IS DISTINCT FROM true, 'orden same_city primero');
  -- expected_for_panelist
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'expected_for_panelist') <> 2, 'expected n ' || (r->'expected_for_panelist')::text);
  t := ARRAY(SELECT x->>'tag' FROM jsonb_array_elements(r->'expected_for_panelist') x ORDER BY 1);
  PERFORM pg_temp.fail_if(t IS DISTINCT FROM ARRAY['00011415','00014118'], 'expected tags ' || t::text);
  -- sender_series
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'sender_series') <> 1, 'series n');
  PERFORM pg_temp.fail_if(r->'sender_series'->0->>'origin_code' IS DISTINCT FROM 'P1', 'series origin');
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'sender_series'->0->'tags') <> 3, 'series tags ' || (r->'sender_series')::text);
  -- details.cancellation_reason
  r2 := ops_case._data('e4000000-0000-0000-0000-000000000004', '00014118', NULL, NULL);
  PERFORM pg_temp.fail_if(r2->'details'->0->>'cancellation_reason' IS DISTINCT FROM 'not_received_timeout', 'details reason');
  -- normalizacion del parametro
  r2 := ops_case._data('e4000000-0000-0000-0000-000000000004', ' 0011418 ', NULL, NULL);
  PERFORM pg_temp.fail_if(r2->'near_tags' IS DISTINCT FROM r->'near_tags', 'p_tag normaliza');
  -- sin etiqueta: listas vacias
  r2 := ops_case._data('e4000000-0000-0000-0000-000000000004', NULL, NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r2->'near_tags') <> 0, 'sin tag near');
  -- _typo_kind
  PERFORM pg_temp.fail_if(ops_case._typo_kind('00011418','00014118') IS DISTINCT FROM 'swap', 'tk swap');
  PERFORM pg_temp.fail_if(ops_case._typo_kind('00011418','00011415') IS DISTINCT FROM 'one_digit', 'tk one');
  PERFORM pg_temp.fail_if(ops_case._typo_kind('00011418','00011418') IS NOT NULL, 'tk igual');
  PERFORM pg_temp.fail_if(ops_case._typo_kind('00011418','0011418') IS NOT NULL, 'tk longitud');
  PERFORM pg_temp.fail_if(ops_case._typo_kind('00011418','ABC11418') IS NOT NULL, 'tk letras');
  PERFORM pg_temp.fail_if(ops_case._typo_kind('00011418','00041118') IS NOT NULL, 'tk 2 dif no adyacentes/no swap');
END $$;
-- 35 envios 'sent' mas hacia N4 (dias 4..38): el tope de 30 debe conservar los mas recientes
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, sent_at, tag_id,
   origin_panelist_id, destination_panelist_id)
SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
       'b1000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000004', current_date, 'sent',
       now() - (g || ' days')::interval, lpad((90000000 + g)::text, 8, '0'),
       'e1000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000004'
  FROM generate_series(4, 38) g;
DO $$
DECLARE r jsonb;
BEGIN
  r := ops_case._data('e4000000-0000-0000-0000-000000000004', '00011418', NULL, NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'expected_for_panelist') <> 30, 'expected tope 30');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'expected_for_panelist') x WHERE x->>'tag' = '00011415'), 'expected incluye el mas reciente');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM jsonb_array_elements(r->'expected_for_panelist') x WHERE x->>'tag' = '90000038'), 'expected excluye el mas antiguo');
  PERFORM pg_temp.fail_if(r->'expected_for_panelist'->0->>'sent_at' > r->'expected_for_panelist'->29->>'sent_at', 'expected orden ascendente');
END $$;
ROLLBACK;
