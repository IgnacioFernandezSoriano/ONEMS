-- =====================================================
-- EPCIS Test Data Generation Script
-- =====================================================
-- Description: Comprehensive test data for EPCIS pipeline
-- Includes: ONE DB entries, RFID readers with LPI codes, raw EPCIS events
-- Date: 2026-02-14
-- =====================================================

-- =====================================================
-- STEP 1: Clean existing test data
-- =====================================================

DO $$
DECLARE
    v_account_id UUID;
BEGIN
    -- Get the first account ID
    SELECT id INTO v_account_id FROM auth.users LIMIT 1;
    
    IF v_account_id IS NULL THEN
        RAISE EXCEPTION 'No user account found. Please create a user first.';
    END IF;
    
    RAISE NOTICE '🧹 Cleaning existing test data for account: %', v_account_id;
    
    -- Delete in reverse dependency order
    DELETE FROM journey_paths WHERE account_id = v_account_id;
    DELETE FROM journey_segments WHERE account_id = v_account_id;
    DELETE FROM processed_events WHERE account_id = v_account_id;
    DELETE FROM rfid_events_raw WHERE account_id = v_account_id AND tag_id LIKE 'TEST-%';
    
    RAISE NOTICE '✅ Cleanup complete';
END $$;

-- =====================================================
-- STEP 2: Ensure cities exist
-- =====================================================

DO $$
DECLARE
    v_account_id UUID;
    v_madrid_id UUID;
    v_barcelona_id UUID;
    v_valencia_id UUID;
    v_sevilla_id UUID;
    v_bilbao_id UUID;
    v_zaragoza_id UUID;
BEGIN
    SELECT id INTO v_account_id FROM auth.users LIMIT 1;
    
    RAISE NOTICE '🏙️  Setting up cities...';
    
    -- Insert or get cities
    INSERT INTO cities (account_id, name, code, country_code)
    VALUES 
        (v_account_id, 'Madrid', 'MAD', 'ES'),
        (v_account_id, 'Barcelona', 'BCN', 'ES'),
        (v_account_id, 'Valencia', 'VLC', 'ES'),
        (v_account_id, 'Sevilla', 'SVQ', 'ES'),
        (v_account_id, 'Bilbao', 'BIO', 'ES'),
        (v_account_id, 'Zaragoza', 'ZAZ', 'ES')
    ON CONFLICT (account_id, code) DO NOTHING;
    
    SELECT id INTO v_madrid_id FROM cities WHERE account_id = v_account_id AND code = 'MAD';
    SELECT id INTO v_barcelona_id FROM cities WHERE account_id = v_account_id AND code = 'BCN';
    SELECT id INTO v_valencia_id FROM cities WHERE account_id = v_account_id AND code = 'VLC';
    SELECT id INTO v_sevilla_id FROM cities WHERE account_id = v_account_id AND code = 'SVQ';
    SELECT id INTO v_bilbao_id FROM cities WHERE account_id = v_account_id AND code = 'BIO';
    SELECT id INTO v_zaragoza_id FROM cities WHERE account_id = v_account_id AND code = 'ZAZ';
    
    RAISE NOTICE '✅ Cities ready: Madrid, Barcelona, Valencia, Sevilla, Bilbao, Zaragoza';
END $$;

-- =====================================================
-- STEP 3: Create carriers
-- =====================================================

DO $$
DECLARE
    v_account_id UUID;
    v_correos_id UUID;
    v_seur_id UUID;
    v_mrw_id UUID;
BEGIN
    SELECT id INTO v_account_id FROM auth.users LIMIT 1;
    
    RAISE NOTICE '🚚 Setting up carriers...';
    
    -- Insert carriers
    INSERT INTO carriers (account_id, name, code)
    VALUES 
        (v_account_id, 'Correos', 'COR'),
        (v_account_id, 'SEUR', 'SEU'),
        (v_account_id, 'MRW', 'MRW')
    ON CONFLICT (account_id, code) DO NOTHING;
    
    SELECT id INTO v_correos_id FROM carriers WHERE account_id = v_account_id AND code = 'COR';
    SELECT id INTO v_seur_id FROM carriers WHERE account_id = v_account_id AND code = 'SEU';
    SELECT id INTO v_mrw_id FROM carriers WHERE account_id = v_account_id AND code = 'MRW';
    
    RAISE NOTICE '✅ Carriers ready: Correos, SEUR, MRW';
