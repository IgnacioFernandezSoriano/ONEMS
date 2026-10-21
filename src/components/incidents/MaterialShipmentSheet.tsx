import { useCallback, useEffect, useRef, useState } from 'react'
import { format, isValid, parseISO } from 'date-fns'
import { supabase } from '@/lib/supabase'
import { downloadCSV, printPDF } from '@/lib/exportUtils'
import { BTN_SECONDARY } from './buttonStyles'

type TFn = (key: string, params?: Record<string, any>, fallback?: string) => string

interface Line {
  key: string
  shipmentId: string
  isCentral: boolean
  status: string
  origin: string
  destination: string
  code: string
  material: string
  sent: number
  received: number
  due: string
}

const k = (s: string) => `material_sheet.${s}`
const DASH = '—'
const PANELIST_COLS = 'id, name, panelist_code, address_line1, address_line2, address_city, address_country, mobile, node_id'

// Neutraliza formulas de hoja de calculo (CSV injection) en celdas de texto
const safeCell = (v: string) => (/^[=+@-]/.test(v) || v.charCodeAt(0) === 9 || v.charCodeAt(0) === 13 ? `'${v}` : v)
const escapeHtml = (v: unknown) =>
  String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')

const fmtDate = (d: string | null | undefined) => {
  if (!d) return DASH
  const p = parseISO(d)
  return isValid(p) ? format(p, 'dd/MM/yyyy') : DASH
}

function describe(p: any, nodes: Record<string, string>): string {
  const addr = [p.address_line1, p.address_line2, p.address_city, p.address_country].filter(Boolean).join(', ')
  const node = p.node_id ? nodes[p.node_id] : ''
  return [p.name, node, addr || DASH, p.mobile || DASH].filter(Boolean).join(' · ')
}

