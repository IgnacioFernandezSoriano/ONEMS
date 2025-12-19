import { supabase } from './supabase'

export interface MaterialRequirement {
  material_id: string
  material_code: string
  material_name: string
  unit_measure: string
  quantity_needed: number
  shipments_count: number
  plans_count: number
}

export interface PanelistMaterialRequirement {
  node_id: string
  node_name: string
  panelist_id: string | null
  panelist_name: string | null
  assignment_status: 'assigned' | 'pending'
  materials: PanelistMaterial[]
  total_items: number
}

export interface PanelistMaterial {
  material_id: string
  material_code: string
  material_name: string
  unit_measure: string
  quantity_needed: number
}

/**
 * Calcula las necesidades de materiales basándose en allocation plan details
 * entre dos fechas. NO gestiona stocks, solo calcula necesidades.
 */
export async function calculateMaterialRequirements(
  accountId: string,
  startDate: string,
  endDate: string
): Promise<MaterialRequirement[]> {
  try {
    // 1. Obtener allocation plan details en el rango de fechas
    const { data: planDetails, error: detailsError } = await supabase
      .from('allocation_plan_details')
      .select('id, plan_id, fecha_programada, origin_panelist_id')
      .eq('account_id', accountId)
      .gte('fecha_programada', startDate)
      .lte('fecha_programada', endDate)
      .in('status', ['pending', 'notified'])

    if (detailsError) throw detailsError
    if (!planDetails || planDetails.length === 0) {
      return []
    }

    // 2. Obtener los allocation plans para conseguir los product_id
    const planIds = [...new Set(planDetails.map(d => d.plan_id))]
    
    const { data: plans, error: plansError } = await supabase
      .from('allocation_plans')
      .select('id, product_id')
      .in('id', planIds)

    if (plansError) throw plansError
    if (!plans) {
      return []
    }

    // 3. Crear mapa de plan_id → product_id
    const planProductMap: Record<string, string> = {}
    plans.forEach(p => {
      planProductMap[p.id] = p.product_id
    })

    // 4. Enriquecer planDetails con product_id
    const enrichedDetails = planDetails.map(d => ({
      ...d,
      product_id: planProductMap[d.plan_id]
    })).filter(d => d.product_id)

    if (enrichedDetails.length === 0) return []

    // 5. Obtener materiales por producto
    const productIds = [...new Set(enrichedDetails.map(d => d.product_id))]
    
    const { data: productMaterials, error: pmError } = await supabase
      .from('product_materials')
      .select('product_id, material_id, quantity')
      .eq('account_id', accountId)
      .in('product_id', productIds)

    if (pmError) throw pmError
    if (!productMaterials || productMaterials.length === 0) {
      return []
    }

    // 6. Obtener información de materiales
    const materialIds = [...new Set(productMaterials.map(pm => pm.material_id))]
    const { data: materials, error: materialsError } = await supabase
      .from('material_catalog')
      .select('id, code, name, unit_measure, status')
      .in('id', materialIds)
      .eq('status', 'active')

    if (materialsError) throw materialsError
    if (!materials) return []

    // 7. Crear mapa de material_id → material
    const materialMap: Record<string, any> = {}
    materials.forEach(m => {
      materialMap[m.id] = m
    })

    // 8. Get panelist stocks to discount from requirements
    const panelistIds = [...new Set(enrichedDetails.map(d => d.origin_panelist_id).filter(Boolean))]
    const { data: panelistStocks } = await supabase
      .from('panelist_material_stocks')
      .select('panelist_id, material_id, quantity')
      .eq('account_id', accountId)
      .in('panelist_id', panelistIds)
      .in('material_id', materialIds)

    // Create map: panelist_id + material_id → quantity
    const panelistStockMap: Record<string, number> = {}
    if (panelistStocks) {
      panelistStocks.forEach(ps => {
        const key = `${ps.panelist_id}_${ps.material_id}`
        panelistStockMap[key] = ps.quantity
      })
    }

    // 9. Calculate materials needed (considering panelist stock)
    const materialsNeeded: Record<string, {
      material: any
      quantity: number
      panelistStockTotal: number
      shipments: Set<string>
      plans: Set<string>
    }> = {}

    for (const detail of enrichedDetails) {
      const materials = productMaterials.filter(pm => pm.product_id === detail.product_id)
      
      for (const pm of materials) {
        if (!materialMap[pm.material_id]) continue
        
        const materialId = pm.material_id
        if (!materialsNeeded[materialId]) {
          materialsNeeded[materialId] = {
            material: materialMap[materialId],
            quantity: 0,
            panelistStockTotal: 0,
            shipments: new Set(),
            plans: new Set()
          }
        }
        
        // Get panelist stock for this material
        const panelistStockKey = `${detail.origin_panelist_id}_${materialId}`
        const panelistStock = panelistStockMap[panelistStockKey] || 0
        
        // Only add to quantity needed if panelist doesn't have enough stock
        const quantityNeededForThisDetail = Math.max(0, pm.quantity - panelistStock)
        
        materialsNeeded[materialId].quantity += quantityNeededForThisDetail
        materialsNeeded[materialId].panelistStockTotal += panelistStock
        materialsNeeded[materialId].shipments.add(detail.id)
        materialsNeeded[materialId].plans.add(detail.plan_id)
      }
    }

    // 10. Get current stocks and minimum stocks to calculate safety stock needs
    const { data: stocks } = await supabase
      .from('material_stocks')
      .select('material_id, quantity, min_stock')
      .eq('account_id', accountId)
      .eq('location_type', 'regulator')
      .in('material_id', materialIds)

    const stockMap: Record<string, { quantity: number; min_stock: number | null }> = {}
    if (stocks) {
      stocks.forEach(s => {
        stockMap[s.material_id] = { quantity: s.quantity, min_stock: s.min_stock }
      })
    }

    // 11. Construir resultado incluyendo stock de seguridad
    const requirements: MaterialRequirement[] = Object.entries(materialsNeeded).map(([materialId, data]) => {
      const stock = stockMap[materialId] || { quantity: 0, min_stock: null }
      const currentStock = stock.quantity
      const minStock = stock.min_stock || 0
      
      // Calculate safety stock need (if current stock is below minimum)
      const safetyStockNeed = Math.max(0, minStock - currentStock)
      
      // Total quantity needed = allocation plans quantity + safety stock need
      const totalQuantityNeeded = data.quantity + safetyStockNeed
      
      return {
        material_id: materialId,
        material_code: data.material.code,
        material_name: data.material.name,
        unit_measure: data.material.unit_measure || 'un',
        quantity_needed: totalQuantityNeeded,
        shipments_count: data.shipments.size,
        plans_count: data.plans.size
      }
    })

    return requirements.sort((a, b) => b.quantity_needed - a.quantity_needed)
  } catch (error) {
    console.error('Error calculating material requirements:', error)
    throw error
  }
}