END $$;

-- =====================================================
-- STEP 4: Create products
-- =====================================================

DO $$
DECLARE
    v_account_id UUID;
    v_correos_id UUID;
    v_seur_id UUID;
    v_mrw_id UUID;
BEGIN
    SELECT id INTO v_account_id FROM auth.users LIMIT 1;
    SELECT id INTO v_correos_id FROM carriers WHERE account_id = v_account_id AND code = 'COR';
    SELECT id INTO v_seur_id FROM carriers WHERE account_id = v_account_id AND code = 'SEU';
    SELECT id INTO v_mrw_id FROM carriers WHERE account_id = v_account_id AND code = 'MRW';
    
    RAISE NOTICE '📦 Setting up products...';
    
    -- Correos products
    INSERT INTO products (account_id, carrier_id, code, name, standard_delivery_hours)
    VALUES 
        (v_account_id, v_correos_id, 'PAQSTD', 'Paquete Estándar', 48),
        (v_account_id, v_correos_id, 'PAQEXP', 'Paquete Express', 24),
        (v_account_id, v_correos_id, 'PAQURG', 'Paquete Urgente', 12)
    ON CONFLICT (account_id, carrier_id, code) DO NOTHING;
    
    -- SEUR products
    INSERT INTO products (account_id, carrier_id, code, name, standard_delivery_hours)
    VALUES 
        (v_account_id, v_seur_id, 'SEUR24', 'SEUR 24h', 24),
        (v_account_id, v_seur_id, 'SEUR48', 'SEUR 48h', 48),
        (v_account_id, v_seur_id, 'SEUR10', 'SEUR 10:00', 12)
    ON CONFLICT (account_id, carrier_id, code) DO NOTHING;
    
    -- MRW products
    INSERT INTO products (account_id, carrier_id, code, name, standard_delivery_hours)
    VALUES 
        (v_account_id, v_mrw_id, 'MRW24', 'MRW 24h', 24),
        (v_account_id, v_mrw_id, 'MRW48', 'MRW 48h', 48),
        (v_account_id, v_mrw_id, 'MRWEXP', 'MRW Express', 18)
    ON CONFLICT (account_id, carrier_id, code) DO NOTHING;
    
    RAISE NOTICE '✅ Products ready: 9 products across 3 carriers';
END $$;

-- =====================================================
-- STEP 5: Create postal centers with city relationships
-- =====================================================

DO $$
DECLARE
    v_account_id UUID;
    v_correos_id UUID;
    v_seur_id UUID;
    v_mrw_id UUID;
    v_madrid_id UUID;
    v_barcelona_id UUID;
    v_valencia_id UUID;
    v_sevilla_id UUID;
    v_bilbao_id UUID;
    v_zaragoza_id UUID;
