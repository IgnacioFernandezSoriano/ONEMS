# EPCIS Data Flow Analysis: Carrier & Product Integration

## Executive Summary

This document provides a comprehensive analysis of the complete EPCIS data flow in the ONEMS system, identifying all components that require modification to integrate **carrier** and **product** information throughout the diagnosis pipeline.

---

## 1. Current Data Flow Architecture

### 1.1 Overview

```
EPCIS Events (External)
    ↓
rfid_events_raw (Ingestion)
    ↓
consolidate_rfid_events() [Function]
    ↓
processed_events (Consolidated)
    ↓
reconstruct_journeys() [Function]
    ↓
journey_segments (Segments)
    ↓
assemble_journeys() [Function]
    ↓
journeys (Complete Journeys)
    ↓
Reporting & Analytics
```

### 1.2 Automated Processing

**Cron Job Schedule:**
- **Function:** `process_rfid_pipeline()`
- **Schedule:** Every hour (via pg_cron)
- **Process:**
  1. Consolidate raw events → processed_events
  2. Reconstruct segments → journey_segments
  3. Assemble journeys → journeys

---

## 2. Database Schema Analysis

### 2.1 Affected Tables

#### **Table 1: rfid_events_raw**
**Purpose:** Stores raw RFID events from EPCIS system

**Current Schema:**
```sql
- id: UUID (PK)
- account_id: UUID (FK → accounts)
- event_id: TEXT (UNIQUE per account)
- read_local_datetime: TIMESTAMPTZ
- reader_id: TEXT
- tag_id: TEXT
- is_processed: BOOLEAN
- created_at: TIMESTAMPTZ
```

**Missing Fields:**
- ❌ carrier_id
- ❌ product_id

**Proposed Changes:**
```sql
ALTER TABLE rfid_events_raw 
ADD COLUMN carrier_id UUID REFERENCES carriers(id),
ADD COLUMN product_id UUID REFERENCES products(id);

CREATE INDEX idx_rfid_raw_carrier_product 
ON rfid_events_raw(account_id, carrier_id, product_id);
```

---

#### **Table 2: processed_events**
**Purpose:** Consolidated RFID events (deduplicated and validated)

**Current Schema:**
```sql
- id: BIGSERIAL (PK)
- account_id: UUID (FK → accounts)
- tag_id: TEXT
- reader_id: TEXT
- postal_center_id: UUID (FK → postal_centers)
- event_type: TEXT ('entry' | 'exit')
- timestamp: TIMESTAMPTZ
- analysis_datetime: TIMESTAMPTZ
- postal_center_code_snapshot: TEXT
- postal_center_name_snapshot: TEXT
- raw_event_count: INTEGER
- is_consolidated: BOOLEAN
- is_estimated: BOOLEAN
- created_at: TIMESTAMPTZ
- processed_at: TIMESTAMPTZ
```

**Missing Fields:**
- ❌ carrier_id
- ❌ product_id

**Proposed Changes:**
```sql
ALTER TABLE processed_events 
ADD COLUMN carrier_id UUID REFERENCES carriers(id),
ADD COLUMN product_id UUID REFERENCES products(id),
ADD COLUMN carrier_name_snapshot TEXT,
ADD COLUMN product_code_snapshot TEXT;

CREATE INDEX idx_processed_events_carrier_product 
ON processed_events(account_id, carrier_id, product_id);
```

---

#### **Table 3: journey_segments**
**Purpose:** Segments of journeys (operational and distribution)

