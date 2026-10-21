import { useCallback } from 'react'
import { eachDayOfInterval, format, isWeekend } from 'date-fns'
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

// Linea de suministro por material (v2: vecinos de la misma ciudad -> central -> compra).
// `donors` y `centralAvailable` son la disponibilidad completa de cada origen: la pantalla
// los usa para aplicar los cambios de origen del manager sin superar lo disponible.
export interface SupplyLine {
  material_id: string
  code: string
  name: string
  is_blocking: boolean
  need: number
  fromNeighbours: { donor_panelist_id: string; donor_name: string; quantity: number }[]
  fromCentral: number
  toPurchase: number
  donors: { donor_panelist_id: string; donor_name: string; available: number }[]
  centralAvailable: number
}

// Restos por debajo de esto son error de coma flotante, no cantidad real (no es redondeo de cantidades)
const EPS = 1e-9

// Origen elegido por el manager para un material en la pantalla de suministro
export type SourceMode = 'proposal' | 'neighbours_only' | 'central_only' | 'purchase_all'

// Aplica el origen elegido por el manager a una linea. Nunca supera lo disponible en el
// origen elegido (excedente de los vecinos / stock central): lo que no cabe pasa a compra.
export function applySourceMode(line: SupplyLine, mode: SourceMode): SupplyLine {
  if (mode === 'proposal') return line
  const base = { ...line, fromNeighbours: [] as SupplyLine['fromNeighbours'], fromCentral: 0, toPurchase: line.need }
  if (mode === 'purchase_all') return base
  if (mode === 'central_only') {
    const q = Math.min(line.centralAvailable, line.need)
    const left = q > 0 ? line.need - q : line.need
    return { ...base, fromCentral: q > 0 ? q : 0, toPurchase: left > EPS ? left : 0 }
  }
  let remaining = line.need
  for (const d of line.donors) {
    if (remaining <= EPS) break
    const q = Math.min(d.available, remaining)
    base.fromNeighbours.push({ donor_panelist_id: d.donor_panelist_id, donor_name: d.donor_name, quantity: q })
    remaining -= q
  }
  return { ...base, toPurchase: remaining > EPS ? remaining : 0 }
}

// Convierte las lineas (ya con los cambios de origen) al plan que espera executeSupply.
export function toSupplyPlan(lines: SupplyLine[]): SupplyPlan {
  const plan: SupplyPlan = { fromCentral: [], fromDonor: [], toPurchase: [] }
  lines.forEach(l => {
    if (l.fromCentral > 0) plan.fromCentral.push({ material_id: l.material_id, quantity: l.fromCentral })
    l.fromNeighbours.filter(n => n.quantity > 0).forEach(n => plan.fromDonor.push({
      material_id: l.material_id, quantity: n.quantity, donor_panelist_id: n.donor_panelist_id, donor_name: n.donor_name
    }))
    if (l.toPurchase > 0) plan.toPurchase.push({ material_id: l.material_id, quantity: l.toPurchase })
  })
  return plan
}

export interface PanelistStockRow {
  material_id: string
  name: string
  code: string
  quantity: number
  is_blocking: boolean
}

export interface AffectedSample {
  id: string
  fecha_programada: string
  destination_auto_id: string
  product: string
}

