import { useState, useMemo } from 'react'
import { Button } from '@/components/common/Button'
import type { Node, City } from '@/lib/types'
import { useTranslation } from '@/hooks/useTranslation'

interface NodeFormProps {
  node: Node
  /** Full (unfiltered) cities list — needed to resolve region siblings for Class C cities */
  cities: City[]
  /** Panelists enriched with node_id, status and address_city */
  panelists: any[]
  onSubmit: (data: { status: 'active' | 'inactive'; panelistId: string | null }) => Promise<void>
  onCancel: () => void
}

const norm = (s?: string | null) => (s || '').trim().toLowerCase()

export function NodeForm({ node, cities, panelists, onSubmit, onCancel }: NodeFormProps) {
  const { t } = useTranslation()

  const city = useMemo(() => cities.find(c => c.id === node.city_id), [cities, node.city_id])
  const isClassC = city?.classification === 'C'

  // Panelist currently assigned to THIS node (shown even if it would otherwise be filtered out)
  const currentPanelist = useMemo(
    () => panelists.find((p: any) => p.node_id === node.id),
    [panelists, node.id]
  )

  // City names that count as "in scope": the node's own city, or every city of the
  // node's region when the city is Class C.
  const scopeCityNames = useMemo(() => {
    if (!city) return new Set<string>()
    const names = isClassC
      ? cities.filter(c => c.region_id === city.region_id).map(c => c.name)
      : [city.name]
    return new Set(names.map(norm))
  }, [city, cities, isClassC])

  // Available panelists: active, with no node assigned, located in the node's city
  // (or region for Class C), matched by address_city text.
  const availablePanelists = useMemo(() => {
    return panelists
      .filter(
        (p: any) =>
          p.status === 'active' &&
          !p.node_id &&
          scopeCityNames.has(norm(p.address_city))
      )
      .sort((a: any, b: any) => (a.name || '').localeCompare(b.name || ''))
  }, [panelists, scopeCityNames])

  const [status, setStatus] = useState<'active' | 'inactive'>(node.status)
  const [panelistId, setPanelistId] = useState<string>(currentPanelist?.id || '')
  const [loading, setLoading] = useState(false)

  const panelistLabel = (p: any) =>
    `${p.name}${p.panelist_code ? ` (${p.panelist_code})` : ''}`

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      await onSubmit({ status, panelistId: panelistId || null })
    } finally {
      setLoading(false)
    }
  }

  const scopeLabel = city?.name || ''

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {/* Node identity (read-only) */}
      <div className="bg-gray-50 border border-gray-200 rounded-md p-3 text-sm">
        <div className="flex items-center justify-between">
          <span className="text-gray-500">{t('topology.node_id', undefined, 'Node ID')}</span>
          <span className="font-medium text-gray-900">{node.auto_id}</span>
        </div>
        {city && (
          <div className="flex items-center justify-between mt-1">
            <span className="text-gray-500">{t('common.city', undefined, 'City')}</span>
            <span className="font-medium text-gray-900 flex items-center gap-2">
              {city.name}
              {city.classification && (
                <span className="text-xs font-medium bg-purple-100 text-purple-700 px-2 py-0.5 rounded-full">
                  {t('topology.class', undefined, 'Class')} {city.classification}
                </span>
              )}
            </span>
          </div>
        )}
      </div>

      {/* Node status */}
      <div>
        <label className="block text-sm font-medium mb-1">
          {t('topology.node_status', undefined, 'Node status')} *
        </label>
        <select
          required
          value={status}
          onChange={(e) => setStatus(e.target.value as 'active' | 'inactive')}
          className="w-full px-3 py-2 border rounded-md"
        >
          <option value="active">{t('common.active', undefined, 'Active')}</option>
          <option value="inactive">{t('common.inactive', undefined, 'Inactive')}</option>
        </select>
      </div>

      {/* Panelist assignment */}
      <div>
        <label className="block text-sm font-medium mb-1">
          {t('topology.assign_panelist', undefined, 'Assign panelist')}
        </label>
        <select
          value={panelistId}
          onChange={(e) => setPanelistId(e.target.value)}
          className="w-full px-3 py-2 border rounded-md"
        >
          <option value="">{t('topology.no_panelist_option', undefined, '— No panelist —')}</option>
          {currentPanelist && (
            <option value={currentPanelist.id}>
              {panelistLabel(currentPanelist)} · {t('topology.panelist_current', undefined, 'current')}
            </option>
          )}
          {availablePanelists
            .filter((p: any) => p.id !== currentPanelist?.id)
            .map((p: any) => (
              <option key={p.id} value={p.id}>
                {panelistLabel(p)}
              </option>
            ))}
        </select>
        <p className="text-xs text-gray-500 mt-1">
          {t(
            isClassC ? 'topology.panelist_hint_region' : 'topology.panelist_hint_city',
            { scope: scopeLabel || '' },
            isClassC
              ? `Available panelists from the region of "${scopeLabel}" (Class C city), with no node assigned.`
              : `Available panelists from "${scopeLabel}", with no node assigned.`
          )}
        </p>
        {availablePanelists.length === 0 && !currentPanelist && (
          <p className="text-xs text-amber-600 mt-1">
            {t('topology.no_available_panelists', undefined, 'No available panelists match this scope.')}
          </p>
        )}
      </div>

      <div className="flex gap-2 justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>
          {t('cityform.cancel', undefined, 'Cancel')}
        </Button>
        <Button type="submit" disabled={loading}>
          {loading ? t('cityform.saving', undefined, 'Saving...') : t('cityform.update', undefined, 'Update')}
        </Button>
      </div>
    </form>
  )
}
