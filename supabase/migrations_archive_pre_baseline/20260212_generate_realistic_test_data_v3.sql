-- Generate Realistic Test Data for DEMO2 (v3 - Final)
-- Uses validated schema: operational segments, all NOT NULL fields
-- 268 journeys across 6 routes with real DEMO2 centers and carriers

DO $$
DECLARE
  v_account_id UUID := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  
  v_carrier_a UUID := '856b4a5c-1716-4110-ac5e-0d7c909b9237';
  v_carrier_b UUID := '5ea9f7ed-a96c-4f3c-b849-05dc80e3ca67';
  v_fedex UUID := '1995c98c-1d30-4aef-8932-a8beef42b737';
  v_usps UUID := '3d1c5be9-6508-43ab-b72e-67e82d23a133';
  
  v_ny_central UUID := '550ecbb1-8913-47b4-bfdd-83b7507aa250';
  v_ny_jfk UUID := '87849c18-1e99-4235-851b-64983f0bba3b';
  v_la_downtown UUID := '0c2c5ddc-2880-4fa3-bc98-71a8d8c012de';
  v_la_lax UUID := '2f2512da-b93b-4826-a42d-e1d6756a6617';
  v_chicago UUID := 'e8140721-3ea0-4020-a6c7-8fdec763840b';
  v_sfo UUID := 'fb7acd54-3ccf-4db4-8c1c-b0e702529f7c';
  v_baltimore_reg UUID := '9354a2dc-58e3-4473-bcd6-282f5f88e418';
  v_philadelphia UUID := 'ce0a2156-ab2f-46cb-9c28-73bb7d10bbfa';
  v_denver UUID := '1b51813b-cf8e-4e16-a5d0-d883fd348e7a';
  v_sacramento UUID := '154562a9-ca4c-40d6-b104-a7fa53877307';
  
  v_journey_id BIGINT;
  v_base_date TIMESTAMP WITH TIME ZONE;
  v_entry_time TIMESTAMP WITH TIME ZONE;
  v_exit_time TIMESTAMP WITH TIME ZONE;
  v_transit_minutes INTEGER;
  v_is_on_time BOOLEAN;
  v_distribution_minutes INTEGER;
  i INTEGER;
