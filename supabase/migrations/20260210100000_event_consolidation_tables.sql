-- =====================================================
-- Sprint 7: Event Consolidation Module - Database Tables
-- =====================================================
-- Description: Creates tables for RFID event consolidation
-- Author: Development Team
-- Date: 2026-02-10
-- =====================================================

-- =====================================================
-- 1. RFID Events Raw Table
-- =====================================================
-- Stores raw RFID events from EPCIS system

CREATE TABLE IF NOT EXISTS rfid_events_raw (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    
    -- EPCIS fields
    event_id TEXT NOT NULL,
    read_local_datetime TIMESTAMPTZ NOT NULL,
    reader_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    
    -- Processing control
    is_processed BOOLEAN DEFAULT FALSE,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT rfid_events_raw_event_id_unique UNIQUE (account_id, event_id)
);

-- Indexes for performance
CREATE INDEX idx_rfid_raw_not_processed 
    ON rfid_events_raw(account_id, is_processed) 
    WHERE is_processed = FALSE;

CREATE INDEX idx_rfid_raw_tag_reader 
    ON rfid_events_raw(account_id, tag_id, reader_id, read_local_datetime);

CREATE INDEX idx_rfid_raw_reader 
    ON rfid_events_raw(account_id, reader_id, read_local_datetime);

-- RLS Policies
ALTER TABLE rfid_events_raw ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rfid_events_raw_select_policy" ON rfid_events_raw;
CREATE POLICY "rfid_events_raw_select_policy" ON rfid_events_raw
    FOR SELECT
    USING (account_id = current_user_account_id());

DROP POLICY IF EXISTS "rfid_events_raw_insert_policy" ON rfid_events_raw;
CREATE POLICY "rfid_events_raw_insert_policy" ON rfid_events_raw
    FOR INSERT
    WITH CHECK (account_id = current_user_account_id());

DROP POLICY IF EXISTS "rfid_events_raw_update_policy" ON rfid_events_raw;
CREATE POLICY "rfid_events_raw_update_policy" ON rfid_events_raw
    FOR UPDATE
    USING (account_id = current_user_account_id());

DROP POLICY IF EXISTS "rfid_events_raw_delete_policy" ON rfid_events_raw;
CREATE POLICY "rfid_events_raw_delete_policy" ON rfid_events_raw
    FOR DELETE
    USING (account_id = current_user_account_id());

-- Superadmin policies
DROP POLICY IF EXISTS "rfid_events_raw_select_superadmin" ON rfid_events_raw;
CREATE POLICY "rfid_events_raw_select_superadmin" ON rfid_events_raw
    FOR SELECT
    USING (is_superadmin());

-- =====================================================
-- 2. Audit Raw Reads Table
-- =====================================================
-- Archives first and last read of processed raw events

CREATE TABLE IF NOT EXISTS audit_raw_reads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    
    -- Event identification
    tag_id TEXT NOT NULL,
    reader_id TEXT NOT NULL,
    
    -- Read summary
    first_read_datetime TIMESTAMPTZ NOT NULL,
    last_read_datetime TIMESTAMPTZ NOT NULL,
    read_count INTEGER NOT NULL,
    
    -- Timestamps
    archived_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT audit_raw_reads_check_count CHECK (read_count > 0),
    CONSTRAINT audit_raw_reads_check_order CHECK (first_read_datetime <= last_read_datetime)
);

-- Indexes
CREATE INDEX idx_audit_raw_tag_reader 
    ON audit_raw_reads(account_id, tag_id, reader_id);

CREATE INDEX idx_audit_raw_archived_at 
    ON audit_raw_reads(account_id, archived_at DESC);

-- RLS Policies
ALTER TABLE audit_raw_reads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "audit_raw_reads_select_policy" ON audit_raw_reads;
CREATE POLICY "audit_raw_reads_select_policy" ON audit_raw_reads
    FOR SELECT
    USING (account_id = current_user_account_id());

DROP POLICY IF EXISTS "audit_raw_reads_insert_policy" ON audit_raw_reads;
CREATE POLICY "audit_raw_reads_insert_policy" ON audit_raw_reads
    FOR INSERT
    WITH CHECK (account_id = current_user_account_id());

DROP POLICY IF EXISTS "audit_raw_reads_select_superadmin" ON audit_raw_reads;
CREATE POLICY "audit_raw_reads_select_superadmin" ON audit_raw_reads
    FOR SELECT
    USING (is_superadmin());

-- =====================================================
-- 3. Add missing fields to processed_events (if needed)
-- =====================================================

-- Add is_estimated field if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'processed_events' 
        AND column_name = 'is_estimated'
    ) THEN
        ALTER TABLE processed_events ADD COLUMN is_estimated BOOLEAN DEFAULT FALSE;
    END IF;
END $$;

-- Add analysis_datetime field if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'processed_events' 
        AND column_name = 'analysis_datetime'
    ) THEN
        ALTER TABLE processed_events ADD COLUMN analysis_datetime TIMESTAMPTZ;
        -- Initialize with timestamp for existing records
        UPDATE processed_events SET analysis_datetime = timestamp WHERE analysis_datetime IS NULL;
        -- Make it NOT NULL after initialization
        ALTER TABLE processed_events ALTER COLUMN analysis_datetime SET NOT NULL;
    END IF;
END $$;

-- =====================================================
-- 4. Add gap_threshold_minutes to accounts (if needed)
-- =====================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'accounts' 
        AND column_name = 'gap_threshold_minutes'
    ) THEN
        ALTER TABLE accounts ADD COLUMN gap_threshold_minutes INTEGER DEFAULT 30;
    END IF;
END $$;

-- =====================================================
-- Summary
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Event Consolidation tables created successfully';
    RAISE NOTICE '   - rfid_events_raw (with 4 indexes and RLS)';
    RAISE NOTICE '   - audit_raw_reads (with 2 indexes and RLS)';
    RAISE NOTICE '   - processed_events updated (is_estimated, analysis_datetime)';
    RAISE NOTICE '   - accounts updated (gap_threshold_minutes)';
END $$;
