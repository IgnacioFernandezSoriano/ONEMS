import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { HelpCircle } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { usePermissions } from '@/contexts/PermissionsContext'
import { ReadOnlyBadge } from '@/components/common/ReadOnlyBadge'
import { useReceiptErrors } from '@/lib/hooks/useReceiptErrors'
import { ReceiptDaySummary } from '@/components/incidents/receipts/ReceiptDaySummary'
import { ReceiptRepeatPanelists } from '@/components/incidents/receipts/ReceiptRepeatPanelists'
import { ReceiptCasesTable } from '@/components/incidents/receipts/ReceiptCasesTable'
import { PanelistNoticeDialog } from '@/components/incidents/receipts/PanelistNoticeDialog'
import { BroadcastDialog } from '@/components/incidents/receipts/BroadcastDialog'
import { ReceiptCaseDialog } from '@/components/incidents/receipts/ReceiptCaseDialog'
import { supabase } from '@/lib/supabase'
import type { ReceiptCase, ReceiptRepeatPanelist } from '@/lib/types'

const todayStr = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function ReceiptErrors() {
  const { t } = useTranslation()
  const { canEdit } = usePermissions()
  const readOnly = !canEdit('receipts')
  const [date, setDate] = useState(todayStr())
  const r = useReceiptErrors(date)
  const [noticeFor, setNoticeFor] = useState<ReceiptRepeatPanelist | null>(null)
  const [showBroadcast, setShowBroadcast] = useState(false)
  const [params, setParams] = useSearchParams()
  const [linkedCase, setLinkedCase] = useState<ReceiptCase | null>(null)

  // Abre un caso concreto si llega por URL (?case=<id>, desde el historial del panelista), sea del dia que sea.
  // Si no existe o es de otra cuenta (RLS) no se abre nada; el parametro se limpia siempre.
  const linkedId = params.get('case')
  useEffect(() => {
    if (!linkedId) return
    let alive = true
    supabase.from('receipt_case')
      .select('id, tag_raw, tag_norm, reason, status, attempts, first_attempt_at, detail_id, culprit_role, resolved_at')
      .eq('id', linkedId).maybeSingle()
      .then(({ data, error }) => {
        if (!alive) return
        if (!error && data) {
          setLinkedCase({ ...(data as any), panelist_name: null, culprit_name: null, resolved_by_name: null })
        }
        setParams({}, { replace: true })
      })
    return () => { alive = false }
  }, [linkedId, setParams])

  return (
    <div className="p-6">
      <div className="flex flex-wrap items-center justify-between gap-3 mb-4">
        <h2 className="text-xl font-bold">{t('receipt_errors.title')} {readOnly && <ReadOnlyBadge />}</h2>
        <div className="flex items-center gap-3">
          <Link to="/help-center?doc=receipt-errors" className="inline-flex items-center gap-1 text-sm text-blue-600 hover:text-blue-800">
            <HelpCircle className="w-4 h-4" />{t('receipt_errors.help_link')}
          </Link>
          <input type="date" className="border rounded px-2 py-1 text-sm" value={date} onChange={e => e.target.value && setDate(e.target.value)} />
          <button onClick={() => r.refresh()} className="px-3 py-1 text-sm border rounded">{t('receipt_errors.refresh')}</button>
          {!readOnly && <button onClick={() => setShowBroadcast(true)} className="px-3 py-1 text-sm bg-blue-600 text-white rounded">{t('receipt_errors.broadcast_button')}</button>}
        </div>
      </div>
      {r.error && <div className="text-red-600 mb-3">{t('common.error')}: {r.error}</div>}
      {r.loading && !r.summary ? <div>{t('common.loading')}</div> : (
        <>
          <ReceiptDaySummary summary={r.summary} trend={r.trend} />
          <ReceiptCasesTable cases={r.openCases} candidates={r.candidates} onFix={r.fixCase} onClose={r.closeCase}
            title={t('receipt_errors.open_cases_title')} readOnly={readOnly} />
          <ReceiptRepeatPanelists rows={r.repeaters} onNotice={setNoticeFor} readOnly={readOnly} />
          <ReceiptCasesTable cases={r.cases} candidates={r.candidates} onFix={r.fixCase} onClose={r.closeCase} readOnly={readOnly} />
        </>
      )}
      {noticeFor && <PanelistNoticeDialog panelist={noticeFor} onSend={r.sendNotice} onClose={() => setNoticeFor(null)} />}
      {linkedCase && <ReceiptCaseDialog c={linkedCase} onDone={() => setLinkedCase(null)} readOnly={readOnly} />}
      {showBroadcast && <BroadcastDialog recipients={r.recipients} history={r.history} onBroadcast={r.broadcast} onClose={() => setShowBroadcast(false)} />}
    </div>
  )
}
