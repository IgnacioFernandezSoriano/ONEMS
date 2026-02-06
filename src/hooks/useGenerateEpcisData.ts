import { useState } from 'react'
import { supabase } from '../lib/supabase'

interface GenerateEpcisDataParams {
  startDate: string
  endDate: string
  itemCount: number
  maxEventsPerItem: number
}

interface GenerateEpcisDataResponse {
  success: boolean
  message: string
  stats: {
    items: number
    totalEvents: number
    avgEventsPerItem: string
    dateRange: {
      start: string
      end: string
    }
  }
}

export function useGenerateEpcisData() {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const generateData = async (params: GenerateEpcisDataParams): Promise<GenerateEpcisDataResponse | null> => {
    setLoading(true)
    setError(null)

    try {
      // Get current session token
      const { data: { session } } = await supabase.auth.getSession()
      
      if (!session) {
        throw new Error('No active session')
      }

      // Call Edge Function
      const { data, error: functionError } = await supabase.functions.invoke('generate-epcis-data', {
        body: params,
        headers: {
          Authorization: `Bearer ${session.access_token}`,
        },
      })

      if (functionError) {
        throw new Error(functionError.message)
      }

      if (data.error) {
        throw new Error(data.error)
      }

      setLoading(false)
      return data as GenerateEpcisDataResponse
    } catch (err: any) {
      const errorMessage = err.message || 'Failed to generate EPCIS data'
      setError(errorMessage)
      setLoading(false)
      return null
    }
  }

  return {
    generateData,
    loading,
    error,
  }
}
