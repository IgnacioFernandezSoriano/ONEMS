-- Reconstruccion de tramos v2: transito desde la ultima lectura, tiempos natural/laborable,
-- enriquecimiento en origen y reconstruccion idempotente por etiqueta.
-- Spec: docs/superpowers/specs/2026-10-30-reconstruccion-tramos-v2-design.md
BEGIN;
\ir fixtures/incident_city.sql

-- PC1 en City1 (dias naturales); PC2 en City2 (dias laborables 08:00-17:00)
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id, calculation_mode, opening_hour, working_hours_end, timezone) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001','natural_days',NULL,NULL,'UTC'),
  ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','PC2','Center 2','City2','c2000000-0000-0000-0000-000000000002','working_days','08:00','17:00','UTC');
INSERT INTO public.readers (id, account_id, postal_center_id, reader_id, name, type) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','LPI1','R1','Mixed'),
  ('f2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000002','LPI2','R2','Mixed');
-- SLA operativo solo en PC2: 120 min esperados
INSERT INTO public.slas (account_id, sla_type, postal_center_id, expected_time_minutes, on_time_percentage, warning_threshold, critical_threshold, is_active)
VALUES ('a0000000-0000-0000-0000-000000000001','operational','d2000000-0000-0000-0000-000000000002',120,100,100,100,true);

-- Helper de insercion de eventos enriquecidos (como los deja la consolidacion)
CREATE TEMP TABLE ev(tag text, pc text, et text, ts timestamptz);
INSERT INTO ev VALUES
  -- Caso 1: lectura suelta en PC1 (lunes 10:00), entrada+salida en PC2 (martes 09:00-11:00)
  ('00000101','PC1','entry','2027-03-01 10:00+00'),
  ('00000101','PC2','entry','2027-03-02 09:00+00'),
  ('00000101','PC2','exit', '2027-03-02 11:00+00'),
  -- Caso 4: entrada+salida en PC1, solo salida en PC2
  ('00000104','PC1','entry','2027-03-01 08:00+00'),
  ('00000104','PC1','exit', '2027-03-01 09:00+00'),
  ('00000104','PC2','exit', '2027-03-02 10:00+00'),
  -- Caso 5: un solo centro con entrada+salida (sin SLA en PC1)
  ('00000105','PC1','entry','2027-03-01 08:00+00'),
  ('00000105','PC1','exit', '2027-03-01 09:30+00');

INSERT INTO public.processed_events (account_id, tag_id, reader_id, postal_center_id, event_type, timestamp, analysis_datetime,
  postal_center_code_snapshot, postal_center_name_snapshot, postal_center_city_snapshot, reader_id_snapshot, reader_type_snapshot,
  carrier_id, product_id, origin_city_name, destination_city_name, is_consolidated)
SELECT 'a0000000-0000-0000-0000-000000000001', e.tag, r.id, pc.id, e.et, e.ts, e.ts,
       pc.code, pc.name, pc.city, r.reader_id, r.type,
       'ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001','City1','City2', false
FROM ev e
JOIN public.postal_centers pc ON pc.code = e.pc AND pc.account_id = 'a0000000-0000-0000-0000-000000000001'
JOIN public.readers r ON r.postal_center_id = pc.id;

SELECT * FROM public.reconstruct_journeys('a0000000-0000-0000-0000-000000000001');

DO $$
DECLARE
  s RECORD;
  v_n int;
  v_ev_pc1_entry bigint; v_ev_pc2_entry bigint;