BEGIN
    SELECT id INTO v_account_id FROM auth.users LIMIT 1;
    SELECT id INTO v_correos_id FROM carriers WHERE account_id = v_account_id AND code = 'COR';
    SELECT id INTO v_seur_id FROM carriers WHERE account_id = v_account_id AND code = 'SEU';
    SELECT id INTO v_mrw_id FROM carriers WHERE account_id = v_account_id AND code = 'MRW';
    
    SELECT id INTO v_madrid_id FROM cities WHERE account_id = v_account_id AND code = 'MAD';
    SELECT id INTO v_barcelona_id FROM cities WHERE account_id = v_account_id AND code = 'BCN';
    SELECT id INTO v_valencia_id FROM cities WHERE account_id = v_account_id AND code = 'VLC';
    SELECT id INTO v_sevilla_id FROM cities WHERE account_id = v_account_id AND code = 'SVQ';
    SELECT id INTO v_bilbao_id FROM cities WHERE account_id = v_account_id AND code = 'BIO';
    SELECT id INTO v_zaragoza_id FROM cities WHERE account_id = v_account_id AND code = 'ZAZ';
    
    RAISE NOTICE '🏢 Setting up postal centers...';
    
    -- Correos centers
    INSERT INTO postal_centers (account_id, carrier_id, city_id, code, name, center_type)
    VALUES 
        (v_account_id, v_correos_id, v_madrid_id, 'COR-MAD', 'Correos Madrid Centro', 'Distribution'),
        (v_account_id, v_correos_id, v_barcelona_id, 'COR-BCN', 'Correos Barcelona Centro', 'Distribution'),
        (v_account_id, v_correos_id, v_valencia_id, 'COR-VLC', 'Correos Valencia Centro', 'Distribution'),
        (v_account_id, v_correos_id, v_sevilla_id, 'COR-SVQ', 'Correos Sevilla Centro', 'Distribution')
    ON CONFLICT (account_id, code) DO NOTHING;
    
    -- SEUR centers
    INSERT INTO postal_centers (account_id, carrier_id, city_id, code, name, center_type)
    VALUES 
        (v_account_id, v_seur_id, v_madrid_id, 'SEUR-MAD', 'SEUR Madrid Hub', 'Hub'),
        (v_account_id, v_seur_id, v_barcelona_id, 'SEUR-BCN', 'SEUR Barcelona Hub', 'Hub'),
        (v_account_id, v_seur_id, v_bilbao_id, 'SEUR-BIO', 'SEUR Bilbao Centro', 'Distribution')
    ON CONFLICT (account_id, code) DO NOTHING;
    
    -- MRW centers
    INSERT INTO postal_centers (account_id, carrier_id, city_id, code, name, center_type)
    VALUES 
        (v_account_id, v_mrw_id, v_madrid_id, 'MRW-MAD', 'MRW Madrid Centro', 'Distribution'),
        (v_account_id, v_mrw_id, v_zaragoza_id, 'MRW-ZAZ', 'MRW Zaragoza Centro', 'Distribution'),
        (v_account_id, v_mrw_id, v_valencia_id, 'MRW-VLC', 'MRW Valencia Centro', 'Distribution')
    ON CONFLICT (account_id, code) DO NOTHING;
    
    RAISE NOTICE '✅ Postal centers ready: 11 centers across 6 cities';
END $$;

-- =====================================================
-- STEP 6: Create RFID readers with LPI codes
-- =====================================================

DO $$
DECLARE
    v_account_id UUID;
    v_center RECORD;
    v_reader_counter INTEGER := 1;
    v_lpi_code TEXT;
BEGIN
    SELECT id INTO v_account_id FROM auth.users LIMIT 1;
    
    RAISE NOTICE '📡 Setting up RFID readers with LPI codes...';
    
    -- Loop through all postal centers and create Entry/Exit readers
    FOR v_center IN
        SELECT id, code, name
        FROM postal_centers
        WHERE account_id = v_account_id
    LOOP
        -- Entry reader (LPI format: J11DBRA02100000XXX)
        v_lpi_code := 'J11DBRA021000003' || LPAD(v_reader_counter::TEXT, 2, '0');
        
        INSERT INTO readers (account_id, postal_center_id, reader_id, code, name, reader_type, status)
        VALUES (
            v_account_id,
            v_center.id,
            v_lpi_code,
            v_center.code || '-ENTRY',
            v_center.name || ' - Entrada',
            'Entry',
            'Active'
        )
        ON CONFLICT (account_id, code) DO NOTHING;
        
        v_reader_counter := v_reader_counter + 1;
        
        -- Exit reader
        v_lpi_code := 'J11DBRA021000003' || LPAD(v_reader_counter::TEXT, 2, '0');
        
        INSERT INTO readers (account_id, postal_center_id, reader_id, code, name, reader_type, status)
        VALUES (
            v_account_id,
            v_center.id,
            v_lpi_code,
            v_center.code || '-EXIT',
            v_center.name || ' - Salida',
            'Exit',
            'Active'
        )
        ON CONFLICT (account_id, code) DO NOTHING;
        
        v_reader_counter := v_reader_counter + 1;
        
        RAISE NOTICE '   ✅ Readers created for: %', v_center.name;
    END LOOP;
    
    RAISE NOTICE '✅ RFID readers ready: % readers with LPI codes', v_reader_counter - 1;
END $$;

-- =====================================================
-- STEP 7: Create ONE DB test entries
-- =====================================================

