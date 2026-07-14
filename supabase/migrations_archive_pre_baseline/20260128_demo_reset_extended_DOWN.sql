-- ============================================
-- Migration: Demo Reset Extended - DOWN (ROLLBACK)
-- Date: 2026-01-28
-- Author: Manus AI
-- Description: Rollback to original Demo Reset functionality
-- ============================================

BEGIN;

-- ============================================
-- STEP 1: Drop new function
-- ============================================

DROP FUNCTION IF EXISTS admin_reset_and_seed_demo2();

-- ============================================
-- STEP 2: Restore original function from backup
-- ============================================

-- The backup function admin_reset_account_data_backup will remain
-- Just drop the new function, original still exists in database

-- ============================================
-- STEP 3: Drop seed data table (optional, keep data)
-- ============================================

-- Uncomment the following line if you want to completely remove seed data
-- DROP TABLE IF EXISTS demo2_seed_data CASCADE;

-- If you want to keep the table but clear data:
-- TRUNCATE TABLE demo2_seed_data;

COMMIT;

-- ============================================
-- NOTES FOR ROLLBACK
-- ============================================
-- 1. The original function admin_reset_account_data still exists
-- 2. The backup function admin_reset_account_data_backup can be removed if needed
-- 3. The seed data table is preserved by default (can be dropped manually if needed)
-- 4. Frontend will need to be reverted to call admin_reset_account_data
