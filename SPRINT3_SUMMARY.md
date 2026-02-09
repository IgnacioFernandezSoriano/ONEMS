# Sprint 3 - Network Diagnostics Module: Postal Centers

## Overview
Sprint 3 implements the Postal Centers module with configuration inheritance from Account Config, weekly schedules, and holidays management.

## Completed Features

### 1. Postal Centers Management
- **CRUD Operations**: Create, Read, Update, Delete postal centers
- **Basic Information**: Code, Name, Description, Active status
- **Calculation Mode**: Natural Days vs Working Days with inheritance from Account Config
- **Conditional UI**: Hides schedules/holidays when Natural Days mode is selected

### 2. Weekly Schedule Management
- **Inheritance System**: Centers inherit weekly schedule from Account Config
- **Customization**: Each center can override specific days
- **Visual Indicators**: "Inherited" badges for days using account configuration
- **Per-Day Configuration**:
  - Working Day checkbox
  - Opening hour (time picker)
  - Cutoff time (time picker)
- **Database Persistence**: Uses UPSERT for efficient updates
- **Loading**: Loads existing schedules when editing a center

### 3. Holidays Management (Non-Working Days)
- **Two-Level System**:
  - **Account-Level Holidays**: Managed in Account Configuration, inherited by all centers (read-only in center form)
  - **Center-Specific Holidays**: Local holidays unique to each center (editable)
- **Visual Distinction**:
  - Inherited holidays: Blue "Inherited from Account" badge, gray background
  - Center-specific holidays: Orange "Specific" badge, white background
- **CRUD for Center Holidays**: Add/remove local holidays with date and reason
- **Database Design**: `postal_center_id = NULL` for account-level, specific ID for center-level

### 4. Readers Module Enhancement
- **Mixed Reader Gap Inheritance**: Readers of type "Mixed" inherit `mixed_reader_gap_minutes` from Account Config
- **Visual Feedback**:
  - Placeholder shows inherited value: "60 (From Account)"
  - Blue hint when NULL: "✓ Inheriting from account: 60 minutes"
- **Type-Specific**: Field only visible for Mixed type readers

## Database Schema

### Tables Created
1. **postal_centers**
   - id, account_id, code, name, description
   - calculation_mode (natural_days | working_days)
   - is_active, created_at, updated_at, created_by, updated_by
   - UNIQUE(account_id, code)

2. **readers**
   - id, account_id, postal_center_id, reader_id, name, description
   - type (Entry | Exit | Mixed)
   - mixed_reader_gap_minutes (nullable, inherits from account)
   - is_active, created_at, updated_at, created_by, updated_by
   - UNIQUE(account_id, reader_id)

3. **weekly_schedule**
   - id, account_id, postal_center_id, day_of_week (0-6)
   - is_working_day, opening_hour, cutoff_time
   - created_at, updated_at
   - UNIQUE(account_id, postal_center_id, day_of_week)
   - postal_center_id = NULL for account-level schedules

4. **non_working_days**
   - id, account_id, postal_center_id, date, reason
   - created_at, updated_at
   - UNIQUE(account_id, postal_center_id, date)
   - postal_center_id = NULL for account-level holidays

### RLS Policies
- All tables have Row Level Security enabled
- Policies use `public.current_user_account_id()` for account isolation
- Superadmin has read access to all data
- Regular users can only access their own account data

## Technical Implementation

### Frontend Components
- **PostalCentersList.tsx**: List view with search, filters, and actions
- **PostalCenterForm.tsx**: Create/Edit form with inheritance logic
- **ReaderForm.tsx**: Reader form with Mixed gap inheritance

### Hooks
- **usePostalCenters.ts**: CRUD operations, weekly schedule, and holidays management
- **useAccountConfig.ts**: Provides account-level configuration for inheritance

### Translations
- Added translations in 4 languages (English, Spanish, French, Arabic)
- Keys: postal_centers.*, readers.*, common.*

