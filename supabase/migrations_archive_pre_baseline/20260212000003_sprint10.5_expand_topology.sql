-- =====================================================
-- Sprint 10.5: Data Architecture & Preparation
-- Phase 3: Expand Topology
-- Date: 2026-02-12
-- =====================================================
-- Creates additional postal centers and associates carriers
-- =====================================================

DO $$
DECLARE
    v_account_id UUID;
    v_carrier_usps UUID;
    v_carrier_fedex UUID;
    v_center_id UUID;
    v_reader_id UUID;
    v_pc_bal_lc UUID;
    v_pc_phl_hub UUID;
    v_pc_chi_dc UUID;
    v_pc_den_hub UUID;
    v_pc_sfo_pc UUID;
BEGIN
    -- Get DEMO2 account
    SELECT id INTO v_account_id FROM accounts WHERE name = 'DEMO2' LIMIT 1;
    
    IF v_account_id IS NULL THEN
        RAISE EXCEPTION 'DEMO2 account not found';
    END IF;
    
    RAISE NOTICE 'Using account: DEMO2 (%)', v_account_id;
    
    -- =====================================================
    -- 1. CREATE OR GET CARRIERS
    -- =====================================================
    
    -- USPS
    INSERT INTO carriers (account_id, name, code, type, status)
    VALUES (v_account_id, 'USPS', 'USPS', 'Postal Service', 'active')
    ON CONFLICT (account_id, code) DO NOTHING
    RETURNING id INTO v_carrier_usps;
    
    IF v_carrier_usps IS NULL THEN
        SELECT id INTO v_carrier_usps FROM carriers WHERE account_id = v_account_id AND code = 'USPS';
    END IF;
    
    -- FedEx
    INSERT INTO carriers (account_id, name, code, type, status)
    VALUES (v_account_id, 'FedEx', 'FEDEX', 'Express Courier', 'active')
    ON CONFLICT (account_id, code) DO NOTHING
    RETURNING id INTO v_carrier_fedex;
    
    IF v_carrier_fedex IS NULL THEN
        SELECT id INTO v_carrier_fedex FROM carriers WHERE account_id = v_account_id AND code = 'FEDEX';
    END IF;
    
    RAISE NOTICE 'Carriers: USPS=%, FedEx=%', v_carrier_usps, v_carrier_fedex;
    
    -- =====================================================
    -- 2. ADD POSTAL CENTERS
    -- =====================================================
    
    -- Get existing Baltimore Local Center
    SELECT id INTO v_pc_bal_lc FROM postal_centers WHERE account_id = v_account_id AND code = 'BAL-LC' LIMIT 1;
    
    -- Philadelphia Regional Hub
    INSERT INTO postal_centers (account_id, code, name, description, is_active)
    VALUES (v_account_id, 'PHL-HUB', 'Philadelphia Regional Hub', 'Regional processing hub for Philadelphia area', true)
    ON CONFLICT (account_id, code) DO NOTHING
    RETURNING id INTO v_pc_phl_hub;
    
    IF v_pc_phl_hub IS NULL THEN
        SELECT id INTO v_pc_phl_hub FROM postal_centers WHERE account_id = v_account_id AND code = 'PHL-HUB';
    END IF;
    
    -- Chicago Distribution Center
    INSERT INTO postal_centers (account_id, code, name, description, is_active)
    VALUES (v_account_id, 'CHI-DC', 'Chicago Distribution Center', 'Main distribution center for Midwest region', true)
    ON CONFLICT (account_id, code) DO NOTHING
    RETURNING id INTO v_pc_chi_dc;
    
    IF v_pc_chi_dc IS NULL THEN
        SELECT id INTO v_pc_chi_dc FROM postal_centers WHERE account_id = v_account_id AND code = 'CHI-DC';
    END IF;
    
    -- Denver Regional Hub
    INSERT INTO postal_centers (account_id, code, name, description, is_active)
    VALUES (v_account_id, 'DEN-HUB', 'Denver Regional Hub', 'Regional hub for Mountain region', true)
    ON CONFLICT (account_id, code) DO NOTHING
    RETURNING id INTO v_pc_den_hub;
    
    IF v_pc_den_hub IS NULL THEN
        SELECT id INTO v_pc_den_hub FROM postal_centers WHERE account_id = v_account_id AND code = 'DEN-HUB';
    END IF;
    
    -- San Francisco Processing Center
    INSERT INTO postal_centers (account_id, code, name, description, is_active)
    VALUES (v_account_id, 'SFO-PC', 'San Francisco Processing Center', 'West Coast processing center', true)
    ON CONFLICT (account_id, code) DO NOTHING
    RETURNING id INTO v_pc_sfo_pc;
    
    IF v_pc_sfo_pc IS NULL THEN
        SELECT id INTO v_pc_sfo_pc FROM postal_centers WHERE account_id = v_account_id AND code = 'SFO-PC';
    END IF;
    
    RAISE NOTICE 'Postal centers created/verified';
    
    -- =====================================================
    -- 3. ASSOCIATE CARRIERS TO CENTERS
    -- =====================================================
    
    -- Baltimore Local Center
    IF v_pc_bal_lc IS NOT NULL THEN
        INSERT INTO postal_center_carriers (postal_center_id, carrier_id) VALUES (v_pc_bal_lc, v_carrier_usps) ON CONFLICT DO NOTHING;
        INSERT INTO postal_center_carriers (postal_center_id, carrier_id) VALUES (v_pc_bal_lc, v_carrier_fedex) ON CONFLICT DO NOTHING;
    END IF;
    
    -- Philadelphia Regional Hub
    INSERT INTO postal_center_carriers (postal_center_id, carrier_id) VALUES (v_pc_phl_hub, v_carrier_usps) ON CONFLICT DO NOTHING;
    INSERT INTO postal_center_carriers (postal_center_id, carrier_id) VALUES (v_pc_phl_hub, v_carrier_fedex) ON CONFLICT DO NOTHING;
    
    -- Chicago Distribution Center
    INSERT INTO postal_center_carriers (postal_center_id, carrier_id) VALUES (v_pc_chi_dc, v_carrier_usps) ON CONFLICT DO NOTHING;
    INSERT INTO postal_center_carriers (postal_center_id, carrier_id) VALUES (v_pc_chi_dc, v_carrier_fedex) ON CONFLICT DO NOTHING;
    
    -- Denver Regional Hub
    INSERT INTO postal_center_carriers (postal_center_id, carrier_id) VALUES (v_pc_den_hub, v_carrier_usps) ON CONFLICT DO NOTHING;
    INSERT INTO postal_center_carriers (postal_center_id, carrier_id) VALUES (v_pc_den_hub, v_carrier_fedex) ON CONFLICT DO NOTHING;
    
    -- San Francisco Processing Center
    INSERT INTO postal_center_carriers (postal_center_id, carrier_id) VALUES (v_pc_sfo_pc, v_carrier_usps) ON CONFLICT DO NOTHING;
    INSERT INTO postal_center_carriers (postal_center_id, carrier_id) VALUES (v_pc_sfo_pc, v_carrier_fedex) ON CONFLICT DO NOTHING;
    
    RAISE NOTICE 'Carriers associated to centers';
    
    -- =====================================================
    -- 4. ADD READERS TO NEW CENTERS
    -- =====================================================
    
    -- Philadelphia Hub
    INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
    VALUES 
        (v_account_id, v_pc_phl_hub, 'PHL-HUB-R01', 'Philadelphia Hub Entry', 'Entry', true),
        (v_account_id, v_pc_phl_hub, 'PHL-HUB-R02', 'Philadelphia Hub Exit', 'Exit', true)
    ON CONFLICT (account_id, reader_id) DO NOTHING;
    
    -- Chicago DC
    INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
    VALUES 
        (v_account_id, v_pc_chi_dc, 'CHI-DC-R01', 'Chicago DC Entry', 'Entry', true),
        (v_account_id, v_pc_chi_dc, 'CHI-DC-R02', 'Chicago DC Exit', 'Exit', true)
    ON CONFLICT (account_id, reader_id) DO NOTHING;
    
    -- Denver Hub
    INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
    VALUES 
        (v_account_id, v_pc_den_hub, 'DEN-HUB-R01', 'Denver Hub Entry', 'Entry', true),
        (v_account_id, v_pc_den_hub, 'DEN-HUB-R02', 'Denver Hub Exit', 'Exit', true)
    ON CONFLICT (account_id, reader_id) DO NOTHING;
    
    -- San Francisco PC
    INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
    VALUES 
        (v_account_id, v_pc_sfo_pc, 'SFO-PC-R01', 'San Francisco PC Entry', 'Entry', true),
        (v_account_id, v_pc_sfo_pc, 'SFO-PC-R02', 'San Francisco PC Exit', 'Exit', true)
    ON CONFLICT (account_id, reader_id) DO NOTHING;
    
    RAISE NOTICE 'Readers created';
    
    -- =====================================================
    -- 5. POPULATE READER LOCATION HISTORY
    -- =====================================================
    
    INSERT INTO reader_location_history (reader_id, postal_center_id, assigned_at)
    SELECT r.id, r.postal_center_id, NOW()
    FROM readers r
    WHERE r.account_id = v_account_id 
      AND r.postal_center_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM reader_location_history WHERE reader_id = r.id);
    
    RAISE NOTICE 'Reader location history populated';
    
    -- =====================================================
    -- 6. ADD SLAs FOR KEY ROUTES
    -- =====================================================
    
    -- Operational SLAs (within centers) - 30 minutes processing time
    INSERT INTO slas (account_id, sla_type, postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    SELECT 
        v_account_id,
        'operational',
        pc.id,
        30,
        'minutes',
        95,
        85,
        70,
        true
    FROM postal_centers pc
    WHERE pc.account_id = v_account_id
      AND NOT EXISTS (
          SELECT 1 FROM slas s 
          WHERE s.account_id = v_account_id 
            AND s.sla_type = 'operational' 
            AND s.postal_center_id = pc.id
      );
    
    -- Distribution SLAs (between centers)
    
    -- Baltimore → Philadelphia (USPS): 4 hours
    IF v_pc_bal_lc IS NOT NULL AND v_pc_phl_hub IS NOT NULL THEN
        INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
        VALUES (v_account_id, 'distribution', v_pc_bal_lc, v_pc_phl_hub, v_carrier_usps, 240, 'minutes', 95, 85, 70, true)
        ON CONFLICT (account_id, from_postal_center_id, to_postal_center_id, carrier_id) DO NOTHING;
    END IF;
    
    -- Philadelphia → Chicago (USPS): 12 hours (long distance)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    VALUES (v_account_id, 'distribution', v_pc_phl_hub, v_pc_chi_dc, v_carrier_usps, 720, 'minutes', 90, 80, 65, true)
    ON CONFLICT (account_id, from_postal_center_id, to_postal_center_id, carrier_id) DO NOTHING;
    
    -- Chicago → Denver (FedEx): 8 hours (medium distance)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    VALUES (v_account_id, 'distribution', v_pc_chi_dc, v_pc_den_hub, v_carrier_fedex, 480, 'minutes', 92, 82, 67, true)
    ON CONFLICT (account_id, from_postal_center_id, to_postal_center_id, carrier_id) DO NOTHING;
    
    -- Denver → San Francisco (FedEx): 6 hours (medium distance)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    VALUES (v_account_id, 'distribution', v_pc_den_hub, v_pc_sfo_pc, v_carrier_fedex, 360, 'minutes', 92, 82, 67, true)
    ON CONFLICT (account_id, from_postal_center_id, to_postal_center_id, carrier_id) DO NOTHING;
    
    RAISE NOTICE 'SLAs created';
    
    RAISE NOTICE '✅ Topology expansion completed';
END $$;

-- =====================================================
-- END OF MIGRATION
-- =====================================================
