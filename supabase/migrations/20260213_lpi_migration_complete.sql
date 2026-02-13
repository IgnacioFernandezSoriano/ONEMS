-- ============================================================================
-- SIMPLE LPI MIGRATION - Using existing postal_centers.city field
-- ============================================================================
-- 1. Changes rfid_events_raw.reader_id from UUID to TEXT (LPI)
-- 2. Updates consolidate_rfid_events() to use postal_centers.city directly
-- 3. Creates test data using existing postal centers
-- 4. Tests consolidation
-- ============================================================================

-- STEP 1: Clean existing test data
-- ============================================================================
TRUNCATE TABLE rfid_events_raw CASCADE;
TRUNCATE TABLE processed_events CASCADE;
TRUNCATE TABLE journey_segments CASCADE;
DELETE FROM journeys WHERE tag_id LIKE 'TEST-%';
DELETE FROM readers WHERE reader_id LIKE 'J11D%';
DELETE FROM one_db WHERE tag_id = 'TEST-TAG-001';

-- STEP 2: Alter rfid_events_raw.reader_id to TEXT (LPI)
-- ============================================================================
ALTER TABLE rfid_events_raw 
  ALTER COLUMN reader_id TYPE TEXT USING reader_id::TEXT;

ALTER TABLE rfid_events_raw 
  ALTER COLUMN reader_id DROP NOT NULL;

-- Remove carrier_id and product_id from rfid_events_raw (obtained from one_db)
ALTER TABLE rfid_events_raw 
  DROP COLUMN IF EXISTS carrier_id;

ALTER TABLE rfid_events_raw 
  DROP COLUMN IF EXISTS product_id;

COMMENT ON COLUMN rfid_events_raw.reader_id IS 'Reader LPI code from EPCIS (e.g., J11DBRA02100000319)';

-- STEP 3: Update consolidate_rfid_events() function
-- ============================================================================
CREATE OR REPLACE FUNCTION consolidate_rfid_events()
RETURNS TABLE(
  processed_count BIGINT,
  error_message TEXT
) 
LANGUAGE plpgsql
AS $$
DECLARE
  v_processed_count BIGINT := 0;
  v_event RECORD;
  v_reader RECORD;
  v_onedb RECORD;
  v_product_id UUID;
  v_carrier_id UUID;
BEGIN
  FOR v_event IN 
    SELECT 
      raw.id,
      raw.account_id,
      raw.tag_id,
      raw.reader_id,
      raw.event_timestamp
    FROM rfid_events_raw raw
    WHERE raw.processed = FALSE
    ORDER BY raw.event_timestamp
  LOOP
    BEGIN
      -- Get reader information by LPI (using postal_centers.city directly)
      SELECT 
        r.id AS reader_uuid,
        r.reader_id AS reader_lpi,
        r.type AS reader_type,
        r.postal_center_id,
        pc.name AS postal_center_name,
        pc.city AS postal_center_city
      INTO v_reader
      FROM readers r
      JOIN postal_centers pc ON pc.id = r.postal_center_id
      WHERE r.reader_id = v_event.reader_id
        AND r.account_id = v_event.account_id
        AND r.is_active = TRUE
      LIMIT 1;

      IF v_reader.reader_uuid IS NULL THEN
        RAISE WARNING 'Reader LPI % not found for event %', v_event.reader_id, v_event.id;
        CONTINUE;
      END IF;

      -- Get carrier and product from ONE DB using tag_id
      SELECT 
        carrier_name,
        product_name
      INTO v_onedb
      FROM one_db
      WHERE tag_id = v_event.tag_id
        AND account_id = v_event.account_id
      LIMIT 1;

      IF v_onedb.carrier_name IS NULL THEN
        RAISE WARNING 'Tag % not found in ONE DB, skipping event %', v_event.tag_id, v_event.id;
        CONTINUE;
      END IF;

      -- Convert carrier_name to carrier_id
      SELECT id INTO v_carrier_id
      FROM carriers
      WHERE name = v_onedb.carrier_name
      LIMIT 1;

      IF v_carrier_id IS NULL THEN
        RAISE WARNING 'Carrier % not found for tag %', v_onedb.carrier_name, v_event.tag_id;
        CONTINUE;
      END IF;

      -- Convert product_name to product_id
      SELECT id INTO v_product_id
      FROM products
      WHERE code = v_onedb.product_name
        AND carrier_id = v_carrier_id
      LIMIT 1;

      IF v_product_id IS NULL THEN
        RAISE WARNING 'Product % not found for carrier %', v_onedb.product_name, v_onedb.carrier_name;
        -- Continue anyway, product_id can be NULL
      END IF;

      -- Insert into processed_events
      INSERT INTO processed_events (
        account_id,
        tag_id,
        event_timestamp,
        reader_id_snapshot,
        reader_type_snapshot,
        postal_center_id_snapshot,
        postal_center_name_snapshot,
        postal_center_city_snapshot,
        carrier_id,
        product_id,
        created_at
      ) VALUES (
        v_event.account_id,
        v_event.tag_id,
        v_event.event_timestamp,
        v_reader.reader_uuid,
        v_reader.reader_type,
        v_reader.postal_center_id,
        v_reader.postal_center_name,
        v_reader.postal_center_city,
        v_carrier_id,
        v_product_id,
        NOW()
      );

      -- Mark raw event as processed
      UPDATE rfid_events_raw
      SET processed = TRUE,
          processed_at = NOW()
      WHERE id = v_event.id;

      v_processed_count := v_processed_count + 1;

    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Error processing event %: %', v_event.id, SQLERRM;
      CONTINUE;
    END;
  END LOOP;

  RETURN QUERY SELECT v_processed_count, NULL::TEXT;
  
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT 0::BIGINT, SQLERRM;
END;
$$;

