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

function safeTz(tz: string): string {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz || 'UTC' });
    return tz || 'UTC';
  } catch {
    return 'UTC';
  }
}

/** Offset (ms) of `tz` relative to UTC at the given instant. */
function tzOffsetMs(utcMs: number, tz: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hourCycle: 'h23',
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: 'numeric',
    minute: 'numeric',
    second: 'numeric',
  }).formatToParts(new Date(utcMs));
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value);
  const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour') % 24, get('minute'), get('second'));
  return asUtc - Math.floor(utcMs / 1000) * 1000;
}

function localToUtcIso(ymd: string, h: number, mi: number, s: number, tz: string): string {
  if (!ymd) return '';
  const [y, m, d] = ymd.slice(0, 10).split('-').map(Number);
  if (!y || !m || !d) return '';
  const zone = safeTz(tz);
  const guess = Date.UTC(y, m - 1, d, h, mi, s);
  let utc = guess - tzOffsetMs(guess, zone);
  // second pass handles DST transitions between guess and result
  utc = guess - tzOffsetMs(utc, zone);
  return new Date(utc).toISOString();
}

/** ISO UTC of 00:00:00 local (zone `tz`) on `ymd`; '' if empty. */
export function startOfDayInTz(ymd: string, tz: string): string {
  return localToUtcIso(ymd, 0, 0, 0, tz);
}

/** ISO UTC of 23:59:59 local (zone `tz`) on `ymd`; '' if empty. */
export function endOfDayInTz(ymd: string, tz: string): string {
  return localToUtcIso(ymd, 23, 59, 59, tz);
}
