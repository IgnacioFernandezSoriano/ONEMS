import { useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/contexts/AuthContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { useStockManagement } from '@/hooks/useStockManagement'
import { calculatePanelistRequirements } from '@/lib/materialCalculator'

export interface NeedLine {
  material_id: string
  material_code: string
  material_name: string
  unit_measure: string
  quantity_needed: number
  is_blocking: boolean
}

export interface SupplyPlan {
  fromCentral: { material_id: string; quantity: number }[]
  fromDonor: { material_id: string; quantity: number; donor_panelist_id: string; donor_name: string }[]
  toPurchase: { material_id: string; quantity: number }[]
}

export function useMaterialsTreatment() {
  const effectiveAccountId = useEffectiveAccountId()
  const { profile } = useAuth()
  const accountId = effectiveAccountId || profile?.account_id
  const { createShipment, markShipmentSent } = useStockManagement()

  const reconcileStock = useCallback(async (panelistId: string, materialId: string, realQty: number) => {
    const { error: e1 } = await supabase.from('panelist_material_stocks').upsert({
      account_id: accountId, panelist_id: panelistId, material_id: materialId,
      quantity: realQty, last_updated: new Date().toISOString()
    }, { onConflict: 'account_id,panelist_id,material_id' })
    if (e1) throw e1
    const { error: e2 } = await supabase.from('material_movements').insert({
      account_id: accountId, material_id: materialId, movement_type: 'adjustment',
      quantity: realQty, notes: 'Reconciliacion por incidencia de materiales', created_by: profile?.id
    })
    if (e2) throw e2
  }, [accountId, profile?.id])

  const recomputeNeed = useCallback(async (panelistId: string, startDate: string, endDate: string): Promise<NeedLine[]> => {
    if (!accountId) return []
    const requirements = await calculatePanelistRequirements(accountId, startDate, endDate)
    const panelistReq = requirements.find(r => r.panelist_id === panelistId)
    const materials = panelistReq?.materials || []
    if (materials.length === 0) return []

    const materialIds = materials.map(m => m.material_id)
    const { data: catalog, error } = await supabase
      .from('material_catalog')
      .select('id, is_blocking')
      .in('id', materialIds)
    if (error) throw error
    const blockingMap: Record<string, boolean> = {}
    ;(catalog || []).forEach((c: any) => { blockingMap[c.id] = !!c.is_blocking })

    return materials.map(m => ({
      material_id: m.material_id,
      material_code: m.material_code,
      material_name: m.material_name,
      unit_measure: m.unit_measure,
      quantity_needed: m.quantity_needed,
      is_blocking: blockingMap[m.material_id] ?? false
    }))
  }, [accountId])

  const resolveSupply = useCallback(async (needLines: NeedLine[], panelistId: string): Promise<SupplyPlan> => {
    const plan: SupplyPlan = { fromCentral: [], fromDonor: [], toPurchase: [] }
    if (!accountId) return plan

    const materialIds = needLines.map(n => n.material_id)
    const { data: centralStocks, error } = await supabase
      .from('material_stocks')
      .select('material_id, quantity')
      .eq('account_id', accountId)
      .in('material_id', materialIds)
    if (error) throw error
    const centralMap: Record<string, number> = {}
    ;(centralStocks || []).forEach((s: any) => { centralMap[s.material_id] = s.quantity })

    for (const need of needLines) {
      let remaining = need.quantity_needed
      if (remaining <= 0) continue

      const central = centralMap[need.material_id] || 0
      if (central > 0) {
        const fromCentralQty = Math.min(central, remaining)
        plan.fromCentral.push({ material_id: need.material_id, quantity: fromCentralQty })
        remaining -= fromCentralQty
      }

      if (remaining > 0) {
        const { data: donors, error: donorsError } = await supabase.rpc('find_surplus_donors', {
          p_account_id: accountId, p_receiver_panelist_id: panelistId,
          p_material_id: need.material_id, p_quantity: remaining
        })
        if (donorsError) throw donorsError
        const sortedDonors = ((donors || []) as any[]).sort((a, b) => {
          if (a.same_city !== b.same_city) return a.same_city ? -1 : 1
          return (b.available || 0) - (a.available || 0)
        })
        for (const donor of sortedDonors) {
          if (remaining <= 0) break
          const available = donor.available || 0
          if (available <= 0) continue
          const fromDonorQty = Math.min(available, remaining)
          plan.fromDonor.push({
            material_id: need.material_id, quantity: fromDonorQty,
            donor_panelist_id: donor.panelist_id, donor_name: donor.panelist_name
          })
          remaining -= fromDonorQty
        }
      }

      if (remaining > 0) {
        plan.toPurchase.push({ material_id: need.material_id, quantity: remaining })
      }
    }

    return plan
  }, [accountId])

  const executeSupply = useCallback(async (supplyPlan: SupplyPlan, receiverPanelistId: string): Promise<{ centralShipmentId: string | null }> => {
    let centralShipmentId: string | null = null

    if (supplyPlan.fromCentral.length > 0) {
      const shipment = await createShipment({
        panelist_id: receiverPanelistId,
        items: supplyPlan.fromCentral.map(c => ({ material_id: c.material_id, quantity_sent: c.quantity }))
      })
      centralShipmentId = shipment.id
      await markShipmentSent(shipment.id)
    }

    if (supplyPlan.fromDonor.length > 0) {
      const byDonor: Record<string, { material_id: string; quantity_sent: number }[]> = {}
      supplyPlan.fromDonor.forEach(d => {
        if (!byDonor[d.donor_panelist_id]) byDonor[d.donor_panelist_id] = []
        byDonor[d.donor_panelist_id].push({ material_id: d.material_id, quantity_sent: d.quantity })
      })
      for (const donorPanelistId of Object.keys(byDonor)) {
        const donorShipment = await createShipment({
          panelist_id: receiverPanelistId,
          items: byDonor[donorPanelistId],
          source_panelist_id: donorPanelistId
        })
        await markShipmentSent(donorShipment.id)
      }
    }

    return { centralShipmentId }
  }, [createShipment, markShipmentSent])

  const createDisplacementBaja = useCallback(async (incidentId: string, expectedDate: string): Promise<string> => {
    const today = new Date().toISOString().slice(0, 10)
    const { data, error } = await supabase.rpc('create_unavailability_from_incident', {
      p_incident_id: incidentId, p_start: today, p_end: expectedDate, p_reason: 'materials'
    })
    if (error) throw error
    return data as string
  }, [])

  const linkShipmentToIncident = useCallback(async (incidentId: string, shipmentId: string) => {
    const { error } = await supabase.from('panelist_incident')
      .update({ linked_material_shipment_id: shipmentId })
      .eq('id', incidentId)
    if (error) throw error
  }, [])

  return {
    reconcileStock,
    recomputeNeed,
    resolveSupply,
    executeSupply,
    createDisplacementBaja,
    linkShipmentToIncident
  }
}
