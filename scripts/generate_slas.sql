-- Generate realistic SLAs based on service type and distances
-- Run this in Supabase SQL Editor

DO $$
DECLARE
    v_account_id UUID;
    v_carrier_a_id UUID;
    v_carrier_b_id UUID;
    v_product_a_std_id UUID;
    v_product_a_exp_id UUID;
    v_product_b_std_id UUID;
    v_product_b_exp_id UUID;
    
    -- Postal centers
    v_bal_reg UUID;
    v_bal_loc UUID;
    v_chi_hub UUID;
    v_la_reg UUID;
    v_la_loc UUID;
    v_la_hub UUID;
    v_mem_hub UUID;
    v_ny_reg UUID;
    v_ny_loc UUID;
    v_ny_hub UUID;
    v_phl_hub UUID;
    v_sac_reg UUID;
    v_sac_loc UUID;
    
BEGIN
    -- Get account ID
    SELECT id INTO v_account_id FROM accounts LIMIT 1;
    
    -- Get carrier IDs
    SELECT id INTO v_carrier_a_id FROM carriers WHERE account_id = v_account_id AND name = 'Carrier A';
    SELECT id INTO v_carrier_b_id FROM carriers WHERE account_id = v_account_id AND name = 'Carrier B';
    
    -- Get product IDs
    SELECT id INTO v_product_a_std_id FROM products WHERE carrier_id = v_carrier_a_id AND code LIKE '%STANDARD%';
    SELECT id INTO v_product_a_exp_id FROM products WHERE carrier_id = v_carrier_a_id AND code LIKE '%EXPRESS%';
    SELECT id INTO v_product_b_std_id FROM products WHERE carrier_id = v_carrier_b_id AND code LIKE '%STANDARD%';
    SELECT id INTO v_product_b_exp_id FROM products WHERE carrier_id = v_carrier_b_id AND code LIKE '%EXPRESS%';
    
    -- Get postal center IDs
    SELECT id INTO v_bal_reg FROM postal_centers WHERE account_id = v_account_id AND code = 'BAL-REG-01';
    SELECT id INTO v_bal_loc FROM postal_centers WHERE account_id = v_account_id AND code = 'BAL-LOC-01';
    SELECT id INTO v_chi_hub FROM postal_centers WHERE account_id = v_account_id AND code = 'CHI-HUB-A';
    SELECT id INTO v_la_reg FROM postal_centers WHERE account_id = v_account_id AND code = 'LA-REG-01';
    SELECT id INTO v_la_loc FROM postal_centers WHERE account_id = v_account_id AND code = 'LA-LOC-01';
    SELECT id INTO v_la_hub FROM postal_centers WHERE account_id = v_account_id AND code = 'LA-HUB-A';
    SELECT id INTO v_mem_hub FROM postal_centers WHERE account_id = v_account_id AND code = 'MEM-HUB-B';
    SELECT id INTO v_ny_reg FROM postal_centers WHERE account_id = v_account_id AND code = 'NY-REG-01';
    SELECT id INTO v_ny_loc FROM postal_centers WHERE account_id = v_account_id AND code = 'NY-LOC-01';
    SELECT id INTO v_ny_hub FROM postal_centers WHERE account_id = v_account_id AND code = 'NY-HUB-A';
    SELECT id INTO v_phl_hub FROM postal_centers WHERE account_id = v_account_id AND code = 'PHL-HUB-B';
    SELECT id INTO v_sac_reg FROM postal_centers WHERE account_id = v_account_id AND code = 'SAC-REG-01';
    SELECT id INTO v_sac_loc FROM postal_centers WHERE account_id = v_account_id AND code = 'SAC-LOC-01';
    
    -- ========================================
    -- OPERATIONAL SLAs (Entry → Exit)
    -- ========================================
    -- EXPRESS: 2 hours (120 min)
    -- STANDARD: 6 hours (360 min)
    
    -- Generate operational SLAs for all centers × carriers × products
    INSERT INTO slas (account_id, sla_type, postal_center_id, carrier_id, product_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
    SELECT 
        v_account_id,
        'operational',
        pc.id,
        p.carrier_id,
        p.id,
        CASE WHEN p.code LIKE '%EXPRESS%' THEN 120 ELSE 360 END,
        'minutes',
        95,
        90,
        80,
        true
    FROM postal_centers pc
    CROSS JOIN products p
    WHERE pc.account_id = v_account_id AND p.account_id = v_account_id;
    
    -- ========================================
    -- DISTRIBUTION SLAs (between centers)
    -- ========================================
    -- Times based on distance and service type
    
    -- Baltimore ↔ New York (169 mi - short distance)
    -- EXPRESS: ~5h, STANDARD: ~12h
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, product_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active) VALUES
    (v_account_id, 'distribution', v_bal_reg, v_ny_reg, v_carrier_a_id, v_product_a_exp_id, 300, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_bal_reg, v_ny_reg, v_carrier_a_id, v_product_a_std_id, 720, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_ny_reg, v_bal_reg, v_carrier_a_id, v_product_a_exp_id, 300, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_ny_reg, v_bal_reg, v_carrier_a_id, v_product_a_std_id, 720, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_bal_loc, v_ny_loc, v_carrier_b_id, v_product_b_exp_id, 300, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_bal_loc, v_ny_loc, v_carrier_b_id, v_product_b_std_id, 720, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_ny_loc, v_bal_loc, v_carrier_b_id, v_product_b_exp_id, 300, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_ny_loc, v_bal_loc, v_carrier_b_id, v_product_b_std_id, 720, 'minutes', 95, 90, 80, true);
    
    -- Los Angeles ↔ Sacramento (361 mi - medium distance)
    -- EXPRESS: ~9h, STANDARD: ~20h
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, product_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active) VALUES
    (v_account_id, 'distribution', v_la_reg, v_sac_reg, v_carrier_a_id, v_product_a_exp_id, 540, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_reg, v_sac_reg, v_carrier_a_id, v_product_a_std_id, 1200, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_sac_reg, v_la_reg, v_carrier_a_id, v_product_a_exp_id, 540, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_sac_reg, v_la_reg, v_carrier_a_id, v_product_a_std_id, 1200, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_loc, v_sac_loc, v_carrier_b_id, v_product_b_exp_id, 540, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_loc, v_sac_loc, v_carrier_b_id, v_product_b_std_id, 1200, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_sac_loc, v_la_loc, v_carrier_b_id, v_product_b_exp_id, 540, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_sac_loc, v_la_loc, v_carrier_b_id, v_product_b_std_id, 1200, 'minutes', 95, 90, 80, true);
    
    -- East Coast ↔ West Coast (2300+ mi - long distance, air transport)
    -- EXPRESS: ~10h (air), STANDARD: ~48h (air/truck)
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, product_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active) VALUES
    (v_account_id, 'distribution', v_bal_reg, v_la_reg, v_carrier_a_id, v_product_a_exp_id, 600, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_bal_reg, v_la_reg, v_carrier_a_id, v_product_a_std_id, 2880, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_reg, v_bal_reg, v_carrier_a_id, v_product_a_exp_id, 600, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_reg, v_bal_reg, v_carrier_a_id, v_product_a_std_id, 2880, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_ny_reg, v_la_reg, v_carrier_a_id, v_product_a_exp_id, 600, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_ny_reg, v_la_reg, v_carrier_a_id, v_product_a_std_id, 2880, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_reg, v_ny_reg, v_carrier_a_id, v_product_a_exp_id, 600, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_reg, v_ny_reg, v_carrier_a_id, v_product_a_std_id, 2880, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_bal_loc, v_la_loc, v_carrier_b_id, v_product_b_exp_id, 600, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_bal_loc, v_la_loc, v_carrier_b_id, v_product_b_std_id, 2880, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_loc, v_bal_loc, v_carrier_b_id, v_product_b_exp_id, 600, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_loc, v_bal_loc, v_carrier_b_id, v_product_b_std_id, 2880, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_ny_loc, v_la_loc, v_carrier_b_id, v_product_b_exp_id, 600, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_ny_loc, v_la_loc, v_carrier_b_id, v_product_b_std_id, 2880, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_loc, v_ny_loc, v_carrier_b_id, v_product_b_exp_id, 600, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_loc, v_ny_loc, v_carrier_b_id, v_product_b_std_id, 2880, 'minutes', 95, 90, 80, true);
    
    -- Hub connections (shorter times for hub-to-hub)
    -- Hubs are optimized for fast transfers
    INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, carrier_id, product_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active) VALUES
    (v_account_id, 'distribution', v_ny_hub, v_chi_hub, v_carrier_a_id, v_product_a_exp_id, 240, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_ny_hub, v_chi_hub, v_carrier_a_id, v_product_a_std_id, 720, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_chi_hub, v_ny_hub, v_carrier_a_id, v_product_a_exp_id, 240, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_chi_hub, v_ny_hub, v_carrier_a_id, v_product_a_std_id, 720, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_chi_hub, v_la_hub, v_carrier_a_id, v_product_a_exp_id, 360, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_chi_hub, v_la_hub, v_carrier_a_id, v_product_a_std_id, 1440, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_hub, v_chi_hub, v_carrier_a_id, v_product_a_exp_id, 360, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_la_hub, v_chi_hub, v_carrier_a_id, v_product_a_std_id, 1440, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_phl_hub, v_mem_hub, v_carrier_b_id, v_product_b_exp_id, 300, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_phl_hub, v_mem_hub, v_carrier_b_id, v_product_b_std_id, 960, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_mem_hub, v_phl_hub, v_carrier_b_id, v_product_b_exp_id, 300, 'minutes', 95, 90, 80, true),
    (v_account_id, 'distribution', v_mem_hub, v_phl_hub, v_carrier_b_id, v_product_b_std_id, 960, 'minutes', 95, 90, 80, true);
    
    RAISE NOTICE 'SLAs generated successfully!';
    
END $$;

-- Verify counts
SELECT 
    sla_type,
    COUNT(*) as count,
    ROUND(AVG(expected_time_minutes)/60.0, 1) as avg_hours
FROM slas
GROUP BY sla_type
ORDER BY sla_type;
