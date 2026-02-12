-- =====================================================
-- Sprint 10.5: Assign Carriers to SLAs
-- =====================================================
-- Creates carrier-specific SLAs for each route

DO $$
DECLARE
    v_account_id UUID;
    v_usps_id UUID;
    v_fedex_id UUID;
    v_sla RECORD;
BEGIN
    -- Get DEMO2 account
    SELECT id INTO v_account_id FROM accounts WHERE name = 'DEMO2';
    
    IF v_account_id IS NULL THEN
        RAISE EXCEPTION 'DEMO2 account not found';
    END IF;
    
    -- Get carrier IDs
    SELECT id INTO v_usps_id FROM carriers WHERE account_id = v_account_id AND code = 'USPS';
    SELECT id INTO v_fedex_id FROM carriers WHERE account_id = v_account_id AND code = 'FEDEX';
    
    IF v_usps_id IS NULL OR v_fedex_id IS NULL THEN
        RAISE EXCEPTION 'Carriers not found';
    END IF;
    
    RAISE NOTICE 'Assigning carriers to SLAs for DEMO2';
    
    -- =====================================================
    -- 1. DELETE EXISTING SLAs (they have carrier_id = NULL)
    -- =====================================================
    
    DELETE FROM slas WHERE account_id = v_account_id;
    
    RAISE NOTICE 'Deleted existing SLAs without carriers';
    
    -- =====================================================
    -- 2. CREATE OPERATIONAL SLAs (one per center, no carrier)
    -- =====================================================
    
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
    WHERE pc.account_id = v_account_id;
    
    RAISE NOTICE 'Created operational SLAs';
    
    -- =====================================================
    -- 3. CREATE DISTRIBUTION SLAs (with carriers)
    -- =====================================================
    
    -- PHL-HUB → CHI-DC (USPS)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    SELECT 
        v_account_id,
        'distribution',
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'PHL-HUB'),
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'CHI-DC'),
        v_usps_id,
        600, -- 10 hours
        'minutes',
        92,
        82,
        67,
        true;
    
    -- PHL-HUB → CHI-DC (FedEx)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    SELECT 
        v_account_id,
        'distribution',
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'PHL-HUB'),
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'CHI-DC'),
        v_fedex_id,
        540, -- 9 hours (FedEx faster)
        'minutes',
        95,
        85,
        70,
        true;
    
    -- CHI-DC → DEN-HUB (USPS)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    SELECT 
        v_account_id,
        'distribution',
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'CHI-DC'),
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'DEN-HUB'),
        v_usps_id,
        480, -- 8 hours
        'minutes',
        92,
        82,
        67,
        true;
    
    -- CHI-DC → DEN-HUB (FedEx)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    SELECT 
        v_account_id,
        'distribution',
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'CHI-DC'),
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'DEN-HUB'),
        v_fedex_id,
        420, -- 7 hours
        'minutes',
        95,
        85,
        70,
        true;
    
    -- DEN-HUB → SFO-PC (USPS)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    SELECT 
        v_account_id,
        'distribution',
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'DEN-HUB'),
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'SFO-PC'),
        v_usps_id,
        720, -- 12 hours
        'minutes',
        90,
        80,
        65,
        true;
    
    -- DEN-HUB → SFO-PC (FedEx)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    SELECT 
        v_account_id,
        'distribution',
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'DEN-HUB'),
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'SFO-PC'),
        v_fedex_id,
        600, -- 10 hours
        'minutes',
        95,
        85,
        70,
        true;
    
    -- SFO-PC → DEN-HUB (reverse, USPS)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    SELECT 
        v_account_id,
        'distribution',
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'SFO-PC'),
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'DEN-HUB'),
        v_usps_id,
        720,
        'minutes',
        90,
        80,
        65,
        true;
    
    -- SFO-PC → DEN-HUB (reverse, FedEx)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    SELECT 
        v_account_id,
        'distribution',
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'SFO-PC'),
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'DEN-HUB'),
        v_fedex_id,
        600,
        'minutes',
        95,
        85,
        70,
        true;
    
    -- DEN-HUB → CHI-DC (reverse, USPS)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    SELECT 
        v_account_id,
        'distribution',
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'DEN-HUB'),
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'CHI-DC'),
        v_usps_id,
        480,
        'minutes',
        92,
        82,
        67,
        true;
    
    -- DEN-HUB → CHI-DC (reverse, FedEx)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    SELECT 
        v_account_id,
        'distribution',
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'DEN-HUB'),
        (SELECT id FROM postal_centers WHERE account_id = v_account_id AND code = 'CHI-DC'),
        v_fedex_id,
        420,
        'minutes',
        95,
        85,
        70,
        true;
    
    RAISE NOTICE 'Created distribution SLAs with carriers';
    RAISE NOTICE '✅ SLAs assigned to carriers successfully';
    
END $$;
