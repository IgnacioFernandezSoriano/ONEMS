import { useState, useCallback } from 'react'
import { useAuth } from '../contexts/AuthContext'
import { 
  calculateMaterialRequirements, 
  calculatePanelistRequirements,
  MaterialRequirement,
  PanelistMaterialRequirement
} from '../lib/materialCalculator'

export function useMaterialRequirements() {
  const { profile } = useAuth()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [materialRequirements, setMaterialRequirements] = useState<MaterialRequirement[]>([])
  const [panelistRequirements, setPanelistRequirements] = useState<PanelistMaterialRequirement[]>([])

  const calculate = useCallback(async (startDate: string, endDate: string) => {
    if (!profile?.account_id) {
      setError('No account ID found')
      return
    }

    setLoading(true)
    setError(null)

    try {
      const [materials, panelists] = await Promise.all([
        calculateMaterialRequirements(profile.account_id, startDate, endDate),
        calculatePanelistRequirements(profile.account_id, startDate, endDate)
      ])

      setMaterialRequirements(materials)
      setPanelistRequirements(panelists)
    } catch (err) {
      console.error('Error calculating requirements:', err)
      setError(err instanceof Error ? err.message : 'Error calculating requirements')
    } finally {
      setLoading(false)
    }
  }, [profile?.account_id])

  const reset = useCallback(() => {
    setMaterialRequirements([])
    setPanelistRequirements([])
    setError(null)
  }, [])

  return {
    loading,
    error,
    materialRequirements,
    panelistRequirements,
    calculate,
    reset
  }
}
