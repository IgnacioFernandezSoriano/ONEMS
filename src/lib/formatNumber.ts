/**
 * Format number with adaptive decimal places
 * - Values between -1 and 1 (excluding ±1): 3 decimals
 * - All other values: 1 decimal
 */
export function formatNumber(value: number | null | undefined): string {
  if (value === null || value === undefined || isNaN(value)) {
    return '0.0'
  }

  const absValue = Math.abs(value)
  
  // Values between -1 and 1 (excluding ±1): 3 decimals
  if (absValue > 0 && absValue < 1) {
    return value.toFixed(3)
  }
  
  // All other values: 1 decimal
  return value.toFixed(1)
}