/**
 * Calcula las necesidades de materiales por nodo/panelista
 * Usa nodo_id del allocation_plan_details y busca el panelista asignado en la tabla panelists
 */
export async function calculatePanelistRequirements(
  accountId: string,
  startDate: string,
  endDate: string
): Promise<PanelistMaterialRequirement[]> {
  try {
    // 1. Obtener allocation plan details con nodos
    const { data: planDetails, error: detailsError } = await supabase
      .from('allocation_plan_details')
      .select('id, plan_id, origin_node_id, origin_panelist_id, fecha_programada')
      .eq('account_id', accountId)
      .gte('fecha_programada', startDate)
      .lte('fecha_programada', endDate)
      .in('status', ['pending', 'notified'])
      .not('origin_node_id', 'is', null)

    if (detailsError) throw detailsError
    if (!planDetails || planDetails.length === 0) return []

    // 2. Obtener allocation plans
    const planIds = [...new Set(planDetails.map(d => d.plan_id))]
    const { data: plans, error: plansError } = await supabase
      .from('allocation_plans')
      .select('id, product_id')
      .in('id', planIds)

    if (plansError) throw plansError
    if (!plans) return []

    const planProductMap: Record<string, string> = {}
    plans.forEach(p => {
      planProductMap[p.id] = p.product_id
    })

    const enrichedDetails = planDetails.map(d => ({
      ...d,
      product_id: planProductMap[d.plan_id]
    })).filter(d => d.product_id)

    if (enrichedDetails.length === 0) return []

    // 3. Obtener product_materials
    const productIds = [...new Set(enrichedDetails.map(d => d.product_id))]
    const { data: productMaterials, error: pmError } = await supabase
      .from('product_materials')
      .select('product_id, material_id, quantity')
      .eq('account_id', accountId)
      .in('product_id', productIds)

    if (pmError) throw pmError
    if (!productMaterials) return []

    // 4. Obtener materiales
    const materialIds = [...new Set(productMaterials.map(pm => pm.material_id))]
    const { data: materials, error: materialsError } = await supabase
      .from('material_catalog')
      .select('id, code, name, unit_measure, status')
      .in('id', materialIds)
      .eq('status', 'active')

    if (materialsError) throw materialsError
    if (!materials) return []

    const materialMap: Record<string, any> = {}
    materials.forEach(m => {
      materialMap[m.id] = m
    })

    // 5. Obtener nodos únicos y buscar panelistas asignados
    const nodeIds = [...new Set(enrichedDetails.map(d => d.origin_node_id).filter(Boolean))]
    
    // Obtener información de nodos desde nodes
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

    // Obtener panelistas asignados a estos nodos
    const { data: panelists, error: panelistsError } = await supabase
      .from('panelists')
      .select('id, name, node_id')
      .eq('account_id', accountId)
      .in('node_id', nodeIds)

    if (panelistsError) throw panelistsError

    // Crear mapa de node_id → panelista
    const nodePanelistMap: Record<string, any> = {}
    if (panelists) {
      panelists.forEach(p => {
        nodePanelistMap[p.node_id] = p
      })
    }

    // 6. Get panelist stocks to discount from shipments
    const panelistIds = [
      ...new Set(enrichedDetails.map(d => d.origin_panelist_id).filter(Boolean)),
      ...panelists.map(p => p.id)
    ]
    
    const { data: panelistStocks } = await supabase
      .from('panelist_material_stocks')
      .select('panelist_id, material_id, quantity')
      .eq('account_id', accountId)
      .in('panelist_id', panelistIds)
      .in('material_id', materialIds)

    // Create map: panelist_id + material_id → quantity
    const panelistStockMap: Record<string, number> = {}
    if (panelistStocks) {
      panelistStocks.forEach(ps => {
        const key = `${ps.panelist_id}_${ps.material_id}`
        panelistStockMap[key] = ps.quantity
      })
    }

    // 7. Agrupar por nodo
    const nodesMap: Record<string, {
      node: any
      panelist: any | null
      origin_panelist_id: string | null
      materials: Record<string, { material: any; quantity: number }>
    }> = {}

    for (const detail of enrichedDetails) {
      const nodeId = detail.origin_node_id
      if (!nodeId) continue

      const node = nodeMap[nodeId]
      if (!node) continue

      if (!nodesMap[nodeId]) {
        // Priorizar origin_panelist_id si existe, sino buscar por nodo
        let panelist = null
        if (detail.origin_panelist_id) {
          // Ya tiene panelista asignado por n8n
          const { data: assignedPanelist } = await supabase
            .from('panelists')
            .select('id, name')
            .eq('id', detail.origin_panelist_id)
            .single()
          panelist = assignedPanelist
        } else {
          // Buscar panelista asignado al nodo
          panelist = nodePanelistMap[nodeId] || null
        }

        nodesMap[nodeId] = {
          node,
          panelist,
          origin_panelist_id: detail.origin_panelist_id,
          materials: {}
        }
      }

      const materials = productMaterials.filter(pm => pm.product_id === detail.product_id)
      
      for (const pm of materials) {
        if (!materialMap[pm.material_id]) continue
        
        const materialId = pm.material_id
        if (!nodesMap[nodeId].materials[materialId]) {
          nodesMap[nodeId].materials[materialId] = {
            material: materialMap[materialId],
            quantity: 0
          }
        }
        
        nodesMap[nodeId].materials[materialId].quantity += pm.quantity
      }
    }

    // 8. Construir resultado (descontando stock del panelista)
    const requirements: PanelistMaterialRequirement[] = Object.entries(nodesMap).map(([nodeId, data]) => {
      const panelistId = data.panelist?.id || data.origin_panelist_id
      
      const panelistMaterials: PanelistMaterial[] = Object.entries(data.materials)
        .map(([materialId, matData]) => {
          // Get panelist stock for this material
          const stockKey = `${panelistId}_${materialId}`
          const panelistStock = panelistStockMap[stockKey] || 0
          
          // Calculate net quantity needed (discount panelist stock)
          const netQuantity = Math.max(0, matData.quantity - panelistStock)
          
          return {
            material_id: materialId,
            material_code: matData.material.code,
            material_name: matData.material.name,
            unit_measure: matData.material.unit_measure || 'un',
            quantity_needed: netQuantity
          }
        })
        .filter(m => m.quantity_needed > 0) // Only include if quantity needed > 0

      const totalItems = panelistMaterials.reduce((sum, m) => sum + m.quantity_needed, 0)

      return {
        node_id: nodeId,
        node_name: data.node.name,
        panelist_id: data.panelist?.id || null,
        panelist_name: data.panelist?.name || null,
        assignment_status: data.panelist ? 'assigned' : 'pending',
        materials: panelistMaterials,
        total_items: totalItems
      }
    })

    return requirements.filter(r => r.total_items > 0).sort((a, b) => b.total_items - a.total_items)
  } catch (error) {
    console.error('Error calculating panelist requirements:', error)
    throw error
  }
}
