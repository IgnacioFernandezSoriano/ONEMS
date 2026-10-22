import { useCallback } from 'react'
import { addDays, eachDayOfInterval, format, isWeekend, parseISO } from 'date-fns'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/contexts/AuthContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { useStockManagement } from '@/hooks/useStockManagement'
import { calculatePanelistRequirements } from '@/lib/materialCalculator'

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
// Inicio del calculo de necesidad: incluye los envios pendientes atrasados (ver resolveSupplyV2)
const OVERDUE_FROM = '2000-01-01'

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

// Linea a comprar guardada al confirmar el suministro (payload.purchase_lines)
export interface PurchaseLine { material_id: string; code: string; name: string; quantity: number }

export function readPurchaseLines(payload: Record<string, any> | null | undefined): PurchaseLine[] {
  const raw = payload?.purchase_lines
  if (!Array.isArray(raw)) return []
  return raw
    .filter((r: any) => r && typeof r === 'object' && Number(r.quantity) > 0)
    .map((r: any) => ({ material_id: String(r.material_id ?? ''), code: String(r.code ?? ''), name: String(r.name ?? ''), quantity: Number(r.quantity) }))
}

export interface ExistingIncidentShipments {
  centralShipmentId: string | null
  donorShipmentIds: Record<string, string> // source_panelist_id -> shipment id
  purchaseShipmentId: string | null
}

