/**
 * Calculate J+K Actual as the day where cumulative samples reach the target STD %
 * This is the industry-standard method for calculating J+K Actual
 * 
 * @param daysArray - Array of business transit days for all samples
 * @param standardPercentage - Target percentage (e.g., 85%)
 * @param fallbackDays - Fallback value if calculation fails (usually standardDays)
 * @returns The day where cumulative samples >= STD %
 */
export function calculateJKActualFromDays(
  daysArray: number[],
  standardPercentage: number,
  fallbackDays: number
): number {
  if (daysArray.length === 0 || standardPercentage <= 0) {
    return fallbackDays;
  }

  // Create distribution: day -> count
  const distribution: Record<number, number> = {};
  daysArray.forEach(day => {
    const roundedDay = Math.round(day);
    distribution[roundedDay] = (distribution[roundedDay] || 0) + 1;
  });

  // Sort days ascending
  const sortedDays = Object.keys(distribution)
    .map(Number)
    .sort((a, b) => a - b);

  // Find day where cumulative samples >= target
  let cumulativeSamples = 0;
  const targetSamples = (standardPercentage / 100) * daysArray.length;

  for (const day of sortedDays) {
    cumulativeSamples += distribution[day];
    if (cumulativeSamples >= targetSamples) {
      return day;
    }
  }

  // If we reach here, return the last day (shouldn't happen in practice)
  return sortedDays[sortedDays.length - 1] || fallbackDays;
}
