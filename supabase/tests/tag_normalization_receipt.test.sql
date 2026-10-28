-- Etiquetas homogéneas (normalize_tag + trigger) y recepción que ya no falla por el trigger transfer_to_one_db.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;

-- ===== (a) forma canónica
SELECT pg_temp.fail_if(public.normalize_tag('  00010758 ') IS DISTINCT FROM '00010758', 'espacios');
SELECT pg_temp.fail_if(public.normalize_tag('10758') IS DISTINCT FROM '00010758', 'sin ceros -> rellena a 8');
SELECT pg_temp.fail_if(public.normalize_tag('000010758') IS DISTINCT FROM '00010758', 'ceros de mas');
SELECT pg_temp.fail_if(public.normalize_tag('1245') IS DISTINCT FROM '00001245', 'corta -> rellena');
SELECT pg_temp.fail_if(public.normalize_tag('0001122479894') IS DISTINCT FROM '1122479894', 'larga: no se trunca');
SELECT pg_temp.fail_if(public.normalize_tag('99910000') IS DISTINCT FROM '99910000', '8 digitos sin ceros');
SELECT pg_temp.fail_if(public.normalize_tag('l9901-000') IS DISTINCT FROM 'L9901000', 'alfanumerica: mayusculas, sin signos');
SELECT pg_temp.fail_if(public.normalize_tag('Done') IS NOT NULL, 'sin digitos -> NULL');
SELECT pg_temp.fail_if(public.normalize_tag('') IS NOT NULL, 'vacia -> NULL');
SELECT pg_temp.fail_if(public.normalize_tag('0000') IS NOT NULL, 'solo ceros -> NULL');
SELECT pg_temp.fail_if(public.normalize_tag(NULL) IS NOT NULL, 'NULL -> NULL');

-- ===== (b) trigger: todo lo escrito queda canónico, idtag conserva lo escrito, lo inválido se rechaza
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada,
                                            week_number, month, year, status, generation_source, tag_id)
VALUES ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11',10,3,2027,'pending','plan',' 10758 ');
SELECT pg_temp.fail_if(tag_id IS DISTINCT FROM '00010758' OR idtag IS DISTINCT FROM '10758', 'insert: ' || tag_id || '/' || idtag)
  FROM public.allocation_plan_details WHERE id = 'd1000000-0000-0000-0000-000000000001';
UPDATE public.allocation_plan_details SET tag_id = '000000123', idtag = '000000123' WHERE id = 'd1000000-0000-0000-0000-000000000001';
SELECT pg_temp.fail_if(tag_id IS DISTINCT FROM '00000123' OR idtag IS DISTINCT FROM '000000123', 'update: ' || tag_id || '/' || idtag)
  FROM public.allocation_plan_details WHERE id = 'd1000000-0000-0000-0000-000000000001';
UPDATE public.allocation_plan_details SET tag_id = NULL WHERE id = 'd1000000-0000-0000-0000-000000000001';
SELECT pg_temp.fail_if(tag_id IS NOT NULL, 'NULL permitido') FROM public.allocation_plan_details WHERE id = 'd1000000-0000-0000-0000-000000000001';
DO $$
BEGIN
  BEGIN
    UPDATE public.allocation_plan_details SET tag_id = 'Done' WHERE id = 'd1000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL etiqueta sin digitos aceptada';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
ROLLBACK;

-- ===== (c) recepción de una fila del plan sin panelistas: se resuelven desde el nodo y pasa a one_db
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada,
                                            week_number, month, year, status, generation_source, tag_id, sent_at)
VALUES ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11',10,3,2027,'sent','plan','11082', now() - interval '2 days');
-- Lo que hace el bot (misma consulta que n8n, simplificada): etiqueta escrita de otra forma por el receptor
UPDATE public.allocation_plan_details
   SET status = 'received', received_at = now()
 WHERE id = (SELECT id FROM public.allocation_plan_details WHERE tag_id = public.normalize_tag('000011082') AND status = 'sent');
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.allocation_plan_details WHERE id = 'd2000000-0000-0000-0000-000000000002';
  PERFORM pg_temp.fail_if(r.status IS DISTINCT FROM 'received', 'status: ' || r.status);
  PERFORM pg_temp.fail_if(r.origin_panelist_id IS DISTINCT FROM 'e1000000-0000-0000-0000-000000000001', 'origen resuelto');
  PERFORM pg_temp.fail_if(r.destination_panelist_id IS DISTINCT FROM 'e4000000-0000-0000-0000-000000000004', 'destino resuelto');
  PERFORM pg_temp.fail_if(r.destination_panelist_name IS DISTINCT FROM 'Pan4', 'nombre destino');
  PERFORM pg_temp.fail_if(r.transferred_to_one_db_at IS NULL, 'no transferida a one_db: ' || coalesce(r.transfer_error_message, '-'));
  PERFORM pg_temp.fail_if(r.validation_errors IS NOT NULL, 'validation_errors: ' || coalesce(r.validation_errors::text, ''));
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.one_db WHERE allocation_detail_id = r.id AND tag_id = '00011082'), 'fila one_db');
END $$;
ROLLBACK;

-- ===== (d) destino sin panelista: la recepción se guarda igualmente, con el aviso, y sin estado fuera del CHECK
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N5');
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada,
                                            week_number, month, year, status, generation_source, tag_id, sent_at)
VALUES ('d3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001','b5000000-0000-0000-0000-000000000005','2027-03-11',10,3,2027,'sent','plan','00011083', now() - interval '2 days');
UPDATE public.allocation_plan_details SET status = 'received', received_at = now() WHERE id = 'd3000000-0000-0000-0000-000000000003';
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.allocation_plan_details WHERE id = 'd3000000-0000-0000-0000-000000000003';
  PERFORM pg_temp.fail_if(r.status IS DISTINCT FROM 'received', 'status (d): ' || r.status);
  PERFORM pg_temp.fail_if(NOT ('Missing destination panelist' = ANY (r.validation_errors)), 'aviso destino: ' || coalesce(r.validation_errors::text, ''));
  PERFORM pg_temp.fail_if(r.transferred_to_one_db_at IS NOT NULL, 'no debe transferirse');
END $$;
ROLLBACK;

-- ===== (e) corrección de datos existentes (simulada): filas guardadas con otra longitud quedan canónicas
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
ALTER TABLE public.allocation_plan_details DISABLE TRIGGER normalize_allocation_tag;
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada,
                                            week_number, month, year, status, generation_source, tag_id)
VALUES ('d4000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11',10,3,2027,'sent','plan','000010172'),
       ('d5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-12',10,3,2027,'sent','plan','Done');
ALTER TABLE public.allocation_plan_details ENABLE TRIGGER normalize_allocation_tag;
UPDATE public.allocation_plan_details
   SET tag_id = public.normalize_tag(tag_id)
 WHERE tag_id IS NOT NULL AND public.normalize_tag(tag_id) IS NOT NULL AND public.normalize_tag(tag_id) IS DISTINCT FROM tag_id;
SELECT pg_temp.fail_if(tag_id IS DISTINCT FROM '00010172', 'backfill: ' || tag_id) FROM public.allocation_plan_details WHERE id = 'd4000000-0000-0000-0000-000000000004';
SELECT pg_temp.fail_if(tag_id IS DISTINCT FROM 'Done', 'backfill deja la invalida: ' || tag_id) FROM public.allocation_plan_details WHERE id = 'd5000000-0000-0000-0000-000000000005';
ROLLBACK;

SELECT 'OK tag_normalization_receipt' AS resultado;
