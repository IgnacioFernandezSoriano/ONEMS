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

export function useStockManagement() {
  const effectiveAccountId = useEffectiveAccountId()
  const { profile } = useAuth()
  // Use effectiveAccountId if available, otherwise fall back to profile.account_id
  const accountId = effectiveAccountId || profile?.account_id

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
          panelist:panelists(name, panelist_code)
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
  }) => {
    try {
      // Check for existing pending shipments for this panelist
      const { data: existingShipments } = await supabase
        .from('material_shipments')
        .select(`
          id,
          expected_date,
          items:material_shipment_items(material_id, quantity_sent)
        `)
        .eq('account_id', accountId)
        .eq('panelist_id', shipment.panelist_id)
        .eq('status', 'pending')

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
      if (existingShipments && existingShipments.length > 0) {
        const shipmentIds = existingShipments.map(s => s.id)
        
        await supabase
          .from('material_shipment_items')
          .delete()
          .in('material_shipment_id', shipmentIds)
        
        await supabase
          .from('material_shipments')
          .delete()
          .in('id', shipmentIds)
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

      if (itemsError) throw itemsError

      await loadData()
      return shipmentData
    } catch (err: any) {
      console.error('Error creating shipment:', err)
      throw err
    }
  }

  const updateShipmentStatus = async (shipmentId: string, status: string, receivedDate?: string) => {
    try {
      const updateData: any = { status }
      
      if (status === 'sent' && !receivedDate) {
        updateData.shipment_date = new Date().toISOString()
      }
      
      if (status === 'delivered' && receivedDate) {
        updateData.received_date = receivedDate
      }

      // Get shipment details with items and panelist info
      const { data: shipment, error: fetchError } = await supabase
        .from('material_shipments')
        .select(`
          *,
          items:material_shipment_items(*),
          panelist:panelists(name, panelist_code)
        `)
        .eq('id', shipmentId)
        .single()

      if (fetchError) throw fetchError

      // Update shipment status
      const { error } = await supabase
        .from('material_shipments')
        .update(updateData)
        .eq('id', shipmentId)

      if (error) throw error

      // If changing to 'sent', update stocks, create movements, and DELETE the shipment
      if (status === 'sent' && shipment.items) {
        for (const item of shipment.items) {
          // 1. Decrement regulator stock
          const { data: currentRegulatorStock } = await supabase
            .from('material_stocks')
            .select('quantity')
            .eq('account_id', accountId)
            .eq('material_id', item.material_id)
            .single()

          if (currentRegulatorStock) {
            const newRegulatorQuantity = Math.max(0, currentRegulatorStock.quantity - item.quantity_sent)
            await supabase
              .from('material_stocks')
              .update({ 
                quantity: newRegulatorQuantity,
                last_updated: new Date().toISOString()
              })
              .eq('account_id', accountId)
              .eq('material_id', item.material_id)
          }

          // 2. Increment panelist stock
          const { data: currentPanelistStock } = await supabase
            .from('panelist_material_stocks')
            .select('quantity')
            .eq('account_id', accountId)
            .eq('panelist_id', shipment.panelist_id)
            .eq('material_id', item.material_id)
            .single()

          const newPanelistQuantity = (currentPanelistStock?.quantity || 0) + item.quantity_sent
          await supabase
            .from('panelist_material_stocks')
            .upsert({
              account_id: accountId,
              panelist_id: shipment.panelist_id,
              material_id: item.material_id,
              quantity: newPanelistQuantity,
              last_updated: new Date().toISOString()
            }, {
              onConflict: 'account_id,panelist_id,material_id'
            })

          // 3. Create movement OUT from regulator
          await supabase
            .from('material_movements')
            .insert({
              account_id: accountId,
              material_id: item.material_id,
              movement_type: 'dispatch',
              quantity: item.quantity_sent,
              from_location: 'Regulator',
              to_location: shipment.panelist?.name || 'Unknown Panelist',
              reference_id: shipmentId,
              notes: `Shipment to ${shipment.panelist?.name || 'Unknown Panelist'}`,
              created_by: profile?.id
            })

          // 4. Create movement IN to panelist
          await supabase
            .from('material_movements')
            .insert({
              account_id: accountId,
              material_id: item.material_id,
              movement_type: 'receipt',
              quantity: item.quantity_sent,
              from_location: 'Regulator',
              to_location: shipment.panelist?.name || 'Unknown Panelist',
              reference_id: shipmentId,
              notes: `Received by ${shipment.panelist?.name || 'Unknown Panelist'}`,
              created_by: profile?.id
            })
        }

        // 5. DELETE the shipment after confirming (status = 'sent')
        await supabase
          .from('material_shipment_items')
          .delete()
          .eq('shipment_id', shipmentId)

        await supabase
          .from('material_shipments')
          .delete()
          .eq('id', shipmentId)
      }

      await loadData()
    } catch (err: any) {
      console.error('Error updating shipment status:', err)
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
          panelist:panelists(name, panelist_code)
        `)
        .eq('id', shipmentId)
        .single()

      if (fetchError) throw fetchError

      // 2. Identify removed items
      const confirmedItemIds = new Set(confirmedItems.map(i => i.id))
      const removedItems = (shipment.items || []).filter((item: any) => !confirmedItemIds.has(item.id))

      // 3. Update quantities of confirmed items in database
      for (const confirmedItem of confirmedItems) {
        await supabase
          .from('material_shipment_items')
          .update({ quantity_sent: confirmedItem.quantity_sent })
          .eq('id', confirmedItem.id)
      }

      // 4. Process confirmed items (send them)
      for (const confirmedItem of confirmedItems) {
        // Get current regulator stock
        const { data: currentRegulatorStock } = await supabase
          .from('material_stocks')
          .select('quantity, material_catalog(code, name, unit_measure)')
          .eq('account_id', accountId)
          .eq('material_id', confirmedItem.material_id)
          .single()

        const stockAvailable = currentRegulatorStock?.quantity || 0
        const hasStockIssue = confirmedItem.quantity_sent > stockAvailable

        // Decrement regulator stock
        if (currentRegulatorStock) {
          const newRegulatorQuantity = Math.max(0, stockAvailable - confirmedItem.quantity_sent)
          await supabase
            .from('material_stocks')
            .update({
              quantity: newRegulatorQuantity,
              last_updated: new Date().toISOString()
            })
            .eq('account_id', accountId)
            .eq('material_id', confirmedItem.material_id)
        }

        // Increment panelist stock
        const { data: currentPanelistStock } = await supabase
          .from('panelist_material_stocks')
          .select('quantity')
          .eq('account_id', accountId)
          .eq('panelist_id', shipment.panelist_id)
          .eq('material_id', confirmedItem.material_id)
          .single()

        const newPanelistQuantity = (currentPanelistStock?.quantity || 0) + confirmedItem.quantity_sent
        await supabase
          .from('panelist_material_stocks')
          .upsert({
            account_id: accountId,
            panelist_id: shipment.panelist_id,
            material_id: confirmedItem.material_id,
            quantity: newPanelistQuantity,
            last_updated: new Date().toISOString()
          }, {
            onConflict: 'account_id,panelist_id,material_id'
          })

        // Create movement with stock alert if needed
        const materialInfo = currentRegulatorStock?.material_catalog as any
        const stockAlertNote = hasStockIssue
          ? `⚠️ STOCK ALERT: Insufficient stock in regulator. Sent: ${confirmedItem.quantity_sent}, Available: ${stockAvailable} ${materialInfo?.unit_measure || 'units'}. Material: ${materialInfo?.name || confirmedItem.material_id}. Inventory check required.`
          : `Shipment to ${shipment.panelist?.name || 'Unknown Panelist'}`

        await supabase
          .from('material_movements')
          .insert({
            account_id: accountId,
            material_id: confirmedItem.material_id,
            movement_type: 'dispatch',
            quantity: confirmedItem.quantity_sent,
            from_location_type: 'regulator',
            from_location_id: null,
            to_location_type: 'panelist',
            to_location_id: shipment.panelist_id,
            reference_id: shipmentId,
            reference_type: 'shipment',
            notes: stockAlertNote,
            created_by: profile?.id
          })

        // Create stock alert if insufficient
        if (hasStockIssue) {
          await supabase
            .from('stock_alerts')
            .insert({
              account_id: accountId,
              material_id: confirmedItem.material_id,
              alert_type: 'regulator_insufficient',
              location_id: null,
              current_quantity: currentRegulatorStock?.quantity || 0,
              expected_quantity: confirmedItem.quantity_sent,
              reference_id: shipmentId,
              reference_type: 'shipment',
              notes: stockAlertNote
            })
        }

        // Create receipt movement for panelist
        await supabase
          .from('material_movements')
          .insert({
            account_id: accountId,
            material_id: confirmedItem.material_id,
            movement_type: 'receipt',
            quantity: confirmedItem.quantity_sent,
            from_location_type: 'regulator',
            from_location_id: null,
            to_location_type: 'panelist',
            to_location_id: shipment.panelist_id,
            reference_id: shipmentId,
            reference_type: 'shipment',
            notes: `Received by ${shipment.panelist?.name || 'Unknown Panelist'}`,
            created_by: profile?.id
          })
      }

      // 5. Delete confirmed items from shipment
      for (const confirmedItem of confirmedItems) {
        await supabase
          .from('material_shipment_items')
          .delete()
          .eq('id', confirmedItem.id)
      }

      // 6. If there are removed items, create new pending shipment
      if (removedItems.length > 0) {
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
              shipment_id: newShipment.id,
              material_id: removedItem.material_id,
              quantity_sent: removedItem.quantity_sent
            })
        }
      }

      // 7. Delete original shipment
      await supabase
        .from('material_shipments')
        .delete()
        .eq('id', shipmentId)

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
      // Delete shipment items first (foreign key constraint)
      const { error: itemsError } = await supabase
        .from('material_shipment_items')
        .delete()
        .eq('shipment_id', shipmentId)

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
    confirmShipment,
    updateShipmentItem,
    deleteShipment,
    updateSettings,
    reload: loadData
  }
}
