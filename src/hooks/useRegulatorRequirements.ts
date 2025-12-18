import { useState, useCallback, useEffect } from 'react'
import { useAuth } from '../contexts/AuthContext'
import { supabase } from '../lib/supabase'
import { calculateMaterialRequirements } from '../lib/materialCalculator'

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
  notes: string | null
  created_at: string
  updated_at: string
}

/**
 * Hook para calcular y gestionar requirements de materiales para el stock del regulador
 * Los requirements se persisten en la tabla material_requirements_periods
 */
export function useRegulatorRequirements() {
  const { profile } = useAuth()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [requirements, setRequirements] = useState<MaterialRequirementPeriod[]>([])

  const loadAllRequirements = useCallback(async () => {
    if (!profile?.account_id) return

    setLoading(true)
    try {
      const { data, error: loadError } = await supabase
        .from('material_requirements_periods')
        .select(`
          *,
          material:material_catalog(code, name, unit_measure)
        `)
        .eq('account_id', profile.account_id)
        .neq('status', 'received') // Show all pending and ordered
        .order('created_at', { ascending: false })

      if (loadError) throw loadError

      // Get current stocks to calculate net quantity
      const materialIds = (data || []).map(item => item.material_id)
      const { data: stocks } = await supabase
        .from('material_stocks')
        .select('material_id, quantity')
        .eq('account_id', profile.account_id)
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
    if (!profile?.account_id) {
      setError('No account ID found')
      return
    }

    setLoading(true)
    setError(null)

    try {
      
      // 1. Calculate requirements from allocation plans
      const calculatedRequirements = await calculateMaterialRequirements(
        profile.account_id,
        startDate,
        endDate
      )


      // 2. Get ALL existing pending requirements (to unify by material)
      const { data: allPendingRequirements } = await supabase
        .from('material_requirements_periods')
        .select('id, material_id, period_start, period_end, quantity_needed, plans_count')
        .eq('account_id', profile.account_id)
        .eq('status', 'pending')
        .in('material_id', calculatedRequirements.map(r => r.material_id))

      // Group pending requirements by material
      const pendingByMaterial: Record<string, Array<{
        id: string
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
        .eq('account_id', profile.account_id)
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
        .eq('account_id', profile.account_id)
        .eq('status', 'ordered')
        .in('material_id', materialIds)

      const orderedMap: Record<string, number> = {}
      if (orderedRequirements) {
        orderedRequirements.forEach(r => {
          orderedMap[r.material_id] = (orderedMap[r.material_id] || 0) + (r.quantity_ordered || 0)
        })
      }

      // 4. Process each calculated requirement and unify pending ones
      for (const req of calculatedRequirements) {
        const currentStock = stockMap[req.material_id] || 0
        const quantityOrdered = orderedMap[req.material_id] || 0
        
        // Net Quantity = Needed - Current Stock - Already Ordered (in transit)
        const netQuantity = Math.max(0, req.quantity_needed - currentStock - quantityOrdered)
        
        // Skip if we have enough stock + ordered
        if (netQuantity === 0) {
          continue
        }

        const existingPending = pendingByMaterial[req.material_id] || []
        
        if (existingPending.length > 0) {
          // Unify all pending requirements for this material
          // Calculate unified period (earliest start, latest end)
          const allPeriods = [...existingPending, { period_start: startDate, period_end: endDate }]
          const earliestStart = allPeriods.reduce((min, p) => 
            p.period_start < min ? p.period_start : min, 
            allPeriods[0].period_start
          )
          const latestEnd = allPeriods.reduce((max, p) => 
            p.period_end > max ? p.period_end : max, 
            allPeriods[0].period_end
          )
          
          // Sum all quantities
          const totalQuantityNeeded = existingPending.reduce((sum, p) => sum + p.quantity_needed, 0) + req.quantity_needed
          const totalPlansCount = existingPending.reduce((sum, p) => sum + p.plans_count, 0) + req.plans_count
          
          // Delete all existing pending records for this material
          await supabase
            .from('material_requirements_periods')
            .delete()
            .eq('account_id', profile.account_id)
            .eq('material_id', req.material_id)
            .eq('status', 'pending')
          
          // Insert unified requirement
          await supabase
            .from('material_requirements_periods')
            .insert({
              account_id: profile.account_id,
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
              account_id: profile.account_id,
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
  }, [profile?.account_id])

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
    try {
      // If quantity is null, use net quantity (quantity_needed - current stock)
      let quantityToOrder = quantity
      
      if (quantityToOrder === null) {
        const { data: req, error: fetchError } = await supabase
          .from('material_requirements_periods')
          .select('quantity_needed, material_id')
          .eq('id', requirementId)
          .single()

        if (fetchError) throw fetchError

        // Get current stock
        const { data: stock } = await supabase
          .from('material_stocks')
          .select('quantity')
          .eq('material_id', req.material_id)
          .eq('location_type', 'regulator')
          .maybeSingle()

        const currentStock = stock?.quantity || 0
        quantityToOrder = Math.max(0, req.quantity_needed - currentStock)
      }

      const { error: updateError } = await supabase
        .from('material_requirements_periods')
        .update({ 
          status: 'ordered',
          quantity_ordered: quantityToOrder,
          updated_at: new Date().toISOString()
        })
        .eq('id', requirementId)

      if (updateError) throw updateError

      // Reload all requirements
      await loadAllRequirements()
    } catch (err) {
      console.error('Error marking as ordered:', err)
      throw err
    }
  }, [loadAllRequirements, profile?.account_id])

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
