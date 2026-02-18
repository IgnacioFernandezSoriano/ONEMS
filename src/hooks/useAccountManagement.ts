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

      // BACKUP: Save products and delivery_standards before deletion
      const { data: productsBackup } = await supabase
        .from('products')
        .select('*')
        .eq('account_id', demo2AccountId)
      
      const { data: deliveryStandardsBackup } = await supabase
        .from('delivery_standards')
        .select('*')
        .eq('account_id', demo2AccountId)

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

      // 12. Delete reader location history
      const { count: readerLocationCount } = await supabase
        .from('reader_location_history')
        .delete({ count: 'exact' })
        .eq('account_id', demo2AccountId)
      deletedCounts.reader_location_history = readerLocationCount || 0

      // RESTORE: Re-insert products and delivery_standards
      if (productsBackup && productsBackup.length > 0) {
        // Remove id, created_at, updated_at to let DB generate new ones
        const productsToRestore = productsBackup.map(({ id, created_at, updated_at, ...rest }) => rest)
        const { error: productsError } = await supabase
          .from('products')
          .insert(productsToRestore)
        
        if (productsError) {
          console.error('Error restoring products:', productsError)
        }
      }

      if (deliveryStandardsBackup && deliveryStandardsBackup.length > 0) {
        // Remove id, created_at, updated_at to let DB generate new ones
        const deliveryStandardsToRestore = deliveryStandardsBackup.map(({ id, created_at, updated_at, ...rest }) => rest)
        const { error: deliveryStandardsError } = await supabase
          .from('delivery_standards')
          .insert(deliveryStandardsToRestore)
        
        if (deliveryStandardsError) {
          console.error('Error restoring delivery_standards:', deliveryStandardsError)
        }
      }

      return {
        success: true,
        account_id: demo2AccountId,
        account_name: 'DEMO2',
        message: 'Account data reset successfully',
        deleted_records: deletedCounts
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