**Current Schema:**
```sql
- id: BIGSERIAL (PK)
- account_id: UUID (FK → accounts)
- tag_id: TEXT
- segment_type: TEXT ('operational' | 'distribution')
- postal_center_id: UUID (for operational)
- from_postal_center_id: UUID (for distribution)
- to_postal_center_id: UUID (for distribution)
- entry_event_id: BIGINT (FK → processed_events)
- exit_event_id: BIGINT (FK → processed_events)
- entry_timestamp: TIMESTAMPTZ
- exit_timestamp: TIMESTAMPTZ
- entry_analysis_datetime: TIMESTAMPTZ
- exit_analysis_datetime: TIMESTAMPTZ
- actual_time_minutes: INTEGER
- adjusted_time_minutes: INTEGER
- pre_operational_wait_minutes: INTEGER
- sla_id: UUID (FK → slas)
- expected_time_minutes: INTEGER
- sla_compliance: TEXT ('on_time' | 'warning' | 'critical' | 'violated' | 'no_sla')
- postal_center_code_snapshot: TEXT
- postal_center_name_snapshot: TEXT
- from_postal_center_code_snapshot: TEXT
- from_postal_center_name_snapshot: TEXT
- to_postal_center_code_snapshot: TEXT
- to_postal_center_name_snapshot: TEXT
- created_at: TIMESTAMPTZ
```

**Missing Fields:**
- ❌ carrier_id
- ❌ product_id

**Proposed Changes:**
```sql
ALTER TABLE journey_segments 
ADD COLUMN carrier_id UUID REFERENCES carriers(id),
ADD COLUMN product_id UUID REFERENCES products(id),
ADD COLUMN carrier_name_snapshot TEXT,
ADD COLUMN product_code_snapshot TEXT;

CREATE INDEX idx_journey_segments_carrier_product 
ON journey_segments(account_id, carrier_id, product_id);

CREATE INDEX idx_journey_segments_route_carrier_product 
ON journey_segments(account_id, from_postal_center_id, to_postal_center_id, carrier_id, product_id)
WHERE segment_type = 'distribution';
```

---

#### **Table 4: journeys**
**Purpose:** Complete end-to-end journeys

**Current Schema:**
```sql
- id: BIGSERIAL (PK)
- account_id: UUID (FK → accounts)
- tag_id: TEXT
- origin_city_id: UUID (FK → cities)
- destination_city_id: UUID (FK → cities)
- origin_city_name: TEXT
- destination_city_name: TEXT
- route_path: JSONB (array of centers visited)
- total_centers_visited: INTEGER
- total_actual_time_minutes: INTEGER
- total_adjusted_time_minutes: INTEGER
- total_operational_time_minutes: INTEGER
- total_distribution_time_minutes: INTEGER
- total_pre_operational_wait_minutes: INTEGER
- journey_status: TEXT ('in_progress' | 'completed' | 'anomalous' | 'stuck')
- is_missroute: BOOLEAN
- missroute_reason: TEXT
- first_event_timestamp: TIMESTAMPTZ
- last_event_timestamp: TIMESTAMPTZ
- total_sla_violations: INTEGER
- total_segments: INTEGER
- on_time_segments: INTEGER
- created_at: TIMESTAMPTZ
- updated_at: TIMESTAMPTZ
```

**Missing Fields:**
- ❌ carrier_id
- ❌ product_id

**Proposed Changes:**
```sql
ALTER TABLE journeys 
ADD COLUMN carrier_id UUID REFERENCES carriers(id),
ADD COLUMN product_id UUID REFERENCES products(id),
ADD COLUMN carrier_name_snapshot TEXT,
ADD COLUMN product_code_snapshot TEXT;

CREATE INDEX idx_journeys_carrier_product 
ON journeys(account_id, carrier_id, product_id);

CREATE INDEX idx_journeys_route_carrier_product 
ON journeys(account_id, origin_city_id, destination_city_id, carrier_id, product_id);
```

---

#### **Table 5: incidents**
**Purpose:** Detected anomalies and violations

**Current Schema:**
```sql
- id: BIGSERIAL (PK)
- account_id: UUID (FK → accounts)
- incident_type: TEXT
- severity: TEXT ('low' | 'medium' | 'high' | 'critical')
- tag_id: TEXT
- postal_center_id: UUID (FK → postal_centers)
- reader_id: TEXT
- event_id: BIGINT (FK → processed_events)
- segment_id: BIGINT (FK → journey_segments)
- description: TEXT
- metadata: JSONB
- is_resolved: BOOLEAN
- resolved_at: TIMESTAMPTZ
- resolved_by: UUID (FK → profiles)
- resolution_notes: TEXT
- detected_at: TIMESTAMPTZ
- created_at: TIMESTAMPTZ
```

