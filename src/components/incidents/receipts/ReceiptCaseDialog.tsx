import { useEffect } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { CaseAnalysisPanel } from '@/components/incidents/CaseAnalysisPanel'
import { IncidentConversation } from '@/components/incidents/IncidentConversation'
import type { ReceiptCase } from '@/lib/types'

interface Props {
  c: ReceiptCase
  onDone: () => void
}

// Modal del caso de recepcion: analisis del agente y conversacion con el panelista.
// rpc_receipt_cases no devuelve panelist_id, asi que la conversacion se abre sin el (undefined).
export function ReceiptCaseDialog({ c, onDone }: Props) {
  const { t } = useTranslation()
  const panelistId = (c as ReceiptCase & { panelist_id?: string | null }).panelist_id ?? undefined

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onDone() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onDone])

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" onClick={onDone}>
      <div className="bg-white rounded-lg shadow-xl w-full max-w-3xl p-6 max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}
        role="dialog" aria-modal="true" aria-labelledby="receipt-case-title">
        <h3 id="receipt-case-title" className="text-lg font-bold mb-3">{t('receipt_errors.case_dialog_title', { tag: c.tag_raw })}</h3>
        <CaseAnalysisPanel kind="receipt" incidentId={c.id} />
        <IncidentConversation kind="receipt" incidentId={c.id} incidentPanelistId={panelistId} />
        <div className="flex justify-end mt-4">
          <button onClick={onDone} className="px-4 py-2 text-sm border rounded">{t('common.cancel')}</button>
        </div>
      </div>
    </div>
  )
}
