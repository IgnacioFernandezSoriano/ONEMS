import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { SLAWithDetails, SLAFormData, GenerateCombinationsRequest } from '@/lib/types_slas'
import type { PostalCenter, Reader } from '@/lib/types_postal_centers'
import { useEffectiveAccountId } from './useEffectiveAccountId'

export function useSLAs() {
  const effectiveAccountId = useEffectiveAccountId()
  const [slas, setSLAs] = useState<SLAWithDetails[]>([])
  const [postalCenters, setPostalCenters] = useState<PostalCenter[]>([])
  const [readers, setReaders] = useState<Reader[]>([])
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
          from_reader:readers!slas_from_reader_id_fkey(*),
          to_reader:readers!slas_to_reader_id_fkey(*),
          from_postal_center:postal_centers!slas_from_postal_center_id_fkey(*),
          to_postal_center:postal_centers!slas_to_postal_center_id_fkey(*)
        `)

      let postalCentersQuery = supabase
        .from('postal_centers')
        .select('*')
        .eq('is_active', true)

      let readersQuery = supabase
        .from('readers')
        .select('*')
        .eq('is_active', true)

      if (effectiveAccountId) {
        slasQuery = slasQuery.eq('account_id', effectiveAccountId)
        postalCentersQuery = postalCentersQuery.eq('account_id', effectiveAccountId)
        readersQuery = readersQuery.eq('account_id', effectiveAccountId)
      }

      const [slasRes, postalCentersRes, readersRes] = await Promise.all([
        slasQuery.order('created_at', { ascending: false }),
        postalCentersQuery.order('name'),
        readersQuery.order('reader_id'),
      ])

      if (slasRes.error) throw slasRes.error
      if (postalCentersRes.error) throw postalCentersRes.error
      if (readersRes.error) throw readersRes.error

      setSLAs(slasRes.data || [])
      setPostalCenters(postalCentersRes.data || [])
      setReaders(readersRes.data || [])
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

  const generateCombinations = async (request: GenerateCombinationsRequest) => {
    if (!effectiveAccountId) throw new Error('Account ID is required')

    // Generate combinations client-side (simpler than RPC for now)
    const combinations: any[] = []

    if (request.sla_type === 'operational') {
      // For each selected postal center, generate SLAs for all entry→exit reader pairs
      const selectedCenters = request.postal_center_ids || []
      
      for (const centerId of selectedCenters) {
        const centerReaders = readers.filter(r => r.postal_center_id === centerId)
        const entryReaders = centerReaders.filter(r => r.type === 'Entry' || r.type === 'Mixed')
        const exitReaders = centerReaders.filter(r => r.type === 'Exit' || r.type === 'Mixed')

        for (const fromReader of entryReaders) {
          for (const toReader of exitReaders) {
            if (fromReader.id !== toReader.id) {
              combinations.push({
                account_id: effectiveAccountId,
                sla_type: 'operational',
                postal_center_id: centerId,
                from_reader_id: fromReader.id,
                to_reader_id: toReader.id,
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
        }
      }
    } else if (request.sla_type === 'distribution') {
      // Generate SLAs for all from_center → to_center pairs
      const fromCenters = request.from_postal_center_ids || []
      const toCenters = request.to_postal_center_ids || []

      for (const fromCenterId of fromCenters) {
        for (const toCenterId of toCenters) {
          if (fromCenterId !== toCenterId) {
            combinations.push({
              account_id: effectiveAccountId,
              sla_type: 'distribution',
              postal_center_id: null,
              from_reader_id: null,
              to_reader_id: null,
              from_postal_center_id: fromCenterId,
              to_postal_center_id: toCenterId,
              expected_time_minutes: request.expected_time_minutes,
              time_unit: request.time_unit,
              on_time_percentage: request.on_time_percentage,
              warning_threshold: request.warning_threshold,
              critical_threshold: request.critical_threshold,
              is_active: true,
            })
          }
        }
      }
    }

    // Batch insert with upsert (skip duplicates)
    if (combinations.length === 0) {
      return { inserted_count: 0, skipped_count: 0 }
    }

    // Chunk into batches of 500
    const chunkSize = 500
    let insertedCount = 0
    let skippedCount = 0

    for (let i = 0; i < combinations.length; i += chunkSize) {
      const chunk = combinations.slice(i, i + chunkSize)
      
      const { data, error } = await supabase
        .from('slas')
        .upsert(chunk, { 
          onConflict: request.sla_type === 'operational' 
            ? 'account_id,postal_center_id,from_reader_id,to_reader_id'
            : 'account_id,from_postal_center_id,to_postal_center_id',
          ignoreDuplicates: true 
        })
        .select()

      if (error) throw error
      
      insertedCount += data?.length || 0
      skippedCount += chunk.length - (data?.length || 0)
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
    readers,
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
