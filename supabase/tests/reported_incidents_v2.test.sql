-- Incidencias reportadas v2: estado auto_resolved, razon materials y (tareas siguientes) mas piezas.
-- Cada escenario va en su propia transaccion con la fixture comun.
\set ON_ERROR_STOP on

CREATE FUNCTION pg_temp.expect_err(p_sql text, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN raise_exception OR check_violation THEN
    IF SQLERRM NOT LIKE p_msg || '%' THEN
      RAISE EXCEPTION 'FAIL error inesperado "%" (esperaba "%") en %', SQLERRM, p_msg, p_sql; END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL no fallo (esperaba "%"): %', p_msg, p_sql;
END $$;

-- Inserta una incidencia para la cuenta 1 / panelista P1 y devuelve su id.
CREATE FUNCTION pg_temp.inc(p_cat text, p_status text DEFAULT 'open', p_detail uuid DEFAULT NULL)
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status, allocation_plan_detail_id)
  VALUES ('a0000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
          p_cat, p_status, p_detail)
  RETURNING id;
$$;

-- ===== Escenario 1: status auto_resolved + razon materials =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.inc('other', 'auto_resolved');                           -- OK
SELECT pg_temp.expect_err($$SELECT pg_temp.inc('other', 'foo')$$, 'new row for relation "panelist_incident" violates check constraint "pi_status_check"');
DO $$
DECLARE v_inc uuid := pg_temp.inc('missing_materials'); v_unav uuid; v_reason text;
BEGIN
  v_unav := public.create_unavailability_from_incident(v_inc, current_date, current_date + 7, 'materials');
  SELECT reason INTO v_reason FROM public.panelist_unavailability WHERE id = v_unav;
  IF v_reason <> 'materials' THEN RAISE EXCEPTION 'FAIL reason=% (esperaba materials)', v_reason; END IF;
  IF (SELECT linked_unavailability_id FROM public.panelist_incident WHERE id = v_inc) IS DISTINCT FROM v_unav THEN
    RAISE EXCEPTION 'FAIL incidencia no enlazada'; END IF;
END $$;
ROLLBACK;

-- ===== Escenario 2: update_panelist_contact ampliada (_v2, 9 parametros) =====
BEGIN;
\ir fixtures/incident_city.sql
UPDATE public.panelists SET telegram_id = 'tg-old' WHERE id = 'e1000000-0000-0000-0000-000000000001';
SELECT public.update_panelist_contact_v2('e1000000-0000-0000-0000-000000000001',
  p_telegram_id => 'tg-new', p_phone => '+34 600 000 000', p_language => 'fr',
  p_email => 'nuevo@test.local', p_address_city => 'Lyon');
DO $$ DECLARE r public.panelists;
BEGIN
  SELECT * INTO r FROM public.panelists WHERE id = 'e1000000-0000-0000-0000-000000000001';
  IF r.telegram_id <> 'tg-old' THEN RAISE EXCEPTION 'FAIL telegram cambiado sin auth.uid()'; END IF;
  IF r.mobile <> '+34 600 000 000' OR r.language <> 'fr' OR r.email <> 'nuevo@test.local' OR r.address_city <> 'Lyon' THEN
    RAISE EXCEPTION 'FAIL campos no aplicados: %', row_to_json(r); END IF;
END $$;
-- cadena vacia = no tocar
SELECT public.update_panelist_contact_v2('e1000000-0000-0000-0000-000000000001', p_email => '');
DO $$ BEGIN
  IF (SELECT email FROM public.panelists WHERE id = 'e1000000-0000-0000-0000-000000000001') <> 'nuevo@test.local' THEN
    RAISE EXCEPTION 'FAIL email cambiado con cadena vacia'; END IF;
