import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'
import { useEffectiveAccountId } from './useEffectiveAccountId'

export interface MaterialStock {
  id: string
  account_id: string
  material_id: string
  quantity: number
  min_stock: number | null
  max_stock: number | null
  last_updated: string | null
  created_at: string
  updated_at: string
  material?: {
    code: string
    name: string
    unit_measure: string
  }
}

export interface PanelistMaterialStock {
  id: string
  account_id: string
  panelist_id: string
  material_id: string
  quantity: number
  last_updated: string | null
  created_at: string
  updated_at: string
  panelist?: {
    name: string
    panelist_code: string
  }
  material?: {
    code: string
    name: string
    unit_measure: string
  }
}

export interface MaterialMovement {
  id: string
  account_id: string
  material_id: string
  movement_type: string
  quantity: number
  from_location: string | null
  to_location: string | null
  reference_id: string | null
  notes: string | null
  created_by: string | null
  created_at: string
  material?: {
    code: string
    name: string
    unit_measure: string
  }
}

export interface MaterialShipment {
  id: string
  account_id: string
  shipment_number: string | null
  panelist_id: string
  status: string
  shipment_date: string | null
  expected_date: string | null
  received_date: string | null
  tracking_number: string | null
  total_items: number | null
  notes: string | null
  created_by: string | null
  created_at: string
  updated_at: string
  // Envio de una incidencia de materiales (no se unifica ni se borra desde Stock)
  panelist_incident_id?: string | null
  source_panelist_id?: string | null
  panelist?: {
    name: string
    panelist_code: string
  }
  items?: MaterialShipmentItem[]
}

export interface MaterialShipmentItem {
  id: string
  account_id: string
  material_shipment_id: string
  material_id: string
  quantity_sent: number
  quantity_received: number | null
  notes: string | null
  created_at: string
  updated_at: string
  material?: {
    code: string
    name: string
    unit_measure: string
  }
}

export interface StockSettings {
  id: string
  account_id: string
  stock_control_enabled: boolean
  auto_generate_purchase_orders: boolean
  auto_generate_shipments: boolean
  purchase_lead_time_days: number | null
  shipment_lead_time_days: number | null
  created_at: string
  updated_at: string
}

// Error con clave i18n: la pantalla lo traduce (el hook no tiene acceso a t()).
export const INCIDENT_SHIPMENT_LOCKED = 'stock.cannot_delete_incident_shipment'
function incidentShipmentLocked(): Error {
  const e: any = new Error(INCIDENT_SHIPMENT_LOCKED)
  e.i18nKey = INCIDENT_SHIPMENT_LOCKED
  return e
}