COMMENT ON FUNCTION consolidate_rfid_events() IS 
'Consolidates raw RFID events into processed_events using LPI-based reader lookup and ONE DB for carrier/product';

-- STEP 4: Generate test data using EXISTING postal centers
-- ============================================================================
DO $$
DECLARE
  v_account_id UUID := 'fe097d32-c4e0-4862-b7d8-55326d48f541'; -- DEMO2 account
  v_carrier_a UUID;
  v_product_standard_a UUID;
  v_postal_center_1 UUID;
  v_postal_center_2 UUID;
  v_postal_center_3 UUID;
  v_center_1_name TEXT;
  v_center_2_name TEXT;
  v_center_3_name TEXT;
  v_tag_id TEXT := 'TEST-TAG-001';
  v_timestamp TIMESTAMPTZ;
  v_allocation_plan_id UUID;
  v_allocation_detail_id UUID;
  v_panelist_origin UUID;
  v_panelist_dest UUID;
BEGIN
  
  -- Get carrier and product
  SELECT id INTO v_carrier_a FROM carriers WHERE name = 'Carrier A' LIMIT 1;
  SELECT id INTO v_product_standard_a FROM products WHERE carrier_id = v_carrier_a AND code = 'STANDARD' LIMIT 1;
  
  -- Get any 3 existing postal centers from DEMO2 (13 available)
  SELECT id, name INTO v_postal_center_1, v_center_1_name FROM postal_centers WHERE account_id = v_account_id LIMIT 1 OFFSET 0;
  SELECT id, name INTO v_postal_center_2, v_center_2_name FROM postal_centers WHERE account_id = v_account_id LIMIT 1 OFFSET 1;
  SELECT id, name INTO v_postal_center_3, v_center_3_name FROM postal_centers WHERE account_id = v_account_id LIMIT 1 OFFSET 2;
  
  IF v_postal_center_1 IS NULL OR v_postal_center_2 IS NULL OR v_postal_center_3 IS NULL THEN
    RAISE EXCEPTION 'Postal centers not found for DEMO2 account';
  END IF;
  
  RAISE NOTICE 'Using postal centers: %, %, %', v_center_1_name, v_center_2_name, v_center_3_name;
  
  -- Create readers with LPI codes
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  VALUES 
    (v_account_id, v_postal_center_1, 'J11DPC1-ENTRY-001', v_center_1_name || ' Entry', 'Entry', TRUE),
    (v_account_id, v_postal_center_1, 'J11DPC1-EXIT-001', v_center_1_name || ' Exit', 'Exit', TRUE),
    (v_account_id, v_postal_center_2, 'J11DPC2-ENTRY-001', v_center_2_name || ' Entry', 'Entry', TRUE),
    (v_account_id, v_postal_center_2, 'J11DPC2-EXIT-001', v_center_2_name || ' Exit', 'Exit', TRUE),
    (v_account_id, v_postal_center_3, 'J11DPC3-ENTRY-001', v_center_3_name || ' Entry', 'Entry', TRUE);
  
  -- Get or create allocation plan
  SELECT id INTO v_allocation_plan_id FROM allocation_plans WHERE account_id = v_account_id LIMIT 1;
  IF v_allocation_plan_id IS NULL THEN
    INSERT INTO allocation_plans (account_id, name, status)
    VALUES (v_account_id, 'Test Plan', 'active')
    RETURNING id INTO v_allocation_plan_id;
  END IF;
  
  -- Get panelists
  SELECT id INTO v_panelist_origin FROM panelists WHERE account_id = v_account_id LIMIT 1 OFFSET 0;
  SELECT id INTO v_panelist_dest FROM panelists WHERE account_id = v_account_id LIMIT 1 OFFSET 1;
  
  -- Create allocation_plan_details entry
  INSERT INTO allocation_plan_details (
    account_id,
    allocation_plan_id,
    tag_id,
    origin_panelist_id,
    destination_panelist_id
  ) VALUES (
    v_account_id,
    v_allocation_plan_id,
    v_tag_id,
    v_panelist_origin,
    v_panelist_dest
  )
  RETURNING id INTO v_allocation_detail_id;
  
  -- Create entry in ONE DB
  v_timestamp := NOW() - INTERVAL '2 hours';
  
  INSERT INTO one_db (
    account_id,
    allocation_detail_id,
    tag_id,
    plan_name,
    carrier_name,
    product_name,
    origin_city_name,
    destination_city_name,
    sent_at,
    received_at,
    total_transit_days,
    source_data_snapshot
  ) VALUES (
    v_account_id,
    v_allocation_detail_id,
    v_tag_id,
    'Test Plan',
    'Carrier A',
    'STANDARD',
    'Origin City',
    'Destination City',
    v_timestamp,
    v_timestamp + INTERVAL '2 days',
    2,
    '{}'::jsonb
  );
  
  -- Generate raw RFID events
  INSERT INTO rfid_events_raw (account_id, tag_id, reader_id, event_timestamp, processed)
  VALUES 
    (v_account_id, v_tag_id, 'J11DPC1-ENTRY-001', v_timestamp, FALSE),
    (v_account_id, v_tag_id, 'J11DPC1-EXIT-001', v_timestamp + INTERVAL '15 minutes', FALSE),
    (v_account_id, v_tag_id, 'J11DPC2-ENTRY-001', v_timestamp + INTERVAL '60 minutes', FALSE),
    (v_account_id, v_tag_id, 'J11DPC2-EXIT-001', v_timestamp + INTERVAL '80 minutes', FALSE),
    (v_account_id, v_tag_id, 'J11DPC3-ENTRY-001', v_timestamp + INTERVAL '130 minutes', FALSE);
  
  RAISE NOTICE '✅ Test data created successfully';
  RAISE NOTICE '   Postal Centers: %, %, %', v_center_1_name, v_center_2_name, v_center_3_name;
  RAISE NOTICE '   Readers: 5 with LPI codes';
  RAISE NOTICE '   ONE DB entry: % (Carrier A, STANDARD)', v_tag_id;
  RAISE NOTICE '   Raw events: 5';
