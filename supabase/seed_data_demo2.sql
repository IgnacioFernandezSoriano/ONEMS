-- Sprint 6.5: Seed Data for DEMO2 Account
-- Realistic postal network data for testing Network Diagnostics Module
-- Account: DEMO2 (f4d823d2-93e6-4755-9a89-9da87e7fa86e)
-- Cities: New York, Los Angeles, Baltimore, Sacramento

-- ============================================================================
-- PART 1: CLEANUP - Delete existing data for DEMO2
-- ============================================================================

DO $$
DECLARE
  demo2_account_id UUID := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
BEGIN
  -- Delete in correct order (respecting foreign keys)
  DELETE FROM journey_segments WHERE account_id = demo2_account_id;
  DELETE FROM processed_events WHERE account_id = demo2_account_id;
  DELETE FROM incidents WHERE account_id = demo2_account_id;
  DELETE FROM journeys WHERE account_id = demo2_account_id;
  DELETE FROM slas WHERE account_id = demo2_account_id;
  DELETE FROM readers WHERE account_id = demo2_account_id;
  DELETE FROM non_working_days WHERE account_id = demo2_account_id;
  DELETE FROM weekly_schedule WHERE account_id = demo2_account_id;
  DELETE FROM postal_centers WHERE account_id = demo2_account_id;
  
  RAISE NOTICE 'Cleanup completed for DEMO2 account';
END $$;

-- ============================================================================
-- PART 2: POSTAL CENTERS (11 centers across 4 cities)
-- ============================================================================

-- Variables
DO $$
DECLARE
  demo2_account_id UUID := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  
  -- City IDs
  ny_city_id UUID := 'baf4eb83-9012-4482-ab6d-c9c61a155974';
  la_city_id UUID := 'f660c72c-9811-4804-a36f-51b6771eb9a2';
  baltimore_city_id UUID := '8a54b748-16c7-47c1-a927-197b1a318264';
  sacramento_city_id UUID := '6a955d6e-290d-4862-93b3-a036dc08d6c9';
  
  -- Postal Center IDs (will be generated)
  ny_hub_central_id UUID;
  ny_hub_jfk_id UUID;
  ny_regional_brooklyn_id UUID;
  la_hub_downtown_id UUID;
  la_regional_lax_id UUID;
  baltimore_regional_id UUID;
  baltimore_local_id UUID;
  sacramento_regional_id UUID;
  sacramento_local_id UUID;
  