**Missing Fields:**
- ❌ carrier_id
- ❌ product_id

**Proposed Changes:**
```sql
ALTER TABLE incidents 
ADD COLUMN carrier_id UUID REFERENCES carriers(id),
ADD COLUMN product_id UUID REFERENCES products(id);

CREATE INDEX idx_incidents_carrier_product 
ON incidents(account_id, carrier_id, product_id);
```

---

#### **Table 6: slas**
**Purpose:** Service Level Agreements

**Current Schema:**
```sql
- id: UUID (PK)
- account_id: UUID (FK → accounts)
- sla_type: TEXT ('operational' | 'distribution')
- postal_center_id: UUID (for operational)
- from_postal_center_id: UUID (for distribution)
- to_postal_center_id: UUID (for distribution)
- carrier_id: UUID (FK → carriers) ✅ ALREADY EXISTS
- product_id: UUID (FK → products) ✅ ALREADY EXISTS
- expected_time_minutes: INTEGER
- time_unit: TEXT
- on_time_percentage: NUMERIC
- warning_threshold: NUMERIC
- critical_threshold: NUMERIC
- is_active: BOOLEAN
- deleted_at: TIMESTAMPTZ
- created_at: TIMESTAMPTZ
- updated_at: TIMESTAMPTZ
```

**Status:** ✅ Already has carrier_id and product_id

**Unique Constraints:**
```sql
-- Operational SLAs: unique per center + carrier + product
CREATE UNIQUE INDEX slas_unique_operational_carrier_product 
ON slas (account_id, postal_center_id, carrier_id, product_id) 
WHERE sla_type = 'operational';

-- Distribution SLAs: unique per route + carrier + product
CREATE UNIQUE INDEX slas_unique_distribution_carrier_product 
ON slas (account_id, from_postal_center_id, to_postal_center_id, carrier_id, product_id) 
WHERE sla_type = 'distribution';
```

---

### 2.2 Reference Tables (No Changes Required)

#### **carriers**
```sql
- id: UUID (PK)
- account_id: UUID (FK → accounts)
- code: TEXT
- name: TEXT
- created_at: TIMESTAMPTZ
```

#### **products**
```sql
- id: UUID (PK)
- account_id: UUID (FK → accounts)
- carrier_id: UUID (FK → carriers)
- code: TEXT
- name: TEXT
- standard_delivery_hours: INTEGER
- created_at: TIMESTAMPTZ
```

---

## 3. Function Analysis & Required Changes

### 3.1 consolidate_rfid_events()

**Location:** `20260210130000_consolidation_main_function.sql`

**Current Behavior:**
- Reads from `rfid_events_raw`
- Groups by `tag_id` + `reader_id`
- Creates entries in `processed_events`

**Required Changes:**

```sql
-- 1. Extract carrier_id and product_id from raw events
FOR v_raw_event IN
    SELECT DISTINCT
        tag_id,
        reader_id,
        carrier_id,  -- NEW
        product_id   -- NEW
    FROM rfid_events_raw
    WHERE account_id = p_account_id
    AND is_processed = FALSE
    ORDER BY tag_id, reader_id
LOOP
    -- 2. Get carrier and product snapshots
    SELECT name INTO v_carrier_name
    FROM carriers
    WHERE id = v_raw_event.carrier_id;
    
    SELECT code INTO v_product_code
    FROM products
    WHERE id = v_raw_event.product_id;
    
    -- 3. Insert with carrier/product info
    INSERT INTO processed_events (
        account_id,
        tag_id,
        reader_id,
        postal_center_id,
        event_type,
        timestamp,
        analysis_datetime,
        carrier_id,           -- NEW
        product_id,           -- NEW
        carrier_name_snapshot,  -- NEW
        product_code_snapshot,  -- NEW
        ...
    ) VALUES (
        p_account_id,
        v_raw_event.tag_id,
        v_reader_info.reader_id,
        v_reader_info.postal_center_id,
        v_consolidated_event.event_type,
        v_consolidated_event.timestamp,
        v_analysis_datetime,
        v_raw_event.carrier_id,     -- NEW
        v_raw_event.product_id,     -- NEW
        v_carrier_name,             -- NEW
        v_product_code,             -- NEW
        ...
    );
END LOOP;
```

