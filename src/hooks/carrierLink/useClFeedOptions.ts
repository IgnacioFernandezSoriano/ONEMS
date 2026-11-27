import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import type { ConnectorStatus } from '@/lib/carrierLink/connectorConfig'

export interface ClFeedOption {
  id: string
  carrier_id: string
  name: string
  status: ConnectorStatus
}

/**
 * Conectores de la cuenta para elegir uno (generador de planes). Usa cl_feed_options: basta View en cl_plans o en
 * cl_connectors (el Allocation Plan Manager no lee cl_feeds) y nunca trae secretos. Sin cuenta no consulta nada.
 */
export function useClFeedOptions(accountId: string | null) {
  const beginLoad = useLatestRequest()
  const [feeds, setFeeds] = useState<ClFeedOption[]>([])
  const [error, setError] = useState<{ message?: string; code?: string } | null>(null)

  useEffect(() => {
    const isStale = beginLoad()
    if (!accountId) {
      setFeeds([])
      setError(null)
      return
    }
    void (async () => {
      const { data, error: e } = await supabase.rpc('cl_feed_options', { p_account_id: accountId })
      if (isStale()) return
      setFeeds(e ? [] : ((data ?? []) as ClFeedOption[]))
      setError(e ?? null)
    })()
  }, [accountId, beginLoad])

  return { feeds, error }
}
