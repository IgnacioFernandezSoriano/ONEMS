import { useEffect, useState } from 'react'
import { Info } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { useAccount } from '@/contexts/AccountContext'
import { ReceiptCaseDialog } from './ReceiptCaseDialog'
import { useCaseAnalysisEnabledForAccount } from '@/lib/hooks/useCaseAnalysis'
import type { ReceiptCase, ReceiptCandidateShipment } from '@/lib/types'

interface Props {
  cases: ReceiptCase[]
  candidates: (caseId: string) => Promise<ReceiptCandidateShipment[]>
  onFix: (caseId: string, detailId: string) => Promise<string>
  onClose: (caseId: string, note: string) => Promise<void>
  // Titulo del bloque (por defecto, "Casos"); los casos abiertos de cualquier dia usan su propio bloque.
  title?: string
}

const OPEN_STATUSES = ['pending', 'needs_decision']
// Sin panelista receptor o sin nodo no hay ciudad de la que elegir envio: solo se pueden cerrar.
const NOT_FIXABLE = ['no_panelist', 'no_node']
// Motivos y estado en que deja el caso cada uno (misma regla que public.receipt_outcome_status), en orden de
// "hay que actuar" a "solo informa". wrong_city_cancelled ya no se produce: va al final, para casos antiguos.
const REASON_GUIDE: Array<[string, string]> = [
  ['not_found', 'pending'],
  ['ambiguous_typo', 'needs_decision'],
  ['other_city_tag', 'needs_decision'],
  ['no_panelist', 'needs_decision'],
  ['no_node', 'needs_decision'],
  ['ok_typo_fixed', 'fixed'],
  ['ok_same_city', 'fixed'],
  ['pobox_absent_no_visit', 'compensated'],
  ['pobox_absent_unavailable', 'compensated'],
  ['not_sent_cancelled', 'compensated'],
  ['already_received', 'informative'],
  ['blocked', 'informative'],
  ['invalid_format', 'informative'],
  ['wrong_city_cancelled', 'compensated'],
]

