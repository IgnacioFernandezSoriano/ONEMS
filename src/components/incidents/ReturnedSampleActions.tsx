import { useEffect, useMemo, useState } from 'react'
import { addDays, format, parseISO, startOfWeek } from 'date-fns'
import type { ReportedIncidentDetail } from '@/lib/types'
import { BTN_PRIMARY, BTN_SECONDARY } from './buttonStyles'

interface TFn {
  (key: string, params?: Record<string, any>, fallback?: string): string
}

type NodeOption = { node_id: string; auto_id: string; city_name: string; panelist_name: string }

const errMsg = (t: TFn, e: any) => `${t('common.error')}: ${e?.message ?? String(e)}`

const REASONS = ['not_found', 'not_in_cell', 'not_pending', 'sample_not_movable', 'has_incident_line',
  'other_city', 'inactive_node', 'other_end', 'no_day']

type Reroute = (detailId: string, toNodeId: string, weekStart: string) => Promise<Record<string, any>>

export function ReturnedSampleActions({ detail, busy, onCancel, onReroute, listNodesForMove, suggestRerouteReturnedSample, t }: {
  detail: ReportedIncidentDetail['detail']
  busy: boolean
  onCancel: () => Promise<unknown>
  onReroute: (toNodeId: string, weekStart: string) => Promise<unknown>
  listNodesForMove: (detailId: string) => Promise<NodeOption[]>
  suggestRerouteReturnedSample: Reroute
  t: TFn
}) {
  const detailId = detail?.id
  const [nodes, setNodes] = useState<NodeOption[] | null>(null)
  const [toNode, setToNode] = useState('')
  const weeks = useMemo(() => {
    const monday = startOfWeek(new Date(), { weekStartsOn: 1 })
    return Array.from({ length: 8 }, (_, k) => addDays(monday, 7 * k))
  }, [])
  const [week, setWeek] = useState(() => format(weeks[0], 'yyyy-MM-dd'))
  const [preview, setPreview] = useState<Record<string, any> | null>(null)
  const [checking, setChecking] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!detailId) return
    let alive = true
    listNodesForMove(detailId)
      .then(r => { if (alive) setNodes(r) })
      .catch(e => { if (alive) { setNodes([]); setError(errMsg(t, e)) } })
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [detailId, listNodesForMove])

  useEffect(() => {
    if (!detailId || !toNode) { setPreview(null); setChecking(false); return }
    let alive = true
    setChecking(true); setPreview(null); setError(null)
    suggestRerouteReturnedSample(detailId, toNode, week)
      .then(r => { if (alive) setPreview(r) })
      .catch(e => { if (alive) setError(errMsg(t, e)) })
      .finally(() => { if (alive) setChecking(false) })
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [detailId, toNode, week, suggestRerouteReturnedSample])

  if (!detail) return <p className="text-sm text-gray-500">{t('reported_incidents.returned.no_detail')}</p>

  if (detail.status !== 'sent' && detail.status !== 'incident') {
    return (
      <p className="text-sm text-gray-500">
        {t('reported_incidents.returned.not_returnable')}: <span className="font-mono">{detail.status}</span>
      </p>
    )
  }

  const found = preview?.found === true
  const doReroute = async () => {
    const ok = await onReroute(toNode, week)
    if (ok === true) { setPreview(null); setToNode('') }
  }
  const doCancel = async () => {
    if (!confirm(t('reported_incidents.returned.cancel_confirm'))) return
    await onCancel()
  }
  const reasonKey = (r: unknown) =>
    typeof r === 'string' && REASONS.includes(r)
      ? `reported_incidents.returned.reason.${r}`
      : 'reported_incidents.returned.reason.unknown'

  return (
    <div className="space-y-3">
      <h4 className="font-medium">{t('reported_incidents.returned.title')}</h4>
      {nodes && nodes.length === 0 ? (
        <p className="text-sm text-gray-500">{t('reported_incidents.returned.no_nodes')}</p>
      ) : (
        <div className="flex flex-wrap gap-3">
          <label className="text-sm">
            <span className="block mb-1">{t('reported_incidents.returned.to_node')}</span>
            <select className="border rounded p-2 text-sm" value={toNode} onChange={e => setToNode(e.target.value)}>
              <option value="" />
              {(nodes ?? []).map(n => (
                <option key={n.node_id} value={n.node_id}>{`${n.auto_id} — ${n.city_name} (${n.panelist_name})`}</option>
              ))}
            </select>
          </label>
          <label className="text-sm">
            <span className="block mb-1">{t('reported_incidents.returned.week')}</span>
            <select className="border rounded p-2 text-sm" value={week} onChange={e => setWeek(e.target.value)}>
              {weeks.map(w => (
                <option key={w.getTime()} value={format(w, 'yyyy-MM-dd')}>{format(w, 'dd/MM')}</option>
              ))}
            </select>
          </label>
        </div>
      )}
      {checking && <p className="text-sm text-gray-500">…</p>}
      {error && <p className="text-sm text-red-600">{error}</p>}
      {preview && (
        <p className={`text-sm ${found ? 'text-green-700' : 'text-red-600'}`}>
          {found
            ? t('reported_incidents.returned.fits', {
                date: format(parseISO(String(preview.date)), 'dd/MM/yyyy'),
                load: String(preview.load_after ?? '-'),
              })
            : t(reasonKey(preview.reason))}
        </p>
      )}
      <div className="flex gap-2">
        <button disabled={busy || checking || !found || !toNode} className={BTN_PRIMARY}
          onClick={doReroute}>
          {t('reported_incidents.returned.confirm_reroute')}
        </button>
        <button disabled={busy} className={BTN_SECONDARY} onClick={doCancel}>
          {t('reported_incidents.action.cancel_shipment')}
        </button>
      </div>
    </div>
  )
}
