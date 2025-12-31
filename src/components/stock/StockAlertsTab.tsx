import { useState, useMemo } from 'react'
import { AlertTriangle, Filter, X, ChevronUp, ChevronDown } from 'lucide-react'
import { useStockAlerts } from '../../hooks/useStockAlerts'
import { useTranslation } from '@/hooks/useTranslation';
// No need for date-fns, use native Date

interface StockAlertsTabProps {
  onNavigateToRegulatorStock: (materialIds: string[]) => void
  onNavigateToPanelistStock: (materialIds: string[]) => void
}

type SortField = 'alert_type' | 'material_name' | 'panelist_name' | 'current_quantity' | 'created_at'
type SortDirection = 'asc' | 'desc'

export default function StockAlertsTab({ onNavigateToRegulatorStock, onNavigateToPanelistStock }: StockAlertsTabProps) {
  const { t } = useTranslation();
  const { alerts, loading } = useStockAlerts()
  
  // Filters
  const [filterType, setFilterType] = useState<string>('all')
  const [filterMaterial, setFilterMaterial] = useState<string>('all')
  const [filterPanelist, setFilterPanelist] = useState<string>('all')
  
  // Sorting
  const [sortField, setSortField] = useState<SortField>('alert_type')
  const [sortDirection, setSortDirection] = useState<SortDirection>('asc')

  // Get unique values for filters
  const materials = useMemo(() => {
    const uniqueMaterials = new Map<string, { id: string; code: string; name: string }>()
    alerts.forEach(alert => {
      if (alert.material_id && alert.material_code && alert.material_name) {
        uniqueMaterials.set(alert.material_id, {
          id: alert.material_id,
          code: alert.material_code,
          name: alert.material_name
        })
      }
    })
    return Array.from(uniqueMaterials.values()).sort((a, b) => a.code.localeCompare(b.code))
  }, [alerts])

  const panelists = useMemo(() => {
    const uniquePanelists = new Set<string>()
    alerts.forEach(alert => {
      if (alert.panelist_name) {
        uniquePanelists.add(alert.panelist_name)
      }
    })
    return Array.from(uniquePanelists).sort()
  }, [alerts])

  // Apply filters and sorting
  const filteredAndSortedAlerts = useMemo(() => {
    let filtered = alerts.filter(alert => {
      if (filterType !== 'all' && alert.alert_type !== filterType) return false
      if (filterMaterial !== 'all' && alert.material_id !== filterMaterial) return false
      if (filterPanelist !== 'all' && alert.panelist_name !== filterPanelist) return false
      return true
    })

    // Sort
    filtered.sort((a, b) => {
      let aValue: any = a[sortField]
      let bValue: any = b[sortField]

      // Handle null values
      if (aValue === null || aValue === undefined) return 1
      if (bValue === null || bValue === undefined) return -1

      // Convert to comparable values
      if (sortField === 'created_at') {
        aValue = new Date(aValue).getTime()
        bValue = new Date(bValue).getTime()
      } else if (typeof aValue === 'string') {
        aValue = aValue.toLowerCase()
        bValue = bValue.toLowerCase()
      }

      if (aValue < bValue) return sortDirection === 'asc' ? -1 : 1
      if (aValue > bValue) return sortDirection === 'asc' ? 1 : -1
      return 0
    })

    return filtered
  }, [alerts, filterType, filterMaterial, filterPanelist, sortField, sortDirection])

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc')
    } else {
      setSortField(field)
      setSortDirection('asc')
    }
  }

  const SortIcon = ({ field }: { field: SortField }) => {
    if (sortField !== field) return null
    return sortDirection === 'asc' ? (
      <ChevronUp className="h-4 w-4" />
    ) : (
      <ChevronDown className="h-4 w-4" />
    )
  }

  const clearFilters = () => {
    setFilterType('all')
    setFilterMaterial('all')
    setFilterPanelist('all')
  }

  const hasActiveFilters = filterType !== 'all' || filterMaterial !== 'all' || filterPanelist !== 'all'

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="text-gray-500">Loading alerts...</div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* Filters */}
      <div className="bg-gray-50 p-4 rounded-lg border border-gray-200">
        <div className="flex items-center gap-2 mb-3">
          <Filter className="h-4 w-4 text-gray-500" />
          <span className="text-sm font-medium text-gray-700">{t('stock.filters')}</span>
          {hasActiveFilters && (
            <button
              onClick={clearFilters}
              className="ml-auto text-xs text-blue-600 hover:text-blue-700 flex items-center gap-1"
            >
              <X className="h-3 w-3" />
              Clear filters
            </button>
          )}
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          {/* Type Filter */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Alert Type</label>
            <select
              value={filterType}
              onChange={(e) => setFilterType(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="all">All Types</option>
              <option value="regulator_insufficient">Regulator Insufficient</option>
              <option value="panelist_negative">Panelist Negative</option>
            </select>
          </div>

          {/* Material Filter */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">{t('stock.material')}</label>
            <select
              value={filterMaterial}
              onChange={(e) => setFilterMaterial(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="all">All Materials</option>
              {materials.map(material => (
                <option key={material.id} value={material.id}>
                  {material.code} - {material.name}
                </option>
              ))}
            </select>
          </div>

          {/* Panelist Filter */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">{t('stock.panelist')}</label>
            <select
              value={filterPanelist}
              onChange={(e) => setFilterPanelist(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              disabled={filterType === 'regulator_insufficient'}
            >
              <option value="all">All Panelists</option>
              {panelists.map(panelist => (
                <option key={panelist} value={panelist}>
                  {panelist}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Results Summary */}
      <div className="text-sm text-gray-600">
        Showing <span className="font-semibold">{filteredAndSortedAlerts.length}</span> of{' '}
        <span className="font-semibold">{alerts.length}</span> alerts
      </div>

      {/* Table */}
      {filteredAndSortedAlerts.length === 0 ? (
        <div className="bg-white border border-gray-200 rounded-lg p-12 text-center">
          <AlertTriangle className="h-12 w-12 text-gray-300 mx-auto mb-3" />
          <p className="text-gray-500">No stock alerts found</p>
          {hasActiveFilters && (
            <button
              onClick={clearFilters}
              className="mt-2 text-sm text-blue-600 hover:text-blue-700"
            >
              Clear filters to see all alerts
            </button>
          )}
        </div>
      ) : (
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th
                    scope="col"
                    className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                    onClick={() => handleSort('alert_type')}
                  >
                    <div className="flex items-center gap-1">
                      Type
                      <SortIcon field="alert_type" />
                    </div>
                  </th>
                  <th
                    scope="col"
                    className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                    onClick={() => handleSort('material_name')}
                  >
                    <div className="flex items-center gap-1">
                      Material
                      <SortIcon field="material_name" />
                    </div>
                  </th>
                  <th
                    scope="col"
                    className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                    onClick={() => handleSort('panelist_name')}
                  >
                    <div className="flex items-center gap-1">
                      Location
                      <SortIcon field="panelist_name" />
                    </div>
                  </th>
                  <th
                    scope="col"
                    className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                    onClick={() => handleSort('current_quantity')}
                  >
                    <div className="flex items-center justify-end gap-1">
                      Current Stock
                      <SortIcon field="current_quantity" />
                    </div>
                  </th>
                  <th
                    scope="col"
                    className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider"
                  >
                    Expected
                  </th>
                  <th
                    scope="col"
                    className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                    onClick={() => handleSort('created_at')}
                  >
                    <div className="flex items-center gap-1">
                      Date
                      <SortIcon field="created_at" />
                    </div>
                  </th>
                  <th scope="col" className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Notes
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {filteredAndSortedAlerts.map((alert) => (
                  <tr
                    key={alert.id}
                    className={`hover:bg-gray-50 ${
                      alert.alert_type === 'regulator_insufficient' ? 'bg-red-50' : 'bg-orange-50'
                    }`}
                  >
                    <td className="px-4 py-3 whitespace-nowrap">
                      <div className="flex items-center gap-2">
                        <AlertTriangle
                          className={`h-4 w-4 ${
                            alert.alert_type === 'regulator_insufficient' ? 'text-red-600' : 'text-orange-600'
                          }`}
                        />
                        <span className="text-sm font-medium text-gray-900">
                          {alert.alert_type === 'regulator_insufficient' ? 'Regulator Insufficient' : 'Panelist Negative'}
                        </span>
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <div className="text-sm font-medium text-gray-900">{alert.material_code}</div>
                      <div className="text-xs text-gray-500">{alert.material_name}</div>
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap">
                      <span className="text-sm text-gray-900">
                        {alert.alert_type === 'regulator_insufficient' 
                          ? 'Regulator' 
                          : (alert.panelist_name || <span className="text-red-600 italic">Unknown Panelist</span>)
                        }
                      </span>
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-right">
                      <span
                        className={`text-sm font-semibold ${
                          alert.current_quantity < 0 ? 'text-red-600' : 'text-orange-600'
                        }`}
                      >
                        {alert.current_quantity}
                      </span>
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-right">
                      <span className="text-sm text-gray-500">
                        {alert.expected_quantity || '-'}
                      </span>
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap">
                      <span className="text-sm text-gray-500">
                        {new Date(alert.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <div className="text-xs max-w-md">
                        {alert.alert_type === 'panelist_negative' && !alert.panelist_name && (
                          <div className="text-red-600 font-medium mb-1">
                            ⚠️ ERROR: Panelist information missing (location_id: {alert.location_id || 'null'})
                          </div>
                        )}
                        <div className="text-gray-600 truncate" title={alert.notes || ''}>
                          {alert.notes}
                        </div>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
