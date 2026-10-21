import { useEffect, useRef, useState } from 'react'
import { format, isValid, parseISO } from 'date-fns'
import { useTranslation } from '@/hooks/useTranslation'
import { useIncidentConversation } from '@/lib/hooks/useIncidentConversation'
import type { ConversationKind, IncidentMessage } from '@/lib/hooks/useIncidentConversation'
import { BTN_PRIMARY } from './buttonStyles'

function fmtTime(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = parseISO(iso)
  return isValid(d) ? format(d, 'dd/MM HH:mm') : ''
}

export function IncidentConversation({ kind, incidentId }: { kind: ConversationKind; incidentId: string }) {
  const { t } = useTranslation()
  const { messages, loading, error, send } = useIncidentConversation(kind, incidentId)
  const [text, setText] = useState('')
  const [sending, setSending] = useState(false)
  const [sendError, setSendError] = useState<string | null>(null)
  const listRef = useRef<HTMLDivElement>(null)
  const nearBottom = useRef(true)

  useEffect(() => {
    const el = listRef.current
    if (el && nearBottom.current) el.scrollTop = el.scrollHeight
  }, [messages])

  const onScroll = () => {
    const el = listRef.current
    if (el) nearBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80
  }

  const doSend = async () => {
    const body = text.trim()
    if (!body || sending) return
    setSending(true); setSendError(null)
    try {
      await send(body)
      setText('')
      nearBottom.current = true
    } catch (e: any) {
      const m: string = e?.message ?? String(e)
      // Sin Telegram: solo el aviso traducido (sin el texto tecnico en ingles)
      setSendError(m.includes('panelist has no telegram') ? t('incident_conversation.no_telegram') : t('common.error') + ': ' + m)
    } finally { setSending(false) }
  }

  const statusIcon = (m: IncidentMessage) => {
    if (m.status === 'pending_send') return <span title={t('incident_conversation.status.pending_send')}>⏳</span>
    if (m.status === 'sent') return <span title={t('incident_conversation.status.sent')}>✓</span>
    if (m.status === 'failed') return <span title={m.error || t('incident_conversation.status.failed')}>⚠</span>
    return null
  }

  const renderMessage = (m: IncidentMessage) => {
    const time = fmtTime(m.sent_at || m.created_at)
    if (m.direction === 'internal') {
      return (
        <div key={m.id} className="text-center text-xs text-gray-500 my-1">
          {m.body} <span className="text-gray-400">{time}</span>
        </div>
      )
    }
    const mine = m.direction === 'outbound'
    const callback = m.meta && typeof m.meta === 'object' ? m.meta.callback : null
    return (
      <div key={m.id} className={`flex ${mine ? 'justify-end' : 'justify-start'} my-1`}>
        <div className={`max-w-[80%] rounded-lg px-3 py-2 text-sm text-start ${mine ? 'bg-blue-50 border border-blue-200' : 'bg-gray-100 border border-gray-200'}`}>
          <div className="text-xs font-medium text-gray-600 mb-0.5">{t(`incident_conversation.author.${m.author}`)}</div>
          <div className="whitespace-pre-wrap break-words">{m.body}</div>
          {callback != null && callback !== '' && (
            <span className="inline-block mt-1 px-2 py-0.5 text-xs rounded-full bg-white border border-gray-300 text-gray-700">
              {t('incident_conversation.button_pressed')}: {String(callback)}
            </span>
          )}
          <div className="flex items-center gap-1 justify-end text-xs text-gray-500 mt-1">
            <span>{time}</span>
            {mine && statusIcon(m)}
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="border rounded p-4 mt-4 max-w-3xl">
      <h4 className="text-sm font-semibold mb-2">{t('incident_conversation.title')}</h4>
      <div ref={listRef} onScroll={onScroll} className="max-h-80 overflow-y-auto mb-3">
        {loading && messages.length === 0 ? (
          <p className="text-sm text-gray-500">{t('common.loading')}</p>
        ) : messages.length === 0 ? (
          <p className="text-sm text-gray-500">{t('incident_conversation.empty')}</p>
        ) : messages.map(renderMessage)}
      </div>
      {error && <p className="text-xs text-red-600 mb-2">{t('common.error')}: {error}</p>}
      <textarea
        className="w-full border rounded p-2 text-sm mb-2"
        rows={2}
        value={text}
        placeholder={t('incident_conversation.placeholder')}
        onChange={e => setText(e.target.value)}
        onKeyDown={e => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); doSend() } }}
      />
      {sendError && <p className="text-xs text-red-600 mb-2">{sendError}</p>}
      <button type="button" className={BTN_PRIMARY} disabled={sending || !text.trim()} onClick={doSend}>
        {sending ? t('incident_conversation.sending') : t('incident_conversation.send')}
      </button>
    </div>
  )
}