DO $$
DECLARE
    v_account_id UUID;
    v_allocation_plan_id UUID;
    v_allocation_detail_id UUID;
    v_tag_counter INTEGER := 1;
    v_tag_id TEXT;
    v_sent_at TIMESTAMPTZ;
    v_received_at TIMESTAMPTZ;
    v_route RECORD;
    v_routes TEXT[][] := ARRAY[
        ARRAY['Correos', 'PAQSTD', 'Madrid', 'Barcelona'],
        ARRAY['Correos', 'PAQEXP', 'Madrid', 'Valencia'],
        ARRAY['Correos', 'PAQURG', 'Barcelona', 'Madrid'],
        ARRAY['SEUR', 'SEUR24', 'Madrid', 'Barcelona'],
        ARRAY['SEUR', 'SEUR48', 'Madrid', 'Bilbao'],
        ARRAY['SEUR', 'SEUR10', 'Barcelona', 'Madrid'],
        ARRAY['MRW', 'MRW24', 'Madrid', 'Valencia'],
        ARRAY['MRW', 'MRW48', 'Madrid', 'Zaragoza'],
        ARRAY['MRW', 'MRWEXP', 'Valencia', 'Madrid']
    ];
BEGIN
    SELECT id INTO v_account_id FROM auth.users LIMIT 1;
    
    RAISE NOTICE '📋 Creating ONE DB test entries...';
    
    -- Create a test allocation plan
    INSERT INTO allocation_plans (account_id, name, start_date, end_date, status)
    VALUES (
        v_account_id,
        'EPCIS Test Plan',
        CURRENT_DATE - INTERVAL '7 days',
        CURRENT_DATE + INTERVAL '30 days',
        'Active'
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_allocation_plan_id;
    
    IF v_allocation_plan_id IS NULL THEN
        SELECT id INTO v_allocation_plan_id 
        FROM allocation_plans 
        WHERE account_id = v_account_id AND name = 'EPCIS Test Plan';
    END IF;
    
    -- Create ONE DB entries for each route (10 shipments per route)
    FOREACH v_route SLICE 1 IN ARRAY v_routes
    LOOP
        FOR i IN 1..10 LOOP
            v_tag_id := 'TEST-' || LPAD(v_tag_counter::TEXT, 6, '0');
            v_sent_at := NOW() - (INTERVAL '1 day' * (5 + random() * 3));
            v_received_at := v_sent_at + (INTERVAL '1 hour' * (12 + random() * 36));
            
            -- Create allocation detail
            INSERT INTO allocation_plan_details (
                account_id,
                allocation_plan_id,
                idtag,
                status
            )
            VALUES (
                v_account_id,
                v_allocation_plan_id,
                v_tag_id,
                'Completed'
            )
            RETURNING id INTO v_allocation_detail_id;
            
            -- Create ONE DB entry
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
                business_transit_days,
                on_time_delivery,
                source_data_snapshot
            )
            VALUES (
                v_account_id,
                v_allocation_detail_id,
                v_tag_id,
                'EPCIS Test Plan',
                v_route[1],
                v_route[2],
                v_route[3],
                v_route[4],
                v_sent_at,
                v_received_at,
                EXTRACT(DAY FROM (v_received_at - v_sent_at))::INTEGER,
                NULL,
                (random() > 0.3),
                jsonb_build_object('test', true)
            );
            
            v_tag_counter := v_tag_counter + 1;
        END LOOP;
        
        RAISE NOTICE '   ✅ 10 shipments: % → % (% - %)', 
            v_route[3], v_route[4], v_route[1], v_route[2];
    END LOOP;
    
    RAISE NOTICE '✅ ONE DB entries ready: % shipments across % routes', 
        v_tag_counter - 1, array_length(v_routes, 1);
END $$;

-- =====================================================
-- STEP 8: Generate EPCIS raw events
-- =====================================================

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
    v_base_time TIMESTAMPTZ;
    v_entry_time TIMESTAMPTZ;
    v_exit_time TIMESTAMPTZ;
    v_processing_time INTERVAL;
    v_transit_time INTERVAL;
    v_events_generated INTEGER := 0;
