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
