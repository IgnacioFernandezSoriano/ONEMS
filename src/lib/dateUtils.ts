/**
 * Utility functions for date handling in filters
 */

/**
 * Adjusts end date to include the entire day (23:59:59)
 * 
 * When filtering by date range, the end date should include all records
 * from that day. Since Supabase interprets '2026-01-31' as '2026-01-31 00:00:00',
 * we need to add time to include the full day.
 * 
 * @param dateString - Date string in YYYY-MM-DD format
 * @returns Date string with time 23:59:59 appended, or original if empty
 */
export function adjustEndDateForFilter(dateString: string): string {
  if (!dateString || dateString === '') {
    return dateString;
  }
  
  // Add time to include the entire day
  return `${dateString} 23:59:59`;
}

/**
 * Adjusts start date to include from beginning of day (00:00:00)
 * 
 * For consistency, explicitly set start time to beginning of day.
 * 
 * @param dateString - Date string in YYYY-MM-DD format
 * @returns Date string with time 00:00:00 appended, or original if empty
 */
export function adjustStartDateForFilter(dateString: string): string {
  if (!dateString || dateString === '') {
    return dateString;
  }
  
  // Add time to start from beginning of day
  return `${dateString} 00:00:00`;
}
