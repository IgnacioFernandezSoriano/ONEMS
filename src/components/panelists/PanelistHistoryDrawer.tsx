import { useEffect, useMemo, useState } from 'react'
import { createPortal } from 'react-dom'
import { format, isValid, parseISO } from 'date-fns'
import { X, ExternalLink, Trash2 } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { usePermissions } from '@/contexts/PermissionsContext'
import { usePanelistHistory } from '@/hooks/usePanelistHistory'
import {
  HISTORY_FILTERS, eventTextKey, filterEvents, leaveReasonKey, linkHref, linkOption,
  type HistoryEvent, type HistoryFilter,
} from '@/lib/panelistHistory'

const ICON: Record<HistoryEvent['type'], string> = {
  note: '📝', incident: '📦', gps: '📍', gps_ref: '🏠', receipt: '📨', leave: '🏖️', notice: '📣',
}
const NOTE_MAX = 2000

function fmt(d: string | null | undefined, withTime = false): string {
  if (!d) return '–'
  const p = parseISO(d)
  return isValid(p) ? format(p, withTime ? 'dd/MM/yyyy HH:mm' : 'dd/MM/yyyy') : '–'
}

/** Panel lateral con el historial del panelista (spec 2026-11-24 §5.3). Se cierra con ✕ o Esc. */
export function PanelistHistoryDrawer({ panelistId, onClose }: { panelistId: string; onClose: () => void }) {
  const { t } = useTranslation()
  const { canView } = usePermissions()
  const h = usePanelistHistory(panelistId)
  const [filter, setFilter] = useState<HistoryFilter>('all')
  const [note, setNote] = useState('')
  const [saving, setSaving] = useState(false)
  const [noteError, setNoteError] = useState<string | null>(null)

  // Esc cierra solo el historial: se escucha en captura y se corta, para que el diálogo de debajo
  // (p. ej. el caso de recepción, que también escucha Esc en window) siga abierto.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return
      e.stopImmediatePropagation()
      onClose()
    }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [onClose])

  const shown = useMemo(() => filterEvents(h.events, filter), [h.events, filter])
  const p = h.data?.panelist
  const s = h.data?.stats

  const save = async () => {
    const body = note.trim()
    if (!body || body.length > NOTE_MAX) { setNoteError('panelist_history.error.note_length'); return }
    setSaving(true); setNoteError(null)
    const err = await h.addNote(body)
    setSaving(false)
    if (err) setNoteError(err); else setNote('')
  }

  const remove = async (id: string) => {
    if (!window.confirm(t('panelist_history.note.delete_confirm'))) return
    const err = await h.deleteNote(id)
    if (err) setNoteError(err)
  }

  const detail = (e: HistoryEvent): string => {
    const d = e.data || {}
    switch (e.type) {
      case 'note': return `«${d.body}»${d.author ? ` · ${d.author}` : ''}`
      case 'incident': return [t(`reported_incidents.category.${d.category}`, undefined, d.category), d.description].filter(Boolean).join(' · ')
      case 'gps': return t(`panelist_history.place.${d.place_kind === 'home' ? 'home' : 'pobox'}`)
      case 'receipt': return [t(`receipt_errors.reason.${d.reason}`, undefined, d.reason), d.tag].filter(Boolean).join(' · ')
      case 'leave': return `${fmt(d.start)} – ${fmt(d.end)} · ${t(leaveReasonKey(d.reason), undefined, d.reason)}`
      case 'notice': return d.body ? `«${d.body}»` : ''
      case 'gps_ref': return d.needs_review ? t('panelist_history.ref.needs_review') : ''
    }
  }

  const statusText = (e: HistoryEvent): string | null => {
    if (!e.status) return null
    if (e.type === 'incident' || e.type === 'gps') return t(`reported_incidents.status.${e.status}`, undefined, e.status)
    if (e.type === 'receipt') return t(`receipt_errors.status.${e.status}`, undefined, e.status)
    if (e.type === 'leave') return e.status === 'cancelled' ? t('panelist_history.leave.cancelled')
      : t(`panelist_history.leave.${e.data?.review_status === 'reviewed' ? 'reviewed' : 'pending'}`)
    return null
  }

  // Portal a <body>: no queda atrapado dentro de otros diálogos; los clics no llegan a la fila de detrás.
  return createPortal(
    <div className="fixed inset-0 z-[60] flex justify-end" role="dialog" aria-modal="true"
         aria-label={t('panelist_history.title')} onClick={e => e.stopPropagation()}>
      <div className="absolute inset-0 bg-black/30" onClick={onClose} />
      <aside className="relative h-full w-full md:w-[60%] bg-white shadow-xl overflow-y-auto p-4 md:p-6">
        <div className="flex items-start justify-between gap-2">
          <h2 className="text-lg font-semibold">
            📋 {p ? `${p.code} · ${p.name}` : t('panelist_history.title')}
          </h2>
          <button onClick={onClose} className="p-1 text-gray-500 hover:text-gray-800" aria-label={t('panelist_history.close')}>
            <X className="w-5 h-5" />
          </button>
        </div>

        {h.loading && <p className="text-sm text-gray-500 mt-4">{t('panelist_history.loading')}</p>}
        {h.error && <p className="text-sm text-red-600 mt-4">{t(h.error)}</p>}

        {p && s && (
          <>
            <p className="text-sm text-gray-600 mt-1">
              {[p.city ?? '–', p.node ?? '–', p.pobox ? t('panelist_history.pobox') : null,
                `${t('panelist_history.created')} ${fmt(p.created)}`, p.mobile ? `📞 ${p.mobile}` : null]
                .filter(Boolean).join(' · ')}
            </p>
            <div className="flex flex-wrap gap-2 mt-3 text-xs">
              <span className="bg-gray-100 rounded-full px-2 py-1">{t('panelist_history.stats.sent', { sent: s.sent_30d, scheduled: s.scheduled_30d })}</span>
              <span className="bg-gray-100 rounded-full px-2 py-1">{t('panelist_history.stats.receipt_problems', { n: s.receipt_problems_30d })}</span>
              <span className={`rounded-full px-2 py-1 ${s.gps_said_no_30d ? 'bg-orange-100' : 'bg-gray-100'}`}>{t('panelist_history.stats.gps_no', { n: s.gps_said_no_30d })}</span>
              <span className="bg-gray-100 rounded-full px-2 py-1">{t('panelist_history.stats.leave_days', { n: s.leave_days_year })}</span>
              <span className={`rounded-full px-2 py-1 ${s.ref_needs_review ? 'bg-orange-100' : 'bg-gray-100'}`}>
                {t(p.pobox ? 'panelist_history.stats.pobox_ref' : 'panelist_history.stats.home_ref',
                   { v: t((p.pobox ? s.pobox_ref : s.home_ref) ? 'panelist_history.yes' : 'panelist_history.no') })}
                {s.ref_needs_review ? ` · ${t('panelist_history.ref.needs_review')}` : ''}
              </span>
            </div>

            {h.data?.can_write && (
              <div className="mt-4 bg-gray-50 rounded p-3">
                <textarea value={note} onChange={e => setNote(e.target.value)} rows={2} maxLength={NOTE_MAX}
                          placeholder={t('panelist_history.note.placeholder')}
                          className="w-full border rounded p-2 text-sm" />
                <div className="flex items-center justify-between mt-2">
                  <span className="text-xs text-red-600">{noteError ? t(noteError) : ''}</span>
                  <button onClick={save} disabled={saving || !note.trim()}
                          className="px-3 py-1.5 text-sm rounded bg-blue-600 text-white disabled:opacity-50">
                    {t('panelist_history.note.save')}
                  </button>
                </div>
              </div>
            )}

            <div className="flex flex-wrap gap-1 mt-4 text-sm">
              {HISTORY_FILTERS.map(f => (
                <button key={f} onClick={() => setFilter(f)}
                        className={`px-2 py-1 rounded ${filter === f ? 'bg-gray-800 text-white' : 'bg-gray-100 text-gray-700'}`}>
                  {t(`panelist_history.filter.${f}`)}
                </button>
              ))}
            </div>

            <ol className="mt-3 border-s-2 border-gray-200 ps-3 space-y-3">
              {shown.length === 0 && <li className="text-sm text-gray-500">{t('panelist_history.empty')}</li>}
              {shown.map(e => {
                const st = statusText(e)
                const showLink = e.link && canView(linkOption(e.link))
                return (
                  <li key={e.id} className="text-sm">
                    <div className="flex flex-wrap items-baseline gap-x-2">
                      <span className="text-gray-500 whitespace-nowrap">{fmt(e.at, true)}</span>
                      <span>{ICON[e.type]} <b>{t(eventTextKey(e))}</b></span>
                      {st && <span className="text-xs bg-gray-100 rounded px-1.5">{st}</span>}
                      {showLink && (
                        <a href={linkHref(e.link!)} target="_blank" rel="noopener noreferrer"
                           className="text-blue-600 inline-flex items-center gap-0.5">
                          {t('panelist_history.open')} <ExternalLink className="w-3 h-3" />
                        </a>
                      )}
                      {e.type === 'note' && e.data?.can_delete && (
                        <button onClick={() => remove(e.id)} className="text-gray-400 hover:text-red-600"
                                aria-label={t('panelist_history.note.delete')}>
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      )}
                    </div>
                    {detail(e) && <div className="text-gray-700 break-words">{detail(e)}</div>}
                  </li>
                )
              })}
            </ol>
            {h.hasMore && (
              <button onClick={h.loadMore} disabled={h.loadingMore} className="mt-4 text-sm text-blue-600">
                {h.loadingMore ? t('panelist_history.loading') : t('panelist_history.load_more')}
              </button>
            )}
          </>
        )}
      </aside>
    </div>,
    document.body,
  )
}
