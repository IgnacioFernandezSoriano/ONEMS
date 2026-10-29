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

-- ===================== Task 2: trigger en one_db, transfer_to_one_db y recalculo por estandar =====================
-- Helper: crea un envio en estado 'sent' (nodo origen -> nodo destino) y lo recibe en p_recv.
CREATE FUNCTION pg_temp.ship(p_plan uuid, p_o uuid, p_d uuid, p_tag text, p_sent timestamptz, p_recv timestamptz) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status, tag_id, sent_at)
  VALUES ('a0000000-0000-0000-0000-000000000003', p_plan, p_o, p_d, '2026-10-27', 44, 10, 2026, 'sent', p_tag, p_sent);
  UPDATE public.allocation_plan_details SET status = 'received', received_at = p_recv WHERE tag_id = p_tag;
END $$;

-- ===== T1: estandar en horas (48 h); el instante no se desplaza y salen las medidas locales
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.ship('cc000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000003','00010305','2026-10-27 13:44:18Z','2026-10-29 07:40:57Z');
SELECT pg_temp.fail_if((SELECT count(*) FROM one_db) IS DISTINCT FROM 1, 'T1 esperaba 1 fila en one_db');
SELECT pg_temp.fail_if((SELECT sent_at FROM one_db) IS DISTINCT FROM '2026-10-27 13:44:18Z'::timestamptz, 'T1 sent_at');
SELECT pg_temp.fail_if((SELECT sent_at_local FROM one_db) IS DISTINCT FROM '2026-10-27 16:44:18'::timestamp, 'T1 sent_at_local');
SELECT pg_temp.fail_if((SELECT received_at_local FROM one_db) IS DISTINCT FROM '2026-10-29 10:40:57'::timestamp, 'T1 received_at_local');
SELECT pg_temp.fail_if((SELECT total_transit_hours FROM one_db) IS DISTINCT FROM 41.94, 'T1 total_transit_hours');
SELECT pg_temp.fail_if((SELECT business_transit_hours FROM one_db) IS DISTINCT FROM 41.94, 'T1 business_transit_hours');
SELECT pg_temp.fail_if((SELECT total_transit_days FROM one_db) IS DISTINCT FROM 2, 'T1 total_transit_days');
SELECT pg_temp.fail_if((SELECT business_transit_days FROM one_db) IS DISTINCT FROM 2, 'T1 business_transit_days');
SELECT pg_temp.fail_if((SELECT on_time_delivery FROM one_db) IS DISTINCT FROM true, 'T1 on_time_delivery');
ROLLBACK;

-- ===== T1b: jue 29/10 16:00 -> lun 2/11 10:00 Nairobi
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.ship('cc000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000003','00010306','2026-10-29 13:00:00Z','2026-11-02 07:00:00Z');
SELECT pg_temp.fail_if((SELECT total_transit_hours FROM one_db) IS DISTINCT FROM 90.00, 'T1b total_transit_hours');
SELECT pg_temp.fail_if((SELECT total_transit_days FROM one_db) IS DISTINCT FROM 4, 'T1b total_transit_days');
SELECT pg_temp.fail_if((SELECT business_transit_hours FROM one_db) IS DISTINCT FROM 42.00, 'T1b business_transit_hours');
SELECT pg_temp.fail_if((SELECT business_transit_days FROM one_db) IS DISTINCT FROM 2, 'T1b business_transit_days');
ROLLBACK;

-- ===== T2: estandar en dias (2); 2 dias laborables = a tiempo, 3 = tarde
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.ship('cc000000-0000-0000-0000-000000000013','b1000000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000003','00010307','2026-10-27 13:44:18Z','2026-10-29 07:40:57Z');
SELECT pg_temp.fail_if((SELECT on_time_delivery FROM one_db WHERE tag_id = '00010307') IS DISTINCT FROM true, 'T2a a tiempo');
SELECT pg_temp.ship('cc000000-0000-0000-0000-000000000013','b1000000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000003','00010308','2026-10-27 13:44:18Z','2026-10-30 10:40:00Z');
SELECT pg_temp.fail_if((SELECT business_transit_days FROM one_db WHERE tag_id = '00010308') IS DISTINCT FROM 3, 'T2b dias');
SELECT pg_temp.fail_if((SELECT on_time_delivery FROM one_db WHERE tag_id = '00010308') IS DISTINCT FROM false, 'T2b tarde');
ROLLBACK;

-- ===== T3: INSERT directo en one_db: el trigger rellena todo
BEGIN;
\ir fixtures/one_db_kenya.sql
INSERT INTO public.one_db (account_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name, sent_at, received_at, source_data_snapshot)
VALUES ('a0000000-0000-0000-0000-000000000003','D1','P','KENYA POST','X','Kericho','Garissa','2026-10-27 13:44:18Z','2026-10-29 07:40:57Z','{}');
SELECT pg_temp.fail_if((SELECT total_transit_hours FROM one_db WHERE tag_id='D1') IS DISTINCT FROM 41.94, 'T3 total_transit_hours');
SELECT pg_temp.fail_if((SELECT business_transit_hours FROM one_db WHERE tag_id='D1') IS DISTINCT FROM 41.94, 'T3 business_transit_hours');
SELECT pg_temp.fail_if((SELECT business_transit_days FROM one_db WHERE tag_id='D1') IS DISTINCT FROM 2, 'T3 business_transit_days');
SELECT pg_temp.fail_if((SELECT sent_at_local FROM one_db WHERE tag_id='D1') IS DISTINCT FROM '2026-10-27 16:44:18'::timestamp, 'T3 sent_at_local');
-- (fin < inicio => 0 queda cubierto en H4/D5b: el CHECK one_db_valid_timestamps impide filas invertidas)
ROLLBACK;

-- ===== T4: cambiar el estandar recalcula on_time (producto casado por description)
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.ship('cc000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000003','00010305','2026-10-27 13:44:18Z','2026-10-29 07:40:57Z');
SELECT pg_temp.fail_if((SELECT on_time_delivery FROM one_db) IS DISTINCT FROM true, 'T4 previo a tiempo');
UPDATE public.delivery_standards SET standard_time = 30 WHERE id = 'd1000000-0000-0000-0000-000000000003';
SELECT pg_temp.fail_if((SELECT on_time_delivery FROM one_db) IS DISTINCT FROM false, 'T4 tras 30 h debe ser false');
ROLLBACK;

-- ===== T5: ruta sin estandar => NULL; time_unit NULL se compara en horas
BEGIN;
\ir fixtures/one_db_kenya.sql
SELECT pg_temp.ship('cc000000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000003','00010309','2026-10-27 13:44:18Z','2026-10-29 07:40:57Z');
SELECT pg_temp.fail_if((SELECT on_time_delivery FROM one_db WHERE tag_id='00010309') IS NOT NULL, 'T5a sin estandar debe ser NULL');
UPDATE public.delivery_standards SET standard_time = 30, time_unit = NULL WHERE id = 'd1000000-0000-0000-0000-000000000003';
SELECT pg_temp.ship('cc000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000003','00010310','2026-10-27 13:44:18Z','2026-10-29 07:40:57Z');
SELECT pg_temp.fail_if((SELECT on_time_delivery FROM one_db WHERE tag_id='00010310') IS DISTINCT FROM false, 'T5b time_unit NULL en horas: 41.94 > 30');
ROLLBACK;
