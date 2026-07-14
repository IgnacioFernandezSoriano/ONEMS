-- =====================================================
-- PHASE 1: Add Carrier & Product to RFID Events Raw
-- =====================================================
-- Description: Schema update + Sample EPCIS data based on ONE DB records
-- Date: 2026-02-13
-- =====================================================

-- =====================================================
-- STEP 1: Schema Update
-- =====================================================

ALTER TABLE rfid_events_raw 
ADD COLUMN IF NOT EXISTS carrier_id UUID REFERENCES carriers(id),
ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES products(id);

CREATE INDEX IF NOT EXISTS idx_rfid_raw_carrier_product 
ON rfid_events_raw(account_id, carrier_id, product_id);

COMMENT ON COLUMN rfid_events_raw.carrier_id IS 'Reference to the carrier handling this shipment';
COMMENT ON COLUMN rfid_events_raw.product_id IS 'Reference to the product/service type (e.g., EXPRESS, STANDARD)';

-- Verify schema
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns
WHERE table_name = 'rfid_events_raw'
AND column_name IN ('carrier_id', 'product_id')
ORDER BY ordinal_position;

-- =====================================================
-- STEP 2: Generate Sample EPCIS Events from ONE DB
-- =====================================================
-- Products table schema (from documentation):
-- - id, account_id, carrier_id, code, name, standard_delivery_hours

DO $$
DECLARE
    v_account_id UUID;
    v_onedb_record RECORD;
    v_carrier RECORD;
    v_product RECORD;
    v_origin_center RECORD;
    v_dest_center RECORD;
    v_origin_entry_reader TEXT;
    v_origin_exit_reader TEXT;
    v_dest_entry_reader TEXT;
    v_dest_exit_reader TEXT;
    v_tag_counter INTEGER := 1;
    v_tag_id TEXT;
    v_base_time TIMESTAMPTZ;
    v_entry_time TIMESTAMPTZ;
    v_exit_time TIMESTAMPTZ;
    v_transit_hours INTEGER;
    v_processing_time INTERVAL;
    v_events_generated INTEGER := 0;