---

### 3.2 reconstruct_journeys()

**Location:** `20260211000000_journey_reconstruction.sql`

**Current Behavior:**
- Reads from `processed_events`
- Creates `journey_segments`
- Matches with SLAs

**Required Changes:**

```sql
-- 1. Group events by tag_id + carrier_id + product_id
FOR v_tag_group IN
    SELECT DISTINCT 
        tag_id,
        carrier_id,    -- NEW
        product_id     -- NEW
    FROM processed_events
    WHERE account_id = p_account_id
    AND processed_at IS NULL
    ORDER BY tag_id
LOOP
    -- 2. Find applicable SLA with carrier and product
    SELECT * INTO v_sla
    FROM find_applicable_sla(
        p_account_id,
        v_segment_type,
        v_postal_center_id,
        v_from_postal_center_id,
        v_to_postal_center_id,
        v_tag_group.carrier_id,   -- NEW
        v_tag_group.product_id    -- NEW
    );
    
    -- 3. Insert segment with carrier/product
    INSERT INTO journey_segments (
        account_id,
        tag_id,
        segment_type,
        carrier_id,                -- NEW
        product_id,                -- NEW
        carrier_name_snapshot,     -- NEW
        product_code_snapshot,     -- NEW
        sla_id,
        expected_time_minutes,
        ...
    ) VALUES (
        p_account_id,
        v_tag_group.tag_id,
        v_segment_type,
        v_tag_group.carrier_id,    -- NEW
        v_tag_group.product_id,    -- NEW
        v_carrier_name,            -- NEW
        v_product_code,            -- NEW
        v_sla.sla_id,
        v_sla.expected_time_minutes,
        ...
    );
END LOOP;
```

---

### 3.3 find_applicable_sla()

**Location:** `20260211000000_journey_reconstruction.sql`

**Current Signature:**
```sql
CREATE OR REPLACE FUNCTION find_applicable_sla(
    p_account_id UUID,
    p_segment_type TEXT,
    p_postal_center_id UUID DEFAULT NULL,
    p_from_postal_center_id UUID DEFAULT NULL,
    p_to_postal_center_id UUID DEFAULT NULL
)
```

**New Signature:**
```sql
CREATE OR REPLACE FUNCTION find_applicable_sla(
    p_account_id UUID,
    p_segment_type TEXT,
    p_postal_center_id UUID DEFAULT NULL,
    p_from_postal_center_id UUID DEFAULT NULL,
    p_to_postal_center_id UUID DEFAULT NULL,
    p_carrier_id UUID DEFAULT NULL,      -- NEW
    p_product_id UUID DEFAULT NULL       -- NEW
)
```

**Updated Logic:**
```sql
IF p_segment_type = 'operational' THEN
    RETURN QUERY
    SELECT 
        s.id,
        s.expected_time_minutes,
        s.on_time_percentage,
        s.warning_threshold,
        s.critical_threshold
    FROM slas s
    WHERE s.account_id = p_account_id
      AND s.sla_type = 'operational'
      AND s.postal_center_id = p_postal_center_id
      AND s.carrier_id = p_carrier_id        -- NEW
      AND s.product_id = p_product_id        -- NEW
      AND s.is_active = true
      AND s.deleted_at IS NULL
    LIMIT 1;
ELSE
    RETURN QUERY
    SELECT 
        s.id,
        s.expected_time_minutes,
        s.on_time_percentage,
        s.warning_threshold,
        s.critical_threshold
    FROM slas s
    WHERE s.account_id = p_account_id
      AND s.sla_type = 'distribution'
      AND s.from_postal_center_id = p_from_postal_center_id
      AND s.to_postal_center_id = p_to_postal_center_id
      AND s.carrier_id = p_carrier_id        -- NEW
      AND s.product_id = p_product_id        -- NEW
      AND s.is_active = true
      AND s.deleted_at IS NULL
    LIMIT 1;
END IF;
```

