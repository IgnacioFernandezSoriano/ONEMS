import type { SupplyLine, SourceMode } from '@/lib/hooks/useMaterialsTreatment'

type TFn = (key: string, params?: Record<string, any>, fallback?: string) => string

const m = (k: string) => `reported_incidents.materials.${k}`
const MODES: { value: SourceMode; key: string }[] = [
  { value: 'proposal', key: 'source_proposal' },
  { value: 'neighbours_only', key: 'source_only_neighbours' },
  { value: 'central_only', key: 'source_only_central' },
  { value: 'purchase_all', key: 'source_purchase_all' }
]

export function SupplyTable({ lines, modes, onModeChange, disabled, t }: {
  lines: SupplyLine[]
  modes: Record<string, SourceMode>
  onModeChange: (materialId: string, mode: SourceMode) => void
  disabled?: boolean
  t: TFn
}) {
  return (
    <table className="w-full text-sm">
      <thead>
        <tr className="text-gray-500">
          <th className="text-start font-medium" />
          <th className="text-end font-medium pe-2">{t(m('col_need'))}</th>
          <th className="text-start font-medium">{t(m('col_neighbours'))}</th>
          <th className="text-end font-medium pe-2">{t(m('col_central'))}</th>
          <th className="text-end font-medium pe-2">{t(m('col_purchase'))}</th>
          <th className="text-start font-medium">{t(m('change_source'))}</th>
        </tr>
      </thead>
      <tbody>
        {lines.map(l => (
          <tr key={l.material_id} className="border-t">
            <td className="py-1 text-start">
              {l.name}{' '}
              {l.is_blocking && <span className="bg-red-100 text-red-700 text-xs px-2 py-0.5 rounded">{t(m('blocking_badge'))}</span>}
            </td>
            <td className="py-1 text-end pe-2">{l.need}</td>
            <td className="py-1 text-start">
              {l.fromNeighbours.length === 0 ? '-' : l.fromNeighbours.map(n => `${n.donor_name || n.donor_panelist_id.slice(0, 8)}: ${n.quantity}`).join(', ')}
            </td>
            <td className="py-1 text-end pe-2">{l.fromCentral || '-'}</td>
            <td className={`py-1 text-end pe-2 ${l.toPurchase > 0 ? 'text-red-700 font-medium' : ''}`}>{l.toPurchase || '-'}</td>
            <td className="py-1 text-start">
              <select className="border rounded p-1 text-sm" disabled={disabled} value={modes[l.material_id] ?? 'proposal'}
                onChange={e => onModeChange(l.material_id, e.target.value as SourceMode)}>
                {MODES.map(o => <option key={o.value} value={o.value}>{t(m(o.key))}</option>)}
              </select>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}