export function ReceiptCasesTable({ cases, candidates, onFix, onClose, title }: Props) {
  const { t } = useTranslation()
  const { effectiveAccountId } = useAccount()
  const analysisEnabled = useCaseAnalysisEnabledForAccount(effectiveAccountId)
  const [statusFilter, setStatusFilter] = useState<string>('all')
  const [fixing, setFixing] = useState<ReceiptCase | null>(null)
  const [closing, setClosing] = useState<ReceiptCase | null>(null)
  const [analyzing, setAnalyzing] = useState<ReceiptCase | null>(null)
  const [showGuide, setShowGuide] = useState(false)

  const rows = cases.filter(c => statusFilter === 'all' || c.status === statusFilter)
  const th = 'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase'
  const STATUSES = ['fixed', 'compensated', 'informative', 'pending', 'needs_decision', 'discarded']

  return (
    <div className="bg-white rounded-lg shadow overflow-hidden mb-6">
      <div className="flex items-center justify-between px-6 pt-4">
        <h3 className="font-semibold">{title ?? t('receipt_errors.cases_title')}</h3>
        <select className="border rounded px-2 py-1 text-sm" value={statusFilter} onChange={e => setStatusFilter(e.target.value)}>
          <option value="all">{t('receipt_errors.filter_all')}</option>
          {STATUSES.map(s => <option key={s} value={s}>{t(`receipt_errors.status.${s}`)}</option>)}
        </select>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-gray-50 border-b">
            <tr>
              <th className={th}>{t('receipt_errors.col.date')}</th>
              <th className={th}>{t('receipt_errors.col.panelist')}</th>
              <th className={th}>{t('receipt_errors.col.tag')}</th>
              <th className={th}>
                <span className="inline-flex items-center gap-1">
                  {t('receipt_errors.col.reason')}
                  <button type="button" onClick={() => setShowGuide(true)} title={t('receipt_errors.reason_guide.open')}
                    aria-label={t('receipt_errors.reason_guide.open')} className="text-gray-400 hover:text-blue-600">
                    <Info className="w-4 h-4" />
                  </button>
                </span>
              </th>
              <th className={th}>{t('receipt_errors.col.status')}</th>
              <th className={th}>{t('receipt_errors.col.attempts')}</th>
              <th className={th}>{t('receipt_errors.col.culprit')}</th>
              <th className={th}></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {rows.length > 0 ? rows.map(c => (
              <tr key={c.id} className="hover:bg-gray-50">
                <td className="px-6 py-3 text-sm whitespace-nowrap">{c.first_attempt_at.slice(0, 16).replace('T', ' ')}</td>
                <td className="px-6 py-3 text-sm">{c.panelist_name ?? '-'}</td>
                <td className="px-6 py-3 text-sm font-mono">{c.tag_raw}</td>
                <td className="px-6 py-3 text-sm">{t(`receipt_errors.reason.${c.reason}`)}</td>
                <td className="px-6 py-3 text-sm">{t(`receipt_errors.status.${c.status}`)}</td>
                <td className="px-6 py-3 text-sm">{c.attempts}</td>
                <td className="px-6 py-3 text-sm">{c.culprit_name ? `${c.culprit_name} (${t(`receipt_errors.role.${c.culprit_role}`)})` : '-'}</td>
                <td className="px-6 py-3 text-sm whitespace-nowrap">
                  {analysisEnabled === true && (
                    <button onClick={() => setAnalyzing(c)} className="text-blue-600 hover:text-blue-800 me-3">{t('receipt_errors.analyze')}</button>
                  )}
                  {OPEN_STATUSES.includes(c.status) && (
                    <>
                      {!NOT_FIXABLE.includes(c.reason) && (
                        <button onClick={() => setFixing(c)} className="text-blue-600 hover:text-blue-800 me-3">{t('receipt_errors.fix')}</button>
                      )}
                      <button onClick={() => setClosing(c)} className="text-gray-600 hover:text-gray-900">{t('receipt_errors.close_case')}</button>
                    </>
                  )}
                </td>
              </tr>
            )) : (
              <tr><td colSpan={8} className="px-6 py-4 text-center text-gray-500">{t('receipt_errors.no_cases')}</td></tr>
            )}
          </tbody>
        </table>
      </div>
      {fixing && <FixDialog c={fixing} candidates={candidates} onFix={onFix} onDone={() => setFixing(null)} />}
      {closing && <CloseDialog c={closing} onClose={onClose} onDone={() => setClosing(null)} />}
      {analyzing && <ReceiptCaseDialog c={analyzing} onDone={() => setAnalyzing(null)} />}
      {showGuide && <ReasonGuideDialog onDone={() => setShowGuide(false)} />}
    </div>
  )
}