BEGIN
  -- New York Centers (3 centers - major hub)
  INSERT INTO postal_centers (account_id, code, name, description, calculation_mode, is_active)
  VALUES 
    (demo2_account_id, 'NY-HUB-01', 'New York Hub Central', 'Main distribution hub in Manhattan', 'working_days', true)
  RETURNING id INTO ny_hub_central_id;
  
  INSERT INTO postal_centers (account_id, code, name, description, calculation_mode, is_active)
  VALUES 
    (demo2_account_id, 'NY-HUB-02', 'New York Hub JFK', 'Airport hub near JFK International', 'working_days', true)
  RETURNING id INTO ny_hub_jfk_id;
  
  INSERT INTO postal_centers (account_id, code, name, description, calculation_mode, is_active)
  VALUES 
    (demo2_account_id, 'NY-REG-01', 'New York Regional Brooklyn', 'Regional center in Brooklyn', 'working_days', true)
  RETURNING id INTO ny_regional_brooklyn_id;
  
  -- Los Angeles Centers (3 centers - major hub)
  INSERT INTO postal_centers (account_id, code, name, description, calculation_mode, is_active)
  VALUES 
    (demo2_account_id, 'LA-HUB-01', 'Los Angeles Hub Downtown', 'Main distribution hub in Downtown LA', 'working_days', true)
  RETURNING id INTO la_hub_downtown_id;
  
  INSERT INTO postal_centers (account_id, code, name, description, calculation_mode, is_active)
  VALUES 
    (demo2_account_id, 'LA-REG-01', 'Los Angeles Regional LAX', 'Regional center near LAX Airport', 'working_days', true)
  RETURNING id INTO la_regional_lax_id;
  
  INSERT INTO postal_centers (account_id, code, name, description, calculation_mode, is_active)
  VALUES 
    (demo2_account_id, 'LA-REG-02', 'Los Angeles Regional Long Beach', 'Regional center in Long Beach', 'working_days', true);
  
  -- Baltimore Centers (2 centers - regional)
  INSERT INTO postal_centers (account_id, code, name, description, calculation_mode, is_active)
  VALUES 
    (demo2_account_id, 'BAL-REG-01', 'Baltimore Regional Center', 'Main regional center', 'working_days', true)
  RETURNING id INTO baltimore_regional_id;
  
  INSERT INTO postal_centers (account_id, code, name, description, calculation_mode, is_active)
  VALUES 
    (demo2_account_id, 'BAL-LOC-01', 'Baltimore Local Center', 'Local distribution center', 'working_days', true)
  RETURNING id INTO baltimore_local_id;
  
  -- Sacramento Centers (2 centers - regional)
  INSERT INTO postal_centers (account_id, code, name, description, calculation_mode, is_active)
  VALUES 
    (demo2_account_id, 'SAC-REG-01', 'Sacramento Regional Center', 'Main regional center', 'working_days', true)
  RETURNING id INTO sacramento_regional_id;
  
  INSERT INTO postal_centers (account_id, code, name, description, calculation_mode, is_active)
  VALUES 
    (demo2_account_id, 'SAC-LOC-01', 'Sacramento Local Center', 'Local distribution center', 'working_days', true)
  RETURNING id INTO sacramento_local_id;
  
  RAISE NOTICE 'Created 11 postal centers';
  
  -- Store IDs in temporary table for next steps
  CREATE TEMP TABLE temp_center_ids (
    code TEXT PRIMARY KEY,
    center_id UUID NOT NULL
  );
  
  INSERT INTO temp_center_ids VALUES
    ('NY-HUB-01', ny_hub_central_id),
    ('NY-HUB-02', ny_hub_jfk_id),
    ('NY-REG-01', ny_regional_brooklyn_id),
    ('LA-HUB-01', la_hub_downtown_id),
    ('LA-REG-01', la_regional_lax_id),
    ('BAL-REG-01', baltimore_regional_id),
    ('BAL-LOC-01', baltimore_local_id),
    ('SAC-REG-01', sacramento_regional_id),
    ('SAC-LOC-01', sacramento_local_id);
    
END $$;

-- ============================================================================
-- PART 3: WEEKLY SCHEDULES (Account-level default)
-- ============================================================================

INSERT INTO weekly_schedule (account_id, postal_center_id, day_of_week, is_working_day, opening_hour, cutoff_time)
VALUES
  -- Monday to Friday (working days)
  ('f4d823d2-93e6-4755-9a89-9da87e7fa86e', NULL, 1, true, '08:00:00', '16:00:00'),
  ('f4d823d2-93e6-4755-9a89-9da87e7fa86e', NULL, 2, true, '08:00:00', '16:00:00'),
  ('f4d823d2-93e6-4755-9a89-9da87e7fa86e', NULL, 3, true, '08:00:00', '16:00:00'),
  ('f4d823d2-93e6-4755-9a89-9da87e7fa86e', NULL, 4, true, '08:00:00', '16:00:00'),
  ('f4d823d2-93e6-4755-9a89-9da87e7fa86e', NULL, 5, true, '08:00:00', '16:00:00'),
  -- Saturday (half day)
  ('f4d823d2-93e6-4755-9a89-9da87e7fa86e', NULL, 6, true, '08:00:00', '12:00:00'),
  -- Sunday (non-working)
  ('f4d823d2-93e6-4755-9a89-9da87e7fa86e', NULL, 0, false, NULL, NULL);

-- ============================================================================
-- PART 4: NON-WORKING DAYS (Account-level holidays 2026)
-- ============================================================================