---

### 3.4 assemble_journeys()

**Location:** `20260211010001_assemble_journeys_function.sql`

**Current Behavior:**
- Groups segments by `tag_id`
- Creates complete journeys

**Required Changes:**

```sql
-- Group segments by tag_id + carrier_id + product_id
FOR v_journey_group IN
    SELECT 
        tag_id,
        carrier_id,        -- NEW
        product_id,        -- NEW
        MIN(entry_timestamp) as first_event,
        MAX(exit_timestamp) as last_event,
        COUNT(*) as segment_count
    FROM journey_segments
    WHERE account_id = p_account_id
    GROUP BY tag_id, carrier_id, product_id  -- NEW
LOOP
    -- Get carrier and product snapshots
    SELECT name INTO v_carrier_name
    FROM carriers
    WHERE id = v_journey_group.carrier_id;
    
    SELECT code INTO v_product_code
    FROM products
    WHERE id = v_journey_group.product_id;
    
    -- Insert journey with carrier/product
    INSERT INTO journeys (
        account_id,
        tag_id,
        carrier_id,              -- NEW
        product_id,              -- NEW
        carrier_name_snapshot,   -- NEW
        product_code_snapshot,   -- NEW
        ...
    ) VALUES (
        p_account_id,
        v_journey_group.tag_id,
        v_journey_group.carrier_id,    -- NEW
        v_journey_group.product_id,    -- NEW
        v_carrier_name,                -- NEW
        v_product_code,                -- NEW
        ...
    );
END LOOP;
```

---

## 4. Frontend Changes

### 4.1 Event Consolidation Page

**File:** `/src/pages/diagnosis/EventConsolidation.tsx`

**Changes Required:**

1. **Add filters:**
```typescript
const [filters, setFilters] = useState({
  carrier_id: '',
  product_id: '',
  // ... existing filters
});
```

2. **Load carriers and products:**
```typescript
const [carriers, setCarriers] = useState<Carrier[]>([]);
const [products, setProducts] = useState<Product[]>([]);

useEffect(() => {
  loadCarriers();
  loadProducts();
}, []);
```

3. **Update incidents query:**
```typescript
const { data, error } = await supabase
  .from('incidents')
  .select(`
    id,
    tag_id,
    incident_type,
    description,
    detected_at,
    is_resolved,
    metadata,
    carrier_id,
    product_id,
    carriers!incidents_carrier_id_fkey(name),
    products!incidents_product_id_fkey(code),
    postal_centers!incidents_postal_center_id_fkey(name)
  `)
  .eq('carrier_id', filters.carrier_id)
  .eq('product_id', filters.product_id)
  .order('detected_at', { ascending: false });
```

4. **Update table columns:**
```tsx
<th>Carrier</th>
<th>Product</th>
<td>{incident.carriers?.name || 'N/A'}</td>
<td>{incident.products?.code || 'N/A'}</td>
```

---

### 4.2 Journey Segments Page

**File:** `/src/pages/diagnosis/JourneySegments.tsx` (if exists)

**Changes Required:**

1. **Add carrier and product columns to table**
2. **Add filters for carrier and product**
3. **Update queries to include carrier/product joins**

---

### 4.3 Route Analysis Page

**File:** `/src/pages/diagnosis/RouteAnalysis.tsx`

**Changes Required:**

