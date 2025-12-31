import React, { useState, useMemo } from 'react'
import { Package, Calendar, Filter, RotateCcw, CheckSquare, Square, ShoppingCart, Trash2, AlertCircle, Clock, Download, FileText, ChevronDown, ChevronUp, Info } from 'lucide-react'
import { useStockManagement } from '../../hooks/useStockManagement'
import { useRegulatorRequirements } from '../../hooks/useRegulatorRequirements'
import { useMaterialCatalog } from '../../hooks/useMaterialCatalog'
import { SmartTooltip } from '../common/SmartTooltip'
import OrderMaterialModal from './OrderMaterialModal'
import ReceivePOModal from './ReceivePOModal'
import { downloadCSV, generatePurchaseOrderPDF, printPDF } from '../../lib/exportUtils'

import { useTranslation } from '@/hooks/useTranslation';
export default function MaterialRequirementsTab() {
  const { t } = useTranslation();
  const { regulatorStocks, reload } = useStockManagement()
  const { requirements, loading: loadingRequirements, calculate, markAsOrdered, receivePO, deleteRequirement } = useRegulatorRequirements()
  const { catalog: materials } = useMaterialCatalog()

  // Filters
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [selectedMaterialId, setSelectedMaterialId] = useState('')
  const [selectedStatus, setSelectedStatus] = useState<string>('')
  const [selectedYear, setSelectedYear] = useState(new Date().getFullYear())
  const [isFiltersCollapsed, setIsFiltersCollapsed] = useState(false)
  const [isMetricsCollapsed, setIsMetricsCollapsed] = useState(false)

  // Selection for bulk actions
  const [selectedRequirements, setSelectedRequirements] = useState<Set<string>>(new Set())

  // Modals
  const [showOrderModal, setShowOrderModal] = useState(false)
  const [showReceiveModal, setShowReceiveModal] = useState(false)
  const [selectedRequirement, setSelectedRequirement] = useState<typeof requirements[0] | null>(null)

  // Month names
  const months = [
    { name: 'Jan', num: 1 }, { name: 'Feb', num: 2 }, { name: 'Mar', num: 3 },
    { name: 'Apr', num: 4 }, { name: 'May', num: 5 }, { name: 'Jun', num: 6 },
    { name: 'Jul', num: 7 }, { name: 'Aug', num: 8 }, { name: 'Sep', num: 9 },
    { name: 'Oct', num: 10 }, { name: 'Nov', num: 11 }, { name: 'Dec', num: 12 }
  ]

  // Generate year range (current year to current year + 10)
  const yearRange = useMemo(() => {
    const currentYear = new Date().getFullYear()
    const years = []
    for (let i = currentYear; i <= currentYear + 10; i++) {
      years.push(i)
    }
    return years
  }, [])

  // Filter requirements
  const filteredRequirements = useMemo(() => {
    let filtered = requirements
    
    // Filter by material
    if (selectedMaterialId) {
      filtered = filtered.filter(r => r.material_id === selectedMaterialId)
    }
    
    // Filter by status
    if (selectedStatus) {
      filtered = filtered.filter(r => r.status === selectedStatus)
    }
    
    return filtered
  }, [requirements, selectedMaterialId, selectedStatus])

  // Enrich requirements with net quantity and current stock
  const enrichedRequirements = useMemo(() => {
    return filteredRequirements.map(req => {
      const currentStock = regulatorStocks.find(s => s.material_id === req.material_id)
      const currentQuantity = currentStock?.quantity || 0
      const netQuantity = Math.max(0, req.quantity_needed - currentQuantity)
      
      return {
        ...req,
        current_stock: currentQuantity,
        net_quantity: netQuantity
      }
    })
  }, [filteredRequirements, regulatorStocks])

  // Calculate metrics
  const metrics = useMemo(() => {
    const pending = enrichedRequirements.filter(r => r.status === 'pending').length
    const ordered = enrichedRequirements.filter(r => r.status === 'ordered').length
    const totalQuantity = enrichedRequirements.reduce((sum, r) => sum + r.net_quantity, 0)
    
    return { pending, ordered, totalQuantity }
  }, [enrichedRequirements])

  const handleCalculate = () => {
    if (!startDate || !endDate) {
      alert('Please select both start and end dates')
      return
    }
    calculate(startDate, endDate)
    setSelectedRequirements(new Set())
  }

  const formatDateLocal = (date: Date) => {
    const y = date.getFullYear()
    const m = String(date.getMonth() + 1).padStart(2, '0')
    const d = String(date.getDate()).padStart(2, '0')
    return `${y}-${m}-${d}`
  }

  const handleMonthSelect = (year: number, month: number) => {
    const firstDay = new Date(year, month - 1, 1)
    const lastDay = new Date(year, month, 0)
    
    setStartDate(formatDateLocal(firstDay))
    setEndDate(formatDateLocal(lastDay))
  }

  const handleFirstSemesterSelect = () => {
    const currentYear = new Date().getFullYear()
    const firstDay = new Date(currentYear, 0, 1) // Jan 1
    const lastDay = new Date(currentYear, 5, 30) // Jun 30
    
    setStartDate(formatDateLocal(firstDay))
    setEndDate(formatDateLocal(lastDay))
  }

  const handleSecondSemesterSelect = () => {
    const currentYear = new Date().getFullYear()
    const firstDay = new Date(currentYear, 6, 1) // Jul 1
    const lastDay = new Date(currentYear, 11, 31) // Dec 31
    
    setStartDate(formatDateLocal(firstDay))
    setEndDate(formatDateLocal(lastDay))
  }

  const handleYearSelect = () => {
    const currentYear = new Date().getFullYear()
    const firstDay = new Date(currentYear, 0, 1) // Jan 1
    const lastDay = new Date(currentYear, 11, 31) // Dec 31
    
    setStartDate(formatDateLocal(firstDay))
    setEndDate(formatDateLocal(lastDay))
  }

  const handleResetFilters = () => {
    setStartDate('')
    setEndDate('')
    setSelectedMaterialId('')
    setSelectedYear(new Date().getFullYear())
    setSelectedRequirements(new Set())
  }

  const handleToggleSelection = (requirementId: string) => {
    const newSelection = new Set(selectedRequirements)
    if (newSelection.has(requirementId)) {
      newSelection.delete(requirementId)
    } else {
      newSelection.add(requirementId)
    }
    setSelectedRequirements(newSelection)
  }

  const handleSelectAll = () => {
    if (selectedRequirements.size === enrichedRequirements.length) {
      setSelectedRequirements(new Set())
    } else {
      setSelectedRequirements(new Set(enrichedRequirements.map(r => r.id)))
    }
  }

  const handleOrder = (requirement: typeof enrichedRequirements[0]) => {
    setSelectedRequirement(requirement)
    setShowOrderModal(true)
  }

  const handleReceive = (requirement: typeof enrichedRequirements[0]) => {
    setSelectedRequirement(requirement)
    setShowReceiveModal(true)
  }

  const handleMarkSelectedAsOrdered = async () => {
    if (selectedRequirements.size === 0) return
    
    const confirmed = confirm(`Mark ${selectedRequirements.size} requirement(s) as ordered?`)
    if (!confirmed) return

    for (const reqId of selectedRequirements) {
      await markAsOrdered(reqId, null) // null = use net quantity as default
    }
    
    setSelectedRequirements(new Set())
  }

  const handleDelete = async (requirementId: string) => {
    const confirmed = confirm('Are you sure you want to delete this requirement?')
    if (!confirmed) return

    try {
      await deleteRequirement(requirementId)
      alert('Requirement deleted successfully')
    } catch (error: any) {
      alert(`Error deleting requirement: ${error.message}`)
    }
  }

  const handleDeleteSelected = async () => {
    if (selectedRequirements.size === 0) return
    
    const confirmed = confirm(`Delete ${selectedRequirements.size} requirement(s)? This action cannot be undone.`)
    if (!confirmed) return

    try {
      for (const reqId of selectedRequirements) {
        await deleteRequirement(reqId)
      }
      alert(`${selectedRequirements.size} requirement(s) deleted successfully`)
      setSelectedRequirements(new Set())
    } catch (error: any) {
      alert(`Error deleting requirements: ${error.message}`)
    }
  }

  const handleExportCSV = () => {
    if (selectedRequirements.size === 0) {
      alert('Please select requirements to export')
      return
    }

    const selectedData = enrichedRequirements
      .filter(r => selectedRequirements.has(r.id))
      .map(r => ({
        'Material Code': r.material_code,
        'Material Name': r.material_name,
        'Quantity Needed': r.quantity_needed,
        'Current Stock': r.current_stock,
        'Net Quantity': r.net_quantity,
        'Unit': r.unit_measure,
        'Status': r.status,
        'Period': `${r.period_start} to ${r.period_end}`
      }))

    downloadCSV(selectedData, `material-requirements-${new Date().toISOString().split('T')[0]}.csv`)
  }

  const handleGeneratePDF = () => {
    if (selectedRequirements.size === 0) {
      alert('Please select requirements to generate purchase order')
      return
    }

    const selectedData = enrichedRequirements.filter(r => selectedRequirements.has(r.id))
    const htmlContent = generatePurchaseOrderPDF(selectedData, 'ONEMS')
    printPDF(htmlContent, 'purchase-order.pdf')
  }

  const getStatusBadge = (status: string) => {
    const styles = {
      pending: 'bg-yellow-100 text-yellow-800',
      ordered: 'bg-blue-100 text-blue-800',
      received: 'bg-green-100 text-green-800'
    }
    
    return (
      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${styles[status as keyof typeof styles] || styles.pending}`}>
        {status.charAt(0).toUpperCase() + status.slice(1)}
      </span>
    )
  }

  return (
    <div className="space-y-6">
      {/* Metrics Cards */}
      {enrichedRequirements.length > 0 && (
        <div className="bg-white border border-gray-200 rounded-lg">
          <button
            onClick={() => setIsMetricsCollapsed(!isMetricsCollapsed)}
            className="w-full px-4 py-3 flex items-center justify-between text-left hover:bg-gray-50"
          >
            <div className="flex items-center gap-2">
              <Package className="h-4 w-4 text-gray-500" />
              <span className="font-medium text-gray-900">Metrics Overview</span>
            </div>
            {isMetricsCollapsed ? (
              <ChevronDown className="h-4 w-4 text-gray-500" />
            ) : (
              <ChevronUp className="h-4 w-4 text-gray-500" />
            )}
          </button>

          {!isMetricsCollapsed && (
            <div className="px-4 pb-4">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm font-medium text-yellow-800">Pending Requirements</p>
                      <p className="text-2xl font-bold text-yellow-900 mt-1">{metrics.pending}</p>
                    </div>
                    <AlertCircle className="h-8 w-8 text-yellow-600" />
                  </div>
                </div>

                <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm font-medium text-blue-800">{t('stock.ordered')}</p>
                      <p className="text-2xl font-bold text-blue-900 mt-1">{metrics.ordered}</p>
                    </div>
                    <Clock className="h-8 w-8 text-blue-600" />
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Filters */}
      <div className="bg-gray-50 border border-gray-200 rounded-lg">
        <button
          onClick={() => setIsFiltersCollapsed(!isFiltersCollapsed)}
          className="w-full px-4 py-3 flex items-center justify-between text-left hover:bg-gray-100 transition-colors"
        >
          <div className="flex items-center gap-2">
            <Filter className="h-5 w-5 text-gray-500" />
            <span className="font-medium text-gray-900">Calculate Requirements</span>
          </div>
          <span className="text-sm text-gray-500">
            {isFiltersCollapsed ? 'Show' : 'Hide'}
          </span>
        </button>

        {!isFiltersCollapsed && (
          <div className="px-4 pb-4 space-y-4">
            {/* Date Filters */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  Start Date
                  <SmartTooltip content="Select the start date of the period for which you want to calculate material requirements based on allocation plans" />
                </label>
                <input
                  type="date"
                  value={startDate}
                  onChange={(e) => setStartDate(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  End Date
                  <SmartTooltip content="Select the end date of the period. The system will analyze all allocation plans within this date range to determine material needs" />
                </label>
                <input
                  type="date"
                  value={endDate}
                  onChange={(e) => setEndDate(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  Material
                  <SmartTooltip content="Filter calculated requirements by a specific material to focus on individual items" />
                </label>
                <select
                  value={selectedMaterialId}
                  onChange={(e) => setSelectedMaterialId(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                >
                  <option value="">All Materials</option>
                  {materials.map(m => (
                    <option key={m.id} value={m.id}>{m.code} - {m.name}</option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  Status
                  <SmartTooltip content="Filter requirements by their current status: Pending (not yet ordered), Ordered (purchase order placed), or Received (materials in stock)" />
                </label>
                <select
                  value={selectedStatus}
                  onChange={(e) => setSelectedStatus(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                >
                  <option value="">All Status</option>
                  <option value="pending">{t('stock.pending')}</option>
                  <option value="ordered">{t('stock.ordered')}</option>
                  <option value="received">{t('stock.received')}</option>
                </select>
              </div>
            </div>

            {/* Month Selectors */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2 flex items-center gap-1">
                <Calendar className="h-4 w-4" />
                Quick Month Selection
                <SmartTooltip content="Click any month button to automatically set the start and end dates for that entire month. This is the fastest way to calculate requirements for a specific month." />
              </label>
              <div className="flex items-center gap-2">
                <select
                  value={selectedYear}
                  onChange={(e) => setSelectedYear(parseInt(e.target.value))}
                  className="border border-gray-300 rounded-md shadow-sm py-1 px-2 text-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                >
                  {yearRange.map(year => (
                    <option key={year} value={year}>{year}</option>
                  ))}
                </select>
                <div className="flex flex-wrap gap-1">
                  {months.map(month => (
                    <button
                      key={month.num}
                      onClick={() => handleMonthSelect(selectedYear, month.num)}
                      className="px-3 py-1 text-sm font-medium rounded-md border border-gray-300 hover:bg-blue-50 hover:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    >
                      {month.name}
                    </button>
                  ))}
                  <button
                    onClick={handleFirstSemesterSelect}
                    className="px-3 py-1 text-sm font-medium rounded-md border border-green-300 bg-green-50 hover:bg-green-100 hover:border-green-500 focus:outline-none focus:ring-2 focus:ring-green-500"
                  >
                    1st Semester
                  </button>
                  <button
                    onClick={handleSecondSemesterSelect}
                    className="px-3 py-1 text-sm font-medium rounded-md border border-teal-300 bg-teal-50 hover:bg-teal-100 hover:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500"
                  >
                    2nd Semester
                  </button>
                  <button
                    onClick={handleYearSelect}
                    className="px-3 py-1 text-sm font-medium rounded-md border border-purple-300 bg-purple-50 hover:bg-purple-100 hover:border-purple-500 focus:outline-none focus:ring-2 focus:ring-purple-500"
                  >
                    Year
                  </button>
                </div>
              </div>
            </div>

            {/* Action Buttons */}
            <div className="flex items-center gap-2">
              <button
                onClick={handleCalculate}
                disabled={loadingRequirements || !startDate || !endDate}
                className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <Package className="h-4 w-4 mr-2" />
                {loadingRequirements ? 'Calculating...' : 'Calculate Requirements'}
              </button>
              <SmartTooltip content="Calculate material requirements for the selected period. The system will:

1. Analyze all allocation plans in the date range
2. Calculate total material needed per product
3. Discount panelist stock (if panelist already has the material)
4. Discount regulator stock
5. Discount already ordered quantities (in transit)
6. Add safety stock if current stock is below minimum

Formula: Net Quantity = (Needed - Panelist Stock - Regulator Stock - Ordered) + Safety Stock

Unification Logic:
- If multiple pending requirements exist for the same material, they will be unified into one record
- The period will span from the earliest start date to the latest end date
- Quantities will be summed">
                <Info className="h-5 w-5 text-blue-500 cursor-help" />
              </SmartTooltip>

              <button
                onClick={handleResetFilters}
                className="inline-flex items-center px-3 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                <RotateCcw className="h-4 w-4 mr-1" />
                Reset
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Requirements Table */}
      {enrichedRequirements.length > 0 && (
        <div className="bg-white border border-gray-200 rounded-lg">
          <div className="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
            <h3 className="text-lg font-medium text-gray-900">
              Material Requirements ({enrichedRequirements.length})
            </h3>
            <div className="flex items-center gap-2">
              {selectedRequirements.size > 0 && (
                <>
                  <button
                    onClick={handleMarkSelectedAsOrdered}
                    className="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                  >
                    <ShoppingCart className="h-4 w-4 mr-1" />
                    Mark {selectedRequirements.size} as Ordered
                  </button>
                  <button
                    onClick={handleExportCSV}
                    className="inline-flex items-center px-3 py-1.5 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                  >
                    <Download className="h-4 w-4 mr-1" />
                    Export CSV
                  </button>
                  <button
                    onClick={handleGeneratePDF}
                    className="inline-flex items-center px-3 py-1.5 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                  >
                    <FileText className="h-4 w-4 mr-1" />
                    Purchase Order PDF
                  </button>
                  <button
                    onClick={handleDeleteSelected}
                    className="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                  >
                    <Trash2 className="h-4 w-4 mr-1" />
                    Delete {selectedRequirements.size} Selected
                  </button>
                </>
              )}
            </div>
          </div>

          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th scope="col" className="px-6 py-3 text-left">
                    <button
                      onClick={handleSelectAll}
                      className="flex items-center gap-2 text-xs font-medium text-gray-500 uppercase tracking-wider hover:text-gray-700"
                    >
                      {selectedRequirements.size === enrichedRequirements.length ? (
                        <CheckSquare className="h-4 w-4" />
                      ) : (
                        <Square className="h-4 w-4" />
                      )}
                      Select
                    </button>
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Material
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Period
                  </th>
                  <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Quantity Needed
                  </th>
                  <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Current Stock
                  </th>
                  <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Quantity Ordered
                  </th>
                  <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Net Quantity
                  </th>
                  <th scope="col" className="px-6 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th scope="col" className="px-6 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {enrichedRequirements.map((req) => (
                  <tr key={req.id} className={selectedRequirements.has(req.id) ? 'bg-blue-50' : ''}>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <button
                        onClick={() => handleToggleSelection(req.id)}
                        className="text-gray-400 hover:text-gray-600"
                      >
                        {selectedRequirements.has(req.id) ? (
                          <CheckSquare className="h-5 w-5 text-blue-600" />
                        ) : (
                          <Square className="h-5 w-5" />
                        )}
                      </button>
                    </td>
                    <td className="px-6 py-4">
                      <div className="text-sm font-medium text-gray-900">{req.material_code}</div>
                      <div className="text-sm text-gray-500">{req.material_name}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm text-gray-900">
                        {new Date(req.period_start).toLocaleDateString()} - {new Date(req.period_end).toLocaleDateString()}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-right">
                      <div className="text-sm font-medium text-gray-900">{req.quantity_needed.toLocaleString()}</div>
                      <div className="text-xs text-gray-500">{req.unit_measure}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-right">
                      <div className="text-sm text-gray-900">{req.current_stock.toLocaleString()}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-right">
                      <div className="text-sm text-orange-900">{(req.quantity_ordered || 0).toLocaleString()}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-right">
                      <div className="text-sm font-bold text-blue-900">{req.net_quantity.toLocaleString()}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-center">
                      {getStatusBadge(req.status)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-center">
                      <div className="flex items-center justify-center gap-2">
                        {req.status === 'pending' && (
                          <button
                            onClick={() => handleOrder(req)}
                            className="inline-flex items-center px-2 py-1 border border-transparent text-xs font-medium rounded text-blue-700 bg-blue-100 hover:bg-blue-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                          >
                            <ShoppingCart className="h-3 w-3 mr-1" />
                            Order
                          </button>
                        )}
                        {req.status === 'ordered' && (
                          <button
                            onClick={() => handleReceive(req)}
                            className="inline-flex items-center px-2 py-1 border border-transparent text-xs font-medium rounded text-green-700 bg-green-100 hover:bg-green-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                          >
                            <Package className="h-3 w-3 mr-1" />
                            Receive
                          </button>
                        )}
                        <button
                          onClick={() => handleDelete(req.id)}
                          className="inline-flex items-center px-2 py-1 border border-transparent text-xs font-medium rounded text-red-700 bg-red-100 hover:bg-red-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                        >
                          <Trash2 className="h-3 w-3" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Modals */}
      {showOrderModal && selectedRequirement && (
        <OrderMaterialModal
          requirement={selectedRequirement}
          onClose={() => {
            setShowOrderModal(false)
            setSelectedRequirement(null)
          }}
          onConfirm={async (quantity) => {
            await markAsOrdered(selectedRequirement.id, Number(quantity))
            setShowOrderModal(false)
            setSelectedRequirement(null)
          }}
        />
      )}

      {showReceiveModal && selectedRequirement && (
        <ReceivePOModal
          requirement={selectedRequirement}
          onClose={() => {
            setShowReceiveModal(false)
            setSelectedRequirement(null)
          }}
          onConfirm={async (requirementId, quantity) => {
            await receivePO(requirementId, quantity)
            setShowReceiveModal(false)
            setSelectedRequirement(null)
            reload()
          }}
        />
      )}
    </div>
  )
}