// Nota que distingue el envio central->panelista de lo COMPRADO (sale cuando llega la compra) del envio central normal
export const PURCHASE_SHIPMENT_NOTE = 'purchase'

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
  const { createShipment } = useStockManagement(accountIdOverride)

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
    // Desde el principio: los envios pendientes/notificados con fecha pasada siguen sin enviar (el bot se los
    // sigue mostrando al panelista), asi que tambien necesitan material. Solo el final del horizonte limita.
    const all = await calculatePanelistRequirements(accountId, OVERDUE_FROM, horizonEnd,
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

    // Stock ya comprometido: el stock solo se descuenta al enviar (send_material_shipment), asi que
    // lo que ya esta en envios `pending` desde el central o desde un donante no esta disponible.
    // Se excluyen los envios de ESTA incidencia (recalcular tras confirmar no resta dos veces).
    const committed: Record<string, number> = {} // `${source_panelist_id || 'central'}_${material_id}`
    let pendQ = supabase
      .from('material_shipments')
      .select('source_panelist_id, panelist_incident_id, items:material_shipment_items(material_id, quantity_sent)')
      .eq('account_id', accountId)
      .eq('status', 'pending')
    pendQ = donorList.length > 0
      ? pendQ.or(`source_panelist_id.is.null,source_panelist_id.in.(${donorList.map(d => d.id).join(',')})`)
      : pendQ.is('source_panelist_id', null)
    const { data: pend, error: ePend } = await pendQ
    if (ePend) throw ePend
    ;((pend || []) as any[]).forEach(sh => {
      if (opts?.excludeIncidentId && sh.panelist_incident_id === opts.excludeIncidentId) return
      ;(sh.items || []).forEach((it: any) => {
        if (!materialIds.includes(it.material_id)) return
        const k = `${sh.source_panelist_id || 'central'}_${it.material_id}`
        committed[k] = (committed[k] || 0) + (Number(it.quantity_sent) || 0)
      })
    })

    return own.map(x => {
      const need = Number(x.quantity_needed)
      const donors = donorList
        .map(d => {
          const k = `${d.id}_${x.material_id}`
          const available = (donorStock[k] || 0) - (committed[k] || 0) - (grossMap[k] || 0)
          return { donor_panelist_id: d.id, donor_name: d.name, available }
        })
        .filter(d => d.available > 0)
        .sort((a, b) => b.available - a.available)
      const centralAvailable = Math.max(0, (centralMap[x.material_id] || 0) - (committed[`central_${x.material_id}`] || 0))
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

  // Envios ya creados para la incidencia (la BD es la fuente de idempotencia): central =
  // source_panelist_id nulo; compra = central con la nota PURCHASE_SHIPMENT_NOTE; donantes por
  // source_panelist_id. Se ignoran los cancelados.
  const fetchIncidentShipments = useCallback(async (incidentId: string): Promise<ExistingIncidentShipments> => {
    const out: ExistingIncidentShipments = { centralShipmentId: null, donorShipmentIds: {}, purchaseShipmentId: null }
    if (!accountId) return out
    const { data, error } = await supabase.from('material_shipments')
      .select('id, source_panelist_id, notes, created_at')
      .eq('panelist_incident_id', incidentId)
      .eq('account_id', accountId)
      .neq('status', 'cancelled')
      .order('created_at')
    if (error) throw error
    ;((data || []) as any[]).forEach(r => {
      if (r.source_panelist_id) {
        if (!out.donorShipmentIds[r.source_panelist_id]) out.donorShipmentIds[r.source_panelist_id] = r.id
      } else if (r.notes === PURCHASE_SHIPMENT_NOTE) {
        if (!out.purchaseShipmentId) out.purchaseShipmentId = r.id
      } else if (!out.centralShipmentId) out.centralShipmentId = r.id
    })
    return out
  }, [accountId])

  const executeSupply = useCallback(async (
    supplyPlan: SupplyPlan,
    receiverPanelistId: string,
    expectedDate?: string,
    opts?: { incidentId?: string; existing?: ExistingIncidentShipments; purchaseExpectedDate?: string }
  ): Promise<{ centralShipmentId: string | null; donorShipmentIds: string[]; purchaseShipmentId: string | null }> => {
    // Lo ya existente en BD para la incidencia se reutiliza: solo se crean los origenes que faltan
    // (un reintento tras un fallo parcial no duplica el central, la compra ni los donantes).
    const existing = opts?.existing ?? { centralShipmentId: null, donorShipmentIds: {}, purchaseShipmentId: null }
    let centralShipmentId: string | null = existing.centralShipmentId
    let purchaseShipmentId: string | null = existing.purchaseShipmentId
    const donorIds: Record<string, string> = { ...existing.donorShipmentIds }

    // Shipments are created as `pending` and NOT dispatched here (v2): the donor
    // confirms the dispatch by Telegram and the central shipment is marked as sent
    // by the manager from the shipments sheet. With opts.incidentId every shipment is
    // linked to the incident on its own INSERT.
    if (supplyPlan.fromCentral.length > 0 && !centralShipmentId) {
      const shipment = await createShipment({
        panelist_id: receiverPanelistId,
        items: supplyPlan.fromCentral.map(c => ({ material_id: c.material_id, quantity_sent: c.quantity })),
        expected_date: expectedDate,
        panelist_incident_id: opts?.incidentId
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
        if (donorIds[donorPanelistId]) continue
        const donorShipment = await createShipment({
          panelist_id: receiverPanelistId,
          items: byDonor[donorPanelistId],
          source_panelist_id: donorPanelistId,
          expected_date: expectedDate,
          panelist_incident_id: opts?.incidentId
        }, true)
        donorIds[donorPanelistId] = donorShipment.id
      }
    }

    // Lo que se compra tambien hay que enviarselo: envio central->panelista aparte, con la llegada prevista
    // de la compra. Queda `pending` en Stock management -> Shipments y se envia cuando llega la compra.
    if (supplyPlan.toPurchase.length > 0 && !purchaseShipmentId) {
      const shipment = await createShipment({
        panelist_id: receiverPanelistId,
        items: supplyPlan.toPurchase.map(c => ({ material_id: c.material_id, quantity_sent: c.quantity })),
        expected_date: opts?.purchaseExpectedDate ?? expectedDate,
        notes: PURCHASE_SHIPMENT_NOTE,
        panelist_incident_id: opts?.incidentId
      }, true)
      purchaseShipmentId = shipment.id
    }

    return { centralShipmentId, donorShipmentIds: Object.values(donorIds), purchaseShipmentId }
  }, [createShipment])

  // Baja por materiales [hoy, expectedDate] SOLO en los dias que no cubre ya otra baja activa del panelista
  // (vacaciones, etc.: la BD no admite bajas solapadas y esos envios ya se replanifican por la otra baja).
  // Una baja por tramo libre; la incidencia queda enlazada a la primera. null = no queda ningun dia libre.
  const createDisplacementBaja = useCallback(async (incidentId: string, expectedDate: string): Promise<string | null> => {
    const today = format(new Date(), 'yyyy-MM-dd') // fecha LOCAL: coherente con la validacion de la pantalla
    const { data: inc, error: e0 } = await supabase.from('panelist_incident').select('panelist_id').eq('id', incidentId).single()
    if (e0) throw e0
    const { data: busy, error: e1 } = await supabase.from('panelist_unavailability')
      .select('start_date, end_date')
      .eq('panelist_id', inc.panelist_id).eq('status', 'active')
      .lte('start_date', expectedDate).gte('end_date', today)
      .order('start_date')
    if (e1) throw e1
    const day = (d: string, n: number) => format(addDays(parseISO(d), n), 'yyyy-MM-dd')
    const gaps: { start: string; end: string }[] = []
    let cursor = today
    for (const b of busy ?? []) {
      if (b.start_date > cursor) gaps.push({ start: cursor, end: day(b.start_date, -1) < expectedDate ? day(b.start_date, -1) : expectedDate })
      if (b.end_date >= cursor) cursor = day(b.end_date, 1)
      if (cursor > expectedDate) break
    }
    if (cursor <= expectedDate) gaps.push({ start: cursor, end: expectedDate })
    if (gaps.length === 0) return null
    // Del ultimo tramo al primero: la RPC enlaza la incidencia a la ultima baja creada -> queda la primera
    let first: string | null = null
    for (const g of [...gaps].reverse()) {
      const { data, error } = await supabase.rpc('create_unavailability_from_incident', {
        p_incident_id: incidentId, p_start: g.start, p_end: g.end, p_reason: 'materials'
      })
      if (error) throw error
      first = data as string
    }
    return first
  }, [])

  // Lo que queda a compra se registra como REQUERIMIENTO DE COMPRA pendiente en Stock management -> Material
  // Requirements (material_requirements_periods, status 'pending', periodo [hoy, llegada prevista]): el gestor
  // confirma alli las cantidades finales y lo marca como pedido. Idempotente: las filas llevan la nota de la
  // incidencia y un reintento no duplica. ("Calcular" de esa pestana suma las pendientes del mismo material.)
  const requestPurchaseLines = useCallback(async (incidentId: string, lines: PurchaseLine[], arrival: string) => {
    if (!accountId) return
    const start = format(new Date(), 'yyyy-MM-dd')
    const note = `Incident ${incidentId}`
    for (const l of lines) {
      const qty = Number(l.quantity)
      if (!l.material_id || !(qty > 0)) continue
      const { data: mine, error: e0 } = await supabase.from('material_requirements_periods').select('id')
        .eq('account_id', accountId).eq('material_id', l.material_id).eq('notes', note).limit(1)
      if (e0) throw e0
      if (mine && mine.length > 0) continue
      // Clave unica (cuenta, periodo, material): si ya hay fila con el mismo periodo se le suma la necesidad
      const { data: same, error: e1 } = await supabase.from('material_requirements_periods')
        .select('id, quantity_needed')
        .eq('account_id', accountId).eq('material_id', l.material_id).eq('period_start', start).eq('period_end', arrival)
        .maybeSingle()
      if (e1) throw e1
      const { error: e2 } = same
        ? await supabase.from('material_requirements_periods').update({
            quantity_needed: Number(same.quantity_needed || 0) + qty, notes: note, updated_at: new Date().toISOString()
          }).eq('id', same.id)
        : await supabase.from('material_requirements_periods').insert({
            account_id: accountId, material_id: l.material_id, period_start: start, period_end: arrival,
            quantity_needed: qty, quantity_ordered: 0, quantity_received: 0, status: 'pending', plans_count: 0, notes: note
          })
      if (e2) throw e2
    }
  }, [accountId])

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
    resolveSupplyV2,
    executeSupply,
    fetchIncidentShipments,
    createDisplacementBaja,
    requestPurchaseLines,
    linkShipmentToIncident,
    linkShipmentsToIncident
  }
}