END $$;
-- validaciones
SELECT pg_temp.expect_err($$SELECT public.update_panelist_contact_v2('e1000000-0000-0000-0000-000000000001', p_email => 'sin-arroba')$$, 'invalid email');
SELECT pg_temp.expect_err($$SELECT public.update_panelist_contact_v2('e1000000-0000-0000-0000-000000000001', p_phone => 'abc')$$, 'invalid phone');
SELECT pg_temp.expect_err($$SELECT public.update_panelist_contact_v2('e1000000-0000-0000-0000-000000000001', p_language => 'xx')$$, 'invalid language');
-- firma antigua sigue funcionando
SELECT public.update_panelist_contact('e1000000-0000-0000-0000-000000000001', NULL, '600111222', 'es');
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.panelists WHERE id = 'e1000000-0000-0000-0000-000000000001'
                 AND mobile = '600111222' AND language = 'es') THEN
    RAISE EXCEPTION 'FAIL firma antigua no aplico telefono/idioma'; END IF;
END $$;
-- permisos: anon sin EXECUTE; authenticated y service_role con EXECUTE
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.update_panelist_contact_v2(uuid,text,text,text,text,text,text,text,text)',
                           'public.update_panelist_contact(uuid,text,text,text)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL anon puede ejecutar %', f; END IF;
    IF NOT has_function_privilege('authenticated', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL authenticated sin EXECUTE en %', f; END IF;
    IF NOT has_function_privilege('service_role', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL service_role sin EXECUTE en %', f; END IF;
  END LOOP;
END $$;
ROLLBACK;

-- ===== Escenario 3: insert_panelist_incident_auto =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
DO $$ DECLARE v uuid; r public.panelist_incident;
BEGIN
  v := public.insert_panelist_incident_auto('e1000000-0000-0000-0000-000000000001', 'parcel_damaged', 'roto', '{"x":1}'::jsonb);
  SELECT * INTO r FROM public.panelist_incident WHERE id = v;
  IF r.account_id <> 'a0000000-0000-0000-0000-000000000001' OR r.status <> 'auto_resolved' OR r.resolved_at IS NULL
     OR r.created_via <> 'telegram' OR r.payload->>'x' <> '1' THEN RAISE EXCEPTION 'FAIL auto: %', row_to_json(r); END IF;
  v := public.insert_panelist_incident_auto('e1000000-0000-0000-0000-000000000001', 'how_to_send', NULL, NULL, NULL, 'open');
  SELECT * INTO r FROM public.panelist_incident WHERE id = v;
  IF r.status <> 'open' OR r.resolved_at IS NOT NULL THEN RAISE EXCEPTION 'FAIL open: %', row_to_json(r); END IF;
END $$;
SELECT pg_temp.expect_err($$SELECT public.insert_panelist_incident_auto('e1000000-0000-0000-0000-000000000001', 'bad_cat')$$, 'invalid category');
SELECT pg_temp.expect_err($$SELECT public.insert_panelist_incident_auto('e1000000-0000-0000-0000-000000000001', 'other', NULL, NULL, NULL, 'resolved')$$, 'invalid status');
SELECT pg_temp.expect_err($$SELECT public.insert_panelist_incident_auto('00000000-0000-0000-0000-000000000000', 'other')$$, 'panelist not found');
-- muestra de la cuenta 2 con panelista de la cuenta 1
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
VALUES ('d2000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002', 'cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', current_date + 7, 'sent');
SELECT pg_temp.expect_err($$SELECT public.insert_panelist_incident_auto('e1000000-0000-0000-0000-000000000001', 'other', NULL, NULL, 'd2000000-0000-0000-0000-000000000002')$$, 'detail belongs to another account');
ROLLBACK;

-- ===== Escenario 4: reroute_returned_sample =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
-- Muestra devuelta N1 -> N2 (etiqueta T1). El motor no exige que la semana caiga dentro del plan.
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id)
VALUES ('d1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', current_date - 3, 'sent', 'T1');
-- cross-tenant (actor 98) mientras sigue 'sent': debe saltar la guarda, no el estado, y no mutar nada
DO $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
  PERFORM pg_temp.expect_err($q$SELECT public.reroute_returned_sample('d1000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000003', date_trunc('week', current_date + 14)::date)$q$, 'Cross-tenant access denied');
  PERFORM set_config('request.jwt.claim.sub','', true);
  IF (SELECT status FROM public.allocation_plan_details WHERE id = 'd1000000-0000-0000-0000-000000000001') <> 'sent' THEN
    RAISE EXCEPTION 'FAIL cross-tenant muto la muestra'; END IF;
END $$;
-- inexistente
SELECT pg_temp.expect_err($$SELECT public.reroute_returned_sample('d9000000-0000-0000-0000-000000000009', 'b3000000-0000-0000-0000-000000000003', date_trunc('week', current_date + 14)::date)$$, 'Sample d9000000-0000-0000-0000-000000000009 not found');
-- camino feliz: N2 -> N3 (misma ciudad)
DO $$ DECLARE j jsonb; r public.allocation_plan_details; w date := date_trunc('week', current_date + 14)::date;
BEGIN
  j := public.reroute_returned_sample('d1000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000003', w);
  SELECT * INTO r FROM public.allocation_plan_details WHERE id = 'd1000000-0000-0000-0000-000000000001';
  IF r.status <> 'pending' OR r.destination_node_id <> 'b3000000-0000-0000-0000-000000000003'
     OR r.original_destination_node_id <> 'b2000000-0000-0000-0000-000000000002' OR r.tag_id <> 'T1'
     OR r.fecha_programada < w OR r.fecha_programada > w + 6 OR r.sent_at IS NOT NULL OR r.sent_date IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL reroute: % / %', j, row_to_json(r); END IF;
  IF (j->>'side') <> 'destination' THEN RAISE EXCEPTION 'FAIL side=%', j->>'side'; END IF;
END $$;
-- ya pending -> no es devuelta
SELECT pg_temp.expect_err($$SELECT public.reroute_returned_sample('d1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', date_trunc('week', current_date + 14)::date)$$, 'Sample is not returned-eligible');
-- cancelled -> rechazada (received dispara transfer_to_one_db con datos incompletos)
UPDATE public.allocation_plan_details SET status = 'cancelled' WHERE id = 'd1000000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_err($$SELECT public.reroute_returned_sample('d1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', date_trunc('week', current_date + 14)::date)$$, 'Sample is not returned-eligible');
-- mismo nodo y mismo dia -> Nothing to change, y la muestra sigue 'incident' (el UPDATE a pending se revierte)
DO $$ DECLARE v_day date; w date := date_trunc('week', current_date + 14)::date;
BEGIN
  UPDATE public.allocation_plan_details SET status = 'pending', destination_node_id = 'b2000000-0000-0000-0000-000000000002'
   WHERE id = 'd1000000-0000-0000-0000-000000000001';
  v_day := (public.suggest_for_sample_move('d1000000-0000-0000-0000-000000000001',
            'b2000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000002', w)->>'date')::date;
  IF v_day IS NULL THEN RAISE EXCEPTION 'FAIL el motor no propuso dia'; END IF;
  UPDATE public.allocation_plan_details SET status = 'incident', fecha_programada = v_day
   WHERE id = 'd1000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.expect_err($q$SELECT public.reroute_returned_sample('d1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', date_trunc('week', current_date + 14)::date)$q$, 'Nothing to change');
  IF (SELECT status FROM public.allocation_plan_details WHERE id = 'd1000000-0000-0000-0000-000000000001') <> 'incident' THEN
    RAISE EXCEPTION 'FAIL la muestra no volvio a incident tras el error'; END IF;
END $$;
-- permisos
DO $$
DECLARE f text := 'public.reroute_returned_sample(uuid,uuid,date)';
BEGIN
  IF has_function_privilege('anon', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL anon puede ejecutar %', f; END IF;
  IF NOT has_function_privilege('authenticated', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL authenticated sin EXECUTE'; END IF;
  IF NOT has_function_privilege('service_role', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL service_role sin EXECUTE'; END IF;
END $$;
ROLLBACK;
