-- =====================================================
-- Sprint 10.5: Configure Working Hours for DEMO2
-- =====================================================
-- Sets up account-level working hours (Mon-Fri 8am-6pm)
-- and configures postal centers to use working_days mode

DO $$
DECLARE
    v_account_id UUID;
BEGIN
    -- Get DEMO2 account
    SELECT id INTO v_account_id FROM accounts WHERE name = 'DEMO2';
    
    IF v_account_id IS NULL THEN
        RAISE EXCEPTION 'DEMO2 account not found';
    END IF;
    
    RAISE NOTICE 'Configuring working hours for DEMO2 (%)', v_account_id;
    
    -- =====================================================
    -- 1. SET POSTAL CENTERS TO WORKING_DAYS MODE
    -- =====================================================
    
    UPDATE postal_centers
    SET calculation_mode = 'working_days'
    WHERE account_id = v_account_id
      AND calculation_mode IS NULL;
    
    RAISE NOTICE 'Updated postal centers to working_days mode';
    
    -- =====================================================
    -- 2. CREATE ACCOUNT-LEVEL WEEKLY SCHEDULE
    -- =====================================================
    -- Monday to Friday: 8am - 6pm (working days)
    
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
        (v_account_id, NULL, 6, false, NULL, NULL)
    ON CONFLICT (account_id, postal_center_id, day_of_week) DO NOTHING;
    
    RAISE NOTICE 'Created account-level weekly schedule (Mon-Fri 8am-6pm)';
    
    -- =====================================================
    -- 3. ADD COMMON US HOLIDAYS FOR 2026
    -- =====================================================
    
    INSERT INTO non_working_days (account_id, postal_center_id, date, reason)
    VALUES 
        -- New Year's Day
        (v_account_id, NULL, '2026-01-01', 'New Year''s Day'),
        
        -- Martin Luther King Jr. Day (3rd Monday of January)
        (v_account_id, NULL, '2026-01-19', 'Martin Luther King Jr. Day'),
        
        -- Presidents' Day (3rd Monday of February)
        (v_account_id, NULL, '2026-02-16', 'Presidents'' Day'),
        
        -- Memorial Day (last Monday of May)
        (v_account_id, NULL, '2026-05-25', 'Memorial Day'),
        
        -- Independence Day
        (v_account_id, NULL, '2026-07-04', 'Independence Day'),
        
        -- Labor Day (1st Monday of September)
        (v_account_id, NULL, '2026-09-07', 'Labor Day'),
        
        -- Columbus Day (2nd Monday of October)
        (v_account_id, NULL, '2026-10-12', 'Columbus Day'),
        
        -- Veterans Day
        (v_account_id, NULL, '2026-11-11', 'Veterans Day'),
        
        -- Thanksgiving (4th Thursday of November)
        (v_account_id, NULL, '2026-11-26', 'Thanksgiving'),
        
        -- Christmas
        (v_account_id, NULL, '2026-12-25', 'Christmas')
    ON CONFLICT (account_id, postal_center_id, date) DO NOTHING;
    
    RAISE NOTICE 'Added US federal holidays for 2026';
    
    -- =====================================================
    -- VERIFICATION
    -- =====================================================
    
    RAISE NOTICE '✅ Working hours configuration completed';
    RAISE NOTICE 'Schedule: Monday-Friday 8am-6pm';
    RAISE NOTICE 'Holidays: 10 US federal holidays';
    
END $$;