BEGIN
  -- ===== Caso 1: 1 transito PC1->PC2 + 1 operativo PC2 =====
  SELECT count(*) INTO v_n FROM public.journey_segments WHERE tag_id = '00000101';
  IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL c1: esperados 2 tramos, hay %', v_n; END IF;

  SELECT id INTO v_ev_pc1_entry FROM public.processed_events WHERE tag_id='00000101' AND postal_center_code_snapshot='PC1' AND event_type='entry';
  SELECT id INTO v_ev_pc2_entry FROM public.processed_events WHERE tag_id='00000101' AND postal_center_code_snapshot='PC2' AND event_type='entry';

  SELECT * INTO s FROM public.journey_segments WHERE tag_id = '00000101' AND segment_type = 'distribution';
  IF s.id IS NULL THEN RAISE EXCEPTION 'FAIL c1: no hay tramo de transito desde la lectura suelta'; END IF;
  IF s.from_postal_center_id <> 'd1000000-0000-0000-0000-000000000001' OR s.to_postal_center_id <> 'd2000000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'FAIL c1: transito from/to incorrectos'; END IF;
  IF s.entry_event_id <> v_ev_pc1_entry OR s.exit_event_id <> v_ev_pc2_entry THEN
    RAISE EXCEPTION 'FAIL c1: ids de evento del transito % / %', s.entry_event_id, s.exit_event_id; END IF;
  IF s.entry_timestamp <> '2027-03-01 10:00+00' OR s.exit_timestamp <> '2027-03-02 09:00+00' THEN
    RAISE EXCEPTION 'FAIL c1: tiempos del transito % -> %', s.entry_timestamp, s.exit_timestamp; END IF;
  IF s.natural_transit_time_minutes <> 1380 OR s.working_transit_time_minutes <> 1380 THEN
    RAISE EXCEPTION 'FAIL c1: transito natural % laborable % (esperado 1380/1380)', s.natural_transit_time_minutes, s.working_transit_time_minutes; END IF;
  IF s.from_postal_center_city <> 'City1' OR s.to_postal_center_city <> 'City2'
     OR s.origin_city_name <> 'City1' OR s.destination_city_name <> 'City2'
     OR s.carrier_id <> 'ca000000-0000-0000-0000-000000000001' OR s.product_id <> 'cb000000-0000-0000-0000-000000000001'
     OR s.carrier_name_snapshot <> 'Carrier' OR s.product_name <> 'PR' THEN
    RAISE EXCEPTION 'FAIL c1: enriquecimiento del transito incompleto'; END IF;
  IF s.sla_compliance <> 'no_sla' THEN RAISE EXCEPTION 'FAIL c1: transito sin SLA debe ser no_sla, es %', s.sla_compliance; END IF;

  SELECT * INTO s FROM public.journey_segments WHERE tag_id = '00000101' AND segment_type = 'operational';
  IF s.postal_center_id <> 'd2000000-0000-0000-0000-000000000002' THEN RAISE EXCEPTION 'FAIL c1: operativo en centro equivocado'; END IF;
  IF s.natural_time_in_center_minutes <> 120 OR s.working_time_in_center_minutes <> 120 THEN
    RAISE EXCEPTION 'FAIL c1: operativo natural % laborable % (esperado 120/120)', s.natural_time_in_center_minutes, s.working_time_in_center_minutes; END IF;
  IF s.sla_id IS NULL OR s.expected_time_minutes <> 120 OR s.sla_compliance <> 'on_time' THEN
    RAISE EXCEPTION 'FAIL c1: SLA operativo PC2 no aplicado (% / % / %)', s.sla_id, s.expected_time_minutes, s.sla_compliance; END IF;
  IF s.from_postal_center_city <> 'City2' OR s.origin_city_name <> 'City1' OR s.product_id IS NULL THEN
    RAISE EXCEPTION 'FAIL c1: enriquecimiento del operativo incompleto'; END IF;

  -- todos los eventos consolidados (tambien la lectura suelta)
  SELECT count(*) INTO v_n FROM public.processed_events
   WHERE account_id='a0000000-0000-0000-0000-000000000001' AND is_consolidated = false;
  IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: % eventos siguen sin consolidar', v_n; END IF;

  -- ===== Caso 4: operativo PC1 + transito PC1->PC2 (solo salida en PC2), sin operativo PC2 =====
  SELECT count(*) INTO v_n FROM public.journey_segments WHERE tag_id = '00000104';
  IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL c4: esperados 2 tramos, hay %', v_n; END IF;
  SELECT * INTO s FROM public.journey_segments WHERE tag_id = '00000104' AND segment_type = 'operational';
  IF s.postal_center_id <> 'd1000000-0000-0000-0000-000000000001' OR s.natural_time_in_center_minutes <> 60 THEN
    RAISE EXCEPTION 'FAIL c4: operativo PC1 incorrecto'; END IF;
  IF s.next_entry_timestamp <> '2027-03-02 10:00+00' THEN
    RAISE EXCEPTION 'FAIL c4: next_entry_timestamp = %', s.next_entry_timestamp; END IF;
  SELECT * INTO s FROM public.journey_segments WHERE tag_id = '00000104' AND segment_type = 'distribution';
  IF s.entry_timestamp <> '2027-03-01 09:00+00' OR s.exit_timestamp <> '2027-03-02 10:00+00' OR s.natural_transit_time_minutes <> 1500 THEN
    RAISE EXCEPTION 'FAIL c4: transito % -> % (%)', s.entry_timestamp, s.exit_timestamp, s.natural_transit_time_minutes; END IF;

  -- ===== Caso 5: un centro, entrada+salida, sin SLA =====
  SELECT count(*) INTO v_n FROM public.journey_segments WHERE tag_id = '00000105';
  IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL c5: esperado 1 tramo, hay %', v_n; END IF;
  SELECT * INTO s FROM public.journey_segments WHERE tag_id = '00000105';
  IF s.segment_type <> 'operational' OR s.natural_time_in_center_minutes <> 90 OR s.sla_compliance <> 'no_sla' OR s.next_entry_timestamp IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL c5: tramo unico incorrecto'; END IF;

  RAISE NOTICE 'PASS casos 1,4,5';
