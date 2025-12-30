import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/contexts/AuthContext'
import { useEffectiveAccountId } from './useEffectiveAccountId'
import {
  calculateMaterialRequirements,
  calculatePanelistRequirements
} from '@/lib/materialCalculator'

export interface MaterialRequirementPeriod {
  id: string
  account_id: string
  period_start: string
  period_end: string
  material_id: string
  material_code: string
  material_name: string
  unit_measure: string
  quantity_needed: number
  quantity_ordered: number
  quantity_received: number
  net_quantity: number // calculated: quantity_needed - current_stock
  status: 'pending' | 'ordered' | 'received'
  plans_count: number
  created_at?: string
  material?: {
    code: string
    name: string
    unit_measure: string
  }
}

/**
 * Hook for managing material requirements at the regulator level.
 * Handles calculation, loading, and status updates of material requirements.
 */
export function useRegulatorRequirements() {
  const { profile } = useAuth()
  const effectiveAccountId = useEffectiveAccountId()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [requirements, setRequirements] = useState<MaterialRequirementPeriod[]>([])

  const loadAllRequirements = useCallback(async () => {
    if (!profile?.account_id) return

    setLoading(true)
    try {
      // Implement pagination to handle more than 1000 records
      const allData: any[] = []
      let hasMore = true
      let page = 0
      const pageSize = 1000

      while (hasMore) {
        const { data, error: loadError } = await supabase
          .from('material_requirements_periods')
          .select(`
            *,
            material:material_catalog(code, name, unit_measure)
          `)
          .eq('account_id', profile.account_id)
          .neq('status', 'received') // Show all pending and ordered
          .order('created_at', { ascending: false })
          .range(page * pageSize, (page + 1) * pageSize - 1)

        if (loadError) throw loadError
        
        if (data && data.length > 0) {
          allData.push(...data)
          hasMore = data.length === pageSize
          page++
        } else {
          hasMore = false
        }
      }

      // Get current stocks to calculate net quantity
      const materialIds = allData.map(item => item.material_id)
      const { data: stocks } = await supabase
        .from('material_stocks')
        .select('material_id, quantity')
        .eq('account_id', profile.account_id)
        .eq('location_type', 'regulator')
        .in('material_id', materialIds)

      const stockMap: Record<string, number> = {}
      if (stocks) {
        stocks.forEach(s => {
          stockMap[s.material_id] = s.quantity
        })
      }

      const formatted = allData.map(item => {
        const currentStock = stockMap[item.material_id] || 0
        const netQuantity = Math.max(0, item.quantity_needed - currentStock)
        return {
          ...item,
          material_code: item.material?.code || 'N/A',
          material_name: item.material?.name || 'No name',
          unit_measure: item.material?.unit_measure || 'un',
          net_quantity: netQuantity
        }
      })

      setRequirements(formatted)
    } catch (err) {
      console.error('Error loading all requirements:', err)
      setError(err instanceof Error ? err.message : 'Error loading requirements')
    } finally {
      setLoading(false)
    }
  }, [profile?.account_id])

  // Load all requirements on mount
  useEffect(() => {
    if (profile?.account_id) {
      loadAllRequirements()
    }
  }, [profile?.account_id, loadAllRequirements])

  const calculate = useCallback(async (startDate: string, endDate: string) => {
    // Use effectiveAccountId if available, otherwise fall back to profile.account_id
    const accountId = effectiveAccountId || profile?.account_id
    
    if (!accountId) {
      setError('No account ID found')
      return
    }

    setLoading(true)
    setError(null)

    try {
      // 1. Calculate requirements for this period
      const calculatedRequirements = await calculateMaterialRequirements(
        accountId,
        startDate,
        endDate
      )


      // 2. Get ALL existing pending requirements (to unify by material)
      const { data: allPendingRequirements } = await supabase
        .from('material_requirements_periods')
        .select('id, material_id, period_start, period_end, quantity_needed, plans_count')
        .eq('account_id', accountId)
        .eq('status', 'pending')
        .in('material_id', calculatedRequirements.map(r => r.material_id))

      // Group pending requirements by material
      const pendingByMaterial: Record<string, Array<{
        id: string
        material_id: string
        period_start: string
        period_end: string
        quantity_needed: number
        plans_count: number
      }>> = {}

      if (allPendingRequirements) {
        allPendingRequirements.forEach(r => {
          if (!pendingByMaterial[r.material_id]) {
            pendingByMaterial[r.material_id] = []
          }
          pendingByMaterial[r.material_id].push(r)
        })
      }

      // 3. Get current stocks to calculate net quantity
      const materialIds = calculatedRequirements.map(r => r.material_id)
      const { data: stocks } = await supabase
        .from('material_stocks')
        .select('material_id, quantity')
        .eq('account_id', accountId)
        .eq('location_type', 'regulator')
        .in('material_id', materialIds)

      const stockMap: Record<string, number> = {}
      if (stocks) {
        stocks.forEach(s => {
          stockMap[s.material_id] = s.quantity
        })
      }

      // Get ordered quantities (in transit) for this period
      const { data: orderedRequirements } = await supabase
        .from('material_requirements_periods')
        .select('material_id, quantity_ordered')
        .eq('account_id', accountId)
        .eq('status', 'ordered')
        .in('material_id', materialIds)

      const orderedMap: Record<string, number> = {}
      if (orderedRequirements) {
        orderedRequirements.forEach(o => {
          orderedMap[o.material_id] = (orderedMap[o.material_id] || 0) + (o.quantity_ordered || 0)
        })
      }

      // 4. For each calculated requirement, check if there's existing pending
      for (const req of calculatedRequirements) {
        const currentStock = stockMap[req.material_id] || 0
        const orderedQuantity = orderedMap[req.material_id] || 0
        const netQuantity = Math.max(0, req.quantity_needed - currentStock - orderedQuantity)

        const existingPending = pendingByMaterial[req.material_id]

        if (existingPending && existingPending.length > 0) {
          // Unify all pending requirements for this material
          // Find earliest start and latest end
          const earliestStart = [startDate, ...existingPending.map(p => p.period_start)]
            .sort()[0]
          const latestEnd = [endDate, ...existingPending.map(p => p.period_end)]
            .sort()
            .reverse()[0]
          
          // Sum all quantities
          const totalQuantityNeeded = existingPending.reduce((sum, p) => sum + p.quantity_needed, 0) + req.quantity_needed
          const totalPlansCount = existingPending.reduce((sum, p) => sum + p.plans_count, 0) + req.plans_count
          
          // Delete all existing pending records for this material
          await supabase
            .from('material_requirements_periods')
            .delete()
            .eq('account_id', accountId)
            .eq('material_id', req.material_id)
            .eq('status', 'pending')
          
          // Insert unified requirement
          await supabase
            .from('material_requirements_periods')
            .insert({
              account_id: accountId,
              period_start: earliestStart,
              period_end: latestEnd,
              material_id: req.material_id,
              quantity_needed: totalQuantityNeeded,
              plans_count: totalPlansCount,
              status: 'pending'
            })
          
          // Clear from map to avoid reprocessing
          delete pendingByMaterial[req.material_id]
        } else {
          // No existing pending, insert new
          await supabase
            .from('material_requirements_periods')
            .insert({
              account_id: accountId,
              period_start: startDate,
              period_end: endDate,
              material_id: req.material_id,
              quantity_needed: req.quantity_needed,
              plans_count: req.plans_count,
              status: 'pending'
            })
        }
      }

      // 5. Load all persisted requirements (not just this period)
      await loadAllRequirements()
    } catch (err) {
      console.error('Error calculating regulator requirements:', err)
      setError(err instanceof Error ? err.message : 'Error calculating requirements')
    } finally {
      setLoading(false)
    }
  }, [profile?.account_id, effectiveAccountId, loadAllRequirements])

  const loadRequirements = useCallback(async (startDate: string, endDate: string) => {
    if (!profile?.account_id) return

    try {
      const { data, error: loadError } = await supabase
        .from('material_requirements_periods')
        .select(`
          *,
          material:material_catalog(code, name, unit_measure)
        `)
        .eq('account_id', profile.account_id)
        .eq('period_start', startDate)
        .eq('period_end', endDate)
        .neq('status', 'received') // Don't show received items
        .order('created_at', { ascending: false })


      if (loadError) throw loadError

      // Get current stocks to calculate net quantity
      const materialIds = (data || []).map(item => item.material_id)
      const { data: stocks } = await supabase
        .from('material_stocks')
        .select('material_id, quantity')
        .eq('account_id', profile.account_id)
        .eq('location_type', 'regulator')
        .in('material_id', materialIds)

      const stockMap: Record<string, number> = {}
      if (stocks) {
        stocks.forEach(s => {
          stockMap[s.material_id] = s.quantity
        })
      }

      const formatted = (data || []).map(item => {
        const currentStock = stockMap[item.material_id] || 0
        const netQuantity = Math.max(0, item.quantity_needed - currentStock)
        return {
          ...item,
          material_code: item.material?.code || 'N/A',
          material_name: item.material?.name || 'No name',
          unit_measure: item.material?.unit_measure || 'un',
          net_quantity: netQuantity
        }
      })

      setRequirements(formatted)
    } catch (err) {
      console.error('Error loading requirements:', err)
      setError(err instanceof Error ? err.message : 'Error loading requirements')
    }
  }, [profile?.account_id])

  const markAsOrdered = useCallback(async (requirementId: string, quantity: number | null) => {
    if (!profile?.account_id) return

    try {
      // If quantity is null, fetch it from the requirement
      let quantityToOrder = quantity
      if (quantityToOrder === null) {
        const { data: req, error: fetchError } = await supabase
          .from('material_requirements_periods')
          .select('quantity_needed, material_id')
          .eq('id', requirementId)
          .single()

        if (fetchError) throw fetchError
        if (!req) throw new Error('Requirement not found')
        
        quantityToOrder = req.quantity_needed
      }

      if (quantityToOrder === null || quantityToOrder <= 0) {
        throw new Error('Invalid quantity to order')
      }

      // Update status and quantity_ordered
      const { error: updateError } = await supabase
        .from('material_requirements_periods')
        .update({ 
          status: 'ordered',
          quantity_ordered: quantityToOrder
        })
        .eq('id', requirementId)

      if (updateError) throw updateError

      // Refresh requirements
      await loadAllRequirements()
    } catch (err) {
      console.error('Error marking as ordered:', err)
      throw err
    }
  }, [profile?.account_id, loadAllRequirements])

  const markAsReceived = useCallback(async (requirementId: string, quantityReceived: number) => {
    if (!profile?.account_id) return

    try {
      // Get current requirement
      const { data: current, error: fetchError } = await supabase
        .from('material_requirements_periods')
        .select('quantity_needed, quantity_received')
        .eq('id', requirementId)
        .single()

      if (fetchError) throw fetchError
      if (!current) throw new Error('Requirement not found')

      const newTotalReceived = (current.quantity_received || 0) + quantityReceived

      const { error: updateError } = await supabase
        .from('material_requirements_periods')
        .update({
          quantity_received: newTotalReceived,
          status: newTotalReceived >= current.quantity_needed ? 'received' : 'ordered'
        })
        .eq('id', requirementId)

      if (updateError) throw updateError

      // Refresh requirements
      await loadAllRequirements()
    } catch (err) {
      console.error('Error marking as received:', err)
      throw err
    }
  }, [profile?.account_id, loadAllRequirements])

  const receiveAndTransferToStock = useCallback(async (
    requirementId: string,
    quantityReceived: number
  ) => {
    if (!profile?.account_id) return

    try {
      // Get requirement details
      const { data: requirement, error: fetchError } = await supabase
        .from('material_requirements_periods')
        .select('material_id, quantity_needed, quantity_received')
        .eq('id', requirementId)
        .single()

      if (fetchError) throw fetchError
      if (!requirement) throw new Error('Requirement not found')

      // 1. Get or create regulator stock
      const { data: existingStock } = await supabase
        .from('material_stocks')
        .select('id, quantity')
        .eq('account_id', profile.account_id)
        .eq('material_id', requirement.material_id)
        .eq('location_type', 'regulator')
        .maybeSingle()

      if (existingStock) {
        // Update existing stock
        await supabase
          .from('material_stocks')
          .update({
            quantity: existingStock.quantity + quantityReceived
          })
          .eq('id', existingStock.id)
      } else {
        // Create new stock entry
        await supabase
          .from('material_stocks')
          .insert({
            account_id: profile.account_id,
            material_id: requirement.material_id,
            location_type: 'regulator',
            quantity: quantityReceived
          })
      }

      // 2. Update requirement
      const newTotalReceived = (requirement.quantity_received || 0) + quantityReceived
      await supabase
        .from('material_requirements_periods')
        .update({
          quantity_received: newTotalReceived,
          status: newTotalReceived >= requirement.quantity_needed ? 'received' : 'ordered'
        })
        .eq('id', requirementId)

      // Refresh requirements
      await loadAllRequirements()
    } catch (err) {
      console.error('Error receiving and transferring to stock:', err)
      throw err
    }
  }, [profile?.account_id, loadAllRequirements])

  const updateQuantityReceived = useCallback(async (
    requirementId: string,
    quantityReceived: number
  ) => {
    try {
      // Get current requirement
      const { data: current, error: fetchError } = await supabase
        .from('material_requirements_periods')
        .select('quantity_needed, quantity_received')
        .eq('id', requirementId)
        .single()

      if (fetchError) throw fetchError

      const newTotalReceived = (current.quantity_received || 0) + quantityReceived
      const newStatus = newTotalReceived >= current.quantity_needed ? 'received' : 'pending'

      const { error: updateError } = await supabase
        .from('material_requirements_periods')
        .update({
          quantity_received: newTotalReceived,
          status: newStatus,
          updated_at: new Date().toISOString()
        })
        .eq('id', requirementId)

      if (updateError) throw updateError

      // Reload all requirements
      await loadAllRequirements()
    } catch (err) {
      console.error('Error updating quantity received:', err)
      throw err
    }
  }, [loadAllRequirements])

  const receivePO = useCallback(async (
    requirementId: string,
    quantityReceived: number
  ) => {
    if (!profile?.account_id) return

    try {
      // Get requirement details
      const { data: requirement, error: fetchError } = await supabase
        .from('material_requirements_periods')
        .select('material_id, quantity_needed, quantity_received')
        .eq('id', requirementId)
        .single()

      if (fetchError) throw fetchError

      // 1. Update or create regulator stock
      const { data: existingStock } = await supabase
        .from('material_stocks')
        .select('id, quantity')
        .eq('account_id', profile.account_id)
        .eq('material_id', requirement.material_id)
        .eq('location_type', 'regulator')
        .maybeSingle()

      if (existingStock) {
        // Update existing stock
        await supabase
          .from('material_stocks')
          .update({
            quantity: existingStock.quantity + quantityReceived,
            updated_at: new Date().toISOString()
          })
          .eq('id', existingStock.id)
      } else {
        // Create new stock record
        await supabase
          .from('material_stocks')
          .insert({
            account_id: profile.account_id,
            material_id: requirement.material_id,
            location_type: 'regulator',
            location_id: null,
            quantity: quantityReceived,
            min_stock: null,
            max_stock: null
          })
      }

      // 2. Create movement record
      await supabase
        .from('material_movements')
        .insert({
          account_id: profile.account_id,
          material_id: requirement.material_id,
          movement_type: 'receipt',
          quantity: quantityReceived,
          from_location_type: null,
          from_location_id: null,
          to_location_type: 'regulator',
          to_location_id: null,
          notes: `Stock receipt from purchase order - Requirement ${requirementId}`,
          reference_id: requirementId,
          reference_type: 'requirement'
        })

      // 3. Update requirement status to received
      const newTotalReceived = (requirement.quantity_received || 0) + quantityReceived
      await supabase
        .from('material_requirements_periods')
        .update({
          quantity_received: newTotalReceived,
          status: 'received',
          updated_at: new Date().toISOString()
        })
        .eq('id', requirementId)

      // 4. Reload all requirements (will exclude received items)
      await loadAllRequirements()
    } catch (err) {
      console.error('Error receiving PO:', err)
      throw err
    }
  }, [profile?.account_id, loadAllRequirements])

  const reset = useCallback(() => {
    setRequirements([])
    setError(null)
  }, [])

  const deleteRequirement = useCallback(async (requirementId: string) => {
    try {
      const { error: deleteError } = await supabase
        .from('material_requirements_periods')
        .delete()
        .eq('id', requirementId)

      if (deleteError) throw deleteError

      // Reload all requirements
      await loadAllRequirements()
    } catch (err) {
      console.error('Error deleting requirement:', err)
      throw err
    }
  }, [loadAllRequirements])

  return {
    loading,
    error,
    requirements,
    calculate,
    loadRequirements,
    loadAllRequirements,
    markAsOrdered,
    receivePO,
    updateQuantityReceived,
    deleteRequirement,
    reset
  }
}