BEGIN
    -- Get account ID from ONE DB
    SELECT DISTINCT account_id INTO v_account_id 
    FROM one_db 
    WHERE account_id IS NOT NULL
    LIMIT 1;
    
    IF v_account_id IS NULL THEN
        RAISE EXCEPTION 'No account_id found in ONE DB';
    END IF;
    
    RAISE NOTICE '🚀 Generating EPCIS events from ONE DB records...';
    RAISE NOTICE 'Account ID: %', v_account_id;
    RAISE NOTICE '';
    
    -- Loop through unique combinations in ONE DB
    FOR v_onedb_record IN
        SELECT DISTINCT
            carrier_name,
            product_name,
            origin_city_name,
            destination_city_name
        FROM one_db
        WHERE account_id = v_account_id
        AND carrier_name IS NOT NULL
        AND product_name IS NOT NULL
        AND origin_city_name IS NOT NULL
        AND destination_city_name IS NOT NULL
        ORDER BY carrier_name, product_name, origin_city_name, destination_city_name
        LIMIT 10  -- Limit to avoid too many events
    LOOP
        -- Find carrier by name
        SELECT id, name INTO v_carrier
        FROM carriers
        WHERE account_id = v_account_id
        AND name ILIKE '%' || v_onedb_record.carrier_name || '%'
        LIMIT 1;
        
        IF v_carrier.id IS NULL THEN
            RAISE WARNING '   ⚠️  Carrier not found: %', v_onedb_record.carrier_name;
            CONTINUE;
        END IF;
        
        -- Find product by code (using code field, not name)
        SELECT id, code, standard_delivery_hours INTO v_product
        FROM products
        WHERE account_id = v_account_id
        AND carrier_id = v_carrier.id
        AND code ILIKE '%' || v_onedb_record.product_name || '%'
        LIMIT 1;
        
        IF v_product.id IS NULL THEN
            -- Try to find any product for this carrier
            SELECT id, code, standard_delivery_hours INTO v_product
            FROM products
            WHERE account_id = v_account_id
            AND carrier_id = v_carrier.id
            LIMIT 1;
        END IF;
        
        IF v_product.id IS NULL THEN
            RAISE WARNING '   ⚠️  Product not found for carrier: %', v_carrier.name;
            CONTINUE;
        END IF;
        
        -- Generate unique tag ID
        v_tag_id := 'TAG-ONEDB-' || LPAD(v_tag_counter::TEXT, 5, '0');
        v_tag_counter := v_tag_counter + 1;
        
        RAISE NOTICE '📦 % → % (% - %)',
            v_onedb_record.origin_city_name,
            v_onedb_record.destination_city_name,
            v_carrier.name,
            v_product.code;
        RAISE NOTICE '   Tag: %', v_tag_id;
        
        -- Find origin postal center
        SELECT pc.id, pc.code, pc.name
        INTO v_origin_center
        FROM postal_centers pc
        JOIN cities c ON pc.city_id = c.id
        WHERE c.name ILIKE '%' || v_onedb_record.origin_city_name || '%'
        AND pc.carrier_id = v_carrier.id
        AND pc.account_id = v_account_id
        LIMIT 1;
        
        -- If no carrier-specific center, use any center in that city
        IF v_origin_center.id IS NULL THEN
            SELECT pc.id, pc.code, pc.name
            INTO v_origin_center
            FROM postal_centers pc
            JOIN cities c ON pc.city_id = c.id
            WHERE c.name ILIKE '%' || v_onedb_record.origin_city_name || '%'
            AND pc.account_id = v_account_id
            LIMIT 1;
        END IF;
        
        -- Find destination postal center
        SELECT pc.id, pc.code, pc.name
        INTO v_dest_center
        FROM postal_centers pc
        JOIN cities c ON pc.city_id = c.id
        WHERE c.name ILIKE '%' || v_onedb_record.destination_city_name || '%'
        AND pc.carrier_id = v_carrier.id
        AND pc.account_id = v_account_id
        LIMIT 1;
        
        IF v_dest_center.id IS NULL THEN
            SELECT pc.id, pc.code, pc.name
            INTO v_dest_center
            FROM postal_centers pc
            JOIN cities c ON pc.city_id = c.id
            WHERE c.name ILIKE '%' || v_onedb_record.destination_city_name || '%'
            AND pc.account_id = v_account_id
            LIMIT 1;
        END IF;
        
        -- Check if we found both centers
        IF v_origin_center.id IS NULL THEN
            RAISE WARNING '   ⚠️  Origin center not found: %', v_onedb_record.origin_city_name;
            CONTINUE;
        END IF;
        
        IF v_dest_center.id IS NULL THEN
            RAISE WARNING '   ⚠️  Destination center not found: %', v_onedb_record.destination_city_name;
            CONTINUE;
        END IF;
        
        RAISE NOTICE '   Origin: %', v_origin_center.code;
        RAISE NOTICE '   Dest: %', v_dest_center.code;
        
        -- Find readers for origin center
        SELECT code INTO v_origin_entry_reader
        FROM readers
        WHERE postal_center_id = v_origin_center.id
        AND reader_type = 'Entry'
        LIMIT 1;
        
        SELECT code INTO v_origin_exit_reader
        FROM readers
        WHERE postal_center_id = v_origin_center.id
        AND reader_type = 'Exit'
        LIMIT 1;
        
        -- Find readers for destination center
        SELECT code INTO v_dest_entry_reader
        FROM readers
        WHERE postal_center_id = v_dest_center.id
        AND reader_type = 'Entry'
        LIMIT 1;
        
        SELECT code INTO v_dest_exit_reader
        FROM readers
        WHERE postal_center_id = v_dest_center.id
        AND reader_type = 'Exit'
        LIMIT 1;
        
        -- Check readers exist
        IF v_origin_entry_reader IS NULL OR v_origin_exit_reader IS NULL THEN
            RAISE WARNING '   ⚠️  Readers not found for origin center';
            CONTINUE;
        END IF;
        
        IF v_dest_entry_reader IS NULL OR v_dest_exit_reader IS NULL THEN
            RAISE WARNING '   ⚠️  Readers not found for destination center';
            CONTINUE;
        END IF;
        
        -- Generate timestamps
        v_base_time := NOW() - (INTERVAL '1 day' * (3 + random() * 4));
        v_processing_time := INTERVAL '1 hour' * (2 + random() * 4);
        v_transit_hours := COALESCE(v_product.standard_delivery_hours, 24);
        
        -- ===== ORIGIN CENTER EVENTS =====
        
        -- Entry at origin (5 reads)
        v_entry_time := v_base_time;
        FOR i IN 1..5 LOOP
            INSERT INTO rfid_events_raw (
                account_id,
                event_id,
                read_local_datetime,
                reader_id,
                tag_id,
                carrier_id,
                product_id,
                is_processed
            ) VALUES (
                v_account_id,
                v_tag_id || '-ORIGIN-ENTRY-' || i,
                v_entry_time + (INTERVAL '1 second' * i),
                v_origin_entry_reader,
                v_tag_id,
                v_carrier.id,
                v_product.id,
                FALSE
            );
        END LOOP;
        
        -- Exit from origin
        v_exit_time := v_entry_time + v_processing_time;
        FOR i IN 1..5 LOOP
            INSERT INTO rfid_events_raw (
                account_id,
                event_id,
                read_local_datetime,
                reader_id,
                tag_id,
                carrier_id,
                product_id,
                is_processed
            ) VALUES (
                v_account_id,
                v_tag_id || '-ORIGIN-EXIT-' || i,
                v_exit_time + (INTERVAL '1 second' * i),
                v_origin_exit_reader,
                v_tag_id,
                v_carrier.id,
                v_product.id,
                FALSE
            );
        END LOOP;
        
        -- ===== DESTINATION CENTER EVENTS =====
        
        -- Entry at destination
        v_entry_time := v_exit_time + (INTERVAL '1 hour' * v_transit_hours);
        FOR i IN 1..5 LOOP
            INSERT INTO rfid_events_raw (
                account_id,
                event_id,
                read_local_datetime,
                reader_id,
                tag_id,
                carrier_id,
                product_id,
                is_processed
            ) VALUES (
                v_account_id,
                v_tag_id || '-DEST-ENTRY-' || i,
                v_entry_time + (INTERVAL '1 second' * i),
                v_dest_entry_reader,
                v_tag_id,
                v_carrier.id,
                v_product.id,
                FALSE
            );
        END LOOP;
        
        -- Exit from destination
        v_exit_time := v_entry_time + v_processing_time;
        FOR i IN 1..5 LOOP
            INSERT INTO rfid_events_raw (
                account_id,
                event_id,
                read_local_datetime,
                reader_id,
                tag_id,
                carrier_id,
                product_id,
                is_processed
            ) VALUES (
                v_account_id,
                v_tag_id || '-DEST-EXIT-' || i,
                v_exit_time + (INTERVAL '1 second' * i),
                v_dest_exit_reader,
                v_tag_id,
                v_carrier.id,
                v_product.id,
                FALSE
            );
        END LOOP;
        
        v_events_generated := v_events_generated + 20;
        RAISE NOTICE '   ✅ 20 events generated';
        RAISE NOTICE '';
        
    END LOOP;
    
    RAISE NOTICE '✅ Total events generated: %', v_events_generated;
    
