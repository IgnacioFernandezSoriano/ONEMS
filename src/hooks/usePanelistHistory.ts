import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import type { HistoryEvent, HistoryPage } from '@/lib/panelistHistory'

/** Código de error traducible a partir del error de Postgres (42501 = sin permiso, 22023 = texto no válido). */
export function historyErrorKey(e: { code?: string } | null | undefined): string {
  if (e?.code === '42501') return 'panelist_history.error.forbidden'
  if (e?.code === '22023') return 'panelist_history.error.note_length'
  return 'panelist_history.error.generic'
}

export function usePanelistHistory(panelistId: string | null) {
  const beginLoad = useLatestRequest()
  const [data, setData] = useState<HistoryPage | null>(null)
  const [events, setEvents] = useState<HistoryEvent[]>([])
  const [loading, setLoading] = useState(false)
  const [loadingMore, setLoadingMore] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const reload = useCallback(async () => {
    if (!panelistId) return
    const isStale = beginLoad()
    setLoading(true); setError(null)
    const { data: d, error: e } = await supabase.rpc('panelist_history', { p_panelist_id: panelistId })
    if (isStale()) return
    if (e) { console.error('panelist_history', e); setError(historyErrorKey(e)); setData(null); setEvents([]) }
    else { setData(d as HistoryPage); setEvents((d as HistoryPage).events || []) }
    setLoading(false)
  }, [panelistId, beginLoad])

  useEffect(() => { setData(null); setEvents([]); reload() }, [reload])

  const loadMore = useCallback(async () => {
    if (!panelistId || !data?.next || loadingMore) return
    setLoadingMore(true)
    const { data: d, error: e } = await supabase.rpc('panelist_history', {
      p_panelist_id: panelistId, p_before: data.next.before, p_before_id: data.next.before_id })
    setLoadingMore(false)
    if (e) { console.error('panelist_history more', e); setError(historyErrorKey(e)); return }
    const page = d as HistoryPage
    setEvents(prev => {
      const seen = new Set(prev.map(x => x.id))
      return [...prev, ...(page.events || []).filter(x => !seen.has(x.id))]
    })
    setData(prev => (prev ? { ...prev, next: page.next } : page))
  }, [panelistId, data, loadingMore])

  /** Devuelve null si se guardó, o la clave del error. */
  const addNote = useCallback(async (body: string): Promise<string | null> => {
    if (!panelistId) return 'panelist_history.error.generic'
    const { error: e } = await supabase.rpc('panelist_note_add', { p_panelist_id: panelistId, p_body: body })
    if (e) { console.error('panelist_note_add', e); return historyErrorKey(e) }
    await reload()
    return null
  }, [panelistId, reload])

  const deleteNote = useCallback(async (noteId: string): Promise<string | null> => {
    const { error: e } = await supabase.rpc('panelist_note_delete', { p_note_id: noteId })
    if (e) { console.error('panelist_note_delete', e); return historyErrorKey(e) }
    await reload()
    return null
  }, [reload])

  return { data, events, loading, loadingMore, error, hasMore: !!data?.next, loadMore, addNote, deleteNote, reload }
}
