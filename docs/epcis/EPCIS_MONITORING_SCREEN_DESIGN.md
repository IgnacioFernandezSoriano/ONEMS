# EPCIS Pipeline Monitoring & Manual Execution Screen

## 📊 Current State Analysis

### Existing Screen: Event Consolidation (`/diagnosis/consolidation`)

**Current Features:**
- Metrics cards showing:
  - Pending events count
  - Total unresolved incidents
  - Last consolidation timestamp
- Manual execution button: "Run Consolidation"
- Incidents table with 50 most recent incidents
- Incident details expandable rows

**Limitations:**
- Only shows consolidation phase (Phase 2)
- No visibility into other pipeline phases
- No progress tracking during execution
- No logs or execution history
- No control over individual phases

---

## 🎯 New Unified Monitoring Screen Design

### Screen Title: **EPCIS Pipeline Monitor**

### Location: `/diagnosis/pipeline-monitor`

---

## 📐 Layout Structure

```
┌─────────────────────────────────────────────────────────────────┐
│  EPCIS Pipeline Monitor                            [Auto Refresh]│
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │ PIPELINE STATUS OVERVIEW                                     ││
│  ├──────────────┬──────────────┬──────────────┬────────────────┤│
│  │ Raw Events   │ Processed    │ Segments     │ Routes         ││
│  │ 1,234        │ 5,678        │ 890          │ 45             ││
│  │ pending      │ events       │ segments     │ unique paths   ││
│  └──────────────┴──────────────┴──────────────┴────────────────┘│
│                                                                  │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │ PIPELINE PHASES                                              ││
│  │                                                              ││
│  │  ┌─────────────────────────────────────────────────────────┐││
│  │  │ Phase 1: Ingestion                      [Status: Idle]  │││
│  │  │ Last run: 2 min ago | Duration: 1.2s                    │││
│  │  │ Events ingested: 234                                    │││
│  │  │                                    [View Logs] [Run Now]│││
│  │  └─────────────────────────────────────────────────────────┘││
│  │                                                              ││
│  │  ┌─────────────────────────────────────────────────────────┐││
│  │  │ Phase 2: Consolidation                  [Status: Ready] │││
│  │  │ Last run: 5 min ago | Duration: 3.4s                    │││
│  │  │ Events processed: 1,234 → 890 consolidated              │││
│  │  │ Incidents detected: 12                                  │││
│  │  │                                    [View Logs] [Run Now]│││
│  │  └─────────────────────────────────────────────────────────┘││
│  │                                                              ││
│  │  ┌─────────────────────────────────────────────────────────┐││
│  │  │ Phase 3: Segment Building               [Status: Ready] │││
│  │  │ Last run: 10 min ago | Duration: 2.1s                   │││
│  │  │ Segments created: 345 (234 operational, 111 transit)    │││
│  │  │ SLA violations: 8                                       │││
│  │  │                                    [View Logs] [Run Now]│││
│  │  └─────────────────────────────────────────────────────────┘││
│  │                                                              ││
│  │  ┌─────────────────────────────────────────────────────────┐││
│  │  │ Phase 4: Route Aggregation              [Status: Ready] │││
│  │  │ Last run: 1 hour ago | Duration: 5.8s                   │││
│  │  │ Unique routes: 45 | Tags processed: 1,234               │││
│  │  │                                    [View Logs] [Run Now]│││
│  │  └─────────────────────────────────────────────────────────┘││
│  │                                                              ││
│  │  [Run Full Pipeline]                                        ││
│  └──────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │ RECENT INCIDENTS                             [View All (12)]││
│  ├──────────────────────────────────────────────────────────────┤│
│  │ ⚠️  Missing Exit | Tag: 30B1D226... | Baltimore | 2 min ago ││
│  │ ⚠️  Unknown Reader | J11DXXX... | 5 min ago                 ││
│  │ 🔴 SLA Violation | Tag: 30B1D227... | Philly→NYC | 8 min ago││
│  └──────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │ EXECUTION LOG                                    [Clear Log]││
│  ├──────────────────────────────────────────────────────────────┤│
│  │ [15:23:45] Phase 2: Consolidation started...                ││
│  │ [15:23:47] Processed 1,234 raw events                       ││
│  │ [15:23:48] Created 890 consolidated events                  ││
│  │ [15:23:48] Detected 12 incidents                            ││
│  │ [15:23:48] ✅ Phase 2 completed in 3.4s                     ││
│  └──────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## 🎨 Component Specifications

### 1. Pipeline Status Overview Cards

**Metrics:**
- **Raw Events Pending**: Count from `rfid_events_raw WHERE processed = FALSE`
- **Processed Events**: Count from `processed_events`
- **Journey Segments**: Count from `journey_segments`
- **Unique Routes**: Count from `journey_paths`

**Style:** Consistent with reporting module cards (minimalista, compacto)

---

### 2. Pipeline Phase Cards

Each phase card shows:

| Element | Description |
|---------|-------------|
| **Phase Name** | "Phase 1: Ingestion", "Phase 2: Consolidation", etc. |
| **Status Pill** | `Idle` (gray), `Running` (blue + spinner), `Ready` (green), `Error` (red) |
| **Last Run** | Relative time (e.g., "2 min ago") |
| **Duration** | Execution time in seconds |
| **Metrics** | Phase-specific metrics (events processed, incidents, etc.) |
| **Actions** | `[View Logs]` button, `[Run Now]` button |

**Phase-Specific Metrics:**

| Phase | Metrics Displayed |
|-------|-------------------|
| **Phase 1: Ingestion** | Events ingested count |
| **Phase 2: Consolidation** | Events processed → consolidated, Incidents detected |
| **Phase 3: Segment Building** | Segments created (operational + transit), SLA violations |
| **Phase 4: Route Aggregation** | Unique routes, Tags processed |

---

### 3. Recent Incidents Panel

**Features:**
- Shows last 10 unresolved incidents
- Incident type icon (⚠️ warning, 🔴 critical)
- Tag ID (truncated with ellipsis)
- Location (postal center or route)
- Relative timestamp
- Click to expand full details (reuse existing `IncidentDetailsRow`)
- "View All" link to full incidents page

---

### 4. Execution Log

**Features:**
- Real-time log of pipeline executions
- Timestamped entries `[HH:MM:SS]`
- Color-coded messages:
  - Info: gray
  - Success: green (✅)
  - Warning: yellow (⚠️)
  - Error: red (❌)
- Auto-scroll to bottom on new entries
- "Clear Log" button
- Max 100 entries (auto-truncate oldest)

**Log Entry Format:**
```
[15:23:45] Phase 2: Consolidation started...
[15:23:47] Processed 1,234 raw events
[15:23:48] Created 890 consolidated events
[15:23:48] Detected 12 incidents
[15:23:48] ✅ Phase 2 completed in 3.4s
```

---

## 🔧 Functionality Specifications

### Manual Execution

**Individual Phase Execution:**
```typescript
const runPhase = async (phase: 'ingestion' | 'consolidation' | 'segments' | 'aggregation') => {
  setPhaseStatus(phase, 'running');
  addLog(`Phase ${phaseNumber}: ${phaseName} started...`);
  
  try {
    const result = await supabase.rpc(`run_${phase}_phase`, { p_account_id });
    
    addLog(`✅ Phase ${phaseNumber} completed in ${result.duration}s`);
    addLog(`${result.summary}`);
    setPhaseStatus(phase, 'ready');
    
    refreshMetrics();
  } catch (error) {
    addLog(`❌ Phase ${phaseNumber} failed: ${error.message}`);
    setPhaseStatus(phase, 'error');
  }
};
```

**Full Pipeline Execution:**
```typescript
const runFullPipeline = async () => {
  for (const phase of ['consolidation', 'segments', 'aggregation']) {
    await runPhase(phase);
  }
};
```

### Auto-Refresh

**Toggle:** Auto-refresh every 30 seconds (configurable)
**Refreshes:**
- Metrics cards
- Phase status and last run times
- Recent incidents

---

## 📊 Backend Requirements

### New RPC Functions Needed

```sql
-- Phase 2: Consolidation (already exists, may need wrapper)
CREATE OR REPLACE FUNCTION run_consolidation_phase(p_account_id UUID)
RETURNS JSON;

