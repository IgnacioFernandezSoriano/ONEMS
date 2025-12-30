# Period Filter Fix - Dashboard

## Date: December 30, 2025

### Problem Identified

The Dashboard was showing **zero values for all Allocation Plans metrics** when selecting "Next Month" (January 2026) or other periods, even though there was data in the database for those periods.

**Root Cause**: The Dashboard code was attempting to filter allocation plan details using a field called `scheduled_date`, but the actual database field is named `fecha_programada` (Spanish for "scheduled date").

### Technical Details

**Incorrect Code** (lines 241-243 and 274-275):
```typescript
const filteredDetails = details.filter(detail => {
  const scheduledDate = (detail as any).scheduled_date;  // ❌ Wrong field name
  if (!scheduledDate) return false;
  return scheduledDate >= periodConfig.startDate && scheduledDate <= periodConfig.endDate;
});
```

**Corrected Code**:
```typescript
const filteredDetails = details.filter(detail => {
  const scheduledDate = detail.fecha_programada;  // ✅ Correct field name
  if (!scheduledDate) return false;
  return scheduledDate >= periodConfig.startDate && scheduledDate <= periodConfig.endDate;
});
```

### Changes Made

**File Modified**: `src/pages/Dashboard.tsx`

**Lines Changed**:
1. **Line 241**: Changed `(detail as any).scheduled_date` to `detail.fecha_programada`
2. **Line 274**: Changed `(d as any).scheduled_date` to `d.fecha_programada`

### Impact

This fix ensures that:

✅ **Allocation Plans metrics** now correctly filter by the selected period
- Total Plans count
- Status breakdown (Pending, Sent, Received)
- Availability issues
- Delayed shipments

✅ **Period selector** now works properly for:
- Current Month
- Next Month (January 2026)
- Last 30/60/90 days

✅ **All calculations** based on filtered data are now accurate

### Testing Recommendations

After deploying this fix, verify:

1. **Select "Next Month" (January 2026)** - should show allocation plans scheduled for January
2. **Select "Current Month" (December 2025)** - should show current month's plans
3. **Switch between periods** - metrics should update accordingly
4. **Check delayed shipments** - should only show plans scheduled before today that haven't been received
5. **Verify availability issues** - should count correctly within the selected period

### Related Information

**Database Schema**: The field `fecha_programada` is defined in:
- Table: `allocation_plan_details`
- View: `v_allocation_details_with_availability`
- Type: `AllocationPlanDetail` in `src/lib/types.ts` (line 167)

**Why Spanish field name?**: The database schema uses Spanish field names for certain business-specific fields like `fecha_programada`, `idtag`, etc., which is common in Latin American business applications.

### Build Information

**Fixed Build**: `onems_dashboard_period_fix_v20251230_084802.zip`
**Size**: 431 KB
**Compilation**: ✅ Successful, no errors

---

## Summary

This was a simple but critical bug where the code was looking for a field that didn't exist (`scheduled_date`) instead of the actual database field (`fecha_programada`). The fix ensures that period filtering now works correctly across all Dashboard metrics.

**Status**: ✅ **Fixed and Ready for Deployment**
