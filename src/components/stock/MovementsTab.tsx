import React, { useState, useMemo } from 'react'
import { Search, TrendingUp, TrendingDown, ArrowRight } from 'lucide-react'
import { useStockManagement } from '../../hooks/useStockManagement'
import { SmartTooltip } from '../common/SmartTooltip'
import { useTranslation } from '../../hooks/useTranslation'

export default function MovementsTab() {
  const { t } = useTranslation()
  const { movements, loading } = useStockManagement()
  const [searchTerm, setSearchTerm] = useState('')
  const [filterType, setFilterType] = useState<string>('')
  const [filterPanelist, setFilterPanelist] = useState<string>('')
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')

  // Get unique movement types
  const movementTypes = Array.from(new Set(movements.map(m => m.movement_type)))
    .filter(Boolean)
    .sort()

  // Get unique panelists from movements (from to_location field)
  const panelists = useMemo(() => {
    const panelistSet = new Set<string>()
    movements.forEach(m => {
      if (m.to_location && m.to_location.startsWith('panelist_')) {
        panelistSet.add(m.to_location)
      }
    })
    return Array.from(panelistSet).sort()
  }, [movements])

  // Filter movements
  const filteredMovements = movements.filter(movement => {
    const materialName = movement.material?.name?.toLowerCase() || ''
    const materialCode = movement.material?.code?.toLowerCase() || ''
    const notes = movement.notes?.toLowerCase() || ''
    const search = searchTerm.toLowerCase()
    
    const matchesSearch = materialName.includes(search) || materialCode.includes(search) || notes.includes(search)
    const matchesType = !filterType || movement.movement_type === filterType
    const matchesPanelist = !filterPanelist || movement.to_location === filterPanelist
    
    // Date range filter
    let matchesDateRange = true
    if (startDate || endDate) {
      const movementDate = new Date(movement.created_at)
      if (startDate) {
        const start = new Date(startDate)
        start.setHours(0, 0, 0, 0)
        matchesDateRange = matchesDateRange && movementDate >= start
      }
      if (endDate) {
        const end = new Date(endDate)
        end.setHours(23, 59, 59, 999)
        matchesDateRange = matchesDateRange && movementDate <= end
      }
    }
    
    return matchesSearch && matchesType && matchesPanelist && matchesDateRange
  })

  const getMovementIcon = (type: string) => {
    if (type.toLowerCase().includes('in') || type.toLowerCase().includes('receipt')) {
      return <TrendingUp className="h-5 w-5 text-green-600" />
    }
    if (type.toLowerCase().includes('out') || type.toLowerCase().includes('dispatch')) {
      return <TrendingDown className="h-5 w-5 text-red-600" />
    }
    return <ArrowRight className="h-5 w-5 text-blue-600" />
  }

  const getMovementColor = (type: string) => {
    if (type.toLowerCase().includes('in') || type.toLowerCase().includes('receipt')) {
      return 'text-green-600'
    }
    if (type.toLowerCase().includes('out') || type.toLowerCase().includes('dispatch')) {
      return 'text-red-600'
    }
    return 'text-blue-600'
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading movements...</div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* Search and Filters */}
      <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
              Search
              <SmartTooltip content="Search by material code or name" />
            </label>
            <div className="relative">
              <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                <Search className="h-5 w-5 text-gray-400" />
              </div>
              <input
                type="text"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                placeholder={t('stock.search_material')}
              />
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
              {t('stock.movement_type')}
              <SmartTooltip content="Filter by movement type" />
            </label>
            <select
              value={filterType}
              onChange={(e) => setFilterType(e.target.value)}
              className="block w-full pl-3 pr-10 py-2 text-base border border-gray-300 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm rounded-md"
            >
              <option value="">{t('stock.all_types')}</option>
              {movementTypes.map((type) => (
                <option key={type} value={type}>
                  {type}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
              {t('stock.panelist')}
              <SmartTooltip content="Filter by destination panelist" />
            </label>
            <select
              value={filterPanelist}
              onChange={(e) => setFilterPanelist(e.target.value)}
              className="block w-full pl-3 pr-10 py-2 text-base border border-gray-300 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm rounded-md"
            >
              <option value="">{t('stock.all_panelists')}</option>
              {panelists.map((panelist) => (
                <option key={panelist} value={panelist}>
                  {panelist.replace('panelist_', 'Panelist ')}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
              {t('common.start_date')}
              <SmartTooltip content="Filter movements from this date" />
            </label>
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
            />
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
              {t('common.end_date')}
              <SmartTooltip content="Filter movements until this date" />
            </label>
            <input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
            />
          </div>

          {(searchTerm || filterType || filterPanelist || startDate || endDate) && (
            <div className="flex items-end">
              <button
                onClick={() => {
                  setSearchTerm('')
                  setFilterType('')
                  setFilterPanelist('')
                  setStartDate('')
                  setEndDate('')
                }}
                className="inline-flex items-center px-3 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                {t('stock.clear_filters')}
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Movements Table */}
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {/* Table Header with Export Button */}
        <div className="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
          <h3 className="text-lg font-medium text-gray-900">
            {t('stock.material_movements')} ({filteredMovements.length})
          </h3>
          <button
            onClick={() => {
              const csvData = filteredMovements.map(m => ({
                'Date': new Date(m.created_at).toLocaleString(),
                'Type': m.movement_type,
                'Material Code': m.material?.code || '',
                'Material Name': m.material?.name || '',
                'Quantity': m.quantity,
                'Unit': m.material?.unit_measure || '',
                'From': m.from_location || '',
                'To': m.to_location || '',
                'Notes': m.notes || ''
              }))
              const headers = ['Date', 'Type', 'Material Code', 'Material Name', 'Quantity', 'Unit', 'From', 'To', 'Notes']
              const csvContent = [
                headers.join(','),
                ...csvData.map(row => headers.map(h => {
                  const value = row[h as keyof typeof row]?.toString() || ''
                  return `"${value.replace(/"/g, '""')}"`
                }).join(','))
              ].join('\n')
              
              const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' })
              const link = document.createElement('a')
              const url = URL.createObjectURL(blob)
              link.setAttribute('href', url)
              link.setAttribute('download', `material_movements_${new Date().toISOString().split('T')[0]}.csv`)
              link.style.visibility = 'hidden'
              document.body.appendChild(link)
              link.click()
              document.body.removeChild(link)
            }}
            className="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
          >
            <svg className="h-4 w-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
            {t('common.export_csv')}
          </button>
        </div>
        
        <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('stock.date')}
                  <SmartTooltip content="Date and time of the movement" />
                </div>
              </th>
              <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('common.type')}
                  <SmartTooltip content="Type of movement (in, out, transfer)" />
                </div>
              </th>
              <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('common.material')}
              </th>
              <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('stock.quantity')}
              </th>
              <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('stock.from')}
                  <SmartTooltip content="Origin location of the material" />
                </div>
              </th>
              <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('common.to')}
                  <SmartTooltip content="Destination location of the material" />
                </div>
              </th>
              <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('stock.notes')}
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {filteredMovements.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-6 py-4 text-center text-sm text-gray-500">
                  {searchTerm || filterType ? 'No movements found' : 'No movements recorded'}
                </td>
              </tr>
            ) : (
              filteredMovements.map((movement) => (
                <tr key={movement.id}>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm text-gray-900">
                      {new Date(movement.created_at).toLocaleDateString('en-US')}
                    </div>
                    <div className="text-xs text-gray-500">
                      {new Date(movement.created_at).toLocaleTimeString('en-US', { 
                        hour: '2-digit', 
                        minute: '2-digit' 
                      })}
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="flex items-center gap-2">
                      {getMovementIcon(movement.movement_type)}
                      <span className={`text-sm font-medium ${getMovementColor(movement.movement_type)}`}>
                        {movement.movement_type}
                      </span>
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm font-medium text-gray-900">
                      {movement.material?.code || 'N/A'}
                    </div>
                    <div className="text-sm text-gray-500">
                      {movement.material?.name || 'No name'}
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className={`text-sm font-semibold ${getMovementColor(movement.movement_type)}`}>
                      {movement.quantity.toLocaleString()} {movement.material?.unit_measure || ''}
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm text-gray-900">
                      {movement.from_location || '-'}
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm text-gray-900">
                      {movement.to_location || '-'}
                    </div>
                  </td>
                  <td className="px-6 py-4">
                    <div className="text-sm text-gray-500 max-w-xs truncate">
                      {movement.notes || '-'}
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
        </div>
        
        {/* Summary */}
        <div className="bg-gray-50 px-4 py-3 border-t border-gray-200">
        <div className="text-sm text-gray-700">
          <span className="font-medium">Total movements:</span> {filteredMovements.length}
          {(searchTerm || filterType) && ` (filtered from ${movements.length})`}
        </div>
        </div>
      </div>
    </div>
  )
}
