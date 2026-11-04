import { useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { useReceiptErrors } from '@/lib/hooks/useReceiptErrors'
import { ReceiptDaySummary } from '@/components/incidents/receipts/ReceiptDaySummary'
import { ReceiptRepeatPanelists } from '@/components/incidents/receipts/ReceiptRepeatPanelists'
import { ReceiptCasesTable } from '@/components/incidents/receipts/ReceiptCasesTable'
import { PanelistNoticeDialog } from '@/components/incidents/receipts/PanelistNoticeDialog'
import { BroadcastDialog } from '@/components/incidents/receipts/BroadcastDialog'
import type { ReceiptRepeatPanelist } from '@/lib/types'

const todayStr = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function ReceiptErrors() {
  const { t } = useTranslation()
  const [date, setDate] = useState(todayStr())
  const r = useReceiptErrors(date)
  const [noticeFor, setNoticeFor] = useState<ReceiptRepeatPanelist | null>(null)
  const [showBroadcast, setShowBroadcast] = useState(false)

  return (
    <div className="p-6">
      <div className="flex flex-wrap items-center justify-between gap-3 mb-4">
        <h2 className="text-xl font-bold">{t('receipt_errors.title')}</h2>
        <div className="flex items-center gap-3">
          <input type="date" className="border rounded px-2 py-1 text-sm" value={date} onChange={e => e.target.value && setDate(e.target.value)} />
          <button onClick={() => r.refresh()} className="px-3 py-1 text-sm border rounded">{t('receipt_errors.refresh')}</button>
          <button onClick={() => setShowBroadcast(true)} className="px-3 py-1 text-sm bg-blue-600 text-white rounded">{t('receipt_errors.broadcast_button')}</button>
        </div>
      </div>
      {r.error && <div className="text-red-600 mb-3">{t('common.error')}: {r.error}</div>}
      {r.loading && !r.summary ? <div>{t('common.loading')}</div> : (
        <>
          <ReceiptDaySummary summary={r.summary} trend={r.trend} />
          <ReceiptCasesTable cases={r.openCases} candidates={r.candidates} onFix={r.fixCase} onClose={r.closeCase}
            title={t('receipt_errors.open_cases_title')} />
          <ReceiptRepeatPanelists rows={r.repeaters} onNotice={setNoticeFor} />
          <ReceiptCasesTable cases={r.cases} candidates={r.candidates} onFix={r.fixCase} onClose={r.closeCase} />
        </>
      )}
      {noticeFor && <PanelistNoticeDialog panelist={noticeFor} onSend={r.sendNotice} onClose={() => setNoticeFor(null)} />}
      {showBroadcast && <BroadcastDialog recipients={r.recipients} history={r.history} onBroadcast={r.broadcast} onClose={() => setShowBroadcast(false)} />}
    </div>
  )
}
