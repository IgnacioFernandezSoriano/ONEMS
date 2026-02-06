// ============================================
// DATE UTILITIES
// ============================================

export function diffInHours(date1: string, date2: string): number {
  const d1 = new Date(date1).getTime()
  const d2 = new Date(date2).getTime()
  const diffMs = Math.abs(d2 - d1)
  return diffMs / (1000 * 60 * 60)
}

export function diffInMinutes(date1: string, date2: string): number {
  const d1 = new Date(date1).getTime()
  const d2 = new Date(date2).getTime()
  const diffMs = Math.abs(d2 - d1)
  return diffMs / (1000 * 60)
}

export function roundToDecimals(value: number, decimals: number): number {
  return Math.round(value * Math.pow(10, decimals)) / Math.pow(10, decimals)
}