### Database Migrations
- **20260209094630_remove_mixed_reader_gap_from_postal_centers.sql**: Cleanup
- **20260209100000_network_diagnostics_module.sql**: Main schema creation

## Key Design Decisions

### 1. Inheritance Pattern
- **NULL = Inherit**: When a field is NULL, the value is inherited from Account Config
- **Visual Feedback**: Placeholders and hints show inherited values
- **Explicit Override**: Users can set specific values to override inheritance

### 2. Calculation Mode Logic
- **Natural Days**: 24/7 operation, no schedules or holidays needed (UI hidden)
- **Working Days**: Requires weekly schedule and holidays configuration (UI visible)

### 3. Holidays Architecture
- **Account-Level**: Annual holidays managed centrally, inherited automatically
- **Center-Level**: Local holidays specific to each center (e.g., regional holidays)
- **No Duplication**: Single source of truth, no data duplication

### 4. Weekly Schedule Persistence
- **UPSERT Strategy**: Uses PostgreSQL UPSERT with conflict resolution
- **Partial Updates**: Only modified days are saved, others remain unchanged
- **Efficient Loading**: Loads only center-specific overrides, inherits rest from account

## Testing Checklist

### Postal Centers
- [x] Create postal center with Natural Days mode
- [x] Create postal center with Working Days mode
- [x] Edit center and change calculation mode
- [x] Verify schedules/holidays hide in Natural Days mode
- [x] Verify schedules/holidays show in Working Days mode

### Weekly Schedule
- [x] Inherit schedule from account (all days)
- [x] Override specific day (e.g., Friday)
- [x] Save and reload - verify override persists
- [x] Change opening/cutoff times
- [x] Toggle working day checkbox

### Holidays
- [x] View inherited account holidays (read-only)
- [x] Add center-specific holiday
- [x] Remove center-specific holiday
- [x] Verify inherited holidays cannot be deleted
- [x] Save and reload - verify center holidays persist

### Readers
- [x] Create Entry reader (no gap field)
- [x] Create Exit reader (no gap field)
- [x] Create Mixed reader with inherited gap
- [x] Create Mixed reader with custom gap
- [x] Verify placeholder shows account value
- [x] Verify hint shows when NULL

## Known Issues / Future Improvements
- None at this time

## Next Steps: Sprint 4
- Complete Readers module UI (list view, bulk operations)
- Add reader assignment to postal centers
- Implement reader status monitoring
- Add reader event log viewer

## Commits
1. `1d84e87` - feat: Hide calendars and schedules when calculation mode is natural_days
2. `e8e3354` - feat(sprint3): Add inheritance from Account Config to Postal Centers
3. `520a7cc` - feat(sprint3): Improve Postal Centers - remove historic hours, add holidays management with inheritance
4. `5bb62ad` - feat(sprint3): Add Weekly Schedule to Postal Centers with inheritance, simplify holidays to account-level only
5. `c855af4` - fix(sprint3): Add day translations and improve Weekly Schedule layout to prevent overflow
6. `2dce260` - fix(sprint3): Remove mixed_reader_gap from Postal Centers - it's reader-specific (Mixed type only)
7. `5cb68d5` - fix(sprint3): Fix weekly schedule persistence, add translations, create DB migration
8. `0197e66` - fix(migration): Update RLS policies to use current_user_account_id instead of get_user_accounts
9. `f999fed` - feat(sprint3): Add center-specific holidays management to Postal Centers
10. `3c51b12` - feat(readers): Add mixed_reader_gap_minutes inheritance from Account Config

## Build Artifact
- **File**: `onems-build-sprint3-final.zip`
- **Size**: ~1.9MB
- **Contents**: Production build ready for Netlify deployment
- **Database**: Requires migration `20260209100000_network_diagnostics_module.sql` to be applied

## Documentation
- Database schema documented in migration file
- Component props documented via TypeScript interfaces
- Translation keys documented in CSV files
- This summary document for sprint overview
