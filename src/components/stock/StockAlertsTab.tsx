import { useState, useMemo } from 'react'
import { AlertTriangle, Package, User, Calendar, FileText, TrendingDown } from 'lucide-react'
import { useStockAlerts } from '../../hooks/useStockAlerts'
import { SmartTooltip } from '../common/SmartTooltip'

interface StockAlertsTabProps {
  onNavigateToRegulatorStock?: (materialIds: string[]) => void
  onNavigateToPanelistStock?: (materialIds: string[]) => void
}

export default function StockAlertsTab({
  onNavigateToRegulatorStock,
  onNavigateToPanelistStock
}: StockAlertsTabProps) {
  const { alerts, loading, getAlertCounts, getAffectedMaterials } = useStockAlerts()
  
  const [filterType, setFilterType] = useState<string>('')
  const [filterMaterial, setFilterMaterial] = useState<string>('')
  const [filterPanelist, setFilterPanelist] = useState<string>('')
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')

  const counts = getAlertCounts()

  // Get unique materials and panelists for filters
  const materials = useMemo(() => {
    const materialsMap = new Map()
    alerts.forEach(alert => {
      if (alert.material_id && alert.material_code) {
        materialsMap.set(alert.material_id, {
          id: alert.material_id,
          code: alert.material_code,
          name: alert.material_name
        })
      }
    })
    return Array.from(materialsMap.values()).sort((a, b) => a.code.localeCompare(b.code))
  }, [alerts])

  const panelists = useMemo(() => {
    const panelistsMap = new Map()
    alerts.forEach(alert => {
      if (alert.location_id && alert.panelist_name) {
        panelistsMap.set(alert.location_id, {
          id: alert.location_id,
          name: alert.panelist_name,
          code: alert.panelist_code
        })
      }
    })
    return Array.from(panelistsMap.values()).sort((a, b) => a.name.localeCompare(b.name))
  }, [alerts])

  // Filter alerts
  const filteredAlerts = alerts.filter(alert => {
    const matchesType = !filterType || alert.alert_type === filterType
    const matchesMaterial = !filterMaterial || alert.material_id === filterMaterial
    const matchesPanelist = !filterPanelist || alert.location_id === filterPanelist

    let matchesDateRange = true
    if (startDate || endDate) {
      const alertDate = new Date(alert.created_at)
      if (startDate) {
        const start = new Date(startDate)
        start.setHours(0, 0, 0, 0)
        matchesDateRange = matchesDateRange && alertDate >= start
      }
      if (endDate) {
        const end = new Date(endDate)
        end.setHours(23, 59, 59, 999)
        matchesDateRange = matchesDateRange && alertDate <= end
      }
    }

    return matchesType && matchesMaterial && matchesPanelist && matchesDateRange
  })

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading alerts...</div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Regulator Alerts Card */}
        <button
          onClick={() => {
            if (onNavigateToRegulatorStock) {
              const materialIds = getAffectedMaterials('regulator_insufficient')
              onNavigateToRegulatorStock(materialIds)
            }
          }}
          className="bg-white border-2 border-red-200 rounded-lg p-6 hover:border-red-400 hover:shadow-lg transition-all text-left group"
        >
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="p-3 bg-red-100 rounded-lg group-hover:bg-red-200 transition-colors">
                <Package className="h-6 w-6 text-red-600" />
              </div>
              <div>
                <div className="text-sm font-medium text-gray-500">Regulator Stock Issues</div>
                <div className="text-3xl font-bold text-red-600">{counts.regulator}</div>
                <div className="text-xs text-gray-500 mt-1">
                  {counts.regulatorMaterials} material{counts.regulatorMaterials !== 1 ? 's' : ''} affected
                </div>
              </div>
            </div>
            <div className="text-gray-400 group-hover:text-red-600 transition-colors">
              <svg className="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
              </svg>
            </div>
          </div>
          <div className="mt-4 text-xs text-gray-600">
            Click to view affected materials in Regulator Stock
          </div>
        </button>

        {/* Panelist Alerts Card */}
        <button
          onClick={() => {
            if (onNavigateToPanelistStock) {
              const materialIds = getAffectedMaterials('panelist_negative')
              onNavigateToPanelistStock(materialIds)
            }
          }}
          className="bg-white border-2 border-orange-200 rounded-lg p-6 hover:border-orange-400 hover:shadow-lg transition-all text-left group"
        >
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="p-3 bg-orange-100 rounded-lg group-hover:bg-orange-200 transition-colors">
                <User className="h-6 w-6 text-orange-600" />
              </div>
              <div>
                <div className="text-sm font-medium text-gray-500">Panelist Stock Issues</div>
                <div className="text-3xl font-bold text-orange-600">{counts.panelist}</div>
                <div className="text-xs text-gray-500 mt-1">
                  {counts.panelistMaterials} material{counts.panelistMaterials !== 1 ? 's' : ''} affected
                </div>
              </div>
            </div>
            <div className="text-gray-400 group-hover:text-orange-600 transition-colors">
              <svg className="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
              </svg>
            </div>
          </div>
          <div className="mt-4 text-xs text-gray-600">
            Click to view affected materials in Panelist Stock
          </div>
        </button>
      </div>

      {/* Filters */}
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
              Alert Type
              <SmartTooltip content="Filter by type of stock issue" />
            </label>
            <select
              value={filterType}
              onChange={(e) => setFilterType(e.target.value)}
              className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
            >
              <option value="">All Types</option>
              <option value="regulator_insufficient">Regulator Insufficient</option>
              <option value="panelist_negative">Panelist Negative</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
              Material
              <SmartTooltip content="Filter by material" />
            </label>
            <select
              value={filterMaterial}
              onChange={(e) => setFilterMaterial(e.target.value)}
              className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
            >
              <option value="">All Materials</option>
              {materials.map((material) => (
                <option key={material.id} value={material.id}>
                  {material.code} - {material.name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
              Panelist
              <SmartTooltip content="Filter by panelist (for panelist alerts)" />
            </label>
            <select
              value={filterPanelist}
              onChange={(e) => setFilterPanelist(e.target.value)}
              className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
            >
              <option value="">All Panelists</option>
              {panelists.map((panelist) => (
                <option key={panelist.id} value={panelist.id}>
                  {panelist.name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
              Date Range
              <SmartTooltip content="Filter by alert creation date" />
            </label>
            <div className="flex gap-2">
              <input
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
                className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
              />
            </div>
          </div>
        </div>

        {(filterType || filterMaterial || filterPanelist || startDate || endDate) && (
          <div className="mt-4 flex items-center justify-between">
            <div className="text-sm text-gray-600">
              Showing {filteredAlerts.length} of {alerts.length} alerts
            </div>
            <button
              onClick={() => {
                setFilterType('')
                setFilterMaterial('')
                setFilterPanelist('')
                setStartDate('')
                setEndDate('')
              }}
              className="text-sm text-blue-600 hover:text-blue-800"
            >
              Clear filters
            </button>
          </div>
        )}
      </div>

      {/* Alerts Grid */}
      {filteredAlerts.length === 0 ? (
        <div className="bg-white border border-gray-200 rounded-lg p-12 text-center">
          <AlertTriangle className="h-12 w-12 text-gray-400 mx-auto mb-4" />
          <div className="text-gray-500">
            {alerts.length === 0 ? 'No stock alerts found' : 'No alerts match the selected filters'}
          </div>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredAlerts.map((alert) => (
            <div
              key={alert.id}
              className={`bg-white border-2 rounded-lg p-4 ${
                alert.alert_type === 'regulator_insufficient'
                  ? 'border-red-200 hover:border-red-400'
                  : 'border-orange-200 hover:border-orange-400'
              } hover:shadow-lg transition-all`}
            >
              {/* Alert Header */}
              <div className="flex items-start justify-between mb-3">
                <div className="flex items-center gap-2">
                  <div className={`p-2 rounded-lg ${
                    alert.alert_type === 'regulator_insufficient'
                      ? 'bg-red-100'
                      : 'bg-orange-100'
                  }`}>
                    <AlertTriangle className={`h-5 w-5 ${
                      alert.alert_type === 'regulator_insufficient'
                        ? 'text-red-600'
                        : 'text-orange-600'
                    }`} />
                  </div>
                  <div>
                    <div className={`text-xs font-medium ${
                      alert.alert_type === 'regulator_insufficient'
                        ? 'text-red-600'
                        : 'text-orange-600'
                    }`}>
                      {alert.alert_type === 'regulator_insufficient'
                        ? 'Regulator Insufficient'
                        : 'Panelist Negative'}
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-1 text-xs text-gray-500">
                  <Calendar className="h-3 w-3" />
                  {new Date(alert.created_at).toLocaleDateString()}
                </div>
              </div>

              {/* Material Info */}
              <div className="mb-3">
                <div className="text-sm font-medium text-gray-900">{alert.material_code}</div>
                <div className="text-xs text-gray-500">{alert.material_name}</div>
              </div>

              {/* Stock Info */}
              <div className="flex items-center gap-2 mb-3">
                <TrendingDown className="h-4 w-4 text-gray-400" />
                <div className="text-sm">
                  <span className="font-medium text-gray-900">
                    {alert.current_quantity.toLocaleString()}
                  </span>
                  <span className="text-gray-500 ml-1">{alert.unit_measure || 'units'}</span>
                  {alert.expected_quantity && (
                    <span className="text-xs text-gray-500 ml-2">
                      (attempted: {alert.expected_quantity.toLocaleString()})
                    </span>
                  )}
                </div>
              </div>

              {/* Panelist Info (if applicable) */}
              {alert.panelist_name && (
                <div className="flex items-center gap-2 mb-3 text-xs text-gray-600">
                  <User className="h-3 w-3" />
                  {alert.panelist_name}
                </div>
              )}

              {/* Notes */}
              {alert.notes && (
                <div className="mt-3 pt-3 border-t border-gray-200">
                  <div className="flex items-start gap-2 text-xs text-gray-600">
                    <FileText className="h-3 w-3 mt-0.5 flex-shrink-0" />
                    <div className="line-clamp-2">{alert.notes}</div>
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
