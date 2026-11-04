import { useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { receiptNoticeTemplates, normalizeNoticeLang } from '@/lib/receiptNoticeTemplates'
import type { ReceiptRepeatPanelist } from '@/lib/types'

interface Props {
  panelist: ReceiptRepeatPanelist
  onSend: (panelistId: string, body: string) => Promise<void>
  onClose: () => void
}

export function PanelistNoticeDialog({ panelist, onSend, onClose }: Props) {
  const { t } = useTranslation()
  const lang = normalizeNoticeLang(panelist.language)
  const tpl = panelist.top_reason ? receiptNoticeTemplates[panelist.top_reason] : undefined
  const [body, setBody] = useState(tpl?.[lang] ?? '')
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const send = async () => {
    try {
      setSending(true); setError(null)
      await onSend(panelist.panelist_id, body)
      onClose()
    } catch (err: any) { setError(err.message ?? String(err)) }
    finally { setSending(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg shadow-xl w-full max-w-xl p-6">
        <h3 className="text-lg font-bold mb-1">{t('receipt_errors.notice_title')}</h3>
        <p className="text-sm text-gray-600 mb-3">{panelist.name} ({panelist.panelist_code}) - {t('receipt_errors.notice_language')}: {lang.toUpperCase()}</p>
        <textarea className="w-full border rounded p-2 text-sm h-48" dir={lang === 'ar' ? 'rtl' : 'ltr'} value={body} maxLength={3000} onChange={e => setBody(e.target.value)} />
        {error && <div className="text-sm text-red-600 mt-2">{t('receipt_errors.error_generic')}: {error}</div>}
        <div className="flex justify-end gap-2 mt-4">
          <button onClick={onClose} className="px-4 py-2 text-sm border rounded">{t('common.cancel')}</button>
          <button onClick={send} disabled={sending || !body.trim()} className="px-4 py-2 text-sm bg-blue-600 text-white rounded disabled:opacity-50">{t('receipt_errors.send')}</button>
        </div>
      </div>
    </div>
  )
}
