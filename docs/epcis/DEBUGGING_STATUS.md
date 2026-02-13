# EPCIS `consolidate_rfid_events` Debugging Status

**Date:** 2026-02-13

## 1. Blocking Issue

The `consolidate_rfid_events()` PostgreSQL function is currently failing with the following error:

```
ERROR: null value in column "reader_id_snapshot" of relation "processed_events" violates not-null constraint
```

This error occurs during the `INSERT` statement into the `processed_events` table, despite the `SELECT` statement explicitly providing values for `reader_id_snapshot` and `reader_type_snapshot`.

## 2. Context

This issue arose after integrating `carrier_id` and `product_id` into the EPCIS event processing pipeline. The goal is to consolidate raw RFID scans from `rfid_events_raw` into logical `processed_events`.

**Test Data:**
- 20 events for tag `TEST-TAG-001`
- Route: Baltimore → New York
- Carrier: Carrier A
- Product: STANDARD

## 3. Investigation Summary

Several debugging steps were taken to isolate the root cause:

1.  **Function Code Verification:** The `INSERT` statement within `consolidate_rfid_events` was repeatedly checked and confirmed to include the `reader_id_snapshot` and `reader_type_snapshot` columns, sourced from the `get_reader_info()` function.

2.  **`get_reader_info()` Manual Test:** The helper function `get_reader_info(reader_id)` was tested independently and confirmed to return the correct `reader_id` and `reader_type` for all readers in the test data.

3.  **Manual `INSERT`:** A manual `INSERT` statement, mimicking the one inside the consolidation function, was executed successfully. This proves that the `processed_events` table itself is correctly configured and can accept the data.

4.  **Row-Level Security (RLS):** RLS was initially a suspect and was disabled on all relevant tables (`rfid_events_raw`, `processed_events`, `journey_segments`, `journeys`) to eliminate it as a potential cause.

5.  **Historical Analysis:** A review of previous, functional versions of the test suite revealed a critical difference. The older tests **did not use the EPCIS pipeline**. Instead, they inserted test data directly into the final `journey_segments` and `journeys` tables. The current implementation is the first time the full `rfid_events_raw` → `processed_events` pipeline is being tested with the carrier and product dimensions.

## 4. Hypothesis

The leading hypothesis is that there is an unknown interaction or side effect within the `consolidate_rfid_events` function's execution context in PostgreSQL. The error is not a simple syntax mistake but likely related to how the `reader_info` record is being accessed or passed to the `INSERT` statement within the loop.

## 5. Next Steps

- **Continue Debugging:** The immediate priority is to resolve this blocking issue to proceed with the EPCIS module development.
- **Simplified Test Case:** Attempt consolidation with a single raw event to further isolate the problem.
- **Alternative Data Access:** Explore alternative ways to fetch and access the reader snapshot data within the function, such as using a direct `JOIN` instead of the `get_reader_info` helper function.
