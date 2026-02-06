-- ============================================
-- RFID INTERMEDIATE DATABASE
-- ============================================
-- This table stores raw RFID events from EPCIS API
-- Data is temporary and deleted after processing

-- RFID Intermediate table
CREATE TABLE rfid_intermediate_db (
  id BIGSERIAL PRIMARY KEY,
  -- EPCIS Event Fields (raw data)
  event_id UUID NOT NULL,
  read_local_date_time TIMESTAMPTZ NOT NULL,
  reader_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  -- Management Fields
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  ingested_at TIMESTAMPTZ DEFAULT now(),
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for performance
CREATE INDEX rfid_intermediate_db_account_id_idx ON rfid_intermediate_db(account_id);
CREATE INDEX rfid_intermediate_db_tag_id_idx ON rfid_intermediate_db(tag_id);
CREATE INDEX rfid_intermediate_db_processed_at_idx ON rfid_intermediate_db(processed_at);
CREATE INDEX rfid_intermediate_db_event_id_idx ON rfid_intermediate_db(event_id);

-- ============================================
-- TRIGGERS
-- ============================================

-- Auto-assign account_id
CREATE TRIGGER set_rfid_intermediate_db_account_id
  BEFORE INSERT ON rfid_intermediate_db
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

-- Prevent account_id changes
CREATE TRIGGER prevent_rfid_intermediate_db_account_change
  BEFORE UPDATE ON rfid_intermediate_db
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

-- ============================================
-- RLS POLICIES
-- ============================================

ALTER TABLE rfid_intermediate_db ENABLE ROW LEVEL SECURITY;

-- SELECT policy
CREATE POLICY "rfid_intermediate_db_select"
  ON rfid_intermediate_db FOR SELECT
  USING (
    current_user_role() = 'superadmin' OR
    account_id = current_user_account_id()
  );

-- INSERT policy
CREATE POLICY "rfid_intermediate_db_insert"
  ON rfid_intermediate_db FOR INSERT
  WITH CHECK (
    current_user_role() IN ('superadmin', 'admin')
  );

-- UPDATE policy
CREATE POLICY "rfid_intermediate_db_update"
  ON rfid_intermediate_db FOR UPDATE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

-- DELETE policy
CREATE POLICY "rfid_intermediate_db_delete"
  ON rfid_intermediate_db FOR DELETE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

-- Verify
SELECT 'RFID Intermediate DB table created successfully' as status;