1. **Group by carrier and product:**
```typescript
SELECT 
  from_postal_center_id,
  to_postal_center_id,
  carrier_id,
  product_id,
  COUNT(*) as total_segments,
  AVG(actual_time_minutes) as avg_time
FROM journey_segments
WHERE segment_type = 'distribution'
GROUP BY from_postal_center_id, to_postal_center_id, carrier_id, product_id
```

2. **Add carrier/product breakdown charts**

---

### 4.4 Types Updates

**File:** `/src/lib/types_diagnosis.ts`

**Add carrier and product fields:**

```typescript
export interface ProcessedEvent {
  // ... existing fields
  carrier_id: string | null;
  product_id: string | null;
  carrier_name_snapshot: string | null;
  product_code_snapshot: string | null;
}

export interface JourneySegment {
  // ... existing fields
  carrier_id: string | null;
  product_id: string | null;
  carrier_name_snapshot: string | null;
  product_code_snapshot: string | null;
}

export interface Journey {
  // ... existing fields
  carrier_id: string | null;
  product_id: string | null;
  carrier_name_snapshot: string | null;
  product_code_snapshot: string | null;
}

export interface Incident {
  // ... existing fields
  carrier_id: string | null;
  product_id: string | null;
}

// Add filters
export interface JourneySegmentFilters {
  // ... existing fields
  carrier_id?: string;
  product_id?: string;
}

export interface JourneyFilters {
  // ... existing fields
  carrier_id?: string;
  product_id?: string;
}
```

---

## 5. Implementation Plan (Step-by-Step)

### Phase 1: Database Schema Updates
1. ✅ Add `carrier_id` and `product_id` to `slas` table (DONE)
2. Add `carrier_id` and `product_id` to `rfid_events_raw`
3. Add `carrier_id`, `product_id`, and snapshots to `processed_events`
4. Add `carrier_id`, `product_id`, and snapshots to `journey_segments`
5. Add `carrier_id`, `product_id`, and snapshots to `journeys`
6. Add `carrier_id` and `product_id` to `incidents`
7. Create indexes for performance

### Phase 2: Backend Functions
8. Update `consolidate_rfid_events()` to extract and propagate carrier/product
9. Update `find_applicable_sla()` to include carrier/product parameters
10. Update `reconstruct_journeys()` to use carrier/product in SLA matching
11. Update `assemble_journeys()` to group by carrier/product
12. Update incident detection logic to include carrier/product

### Phase 3: Test Data Generation
13. Create sample EPCIS events with carrier/product
14. Insert into `rfid_events_raw`
15. Run consolidation pipeline
16. Verify data propagation through all tables

### Phase 4: Frontend Updates
17. Update TypeScript types
18. Add carrier/product filters to Event Consolidation page
19. Add carrier/product columns to all diagnosis tables
20. Update queries to join with carriers and products
21. Add carrier/product breakdown in analytics

### Phase 5: Testing & Validation
22. End-to-end testing with sample data
23. Verify SLA matching works correctly per carrier/product
24. Validate reporting shows correct carrier/product segmentation
25. Performance testing with large datasets

---

## 6. Sample EPCIS Event Structure

**Expected EPCIS event format with carrier and product:**

```json
{
  "event_id": "EVT-001-20260213-001",
  "read_local_datetime": "2026-02-13T10:30:00Z",
  "reader_id": "BAL-REG-01-ENTRY-01",
  "tag_id": "TAG-00001",
  "carrier_id": "uuid-of-carrier-a",
  "product_id": "uuid-of-carrier-a-express"
}
```

---

## 7. Data Consistency Rules

1. **Carrier-Product Relationship:**
   - A product MUST belong to a carrier
   - Cannot mix carriers and products from different carriers

2. **Tag Journey Consistency:**
   - A tag's journey MUST use the same carrier and product throughout
   - If carrier/product changes, it's a new journey

3. **SLA Matching:**
   - SLAs are specific to carrier + product + route/center
   - No SLA match = `sla_compliance: 'no_sla'`