END $$;

-- ===== Caso 2: idempotencia (segunda pasada sin eventos nuevos) =====
CREATE TEMP TABLE before_ids AS SELECT tag_id, segment_type, entry_event_id, exit_event_id FROM public.journey_segments ORDER BY 1,2;
SELECT * FROM public.reconstruct_journeys('a0000000-0000-0000-0000-000000000001');
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM (
    (SELECT tag_id, segment_type, entry_event_id, exit_event_id FROM public.journey_segments
      EXCEPT SELECT * FROM before_ids)
    UNION ALL
    (SELECT * FROM before_ids
      EXCEPT SELECT tag_id, segment_type, entry_event_id, exit_event_id FROM public.journey_segments)) d;
  IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL c2: la segunda pasada cambio % tramos', v_n; END IF;
  RAISE NOTICE 'PASS caso 2';
END $$;

-- ===== Caso 3: lectura tardia (salida de PC1 a las 12:00) =====
INSERT INTO public.processed_events (account_id, tag_id, reader_id, postal_center_id, event_type, timestamp, analysis_datetime,
  postal_center_code_snapshot, postal_center_name_snapshot, postal_center_city_snapshot, reader_id_snapshot, reader_type_snapshot,
  carrier_id, product_id, origin_city_name, destination_city_name, is_consolidated)
VALUES ('a0000000-0000-0000-0000-000000000001','00000101','f1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','exit','2027-03-01 12:00+00','2027-03-01 12:00+00',
        'PC1','Center 1','City1','LPI1','Mixed','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001','City1','City2',false);
SELECT * FROM public.reconstruct_journeys('a0000000-0000-0000-0000-000000000001');
DO $$
DECLARE s RECORD; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.journey_segments WHERE tag_id = '00000101';
  IF v_n <> 3 THEN RAISE EXCEPTION 'FAIL c3: esperados 3 tramos tras la lectura tardia, hay %', v_n; END IF;
  SELECT * INTO s FROM public.journey_segments WHERE tag_id = '00000101' AND segment_type = 'operational' AND postal_center_id = 'd1000000-0000-0000-0000-000000000001';
  IF s.id IS NULL OR s.natural_time_in_center_minutes <> 120 THEN RAISE EXCEPTION 'FAIL c3: operativo PC1 no creado'; END IF;
  SELECT * INTO s FROM public.journey_segments WHERE tag_id = '00000101' AND segment_type = 'distribution';
  IF s.entry_timestamp <> '2027-03-01 12:00+00' OR s.natural_transit_time_minutes <> 1260 THEN
    RAISE EXCEPTION 'FAIL c3: el transito debe empezar en la salida tardia (% / %)', s.entry_timestamp, s.natural_transit_time_minutes; END IF;
  SELECT count(*) INTO v_n FROM public.processed_events WHERE tag_id = '00000101' AND is_consolidated = false;
  IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL c3: lectura tardia sin consolidar'; END IF;
  RAISE NOTICE 'PASS caso 3';
END $$;
ROLLBACK;

-- ===== calculate_working_time_minutes: solapamiento exacto L-V 08:00-17:00 en la zona del centro =====
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO public.postal_centers (id, account_id, code, name, calculation_mode, opening_hour, working_hours_end, timezone) VALUES
  ('d3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','PC3','Center 3','working_days','08:00','17:00','Africa/Nairobi');
DO $$
DECLARE v int;
BEGIN
  -- viernes 2027-03-05 06:30 UTC (09:30 Nairobi) -> lunes 2027-03-08 06:00 UTC (09:00 Nairobi):
  -- viernes 09:30-17:00 = 450 min, fin de semana 0, lunes 08:00-09:00 = 60 min
  v := public.calculate_working_time_minutes('2027-03-05 06:30+00','2027-03-08 06:00+00','d3000000-0000-0000-0000-000000000003');
  IF v <> 510 THEN RAISE EXCEPTION 'FAIL working: esperado 510, es %', v; END IF;
  -- fuera de horario por completo -> 0
  v := public.calculate_working_time_minutes('2027-03-06 06:00+00','2027-03-06 08:00+00','d3000000-0000-0000-0000-000000000003');
  IF v <> 0 THEN RAISE EXCEPTION 'FAIL working sabado: esperado 0, es %', v; END IF;
  -- fin antes del inicio -> 0
  v := public.calculate_working_time_minutes('2027-03-08 06:00+00','2027-03-05 06:00+00','d3000000-0000-0000-0000-000000000003');
  IF v <> 0 THEN RAISE EXCEPTION 'FAIL working invertido: esperado 0, es %', v; END IF;
  RAISE NOTICE 'PASS calculate_working_time_minutes';
END $$;
ROLLBACK;
