import { useEffect, useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { receiptNoticeTemplates, NOTICE_LANGS, normalizeNoticeLang } from '@/lib/receiptNoticeTemplates'
import type { NoticeLang } from '@/lib/receiptNoticeTemplates'
import type { BroadcastRecipientsByLang, BroadcastHistoryRow } from '@/lib/types'

interface Props {
  recipients: () => Promise<BroadcastRecipientsByLang[]>
  history: () => Promise<BroadcastHistoryRow[]>
  onBroadcast: (bodies: Record<string, string>) => Promise<number>
  onClose: () => void
}

const TEMPLATE_KEYS = ['pobox_daily_visit_lesson', 'pobox_absent_no_visit', 'not_sent_cancelled', 'ok_typo_fixed', 'wrong_city_cancelled']

export function BroadcastDialog({ recipients, history, onBroadcast, onClose }: Props) {
  const { t } = useTranslation()
  const [recips, setRecips] = useState<BroadcastRecipientsByLang[]>([])
  const [hist, setHist] = useState<BroadcastHistoryRow[]>([])
  const [tplKey, setTplKey] = useState(TEMPLATE_KEYS[0])
  const [bodies, setBodies] = useState<Record<string, string>>({ ...receiptNoticeTemplates[TEMPLATE_KEYS[0]] })
  const [tab, setTab] = useState<NoticeLang>('en')
  const [confirming, setConfirming] = useState(false)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [sentCount, setSentCount] = useState<number | null>(null)

  useEffect(() => {
    let alive = true
    ;(async () => {
      try {
        const r = await recipients(); const h = await history()
        if (alive) { setRecips(r); setHist(h) }
      } catch (err: any) { if (alive) setError(err.message ?? String(err)) }
    })()
    return () => { alive = false }
  }, [recipients, history])

  const countFor = (l: NoticeLang) => recips.filter(r => normalizeNoticeLang(r.language) === l).reduce((s, r) => s + r.n, 0)
  const tabs: NoticeLang[] = NOTICE_LANGS.filter(l => l === 'en' || countFor(l) > 0)
  const total = recips.reduce((s, r) => s + r.n, 0)

  const pickTemplate = (k: string) => { setTplKey(k); setBodies({ ...receiptNoticeTemplates[k] }); setConfirming(false) }

  const send = async () => {
    if (sentCount !== null || sending) return
    try {
      setSending(true); setError(null)
      const n = await onBroadcast(bodies)
      setSentCount(n); setConfirming(false)
      setHist(await history())
    } catch (err: any) { setError(err.message ?? String(err)) }
    finally { setSending(false) }
  }

  const th = 'px-3 py-2 text-left text-xs text-gray-500 uppercase'
  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg shadow-xl w-full max-w-3xl p-6 max-h-[90vh] overflow-y-auto">
        <h3 className="text-lg font-bold mb-3">{t('receipt_errors.broadcast_title')}</h3>
        <label className="text-sm text-gray-600">{t('receipt_errors.broadcast_template')}</label>
        <select className="border rounded px-2 py-1 text-sm block mb-3" value={tplKey} onChange={e => pickTemplate(e.target.value)}>
          {TEMPLATE_KEYS.map(k => <option key={k} value={k}>{t(`receipt_errors.template.${k}`)}</option>)}
        </select>
        <div className="flex gap-2 mb-2 border-b">
          {tabs.map(l => (
            <button key={l} onClick={() => setTab(l)} className={`px-3 py-1 text-sm ${tab === l ? 'border-b-2 border-blue-600 font-medium' : 'text-gray-500'}`}>
              {l.toUpperCase()} ({countFor(l)})
            </button>
          ))}
        </div>
        <textarea className="w-full border rounded p-2 text-sm h-56" dir={tab === 'ar' ? 'rtl' : 'ltr'} maxLength={3000}
          value={bodies[tab] ?? ''} onChange={e => { setBodies({ ...bodies, [tab]: e.target.value }); setConfirming(false) }} />
        <p className="text-sm text-gray-600 mt-2">{t('receipt_errors.broadcast_recipients', { count: total })}</p>
        {error && <div className="text-sm text-red-600 mt-2">{t('receipt_errors.error_generic')}: {error}</div>}
        {sentCount !== null && <div className="text-sm text-green-700 mt-2">{t('receipt_errors.broadcast_queued', { count: sentCount })}</div>}
        <div className="flex justify-end gap-2 mt-4">
          <button onClick={onClose} className="px-4 py-2 text-sm border rounded">{t('common.close')}</button>
          {/* Tras un envio correcto no se puede volver a enviar desde este dialogo (se reinicia al reabrirlo). */}
          {sentCount !== null ? null : !confirming
            ? <button onClick={() => setConfirming(true)} disabled={!bodies.en?.trim() || total === 0} className="px-4 py-2 text-sm bg-blue-600 text-white rounded disabled:opacity-50">{t('receipt_errors.send')}</button>
            : <button onClick={send} disabled={sending || sentCount !== null} className="px-4 py-2 text-sm bg-red-600 text-white rounded disabled:opacity-50">{t('receipt_errors.broadcast_confirm', { count: total })}</button>}
        </div>
        <h4 className="font-semibold mt-6 mb-2">{t('receipt_errors.broadcast_history')}</h4>
        <table className="w-full text-sm">
          <thead className="bg-gray-50"><tr>
            <th className={th}>{t('receipt_errors.col.date')}</th>
            <th className={th}>{t('receipt_errors.col.text')}</th>
            <th className={th}>{t('receipt_errors.col.total')}</th>
            <th className={th}>{t('receipt_errors.col.sent')}</th>
            <th className={th}>{t('receipt_errors.col.failed')}</th>
          </tr></thead>
          <tbody className="divide-y">
            {hist.length > 0 ? hist.map(h => (
              <tr key={h.broadcast_id}>
                <td className="px-3 py-2">{h.created_at.slice(0, 16).replace('T', ' ')}</td>
                <td className="px-3 py-2 max-w-xs truncate" title={h.body_en ?? ''}>{h.body_en}</td>
                <td className="px-3 py-2">{h.total}</td><td className="px-3 py-2">{h.sent}</td><td className="px-3 py-2">{h.failed}</td>
              </tr>
            )) : <tr><td colSpan={5} className="px-3 py-3 text-center text-gray-500">{t('receipt_errors.broadcast_no_history')}</td></tr>}
          </tbody>
        </table>
      </div>
    </div>
  )
}
