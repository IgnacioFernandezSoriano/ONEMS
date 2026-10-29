import { createContext, useContext } from 'react'
import type { TimeUnit } from '../lib/accountTime'

export interface TimeUnitContextValue {
  unit: TimeUnit
  setUnit: (u: TimeUnit) => void
}

export const TimeUnitContext = createContext<TimeUnitContextValue | undefined>(undefined)

export function useTimeUnit() {
  const ctx = useContext(TimeUnitContext)
  if (!ctx) throw new Error('useTimeUnit must be used within a TimeUnitProvider')
  return ctx
}
