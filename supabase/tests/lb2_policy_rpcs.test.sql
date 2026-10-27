-- Load Balancing v2 (fix I2): RPCs SECURITY DEFINER para editar politicas y dias laborables sin depender de
-- las politicas RLS de account_config / cities / weekly_schedule.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
CREATE FUNCTION pg_temp.wdows() RETURNS int[] LANGUAGE sql AS $$
  SELECT array_agg(EXTRACT(dow FROM d)::int ORDER BY d) FROM generate_series('2027-03-07'::date, '2027-03-13', '1 day') d
   WHERE public.is_account_working_day('a0000000-0000-0000-0000-000000000001', d::date);
$$;

-- ===== Rol 'user' de la cuenta 1: politica de cuenta (sin fila previa), de ciudad y dia laborable.
BEGIN;
\ir fixtures/incident_city.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_set_account_balance_policy('a0000000-0000-0000-0000-000000000001', 'weekly', NULL);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true OR r->>'date_policy' IS DISTINCT FROM 'weekly'
                          OR (r->>'pobox_enabled')::boolean IS DISTINCT FROM false, 'cuenta insert: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT calculation_mode FROM public.account_config
                            WHERE account_id = 'a0000000-0000-0000-0000-000000000001') IS DISTINCT FROM 'natural_days',
                          'calculation_mode por defecto');
  -- Solo cambia el parametro no nulo.
  UPDATE public.account_config SET calculation_mode = 'working_days' WHERE account_id = 'a0000000-0000-0000-0000-000000000001';
  r := public.rpc_set_account_balance_policy('a0000000-0000-0000-0000-000000000001', NULL, true);
  PERFORM pg_temp.fail_if(r->>'date_policy' IS DISTINCT FROM 'weekly' OR (r->>'pobox_enabled')::boolean IS DISTINCT FROM true,
                          'cuenta update parcial: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT calculation_mode FROM public.account_config
                            WHERE account_id = 'a0000000-0000-0000-0000-000000000001') IS DISTINCT FROM 'working_days',
                          'no debe pisar calculation_mode');

  -- Ciudad: fija date_policy sin tocar pobox; luego pobox; luego vuelve a heredar (NULL).
  r := public.rpc_set_city_balance_policy('c1000000-0000-0000-0000-000000000001', true, 'weekly', false, NULL);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'ciudad: ' || r::text);
  UPDATE public.cities SET pobox_enabled = true WHERE id = 'c1000000-0000-0000-0000-000000000001';
  r := public.rpc_set_city_balance_policy('c1000000-0000-0000-0000-000000000001', true, 'daily', false, NULL);
  PERFORM pg_temp.fail_if((SELECT date_policy IS DISTINCT FROM 'daily' OR pobox_enabled IS DISTINCT FROM true FROM public.cities
                            WHERE id = 'c1000000-0000-0000-0000-000000000001'), 'ciudad: pobox no debe cambiar');
  r := public.rpc_set_city_balance_policy('c1000000-0000-0000-0000-000000000001', true, NULL, true, NULL);
  PERFORM pg_temp.fail_if((SELECT date_policy IS NOT NULL OR pobox_enabled IS NOT NULL FROM public.cities
                            WHERE id = 'c1000000-0000-0000-0000-000000000001'), 'ciudad: NULL = hereda');

  -- Primer dia laborable en una cuenta sin filas: siembra las 7 y apaga el lunes.
  r := public.rpc_set_working_day('a0000000-0000-0000-0000-000000000001', 1, false);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'working day: ' || r::text);
  PERFORM pg_temp.fail_if(pg_temp.wdows() IS DISTINCT FROM ARRAY[2,3,4,5], 'tras lunes off: ' || pg_temp.wdows()::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.weekly_schedule
                            WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND postal_center_id IS NULL) <> 7,
                          'deberia haber 7 filas');
  -- Encender el sabado (fila sembrada sin horas) => horas presentes por el CHECK.
  r := public.rpc_set_working_day('a0000000-0000-0000-0000-000000000001', 6, true);
  PERFORM pg_temp.fail_if(pg_temp.wdows() IS DISTINCT FROM ARRAY[2,3,4,5,6], 'tras sabado on: ' || pg_temp.wdows()::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.weekly_schedule
                            WHERE account_id = 'a0000000-0000-0000-0000-000000000001') <> 7, 'sigue con 7 filas');
END $$;
ROLLBACK;