export function useStockManagement(accountIdOverride?: string) {
  const effectiveAccountId = useEffectiveAccountId()
  const { profile } = useAuth()
  // Use effectiveAccountId if available, otherwise fall back to profile.account_id
  const accountId = accountIdOverride ?? (effectiveAccountId || profile?.account_id)

  const [regulatorStocks, setRegulatorStocks] = useState<MaterialStock[]>([])
  const [panelistStocks, setPanelistStocks] = useState<PanelistMaterialStock[]>([])
  const [movements, setMovements] = useState<MaterialMovement[]>([])
  const [shipments, setShipments] = useState<MaterialShipment[]>([])
  const [settings, setSettings] = useState<StockSettings | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (accountId) {
      loadData()
    }
  }, [accountId, effectiveAccountId])

  const loadData = async () => {
    try {
      setLoading(true)
      setError(null)

      // Load regulator stocks
      const { data: stocksData, error: stocksError } = await supabase
        .from('material_stocks')
        .select(`
          *,
          material:material_catalog(code, name, unit_measure)
        `)
        .eq('account_id', accountId)
        .order('created_at', { ascending: false })

      if (stocksError) throw stocksError

      // Load panelist stocks
      const { data: panelistStocksData, error: panelistStocksError } = await supabase
        .from('panelist_material_stocks')
        .select(`
          *,
          panelist:panelists(name, panelist_code),
          material:material_catalog(code, name, unit_measure)
        `)
        .eq('account_id', accountId)
        .order('created_at', { ascending: false })

      if (panelistStocksError) throw panelistStocksError

      // Load movements
      const { data: movementsData, error: movementsError } = await supabase
        .from('material_movements')
        .select(`
          *,
          material:material_catalog(code, name, unit_measure)
        `)
        .eq('account_id', accountId)
        .order('created_at', { ascending: false })
        .limit(100)

      if (movementsError) throw movementsError

      // Load shipments with items
      const { data: shipmentsData, error: shipmentsError } = await supabase
        .from('material_shipments')
        .select(`
          *,
          panelist:panelists!material_shipments_panelist_id_fkey(name, panelist_code)
        `)
        .eq('account_id', accountId)
        .order('created_at', { ascending: false })

      if (shipmentsError) throw shipmentsError

      // Load shipment items for each shipment
      if (shipmentsData) {
        const shipmentsWithItems = await Promise.all(
          shipmentsData.map(async (shipment) => {
            const { data: items } = await supabase
              .from('material_shipment_items')
              .select(`
                *,
                material:material_catalog(code, name, unit_measure)
              `)
              .eq('material_shipment_id', shipment.id)

            return { ...shipment, items: items || [] }
          })
        )
        setShipments(shipmentsWithItems)
      }

      // Load settings
      const { data: settingsData, error: settingsError } = await supabase
        .from('stock_settings')
        .select('*')
        .eq('account_id', accountId)
        .single()

      if (settingsError && settingsError.code !== 'PGRST116') {
        // PGRST116 = no rows returned, which is OK
        throw settingsError
      }

      setRegulatorStocks(stocksData || [])
      setPanelistStocks(panelistStocksData || [])
      setMovements(movementsData || [])
      setSettings(settingsData)
    } catch (err: any) {
      console.error('Error loading stock management data:', err)
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const updateRegulatorStock = async (materialId: string, quantity: number, minStock?: number, maxStock?: number) => {
    try {
      const { data, error } = await supabase
        .from('material_stocks')
        .upsert({
          account_id: accountId,
          material_id: materialId,
          quantity,
          min_stock: minStock,
          max_stock: maxStock,
          last_updated: new Date().toISOString()
        }, {
          onConflict: 'account_id,material_id'
        })
        .select()

      if (error) throw error

      await loadData()
      return data
    } catch (err: any) {
      console.error('Error updating regulator stock:', err)
      throw err
    }
  }

  const createMovement = async (movement: {
    material_id: string
    movement_type: string
    quantity: number
    from_location?: string
    to_location?: string
    reference_id?: string
    notes?: string
  }) => {
    try {
      const { data, error } = await supabase
        .from('material_movements')
        .insert({
          account_id: accountId,
          created_by: profile?.id,
          ...movement
        })
        .select()

      if (error) throw error

      await loadData()
      return data
    } catch (err: any) {
      console.error('Error creating movement:', err)
      throw err
    }
  }

  const createShipment = async (shipment: {
    panelist_id: string
    items: { material_id: string; quantity_sent: number }[]
    shipment_date?: string
    expected_date?: string
    tracking_number?: string
    notes?: string
    source_panelist_id?: string
    panelist_incident_id?: string
  }, skipUnify: boolean = false) => {
    try {
      // Check for existing pending shipments for this panelist.
      // Solo se unifican los envios rutinarios desde el central: los de una incidencia
      // (panelist_incident_id) o desde un donante (source_panelist_id) NUNCA se tocan.
      let existingShipments: { id: string; expected_date: string | null; items: any[] | null }[] | null = null
      if (!skipUnify) {
        const { data: ex, error: exError } = await supabase
          .from('material_shipments')
          .select(`
            id,
            expected_date,
            items:material_shipment_items(material_id, quantity_sent)
          `)
          .eq('account_id', accountId)
          .eq('panelist_id', shipment.panelist_id)
          .eq('status', 'pending')
          .is('panelist_incident_id', null)
          .is('source_panelist_id', null)
        if (exError) throw exError
        existingShipments = ex as any
      }

      // Group existing items by material
      const existingItemsMap: Record<string, { shipment_id: string; quantity: number }> = {}
      if (existingShipments && existingShipments.length > 0) {
        existingShipments.forEach(s => {
          if (s.items) {
            s.items.forEach((item: any) => {
              if (!existingItemsMap[item.material_id]) {
                existingItemsMap[item.material_id] = { shipment_id: s.id, quantity: 0 }
              }
              existingItemsMap[item.material_id].quantity += item.quantity_sent
            })
          }
        })
      }

      // Unify: Delete all existing pending shipments for this panelist
      // (skipped entirely when skipUnify is true, so treatment shipments
      // never absorb unrelated routine pending shipments)
      if (existingShipments && existingShipments.length > 0) {
        const shipmentIds = existingShipments.map(s => s.id)

        // Si algun borrado falla se para aqui: no se crea el envio unificado (evita duplicar cantidades)
        const { error: delItemsError } = await supabase
          .from('material_shipment_items')
          .delete()
          .in('material_shipment_id', shipmentIds)
        if (delItemsError) throw delItemsError

        const { error: delShipError } = await supabase
          .from('material_shipments')
          .delete()
          .in('id', shipmentIds)
        if (delShipError) throw delShipError
      }

      // Merge new items with existing
      const mergedItems: Record<string, number> = {}

      // Add existing quantities
      Object.keys(existingItemsMap).forEach(materialId => {
        mergedItems[materialId] = existingItemsMap[materialId].quantity
      })

      // Add new quantities
      shipment.items.forEach(item => {
        mergedItems[item.material_id] = (mergedItems[item.material_id] || 0) + item.quantity_sent
      })

      // Create unified shipment
      const { data: shipmentData, error: shipmentError } = await supabase
        .from('material_shipments')
        .insert({
          account_id: accountId,
          panelist_id: shipment.panelist_id,
          status: 'pending',
          shipment_date: shipment.shipment_date,
          expected_date: shipment.expected_date || new Date().toISOString(),
          tracking_number: shipment.tracking_number,
          total_items: Object.keys(mergedItems).length,
          notes: shipment.notes,
          source_panelist_id: shipment.source_panelist_id,
          // Enlace a la incidencia desde la creacion (fuente de idempotencia de los reintentos)
          panelist_incident_id: shipment.panelist_incident_id,
          created_by: profile?.id
        })
        .select()
        .single()

      if (shipmentError) throw shipmentError

      // Create unified shipment items
      const itemsToInsert = Object.entries(mergedItems).map(([material_id, quantity]) => ({
        account_id: accountId,
        material_shipment_id: shipmentData.id,
        material_id,
        quantity_sent: quantity
      }))

      const { error: itemsError } = await supabase
        .from('material_shipment_items')
        .insert(itemsToInsert)

      if (itemsError) {
        // No dejar una cabecera sin lineas (mejor esfuerzo) y propagar el error original
        const { error: cleanupError } = await supabase.from('material_shipments').delete().eq('id', shipmentData.id)
        if (cleanupError) console.error('Error removing orphan shipment header:', cleanupError)
        throw itemsError
      }

      await loadData()
      return shipmentData
    } catch (err: any) {
      console.error('Error creating shipment:', err)
      throw err
    }
  }

  const updateShipmentStatus = async (shipmentId: string, status: string, receivedDate?: string) => {
    try {
      // 'sent' and 'delivered' transitions now go through the dedicated RPCs
      // (markShipmentSent / markShipmentReceived), which do the stock
      // crediting/decrementing server-side. This function only remains for
      // trivial status/date updates that are NOT part of the reception lifecycle.
      if (status === 'sent') {
        await markShipmentSent(shipmentId)
        return
      }

      if (status === 'delivered') {
        await markShipmentReceived(shipmentId)
        return
      }

      const updateData: any = { status }

      if (receivedDate) {
        updateData.received_date = receivedDate
      }

      const { error } = await supabase
        .from('material_shipments')
        .update(updateData)
        .eq('id', shipmentId)

      if (error) throw error

      await loadData()
    } catch (err: any) {
      console.error('Error updating shipment status:', err)
      throw err
    }
  }

  const markShipmentSent = async (shipmentId: string) => {
    try {
      const { error } = await supabase.rpc('send_material_shipment', { p_shipment_id: shipmentId })
      if (error) throw error
      await loadData()
    } catch (err: any) {
      console.error('Error marking shipment as sent:', err)
      throw err
    }
  }

  const markShipmentReceived = async (shipmentId: string) => {
    try {
      const { error } = await supabase.rpc('receive_material_shipment', { p_shipment_id: shipmentId })
      if (error) throw error
      await loadData()
    } catch (err: any) {
      console.error('Error marking shipment as received:', err)
      throw err
    }
  }

  const confirmShipment = async (
    shipmentId: string,
    confirmedItems: Array<{ id: string; material_id: string; quantity_sent: number }>,
    sentDate: string
  ) => {
    try {
      // 1. Get shipment details
      const { data: shipment, error: fetchError } = await supabase
        .from('material_shipments')
        .select(`
          *,
          items:material_shipment_items(*),
          panelist:panelists!material_shipments_panelist_id_fkey(name, panelist_code)
        `)
        .eq('id', shipmentId)
        .single()

      if (fetchError) throw fetchError

      // 2. Identify removed items
      const confirmedItemIds = new Set(confirmedItems.map(i => i.id))
      const removedItems = (shipment.items || []).filter((item: any) => !confirmedItemIds.has(item.id))

      // Un envio de incidencia no se parte desde Stock (sus lineas saldrian de la incidencia)
      if (shipment.panelist_incident_id && removedItems.length > 0) throw incidentShipmentLocked()

      // 3. Update quantities of confirmed items in database
      for (const confirmedItem of confirmedItems) {
        await supabase
          .from('material_shipment_items')
          .update({ quantity_sent: confirmedItem.quantity_sent })
          .eq('id', confirmedItem.id)
      }

      // 4. If there are removed items, create a new pending shipment for them
      //    and drop them from the current shipment. Stock crediting/decrementing
      //    is NOT done here anymore: it happens server-side when the shipment is
      //    actually sent/received via markShipmentSent/markShipmentReceived.
      if (removedItems.length > 0) {
        for (const removedItem of removedItems) {
          const { error: delError } = await supabase
            .from('material_shipment_items')
            .delete()
            .eq('id', removedItem.id)
          if (delError) throw delError
        }

        const { data: newShipment, error: newShipmentError } = await supabase
          .from('material_shipments')
          .insert({
            account_id: accountId,
            panelist_id: shipment.panelist_id,
            status: 'pending',
            expected_date: shipment.expected_date,
            notes: `Materials removed from shipment ${shipmentId.substring(0, 8)}`,
            created_by: profile?.id
          })
          .select()
          .single()

        if (newShipmentError) throw newShipmentError

        // Add removed items to new shipment
        for (const removedItem of removedItems) {
          await supabase
            .from('material_shipment_items')
            .insert({
              account_id: accountId,
              material_shipment_id: newShipment.id,
              material_id: removedItem.material_id,
              quantity_sent: removedItem.quantity_sent
            })
        }
      }

      // 5. Dispatch the (remaining) shipment: decrement source stock and
      //    transition status -> sent server-side via the send RPC.
      const { error: sendError } = await supabase.rpc('send_material_shipment', { p_shipment_id: shipmentId })
      if (sendError) throw sendError

      await loadData()
    } catch (err: any) {
      console.error('Error confirming shipment:', err)
      throw err
    }
  }

  const updateSettings = async (newSettings: Partial<StockSettings>) => {
    try {
      const { data, error } = await supabase
        .from('stock_settings')
        .upsert({
          account_id: accountId,
          ...newSettings
        }, {
          onConflict: 'account_id'
        })
        .select()

      if (error) throw error

      await loadData()
      return data
    } catch (err: any) {
      console.error('Error updating settings:', err)
      throw err
    }
  }

  const updateShipmentItem = async (itemId: string, quantitySent: number) => {
    try {
      const { error } = await supabase
        .from('material_shipment_items')
        .update({
          quantity_sent: quantitySent,
          updated_at: new Date().toISOString()
        })
        .eq('id', itemId)

      if (error) throw error

      await loadData()
    } catch (err: any) {
      console.error('Error updating shipment item:', err)
      throw err
    }
  }

  const deleteShipment = async (shipmentId: string) => {
    try {
      // Los envios de una incidencia de materiales no se borran desde Stock
      const { data: sh, error: fetchError } = await supabase
        .from('material_shipments')
        .select('panelist_incident_id')
        .eq('id', shipmentId)
        .maybeSingle()
      if (fetchError) throw fetchError
      if (sh?.panelist_incident_id) throw incidentShipmentLocked()

      // Delete shipment items first (foreign key constraint)
      const { error: itemsError } = await supabase
        .from('material_shipment_items')
        .delete()
        .eq('material_shipment_id', shipmentId)

      if (itemsError) throw itemsError

      // Delete shipment
      const { error: shipmentError } = await supabase
        .from('material_shipments')
        .delete()
        .eq('id', shipmentId)

      if (shipmentError) throw shipmentError

      await loadData()
    } catch (err: any) {
      console.error('Error deleting shipment:', err)
      throw err
    }
  }

  return {
    regulatorStocks,
    panelistStocks,
    movements,
    shipments,
    settings,
    loading,
    error,
    updateRegulatorStock,
    createMovement,
    createShipment,
    updateShipmentStatus,
    markShipmentSent,
    markShipmentReceived,
    confirmShipment,
    updateShipmentItem,
    deleteShipment,
    updateSettings,
    reload: loadData
  }
}
