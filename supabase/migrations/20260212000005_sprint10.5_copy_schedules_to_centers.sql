-- =====================================================
-- Sprint 10.5: Copy Account Schedules to Postal Centers
-- =====================================================
-- Copies account-level schedules to each postal center
-- and fixes day_of_week mapping (ISODOW vs 0-6)

DO $$
DECLARE
    v_account_id UUID;
    v_center RECORD;
BEGIN
    -- Get DEMO2 account
    SELECT id INTO v_account_id FROM accounts WHERE name = 'DEMO2';
    
    IF v_account_id IS NULL THEN
        RAISE EXCEPTION 'DEMO2 account not found';
    END IF;
    
    RAISE NOTICE 'Copying schedules to postal centers for DEMO2';
    
    -- =====================================================
    -- 1. FIX DAY_OF_WEEK MAPPING IN ACCOUNT SCHEDULE
    -- =====================================================
    -- The function uses ISODOW (1=Mon, 7=Sun) but table uses (0=Sun, 6=Sat)
    -- We need to convert: 0→7, 1→1, 2→2, ..., 6→6
    -- Actually, let's recreate with ISODOW mapping
    
    -- Delete existing account schedules
    DELETE FROM weekly_schedule 
    WHERE account_id = v_account_id 
      AND postal_center_id IS NULL;
    
    -- Recreate with day_of_week mapping (0=Sunday, 1=Monday, ..., 6=Saturday)
    -- But the function uses ISODOW (1=Monday, 7=Sunday)
    -- So we need to map: ISODOW 1→table 1, ISODOW 7→table 0
    INSERT INTO weekly_schedule (account_id, postal_center_id, day_of_week, is_working_day, opening_hour, cutoff_time)
    VALUES 
        -- Sunday (0) - Non-working
        (v_account_id, NULL, 0, false, NULL, NULL),
        
        -- Monday (1) - Working 8am-6pm
        (v_account_id, NULL, 1, true, '08:00:00', '18:00:00'),
        
        -- Tuesday (2) - Working 8am-6pm
        (v_account_id, NULL, 2, true, '08:00:00', '18:00:00'),
        
        -- Wednesday (3) - Working 8am-6pm
        (v_account_id, NULL, 3, true, '08:00:00', '18:00:00'),
        
        -- Thursday (4) - Working 8am-6pm
        (v_account_id, NULL, 4, true, '08:00:00', '18:00:00'),
        
        -- Friday (5) - Working 8am-6pm
        (v_account_id, NULL, 5, true, '08:00:00', '18:00:00'),
        
        -- Saturday (6) - Non-working
        (v_account_id, NULL, 6, false, NULL, NULL);
    
    RAISE NOTICE 'Fixed account-level schedule with ISODOW mapping';
    
    -- =====================================================
    -- 2. COPY SCHEDULES TO EACH POSTAL CENTER
    -- =====================================================
    
    FOR v_center IN 
        SELECT id, code, name 
        FROM postal_centers 
        WHERE account_id = v_account_id
    LOOP
        -- Copy account schedule to this center
        INSERT INTO weekly_schedule (account_id, postal_center_id, day_of_week, is_working_day, opening_hour, cutoff_time)
        SELECT 
            account_id,
            v_center.id,  -- Set postal_center_id
            day_of_week,
            is_working_day,
            opening_hour,
            cutoff_time
        FROM weekly_schedule
        WHERE account_id = v_account_id
          AND postal_center_id IS NULL
        ON CONFLICT (account_id, postal_center_id, day_of_week) DO NOTHING;
        
        -- Copy holidays to this center
        INSERT INTO non_working_days (account_id, postal_center_id, date, reason)
        SELECT 
            account_id,
            v_center.id,  -- Set postal_center_id
            date,
            reason
        FROM non_working_days
        WHERE account_id = v_account_id
          AND postal_center_id IS NULL
        ON CONFLICT (account_id, postal_center_id, date) DO NOTHING;
        
        RAISE NOTICE 'Copied schedule to center: % (%)', v_center.name, v_center.code;
    END LOOP;
    
    RAISE NOTICE '✅ Schedules copied to all postal centers';
    
END $$;
