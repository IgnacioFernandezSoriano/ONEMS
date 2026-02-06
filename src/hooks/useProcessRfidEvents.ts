import { useState } from 'react'
import { supabase } from '../lib/supabase'

interface ProcessingResult {
  success: boolean
  message: string
  stats: {
    processed: number
    routes: number
    anomalies: number
    errors: number
  }
}

export function useProcessRfidEvents() {
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<ProcessingResult | null>(null)
  const [error, setError] = useState<string | null>(null)

  const processEvents = async (batchSize: number = 5000) => {
    setLoading(true)
    setError(null)
    setResult(null)

    try {
      const { data: { session } } = await supabase.auth.getSession()

      if (!session) {
        throw new Error('No active session')
      }

      const supabaseUrl = (window as any).ENV?.VITE_SUPABASE_URL || import.meta.env.VITE_SUPABASE_URL
      
      const response = await fetch(
        `${supabaseUrl}/functions/v1/process-rfid-events`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`,
          },
          body: JSON.stringify({ batchSize }),
        }
      )

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || 'Failed to process events')
      }

      const data = await response.json()
      setResult(data)
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  return { processEvents, loading, result, error }
}