INSERT INTO non_working_days (account_id, postal_center_id, date, reason)
VALUES
  ('f4d823d2-93e6-4755-9a89-9da87e7fa86e', NULL, '2026-01-01', 'New Year''s Day'),
  ('f4d823d2-93e6-4755-9a89-9da87e7fa86e', NULL, '2026-07-04', 'Independence Day'),
  ('f4d823d2-93e6-4755-9a89-9da87e7fa86e', NULL, '2026-12-25', 'Christmas Day');

-- ============================================================================
-- PART 5: READERS (45 readers total)
-- ============================================================================

DO $$
DECLARE
  demo2_account_id UUID := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  center_rec RECORD;
BEGIN
  -- NY Hub Central (6 readers)
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'NY-HUB-01-R01', 'Entry Gate 1', 'Entry', true FROM temp_center_ids WHERE code = 'NY-HUB-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'NY-HUB-01-R02', 'Entry Gate 2', 'Entry', true FROM temp_center_ids WHERE code = 'NY-HUB-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'NY-HUB-01-R03', 'Exit Gate 1', 'Exit', true FROM temp_center_ids WHERE code = 'NY-HUB-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'NY-HUB-01-R04', 'Exit Gate 2', 'Exit', true FROM temp_center_ids WHERE code = 'NY-HUB-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, mixed_reader_gap_minutes, is_active)
  SELECT demo2_account_id, center_id, 'NY-HUB-01-R05', 'Mixed Sorting Line 1', 'Mixed', 30, true FROM temp_center_ids WHERE code = 'NY-HUB-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, mixed_reader_gap_minutes, is_active)
  SELECT demo2_account_id, center_id, 'NY-HUB-01-R06', 'Mixed Sorting Line 2', 'Mixed', 30, true FROM temp_center_ids WHERE code = 'NY-HUB-01';
  
  -- NY Hub JFK (5 readers)
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'NY-HUB-02-R01', 'Entry Gate 1', 'Entry', true FROM temp_center_ids WHERE code = 'NY-HUB-02';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'NY-HUB-02-R02', 'Entry Gate 2', 'Entry', true FROM temp_center_ids WHERE code = 'NY-HUB-02';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'NY-HUB-02-R03', 'Exit Gate 1', 'Exit', true FROM temp_center_ids WHERE code = 'NY-HUB-02';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'NY-HUB-02-R04', 'Exit Gate 2', 'Exit', true FROM temp_center_ids WHERE code = 'NY-HUB-02';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, mixed_reader_gap_minutes, is_active)
  SELECT demo2_account_id, center_id, 'NY-HUB-02-R05', 'Mixed Sorting Line', 'Mixed', 30, true FROM temp_center_ids WHERE code = 'NY-HUB-02';
  
  -- NY Regional Brooklyn (4 readers)
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'NY-REG-01-R01', 'Entry Gate', 'Entry', true FROM temp_center_ids WHERE code = 'NY-REG-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'NY-REG-01-R02', 'Exit Gate', 'Exit', true FROM temp_center_ids WHERE code = 'NY-REG-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, mixed_reader_gap_minutes, is_active)
  SELECT demo2_account_id, center_id, 'NY-REG-01-R03', 'Mixed Sorting Line 1', 'Mixed', 30, true FROM temp_center_ids WHERE code = 'NY-REG-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, mixed_reader_gap_minutes, is_active)
  SELECT demo2_account_id, center_id, 'NY-REG-01-R04', 'Mixed Sorting Line 2', 'Mixed', 30, true FROM temp_center_ids WHERE code = 'NY-REG-01';
  
  -- LA Hub Downtown (6 readers)
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'LA-HUB-01-R01', 'Entry Gate 1', 'Entry', true FROM temp_center_ids WHERE code = 'LA-HUB-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'LA-HUB-01-R02', 'Entry Gate 2', 'Entry', true FROM temp_center_ids WHERE code = 'LA-HUB-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'LA-HUB-01-R03', 'Exit Gate 1', 'Exit', true FROM temp_center_ids WHERE code = 'LA-HUB-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'LA-HUB-01-R04', 'Exit Gate 2', 'Exit', true FROM temp_center_ids WHERE code = 'LA-HUB-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, mixed_reader_gap_minutes, is_active)
  SELECT demo2_account_id, center_id, 'LA-HUB-01-R05', 'Mixed Sorting Line 1', 'Mixed', 30, true FROM temp_center_ids WHERE code = 'LA-HUB-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, mixed_reader_gap_minutes, is_active)
  SELECT demo2_account_id, center_id, 'LA-HUB-01-R06', 'Mixed Sorting Line 2', 'Mixed', 30, true FROM temp_center_ids WHERE code = 'LA-HUB-01';
  
  -- LA Regional LAX (4 readers)
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'LA-REG-01-R01', 'Entry Gate', 'Entry', true FROM temp_center_ids WHERE code = 'LA-REG-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'LA-REG-01-R02', 'Exit Gate', 'Exit', true FROM temp_center_ids WHERE code = 'LA-REG-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, mixed_reader_gap_minutes, is_active)
  SELECT demo2_account_id, center_id, 'LA-REG-01-R03', 'Mixed Sorting Line 1', 'Mixed', 30, true FROM temp_center_ids WHERE code = 'LA-REG-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, mixed_reader_gap_minutes, is_active)
  SELECT demo2_account_id, center_id, 'LA-REG-01-R04', 'Mixed Sorting Line 2', 'Mixed', 30, true FROM temp_center_ids WHERE code = 'LA-REG-01';
  
  -- Baltimore Regional (3 readers)
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'BAL-REG-01-R01', 'Entry Gate', 'Entry', true FROM temp_center_ids WHERE code = 'BAL-REG-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'BAL-REG-01-R02', 'Exit Gate', 'Exit', true FROM temp_center_ids WHERE code = 'BAL-REG-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, mixed_reader_gap_minutes, is_active)
  SELECT demo2_account_id, center_id, 'BAL-REG-01-R03', 'Mixed Sorting Line', 'Mixed', 30, true FROM temp_center_ids WHERE code = 'BAL-REG-01';
  
  -- Baltimore Local (2 readers)
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'BAL-LOC-01-R01', 'Entry Gate', 'Entry', true FROM temp_center_ids WHERE code = 'BAL-LOC-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'BAL-LOC-01-R02', 'Exit Gate', 'Exit', true FROM temp_center_ids WHERE code = 'BAL-LOC-01';
  
  -- Sacramento Regional (3 readers)
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'SAC-REG-01-R01', 'Entry Gate', 'Entry', true FROM temp_center_ids WHERE code = 'SAC-REG-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'SAC-REG-01-R02', 'Exit Gate', 'Exit', true FROM temp_center_ids WHERE code = 'SAC-REG-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, mixed_reader_gap_minutes, is_active)
  SELECT demo2_account_id, center_id, 'SAC-REG-01-R03', 'Mixed Sorting Line', 'Mixed', 30, true FROM temp_center_ids WHERE code = 'SAC-REG-01';
  
  -- Sacramento Local (2 readers)
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'SAC-LOC-01-R01', 'Entry Gate', 'Entry', true FROM temp_center_ids WHERE code = 'SAC-LOC-01';
  INSERT INTO readers (account_id, postal_center_id, reader_id, name, type, is_active)
  SELECT demo2_account_id, center_id, 'SAC-LOC-01-R02', 'Exit Gate', 'Exit', true FROM temp_center_ids WHERE code = 'SAC-LOC-01';
  
  RAISE NOTICE 'Created 38 readers across 9 centers';
