import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { useAccount } from '../contexts/AccountContext'

export interface AccountConfig {
  id: string
  account_id: string
  calculation_mode: 'natural_days' | 'working_days'
  mixed_reader_gap_minutes: number
  created_at: string
  updated_at: string
}

export interface NonWorkingDay {
  id: string
  account_id: string
  date: string
  reason: string
  created_at: string
}

export interface WeeklySchedule {
  id: string
  account_id: string
  postal_center_id?: string
  day_of_week: number // 0 = Sunday, 6 = Saturday
  opening_hour: string // HH:MM format
  cutoff_time: string // HH:MM format
  is_working_day: boolean
  created_at: string
}

export function useAccountConfig() {
  const { effectiveAccountId } = useAccount()
  const [config, setConfig] = useState<AccountConfig | null>(null)
  const [nonWorkingDays, setNonWorkingDays] = useState<NonWorkingDay[]>([])
  const [weeklySchedule, setWeeklySchedule] = useState<WeeklySchedule[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (effectiveAccountId) {
      fetchAccountConfig()
      fetchNonWorkingDays()
      fetchWeeklySchedule()
    }
  }, [effectiveAccountId])

  const fetchAccountConfig = async () => {
    try {
      setLoading(true)
      const { data, error: fetchError } = await supabase
        .from('account_config')
        .select('*')
        .eq('account_id', effectiveAccountId)
        .single()

      if (fetchError) throw fetchError
      setConfig(data)
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const fetchNonWorkingDays = async () => {
    try {
      const { data, error: fetchError } = await supabase
        .from('non_working_days')
        .select('*')
        .eq('account_id', effectiveAccountId)
        .order('date', { ascending: true })

      if (fetchError) throw fetchError
      setNonWorkingDays(data || [])
    } catch (err: any) {
      console.error('Error fetching non-working days:', err)
    }
  }

  const fetchWeeklySchedule = async () => {
    try {
      const { data, error: fetchError } = await supabase
        .from('weekly_schedule')
        .select('*')
        .eq('account_id', effectiveAccountId)
        .order('day_of_week', { ascending: true })

      if (fetchError) throw fetchError
      setWeeklySchedule(data || [])
    } catch (err: any) {
      console.error('Error fetching weekly schedule:', err)
    }
  }

  const updateConfig = async (updates: Partial<AccountConfig>) => {
    try {
      const { error: updateError } = await supabase
        .from('account_config')
        .update(updates)
        .eq('account_id', effectiveAccountId)

      if (updateError) throw updateError
      await fetchAccountConfig()
      return { success: true }
    } catch (err: any) {
      return { success: false, error: err.message }
    }
  }

  const addNonWorkingDay = async (date: string, reason: string) => {
    try {
      const { error: insertError } = await supabase
        .from('non_working_days')
        .insert({
          account_id: effectiveAccountId,
          date,
          reason,
        })

      if (insertError) throw insertError
      await fetchNonWorkingDays()
      return { success: true }
    } catch (err: any) {
      return { success: false, error: err.message }
    }
  }

  const deleteNonWorkingDay = async (id: string) => {
    try {
      const { error: deleteError } = await supabase
        .from('non_working_days')
        .delete()
        .eq('id', id)

      if (deleteError) throw deleteError
      await fetchNonWorkingDays()
      return { success: true }
    } catch (err: any) {
      return { success: false, error: err.message }
    }
  }

  const updateWeeklySchedule = async (
    dayOfWeek: number,
    updates: Partial<WeeklySchedule>
  ) => {
    try {
      const existing = weeklySchedule.find((s) => s.day_of_week === dayOfWeek)

      if (existing) {
        const { error: updateError } = await supabase
          .from('weekly_schedule')
          .update(updates)
          .eq('id', existing.id)

        if (updateError) throw updateError
      } else {
        // When inserting new record, include all required fields with defaults
        const newRecord = {
          account_id: effectiveAccountId,
          day_of_week: dayOfWeek,
          is_working_day: true,
          opening_hour: '08:00',
          cutoff_time: '18:00',
          ...updates, // Override with provided updates
        }
        
        const { error: insertError } = await supabase
          .from('weekly_schedule')
          .insert(newRecord)

        if (insertError) throw insertError
      }

      await fetchWeeklySchedule()
      return { success: true }
    } catch (err: any) {
      return { success: false, error: err.message }
    }
  }

  const bulkImportNonWorkingDays = async (holidays: Array<{ date: string; reason: string }>) => {
    try {
      const records = holidays.map((h) => ({
        account_id: effectiveAccountId,
        date: h.date,
        reason: h.reason,
      }))

      const { error: insertError } = await supabase
        .from('non_working_days')
        .insert(records)

      if (insertError) throw insertError
      await fetchNonWorkingDays()
      return { success: true }
    } catch (err: any) {
      return { success: false, error: err.message }
    }
  }

  return {
    config,
    nonWorkingDays,
    weeklySchedule,
    loading,
    error,
    updateConfig,
    addNonWorkingDay,
    deleteNonWorkingDay,
    updateWeeklySchedule,
    bulkImportNonWorkingDays,
    refetch: () => {
      fetchAccountConfig()
      fetchNonWorkingDays()
      fetchWeeklySchedule()
    },
  }
}
