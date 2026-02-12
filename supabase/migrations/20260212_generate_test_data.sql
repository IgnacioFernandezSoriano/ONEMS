-- Generate Synthetic Test Data for Route Analysis and Network Overview
-- Creates diverse scenarios: good performance, poor performance, mixed carriers, multiple routes

-- This script generates realistic test data for DEMO2 account
-- Scenarios:
-- 1. High-performing routes (90%+ on-time)
-- 2. Medium-performing routes (70-90% on-time)
-- 3. Poor-performing routes (<70% on-time)
-- 4. Multiple carriers with different performance levels
-- 5. Various route combinations between centers

DO $$
DECLARE
  v_account_id UUID;
  v_carrier_fedex UUID;
  v_carrier_dhl UUID;
  v_carrier_ups UUID;
  v_center_madrid UUID;
  v_center_barcelona UUID;
  v_center_valencia UUID;
  v_center_sevilla UUID;
  v_journey_id UUID;
  v_segment_id UUID;
  v_base_date TIMESTAMP WITH TIME ZONE;
  v_entry_time TIMESTAMP WITH TIME ZONE;
  v_exit_time TIMESTAMP WITH TIME ZONE;
  v_transit_minutes INTEGER;
  v_sla_minutes INTEGER;
  v_is_on_time BOOLEAN;
  i INTEGER;
