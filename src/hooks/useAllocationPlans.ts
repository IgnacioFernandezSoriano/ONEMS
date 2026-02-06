import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useEffectiveAccountId } from './useEffectiveAccountId'
import type {
  GeneratedAllocationPlan,
  GeneratedAllocationPlanDetail,
  GeneratedAllocationPlanWithDetails,
  Carrier,
  Product,
  City,
  Node,
} from '@/lib/types'

export function useAllocationPlans() {
  const effectiveAccountId = useEffectiveAccountId()
  const [generatedPlans, setGeneratedPlans] = useState<GeneratedAllocationPlanWithDetails[]>([])
  const [carriers, setCarriers] = useState<Carrier[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [cities, setCities] = useState<City[]>([])
  const [nodes, setNodes] = useState<Node[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAll = async () => {
    try {
      setLoading(true)
      setError(null)

      // Fetch generated plans with relations
      let plansQuery = supabase
        .from('generated_allocation_plans')
        .select('*, carriers(*), products(*)')

      // Filter by account if effectiveAccountId is set
      if (effectiveAccountId) {
        plansQuery = plansQuery.eq('account_id', effectiveAccountId)
      }

      const { data: plansData, error: plansError } = await plansQuery.order('created_at', { ascending: false })

      if (plansError) throw plansError

      // Count details for each plan
      const plansWithCounts = await Promise.all(
        (plansData || []).map(async (plan) => {
          const { count } = await supabase
            .from('generated_allocation_plan_details')
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

      setGeneratedPlans(plansWithCounts)

      // Fetch carriers
      const { data: carriersData, error: carriersError } = await supabase
        .from('carriers')
        .select('*')
        .eq('status', 'active')
        .order('name')

      if (carriersError) throw carriersError
      setCarriers(carriersData || [])

      // Fetch products
      const { data: productsData, error: productsError } = await supabase
        .from('products')
        .select('*')
        .eq('status', 'active')
        .order('description')

      if (productsError) throw productsError
      setProducts(productsData || [])

      // Fetch cities
      const { data: citiesData, error: citiesError } = await supabase
        .from('cities')
        .select('*')
        .eq('status', 'active')
        .order('name')

      if (citiesError) throw citiesError
      setCities(citiesData || [])

      // Fetch nodes
      const { data: nodesData, error: nodesError } = await supabase
        .from('nodes')
        .select('*')
        .eq('status', 'active')
        .order('auto_id')

      if (nodesError) throw nodesError
      setNodes(nodesData || [])
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAll()
  }, [effectiveAccountId])

  const createPlan = async (data: {
    plan_name: string
    carrier_id: string
    product_id: string
    total_samples: number
    start_date: string
    end_date: string
  }) => {
    try {
      // Get current user
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('User not authenticated')

      // Get account_id: use effectiveAccountId if available (superadmin with selected account),
      // otherwise use profile.account_id (normal user)
      let accountId = effectiveAccountId
      
      if (!accountId) {
        const { data: profile } = await supabase
          .from('profiles')
          .select('account_id')
          .eq('id', user.id)
          .single()
        accountId = profile?.account_id
      }

      if (!accountId) throw new Error('User account not found')

      const { data: plan, error } = await supabase
        .from('generated_allocation_plans')
        .insert({
          ...data,
          account_id: accountId,
          created_by: user.id,
        })
        .select()
        .single()

      if (error) throw error
      await fetchAll()
      return plan
    } catch (err: any) {
      setError(err.message)
      console.error('Error creating allocation plan:', err)
      throw err
    }
  }

  const createPlanDetails = async (planId: string, details: any[]) => {
    const { error } = await supabase.from('generated_allocation_plan_details').insert(
      details.map((d) => ({
        plan_id: planId,
        ...d,
      }))
    )

    if (error) throw error
    await fetchAll()
  }

  const updatePlan = async (id: string, data: Partial<GeneratedAllocationPlan>) => {
    const { error } = await supabase
      .from('generated_allocation_plans')
      .update(data)
      .eq('id', id)

    if (error) throw error
    await fetchAll()
  }

  const deletePlan = async (id: string) => {
    // Delete details first (cascade should handle this, but being explicit)
    await supabase.from('generated_allocation_plan_details').delete().eq('plan_id', id)

    const { error } = await supabase.from('generated_allocation_plans').delete().eq('id', id)

    if (error) throw error
    await fetchAll()
  }

  const getPlanDetails = async (planId: string) => {
    const { data, error } = await supabase
      .from('generated_allocation_plan_details')
      .select('*')
      .eq('plan_id', planId)
      .order('fecha_programada')

    if (error) throw error
    return data || []
  }

  const updatePlanDetail = async (id: string, data: Partial<GeneratedAllocationPlanDetail>) => {
    const { error } = await supabase
      .from('generated_allocation_plan_details')
      .update(data)
      .eq('id', id)

    if (error) throw error
  }

  const deletePlanDetail = async (id: string) => {
    const { error } = await supabase
      .from('generated_allocation_plan_details')
      .delete()
      .eq('id', id)

    if (error) throw error
  }

  const applyPlan = async (planId: string, appliedBy: string) => {
    // Get plan and details
    const { data: plan, error: planError } = await supabase
      .from('generated_allocation_plans')
      .select('*')
      .eq('id', planId)
      .single()

    if (planError) throw planError

    const { data: details, error: detailsError } = await supabase
      .from('generated_allocation_plan_details')
      .select('*')
      .eq('plan_id', planId)

    if (detailsError) throw detailsError

    // Create applied plan
    const { data: appliedPlan, error: appliedPlanError } = await supabase
      .from('allocation_plans')
      .insert({
        plan_name: plan.plan_name,
        carrier_id: plan.carrier_id,
        product_id: plan.product_id,
        total_samples: plan.total_samples,
        start_date: plan.start_date,
        end_date: plan.end_date,
        status: 'active',
        created_by: plan.created_by,
        applied_by: appliedBy,
      })
      .select()
      .single()

    if (appliedPlanError) throw appliedPlanError

    // Create applied plan details in batches (Supabase limit: 1000 per request)
    const batchSize = 1000
    const detailsToInsert = details.map((d) => ({
      plan_id: appliedPlan.id,
      origin_node_id: d.origin_node_id,
      destination_node_id: d.destination_node_id,
      fecha_programada: d.fecha_programada,
      week_number: d.week_number,
      month: d.month,
      year: d.year,
      status: d.status,
    }))

    for (let i = 0; i < detailsToInsert.length; i += batchSize) {
      const batch = detailsToInsert.slice(i, i + batchSize)
      const { error: batchError } = await supabase.from('allocation_plan_details').insert(batch)
      if (batchError) throw batchError
    }

    // Update generated plan status
    await updatePlan(planId, { status: 'applied' })

    await fetchAll()
    return appliedPlan
  }

  return {
    generatedPlans,
    carriers,
    products,
    cities,
    nodes,
    loading,
    error,
    createPlan,
    createPlanDetails,
    updatePlan,
    deletePlan,
    getPlanDetails,
    updatePlanDetail,
    deletePlanDetail,
    applyPlan,
    refresh: fetchAll,
  }
}
