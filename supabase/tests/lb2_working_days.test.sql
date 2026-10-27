-- Load Balancing v2, tarea 1: dias laborables de la cuenta desde weekly_schedule (0=domingo..6=sabado,
-- sin filas => lunes-viernes) + non_working_days, working_day_in_range delegando en ello, y
-- effective_city_policy (politica de fechas / POBOX; POBOX fuerza 'daily').
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;

-- ===== Caso A: sin weekly_schedule => lunes-viernes.
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fail_if(public.is_account_working_day('a0000000-0000-0000-0000-000000000001', '2027-03-06'), 'A: sabado deberia ser no laborable');
SELECT pg_temp.fail_if(NOT public.is_account_working_day('a0000000-0000-0000-0000-000000000001', '2027-03-08'), 'A: lunes deberia ser laborable');
ROLLBACK;

-- ===== Caso B: domingo-jueves laborables.
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO public.weekly_schedule (account_id, day_of_week, is_working_day, opening_hour, cutoff_time)
  SELECT 'a0000000-0000-0000-0000-000000000001', d, d <= 4, '08:00', '17:00' FROM generate_series(0, 6) d;
SELECT pg_temp.fail_if(NOT public.is_account_working_day('a0000000-0000-0000-0000-000000000001', '2027-03-07'), 'B: domingo deberia ser laborable');
SELECT pg_temp.fail_if(public.is_account_working_day('a0000000-0000-0000-0000-000000000001', '2027-03-05'), 'B: viernes deberia ser no laborable');

-- ===== Caso D: working_day_in_range con el calendario Dom-Jue.
SELECT pg_temp.fail_if(public.working_day_in_range('a0000000-0000-0000-0000-000000000001', '2027-03-05', '2027-03-01', '2027-03-12') IS DISTINCT FROM '2027-03-07'::date,
  'D: esperaba 2027-03-07, obtuvo ' || COALESCE(public.working_day_in_range('a0000000-0000-0000-0000-000000000001', '2027-03-05', '2027-03-01', '2027-03-12')::text, 'NULL'));
ROLLBACK;

-- ===== Caso C: non_working_days manda sobre el calendario.
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO public.non_working_days (account_id, date, reason) VALUES ('a0000000-0000-0000-0000-000000000001', '2027-03-08', 'festivo test');
SELECT pg_temp.fail_if(public.is_account_working_day('a0000000-0000-0000-0000-000000000001', '2027-03-08'), 'C: festivo deberia ser no laborable');
ROLLBACK;

-- ===== Caso E: effective_city_policy.
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO public.account_config (account_id) VALUES ('a0000000-0000-0000-0000-000000000001');
SELECT pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.effective_city_policy('c1000000-0000-0000-0000-000000000001')
  WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND date_policy = 'daily' AND NOT pobox_enabled), 'E1: defaults de cuenta');
UPDATE public.cities SET date_policy = 'weekly' WHERE id = 'c1000000-0000-0000-0000-000000000001';
SELECT pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.effective_city_policy('c1000000-0000-0000-0000-000000000001')
  WHERE date_policy = 'weekly' AND NOT pobox_enabled), 'E2: ciudad weekly');
UPDATE public.cities SET pobox_enabled = true WHERE id = 'c1000000-0000-0000-0000-000000000001';
SELECT pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.effective_city_policy('c1000000-0000-0000-0000-000000000001')
  WHERE date_policy = 'daily' AND pobox_enabled), 'E3: POBOX fuerza daily');
ROLLBACK;

-- ===== Caso F: festivo de un solo centro postal NO afecta a la cuenta.
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO public.postal_centers (id, account_id, code, name)
  VALUES ('d1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'PC1', 'Centro1');
INSERT INTO public.non_working_days (account_id, postal_center_id, date, reason)
  VALUES ('a0000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', '2027-03-08', 'festivo del centro');
SELECT pg_temp.fail_if(NOT public.is_account_working_day('a0000000-0000-0000-0000-000000000001', '2027-03-08'), 'F: festivo de centro no debe afectar a la cuenta');
ROLLBACK;

-- ===== Caso G: POBOX heredado de la cuenta (ciudad NULL) fuerza daily aunque la cuenta sea weekly.
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO public.account_config (account_id, date_policy, pobox_enabled)
  VALUES ('a0000000-0000-0000-0000-000000000001', 'weekly', true);
SELECT pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.effective_city_policy('c1000000-0000-0000-0000-000000000001')
  WHERE date_policy = 'daily' AND pobox_enabled), 'G: POBOX heredado de la cuenta fuerza daily');
ROLLBACK;