function FixDialog({ c, candidates, onFix, onDone }: { c: ReceiptCase; candidates: Props['candidates']; onFix: Props['onFix']; onDone: () => void }) {
  const { t } = useTranslation()
  const [list, setList] = useState<ReceiptCandidateShipment[] | null>(null)
  const [pick, setPick] = useState<string>('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let alive = true
    candidates(c.id).then(r => { if (alive) setList(r) }).catch(err => { if (alive) { setList([]); setError(err.message ?? String(err)) } })
    return () => { alive = false }
  }, [c.id, candidates])

  const submit = async () => {
    try { setBusy(true); setError(null); await onFix(c.id, pick); onDone() }
    catch (err: any) { setError(err.message ?? String(err)) }
    finally { setBusy(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg shadow-xl w-full max-w-2xl p-6">
        <h3 className="text-lg font-bold mb-1">{t('receipt_errors.fix_title')}</h3>
        <p className="text-sm text-gray-600 mb-3">{t('receipt_errors.fix_help', { tag: c.tag_raw })}</p>
        <div className="border rounded max-h-72 overflow-y-auto">
          {list === null ? <div className="p-4 text-sm">{t('common.loading')}</div>
            : list.length === 0 ? <div className="p-4 text-sm text-gray-500">{t('receipt_errors.fix_no_candidates')}</div>
            : (
              <table className="w-full text-sm">
                <thead className="bg-gray-50"><tr>
                  <th className="px-3 py-2"></th>
                  <th className="px-3 py-2 text-left text-xs text-gray-500 uppercase">{t('receipt_errors.col.tag')}</th>
                  <th className="px-3 py-2 text-left text-xs text-gray-500 uppercase">{t('receipt_errors.col.origin_panelist')}</th>
                  <th className="px-3 py-2 text-left text-xs text-gray-500 uppercase">{t('receipt_errors.col.date')}</th>
                </tr></thead>
                <tbody className="divide-y">
                  {list.map(s => (
                    <tr key={s.id} className={pick === s.id ? 'bg-blue-50' : 'hover:bg-gray-50'} onClick={() => setPick(s.id)}>
                      <td className="px-3 py-2"><input type="radio" name="candidate" checked={pick === s.id} onChange={() => setPick(s.id)} /></td>
                      <td className="px-3 py-2 font-mono">{s.tag_id ?? '-'}</td>
                      <td className="px-3 py-2">{s.origin_panelist_name ?? '-'}</td>
                      <td className="px-3 py-2">{s.fecha_programada}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
        </div>
        {error && <div className="text-sm text-red-600 mt-2">{t('receipt_errors.error_generic')}: {error}</div>}
        <div className="flex justify-end gap-2 mt-4">
          <button onClick={onDone} className="px-4 py-2 text-sm border rounded">{t('common.cancel')}</button>
          <button onClick={submit} disabled={!pick || busy} className="px-4 py-2 text-sm bg-blue-600 text-white rounded disabled:opacity-50">{t('receipt_errors.fix_confirm')}</button>
        </div>
      </div>
    </div>
  )
}

function CloseDialog({ c, onClose, onDone }: { c: ReceiptCase; onClose: Props['onClose']; onDone: () => void }) {
  const { t } = useTranslation()
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async () => {
    try { setBusy(true); setError(null); await onClose(c.id, note); onDone() }
    catch (err: any) { setError(err.message ?? String(err)) }
    finally { setBusy(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg shadow-xl w-full max-w-lg p-6">
        <h3 className="text-lg font-bold mb-1">{t('receipt_errors.close_title')}</h3>
        <p className="text-sm text-gray-600 mb-3">{t('receipt_errors.close_help', { tag: c.tag_raw })}</p>
        <textarea className="w-full border rounded p-2 text-sm h-24" value={note} placeholder={t('receipt_errors.close_note')} onChange={e => setNote(e.target.value)} />
        {error && <div className="text-sm text-red-600 mt-2">{t('receipt_errors.error_generic')}: {error}</div>}
        <div className="flex justify-end gap-2 mt-4">
          <button onClick={onDone} className="px-4 py-2 text-sm border rounded">{t('common.cancel')}</button>
          <button onClick={submit} disabled={busy} className="px-4 py-2 text-sm bg-gray-800 text-white rounded disabled:opacity-50">{t('receipt_errors.close_confirm')}</button>
        </div>
      </div>
    </div>
  )
}

function ReasonGuideDialog({ onDone }: { onDone: () => void }) {
  const { t } = useTranslation()
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onDone() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onDone])
  const tone: Record<string, string> = {
    pending: 'bg-amber-100 text-amber-800',
    needs_decision: 'bg-red-100 text-red-700',
    fixed: 'bg-blue-100 text-blue-700',
    compensated: 'bg-orange-100 text-orange-700',
    informative: 'bg-gray-100 text-gray-700',
  }
  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" onClick={onDone}>
      <div className="bg-white rounded-lg shadow-xl w-full max-w-3xl p-6 max-h-[85vh] flex flex-col" onClick={e => e.stopPropagation()}
        role="dialog" aria-modal="true" aria-labelledby="reason-guide-title">
        <h3 id="reason-guide-title" className="text-lg font-bold mb-1">{t('receipt_errors.reason_guide.title')}</h3>
        <p className="text-sm text-gray-600 mb-3">{t('receipt_errors.reason_guide.intro')}</p>
        <div className="overflow-y-auto border rounded divide-y">
          {REASON_GUIDE.map(([reason, status]) => (
            <div key={reason} className="px-4 py-3">
              <div className="flex flex-wrap items-center gap-2 mb-1">
                <span className="font-medium text-sm">{t(`receipt_errors.reason.${reason}`)}</span>
                <span className={`text-xs px-2 py-0.5 rounded-full ${tone[status] ?? tone.informative}`}>{t(`receipt_errors.status.${status}`)}</span>
              </div>
              <p className="text-sm text-gray-600">{t(`receipt_errors.reason_help.${reason}`)}</p>
            </div>
          ))}
        </div>
        <div className="flex justify-end mt-4">
          <button onClick={onDone} className="px-4 py-2 text-sm border rounded">{t('receipt_errors.reason_guide.close')}</button>
        </div>
      </div>
    </div>
  )
}