-- ===== Una fila de centro postal no cuenta como fila de la cuenta (se siembran igualmente las 7) y no se toca.
BEGIN;
\ir fixtures/incident_city.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
INSERT INTO public.postal_centers (id, account_id, code, name)
  VALUES ('d1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'PC1', 'Centro1');
INSERT INTO public.weekly_schedule (account_id, postal_center_id, day_of_week, is_working_day, opening_hour, cutoff_time)
  VALUES ('a0000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 1, true, '07:00', '19:00');
SELECT public.rpc_set_working_day('a0000000-0000-0000-0000-000000000001', 1, false);
SELECT pg_temp.fail_if((SELECT count(*) FROM public.weekly_schedule WHERE postal_center_id IS NULL) <> 7, 'centro: 7 filas de cuenta');
SELECT pg_temp.fail_if((SELECT NOT is_working_day FROM public.weekly_schedule WHERE postal_center_id IS NOT NULL), 'centro: fila del centro tocada');
SELECT pg_temp.fail_if(pg_temp.wdows() IS DISTINCT FROM ARRAY[2,3,4,5], 'centro: dias');
ROLLBACK;

-- ===== Actor de la cuenta 2 sobre la cuenta 1 => 42501 en las tres.
BEGIN;
\ir fixtures/incident_city.sql
SELECT set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
DO $$
BEGIN
  BEGIN
    PERFORM public.rpc_set_account_balance_policy('a0000000-0000-0000-0000-000000000001', 'weekly', NULL);
    RAISE EXCEPTION 'FAIL cuenta ajena: account policy';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.rpc_set_city_balance_policy('c1000000-0000-0000-0000-000000000001', true, 'weekly', false, NULL);
    RAISE EXCEPTION 'FAIL cuenta ajena: city policy';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.rpc_set_working_day('a0000000-0000-0000-0000-000000000001', 1, false);
    RAISE EXCEPTION 'FAIL cuenta ajena: working day';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
SELECT pg_temp.fail_if(EXISTS (SELECT 1 FROM public.account_config), 'cuenta ajena escribio account_config');
SELECT pg_temp.fail_if(EXISTS (SELECT 1 FROM public.weekly_schedule), 'cuenta ajena escribio weekly_schedule');
ROLLBACK;

-- ===== Superadmin (account_id NULL) puede editar las politicas de la cuenta 1.
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO auth.users (id, email) VALUES ('97000000-0000-0000-0000-000000000097', 'sa@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id)
  VALUES ('97000000-0000-0000-0000-000000000097', 'sa@t.l', 'SA', 'superadmin', NULL);
SELECT set_config('request.jwt.claim.sub','97000000-0000-0000-0000-000000000097', true);
SELECT public.rpc_set_account_balance_policy('a0000000-0000-0000-0000-000000000001', 'weekly', true);
SELECT public.rpc_set_city_balance_policy('c1000000-0000-0000-0000-000000000001', true, 'weekly', true, false);
SELECT public.rpc_set_working_day('a0000000-0000-0000-0000-000000000001', 6, true);
SELECT pg_temp.fail_if((SELECT date_policy <> 'weekly' OR NOT pobox_enabled FROM public.account_config
                         WHERE account_id = 'a0000000-0000-0000-0000-000000000001'), 'superadmin: cuenta');
SELECT pg_temp.fail_if((SELECT date_policy IS DISTINCT FROM 'weekly' OR pobox_enabled IS DISTINCT FROM false FROM public.cities
                         WHERE id = 'c1000000-0000-0000-0000-000000000001'), 'superadmin: ciudad');
SELECT pg_temp.fail_if(pg_temp.wdows() IS DISTINCT FROM ARRAY[1,2,3,4,5,6], 'superadmin: sabado');
ROLLBACK;

-- ===== Valores invalidos.
BEGIN;
\ir fixtures/incident_city.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DO $$
BEGIN
  BEGIN
    PERFORM public.rpc_set_account_balance_policy('a0000000-0000-0000-0000-000000000001', 'monthly', NULL);
    RAISE EXCEPTION 'FAIL politica invalida aceptada (cuenta)';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.rpc_set_city_balance_policy('c1000000-0000-0000-0000-000000000001', true, 'monthly', false, NULL);
    RAISE EXCEPTION 'FAIL politica invalida aceptada (ciudad)';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.rpc_set_working_day('a0000000-0000-0000-0000-000000000001', 7, true);
    RAISE EXCEPTION 'FAIL dia invalido aceptado';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END $$;
ROLLBACK;

-- ===== Ciudad inexistente => 'City not found' (no 42501, no escritura).
BEGIN;
\ir fixtures/incident_city.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.fail_if((public.rpc_set_city_balance_policy('c9000000-0000-0000-0000-000000000009', true, 'weekly', false, NULL)->>'success')::boolean
                       IS DISTINCT FROM false, 'ciudad inexistente');
ROLLBACK;

-- ===== Permisos: anon no puede ejecutar.
SELECT pg_temp.fail_if(has_function_privilege('anon', 'public.rpc_set_working_day(uuid, integer, boolean)', 'EXECUTE'), 'anon working day');
SELECT pg_temp.fail_if(has_function_privilege('anon', 'public.rpc_set_account_balance_policy(uuid, text, boolean)', 'EXECUTE'), 'anon account');
SELECT pg_temp.fail_if(has_function_privilege('anon', 'public.rpc_set_city_balance_policy(uuid, boolean, text, boolean, boolean)', 'EXECUTE'), 'anon city');
SELECT pg_temp.fail_if(NOT has_function_privilege('authenticated', 'public.rpc_set_working_day(uuid, integer, boolean)', 'EXECUTE'), 'authenticated working day');