END $$;

-- =====================================================
-- STEP 3: Verification
-- =====================================================

-- Count events by carrier and product
SELECT 
    c.name as carrier,
    p.code as product,
    COUNT(*) as event_count,
    COUNT(DISTINCT tag_id) as unique_tags
FROM rfid_events_raw r
JOIN carriers c ON r.carrier_id = c.id
JOIN products p ON r.product_id = p.id
WHERE r.is_processed = FALSE
GROUP BY c.name, p.code
ORDER BY c.name, p.code;

-- Show sample events
SELECT 
    tag_id,
    reader_id,
    read_local_datetime,
    c.name as carrier,
    p.code as product
FROM rfid_events_raw r
JOIN carriers c ON r.carrier_id = c.id
JOIN products p ON r.product_id = p.id
WHERE r.is_processed = FALSE
ORDER BY tag_id, read_local_datetime
LIMIT 20;

-- Summary
SELECT 
    COUNT(*) as total_events,
    COUNT(DISTINCT tag_id) as total_tags,
    COUNT(DISTINCT carrier_id) as total_carriers,
    COUNT(DISTINCT product_id) as total_products,
    MIN(read_local_datetime) as earliest_event,
    MAX(read_local_datetime) as latest_event
FROM rfid_events_raw
WHERE is_processed = FALSE;
