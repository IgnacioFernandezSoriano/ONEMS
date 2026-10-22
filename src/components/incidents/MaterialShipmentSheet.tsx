import { useCallback, useEffect, useState } from 'react'
import { format, isValid, parseISO } from 'date-fns'
import { supabase } from '@/lib/supabase'
import type { PurchaseLine } from '@/lib/hooks/useMaterialsTreatment'

type TFn = (key: string, params?: Record<string, any>, fallback?: string) => string

interface Line {
  key: string
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

// Hoja de envios de material de la incidencia: SOLO informativa, sin botones ni acciones. Los envios se
// gestionan en Stock management -> Shipments y la compra en Material Requirements (pedido).
// purchaseLines: lo que queda a compra al confirmar (payload.purchase_lines), con llegada purchaseDue.
export function MaterialShipmentSheet({ incidentId, accountId, receiverPanelistId, purchaseLines, purchaseDue, t }: {
  incidentId: string
  accountId: string
  receiverPanelistId: string | null
  purchaseLines: PurchaseLine[]
  purchaseDue: string | null
  t: TFn
}) {
  const [lines, setLines] = useState<Line[] | null>(null)
  const [receiverDesc, setReceiverDesc] = useState<string>(DASH)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    const { data: ships, error: e1 } = await supabase.from('material_shipments')
      .select('id, status, expected_date, panelist_id, source_panelist_id, created_at')
      .eq('panelist_incident_id', incidentId).eq('account_id', accountId).order('created_at')
    if (e1) throw e1
    const sh = ships ?? []
    const shipIds = sh.map((s: any) => s.id)
    const { data: items, error: e2 } = shipIds.length
      ? await supabase.from('material_shipment_items')
        .select('id, material_shipment_id, material_id, quantity_sent, quantity_received')
        .in('material_shipment_id', shipIds).eq('account_id', accountId)
      : { data: [] as any[], error: null }
    if (e2) throw e2
    const matIds = Array.from(new Set((items ?? []).map((i: any) => i.material_id)))
    const panIds = Array.from(new Set([...sh.flatMap((s: any) => [s.panelist_id, s.source_panelist_id]), receiverPanelistId].filter(Boolean)))
    const [mats, pans] = await Promise.all([
      matIds.length
        ? supabase.from('material_catalog').select('id, code, name').eq('account_id', accountId).in('id', matIds)
        : Promise.resolve({ data: [] as any[], error: null }),
      panIds.length
        ? supabase.from('panelists').select(PANELIST_COLS).eq('account_id', accountId).in('id', panIds)
        : Promise.resolve({ data: [] as any[], error: null })
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
          key: i.id, status: s.status ?? 'pending',
          origin, destination, code: mat?.code ?? DASH, material: mat?.name ?? DASH,
          sent: Number(i.quantity_sent) || 0, received: Number(i.quantity_received) || 0, due: fmtDate(s.expected_date)
        })
      })
    })
    setLines(out)
    setReceiverDesc(receiverPanelistId ? (panMap[receiverPanelistId] ?? DASH) : DASH)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [incidentId, accountId, receiverPanelistId])

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { load().catch(e => setError(`${t('common.error')}: ${e?.message ?? String(e)}`)) }, [load])

  if (!lines || (lines.length === 0 && purchaseLines.length === 0)) {
    return error ? <p className="text-sm text-red-600">{error}</p> : null
  }

  // Bloque "A comprar": no son envios, solo informacion para la compra (origen Compra, destino el receptor)
  const purchaseOrigin = t(k('purchase_origin'))
  const purchaseStatus = t(k('to_buy_title'))
  const purchaseDueText = fmtDate(purchaseDue)

  const statusLabel = (s: string) => t(k(`status.${s}`), undefined, s)
  const qtyText = (l: Line) => (l.received > 0 ? `${l.sent} (${t(k('received_of'), { received: l.received, sent: l.sent })})` : String(l.sent))

  const COLS = ['origin', 'destination', 'material', 'quantity', 'due', 'status']

  return (
    <div>
      <h4 className="font-medium mb-2">{t(k('title'))}</h4>
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
                <td className="py-1 pe-2">{statusLabel(l.status)}</td>
              </tr>
            ))}
            {purchaseLines.length > 0 && (
              <tr className="border-t">
                <td colSpan={COLS.length} className="py-1 pe-2 font-medium">{purchaseStatus}</td>
              </tr>
            )}
            {purchaseLines.map(p => (
              <tr key={`buy-${p.material_id || p.code}`} className="border-t align-top">
                <td className="py-1 pe-2">{purchaseOrigin}</td>
                <td className="py-1 pe-2">{receiverDesc}</td>
                <td className="py-1 pe-2">{p.code} - {p.name}</td>
                <td className="py-1 pe-2">{p.quantity}</td>
                <td className="py-1 pe-2">{purchaseDueText}</td>
                <td className="py-1 pe-2">{purchaseStatus}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
