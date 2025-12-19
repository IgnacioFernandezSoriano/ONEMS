import { useState, useMemo } from 'react'
import { Package, Download, Users, ShoppingCart, Calendar, Filter, RotateCcw } from 'lucide-react'
import { useMaterialRequirements } from '../hooks/useMaterialRequirements'
import { SmartTooltip } from '../components/common/SmartTooltip'
import { useMaterialCatalog } from '../hooks/useMaterialCatalog'
import { useAuth } from '../contexts/AuthContext'

export default function MaterialRequirements() {
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [selectedMaterialId, setSelectedMaterialId] = useState('')
  const [selectedNodeId, setSelectedNodeId] = useState('')
  const [selectedYear, setSelectedYear] = useState(new Date().getFullYear())
  const [isFiltersCollapsed, setIsFiltersCollapsed] = useState(false)
  const [activeTab, setActiveTab] = useState<'purchase' | 'panelist'>('purchase')
  
  const { profile } = useAuth()
  const { catalog: materials } = useMaterialCatalog()
  const { loading, error, materialRequirements, panelistRequirements, calculate } = useMaterialRequirements()

  // Get unique nodes from panelist requirements
  const uniqueNodes = useMemo(() => {
    const nodesMap = new Map()
    panelistRequirements.forEach(pr => {
      if (pr.node_id && pr.node_name) {
        nodesMap.set(pr.node_id, pr.node_name)
      }
    })
    return Array.from(nodesMap.entries()).map(([id, name]) => ({ id, name }))
  }, [panelistRequirements])

  // Filter results based on selected filters
  const filteredMaterialRequirements = useMemo(() => {
    if (!selectedMaterialId) return materialRequirements
    return materialRequirements.filter(m => m.material_id === selectedMaterialId)
  }, [materialRequirements, selectedMaterialId])

  const filteredPanelistRequirements = useMemo(() => {
    let filtered = panelistRequirements
    
    if (selectedNodeId) {
      filtered = filtered.filter(pr => pr.node_id === selectedNodeId)
    }
    
    if (selectedMaterialId) {
      filtered = filtered.map(pr => ({
        ...pr,
        materials: pr.materials.filter(m => m.material_id === selectedMaterialId),
        total_items: pr.materials.filter(m => m.material_id === selectedMaterialId).length
      })).filter(pr => pr.materials.length > 0)
    }
    
    return filtered
  }, [panelistRequirements, selectedNodeId, selectedMaterialId])

  const handleCalculate = () => {
    if (!startDate || !endDate) {
      alert('Please select both start and end dates')
      return
    }
    calculate(startDate, endDate)
  }

  const handleMonthSelect = (year: number, month: number) => {
    const firstDay = new Date(year, month - 1, 1)
    const lastDay = new Date(year, month, 0)
    
    setStartDate(firstDay.toISOString().split('T')[0])
    setEndDate(lastDay.toISOString().split('T')[0])
  }

  const handleFirstSemesterSelect = () => {
    const firstDay = new Date(selectedYear, 0, 1) // Jan 1
    const lastDay = new Date(selectedYear, 5, 30) // Jun 30
    
    setStartDate(firstDay.toISOString().split('T')[0])
    setEndDate(lastDay.toISOString().split('T')[0])
  }

  const handleSecondSemesterSelect = () => {
    const firstDay = new Date(selectedYear, 6, 1) // Jul 1
    const lastDay = new Date(selectedYear, 11, 31) // Dec 31
    
    setStartDate(firstDay.toISOString().split('T')[0])
    setEndDate(lastDay.toISOString().split('T')[0])
  }

  const handleYearSelect = () => {
    const firstDay = new Date(selectedYear, 0, 1) // Jan 1
    const lastDay = new Date(selectedYear, 11, 31) // Dec 31
    
    setStartDate(firstDay.toISOString().split('T')[0])
    setEndDate(lastDay.toISOString().split('T')[0])
  }

  const handleResetFilters = () => {
    setStartDate('')
    setEndDate('')
    setSelectedMaterialId('')
    setSelectedNodeId('')
    setSelectedYear(new Date().getFullYear())
  }

  const handleExportCSV = () => {
    if (activeTab === 'purchase' && filteredMaterialRequirements.length > 0) {
      exportPurchaseCSV()
    } else if (activeTab === 'panelist' && filteredPanelistRequirements.length > 0) {
      exportPanelistCSV()
    }
  }

  const exportPurchaseCSV = () => {
    const headers = ['Material Code', 'Material Name', 'Unit', 'Quantity Needed', 'Shipments', 'Plans']
    const rows = filteredMaterialRequirements.map(m => [
      m.material_code,
      m.material_name,
      m.unit_measure,
      m.quantity_needed.toString(),
      m.shipments_count.toString(),
      m.plans_count.toString()
    ])
    
    const csv = [headers, ...rows].map(row => row.join(',')).join('\n')
    downloadCSV(csv, `material-requirements-${startDate}-to-${endDate}.csv`)
  }

  const exportPanelistCSV = () => {
    const headers = ['Node', 'Panelist', 'Status', 'Material Code', 'Material Name', 'Unit', 'Quantity Needed']
    const rows: string[][] = []
    
    filteredPanelistRequirements.forEach(pr => {
      pr.materials.forEach(m => {
        rows.push([
          pr.node_name,
          pr.panelist_name || 'Pending',
          pr.assignment_status === 'assigned' ? 'Assigned' : 'Pending',
          m.material_code,
          m.material_name,
          m.unit_measure,
          m.quantity_needed.toString()
        ])
      })
    })
    
    const csv = [headers, ...rows].map(row => row.join(',')).join('\n')
    downloadCSV(csv, `panelist-requirements-${startDate}-to-${endDate}.csv`)
  }

  const downloadCSV = (csv: string, filename: string) => {
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = window.URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = filename
    a.click()
    window.URL.revokeObjectURL(url)
  }

  const totalMaterials = filteredMaterialRequirements.length
  const totalPanelists = filteredPanelistRequirements.length

  const currentYear = new Date().getFullYear()
  const years = Array.from({ length: 10 }, (_, i) => currentYear + i)
  const months = [
    { num: 1, name: 'Jan' }, { num: 2, name: 'Feb' }, { num: 3, name: 'Mar' },
    { num: 4, name: 'Apr' }, { num: 5, name: 'May' }, { num: 6, name: 'Jun' },
    { num: 7, name: 'Jul' }, { num: 8, name: 'Aug' }, { num: 9, name: 'Sep' },
    { num: 10, name: 'Oct' }, { num: 11, name: 'Nov' }, { num: 12, name: 'Dec' }
  ]

  return (
    <div className="p-6">
      <div className="flex items-center gap-3 mb-6">
        <Package className="w-8 h-8 text-blue-600" />
        <div className="flex items-center gap-2">
          <h1 className="text-2xl font-bold text-gray-900">Material Requirements</h1>
          <SmartTooltip content="Calculate material needs based on allocation plans within a date range. This module shows what materials need to be purchased and which panelists need to receive materials for their scheduled shipments." />
        </div>
      </div>

      <p className="text-gray-600 mb-6">Calculate material needs based on allocation plans</p>

      {error && (
        <div className="mb-4 p-4 bg-red-50 border border-red-200 rounded-lg text-red-700">
          Error calculating requirements
        </div>
      )}

      {/* KPIs - Show after calculation */}
      {(materialRequirements.length > 0 || panelistRequirements.length > 0) && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-600 mb-1">Total Materials</p>
                <p className="text-3xl font-bold text-gray-900">{totalMaterials}</p>
                <p className="text-xs text-gray-500 mt-1">items needed</p>
              </div>
              <Package className="w-12 h-12 text-blue-500" />
            </div>
          </div>

          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-600 mb-1">Panelists Needing</p>
                <p className="text-3xl font-bold text-gray-900">{totalPanelists}</p>
                <p className="text-xs text-gray-500 mt-1">to send</p>
              </div>
              <Users className="w-12 h-12 text-orange-500" />
            </div>
          </div>
        </div>
      )}

      {/* Filters - Collapsible */}
      <div className="bg-white rounded-lg shadow p-4 mb-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <button
              onClick={() => setIsFiltersCollapsed(!isFiltersCollapsed)}
              className="p-1 hover:bg-gray-100 rounded transition-colors"
              title={isFiltersCollapsed ? "Expand filters" : "Collapse filters"}
            >
              {isFiltersCollapsed ? (
                <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                </svg>
              ) : (
                <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 15l7-7 7 7" />
                </svg>
              )}
            </button>
            <Filter className="w-5 h-5 text-gray-600" />
            <h3 className="text-lg font-semibold text-gray-900">Filters</h3>
            <SmartTooltip content="Filter material requirements by date range, material type, or node. Use the quick month selector for easy date selection." />
          </div>
          <button
            onClick={handleResetFilters}
            className="flex items-center gap-2 px-3 py-1.5 text-sm text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
            title="Reset all filters"
          >
            <RotateCcw className="w-4 h-4" />
            Reset
          </button>
        </div>

        {!isFiltersCollapsed && (
          <>
            {/* All filters in one row */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-4">
              <div>
                <label className="flex items-center gap-2 block text-sm font-medium text-gray-700 mb-2">
                  <Calendar className="w-4 h-4" />
                  Start Date
                  <SmartTooltip content="The beginning date of the period for which to calculate material requirements." />
                </label>
                <input
                  type="date"
                  value={startDate}
                  onChange={(e) => setStartDate(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>

              <div>
                <label className="flex items-center gap-2 block text-sm font-medium text-gray-700 mb-2">
                  <Calendar className="w-4 h-4" />
                  End Date
                  <SmartTooltip content="The ending date of the period for which to calculate material requirements." />
                </label>
                <input
                  type="date"
                  value={endDate}
                  onChange={(e) => setEndDate(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>

              <div>
                <label className="flex items-center gap-2 block text-sm font-medium text-gray-700 mb-2">
                  <Package className="w-4 h-4" />
                  Material
                  <SmartTooltip content="Filter results to show only a specific material. Leave empty to show all materials." />
                </label>
                <select
                  value={selectedMaterialId}
                  onChange={(e) => setSelectedMaterialId(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="">All Materials</option>
                  {materials.filter((m: any) => m.status === 'active').map((material: any) => (
                    <option key={material.id} value={material.id}>
                      {material.code} - {material.name}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="flex items-center gap-2 block text-sm font-medium text-gray-700 mb-2">
                  <Users className="w-4 h-4" />
                  Node
                  <SmartTooltip content="Filter panelist requirements to show only a specific node. This filter only applies to the Panelist Requirements tab." />
                </label>
                <select
                  value={selectedNodeId}
                  onChange={(e) => setSelectedNodeId(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="">All Nodes</option>
                  {uniqueNodes.map(node => (
                    <option key={node.id} value={node.id}>
                      {node.name}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            {/* Quick Period Selector */}
            <div className="mb-4">
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                Quick Period Selection
                <SmartTooltip content="Click any month button to automatically set the start and end dates for that entire month, or use semester/year buttons for longer periods." />
              </label>
              <div className="flex items-center gap-2 mb-2">
                <select
                  value={selectedYear}
                  onChange={(e) => setSelectedYear(Number(e.target.value))}
                  className="px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  {years.map(year => (
                    <option key={year} value={year}>{year}</option>
                  ))}
                </select>
              </div>
              <div className="flex flex-wrap gap-2">
                {months.map(month => (
                  <button
                    key={month.num}
                    onClick={() => handleMonthSelect(selectedYear, month.num)}
                    className="px-3 py-1.5 text-sm font-medium rounded-lg border border-gray-300 hover:bg-blue-50 hover:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
                  >
                    {month.name}
                  </button>
                ))}
                <button
                  onClick={handleFirstSemesterSelect}
                  className="px-3 py-1.5 text-sm font-medium rounded-lg border border-green-300 bg-green-50 hover:bg-green-100 hover:border-green-500 focus:outline-none focus:ring-2 focus:ring-green-500 transition-colors"
                >
                  1st Semester
                </button>
                <button
                  onClick={handleSecondSemesterSelect}
                  className="px-3 py-1.5 text-sm font-medium rounded-lg border border-teal-300 bg-teal-50 hover:bg-teal-100 hover:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500 transition-colors"
                >
                  2nd Semester
                </button>
                <button
                  onClick={handleYearSelect}
                  className="px-3 py-1.5 text-sm font-medium rounded-lg border border-purple-300 bg-purple-50 hover:bg-purple-100 hover:border-purple-500 focus:outline-none focus:ring-2 focus:ring-purple-500 transition-colors"
                >
                  Year
                </button>
              </div>
            </div>

            <button
              onClick={handleCalculate}
              disabled={loading || !startDate || !endDate}
              className="w-full bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors font-medium"
            >
              {loading ? 'Calculating...' : 'Calculate'}
            </button>
          </>
        )}
      </div>

      {/* Tabs and Results */}
      {(materialRequirements.length > 0 || panelistRequirements.length > 0) && (
        <div className="bg-white rounded-lg shadow-sm border border-gray-200">
          <div className="border-b border-gray-200 flex items-center justify-between px-6 py-4">
            <div className="flex gap-4">
              <button
                onClick={() => setActiveTab('purchase')}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg transition-colors ${
                  activeTab === 'purchase'
                    ? 'bg-blue-100 text-blue-700 font-medium'
                    : 'text-gray-600 hover:bg-gray-100'
                }`}
              >
                <ShoppingCart className="w-4 h-4" />
                Purchase Requirements
                <SmartTooltip content="Shows the total quantity of each material needed to be purchased to fulfill all allocation plans in the selected date range." />
              </button>
              <button
                onClick={() => setActiveTab('panelist')}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg transition-colors ${
                  activeTab === 'panelist'
                    ? 'bg-blue-100 text-blue-700 font-medium'
                    : 'text-gray-600 hover:bg-gray-100'
                }`}
              >
                <Users className="w-4 h-4" />
                Panelist Requirements
                <SmartTooltip content="Shows which materials need to be sent to each panelist/node for their scheduled shipments." />
              </button>
            </div>

            <button
              onClick={handleExportCSV}
              className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
            >
              <Download className="w-4 h-4" />
              Export to CSV
            </button>
          </div>

          <div className="p-6">
            {activeTab === 'purchase' && (
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b border-gray-200">
                      <th className="text-left py-3 px-4 text-sm font-semibold text-gray-700">Material Code</th>
                      <th className="text-left py-3 px-4 text-sm font-semibold text-gray-700">Material Name</th>
                      <th className="text-left py-3 px-4 text-sm font-semibold text-gray-700">Unit</th>
                      <th className="text-right py-3 px-4 text-sm font-semibold text-gray-700">Quantity Needed</th>
                      <th className="text-right py-3 px-4 text-sm font-semibold text-gray-700">Shipments</th>
                      <th className="text-right py-3 px-4 text-sm font-semibold text-gray-700">Plans</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredMaterialRequirements.map((material, index) => (
                      <tr key={index} className="border-b border-gray-100 hover:bg-gray-50">
                        <td className="py-3 px-4 text-sm text-gray-900">{material.material_code}</td>
                        <td className="py-3 px-4 text-sm text-gray-900">{material.material_name}</td>
                        <td className="py-3 px-4 text-sm text-gray-600">{material.unit_measure}</td>
                        <td className="py-3 px-4 text-sm text-gray-900 text-right font-medium">{material.quantity_needed}</td>
                        <td className="py-3 px-4 text-sm text-gray-600 text-right">{material.shipments_count}</td>
                        <td className="py-3 px-4 text-sm text-gray-600 text-right">{material.plans_count}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {activeTab === 'panelist' && (
              <div className="space-y-4">
                {filteredPanelistRequirements.map((panelist, index) => (
                  <div key={index} className="border border-gray-200 rounded-lg p-4">
                    <div className="flex items-center justify-between mb-3">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 bg-blue-100 rounded-full flex items-center justify-center">
                          <Users className="w-5 h-5 text-blue-600" />
                        </div>
                        <div>
                          <p className="font-medium text-gray-900">📍 {panelist.node_name}</p>
                          <p className="text-sm text-gray-600">
                            {panelist.panelist_name ? (
                              <span className="text-green-600">→ {panelist.panelist_name}</span>
                            ) : (
                              <span className="text-orange-600">→ Pending assignment</span>
                            )}
                          </p>
                        </div>
                      </div>
                      <span className={`px-3 py-1 rounded-full text-xs font-medium ${
                        panelist.assignment_status === 'assigned'
                          ? 'bg-green-100 text-green-700'
                          : 'bg-orange-100 text-orange-700'
                      }`}>
                        {panelist.assignment_status === 'assigned' ? 'Assigned' : 'Pending'}
                      </span>
                    </div>

                    <div className="overflow-x-auto">
                      <table className="w-full">
                        <thead>
                          <tr className="border-b border-gray-200">
                            <th className="text-left py-2 px-3 text-xs font-semibold text-gray-700">Material Code</th>
                            <th className="text-left py-2 px-3 text-xs font-semibold text-gray-700">Material Name</th>
                            <th className="text-left py-2 px-3 text-xs font-semibold text-gray-700">Unit</th>
                            <th className="text-right py-2 px-3 text-xs font-semibold text-gray-700">Quantity</th>
                          </tr>
                        </thead>
                        <tbody>
                          {panelist.materials.map((material, mIndex) => (
                            <tr key={mIndex} className="border-b border-gray-100">
                              <td className="py-2 px-3 text-sm text-gray-900">{material.material_code}</td>
                              <td className="py-2 px-3 text-sm text-gray-900">{material.material_name}</td>
                              <td className="py-2 px-3 text-sm text-gray-600">{material.unit_measure}</td>
                              <td className="py-2 px-3 text-sm text-gray-900 text-right font-medium">{material.quantity_needed}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