export function MaterialShipmentSheet({ incidentId, accountId, onChanged, t }: {
  incidentId: string
  accountId: string
  onChanged: () => Promise<void> | void
  t: TFn
}) {
  const [lines, setLines] = useState<Line[] | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const inFlight = useRef(false)

  const load = useCallback(async () => {
    const { data: ships, error: e1 } = await supabase.from('material_shipments')
      .select('id, status, expected_date, panelist_id, source_panelist_id, created_at')
      .eq('panelist_incident_id', incidentId).eq('account_id', accountId).order('created_at')
    if (e1) throw e1
    const sh = ships ?? []
    if (sh.length === 0) { setLines([]); return }
    const { data: items, error: e2 } = await supabase.from('material_shipment_items')
      .select('id, material_shipment_id, material_id, quantity_sent, quantity_received')
      .in('material_shipment_id', sh.map((s: any) => s.id)).eq('account_id', accountId)
    if (e2) throw e2
    const matIds = Array.from(new Set((items ?? []).map((i: any) => i.material_id)))
    const panIds = Array.from(new Set(sh.flatMap((s: any) => [s.panelist_id, s.source_panelist_id]).filter(Boolean)))
    const [mats, pans] = await Promise.all([
      matIds.length
        ? supabase.from('material_catalog').select('id, code, name').eq('account_id', accountId).in('id', matIds)
        : Promise.resolve({ data: [] as any[], error: null }),
      supabase.from('panelists').select(PANELIST_COLS).eq('account_id', accountId).in('id', panIds)
    ])
    if (mats.error) throw mats.error
    if (pans.error) throw pans.error
    const nodeIds = Array.from(new Set((pans.data ?? []).map((p: any) => p.node_id).filter(Boolean)))
    const nodes: Record<string, string> = {}
    if (nodeIds.length) {
      const { data: nd, error: e3 } = await supabase.from('nodes').select('id, auto_id').eq('account_id', accountId).in('id', nodeIds)
      if (e3) throw e3
      ;(nd ?? []).forEach((n: any) => { nodes[n.id] = n.auto_id })
    }
    const matMap: Record<string, any> = {}
    ;(mats.data ?? []).forEach((r: any) => { matMap[r.id] = r })
    const panMap: Record<string, string> = {}
    ;(pans.data ?? []).forEach((p: any) => { panMap[p.id] = describe(p, nodes) })

    const out: Line[] = []
    sh.forEach((s: any) => {
      const origin = s.source_panelist_id ? (panMap[s.source_panelist_id] ?? DASH) : t(k('central_warehouse'))
      const destination = panMap[s.panelist_id] ?? DASH
      ;(items ?? []).filter((i: any) => i.material_shipment_id === s.id).forEach((i: any) => {
        const mat = matMap[i.material_id]
        out.push({
          key: i.id, shipmentId: s.id, isCentral: !s.source_panelist_id, status: s.status ?? 'pending',
          origin, destination, code: mat?.code ?? DASH, material: mat?.name ?? DASH,
          sent: Number(i.quantity_sent) || 0, received: Number(i.quantity_received) || 0, due: fmtDate(s.expected_date)
        })
      })
    })
    setLines(out)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [incidentId, accountId])

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { load().catch(e => setError(`${t('common.error')}: ${e?.message ?? String(e)}`)) }, [load])

  if (!lines || lines.length === 0) {
    return error ? <p className="text-sm text-red-600">{error}</p> : null
  }

  const statusLabel = (s: string) => t(k(`status.${s}`), undefined, s)
  const qtyText = (l: Line) => (l.received > 0 ? `${l.sent} (${t(k('received_of'), { received: l.received, sent: l.sent })})` : String(l.sent))

  const markSent = async (id: string) => {
    if (inFlight.current) return
    if (!confirm(t(k('confirm_mark_sent')))) return
    inFlight.current = true
    setBusy(true); setError(null)
    try {
      const { error: e } = await supabase.rpc('send_material_shipment', { p_shipment_id: id })
      if (e) throw e
      await load()
      await onChanged()
    } catch (e: any) { setError(`${t('common.error')}: ${e?.message ?? String(e)}`) }
    finally { inFlight.current = false; setBusy(false) }
  }

  const exportCsv = () => {
    downloadCSV(lines.map(l => ({
      [t(k('col.origin'))]: safeCell(l.origin),
      [t(k('col.destination'))]: safeCell(l.destination),
      [t(k('col.material'))]: safeCell(`${l.code} - ${l.material}`),
      [t(k('col.quantity'))]: safeCell(qtyText(l)),
      [t(k('col.due'))]: safeCell(l.due),
      [t(k('col.status'))]: safeCell(statusLabel(l.status))
    })), `material-shipments-${format(new Date(), 'yyyyMMdd')}.csv`)
  }

  const COLS = ['origin', 'destination', 'material', 'quantity', 'due', 'status']

  const print = () => {
    const head = COLS.map(c => `<th>${escapeHtml(t(k(`col.${c}`)))}</th>`).join('')
    const body = lines.map(l => `<tr>
      <td>${escapeHtml(l.origin)}</td><td>${escapeHtml(l.destination)}</td>
      <td>${escapeHtml(l.code)} - ${escapeHtml(l.material)}</td><td>${escapeHtml(qtyText(l))}</td>
      <td>${escapeHtml(l.due)}</td><td>${escapeHtml(statusLabel(l.status))}</td></tr>`).join('')
    const dir = document.documentElement.dir === 'rtl' ? 'rtl' : 'ltr'
    const html = `<!DOCTYPE html><html dir="${dir}"><head><meta charset="UTF-8"><title>${escapeHtml(t(k('title')))}</title>
<style>body{font-family:Arial,sans-serif;margin:30px;color:#333}h1{font-size:22px;color:#10b981;border-bottom:3px solid #10b981;padding-bottom:10px}
table{width:100%;border-collapse:collapse;font-size:12px}th{background:#10b981;color:#fff;padding:8px;text-align:start}
td{border-bottom:1px solid #ddd;padding:8px;vertical-align:top}</style></head><body>
<h1>${escapeHtml(t(k('title')))}</h1><p>${escapeHtml(format(new Date(), 'dd/MM/yyyy'))}</p>
<table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></body></html>`
    printPDF(html, 'material-shipments')
  }

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-2 mb-2">
        <h4 className="font-medium">{t(k('title'))}</h4>
        <div className="flex gap-2">
          <button className={BTN_SECONDARY} onClick={print}>{t(k('print'))}</button>
          <button className={BTN_SECONDARY} onClick={exportCsv}>{t(k('download_csv'))}</button>
        </div>
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-gray-600">
              {COLS.map(c => (
                <th key={c} className="text-start py-1 pe-2 font-medium">{t(k(`col.${c}`))}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {lines.map(l => (
              <tr key={l.key} className="border-t align-top">
                <td className="py-1 pe-2">{l.origin}</td>
                <td className="py-1 pe-2">{l.destination}</td>
                <td className="py-1 pe-2">{l.code} - {l.material}</td>
                <td className="py-1 pe-2">{qtyText(l)}</td>
                <td className="py-1 pe-2">{l.due}</td>
                <td className="py-1 pe-2">
                  <div>{statusLabel(l.status)}</div>
                  {l.status === 'pending' && l.isCentral && (
                    <button disabled={busy} className={BTN_SECONDARY} onClick={() => markSent(l.shipmentId)}>{t(k('mark_sent'))}</button>
                  )}
                  {l.status === 'pending' && !l.isCentral && (
                    <p className="text-xs text-gray-500">{t(k('donor_confirms_telegram'))}</p>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
