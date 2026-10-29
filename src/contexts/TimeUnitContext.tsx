import { useCallback, useMemo, useState, ReactNode } from 'react'
import type { TimeUnit } from '../lib/accountTime'
import { TimeUnitContext } from '../hooks/useTimeUnit'

const STORAGE_KEY = 'onems.timeUnit'

function readInitialUnit(): TimeUnit {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    return stored === 'days' || stored === 'hours' ? stored : 'hours'
  } catch {
    return 'hours'
  }
}

export function TimeUnitProvider({ children }: { children: ReactNode }) {
  const [unit, setUnitState] = useState<TimeUnit>(() => readInitialUnit())

  const setUnit = useCallback((u: TimeUnit) => {
    setUnitState(u)
    try {
      localStorage.setItem(STORAGE_KEY, u)
    } catch {
      // almacenamiento no disponible: se mantiene solo en memoria
    }
  }, [])

  const value = useMemo(() => ({ unit, setUnit }), [unit, setUnit])

  return <TimeUnitContext.Provider value={value}>{children}</TimeUnitContext.Provider>
}
