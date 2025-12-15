-- Migration 015: Create ONE_DB table for validated postal quality measurements
-- Version: 2.0
-- Date: 2025-12-10

-- Create ONE_DB table (multi-tenant, denormalized for analytics)
CREATE TABLE IF NOT EXISTS one_db (
  -- Primary Keys
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  allocation_detail_id UUID NOT NULL REFERENCES allocation_plan_details(id) ON DELETE RESTRICT,
  
  -- Identifiers
  tag_id TEXT NOT NULL,
  plan_name TEXT NOT NULL,
  
  -- Shipment Details
  carrier_name TEXT NOT NULL,
  product_name TEXT NOT NULL,
  
  -- Geographic Information (simplified - no nodes/panelists)
  origin_city_name TEXT NOT NULL,
  destination_city_name TEXT NOT NULL,
  
  -- Timestamps (UTC)
  sent_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL,
  
  -- Calculated KPIs
  total_transit_days INTEGER NOT NULL,
  business_transit_days INTEGER,
  on_time_delivery BOOLEAN,
  
  -- Audit Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  source_data_snapshot JSONB NOT NULL,
  
  -- Constraints
  CONSTRAINT one_db_unique_allocation_detail UNIQUE(allocation_detail_id),
  CONSTRAINT one_db_valid_timestamps CHECK (sent_at <= received_at),
  CONSTRAINT one_db_valid_transit_days CHECK (total_transit_days >= 0)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_one_db_account_id ON one_db(account_id);
CREATE INDEX IF NOT EXISTS idx_one_db_account_tag ON one_db(account_id, tag_id);
CREATE INDEX IF NOT EXISTS idx_one_db_sent_at ON one_db(sent_at);
CREATE INDEX IF NOT EXISTS idx_one_db_carrier_product ON one_db(carrier_name, product_name);
CREATE INDEX IF NOT EXISTS idx_one_db_cities ON one_db(origin_city_name, destination_city_name);

-- Enable Row Level Security
ALTER TABLE one_db ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can only see their own data
CREATE POLICY one_db_select_policy ON one_db
  FOR SELECT
  USING (account_id = auth.uid());

-- RLS Policy: Only the system (via trigger) can insert
CREATE POLICY one_db_insert_policy ON one_db
  FOR INSERT
  WITH CHECK (account_id = auth.uid());

-- Add comment
COMMENT ON TABLE one_db IS 'Validated postal quality measurement records for end-to-end analytics';