4. **Snapshot Fields:**
   - Always capture carrier name and product code at event time
   - Protects against master data changes

---

## 8. Migration Strategy

**Existing Data:**
- Existing records without carrier/product will have NULL values
- Reports should handle NULL gracefully (show as "Unknown" or "Legacy")
- Option to backfill if carrier/product can be inferred

**Rollout:**
1. Deploy schema changes
2. Deploy backend functions
3. Deploy frontend (backward compatible)
4. Start ingesting new EPCIS events with carrier/product
5. Monitor and validate

---

## Document Version
- **Version:** 1.0
- **Date:** 2026-02-13
- **Status:** Ready for Implementation


---

## 9. Environment Access & Configuration

### 9.1 GitHub Repository

**Repository Information:**
- **URL:** https://github.com/IgnacioFernandezSoriano/ONEMS
- **Branch:** main
- **Personal Access Token:** `[REDACTED_FOR_SECURITY]`

**Clone Command:**
```bash
git clone https://[REDACTED_FOR_SECURITY]@github.com/IgnacioFernandezSoriano/ONEMS.git
```

**Key Directories:**
- `/src/pages/diagnosis/` - Frontend diagnosis pages
- `/src/components/` - Reusable components
- `/src/lib/types_diagnosis.ts` - TypeScript type definitions
- `/src/hooks/` - Custom React hooks
- `/supabase/migrations/` - Database migration scripts

---

### 9.2 Supabase Database

**Project Information:**
- **Project ID:** sehbnpgzqljrsqimwyuz
- **Project URL:** https://sehbnpgzqljrsqimwyuz.supabase.co
- **Dashboard:** https://supabase.com/dashboard/project/sehbnpgzqljrsqimwyuz
- **SQL Editor:** https://supabase.com/dashboard/project/sehbnpgzqljrsqimwyuz/sql/new

**API Keys:**
- **Anon Key (Public):**
  ```
  eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ4OTQzMTEsImV4cCI6MjA4MDQ3MDMxMX0.C-LsSmfOo38Tqc_PwP1c-nFyK1PeVj_mCBqanYsgoeg
  ```

- **Service Role Key (Private - Admin Access):**
  ```
  eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDg5NDMxMSwiZXhwIjoyMDgwNDcwMzExfQ.8aPEi2qUYMiKBi__jAu-8gnkc3Z5b1jrPpbjBYQPf4k
  ```

**Connection from Python:**
```python
from supabase import create_client
import os

# Set environment variables
os.environ['SUPABASE_URL'] = 'https://sehbnpgzqljrsqimwyuz.supabase.co'
os.environ['SUPABASE_KEY'] = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'  # Service Role Key

# Create client
supabase = create_client(
    os.environ['SUPABASE_URL'],
    os.environ['SUPABASE_KEY']
)

# Example query
result = supabase.table('rfid_events_raw').select('*').limit(10).execute()
```

**Direct SQL Access:**
1. Go to SQL Editor: https://supabase.com/dashboard/project/sehbnpgzqljrsqimwyuz/sql/new
2. Paste SQL commands
3. Click "Run" or press Ctrl+Enter

---

### 9.3 Netlify Deployment

**Site Information:**
- **Site Name:** onem-dev
- **Site URL:** https://onem-dev.netlify.app
- **API ID:** 38d8267b-c809-4d9a-8128-0b909fc09f92
- **Dashboard:** https://app.netlify.com/sites/onem-dev
- **Personal Access Token:** `nfp_kR1BMw6SZ9YM8sC1iJRdswRmNweNFqdE60b3`

**Environment Variables (Netlify):**
```bash
VITE_SUPABASE_URL=https://sehbnpgzqljrsqimwyuz.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ4OTQzMTEsImV4cCI6MjA4MDQ3MDMxMX0.C-LsSmfOo38Tqc_PwP1c-nFyK1PeVj_mCBqanYsgoeg
```