-- Phase 3: Segment Building
CREATE OR REPLACE FUNCTION run_segments_phase(p_account_id UUID)
RETURNS JSON;

-- Phase 4: Route Aggregation
CREATE OR REPLACE FUNCTION run_aggregation_phase(p_account_id UUID)
RETURNS JSON;

-- Get pipeline status
CREATE OR REPLACE FUNCTION get_pipeline_status(p_account_id UUID)
RETURNS JSON;
```

**Return Format:**
```json
{
  "success": true,
  "duration_seconds": 3.4,
  "summary": "Processed 1,234 events → 890 consolidated, 12 incidents detected",
  "metrics": {
    "events_processed": 1234,
    "events_created": 890,
    "incidents_detected": 12
  }
}
```

---

## 🎯 Benefits of Unified Screen

| Benefit | Description |
|---------|-------------|
| **Complete Visibility** | See status of all 4 pipeline phases in one place |
| **Manual Control** | Run individual phases or full pipeline on demand |
| **Real-time Feedback** | Execution log shows progress and results immediately |
| **Troubleshooting** | Quickly identify which phase has issues |
| **Monitoring** | Auto-refresh keeps metrics current |
| **Consistency** | Unified UX consistent with reporting module |

---

## 🚀 Implementation Priority

1. ✅ Backend: Create RPC functions for each phase
2. ✅ Frontend: Build unified monitoring screen
3. ✅ Navigation: Add to diagnosis menu
4. ✅ Testing: Validate manual execution of each phase
5. ⏳ Enhancement: Add auto-scheduling configuration (future)
