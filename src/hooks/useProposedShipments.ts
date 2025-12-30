import { useState, useCallback } from 'react'
import { useAuth } from '../contexts/AuthContext'
import { supabase } from '../lib/supabase'
import { useEffectiveAccountId } from './useEffectiveAccountId'

export interface ProposedShipment {
  node_id: string
  node_name: string
  panelist_id: string | null
  panelist_name: string | null
  panelist_code: string | null
  assignment_status: 'assigned' | 'pending'
  materials: ShipmentMaterial[]
  total_quantity: number
  total_items: number
}

export interface ShipmentMaterial {
  material_id: string
  material_code: string
  material_name: string
  unit_measure: string
  quantity_needed: number
}

/**
 * Hook para calcular envíos propuestos basados en allocation plans
 * Similar a useMaterialRequirements pero enfocado en crear shipments
 */
export function useProposedShipments() {
  const effectiveAccountId = useEffectiveAccountId()
  const { profile } = useAuth()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [proposedShipments, setProposedShipments] = useState<ProposedShipment[]>([])

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
      // 1. Get allocation plan details in date range with pagination
      const allPlanDetails: any[] = []
      let hasMore = true
      let page = 0
      const pageSize = 1000

      while (hasMore) {
        const { data: planDetails, error: detailsError } = await supabase
          .from('allocation_plan_details')
          .select('id, plan_id, origin_node_id, origin_panelist_id, fecha_programada')
          .eq('account_id', accountId)
          .gte('fecha_programada', startDate)
          .lte('fecha_programada', endDate)
          .in('status', ['pending', 'notified'])
          .not('origin_node_id', 'is', null)
          .range(page * pageSize, (page + 1) * pageSize - 1)

        if (detailsError) throw detailsError
        
        if (planDetails && planDetails.length > 0) {
          allPlanDetails.push(...planDetails)
          hasMore = planDetails.length === pageSize
          page++
        } else {
          hasMore = false
        }
      }

      if (allPlanDetails.length === 0) {
        setProposedShipments([])
        return
      }

      // 2. Get allocation plans to get product_id
      const planIds = [...new Set(allPlanDetails.map(d => d.plan_id))]
      const { data: plans, error: plansError } = await supabase
        .from('allocation_plans')
        .select('id, product_id')
        .in('id', planIds)

      if (plansError) throw plansError
      if (!plans) {
        setProposedShipments([])
        return
      }

      // 3. Map plan_id → product_id
      const planProductMap: Record<string, string> = {}
      plans.forEach(p => {
        planProductMap[p.id] = p.product_id
      })

      const enrichedDetails = allPlanDetails.map(d => ({
        ...d,
        product_id: planProductMap[d.plan_id]
      })).filter(d => d.product_id)

      if (enrichedDetails.length === 0) {
        setProposedShipments([])
        return
      }

      // 4. Get product_materials
      const productIds = [...new Set(enrichedDetails.map(d => d.product_id))]
      const { data: productMaterials, error: pmError } = await supabase
        .from('product_materials')
        .select('product_id, material_id, quantity')
        .eq('account_id', accountId)
        .in('product_id', productIds)

      if (pmError) throw pmError
      if (!productMaterials) {
        setProposedShipments([])
        return
      }

      // 5. Get materials
      const materialIds = [...new Set(productMaterials.map(pm => pm.material_id))]
      const { data: materials, error: materialsError } = await supabase
        .from('material_catalog')
        .select('id, code, name, unit_measure, status')
        .in('id', materialIds)
        .eq('status', 'active')

      if (materialsError) throw materialsError
      if (!materials) {
        setProposedShipments([])
        return
      }

      const materialMap: Record<string, any> = {}
      materials.forEach(m => {
        materialMap[m.id] = m
      })

      // 6. Get unique nodes and find assigned panelists
      const nodeIds = [...new Set(enrichedDetails.map(d => d.origin_node_id).filter(Boolean))]
      
      const { data: nodes, error: nodesError } = await supabase
        .from('nodes')
        .select('id, auto_id')
        .in('id', nodeIds)

      if (nodesError) throw nodesError

      const nodeMap: Record<string, any> = {}
      if (nodes) {
        nodes.forEach(n => {
          nodeMap[n.id] = { id: n.id, name: n.auto_id }
        })
      }

      // Get panelists assigned to these nodes
      const { data: panelists, error: panelistsError } = await supabase
        .from('panelists')
        .select('id, name, panelist_code, node_id')
        .eq('account_id', accountId)
        .in('node_id', nodeIds)

      if (panelistsError) throw panelistsError

      const nodePanelistMap: Record<string, any> = {}
      if (panelists) {
        panelists.forEach(p => {
          nodePanelistMap[p.node_id] = p
        })
      }

      // 7. Group by node/panelist
      const shipmentsMap: Record<string, {
        node: any
        panelist: any | null
        materials: Record<string, { material: any; quantity: number }>
      }> = {}

      for (const detail of enrichedDetails) {
        const nodeId = detail.origin_node_id
        if (!nodeId) continue

        const node = nodeMap[nodeId]
        if (!node) continue

        if (!shipmentsMap[nodeId]) {
          let panelist = null
          if (detail.origin_panelist_id) {
            const { data: assignedPanelist } = await supabase
              .from('panelists')
              .select('id, name, panelist_code')
              .eq('id', detail.origin_panelist_id)
              .single()
            panelist = assignedPanelist
          } else {
            panelist = nodePanelistMap[nodeId] || null
          }

          shipmentsMap[nodeId] = {
            node,
            panelist,
            materials: {}
          }
        }

        // Calculate materials for this detail
        const materialsForProduct = productMaterials.filter(pm => pm.product_id === detail.product_id)
        
        for (const pm of materialsForProduct) {
          if (!materialMap[pm.material_id]) continue
          
          const materialId = pm.material_id
          if (!shipmentsMap[nodeId].materials[materialId]) {
            shipmentsMap[nodeId].materials[materialId] = {
              material: materialMap[materialId],
              quantity: 0
            }
          }
          
          shipmentsMap[nodeId].materials[materialId].quantity += pm.quantity
        }
      }

      // 8. Build result
      const shipments: ProposedShipment[] = Object.entries(shipmentsMap).map(([nodeId, data]) => {
        const materials: ShipmentMaterial[] = Object.values(data.materials).map(m => ({
          material_id: m.material.id,
          material_code: m.material.code,
          material_name: m.material.name,
          unit_measure: m.material.unit_measure || 'un',
          quantity_needed: m.quantity
        }))

        const totalQuantity = materials.reduce((sum, m) => sum + m.quantity_needed, 0)

        return {
          node_id: nodeId,
          node_name: data.node.name,
          panelist_id: data.panelist?.id || null,
          panelist_name: data.panelist?.name || null,
          panelist_code: data.panelist?.panelist_code || null,
          assignment_status: data.panelist ? 'assigned' : 'pending',
          materials,
          total_quantity: totalQuantity,
          total_items: materials.length
        }
      })

      // Sort by panelist name
      shipments.sort((a, b) => {
        const nameA = a.panelist_name || a.node_name
        const nameB = b.panelist_name || b.node_name
        return nameA.localeCompare(nameB)
      })

      setProposedShipments(shipments)
    } catch (err) {
      console.error('Error calculating proposed shipments:', err)
      setError(err instanceof Error ? err.message : 'Error calculating shipments')
    } finally {
      setLoading(false)
    }
  }, [profile?.account_id, effectiveAccountId])

  const reset = useCallback(() => {
    setProposedShipments([])
    setError(null)
  }, [])

  return {
    loading,
    error,
    proposedShipments,
    calculate,
    reset
  }
}
