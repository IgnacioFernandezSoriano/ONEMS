import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { AllocationPlanWithDetails } from '@/lib/types'
import { useEffectiveAccountId } from './useEffectiveAccountId'

export function useAppliedAllocationPlans() {
  const effectiveAccountId = useEffectiveAccountId()
  const [appliedPlans, setAppliedPlans] = useState<AllocationPlanWithDetails[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAll = async () => {
    try {
      setLoading(true)
      setError(null)

      // Fetch applied plans with relations
      const { data: plansData, error: plansError } = await supabase
        .from('allocation_plans')
        .select('*, carriers(*), products(*)')
        .order('applied_date', { ascending: false })

      if (plansError) throw plansError

      // Count details for each plan
      const plansWithCounts = await Promise.all(
        (plansData || []).map(async (plan) => {
          const { count } = await supabase
            .from('allocation_plan_details')
            .select('*', { count: 'exact', head: true })
            .eq('plan_id', plan.id)

          return {
            ...plan,
            carrier: plan.carriers,
            product: plan.products,
            details_count: count || 0,
          }
        })
      )

      setAppliedPlans(plansWithCounts)
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAll()
  }, [effectiveAccountId])

  const getPlanDetails = async (planId: string) => {
    // Implement pagination to handle more than 1000 records
    const allDetails: any[] = []
    let hasMore = true
    let page = 0
    const pageSize = 1000

    while (hasMore) {
      const { data, error } = await supabase
        .from('allocation_plan_details')
        .select('*')
        .eq('plan_id', planId)
        .order('fecha_programada')
        .range(page * pageSize, (page + 1) * pageSize - 1)

      if (error) throw error
      
      if (data && data.length > 0) {
        allDetails.push(...data)
        hasMore = data.length === pageSize
        page++
      } else {
        hasMore = false
      }
    }

    return allDetails
  }

  return {
    appliedPlans,
    loading,
    error,
    getPlanDetails,
    refresh: fetchAll,
  }
}
