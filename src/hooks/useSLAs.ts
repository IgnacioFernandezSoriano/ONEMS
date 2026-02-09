import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { SLAWithDetails, SLAFormData, GenerateCombinationsRequest } from '@/lib/types_slas'
import type { PostalCenter } from '@/lib/types_postal_centers'
import { useEffectiveAccountId } from './useEffectiveAccountId'

export function useSLAs() {
  const effectiveAccountId = useEffectiveAccountId()
  const [slas, setSLAs] = useState<SLAWithDetails[]>([])
  const [postalCenters, setPostalCenters] = useState<PostalCenter[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAll = async () => {
    try {
      setLoading(true)
      setError(null)

      // Build queries with account filter
      let slasQuery = supabase
        .from('slas')
        .select(`
          *,
          postal_center:postal_centers!slas_postal_center_id_fkey(*),
          from_postal_center:postal_centers!slas_from_postal_center_id_fkey(*),
          to_postal_center:postal_centers!slas_to_postal_center_id_fkey(*)
        `)

      let postalCentersQuery = supabase
        .from('postal_centers')
        .select('*')
        .eq('is_active', true)

      if (effectiveAccountId) {
        slasQuery = slasQuery.eq('account_id', effectiveAccountId)
        postalCentersQuery = postalCentersQuery.eq('account_id', effectiveAccountId)
      }

      const [slasRes, postalCentersRes] = await Promise.all([
        slasQuery.order('created_at', { ascending: false }),
        postalCentersQuery.order('name'),
      ])

      if (slasRes.error) throw slasRes.error
      if (postalCentersRes.error) throw postalCentersRes.error

      setSLAs(slasRes.data || [])
      setPostalCenters(postalCentersRes.data || [])
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAll()
  }, [effectiveAccountId])

  const createSLA = async (data: SLAFormData) => {
    if (!effectiveAccountId) throw new Error('Account ID is required')

    const { error } = await supabase.from('slas').insert({
      ...data,
      account_id: effectiveAccountId,
    })

    if (error) throw error
    await fetchAll()
  }

  const generateCombinations = async (request: GenerateCombinationsRequest & {
    selectedCenters?: string[]
    selectedRoutes?: Array<{ from: string; to: string }>
    generateOperational?: boolean
    generateDistribution?: boolean
  }) => {
    if (!effectiveAccountId) throw new Error('Account ID is required')

    const combinations: any[] = []

    // 1. Generate OPERATIONAL SLAs for selected centers
    if (request.generateOperational && request.selectedCenters) {
      for (const centerId of request.selectedCenters) {
        combinations.push({
          account_id: effectiveAccountId,
          sla_type: 'operational',
          postal_center_id: centerId,
          from_postal_center_id: null,
          to_postal_center_id: null,
          expected_time_minutes: request.expected_time_minutes,
          time_unit: request.time_unit,
          on_time_percentage: request.on_time_percentage,
          warning_threshold: request.warning_threshold,
          critical_threshold: request.critical_threshold,
          is_active: true,
        })
      }
    }

    // 2. Generate DISTRIBUTION SLAs for selected routes
    if (request.generateDistribution && request.selectedRoutes) {
      for (const route of request.selectedRoutes) {
        combinations.push({
          account_id: effectiveAccountId,
          sla_type: 'distribution',
          postal_center_id: null,
          from_postal_center_id: route.from,
          to_postal_center_id: route.to,
          expected_time_minutes: request.expected_time_minutes,
          time_unit: request.time_unit,
          on_time_percentage: request.on_time_percentage,
          warning_threshold: request.warning_threshold,
          critical_threshold: request.critical_threshold,
          is_active: true,
        })
      }
    }

    if (combinations.length === 0) {
      return { inserted_count: 0, skipped_count: 0 }
    }

    // Batch insert with upsert (skip duplicates)
    const chunkSize = 500
    let insertedCount = 0
    let skippedCount = 0

    for (let i = 0; i < combinations.length; i += chunkSize) {
      const chunk = combinations.slice(i, i + chunkSize)
      
      const { data, error } = await supabase
        .from('slas')
        .upsert(chunk, { 
          onConflict: 'id', // Will use unique indexes to detect conflicts
          ignoreDuplicates: true 
        })
        .select()

      if (error) {
        // If error is due to unique constraint, count as skipped
        if (error.code === '23505') {
          skippedCount += chunk.length
        } else {
          throw error
        }
      } else {
        insertedCount += data?.length || 0
        skippedCount += chunk.length - (data?.length || 0)
      }
    }

    await fetchAll()
    return { inserted_count: insertedCount, skipped_count: skippedCount }
  }

  const updateSLA = async (
    id: string,
    data: Partial<SLAFormData>
  ) => {
    const { error } = await supabase
      .from('slas')
      .update(data)
      .eq('id', id)

    if (error) throw error
    await fetchAll()
  }

  const updateMultiple = async (
    ids: string[],
    data: Partial<SLAFormData>
  ) => {
    const { error } = await supabase
      .from('slas')
      .update(data)
      .in('id', ids)

    if (error) throw error
    await fetchAll()
  }

  const deleteSLA = async (id: string) => {
    const { error } = await supabase.from('slas').delete().eq('id', id)
    if (error) throw error
    await fetchAll()
  }

  const deleteMultiple = async (ids: string[]) => {
    const { error } = await supabase.from('slas').delete().in('id', ids)
    if (error) throw error
    await fetchAll()
  }

  return {
    slas,
    postalCenters,
    loading,
    error,
    createSLA,
    generateCombinations,
    updateSLA,
    updateMultiple,
    deleteSLA,
    deleteMultiple,
    refresh: fetchAll,
  }
}
