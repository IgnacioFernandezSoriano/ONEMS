-- Viajes y tramos deben llevar ciudad origen/destino, transportista y producto
-- copiados de processed_events; y un evento leido antes de registrar la etiqueta
-- se enriquece en la pasada siguiente (reenrich_processed_events).
BEGIN;
\ir fixtures/incident_city.sql

INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','PC2','Center 2','City2','c2000000-0000-0000-0000-000000000002');
INSERT INTO public.readers (id, account_id, postal_center_id, reader_id, name, type) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','LPI1','R1','Mixed'),
  ('f2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000002','LPI2','R2','Mixed');

-- Etiqueta A: registrada ANTES de leerse -> la consolidacion ya enriquecio los eventos
INSERT INTO public.one_db (account_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name, sent_at, received_at, total_transit_days, source_data_snapshot)
VALUES ('a0000000-0000-0000-0000-000000000001','00000001','Mar27','Carrier','PR','City1','City2','2027-03-01 08:00+00','2027-03-03 08:00+00',2,'{}');

INSERT INTO public.processed_events (account_id, tag_id, reader_id, postal_center_id, event_type, timestamp, analysis_datetime,
  postal_center_code_snapshot, postal_center_name_snapshot, postal_center_city_snapshot, reader_id_snapshot, reader_type_snapshot,
  carrier_id, product_id, origin_city_name, destination_city_name, is_consolidated)
VALUES
  ('a0000000-0000-0000-0000-000000000001','00000001','f1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','entry','2027-03-01 08:00+00','2027-03-01 08:00+00','PC1','Center 1','City1','LPI1','Mixed','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001','City1','City2',false),
  ('a0000000-0000-0000-0000-000000000001','00000001','f1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','exit', '2027-03-01 10:00+00','2027-03-01 10:00+00','PC1','Center 1','City1','LPI1','Mixed','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001','City1','City2',false),
  ('a0000000-0000-0000-0000-000000000001','00000001','f2000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000002','entry','2027-03-02 20:00+00','2027-03-02 20:00+00','PC2','Center 2','City2','LPI2','Mixed','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001','City1','City2',false),
  ('a0000000-0000-0000-0000-000000000001','00000001','f2000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000002','exit', '2027-03-02 22:00+00','2027-03-02 22:00+00','PC2','Center 2','City2','LPI2','Mixed','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001','City1','City2',false);

-- Etiqueta B: leida ANTES de registrarse -> eventos sin enriquecer; el registro llega despues
INSERT INTO public.processed_events (account_id, tag_id, reader_id, postal_center_id, event_type, timestamp, analysis_datetime,
  postal_center_code_snapshot, postal_center_name_snapshot, postal_center_city_snapshot, reader_id_snapshot, reader_type_snapshot, is_consolidated)
VALUES
  ('a0000000-0000-0000-0000-000000000001','00000002','f1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','entry','2027-03-05 08:00+00','2027-03-05 08:00+00','PC1','Center 1','City1','LPI1','Mixed',false),
  ('a0000000-0000-0000-0000-000000000001','00000002','f1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','exit', '2027-03-05 09:00+00','2027-03-05 09:00+00','PC1','Center 1','City1','LPI1','Mixed',false);
INSERT INTO public.one_db (account_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name, sent_at, received_at, total_transit_days, source_data_snapshot)
VALUES ('a0000000-0000-0000-0000-000000000001','00000002','Mar27','Carrier','PR','City2','City1','2027-03-05 07:00+00','2027-03-06 08:00+00',1,'{}');

-- Pipeline completo de la cuenta (la consolidacion no tiene eventos crudos: 0)
DO $$
DECLARE
  r RECORD;
  v_phases text := '';
BEGIN
  FOR r IN SELECT * FROM public.process_rfid_pipeline('a0000000-0000-0000-0000-000000000001') LOOP
    v_phases := v_phases || r.phase || '=' || r.status || ' ';
    IF r.status <> 'success' THEN
      RAISE EXCEPTION 'FAIL: fase % con estado % (%)', r.phase, r.status, r.message;
    END IF;
  END LOOP;
  IF v_phases NOT LIKE '%enrichment=success%' OR v_phases NOT LIKE '%propagation=success%' THEN
    RAISE EXCEPTION 'FAIL: faltan fases nuevas: %', v_phases;
  END IF;
  RAISE NOTICE 'fases: %', v_phases;
END $$;

DO $$
DECLARE
  j RECORD;
  v_bad int;
  v_dist RECORD;