BEGIN
  -- Get DEMO2 account
  SELECT id INTO v_account_id FROM accounts WHERE slug = 'DEMO2';
  
  IF v_account_id IS NULL THEN
    RAISE EXCEPTION 'DEMO2 account not found';
  END IF;

  -- Get carriers
  SELECT id INTO v_carrier_fedex FROM carriers WHERE account_id = v_account_id AND name = 'FedEx';
  SELECT id INTO v_carrier_dhl FROM carriers WHERE account_id = v_account_id AND name = 'DHL';
  SELECT id INTO v_carrier_ups FROM carriers WHERE account_id = v_account_id AND name = 'UPS';

  -- Get postal centers
  SELECT id INTO v_center_madrid FROM postal_centers WHERE account_id = v_account_id AND city_name = 'Madrid';
  SELECT id INTO v_center_barcelona FROM postal_centers WHERE account_id = v_account_id AND city_name = 'Barcelona';
  SELECT id INTO v_center_valencia FROM postal_centers WHERE account_id = v_account_id AND city_name = 'Valencia';
  SELECT id INTO v_center_sevilla FROM postal_centers WHERE account_id = v_account_id AND city_name = 'Sevilla';

  -- Base date: 30 days ago
  v_base_date := NOW() - INTERVAL '30 days';

  RAISE NOTICE 'Generating synthetic test data for DEMO2...';

  -- SCENARIO 1: Madrid -> Barcelona (HIGH PERFORMANCE - FedEx)
  -- 50 journeys, 95% on-time
  FOR i IN 1..50 LOOP
    v_journey_id := gen_random_uuid();
    v_entry_time := v_base_date + (i || ' hours')::INTERVAL;
    
    -- Transit time: 6-8 hours (SLA: 12 hours)
    v_transit_minutes := 360 + floor(random() * 120)::INTEGER;
    v_sla_minutes := 720;
    v_is_on_time := (random() < 0.95); -- 95% on-time
    
    IF NOT v_is_on_time THEN
      v_transit_minutes := 780 + floor(random() * 120)::INTEGER; -- 13-15 hours (late)
    END IF;
    
    v_exit_time := v_entry_time + (v_transit_minutes || ' minutes')::INTERVAL;

    -- Insert journey
    INSERT INTO journeys (
      id, account_id, item_id, origin_city_name, destination_city_name,
      first_event_timestamp, last_event_timestamp, journey_status,
      total_actual_time_minutes, total_sla_violations, is_missroute
    ) VALUES (
      v_journey_id, v_account_id, 'TEST-MAD-BCN-' || i, 'Madrid', 'Barcelona',
      v_entry_time, v_exit_time, 'completed',
      v_transit_minutes, CASE WHEN v_is_on_time THEN 0 ELSE 1 END, FALSE
    );

    -- Insert processing segment (Madrid)
    INSERT INTO journey_segments (
      id, account_id, journey_id, item_id, segment_type,
      from_postal_center_id, entry_timestamp, exit_timestamp,
      actual_time_minutes, sla_compliance
    ) VALUES (
      gen_random_uuid(), v_account_id, v_journey_id, 'TEST-MAD-BCN-' || i, 'processing',
      v_center_madrid, v_entry_time, v_entry_time + INTERVAL '30 minutes',
      30, 'on_time'
    );

    -- Insert distribution segment (Madrid -> Barcelona via FedEx)
    INSERT INTO journey_segments (
      id, account_id, journey_id, item_id, segment_type,
      from_postal_center_id, to_postal_center_id, carrier_id,
      entry_timestamp, exit_timestamp, actual_time_minutes,
      sla_compliance
    ) VALUES (
      gen_random_uuid(), v_account_id, v_journey_id, 'TEST-MAD-BCN-' || i, 'distribution',
      v_center_madrid, v_center_barcelona, v_carrier_fedex,
      v_entry_time + INTERVAL '30 minutes', v_exit_time - INTERVAL '30 minutes',
      v_transit_minutes - 60,
      CASE WHEN v_is_on_time THEN 'on_time' ELSE 'late' END
    );

    -- Insert processing segment (Barcelona)
    INSERT INTO journey_segments (
      id, account_id, journey_id, item_id, segment_type,
      from_postal_center_id, entry_timestamp, exit_timestamp,
      actual_time_minutes, sla_compliance
    ) VALUES (
      gen_random_uuid(), v_account_id, v_journey_id, 'TEST-MAD-BCN-' || i, 'processing',
      v_center_barcelona, v_exit_time - INTERVAL '30 minutes', v_exit_time,
      30, 'on_time'
    );
  END LOOP;

  -- SCENARIO 2: Barcelona -> Valencia (MEDIUM PERFORMANCE - DHL)
  -- 40 journeys, 80% on-time
  FOR i IN 1..40 LOOP
    v_journey_id := gen_random_uuid();
    v_entry_time := v_base_date + (i * 1.5 || ' hours')::INTERVAL;
    
    v_transit_minutes := 240 + floor(random() * 120)::INTEGER; -- 4-6 hours
    v_sla_minutes := 480; -- 8 hours SLA
    v_is_on_time := (random() < 0.80); -- 80% on-time
    
    IF NOT v_is_on_time THEN
      v_transit_minutes := 540 + floor(random() * 180)::INTEGER; -- 9-12 hours (late)
    END IF;
    
    v_exit_time := v_entry_time + (v_transit_minutes || ' minutes')::INTERVAL;

    INSERT INTO journeys (
      id, account_id, item_id, origin_city_name, destination_city_name,
      first_event_timestamp, last_event_timestamp, journey_status,
      total_actual_time_minutes, total_sla_violations, is_missroute
    ) VALUES (
      v_journey_id, v_account_id, 'TEST-BCN-VAL-' || i, 'Barcelona', 'Valencia',
      v_entry_time, v_exit_time, 'completed',
      v_transit_minutes, CASE WHEN v_is_on_time THEN 0 ELSE 1 END, FALSE
    );

    INSERT INTO journey_segments (
      id, account_id, journey_id, item_id, segment_type,
      from_postal_center_id, entry_timestamp, exit_timestamp,
      actual_time_minutes, sla_compliance
    ) VALUES (
      gen_random_uuid(), v_account_id, v_journey_id, 'TEST-BCN-VAL-' || i, 'processing',
      v_center_barcelona, v_entry_time, v_entry_time + INTERVAL '20 minutes',
      20, 'on_time'
    );

    INSERT INTO journey_segments (
      id, account_id, journey_id, item_id, segment_type,
      from_postal_center_id, to_postal_center_id, carrier_id,
      entry_timestamp, exit_timestamp, actual_time_minutes,
      sla_compliance
    ) VALUES (
      gen_random_uuid(), v_account_id, v_journey_id, 'TEST-BCN-VAL-' || i, 'distribution',
      v_center_barcelona, v_center_valencia, v_carrier_dhl,
      v_entry_time + INTERVAL '20 minutes', v_exit_time - INTERVAL '20 minutes',
      v_transit_minutes - 40,
      CASE WHEN v_is_on_time THEN 'on_time' ELSE 'late' END
    );

    INSERT INTO journey_segments (
      id, account_id, journey_id, item_id, segment_type,
      from_postal_center_id, entry_timestamp, exit_timestamp,
      actual_time_minutes, sla_compliance
    ) VALUES (
      gen_random_uuid(), v_account_id, v_journey_id, 'TEST-BCN-VAL-' || i, 'processing',
      v_center_valencia, v_exit_time - INTERVAL '20 minutes', v_exit_time,
      20, 'on_time'
    );
  END LOOP;

  -- SCENARIO 3: Valencia -> Sevilla (POOR PERFORMANCE - UPS)
  -- 35 journeys, 60% on-time
  FOR i IN 1..35 LOOP
    v_journey_id := gen_random_uuid();
    v_entry_time := v_base_date + (i * 2 || ' hours')::INTERVAL;
    
    v_transit_minutes := 480 + floor(random() * 120)::INTEGER; -- 8-10 hours
    v_sla_minutes := 600; -- 10 hours SLA
    v_is_on_time := (random() < 0.60); -- 60% on-time
    
    IF NOT v_is_on_time THEN
      v_transit_minutes := 720 + floor(random() * 240)::INTEGER; -- 12-16 hours (late)
    END IF;
    
    v_exit_time := v_entry_time + (v_transit_minutes || ' minutes')::INTERVAL;

    INSERT INTO journeys (
      id, account_id, item_id, origin_city_name, destination_city_name,
      first_event_timestamp, last_event_timestamp, journey_status,
      total_actual_time_minutes, total_sla_violations, is_missroute
    ) VALUES (
      v_journey_id, v_account_id, 'TEST-VAL-SEV-' || i, 'Valencia', 'Sevilla',
      v_entry_time, v_exit_time, 'completed',
      v_transit_minutes, CASE WHEN v_is_on_time THEN 0 ELSE 1 END, FALSE
    );

    INSERT INTO journey_segments (
      id, account_id, journey_id, item_id, segment_type,
      from_postal_center_id, entry_timestamp, exit_timestamp,
      actual_time_minutes, sla_compliance
    ) VALUES (
      gen_random_uuid(), v_account_id, v_journey_id, 'TEST-VAL-SEV-' || i, 'processing',
      v_center_valencia, v_entry_time, v_entry_time + INTERVAL '45 minutes',
      45, 'on_time'
    );

    INSERT INTO journey_segments (
      id, account_id, journey_id, item_id, segment_type,
      from_postal_center_id, to_postal_center_id, carrier_id,
      entry_timestamp, exit_timestamp, actual_time_minutes,
      sla_compliance
    ) VALUES (
      gen_random_uuid(), v_account_id, v_journey_id, 'TEST-VAL-SEV-' || i, 'distribution',
      v_center_valencia, v_center_sevilla, v_carrier_ups,
      v_entry_time + INTERVAL '45 minutes', v_exit_time - INTERVAL '25 minutes',
      v_transit_minutes - 70,
      CASE WHEN v_is_on_time THEN 'on_time' ELSE 'late' END
    );

    INSERT INTO journey_segments (
      id, account_id, journey_id, item_id, segment_type,
      from_postal_center_id, entry_timestamp, exit_timestamp,
      actual_time_minutes, sla_compliance
    ) VALUES (
      gen_random_uuid(), v_account_id, v_journey_id, 'TEST-VAL-SEV-' || i, 'processing',
      v_center_sevilla, v_exit_time - INTERVAL '25 minutes', v_exit_time,
      25, 'on_time'
    );
  END LOOP;

  -- SCENARIO 4: Sevilla -> Madrid (MIXED PERFORMANCE - Multiple Carriers)
  -- 30 journeys with FedEx, DHL, UPS
  FOR i IN 1..30 LOOP
    v_journey_id := gen_random_uuid();
    v_entry_time := v_base_date + (i * 2.5 || ' hours')::INTERVAL;
    
    -- Assign carrier based on iteration
    DECLARE
      v_carrier UUID;
      v_carrier_name TEXT;
      v_performance NUMERIC;
    BEGIN
      IF i % 3 = 0 THEN
        v_carrier := v_carrier_fedex;
        v_carrier_name := 'FedEx';
        v_performance := 0.92; -- 92% on-time
      ELSIF i % 3 = 1 THEN
        v_carrier := v_carrier_dhl;
        v_carrier_name := 'DHL';
        v_performance := 0.78; -- 78% on-time
      ELSE
        v_carrier := v_carrier_ups;
        v_carrier_name := 'UPS';
        v_performance := 0.65; -- 65% on-time
      END IF;

      v_transit_minutes := 420 + floor(random() * 120)::INTEGER; -- 7-9 hours
      v_sla_minutes := 540; -- 9 hours SLA
      v_is_on_time := (random() < v_performance);
      
      IF NOT v_is_on_time THEN
        v_transit_minutes := 600 + floor(random() * 180)::INTEGER; -- 10-13 hours
      END IF;
      
      v_exit_time := v_entry_time + (v_transit_minutes || ' minutes')::INTERVAL;

      INSERT INTO journeys (
        id, account_id, item_id, origin_city_name, destination_city_name,
        first_event_timestamp, last_event_timestamp, journey_status,
        total_actual_time_minutes, total_sla_violations, is_missroute
      ) VALUES (
        v_journey_id, v_account_id, 'TEST-SEV-MAD-' || i, 'Sevilla', 'Madrid',
        v_entry_time, v_exit_time, 'completed',
        v_transit_minutes, CASE WHEN v_is_on_time THEN 0 ELSE 1 END, FALSE
      );

      INSERT INTO journey_segments (
        id, account_id, journey_id, item_id, segment_type,
        from_postal_center_id, entry_timestamp, exit_timestamp,
        actual_time_minutes, sla_compliance
      ) VALUES (
        gen_random_uuid(), v_account_id, v_journey_id, 'TEST-SEV-MAD-' || i, 'processing',
        v_center_sevilla, v_entry_time, v_entry_time + INTERVAL '35 minutes',
        35, 'on_time'
      );

      INSERT INTO journey_segments (
        id, account_id, journey_id, item_id, segment_type,
        from_postal_center_id, to_postal_center_id, carrier_id,
        entry_timestamp, exit_timestamp, actual_time_minutes,
        sla_compliance
      ) VALUES (
        gen_random_uuid(), v_account_id, v_journey_id, 'TEST-SEV-MAD-' || i, 'distribution',
        v_center_sevilla, v_center_madrid, v_carrier,
        v_entry_time + INTERVAL '35 minutes', v_exit_time - INTERVAL '30 minutes',
        v_transit_minutes - 65,
        CASE WHEN v_is_on_time THEN 'on_time' ELSE 'late' END
      );

      INSERT INTO journey_segments (
        id, account_id, journey_id, item_id, segment_type,
        from_postal_center_id, entry_timestamp, exit_timestamp,
        actual_time_minutes, sla_compliance
      ) VALUES (
        gen_random_uuid(), v_account_id, v_journey_id, 'TEST-SEV-MAD-' || i, 'processing',
        v_center_madrid, v_exit_time - INTERVAL '30 minutes', v_exit_time,
        30, 'on_time'
      );
    END;
  END LOOP;

  RAISE NOTICE 'Synthetic test data generation completed!';
  RAISE NOTICE 'Generated: 155 journeys across 4 routes with 3 carriers';
  RAISE NOTICE 'Performance scenarios: High (95%%), Medium (80%%), Poor (60%%), Mixed';
END $$;