BEGIN
  v_base_date := NOW() - INTERVAL '30 days';
  
  RAISE NOTICE 'Generating 268 journeys across 6 routes...';

  -- ROUTE 1: NY -> LA via FedEx (92% on-time, 60 journeys)
  FOR i IN 1..60 LOOP
    v_journey_id := (EXTRACT(EPOCH FROM NOW()) * 1000000 + i)::BIGINT;
    v_entry_time := v_base_date + (i * 12 || ' hours')::INTERVAL;
    v_transit_minutes := 2880 + floor(random() * 240)::INTEGER;
    v_is_on_time := (random() < 0.92);
    IF NOT v_is_on_time THEN v_transit_minutes := 3300 + floor(random() * 300)::INTEGER; END IF;
    v_exit_time := v_entry_time + (v_transit_minutes || ' minutes')::INTERVAL;
    v_distribution_minutes := v_transit_minutes - 85;

    INSERT INTO journeys (id, account_id, tag_id, origin_city_name, destination_city_name, route_path,
      first_event_timestamp, last_event_timestamp, journey_status, total_actual_time_minutes,
      total_distribution_time_minutes, total_sla_violations, is_missroute, total_segments, on_time_segments)
    VALUES (v_journey_id, v_account_id, 'NY-LA-' || i, 'New York', 'Los Angeles', '[]'::jsonb,
      v_entry_time, v_exit_time, 'completed', v_transit_minutes, v_distribution_minutes,
      CASE WHEN v_is_on_time THEN 0 ELSE 1 END, FALSE, 3, CASE WHEN v_is_on_time THEN 3 ELSE 2 END);

    INSERT INTO journey_segments (account_id, tag_id, segment_type, postal_center_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'NY-LA-' || i, 'operational', v_ny_central,
      v_entry_time, v_entry_time + INTERVAL '45 minutes', v_entry_time, v_entry_time + INTERVAL '45 minutes',
      45, 45, 0, 'on_time');

    INSERT INTO journey_segments (account_id, tag_id, segment_type,
      from_postal_center_id, to_postal_center_id, carrier_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'NY-LA-' || i, 'distribution', v_ny_central, v_la_downtown, v_fedex,
      v_entry_time + INTERVAL '45 minutes', v_exit_time - INTERVAL '40 minutes',
      v_entry_time + INTERVAL '45 minutes', v_exit_time - INTERVAL '40 minutes',
      v_distribution_minutes, v_distribution_minutes, 0, CASE WHEN v_is_on_time THEN 'on_time' ELSE 'violated' END);

    INSERT INTO journey_segments (account_id, tag_id, segment_type, postal_center_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'NY-LA-' || i, 'operational', v_la_downtown,
      v_exit_time - INTERVAL '40 minutes', v_exit_time, v_exit_time - INTERVAL '40 minutes', v_exit_time,
      40, 40, 0, 'on_time');
  END LOOP;

  -- ROUTE 2: LA -> Chicago via USPS (78% on-time, 50 journeys)
  FOR i IN 1..50 LOOP
    v_journey_id := (EXTRACT(EPOCH FROM NOW()) * 1000000 + 100000 + i)::BIGINT;
    v_entry_time := v_base_date + (i * 14 || ' hours')::INTERVAL;
    v_transit_minutes := 1800 + floor(random() * 240)::INTEGER;
    v_is_on_time := (random() < 0.78);
    IF NOT v_is_on_time THEN v_transit_minutes := 2400 + floor(random() * 360)::INTEGER; END IF;
    v_exit_time := v_entry_time + (v_transit_minutes || ' minutes')::INTERVAL;
    v_distribution_minutes := v_transit_minutes - 65;

    INSERT INTO journeys (id, account_id, tag_id, origin_city_name, destination_city_name, route_path,
      first_event_timestamp, last_event_timestamp, journey_status, total_actual_time_minutes,
      total_distribution_time_minutes, total_sla_violations, is_missroute, total_segments, on_time_segments)
    VALUES (v_journey_id, v_account_id, 'LA-CHI-' || i, 'Los Angeles', 'Chicago', '[]'::jsonb,
      v_entry_time, v_exit_time, 'completed', v_transit_minutes, v_distribution_minutes,
      CASE WHEN v_is_on_time THEN 0 ELSE 1 END, FALSE, 3, CASE WHEN v_is_on_time THEN 3 ELSE 2 END);

    INSERT INTO journey_segments (account_id, tag_id, segment_type, postal_center_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'LA-CHI-' || i, 'operational', v_la_lax,
      v_entry_time, v_entry_time + INTERVAL '35 minutes', v_entry_time, v_entry_time + INTERVAL '35 minutes',
      35, 35, 0, 'on_time');

    INSERT INTO journey_segments (account_id, tag_id, segment_type,
      from_postal_center_id, to_postal_center_id, carrier_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'LA-CHI-' || i, 'distribution', v_la_lax, v_chicago, v_usps,
      v_entry_time + INTERVAL '35 minutes', v_exit_time - INTERVAL '30 minutes',
      v_entry_time + INTERVAL '35 minutes', v_exit_time - INTERVAL '30 minutes',
      v_distribution_minutes, v_distribution_minutes, 0, CASE WHEN v_is_on_time THEN 'on_time' ELSE 'violated' END);

    INSERT INTO journey_segments (account_id, tag_id, segment_type, postal_center_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'LA-CHI-' || i, 'operational', v_chicago,
      v_exit_time - INTERVAL '30 minutes', v_exit_time, v_exit_time - INTERVAL '30 minutes', v_exit_time,
      30, 30, 0, 'on_time');
  END LOOP;

  -- ROUTE 3: Chicago -> Queens via Carrier B (65% on-time, 45 journeys)
  FOR i IN 1..45 LOOP
    v_journey_id := (EXTRACT(EPOCH FROM NOW()) * 1000000 + 200000 + i)::BIGINT;
    v_entry_time := v_base_date + (i * 16 || ' hours')::INTERVAL;
    v_transit_minutes := 1200 + floor(random() * 180)::INTEGER;
    v_is_on_time := (random() < 0.65);
    IF NOT v_is_on_time THEN v_transit_minutes := 1680 + floor(random() * 360)::INTEGER; END IF;
    v_exit_time := v_entry_time + (v_transit_minutes || ' minutes')::INTERVAL;
    v_distribution_minutes := v_transit_minutes - 85;

    INSERT INTO journeys (id, account_id, tag_id, origin_city_name, destination_city_name, route_path,
      first_event_timestamp, last_event_timestamp, journey_status, total_actual_time_minutes,
      total_distribution_time_minutes, total_sla_violations, is_missroute, total_segments, on_time_segments)
    VALUES (v_journey_id, v_account_id, 'CHI-NY-' || i, 'Chicago', 'Queens', '[]'::jsonb,
      v_entry_time, v_exit_time, 'completed', v_transit_minutes, v_distribution_minutes,
      CASE WHEN v_is_on_time THEN 0 ELSE 1 END, FALSE, 3, CASE WHEN v_is_on_time THEN 3 ELSE 2 END);

    INSERT INTO journey_segments (account_id, tag_id, segment_type, postal_center_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'CHI-NY-' || i, 'operational', v_chicago,
      v_entry_time, v_entry_time + INTERVAL '50 minutes', v_entry_time, v_entry_time + INTERVAL '50 minutes',
      50, 50, 0, 'on_time');

    INSERT INTO journey_segments (account_id, tag_id, segment_type,
      from_postal_center_id, to_postal_center_id, carrier_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'CHI-NY-' || i, 'distribution', v_chicago, v_ny_jfk, v_carrier_b,
      v_entry_time + INTERVAL '50 minutes', v_exit_time - INTERVAL '35 minutes',
      v_entry_time + INTERVAL '50 minutes', v_exit_time - INTERVAL '35 minutes',
      v_distribution_minutes, v_distribution_minutes, 0, CASE WHEN v_is_on_time THEN 'on_time' ELSE 'violated' END);

    INSERT INTO journey_segments (account_id, tag_id, segment_type, postal_center_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'CHI-NY-' || i, 'operational', v_ny_jfk,
      v_exit_time - INTERVAL '35 minutes', v_exit_time, v_exit_time - INTERVAL '35 minutes', v_exit_time,
      35, 35, 0, 'on_time');
  END LOOP;

  -- ROUTE 4: SF -> Sacramento via Carrier A (94% on-time, 40 journeys)
  FOR i IN 1..40 LOOP
    v_journey_id := (EXTRACT(EPOCH FROM NOW()) * 1000000 + 300000 + i)::BIGINT;
    v_entry_time := v_base_date + (i * 18 || ' hours')::INTERVAL;
    v_transit_minutes := 180 + floor(random() * 60)::INTEGER;
    v_is_on_time := (random() < 0.94);
    IF NOT v_is_on_time THEN v_transit_minutes := 300 + floor(random() * 120)::INTEGER; END IF;
    v_exit_time := v_entry_time + (v_transit_minutes || ' minutes')::INTERVAL;
    v_distribution_minutes := v_transit_minutes - 35;

    INSERT INTO journeys (id, account_id, tag_id, origin_city_name, destination_city_name, route_path,
      first_event_timestamp, last_event_timestamp, journey_status, total_actual_time_minutes,
      total_distribution_time_minutes, total_sla_violations, is_missroute, total_segments, on_time_segments)
    VALUES (v_journey_id, v_account_id, 'SFO-SAC-' || i, 'San Francisco', 'Sacramento', '[]'::jsonb,
      v_entry_time, v_exit_time, 'completed', v_transit_minutes, v_distribution_minutes,
      CASE WHEN v_is_on_time THEN 0 ELSE 1 END, FALSE, 3, CASE WHEN v_is_on_time THEN 3 ELSE 2 END);

    INSERT INTO journey_segments (account_id, tag_id, segment_type, postal_center_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'SFO-SAC-' || i, 'operational', v_sfo,
      v_entry_time, v_entry_time + INTERVAL '20 minutes', v_entry_time, v_entry_time + INTERVAL '20 minutes',
      20, 20, 0, 'on_time');

    INSERT INTO journey_segments (account_id, tag_id, segment_type,
      from_postal_center_id, to_postal_center_id, carrier_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'SFO-SAC-' || i, 'distribution', v_sfo, v_sacramento, v_carrier_a,
      v_entry_time + INTERVAL '20 minutes', v_exit_time - INTERVAL '15 minutes',
      v_entry_time + INTERVAL '20 minutes', v_exit_time - INTERVAL '15 minutes',
      v_distribution_minutes, v_distribution_minutes, 0, CASE WHEN v_is_on_time THEN 'on_time' ELSE 'violated' END);

    INSERT INTO journey_segments (account_id, tag_id, segment_type, postal_center_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'SFO-SAC-' || i, 'operational', v_sacramento,
      v_exit_time - INTERVAL '15 minutes', v_exit_time, v_exit_time - INTERVAL '15 minutes', v_exit_time,
      15, 15, 0, 'on_time');
  END LOOP;

  -- ROUTE 5: Baltimore -> Philadelphia via USPS (72% on-time, 35 journeys)
  FOR i IN 1..35 LOOP
    v_journey_id := (EXTRACT(EPOCH FROM NOW()) * 1000000 + 400000 + i)::BIGINT;
    v_entry_time := v_base_date + (i * 20 || ' hours')::INTERVAL;
    v_transit_minutes := 240 + floor(random() * 60)::INTEGER;
    v_is_on_time := (random() < 0.72);
    IF NOT v_is_on_time THEN v_transit_minutes := 360 + floor(random() * 120)::INTEGER; END IF;
    v_exit_time := v_entry_time + (v_transit_minutes || ' minutes')::INTERVAL;
    v_distribution_minutes := v_transit_minutes - 45;

    INSERT INTO journeys (id, account_id, tag_id, origin_city_name, destination_city_name, route_path,
      first_event_timestamp, last_event_timestamp, journey_status, total_actual_time_minutes,
      total_distribution_time_minutes, total_sla_violations, is_missroute, total_segments, on_time_segments)
    VALUES (v_journey_id, v_account_id, 'BAL-PHL-' || i, 'Baltimore', 'Philadelphia', '[]'::jsonb,
      v_entry_time, v_exit_time, 'completed', v_transit_minutes, v_distribution_minutes,
      CASE WHEN v_is_on_time THEN 0 ELSE 1 END, FALSE, 3, CASE WHEN v_is_on_time THEN 3 ELSE 2 END);

    INSERT INTO journey_segments (account_id, tag_id, segment_type, postal_center_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'BAL-PHL-' || i, 'operational', v_baltimore_reg,
      v_entry_time, v_entry_time + INTERVAL '25 minutes', v_entry_time, v_entry_time + INTERVAL '25 minutes',
      25, 25, 0, 'on_time');

    INSERT INTO journey_segments (account_id, tag_id, segment_type,
      from_postal_center_id, to_postal_center_id, carrier_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'BAL-PHL-' || i, 'distribution', v_baltimore_reg, v_philadelphia, v_usps,
      v_entry_time + INTERVAL '25 minutes', v_exit_time - INTERVAL '20 minutes',
      v_entry_time + INTERVAL '25 minutes', v_exit_time - INTERVAL '20 minutes',
      v_distribution_minutes, v_distribution_minutes, 0, CASE WHEN v_is_on_time THEN 'on_time' ELSE 'violated' END);

    INSERT INTO journey_segments (account_id, tag_id, segment_type, postal_center_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'BAL-PHL-' || i, 'operational', v_philadelphia,
      v_exit_time - INTERVAL '20 minutes', v_exit_time, v_exit_time - INTERVAL '20 minutes', v_exit_time,
      20, 20, 0, 'on_time');
  END LOOP;

  -- ROUTE 6: Denver -> SF via FedEx (85% on-time, 38 journeys)
  FOR i IN 1..38 LOOP
    v_journey_id := (EXTRACT(EPOCH FROM NOW()) * 1000000 + 500000 + i)::BIGINT;
    v_entry_time := v_base_date + (i * 19 || ' hours')::INTERVAL;
    v_transit_minutes := 1080 + floor(random() * 120)::INTEGER;
    v_is_on_time := (random() < 0.85);
    IF NOT v_is_on_time THEN v_transit_minutes := 1440 + floor(random() * 240)::INTEGER; END IF;
    v_exit_time := v_entry_time + (v_transit_minutes || ' minutes')::INTERVAL;
    v_distribution_minutes := v_transit_minutes - 55;

    INSERT INTO journeys (id, account_id, tag_id, origin_city_name, destination_city_name, route_path,
      first_event_timestamp, last_event_timestamp, journey_status, total_actual_time_minutes,
      total_distribution_time_minutes, total_sla_violations, is_missroute, total_segments, on_time_segments)
    VALUES (v_journey_id, v_account_id, 'DEN-SFO-' || i, 'Denver', 'San Francisco', '[]'::jsonb,
      v_entry_time, v_exit_time, 'completed', v_transit_minutes, v_distribution_minutes,
      CASE WHEN v_is_on_time THEN 0 ELSE 1 END, FALSE, 3, CASE WHEN v_is_on_time THEN 3 ELSE 2 END);

    INSERT INTO journey_segments (account_id, tag_id, segment_type, postal_center_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'DEN-SFO-' || i, 'operational', v_denver,
      v_entry_time, v_entry_time + INTERVAL '30 minutes', v_entry_time, v_entry_time + INTERVAL '30 minutes',
      30, 30, 0, 'on_time');

    INSERT INTO journey_segments (account_id, tag_id, segment_type,
      from_postal_center_id, to_postal_center_id, carrier_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'DEN-SFO-' || i, 'distribution', v_denver, v_sfo, v_fedex,
      v_entry_time + INTERVAL '30 minutes', v_exit_time - INTERVAL '25 minutes',
      v_entry_time + INTERVAL '30 minutes', v_exit_time - INTERVAL '25 minutes',
      v_distribution_minutes, v_distribution_minutes, 0, CASE WHEN v_is_on_time THEN 'on_time' ELSE 'violated' END);

    INSERT INTO journey_segments (account_id, tag_id, segment_type, postal_center_id,
      entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
      actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes, sla_compliance)
    VALUES (v_account_id, 'DEN-SFO-' || i, 'operational', v_sfo,
      v_exit_time - INTERVAL '25 minutes', v_exit_time, v_exit_time - INTERVAL '25 minutes', v_exit_time,
      25, 25, 0, 'on_time');
  END LOOP;

  RAISE NOTICE 'SUCCESS: 268 journeys generated across 6 routes';
  RAISE NOTICE 'Routes: NY-LA(60), LA-CHI(50), CHI-NY(45), SFO-SAC(40), BAL-PHL(35), DEN-SFO(38)';
  RAISE NOTICE 'Performance: 92%%, 78%%, 65%%, 94%%, 72%%, 85%%';
END $$;
