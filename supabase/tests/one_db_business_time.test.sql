-- Business time: horas y dias laborables calculados en la hora local de la cuenta (Africa/Nairobi = UTC+3).
-- Los instantes se dan en UTC = hora Nairobi - 3 h.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;

-- ===== Caso H1: vie 16:00 Nairobi -> lun 10:00 Nairobi = 8 + 10 = 18.00
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.fail_if(public.calculate_business_hours('2026-10-30 13:00:00+00', '2026-11-02 07:00:00+00', 'a0000000-0000-0000-0000-000000000003') IS DISTINCT FROM 18.00, 'H1 esperaba 18.00');
ROLLBACK;

-- ===== Caso H2: mar 16:44 -> jue 10:40 Nairobi = 41.93
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.fail_if(public.calculate_business_hours('2026-10-27 13:44:00+00', '2026-10-29 07:40:00+00', 'a0000000-0000-0000-0000-000000000003') IS DISTINCT FROM 41.93, 'H2 esperaba 41.93');
ROLLBACK;

-- ===== Caso H3/H4/H-NULL: mismo instante = 0; fin < inicio = 0; entrada NULL = NULL
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.fail_if(public.calculate_business_hours('2026-10-26 06:00:00+00', '2026-10-26 06:00:00+00', 'a0000000-0000-0000-0000-000000000003') IS DISTINCT FROM 0.00, 'H3 esperaba 0.00');
SELECT pg_temp.fail_if(public.calculate_business_hours('2026-11-02 07:00:00+00', '2026-10-30 13:00:00+00', 'a0000000-0000-0000-0000-000000000003') IS DISTINCT FROM 0.00, 'H4 esperaba 0.00');
SELECT pg_temp.fail_if(public.calculate_business_hours(NULL, '2026-10-30 13:00:00+00', 'a0000000-0000-0000-0000-000000000003') IS NOT NULL, 'H-NULL esperaba NULL');
ROLLBACK;

-- ===== Caso H5: H1 con el lunes festivo = 8.00
BEGIN;
\ir fixtures/one_db_kenya.sql
INSERT INTO public.non_working_days (account_id, postal_center_id, date, reason) VALUES ('a0000000-0000-0000-0000-000000000003', NULL, '2026-11-02', 'festivo test');
SELECT pg_temp.fail_if(public.calculate_business_hours('2026-10-30 13:00:00+00', '2026-11-02 07:00:00+00', 'a0000000-0000-0000-0000-000000000003') IS DISTINCT FROM 8.00, 'H5 esperaba 8.00');
ROLLBACK;

-- ===== Caso H6: sin cuenta => UTC y lunes-viernes. vie 22:00Z -> lun 02:00Z = 2 + 2 = 4.00
BEGIN;
SELECT pg_temp.fail_if(public.calculate_business_hours('2026-10-30 22:00:00+00', '2026-11-02 02:00:00+00', NULL) IS DISTINCT FROM 4.00, 'H6 esperaba 4.00');
ROLLBACK;

-- ===== Caso D1: mar 16:44 -> jue 10:40 Nairobi = 2 dias (mar, mie)
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.fail_if(public.calculate_business_days('2026-10-27 13:44:00+00', '2026-10-29 07:40:00+00', 'a0000000-0000-0000-0000-000000000003') IS DISTINCT FROM 2, 'D1 esperaba 2');
ROLLBACK;

-- ===== Caso D2: mismo dia local = 0
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.fail_if(public.calculate_business_days('2026-10-26 06:00:00+00', '2026-10-26 15:00:00+00', 'a0000000-0000-0000-0000-000000000003') IS DISTINCT FROM 0, 'D2 esperaba 0');
ROLLBACK;

-- ===== Caso D3: vie 16:00 -> lun 10:00 = 1 (viernes); lunes festivo = 1; viernes festivo = 0
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.fail_if(public.calculate_business_days('2026-10-30 13:00:00+00', '2026-11-02 07:00:00+00', 'a0000000-0000-0000-0000-000000000003') IS DISTINCT FROM 1, 'D3a esperaba 1');
INSERT INTO public.non_working_days (account_id, postal_center_id, date, reason) VALUES ('a0000000-0000-0000-0000-000000000003', NULL, '2026-11-02', 'festivo lunes');
SELECT pg_temp.fail_if(public.calculate_business_days('2026-10-30 13:00:00+00', '2026-11-02 07:00:00+00', 'a0000000-0000-0000-0000-000000000003') IS DISTINCT FROM 1, 'D3b esperaba 1');
INSERT INTO public.non_working_days (account_id, postal_center_id, date, reason) VALUES ('a0000000-0000-0000-0000-000000000003', NULL, '2026-10-30', 'festivo viernes');
SELECT pg_temp.fail_if(public.calculate_business_days('2026-10-30 13:00:00+00', '2026-11-02 07:00:00+00', 'a0000000-0000-0000-0000-000000000003') IS DISTINCT FROM 0, 'D3c esperaba 0');
ROLLBACK;

-- ===== Caso D4: 28/10 23:30Z y 29/10 08:00Z son ambos 29/10 en Nairobi => 0 (en UTC serian 1)
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.fail_if(public.calculate_business_days('2026-10-28 23:30:00+00', '2026-10-29 08:00:00+00', 'a0000000-0000-0000-0000-000000000003') IS DISTINCT FROM 0, 'D4 esperaba 0');
ROLLBACK;

-- ===== Caso D5: sin cuenta => UTC y lunes-viernes; fin < inicio = 0
BEGIN;
SELECT pg_temp.fail_if(public.calculate_business_days('2026-10-28 23:30:00+00', '2026-10-29 08:00:00+00', NULL) IS DISTINCT FROM 1, 'D5a esperaba 1');
SELECT pg_temp.fail_if(public.calculate_business_days('2026-11-02 07:00:00+00', '2026-10-30 13:00:00+00', NULL) IS DISTINCT FROM 0, 'D5b esperaba 0');
ROLLBACK;
