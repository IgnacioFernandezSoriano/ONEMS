import { useState } from 'react'
import { supabase } from '@/lib/supabase'

export interface Account {
  id: string
  name: string
  created_at: string
}

export interface ResetResult {
  success: boolean
  account_id?: string
  account_name?: string
  message: string
  deleted_records?: Record<string, number>
  restored_records?: Record<string, number>
}

export function useAccountManagement() {
  const [accounts, setAccounts] = useState<Account[]>([])
  const [loading, setLoading] = useState(false)
  const [resetting, setResetting] = useState(false)

  const fetchAccounts = async () => {
    setLoading(true)
    try {
      const { data, error } = await supabase
        .from('accounts')
        .select('id, name, created_at')
        .eq('name', 'DEMO2')
        .single()

      if (error) throw error
      setAccounts(data ? [data] : [])
    } catch (error) {
      console.error('Error fetching DEMO2 account:', error)
    } finally {
      setLoading(false)
    }
  }

  const resetAccountData = async (accountIdentifier: string): Promise<ResetResult> => {
    setResetting(true)
    try {
      // Get DEMO2 account ID
      const { data: accountData, error: accountError } = await supabase
        .from('accounts')
        .select('id')
        .eq('name', 'DEMO2')
        .single()

      if (accountError) throw accountError
      if (!accountData) throw new Error('DEMO2 account not found')

      const demo2AccountId = accountData.id
      const deletedCounts: Record<string, number> = {}

      // Load fixed configuration data from JSON files
      const carriersData = await import('@/data/demo2/carriers.json')
      const regionsData = await import('@/data/demo2/regions.json')
      const citiesData = await import('@/data/demo2/cities.json')
      const nodesData = await import('@/data/demo2/nodes.json')
      const panelistsData = await import('@/data/demo2/panelists.json')
      const productsData = await import('@/data/demo2/products.json')
      const deliveryStandardsData = await import('@/data/demo2/delivery_standards.json')
      const oneDbData = await import('@/data/demo2/one_db.json')
      const postalCentersData = await import('@/data/demo2/postal_centers.json')
      const readersData = await import('@/data/demo2/readers.json')

      // Delete in correct order to respect foreign key constraints

      // 1. Delete SLAs first (depends on products)
      const { count: slasCount } = await supabase
        .from('slas')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.slas = slasCount || 0

      // 2. Delete allocation plans
      const { count: allocationPlansCount } = await supabase
        .from('allocation_plans')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.allocation_plans = allocationPlansCount || 0

      // 3. Delete applied allocation plans
      const { count: appliedPlansCount } = await supabase
        .from('applied_allocation_plans')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.applied_allocation_plans = appliedPlansCount || 0

      // 4. Delete panelist unavailability
      const { count: unavailabilityCount } = await supabase
        .from('panelist_unavailability')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.panelist_unavailability = unavailabilityCount || 0

      // 5. Delete stock alerts
      const { count: stockAlertsCount } = await supabase
        .from('stock_alerts')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.stock_alerts = stockAlertsCount || 0

      // 6. Delete panelist stock
      const { count: panelistStockCount } = await supabase
        .from('panelist_stock')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.panelist_stock = panelistStockCount || 0

      // 7. Delete regulator stock
      const { count: regulatorStockCount } = await supabase
        .from('regulator_stock')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.regulator_stock = regulatorStockCount || 0

      // 8. Delete proposed shipments
      const { count: proposedShipmentsCount } = await supabase
        .from('proposed_shipments')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.proposed_shipments = proposedShipmentsCount || 0

      // 9. Delete complete journeys
      const { count: completeJourneysCount } = await supabase
        .from('complete_journeys')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.complete_journeys = completeJourneysCount || 0

      // 10. Delete journey segments
      const { count: journeySegmentsCount } = await supabase
        .from('journey_segments')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.journey_segments = journeySegmentsCount || 0

      // 11. Delete processed events
      const { count: processedEventsCount } = await supabase
        .from('processed_events')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.processed_events = processedEventsCount || 0

      // 12. Delete one_db
      const { count: oneDbCount } = await supabase
        .from('one_db')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.one_db = oneDbCount || 0

      // 13. Delete readers (depends on postal_centers)
      const { count: readersCount } = await supabase
        .from('readers')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.readers = readersCount || 0

      // 14. Delete reader location history
      const { count: readerLocationCount } = await supabase
        .from('reader_location_history')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.reader_location_history = readerLocationCount || 0

      // 15. Delete panelists (depends on nodes)
      const { count: panelistsCount } = await supabase
        .from('panelists')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.panelists = panelistsCount || 0

      // 15. Delete nodes (depends on postal_centers)
      const { count: nodesCount } = await supabase
        .from('nodes')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.nodes = nodesCount || 0

      // 16. Delete postal_centers (depends on cities)
      const { count: postalCentersCount } = await supabase
        .from('postal_centers')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.postal_centers = postalCentersCount || 0

      // 17. Delete topology
      const { count: topologyCount } = await supabase
        .from('topology')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.topology = topologyCount || 0

      // 18. Delete cities (depends on regions)
      const { count: citiesCount } = await supabase
        .from('cities')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.cities = citiesCount || 0

      // 19. Delete regions
      const { count: regionsCount } = await supabase
        .from('regions')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.regions = regionsCount || 0

      // 20. Delete carriers
      const { count: carriersCount } = await supabase
        .from('carriers')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.carriers = carriersCount || 0

      // RESTORE: Re-insert all configuration and data tables in correct order
      const restoredCounts: Record<string, number> = {}
      
      // Restore carriers first (no dependencies)
      if (carriersData.default && carriersData.default.length > 0) {
        const { error } = await supabase.from('carriers').insert(carriersData.default)
        if (!error) restoredCounts.carriers = carriersData.default.length
        else console.error('Error restoring carriers:', error)
      }

      // Restore regions
      if (regionsData.default && regionsData.default.length > 0) {
        const { error } = await supabase.from('regions').insert(regionsData.default)
        if (!error) restoredCounts.regions = regionsData.default.length
        else console.error('Error restoring regions:', error)
      }

      // Restore cities (depends on regions)
      if (citiesData.default && citiesData.default.length > 0) {
        const { error } = await supabase.from('cities').insert(citiesData.default)
        if (!error) restoredCounts.cities = citiesData.default.length
        else console.error('Error restoring cities:', error)
      }



      // Restore nodes (depends on cities)
      if (nodesData.default && nodesData.default.length > 0) {
        const { error } = await supabase.from('nodes').insert(nodesData.default)
        if (!error) restoredCounts.nodes = nodesData.default.length
        else console.error('Error restoring nodes:', error)
      }

      // Restore panelists (depends on nodes)
      if (panelistsData.default && panelistsData.default.length > 0) {
        const { error } = await supabase.from('panelists').insert(panelistsData.default)
        if (!error) restoredCounts.panelists = panelistsData.default.length
        else console.error('Error restoring panelists:', error)
      }

      // Restore postal_centers (depends on cities)
      if (postalCentersData.default && postalCentersData.default.length > 0) {
        const { error } = await supabase.from('postal_centers').insert(postalCentersData.default)
        if (!error) restoredCounts.postal_centers = postalCentersData.default.length
        else console.error('Error restoring postal_centers:', error)
      }

      // Restore readers (depends on postal_centers)
      if (readersData.default && readersData.default.length > 0) {
        const { error } = await supabase.from('readers').insert(readersData.default)
        if (!error) restoredCounts.readers = readersData.default.length
        else console.error('Error restoring readers:', error)
      }

      // Restore products
      if (productsData.default && productsData.default.length > 0) {
        const { error: productsError } = await supabase
          .from('products')
          .insert(productsData.default)
        
        if (productsError) {
          console.error('Error restoring products:', productsError)
        } else {
          restoredCounts.products = productsData.default.length
        }
      }

      if (deliveryStandardsData.default && deliveryStandardsData.default.length > 0) {
        const { error: deliveryStandardsError } = await supabase
          .from('delivery_standards')
          .insert(deliveryStandardsData.default)
        
        if (deliveryStandardsError) {
          console.error('Error restoring delivery_standards:', deliveryStandardsError)
        } else {
          restoredCounts.delivery_standards = deliveryStandardsData.default.length
        }
      }

      if (oneDbData.default && oneDbData.default.length > 0) {
        const { error: oneDbError } = await supabase
          .from('one_db')
          .insert(oneDbData.default)
        
        if (oneDbError) {
          console.error('Error restoring one_db:', oneDbError)
        } else {
          restoredCounts.one_db = oneDbData.default.length
        }
      }

      return {
        success: true,
        account_id: demo2AccountId,
        account_name: 'DEMO2',
        message: 'Account data reset successfully',
        deleted_records: deletedCounts,
        restored_records: restoredCounts
      }
    } catch (error: any) {
      console.error('Error resetting account:', error)
      return {
        success: false,
        message: `Error resetting and seeding DEMO2: ${error.message || 'Unknown error'}`
      }
    } finally {
      setResetting(false)
    }
  }

  return {
    accounts,
    loading,
    resetting,
    fetchAccounts,
    resetAccountData
  }
}