**Manual Deployment:**
1. Build project locally: `pnpm run build`
2. Create ZIP: `cd dist && zip -r ../deploy.zip .`
3. Upload to Netlify Dashboard → Deploys → Drag & Drop

---

### 9.4 Development Environment Setup

**Prerequisites:**
- Node.js 22.13.0
- pnpm (package manager)
- Git
- Python 3.11+ (for backend scripts)

**Local Setup:**
```bash
# 1. Clone repository
git clone https://[REDACTED_FOR_SECURITY]@github.com/IgnacioFernandezSoriano/ONEMS.git
cd ONEMS

# 2. Install dependencies
pnpm install

# 3. Create .env.local file
cat > .env.local << EOF
VITE_SUPABASE_URL=https://sehbnpgzqljrsqimwyuz.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ4OTQzMTEsImV4cCI6MjA4MDQ3MDMxMX0.C-LsSmfOo38Tqc_PwP1c-nFyK1PeVj_mCBqanYsgoeg
EOF

# 4. Run development server
pnpm run dev

# 5. Access at http://localhost:5173
```

**Python Environment for Scripts:**
```bash
# Install Supabase client
pip3 install supabase

# Set environment variables
export SUPABASE_URL='https://sehbnpgzqljrsqimwyuz.supabase.co'
export SUPABASE_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'  # Service Role Key

# Run scripts
python3 generate_sample_data.py
```

---

### 9.5 Database Migration Workflow

**Creating New Migrations:**

1. **Create migration file:**
```bash
cd supabase/migrations
touch $(date +%Y%m%d%H%M%S)_add_carrier_product_to_rfid_raw.sql
```

2. **Write SQL in migration file:**
```sql
-- Migration: Add carrier and product to rfid_events_raw
ALTER TABLE rfid_events_raw 
ADD COLUMN carrier_id UUID REFERENCES carriers(id),
ADD COLUMN product_id UUID REFERENCES products(id);

CREATE INDEX idx_rfid_raw_carrier_product 
ON rfid_events_raw(account_id, carrier_id, product_id);
```

3. **Apply migration via Supabase SQL Editor:**
   - Go to: https://supabase.com/dashboard/project/sehbnpgzqljrsqimwyuz/sql/new
   - Paste SQL content
   - Click "Run"

4. **Commit to GitHub:**
```bash
git add supabase/migrations/
git commit -m "feat: add carrier and product to rfid_events_raw"
git push origin main
```

---

### 9.6 Access Summary Table

| **Resource** | **URL/Endpoint** | **Credentials** |
|--------------|------------------|-----------------|
| GitHub Repo | https://github.com/IgnacioFernandezSoriano/ONEMS | PAT: `[REDACTED_FOR_SECURITY]` |
| Supabase Dashboard | https://supabase.com/dashboard/project/sehbnpgzqljrsqimwyuz | Login via browser |
| Supabase API | https://sehbnpgzqljrsqimwyuz.supabase.co | Anon Key (see above) |
| Supabase SQL Editor | https://supabase.com/dashboard/project/sehbnpgzqljrsqimwyuz/sql/new | Login via browser |
| Netlify Site | https://onem-dev.netlify.app | Public access |
| Netlify Dashboard | https://app.netlify.com/sites/onem-dev | Login via browser |

---

### 9.7 Security Notes

⚠️ **Important Security Considerations:**

1. **Service Role Key** - Has admin access, bypass RLS policies. Use only in backend scripts, NEVER expose in frontend.

2. **Anon Key** - Safe for frontend use, respects Row Level Security (RLS) policies.

3. **GitHub PAT** - Personal Access Token with repo access. Rotate periodically.

4. **Environment Variables** - Never commit `.env.local` to Git. Use `.env.example` for templates.

5. **RLS Policies** - Always test that Row Level Security policies work correctly after schema changes.

---

## Document Version
- **Version:** 1.1
- **Date:** 2026-02-13
- **Status:** Ready for Implementation
- **Last Updated:** Added environment access and configuration details