export function useMaterialsTreatment(accountIdOverride?: string) {
  const effectiveAccountId = useEffectiveAccountId()
  const { profile } = useAuth()
  const accountId = accountIdOverride ?? (effectiveAccountId || profile?.account_id)
  const { createShipment, markShipmentSent } = useStockManagement(accountIdOverride)

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

  const resolveSupply = useCallback(async (
    needLines: NeedLine[],
    panelistId: string,
    startDate?: string,
    endDate?: string
  ): Promise<SupplyPlan> => {
    const plan: SupplyPlan = { fromCentral: [], fromDonor: [], toPurchase: [] }
    if (!accountId) return plan

    // Misma ventana que usa recomputeNeed cuando el caller no la especifica (hoy .. hoy+90d)
    const windowStart = startDate || new Date().toISOString().slice(0, 10)
    const windowEnd = endDate || (() => {
      const horizon = new Date()
      horizon.setDate(horizon.getDate() + 90)
      return horizon.toISOString().slice(0, 10)
    })()

    const materialIds = needLines.map(n => n.material_id)
    const { data: centralStocks, error } = await supabase
      .from('material_stocks')
      .select('material_id, quantity')
      .eq('account_id', accountId)
      .in('material_id', materialIds)
    if (error) throw error
    const centralMap: Record<string, number> = {}
    ;(centralStocks || []).forEach((s: any) => { centralMap[s.material_id] = s.quantity })

    // Necesidad propia de cada panelista (para calcular excedente real de los donantes: stock - su propio plan)
    const allRequirements = await calculatePanelistRequirements(accountId, windowStart, windowEnd)
    const ownNeedMap: Record<string, number> = {}
    allRequirements.forEach(r => {
      (r.materials || []).forEach((m: any) => {
        ownNeedMap[`${r.panelist_id}_${m.material_id}`] = m.quantity_needed
      })
    })

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
        // Orden ya resuelto por la RPC (same_city desc, available desc); se conserva tal cual.
        // TODO futuro: preferencia de "tier A" de ciudad requiere catálogo `cities` con tipo/tier.
        const sortedDonors = ((donors || []) as any[]).sort((a, b) => {
          if (a.same_city !== b.same_city) return a.same_city ? -1 : 1
          return (b.available || 0) - (a.available || 0)
        })
        for (const donor of sortedDonors) {
          if (remaining <= 0) break
          const available = donor.available || 0
          const ownNeed = ownNeedMap[`${donor.panelist_id}_${need.material_id}`] || 0
          const usableSurplus = available - ownNeed
          if (usableSurplus <= 0) continue
          const fromDonorQty = Math.min(usableSurplus, remaining)
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

  // v2 (anexo falta de material §3, §8b.5): una sola llamada a calculatePanelistRequirements
  // da la necesidad de TODOS los panelistas en el horizonte. Necesidad del receptor = su linea
  // neta (ya descuenta su stock y lo en camino que no sea de esta incidencia). Donantes =
  // panelistas activos cuyo nodo esta en la misma ciudad (nodes.city_id), con
  // excedente = stock - necesidad bruta propia en el mismo horizonte (> 0), de mayor a menor.
  // Despues el almacen central y el resto a compra. Sin redondeos.
  const resolveSupplyV2 = useCallback(async (
    panelistId: string,
    horizonEnd: string,
    opts?: { excludeIncidentId?: string }
  ): Promise<SupplyLine[]> => {
    if (!accountId) return []
    const today = format(new Date(), 'yyyy-MM-dd')
    const all = await calculatePanelistRequirements(accountId, today, horizonEnd,
      { excludeIncidentId: opts?.excludeIncidentId, includeCovered: true })
    const own = (all.find(r => r.panelist_id === panelistId)?.materials || []).filter(x => x.quantity_needed > 0)
    if (own.length === 0) return []
    const materialIds = own.map(x => x.material_id)

    // Necesidad bruta propia de cada panelista en el horizonte (para el excedente de los donantes)
    const grossMap: Record<string, number> = {}
    all.forEach(r => {
      if (!r.panelist_id) return
      r.materials.forEach(x => {
        const k = `${r.panelist_id}_${x.material_id}`
        grossMap[k] = (grossMap[k] || 0) + Number(x.gross_quantity ?? x.quantity_needed)
      })
    })

    const { data: catalog, error: eCat } = await supabase
      .from('material_catalog').select('id, is_blocking').in('id', materialIds)
    if (eCat) throw eCat
    const blocking: Record<string, boolean> = {}
    ;(catalog || []).forEach((c: any) => { blocking[c.id] = !!c.is_blocking })

    // Almacen central: filas de la cuenta (las mismas que descuenta send_material_shipment),
    // limitadas a ubicacion central/regulador o sin ubicacion. Si hubiera varias filas por
    // material se toma la mayor (send_material_shipment descuenta la cantidad en cada fila).
    const { data: central, error: eCentral } = await supabase
      .from('material_stocks')
      .select('material_id, quantity, location_type')
      .eq('account_id', accountId)
      .in('material_id', materialIds)
      .or('location_type.is.null,location_type.in.(central,regulator)')
    if (eCentral) throw eCentral
    const centralMap: Record<string, number> = {}
    ;(central || []).forEach((r: any) => {
      centralMap[r.material_id] = Math.max(centralMap[r.material_id] ?? 0, Number(r.quantity) || 0)
    })

    // Donantes: panelistas activos de la misma ciudad (por su nodo), distintos del receptor
    let donorList: { id: string; name: string }[] = []
    const { data: recv, error: eRecv } = await supabase
      .from('panelists').select('node:nodes(city_id)').eq('id', panelistId).maybeSingle()
    if (eRecv) throw eRecv
    const cityId: string | null = (recv as any)?.node?.city_id ?? null
    if (cityId) {
      const { data: cityNodes, error: eNodes } = await supabase
        .from('nodes').select('id').eq('account_id', accountId).eq('city_id', cityId)
      if (eNodes) throw eNodes
      const nodeIds = (cityNodes || []).map((n: any) => n.id)
      if (nodeIds.length > 0) {
        const { data: ps, error: ePs } = await supabase
          .from('panelists').select('id, name')
          .eq('account_id', accountId).eq('status', 'active').in('node_id', nodeIds).neq('id', panelistId)
        if (ePs) throw ePs
        donorList = (ps || []).map((p: any) => ({ id: p.id, name: p.name ?? '' }))
      }
    }
    const donorStock: Record<string, number> = {}
    if (donorList.length > 0) {
      const { data: st, error: eSt } = await supabase
        .from('panelist_material_stocks').select('panelist_id, material_id, quantity')
        .eq('account_id', accountId).in('panelist_id', donorList.map(d => d.id)).in('material_id', materialIds)
      if (eSt) throw eSt
      ;(st || []).forEach((r: any) => { donorStock[`${r.panelist_id}_${r.material_id}`] = Number(r.quantity) || 0 })
    }

    return own.map(x => {
      const need = Number(x.quantity_needed)
      const donors = donorList
        .map(d => {
          const k = `${d.id}_${x.material_id}`
          return { donor_panelist_id: d.id, donor_name: d.name, available: (donorStock[k] || 0) - (grossMap[k] || 0) }
        })
        .filter(d => d.available > 0)
        .sort((a, b) => b.available - a.available)
      const centralAvailable = centralMap[x.material_id] || 0
      const line: SupplyLine = {
        material_id: x.material_id, code: x.material_code, name: x.material_name,
        is_blocking: blocking[x.material_id] ?? false, need,
        fromNeighbours: [], fromCentral: 0, toPurchase: 0, donors, centralAvailable
      }
      let remaining = need
      for (const d of donors) {
        if (remaining <= EPS) break
        const q = Math.min(d.available, remaining)
        line.fromNeighbours.push({ donor_panelist_id: d.donor_panelist_id, donor_name: d.donor_name, quantity: q })
        remaining -= q
      }
      if (remaining > EPS && centralAvailable > 0) {
        line.fromCentral = Math.min(centralAvailable, remaining)
        remaining -= line.fromCentral
      }
      line.toPurchase = remaining > EPS ? remaining : 0
      return line
    })
  }, [accountId])

  const executeSupply = useCallback(async (supplyPlan: SupplyPlan, receiverPanelistId: string): Promise<{ centralShipmentId: string | null; donorShipmentIds: string[] }> => {
    let centralShipmentId: string | null = null
    const donorShipmentIds: string[] = []

    // Shipments are created as `pending` and NOT dispatched here (v2): the donor
    // confirms the dispatch by Telegram and the central shipment is marked as sent
    // by the manager from the shipments sheet. The caller links every created
    // shipment to the incident (linkShipmentsToIncident).
    if (supplyPlan.fromCentral.length > 0) {
      const shipment = await createShipment({
        panelist_id: receiverPanelistId,
        items: supplyPlan.fromCentral.map(c => ({ material_id: c.material_id, quantity_sent: c.quantity }))
      }, true)
      centralShipmentId = shipment.id
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
        }, true)
        donorShipmentIds.push(donorShipment.id)
      }
    }

    return { centralShipmentId, donorShipmentIds }
  }, [createShipment])

  const createDisplacementBaja = useCallback(async (incidentId: string, expectedDate: string): Promise<string> => {
    const today = format(new Date(), 'yyyy-MM-dd') // fecha LOCAL: coherente con la validacion de la pantalla
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

  // v2: todos los envios de la incidencia (central y donantes) quedan enlazados a ella.
  // Idempotente: repetirlo con los mismos ids no cambia nada.
  const linkShipmentsToIncident = useCallback(async (incidentId: string, shipmentIds: string[]) => {
    if (shipmentIds.length === 0) return
    const { error } = await supabase.from('material_shipments')
      .update({ panelist_incident_id: incidentId })
      .in('id', shipmentIds)
    if (error) throw error
  }, [])

  const fetchPanelistStock = useCallback(async (panelistId: string): Promise<PanelistStockRow[]> => {
    if (!accountId) return []
    const { data, error } = await supabase
      .from('panelist_material_stocks')
      .select('material_id, quantity, material:material_catalog(name, code, is_blocking)')
      .eq('account_id', accountId)
      .eq('panelist_id', panelistId)
    if (error) throw error
    return ((data || []) as any[]).map(r => ({
      material_id: r.material_id,
      name: r.material?.name ?? '',
      code: r.material?.code ?? '',
      quantity: Number(r.quantity) || 0,
      is_blocking: !!r.material?.is_blocking
    }))
  }, [accountId])

  const zeroAllStock = useCallback(async (panelistId: string): Promise<number> => {
    const rows = await fetchPanelistStock(panelistId)
    let zeroed = 0
    for (const r of rows) {
      if (r.quantity > 0) {
        await reconcileStock(panelistId, r.material_id, 0)
        zeroed++
      }
    }
    return zeroed
  }, [fetchPanelistStock, reconcileStock])

  const daysWithoutStock = useCallback(async (
    panelistNodeId: string,
    from: string,
    to: string,
    blockingMaterialIds: string[]
  ): Promise<{ businessDays: number; samples: AffectedSample[] }> => {
    if (to < from) return { businessDays: 0, samples: [] }
    const businessDays = eachDayOfInterval({ start: new Date(`${from}T00:00:00`), end: new Date(`${to}T00:00:00`) })
      .filter(d => !isWeekend(d)).length
    if (blockingMaterialIds.length === 0) return { businessDays, samples: [] }

    const { data: pm, error: e1 } = await supabase
      .from('product_materials')
      .select('product_id')
      .in('material_id', blockingMaterialIds)
    if (e1) throw e1
    const productIds = Array.from(new Set((pm || []).map((r: any) => r.product_id)))
    if (productIds.length === 0) return { businessDays, samples: [] }

    const { data, error: e2 } = await supabase
      .from('allocation_plan_details')
      .select(`id, fecha_programada,
        destination_node:nodes!allocation_plan_details_destination_node_id_fkey(auto_id),
        plan:allocation_plans!inner(product_id, product:products(description))`)
      .eq('origin_node_id', panelistNodeId)
      .in('status', ['pending', 'notified'])
      .gte('fecha_programada', from)
      .lte('fecha_programada', to)
      .in('plan.product_id', productIds)
      .order('fecha_programada')
    if (e2) throw e2
    const samples = ((data || []) as any[]).map(r => ({
      id: r.id,
      fecha_programada: r.fecha_programada,
      destination_auto_id: r.destination_node?.auto_id ?? '',
      product: r.plan?.product?.description ?? ''
    }))
    return { businessDays, samples }
  }, [])

  return {
    reconcileStock,
    fetchPanelistStock,
    zeroAllStock,
    daysWithoutStock,
    recomputeNeed,
    resolveSupply,
    resolveSupplyV2,
    executeSupply,
    createDisplacementBaja,
    linkShipmentToIncident,
    linkShipmentsToIncident,
    markShipmentSent
  }
}