END $$;

-- STEP 5: Test consolidation
-- ============================================================================
SELECT '=== BEFORE CONSOLIDATION ===' AS step;
SELECT COUNT(*) AS raw_events FROM rfid_events_raw WHERE tag_id = 'TEST-TAG-001';

SELECT '=== RUNNING CONSOLIDATION ===' AS step;
SELECT * FROM consolidate_rfid_events();

SELECT '=== AFTER CONSOLIDATION ===' AS step;
SELECT 
    COUNT(*) AS total_processed,
    COUNT(*) FILTER (WHERE reader_id_snapshot IS NOT NULL) AS with_reader_id,
    COUNT(*) FILTER (WHERE product_id IS NOT NULL) AS with_product_id,
    COUNT(*) FILTER (WHERE carrier_id IS NOT NULL) AS with_carrier_id,
    COUNT(*) FILTER (WHERE postal_center_city_snapshot IS NOT NULL) AS with_city
FROM processed_events
WHERE tag_id = 'TEST-TAG-001';

-- Display results
SELECT 
    event_timestamp,
    reader_type_snapshot AS reader_type,
    postal_center_name_snapshot AS center,
    postal_center_city_snapshot AS city,
    (SELECT name FROM carriers WHERE id = carrier_id) AS carrier,
    (SELECT code FROM products WHERE id = product_id) AS product
FROM processed_events
WHERE tag_id = 'TEST-TAG-001'
ORDER BY event_timestamp;
