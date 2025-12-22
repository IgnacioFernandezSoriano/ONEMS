import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { AllocationPlanDetailWithRelations } from '@/lib/types'

export function useAllocationPlanDetails() {
  const [details, setDetails] = useState<AllocationPlanDetailWithRelations[]>([])
  const [plans, setPlans] = useState<any[]>([])
  const [carriers, setCarriers] = useState<any[]>([])
  const [products, setProducts] = useState<any[]>([])
  const [cities, setCities] = useState<any[]>([])
  const [nodes, setNodes] = useState<any[]>([])
  const [panelists, setPanelists] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAll = async () => {
    try {
      setLoading(true)
      setError(null)

      // Fetch allocation plan details with availability status from view
      const { data: detailsData, error: detailsError } = await supabase
        .from('v_allocation_details_with_availability')
        .select('*')
        .order('fecha_programada', { ascending: true })

      if (detailsError) throw detailsError

      // Fetch additional data for filters and selectors
      const [plansRes, carriersRes, productsRes, citiesRes, nodesRes, panelistsRes] = await Promise.all([
        supabase.from('allocation_plans').select('id, plan_name, carrier_id, product_id').order('plan_name'),
        supabase.from('carriers').select('id, code, name').eq('status', 'active').order('name'),
        supabase.from('products').select('id, code, description').eq('status', 'active').order('description'),
        supabase.from('cities').select('id, code, name').eq('status', 'active').order('name'),
        supabase.from('nodes').select('id, auto_id, city_id').eq('status', 'active').order('auto_id'),
        supabase.from('panelists').select('id, panelist_code, name, node_id').eq('status', 'active').order('name'),
      ])

      if (plansRes.error) throw plansRes.error
      if (carriersRes.error) throw carriersRes.error
      if (productsRes.error) throw productsRes.error
      if (citiesRes.error) throw citiesRes.error
      if (nodesRes.error) throw nodesRes.error
      if (panelistsRes.error) throw panelistsRes.error

      // Enrich details with related data
      const enrichedDetails = (detailsData || []).map((detail: any) => {
        const plan = plansRes.data?.find((p) => p.id === detail.plan_id)
        const originNode = nodesRes.data?.find((n) => n.id === detail.origin_node_id)
        const destinationNode = nodesRes.data?.find((n) => n.id === detail.destination_node_id)
        const originCity = citiesRes.data?.find((c) => c.id === detail.origin_city_id)
        const destinationCity = citiesRes.data?.find((c) => c.id === detail.destination_city_id)
        const carrier = carriersRes.data?.find((c) => c.id === plan?.carrier_id)
        const product = productsRes.data?.find((p) => p.id === plan?.product_id)

        return {
          ...detail,
          plan,
          origin_node: originNode,
          destination_node: destinationNode,
          origin_city: originCity,
          destination_city: destinationCity,
          carrier,
          product,
        }
      })

      setDetails(enrichedDetails)
      setPlans(plansRes.data || [])
      setCarriers(carriersRes.data || [])
      setProducts(productsRes.data || [])
      setCities(citiesRes.data || [])
      setNodes(nodesRes.data || [])
      setPanelists(panelistsRes.data || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching allocation plan details:', err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAll()
  }, [])

  const updateDetail = async (id: string, updates: Partial<AllocationPlanDetailWithRelations>) => {
    try {
      // If status is being set to 'received', delete the record instead of updating
      // (the database trigger will have already transferred it to one_db)
      if (updates.status === 'received') {
        // First update to 'received' to trigger the one_db transfer
        const { error: updateError } = await supabase
          .from('allocation_plan_details')
          .update(updates)
          .eq('id', id)

        if (updateError) throw updateError

        // Then delete the record from allocation_plan_details
        const { error: deleteError } = await supabase
          .from('allocation_plan_details')
          .delete()
          .eq('id', id)

        if (deleteError) throw deleteError
      } else {
        // Normal update for other status changes
        const { error } = await supabase
          .from('allocation_plan_details')
          .update(updates)
          .eq('id', id)

        if (error) throw error
      }

      await fetchAll()
    } catch (err: any) {
      throw new Error(`Failed to update detail: ${err.message}`)
    }
  }

  const bulkUpdateDetails = async (ids: string[], updates: Partial<AllocationPlanDetailWithRelations>) => {
    try {
      const { error } = await supabase
        .from('allocation_plan_details')
        .update(updates)
        .in('id', ids)

      if (error) throw error
      await fetchAll()
    } catch (err: any) {
      throw new Error(`Failed to bulk update details: ${err.message}`)
    }
  }

  const bulkDeleteDetails = async (ids: string[]) => {
    try {
      // Validate IDs
      if (!ids || ids.length === 0) {
        throw new Error('No IDs provided for deletion')
      }

      // Filter out invalid IDs
      const validIds = ids.filter(id => id && typeof id === 'string' && id.length > 0)
      
      if (validIds.length === 0) {
        throw new Error('No valid IDs provided for deletion')
      }

      console.log('Attempting to delete', validIds.length, 'records')

      // Delete records individually in parallel batches of 10 to avoid overwhelming the API
      const batchSize = 10
      let deletedCount = 0
      let failedCount = 0
      
      for (let i = 0; i < validIds.length; i += batchSize) {
        const batch = validIds.slice(i, i + batchSize)
        
        const results = await Promise.allSettled(
          batch.map(id => 
            supabase
              .from('allocation_plan_details')
              .delete()
              .eq('id', id)
          )
        )
        
        results.forEach((result, index) => {
          if (result.status === 'fulfilled' && !result.value.error) {
            deletedCount++
          } else {
            failedCount++
            console.error(`Failed to delete ID ${batch[index]}:`, 
              result.status === 'fulfilled' ? result.value.error : result.reason)
          }
        })
      }

      console.log(`Deleted: ${deletedCount}, Failed: ${failedCount}`)
      
      if (failedCount > 0) {
        throw new Error(`Deleted ${deletedCount} records, but ${failedCount} failed`)
      }
      
      await fetchAll()
    } catch (err: any) {
      console.error('Bulk delete error:', err)
      throw new Error(`Failed to bulk delete details: ${err.message}`)
    }
  }

  const getNodesByCity = (cityId: string) => {
    return nodes.filter((node) => node.city_id === cityId)
  }

  const createDetail = async (newDetail: any) => {
    try {
      const { data, error } = await supabase
        .from('allocation_plan_details')
        .insert([newDetail])
        .select()
        .single()

      if (error) throw error

      // Refresh data after creation
      await fetchAll()
      
      return data
    } catch (err: any) {
      console.error('Error creating allocation plan detail:', err)
      throw err
    }
  }

  const markAsSent = async (
    detailId: string,
    data: {
      tag_id: string
      sent_at: string
      origin_panelist_id: string
      origin_panelist_name: string
    }
  ) => {
    try {
      // 1. Get allocation plan detail
      const detail = details.find(d => d.id === detailId)
      if (!detail) throw new Error('Allocation plan detail not found')

      // 2. Get product_id from plan
      const plan = plans.find(p => p.id === detail.plan_id)
      if (!plan || !plan.product_id) throw new Error('Product not found for this allocation plan')

      // 3. Get materials needed for this product
      const { data: productMaterials, error: materialsError } = await supabase
        .from('product_materials')
        .select('material_id, quantity, material_catalog(*)')
        .eq('product_id', plan.product_id)

      if (materialsError) throw materialsError

      if (!productMaterials || productMaterials.length === 0) {
        console.warn('No materials defined for this product')
      } else {
        // 4. For each material, deduct from panelist stock
        for (const pm of productMaterials) {
          // 4a. Get current stock of panelist
          const { data: currentStock } = await supabase
            .from('panelist_material_stocks')
            .select('id, quantity')
            .eq('panelist_id', data.origin_panelist_id)
            .eq('material_id', pm.material_id)
            .maybeSingle()

          const currentQuantity = currentStock?.quantity || 0
          const newQuantity = currentQuantity - pm.quantity

          // 4b. Update or create stock
          if (currentStock) {
            await supabase
              .from('panelist_material_stocks')
              .update({
                quantity: newQuantity,
                last_updated: new Date().toISOString()
              })
              .eq('id', currentStock.id)
          } else {
            await supabase
              .from('panelist_material_stocks')
              .insert({
                account_id: detail.account_id,
                panelist_id: data.origin_panelist_id,
                material_id: pm.material_id,
                quantity: newQuantity,
                last_updated: new Date().toISOString()
              })
          }

          // 4c. Create material movement
          const isNegative = newQuantity < 0
          const catalog = pm.material_catalog as any
          const movementNotes = isNegative
            ? `⚠️ STOCK ALERT: Negative stock after allocation shipment. Current: ${newQuantity} ${catalog?.unit_measure || 'units'}. Material: ${catalog?.name || pm.material_id}. Panelist: ${data.origin_panelist_name}. Tag: ${data.tag_id}`
            : `Allocation shipment - Tag: ${data.tag_id}, Panelist: ${data.origin_panelist_name}`

          await supabase
            .from('material_movements')
            .insert({
              account_id: detail.account_id,
              material_id: pm.material_id,
              movement_type: 'allocation_shipment',
              quantity: pm.quantity,
              from_location_type: 'panelist',
              from_location_id: data.origin_panelist_id,
              to_location_type: 'in_transit',
              to_location_id: null,
              reference_id: detailId,
              reference_type: 'allocation_plan_detail',
              notes: movementNotes,
              created_by: null
            })

          // Create stock alert if negative
          if (isNegative) {
            await supabase
              .from('stock_alerts')
              .insert({
                account_id: detail.account_id,
                material_id: pm.material_id,
                alert_type: 'panelist_negative',
                location_id: data.origin_panelist_id,
                current_quantity: newQuantity,
                expected_quantity: pm.quantity,
                reference_id: detailId,
                reference_type: 'allocation_plan_detail',
                notes: movementNotes
              })
          }
        }
      }

      // 5. Update allocation_plan_details status
      await updateDetail(detailId, {
        ...data,
        status: 'sent'
      })

    } catch (err: any) {
      throw new Error(`Failed to mark as sent: ${err.message}`)
    }
  }

  return {
    details,
    plans,
    carriers,
    products,
    cities,
    nodes,
    panelists,
    loading,
    error,
    updateDetail,
    createDetail,
    markAsSent,
    bulkUpdateDetails,
    bulkDeleteDetails,
    getNodesByCity,
    refresh: fetchAll,
  }
}
