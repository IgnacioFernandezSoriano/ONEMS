import { useState } from 'react'
import { Loader2 } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { useCaseAnalysis } from '@/lib/hooks/useCaseAnalysis'
import type { CaseDraft } from '@/lib/hooks/useCaseAnalysis'
import type { ConversationKind } from '@/lib/hooks/useIncidentConversation'
import { BTN_PRIMARY, BTN_SECONDARY } from './buttonStyles'

const LIKELIHOODS = ['alta', 'media', 'baja']
const ROLES = ['remitente', 'receptor', 'destinatario']

interface Props {
  kind: ConversationKind
  incidentId: string
}

function DraftEditor({ draft, sent, onSend }: {
  draft: CaseDraft
  sent: boolean
  onSend: (draft: CaseDraft, body: string) => Promise<void>
}) {
  const { t } = useTranslation()
  const [body, setBody] = useState(draft.text)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState(false)

  const doSend = async () => {
    if (sending || sent || !body.trim()) return
    setSending(true); setError(false)
    try { await onSend(draft, body.trim()) } catch { setError(true) } finally { setSending(false) }
  }

  return (
    <div className="mb-3">
      <textarea
        className="w-full border rounded p-2 text-sm"
        rows={5}
        dir={draft.language === 'ar' ? 'rtl' : 'ltr'}
        value={body}
        maxLength={3000}
        disabled={sent}
        onChange={e => setBody(e.target.value)}
      />
      {error && <p className="text-xs text-red-600 mb-1">{t('case_analysis.send_error')}</p>}
      {sent ? (
        <span className="text-sm text-green-700">✓ {t('case_analysis.sent')}</span>
      ) : (
        <button type="button" className={BTN_PRIMARY} disabled={sending || !body.trim()} onClick={doSend}>
          {t('case_analysis.send_to', { name: draft.name })}
        </button>
      )}
    </div>
  )
}

export function CaseAnalysisPanel({ kind, incidentId }: Props) {
  const { t } = useTranslation()
  const { state, result, error, start, send, sent } = useCaseAnalysis(kind, incidentId)
  const a = result?.analysis
  const drafts = result?.drafts ?? []
  const nameOf = (id: string) => drafts.find(d => d.panelist_id === id)?.name ?? ''

  const section = (title: string, text: string | null | undefined) => text ? (
    <div className="mb-3">
      <h5 className="text-xs font-semibold text-gray-600 uppercase mb-0.5">{title}</h5>
      <p className="text-sm whitespace-pre-wrap">{text}</p>
    </div>
  ) : null

  return (
    <div className="border rounded p-4 mt-4 max-w-3xl">
      <button type="button" className={BTN_SECONDARY} disabled={state === 'running'} onClick={() => { void start() }}>
        {state === 'running' ? (
          <span className="inline-flex items-center gap-2"><Loader2 className="w-4 h-4 animate-spin" />{t('case_analysis.running')}</span>
        ) : t('case_analysis.button')}
      </button>
      {state === 'failed' && (
        <p className="text-sm text-red-600 mt-2">
          {error === 'agent_timeout' ? t('case_analysis.agent_timeout') : t('case_analysis.failed')}
        </p>
      )}
      {state === 'done' && a && (
        <div className="mt-4">
          {section(t('case_analysis.summary'), a.summary)}
          {section(t('case_analysis.plan'), a.plan)}
          {section(t('case_analysis.reality'), a.reality)}
          {section(t('case_analysis.comparison'), a.comparison)}
          {a.causes?.length > 0 && (
            <div className="mb-3">
              <h5 className="text-xs font-semibold text-gray-600 uppercase mb-0.5">{t('case_analysis.causes')}</h5>
              <ul className="list-disc ps-5 text-sm">
                {a.causes.map((c, i) => (
                  <li key={i}>
                    {c.text} <span className="text-gray-500">- {t('case_analysis.probable_with', { level: LIKELIHOODS.includes(c.likelihood) ? t(`case_analysis.likelihood.${c.likelihood}`) : '' })}</span>
                    {c.evidence && <div className="text-xs text-gray-500">{c.evidence}</div>}
                  </li>
                ))}
              </ul>
            </div>
          )}
          {a.noise?.length > 0 && (
            <div className="mb-3">
              <h5 className="text-xs font-semibold text-gray-600 uppercase mb-0.5">{t('case_analysis.noise')}</h5>
              <ul className="list-disc ps-5 text-sm">{a.noise.map((n, i) => <li key={i}>{n}</li>)}</ul>
            </div>
          )}
          {a.contacts?.length > 0 && (
            <div className="mb-3">
              <h5 className="text-xs font-semibold text-gray-600 uppercase mb-0.5">{t('case_analysis.contacts')}</h5>
              <ul className="list-disc ps-5 text-sm">
                {a.contacts.map((c, i) => (
                  <li key={i}>
                    {ROLES.includes(c.role) ? t(`case_analysis.role.${c.role}`) : ''}{nameOf(c.panelist_id) ? `${ROLES.includes(c.role) ? ': ' : ''}${nameOf(c.panelist_id)}` : ''}
                    {c.why && <span className="text-gray-500"> - {c.why}</span>}
                  </li>
                ))}
              </ul>
            </div>
          )}
          <div className="mb-3">
            <h5 className="text-xs font-semibold text-gray-600 uppercase mb-0.5">{t('case_analysis.improvement')}</h5>
            <p className="text-sm whitespace-pre-wrap">{a.improvement || t('case_analysis.no_improvement')}</p>
          </div>
          {drafts.length > 0 && (
            <div>
              <h5 className="text-xs font-semibold text-gray-600 uppercase mb-1">{t('case_analysis.drafts')}</h5>
              {drafts.map(d => (
                <div key={d.key}>
                  <div className="text-xs text-gray-600 mb-0.5">{t('case_analysis.recipient')}: {d.name} ({d.code})</div>
                  <DraftEditor draft={d} sent={sent.has(d.key)} onSend={send} />
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