END $$;

-- ============================================================================
-- PART 6: SLAs - OPERATIONAL (9 SLAs, one per center)
-- ============================================================================

DO $$
DECLARE
  demo2_account_id UUID := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
BEGIN
  -- Hub centers: 2-4 hours (120-240 minutes)
  INSERT INTO slas (account_id, sla_type, postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  SELECT demo2_account_id, 'operational', center_id, 180, 'minutes', 95, 85, 70, true FROM temp_center_ids WHERE code = 'NY-HUB-01';
  
  INSERT INTO slas (account_id, sla_type, postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  SELECT demo2_account_id, 'operational', center_id, 180, 'minutes', 95, 85, 70, true FROM temp_center_ids WHERE code = 'NY-HUB-02';
  
  INSERT INTO slas (account_id, sla_type, postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  SELECT demo2_account_id, 'operational', center_id, 180, 'minutes', 95, 85, 70, true FROM temp_center_ids WHERE code = 'LA-HUB-01';
  
  -- Regional centers: 1-3 hours (60-180 minutes)
  INSERT INTO slas (account_id, sla_type, postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  SELECT demo2_account_id, 'operational', center_id, 120, 'minutes', 95, 85, 70, true FROM temp_center_ids WHERE code = 'NY-REG-01';
  
  INSERT INTO slas (account_id, sla_type, postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  SELECT demo2_account_id, 'operational', center_id, 120, 'minutes', 95, 85, 70, true FROM temp_center_ids WHERE code = 'LA-REG-01';
  
  INSERT INTO slas (account_id, sla_type, postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  SELECT demo2_account_id, 'operational', center_id, 120, 'minutes', 95, 85, 70, true FROM temp_center_ids WHERE code = 'BAL-REG-01';
  
  INSERT INTO slas (account_id, sla_type, postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  SELECT demo2_account_id, 'operational', center_id, 120, 'minutes', 95, 85, 70, true FROM temp_center_ids WHERE code = 'SAC-REG-01';
  
  -- Local centers: 0.5-2 hours (30-120 minutes)
  INSERT INTO slas (account_id, sla_type, postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  SELECT demo2_account_id, 'operational', center_id, 60, 'minutes', 95, 85, 70, true FROM temp_center_ids WHERE code = 'BAL-LOC-01';
  
  INSERT INTO slas (account_id, sla_type, postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  SELECT demo2_account_id, 'operational', center_id, 60, 'minutes', 95, 85, 70, true FROM temp_center_ids WHERE code = 'SAC-LOC-01';
  
  RAISE NOTICE 'Created 9 operational SLAs';
END $$;

-- ============================================================================
-- PART 7: SLAs - DISTRIBUTION (Major routes between cities)
-- ============================================================================

DO $$
DECLARE
  demo2_account_id UUID := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  ny_hub_01 UUID;
  ny_hub_02 UUID;
  ny_reg_01 UUID;
  la_hub_01 UUID;
  la_reg_01 UUID;
  bal_reg_01 UUID;
  bal_loc_01 UUID;
  sac_reg_01 UUID;
  sac_loc_01 UUID;
BEGIN
  -- Get center IDs
  SELECT center_id INTO ny_hub_01 FROM temp_center_ids WHERE code = 'NY-HUB-01';
  SELECT center_id INTO ny_hub_02 FROM temp_center_ids WHERE code = 'NY-HUB-02';
  SELECT center_id INTO ny_reg_01 FROM temp_center_ids WHERE code = 'NY-REG-01';
  SELECT center_id INTO la_hub_01 FROM temp_center_ids WHERE code = 'LA-HUB-01';
  SELECT center_id INTO la_reg_01 FROM temp_center_ids WHERE code = 'LA-REG-01';
  SELECT center_id INTO bal_reg_01 FROM temp_center_ids WHERE code = 'BAL-REG-01';
  SELECT center_id INTO bal_loc_01 FROM temp_center_ids WHERE code = 'BAL-LOC-01';
  SELECT center_id INTO sac_reg_01 FROM temp_center_ids WHERE code = 'SAC-REG-01';
  SELECT center_id INTO sac_loc_01 FROM temp_center_ids WHERE code = 'SAC-LOC-01';
  
  -- Cross-country routes (NY <-> LA): 3-4 days (4320-5760 minutes)
  INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  VALUES 
    (demo2_account_id, 'distribution', ny_hub_01, la_hub_01, 5040, 'minutes', 90, 80, 65, true), -- 3.5 days
    (demo2_account_id, 'distribution', la_hub_01, ny_hub_01, 5040, 'minutes', 90, 80, 65, true);
  
  -- Regional routes (within East Coast): 1-2 days (1440-2880 minutes)
  INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  VALUES 
    (demo2_account_id, 'distribution', ny_hub_01, bal_reg_01, 1440, 'minutes', 92, 82, 67, true), -- 1 day
    (demo2_account_id, 'distribution', bal_reg_01, ny_hub_01, 1440, 'minutes', 92, 82, 67, true),
    (demo2_account_id, 'distribution', ny_hub_01, ny_reg_01, 720, 'minutes', 95, 85, 70, true), -- 0.5 day (local)
    (demo2_account_id, 'distribution', ny_reg_01, ny_hub_01, 720, 'minutes', 95, 85, 70, true);
  
  -- Regional routes (within West Coast): 1-2 days
  INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  VALUES 
    (demo2_account_id, 'distribution', la_hub_01, sac_reg_01, 1440, 'minutes', 92, 82, 67, true), -- 1 day
    (demo2_account_id, 'distribution', sac_reg_01, la_hub_01, 1440, 'minutes', 92, 82, 67, true),
    (demo2_account_id, 'distribution', la_hub_01, la_reg_01, 720, 'minutes', 95, 85, 70, true), -- 0.5 day (local)
    (demo2_account_id, 'distribution', la_reg_01, la_hub_01, 720, 'minutes', 95, 85, 70, true);
  
  -- Local routes (within city)
  INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  VALUES 
    (demo2_account_id, 'distribution', bal_reg_01, bal_loc_01, 480, 'minutes', 95, 85, 70, true), -- 8 hours
    (demo2_account_id, 'distribution', bal_loc_01, bal_reg_01, 480, 'minutes', 95, 85, 70, true),
    (demo2_account_id, 'distribution', sac_reg_01, sac_loc_01, 480, 'minutes', 95, 85, 70, true),
    (demo2_account_id, 'distribution', sac_loc_01, sac_reg_01, 480, 'minutes', 95, 85, 70, true);
  
  -- Additional cross-regional routes
  INSERT INTO slas (account_id, sla_type, from_postal_center_id, to_postal_center_id, expected_time_minutes, time_unit, on_time_percentage, warning_threshold, critical_threshold, is_active)
  VALUES 
    (demo2_account_id, 'distribution', bal_reg_01, la_hub_01, 4320, 'minutes', 90, 80, 65, true), -- 3 days
    (demo2_account_id, 'distribution', la_hub_01, bal_reg_01, 4320, 'minutes', 90, 80, 65, true),
    (demo2_account_id, 'distribution', sac_reg_01, ny_hub_01, 4320, 'minutes', 90, 80, 65, true),
    (demo2_account_id, 'distribution', ny_hub_01, sac_reg_01, 4320, 'minutes', 90, 80, 65, true);
  
  RAISE NOTICE 'Created 20 distribution SLAs';
END $$;

-- ============================================================================
-- PART 8: PROCESSED EVENTS (Simulated journey data - 100 tags)
-- ============================================================================

-- This will be generated in a separate script due to complexity
-- For now, we'll create a few sample events to validate the structure

DO $$
DECLARE
  demo2_account_id UUID := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  ny_hub_01 UUID;
  la_hub_01 UUID;
  entry_reader_ny UUID;
  exit_reader_ny UUID;
  entry_reader_la UUID;
  exit_reader_la UUID;
  base_time TIMESTAMPTZ := '2026-02-01 08:00:00+00';
BEGIN
  -- Get center and reader IDs
  SELECT center_id INTO ny_hub_01 FROM temp_center_ids WHERE code = 'NY-HUB-01';
  SELECT center_id INTO la_hub_01 FROM temp_center_ids WHERE code = 'LA-HUB-01';
  
  SELECT id INTO entry_reader_ny FROM readers WHERE reader_id = 'NY-HUB-01-R01' LIMIT 1;
  SELECT id INTO exit_reader_ny FROM readers WHERE reader_id = 'NY-HUB-01-R03' LIMIT 1;
  SELECT id INTO entry_reader_la FROM readers WHERE reader_id = 'LA-HUB-01-R01' LIMIT 1;
  SELECT id INTO exit_reader_la FROM readers WHERE reader_id = 'LA-HUB-01-R03' LIMIT 1;
  
  -- Sample Tag 1: Normal journey NY -> LA
  -- Entry NY Hub
  INSERT INTO processed_events (account_id, tag_id, reader_id, postal_center_id, event_type, timestamp, analysis_datetime, postal_center_code_snapshot, postal_center_name_snapshot, reader_id_snapshot, reader_type_snapshot, is_consolidated, raw_event_count)
  VALUES (demo2_account_id, 'TAG-001', entry_reader_ny, ny_hub_01, 'entry', base_time, base_time, 'NY-HUB-01', 'New York Hub Central', 'NY-HUB-01-R01', 'Entry', false, 1);
  
  -- Exit NY Hub (3 hours later)
  INSERT INTO processed_events (account_id, tag_id, reader_id, postal_center_id, event_type, timestamp, analysis_datetime, postal_center_code_snapshot, postal_center_name_snapshot, reader_id_snapshot, reader_type_snapshot, is_consolidated, raw_event_count)
  VALUES (demo2_account_id, 'TAG-001', exit_reader_ny, ny_hub_01, 'exit', base_time + interval '3 hours', base_time + interval '3 hours', 'NY-HUB-01', 'New York Hub Central', 'NY-HUB-01-R03', 'Exit', false, 1);
  
  -- Entry LA Hub (3.5 days later)
  INSERT INTO processed_events (account_id, tag_id, reader_id, postal_center_id, event_type, timestamp, analysis_datetime, postal_center_code_snapshot, postal_center_name_snapshot, reader_id_snapshot, reader_type_snapshot, is_consolidated, raw_event_count)
  VALUES (demo2_account_id, 'TAG-001', entry_reader_la, la_hub_01, 'entry', base_time + interval '3.5 days', base_time + interval '3.5 days', 'LA-HUB-01', 'Los Angeles Hub Downtown', 'LA-HUB-01-R01', 'Entry', false, 1);
  
  -- Exit LA Hub (2 hours later)
  INSERT INTO processed_events (account_id, tag_id, reader_id, postal_center_id, event_type, timestamp, analysis_datetime, postal_center_code_snapshot, postal_center_name_snapshot, reader_id_snapshot, reader_type_snapshot, is_consolidated, raw_event_count)
  VALUES (demo2_account_id, 'TAG-001', exit_reader_la, la_hub_01, 'exit', base_time + interval '3.5 days' + interval '2 hours', base_time + interval '3.5 days' + interval '2 hours', 'LA-HUB-01', 'Los Angeles Hub Downtown', 'LA-HUB-01-R03', 'Exit', false, 1);
  
  RAISE NOTICE 'Created 4 sample processed events for TAG-001';
END $$;

-- ============================================================================
-- CLEANUP TEMP TABLES
-- ============================================================================

DROP TABLE IF EXISTS temp_center_ids;

-- ============================================================================
-- SUMMARY
-- ============================================================================

DO $$
DECLARE
  center_count INT;
  reader_count INT;
  sla_op_count INT;
  sla_dist_count INT;
  event_count INT;
BEGIN
  SELECT COUNT(*) INTO center_count FROM postal_centers WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  SELECT COUNT(*) INTO reader_count FROM readers WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  SELECT COUNT(*) INTO sla_op_count FROM slas WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND sla_type = 'operational';
  SELECT COUNT(*) INTO sla_dist_count FROM slas WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND sla_type = 'distribution';
  SELECT COUNT(*) INTO event_count FROM processed_events WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  
  RAISE NOTICE '========================================';
  RAISE NOTICE 'SEED DATA SUMMARY FOR DEMO2';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Postal Centers: %', center_count;
  RAISE NOTICE 'Readers: %', reader_count;
  RAISE NOTICE 'Operational SLAs: %', sla_op_count;
  RAISE NOTICE 'Distribution SLAs: %', sla_dist_count;
  RAISE NOTICE 'Processed Events (sample): %', event_count;
  RAISE NOTICE '========================================';
END $$;