BEGIN
  -- Viaje A
  SELECT * INTO j FROM public.journeys
   WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND tag_id = '00000001';
  IF j.id IS NULL THEN RAISE EXCEPTION 'FAIL: no se creo el viaje A'; END IF;
  IF j.origin_city_name IS DISTINCT FROM 'City1' OR j.destination_city_name IS DISTINCT FROM 'City2' THEN
    RAISE EXCEPTION 'FAIL: viaje A ciudades % -> %', j.origin_city_name, j.destination_city_name;
  END IF;
  IF j.origin_city_id IS DISTINCT FROM 'c1000000-0000-0000-0000-000000000001'
     OR j.destination_city_id IS DISTINCT FROM 'c2000000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'FAIL: viaje A ids de ciudad % -> %', j.origin_city_id, j.destination_city_id;
  END IF;
  IF j.product_id IS DISTINCT FROM 'cb000000-0000-0000-0000-000000000001' OR j.product_name IS DISTINCT FROM 'PR' THEN
    RAISE EXCEPTION 'FAIL: viaje A producto % / %', j.product_id, j.product_name;
  END IF;

  -- Tramos A: 2 operational + 1 distribution, todos enriquecidos
  SELECT count(*) INTO v_bad FROM public.journey_segments
   WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND tag_id = '00000001'
     AND (origin_city_name IS DISTINCT FROM 'City1' OR destination_city_name IS DISTINCT FROM 'City2'
          OR carrier_id IS DISTINCT FROM 'ca000000-0000-0000-0000-000000000001'
          OR product_id IS DISTINCT FROM 'cb000000-0000-0000-0000-000000000001'
          OR carrier_name_snapshot IS DISTINCT FROM 'Carrier' OR product_name IS DISTINCT FROM 'PR');
  IF v_bad <> 0 THEN RAISE EXCEPTION 'FAIL: % tramos de A sin enriquecer', v_bad; END IF;

  SELECT * INTO v_dist FROM public.journey_segments
   WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND tag_id = '00000001' AND segment_type = 'distribution';
  IF v_dist.id IS NULL THEN RAISE EXCEPTION 'FAIL: no hay tramo de distribucion para A'; END IF;
  IF v_dist.from_postal_center_city IS DISTINCT FROM 'City1' OR v_dist.to_postal_center_city IS DISTINCT FROM 'City2' THEN
    RAISE EXCEPTION 'FAIL: tramo distribucion ciudades de centro % -> %', v_dist.from_postal_center_city, v_dist.to_postal_center_city;
  END IF;

  -- Etiqueta B: eventos reenriquecidos y viaje con ciudades
  SELECT count(*) INTO v_bad FROM public.processed_events
   WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND tag_id = '00000002'
     AND (origin_city_name IS DISTINCT FROM 'City2' OR destination_city_name IS DISTINCT FROM 'City1'
          OR carrier_id IS DISTINCT FROM 'ca000000-0000-0000-0000-000000000001'
          OR product_id IS DISTINCT FROM 'cb000000-0000-0000-0000-000000000001');
  IF v_bad <> 0 THEN RAISE EXCEPTION 'FAIL: % eventos de B sin reenriquecer', v_bad; END IF;

  SELECT * INTO j FROM public.journeys
   WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND tag_id = '00000002';
  IF j.origin_city_name IS DISTINCT FROM 'City2' OR j.destination_city_id IS DISTINCT FROM 'c1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL: viaje B % -> % (id destino %)', j.origin_city_name, j.destination_city_name, j.destination_city_id;
  END IF;

  -- Segunda pasada: idempotente (nada que actualizar)
  SELECT segments_updated + journeys_updated INTO v_bad
    FROM public.propagate_journey_enrichment('a0000000-0000-0000-0000-000000000001');
  IF v_bad <> 0 THEN RAISE EXCEPTION 'FAIL: segunda pasada actualizo % filas', v_bad; END IF;

  RAISE NOTICE 'PASS: journeys_origin_destination';
END $$;
ROLLBACK;

-- Producto casado por DESCRIPCION (caso Kenya: one_db.product_name = descripcion)
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001');
INSERT INTO public.readers (id, account_id, postal_center_id, reader_id, name, type) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','LPI1','R1','Mixed');
-- evento ya enriquecido con ciudad pero sin producto (como quedaron los de Kenya)
INSERT INTO public.processed_events (account_id, tag_id, reader_id, postal_center_id, event_type, timestamp, analysis_datetime,
  postal_center_code_snapshot, postal_center_name_snapshot, postal_center_city_snapshot, reader_id_snapshot, reader_type_snapshot,
  carrier_id, origin_city_name, destination_city_name, is_consolidated)
VALUES
  ('a0000000-0000-0000-0000-000000000001','00000003','f1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','entry','2027-03-07 08:00+00','2027-03-07 08:00+00','PC1','Center 1','City1','LPI1','Mixed','ca000000-0000-0000-0000-000000000001','City1','City2',false),
  ('a0000000-0000-0000-0000-000000000001','00000003','f1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','exit', '2027-03-07 09:00+00','2027-03-07 09:00+00','PC1','Center 1','City1','LPI1','Mixed','ca000000-0000-0000-0000-000000000001','City1','City2',false);
INSERT INTO public.one_db (account_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name, sent_at, received_at, total_transit_days, source_data_snapshot)
VALUES ('a0000000-0000-0000-0000-000000000001','00000003','Mar27','Carrier','Prod','City1','City2','2027-03-07 07:00+00','2027-03-08 08:00+00',1,'{}');

DO $$
DECLARE
  v_n int;
  j RECORD;
BEGIN
  PERFORM public.process_rfid_pipeline('a0000000-0000-0000-0000-000000000001');
  SELECT count(*) INTO v_n FROM public.processed_events
   WHERE tag_id = '00000003' AND product_id IS DISTINCT FROM 'cb000000-0000-0000-0000-000000000001';
  IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: % eventos sin producto casado por descripcion', v_n; END IF;
  SELECT * INTO j FROM public.journeys WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND tag_id = '00000003';
  IF j.product_id IS DISTINCT FROM 'cb000000-0000-0000-0000-000000000001' OR j.product_name IS DISTINCT FROM 'PR' THEN
    RAISE EXCEPTION 'FAIL: viaje sin producto (% / %)', j.product_id, j.product_name;
  END IF;
  RAISE NOTICE 'PASS: producto por descripcion';
END $$;
ROLLBACK;
