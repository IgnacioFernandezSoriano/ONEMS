import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { PostalCenter, Reader, PostalCenterWithReaders, PostalCenterFormData, ReaderFormData } from '@/lib/types_postal_centers'
import { useEffectiveAccountId } from './useEffectiveAccountId'

export function usePostalCenters() {
  const effectiveAccountId = useEffectiveAccountId()
  const [postalCenters, setPostalCenters] = useState<PostalCenterWithReaders[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAll = async () => {
    try {
      setLoading(true)
      setError(null)

      // Fetch postal centers
      let centersQuery = supabase
        .from('postal_centers')
        .select('*')
        .order('name')

      if (effectiveAccountId) {
        centersQuery = centersQuery.eq('account_id', effectiveAccountId)
      }

      const { data: centers, error: centersError } = await centersQuery

      if (centersError) throw centersError

      // Fetch readers for all centers
      let readersQuery = supabase
        .from('readers')
        .select('*')
        .order('name')

      if (effectiveAccountId) {
        readersQuery = readersQuery.eq('account_id', effectiveAccountId)
      }

      const { data: readers, error: readersError } = await readersQuery

      if (readersError) throw readersError

      // Group readers by postal_center_id
      const readersByCenter = (readers || []).reduce((acc, reader) => {
        if (!acc[reader.postal_center_id]) {
          acc[reader.postal_center_id] = []
        }
        acc[reader.postal_center_id].push(reader)
        return acc
      }, {} as Record<string, Reader[]>)

      // Combine centers with their readers
      const centersWithReaders: PostalCenterWithReaders[] = (centers || []).map(center => ({
        ...center,
        readers: readersByCenter[center.id] || []
      }))

      setPostalCenters(centersWithReaders)
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAll()
  }, [effectiveAccountId])

  const createPostalCenter = async (data: PostalCenterFormData & { weeklySchedule?: any[] }) => {
    const { weeklySchedule, ...centerData } = data
    
    // Insert postal center
    const { data: newCenter, error: centerError } = await supabase
      .from('postal_centers')
      .insert({
        ...centerData,
        account_id: effectiveAccountId
      })
      .select()
      .single()
    
    if (centerError) throw centerError
    
    // Insert center-specific weekly schedule if any
    if (weeklySchedule && weeklySchedule.length > 0 && newCenter) {
      const scheduleToInsert = weeklySchedule.map(s => ({
        account_id: effectiveAccountId,
        postal_center_id: newCenter.id,
        day_of_week: s.day_of_week,
        is_working_day: s.is_working_day,
        opening_hour: s.opening_hour,
        cutoff_time: s.cutoff_time
      }))
      
      const { error: scheduleError } = await supabase
        .from('weekly_schedule')
        .insert(scheduleToInsert)
      
      if (scheduleError) throw scheduleError
    }
    
    await fetchAll()
  }

  const updatePostalCenter = async (id: string, data: Partial<PostalCenterFormData> & { weeklySchedule?: any[] }) => {
    const { weeklySchedule, ...centerData } = data
    
    // Update postal center
    const { error: centerError } = await supabase
      .from('postal_centers')
      .update(centerData)
      .eq('id', id)
    
    if (centerError) throw centerError
    
    // Update weekly schedule if provided
    if (weeklySchedule !== undefined && weeklySchedule.length > 0) {
      // Use upsert to insert or update each day
      const scheduleToUpsert = weeklySchedule.map(s => ({
        account_id: effectiveAccountId,
        postal_center_id: id,
        day_of_week: s.day_of_week,
        is_working_day: s.is_working_day,
        opening_hour: s.opening_hour,
        cutoff_time: s.cutoff_time
      }))
      
      const { error: scheduleError } = await supabase
        .from('weekly_schedule')
        .upsert(scheduleToUpsert, {
          onConflict: 'account_id,postal_center_id,day_of_week'
        })
      
      if (scheduleError) throw scheduleError
    }
    
    await fetchAll()
  }

  const deletePostalCenter = async (id: string) => {
    const { error } = await supabase
      .from('postal_centers')
      .delete()
      .eq('id', id)
    if (error) throw error
    await fetchAll()
  }

  const createReader = async (postalCenterId: string, data: ReaderFormData) => {
    const { error } = await supabase.from('readers').insert({
      ...data,
      postal_center_id: postalCenterId,
      account_id: effectiveAccountId
    })
    if (error) throw error
    await fetchAll()
  }

  const updateReader = async (id: string, data: Partial<ReaderFormData>) => {
    const { error } = await supabase
      .from('readers')
      .update(data)
      .eq('id', id)
    if (error) throw error
    await fetchAll()
  }

  const deleteReader = async (id: string) => {
    const { error } = await supabase
      .from('readers')
      .delete()
      .eq('id', id)
    if (error) throw error
    await fetchAll()
  }

  return {
    postalCenters,
    loading,
    error,
    createPostalCenter,
    updatePostalCenter,
    deletePostalCenter,
    createReader,
    updateReader,
    deleteReader,
    refresh: fetchAll
  }
}