BEGIN
    SELECT id INTO v_account_id FROM auth.users LIMIT 1;
    
    RAISE NOTICE '🚀 Generating EPCIS raw events from ONE DB...';
    RAISE NOTICE '';
    
    -- Loop through ONE DB entries
    FOR v_onedb_record IN
        SELECT 
            tag_id,
            carrier_name,
            product_name,
            origin_city_name,
            destination_city_name,
            sent_at,
            received_at
        FROM one_db
        WHERE account_id = v_account_id
        AND tag_id LIKE 'TEST-%'
        ORDER BY tag_id
    LOOP
        -- Find carrier
        SELECT id, name INTO v_carrier
        FROM carriers
        WHERE account_id = v_account_id
        AND name = v_onedb_record.carrier_name;
        
        IF v_carrier.id IS NULL THEN
            RAISE WARNING '   ⚠️  Carrier not found: %', v_onedb_record.carrier_name;
            CONTINUE;
        END IF;
        
        -- Find product
        SELECT id, code, standard_delivery_hours INTO v_product
        FROM products
        WHERE account_id = v_account_id
        AND carrier_id = v_carrier.id
        AND code = v_onedb_record.product_name;
        
        IF v_product.id IS NULL THEN
            RAISE WARNING '   ⚠️  Product not found: %', v_onedb_record.product_name;
            CONTINUE;
        END IF;
        
        -- Find origin postal center
        SELECT pc.id, pc.code, pc.name
        INTO v_origin_center
        FROM postal_centers pc
        JOIN cities c ON pc.city_id = c.id
        WHERE c.name = v_onedb_record.origin_city_name
        AND pc.carrier_id = v_carrier.id
        AND pc.account_id = v_account_id;
        
        -- Find destination postal center
        SELECT pc.id, pc.code, pc.name
        INTO v_dest_center
        FROM postal_centers pc
        JOIN cities c ON pc.city_id = c.id
        WHERE c.name = v_onedb_record.destination_city_name
        AND pc.carrier_id = v_carrier.id
        AND pc.account_id = v_account_id;
        
        IF v_origin_center.id IS NULL OR v_dest_center.id IS NULL THEN
            RAISE WARNING '   ⚠️  Centers not found for: % → %', 
                v_onedb_record.origin_city_name, v_onedb_record.destination_city_name;
            CONTINUE;
        END IF;
        
        -- Find readers
        SELECT reader_id INTO v_origin_entry_reader
        FROM readers
        WHERE postal_center_id = v_origin_center.id
        AND reader_type = 'Entry';
        
        SELECT reader_id INTO v_origin_exit_reader
        FROM readers
        WHERE postal_center_id = v_origin_center.id
        AND reader_type = 'Exit';
        
        SELECT reader_id INTO v_dest_entry_reader
        FROM readers
        WHERE postal_center_id = v_dest_center.id
        AND reader_type = 'Entry';
        
        SELECT reader_id INTO v_dest_exit_reader
        FROM readers
        WHERE postal_center_id = v_dest_center.id
        AND reader_type = 'Exit';
        
        IF v_origin_entry_reader IS NULL OR v_origin_exit_reader IS NULL OR
           v_dest_entry_reader IS NULL OR v_dest_exit_reader IS NULL THEN
            RAISE WARNING '   ⚠️  Readers not found for centers';
            CONTINUE;
        END IF;
        
        -- Calculate timing
        v_base_time := v_onedb_record.sent_at;
        v_processing_time := INTERVAL '2 hours' + (INTERVAL '1 hour' * random() * 2);
        v_transit_time := v_onedb_record.received_at - v_onedb_record.sent_at - (v_processing_time * 2);
        
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
                is_processed
            ) VALUES (
                v_account_id,
                v_onedb_record.tag_id || '-ORIGIN-ENTRY-' || i,
                v_entry_time + (INTERVAL '1 second' * i),
                v_origin_entry_reader,
                v_onedb_record.tag_id,
                FALSE
            );
        END LOOP;
        
        -- Exit from origin (5 reads)
        v_exit_time := v_entry_time + v_processing_time;
        FOR i IN 1..5 LOOP
            INSERT INTO rfid_events_raw (
                account_id,
                event_id,
                read_local_datetime,
                reader_id,
                tag_id,
                is_processed
            ) VALUES (
                v_account_id,
                v_onedb_record.tag_id || '-ORIGIN-EXIT-' || i,
                v_exit_time + (INTERVAL '1 second' * i),
                v_origin_exit_reader,
                v_onedb_record.tag_id,
                FALSE
            );
        END LOOP;
        
        -- ===== DESTINATION CENTER EVENTS =====
        
        -- Entry at destination (5 reads)
        v_entry_time := v_exit_time + v_transit_time;
        FOR i IN 1..5 LOOP
            INSERT INTO rfid_events_raw (
                account_id,
                event_id,
                read_local_datetime,
                reader_id,
                tag_id,
                is_processed
            ) VALUES (
                v_account_id,
                v_onedb_record.tag_id || '-DEST-ENTRY-' || i,
                v_entry_time + (INTERVAL '1 second' * i),
                v_dest_entry_reader,
                v_onedb_record.tag_id,
                FALSE
            );
        END LOOP;
        
        -- Exit from destination (5 reads)
        v_exit_time := v_entry_time + v_processing_time;
        FOR i IN 1..5 LOOP
            INSERT INTO rfid_events_raw (
                account_id,
                event_id,
                read_local_datetime,
                reader_id,
                tag_id,
                is_processed
            ) VALUES (
                v_account_id,
                v_onedb_record.tag_id || '-DEST-EXIT-' || i,
                v_exit_time + (INTERVAL '1 second' * i),
                v_dest_exit_reader,
                v_onedb_record.tag_id,
                FALSE
            );
        END LOOP;
        
        v_events_generated := v_events_generated + 20;
        
        IF v_events_generated % 100 = 0 THEN
            RAISE NOTICE '   Progress: % events generated...', v_events_generated;
        END IF;
    END LOOP;
    
    RAISE NOTICE '';
    RAISE NOTICE '✅ EPCIS raw events generated: % events', v_events_generated;
