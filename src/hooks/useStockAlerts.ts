import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

export interface StockAlert {
  id: string
  account_id: string
  material_id: string
  alert_type: 'regulator_insufficient' | 'panelist_negative'
  location_id: string | null
  current_quantity: number
  expected_quantity: number | null
  reference_id: string | null
  reference_type: string | null
  notes: string | null
  created_at: string
  resolved_at: string | null
  material_code?: string
  material_name?: string
  unit_measure?: string
  panelist_name?: string
  panelist_code?: string
}

export function useStockAlerts() {
  const { profile } = useAuth()
  const accountId = profile?.account_id

  const [alerts, setAlerts] = useState<StockAlert[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const loadAlerts = async () => {
    if (!accountId) return

    try {
      setLoading(true)
      setError(null)

      // Load active alerts from view
      const { data, error: fetchError } = await supabase
        .from('v_active_stock_alerts')
        .select('*')
        .eq('account_id', accountId)
        .order('created_at', { ascending: false })

      if (fetchError) throw fetchError

      // Enrich alerts with panelist information
      if (data && data.length > 0) {
        // Get unique panelist IDs from alerts that don't have panelist_name
        const panelistIds = Array.from(new Set(
          data
            .filter(alert => alert.alert_type === 'panelist_negative' && alert.location_id && !alert.panelist_name)
            .map(alert => alert.location_id)
        ))

        console.log('[Stock Alerts] Alerts loaded:', data.length)
        console.log('[Stock Alerts] Panelist IDs to enrich:', panelistIds)

        if (panelistIds.length > 0) {
          // Fetch panelist information with account_id filter
          const { data: panelists, error: panelistError } = await supabase
            .from('panelists')
            .select('id, name, panelist_code')
            .eq('account_id', accountId)
            .in('id', panelistIds)

          console.log('[Stock Alerts] Panelists fetched:', panelists?.length || 0)

          if (panelistError) {
            console.error('[Stock Alerts] Error fetching panelists:', panelistError)
          } else if (panelists && panelists.length > 0) {
            // Create a map for quick lookup
            const panelistMap = new Map(panelists.map(p => [p.id, p]))

            // Enrich alerts with panelist data
            const enrichedData = data.map(alert => {
              if (alert.alert_type === 'panelist_negative' && alert.location_id && !alert.panelist_name) {
                const panelist = panelistMap.get(alert.location_id)
                if (panelist) {
                  console.log(`[Stock Alerts] Enriching alert ${alert.id} with panelist ${panelist.name}`)
                  return {
                    ...alert,
                    panelist_name: panelist.name,
                    panelist_code: panelist.panelist_code
                  }
                } else {
                  console.warn(`[Stock Alerts] Panelist not found for location_id: ${alert.location_id}`)
                }
              }
              return alert
            })

            setAlerts(enrichedData)
            return
          } else {
            console.warn('[Stock Alerts] No panelists found for IDs:', panelistIds)
          }
        }
      }

      setAlerts(data || [])
    } catch (err: any) {
      console.error('Error loading stock alerts:', err)
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const createAlert = async (alert: {
    material_id: string
    alert_type: 'regulator_insufficient' | 'panelist_negative'
    location_id?: string | null
    current_quantity: number
    expected_quantity?: number | null
    reference_id?: string | null
    reference_type?: string | null
    notes?: string | null
  }) => {
    if (!accountId) return

    try {
      const { error: insertError } = await supabase
        .from('stock_alerts')
        .insert({
          account_id: accountId,
          ...alert
        })

      if (insertError) throw insertError

      await loadAlerts()
    } catch (err: any) {
      console.error('Error creating stock alert:', err)
      throw err
    }
  }

  const getAlertCounts = () => {
    const regulatorAlerts = alerts.filter(a => a.alert_type === 'regulator_insufficient')
    const panelistAlerts = alerts.filter(a => a.alert_type === 'panelist_negative')

    return {
      regulator: regulatorAlerts.length,
      panelist: panelistAlerts.length,
      total: alerts.length,
      regulatorMaterials: new Set(regulatorAlerts.map(a => a.material_id)).size,
      panelistMaterials: new Set(panelistAlerts.map(a => a.material_id)).size
    }
  }

  const getAffectedMaterials = (alertType: 'regulator_insufficient' | 'panelist_negative') => {
    return Array.from(new Set(
      alerts
        .filter(a => a.alert_type === alertType)
        .map(a => a.material_id)
    ))
  }

  useEffect(() => {
    loadAlerts()
  }, [accountId])

  return {
    alerts,
    loading,
    error,
    createAlert,
    getAlertCounts,
    getAffectedMaterials,
    reload: loadAlerts
  }
}
