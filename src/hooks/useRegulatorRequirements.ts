import { useState, useCallback } from 'react'
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


      // 2. Check existing requirements for this period
      const { data: existingRequirements } = await supabase
        .from('material_requirements_periods')
        .select('material_id, status, quantity_needed')
        .eq('account_id', profile.account_id)
        .eq('period_start', startDate)
        .eq('period_end', endDate)

      const existingMap: Record<string, { status: string; quantity_needed: number }> = {}
      if (existingRequirements) {
        existingRequirements.forEach(r => {
          existingMap[r.material_id] = { status: r.status, quantity_needed: r.quantity_needed }
        })
      }

      // 3. Upsert or insert new requirements
      for (const req of calculatedRequirements) {
        const existing = existingMap[req.material_id]
        
        if (existing) {
          // If already ordered or received, create a NEW line instead of updating
          if (existing.status === 'ordered' || existing.status === 'received') {
            // Only create new line if quantity changed
            if (existing.quantity_needed !== req.quantity_needed) {
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
          } else {
            // Status is 'pending', safe to update
            await supabase
              .from('material_requirements_periods')
              .update({
                quantity_needed: req.quantity_needed,
                plans_count: req.plans_count,
                updated_at: new Date().toISOString()
              })
              .eq('account_id', profile.account_id)
              .eq('period_start', startDate)
              .eq('period_end', endDate)
              .eq('material_id', req.material_id)
              .eq('status', 'pending')
          }
        } else {
          // New requirement, insert
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

      // 3. Load persisted requirements for this period
      await loadRequirements(startDate, endDate)
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

      // Reload current requirements
      if (requirements.length > 0) {
        const firstReq = requirements[0]
        await loadRequirements(firstReq.period_start, firstReq.period_end)
      }
    } catch (err) {
      console.error('Error marking as ordered:', err)
      throw err
    }
  }, [requirements, loadRequirements, profile?.account_id])

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

      // Reload current requirements
      if (requirements.length > 0) {
        const firstReq = requirements[0]
        await loadRequirements(firstReq.period_start, firstReq.period_end)
      }
    } catch (err) {
      console.error('Error updating quantity received:', err)
      throw err
    }
  }, [requirements, loadRequirements])

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

      // 4. Reload requirements (will exclude received items)
      if (requirements.length > 0) {
        const firstReq = requirements[0]
        await loadRequirements(firstReq.period_start, firstReq.period_end)
      }
    } catch (err) {
      console.error('Error receiving PO:', err)
      throw err
    }
  }, [profile?.account_id, requirements, loadRequirements])

  const reset = useCallback(() => {
    setRequirements([])
    setError(null)
  }, [])

  return {
    loading,
    error,
    requirements,
    calculate,
    loadRequirements,
    markAsOrdered,
    receivePO,
    updateQuantityReceived,
    reset
  }
}