END $$;

-- =====================================================
-- STEP 9: Verification queries
-- =====================================================

-- Summary of generated data
SELECT 
    '🎯 Test Data Summary' as section,
    (SELECT COUNT(*) FROM cities WHERE account_id = (SELECT id FROM auth.users LIMIT 1)) as cities,
    (SELECT COUNT(*) FROM carriers WHERE account_id = (SELECT id FROM auth.users LIMIT 1)) as carriers,
    (SELECT COUNT(*) FROM products WHERE account_id = (SELECT id FROM auth.users LIMIT 1)) as products,
    (SELECT COUNT(*) FROM postal_centers WHERE account_id = (SELECT id FROM auth.users LIMIT 1)) as postal_centers,
    (SELECT COUNT(*) FROM readers WHERE account_id = (SELECT id FROM auth.users LIMIT 1)) as readers,
    (SELECT COUNT(*) FROM one_db WHERE account_id = (SELECT id FROM auth.users LIMIT 1) AND tag_id LIKE 'TEST-%') as one_db_entries,
    (SELECT COUNT(*) FROM rfid_events_raw WHERE account_id = (SELECT id FROM auth.users LIMIT 1) AND tag_id LIKE 'TEST-%') as rfid_events;

-- ONE DB routes summary
SELECT 
    carrier_name,
    product_name,
    origin_city_name || ' → ' || destination_city_name as route,
    COUNT(*) as shipments,
    ROUND(AVG(total_transit_days), 1) as avg_transit_days,
    ROUND(AVG(CASE WHEN on_time_delivery THEN 1 ELSE 0 END) * 100, 1) as on_time_pct
FROM one_db
WHERE account_id = (SELECT id FROM auth.users LIMIT 1)
AND tag_id LIKE 'TEST-%'
GROUP BY carrier_name, product_name, origin_city_name, destination_city_name
ORDER BY carrier_name, product_name, origin_city_name, destination_city_name;

-- RFID events by tag (sample)
SELECT 
    tag_id,
    COUNT(*) as event_count,
    MIN(read_local_datetime) as first_read,
    MAX(read_local_datetime) as last_read,
    MAX(read_local_datetime) - MIN(read_local_datetime) as duration
FROM rfid_events_raw
WHERE account_id = (SELECT id FROM auth.users LIMIT 1)
AND tag_id LIKE 'TEST-%'
GROUP BY tag_id
ORDER BY tag_id
LIMIT 10;

-- Readers with LPI codes
SELECT 
    pc.code as center_code,
    r.code as reader_code,
    r.reader_id as lpi_code,
    r.reader_type,
    r.status
FROM readers r
JOIN postal_centers pc ON r.postal_center_id = pc.id
WHERE r.account_id = (SELECT id FROM auth.users LIMIT 1)
ORDER BY pc.code, r.reader_type;

RAISE NOTICE '';
RAISE NOTICE '✅ ✅ ✅ TEST DATA GENERATION COMPLETE ✅ ✅ ✅';
RAISE NOTICE '';
RAISE NOTICE 'Next steps:';
RAISE NOTICE '1. Execute: SELECT execute_pipeline_phase(''consolidate'');';
RAISE NOTICE '2. Execute: SELECT execute_pipeline_phase(''segment'');';
RAISE NOTICE '3. Execute: SELECT execute_pipeline_phase(''aggregate'');';
RAISE NOTICE '4. View results in Route Path Analysis screen';
