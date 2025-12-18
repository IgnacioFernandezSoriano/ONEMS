/**
 * Calculate ISO 8601 week number from a date
 * Uses the same logic as allocationPlanCalculator.ts for consistency
 * @param date Date object or date string (YYYY-MM-DD)
 * @returns ISO week number
 */
function getWeekNumber(date: Date): number {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
  const dayNum = d.getUTCDay() || 7
  d.setUTCDate(d.getUTCDate() + 4 - dayNum)
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
  return Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7)
}

/**
 * Calculate ISO 8601 week number and year from a date string (YYYY-MM-DD)
 * @param dateString Date in format YYYY-MM-DD
 * @returns Object with year and week_number
 */
export function getISOWeekFromDate(dateString: string): { year: number; week_number: number } {
  if (!dateString) {
    return { year: new Date().getFullYear(), week_number: 1 };
  }

  const date = new Date(dateString + 'T00:00:00'); // Ensure local time
  
  // Calculate week number using ISO 8601 standard
  const weekNumber = getWeekNumber(date);
  
  // Determine the year for the week
  // If week is 1 and month is December, the week belongs to next year
  // If week is 52/53 and month is January, the week belongs to previous year
  const month = date.getMonth();
  let year = date.getFullYear();
  
  if (weekNumber === 1 && month === 11) {
    // Week 1 in December belongs to next year
    year += 1;
  } else if (weekNumber >= 52 && month === 0) {
    // Week 52/53 in January belongs to previous year
    year -= 1;
  }
  
  return {
    year,
    week_number: weekNumber
  };
}

/**
 * Format week for display
 * @param year Year
 * @param weekNumber Week number
 * @returns Formatted string like "2026-W05"
 */
export function formatWeek(year: number, weekNumber: number): string {
  return `${year}-W${String(weekNumber).padStart(2, '0')}`;
}
