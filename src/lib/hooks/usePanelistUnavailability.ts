import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { PanelistUnavailability, PanelistUnavailabilityWithPanelist } from '@/lib/types'

export function usePanelistUnavailability(panelistId?: string) {
  const [unavailabilityPeriods, setUnavailabilityPeriods] = useState<PanelistUnavailabilityWithPanelist[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchUnavailabilityPeriods = async () => {
    try {
      setLoading(true)
      setError(null)

      let query = supabase
        .from('panelist_unavailability')
        .select(`
          *,
          panelist:panelists (*)
        `)
        .order('start_date', { ascending: false })

      if (panelistId) {
        query = query.eq('panelist_id', panelistId)
      }

      const { data, error: fetchError } = await query

      if (fetchError) throw fetchError

      setUnavailabilityPeriods(data || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching unavailability periods:', err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchUnavailabilityPeriods()
  }, [panelistId])

  const createUnavailabilityPeriod = async (
    periodData: Omit<PanelistUnavailability, 'id' | 'created_at' | 'updated_at' | 'account_id'>
  ) => {
    try {
      // Get current user's account_id
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('User not authenticated')

      const { data: profile } = await supabase
        .from('profiles')
        .select('account_id')
        .eq('id', user.id)
        .single()

      if (!profile?.account_id) throw new Error('User account not found')

      const { data, error: insertError } = await supabase
        .from('panelist_unavailability')
        .insert({
          ...periodData,
          account_id: profile.account_id,
          created_by: user.id,
        })
        .select()
        .single()

      if (insertError) throw insertError

      await fetchUnavailabilityPeriods()
      return data
    } catch (err: any) {
      setError(err.message)
      console.error('Error creating unavailability period:', err)
      throw err
    }
  }

  const updateUnavailabilityPeriod = async (id: string, updates: Partial<PanelistUnavailability>) => {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('User not authenticated')

      const { data, error: updateError } = await supabase
        .from('panelist_unavailability')
        .update({
          ...updates,
          updated_by: user.id,
        })
        .eq('id', id)
        .select()
        .single()

      if (updateError) throw updateError

      await fetchUnavailabilityPeriods()
      return data
    } catch (err: any) {
      setError(err.message)
      console.error('Error updating unavailability period:', err)
      throw err
    }
  }

  const cancelUnavailabilityPeriod = async (id: string) => {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('User not authenticated')

      const { data, error: updateError } = await supabase
        .from('panelist_unavailability')
        .update({
          status: 'cancelled',
          updated_by: user.id,
        })
        .eq('id', id)
        .select()
        .single()

      if (updateError) throw updateError

      await fetchUnavailabilityPeriods()
      return data
    } catch (err: any) {
      setError(err.message)
      console.error('Error cancelling unavailability period:', err)
      throw err
    }
  }

  const deleteUnavailabilityPeriod = async (id: string) => {
    try {
      const { error: deleteError } = await supabase
        .from('panelist_unavailability')
        .delete()
        .eq('id', id)

      if (deleteError) throw deleteError

      await fetchUnavailabilityPeriods()
    } catch (err: any) {
      setError(err.message)
      console.error('Error deleting unavailability period:', err)
      throw err
    }
  }

  const getActivePeriods = (): PanelistUnavailabilityWithPanelist[] => {
    return unavailabilityPeriods.filter(p => p.status === 'active')
  }

  const isPanelistAvailable = (panelistId: string, date: string): boolean => {
    const checkDate = new Date(date)
    return !unavailabilityPeriods.some(period => {
      if (period.panelist_id !== panelistId || period.status !== 'active') return false
      const startDate = new Date(period.start_date)
      const endDate = new Date(period.end_date)
      return checkDate >= startDate && checkDate <= endDate
    })
  }

  return {
    unavailabilityPeriods,
    loading,
    error,
    fetchUnavailabilityPeriods,
    createUnavailabilityPeriod,
    updateUnavailabilityPeriod,
    cancelUnavailabilityPeriod,
    deleteUnavailabilityPeriod,
    getActivePeriods,
    isPanelistAvailable,
  }
}
