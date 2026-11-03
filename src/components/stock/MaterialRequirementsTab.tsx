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
    { name: t('hc.material_requirements_tab.month_jan'), num: 1 }, { name: t('hc.material_requirements_tab.month_feb'), num: 2 }, { name: t('hc.material_requirements_tab.month_mar'), num: 3 },
    { name: t('hc.material_requirements_tab.month_apr'), num: 4 }, { name: t('hc.material_requirements_tab.month_may'), num: 5 }, { name: t('hc.material_requirements_tab.month_jun'), num: 6 },
    { name: t('hc.material_requirements_tab.month_jul'), num: 7 }, { name: t('hc.material_requirements_tab.month_aug'), num: 8 }, { name: t('hc.material_requirements_tab.month_sep'), num: 9 },
    { name: t('hc.material_requirements_tab.month_oct'), num: 10 }, { name: t('hc.material_requirements_tab.month_nov'), num: 11 }, { name: t('hc.material_requirements_tab.month_dec'), num: 12 }
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
      alert(t('stock.please_select_dates'))
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
    
    const confirmed = confirm(t('hc.material_requirements_tab.confirm_mark_ordered', { count: selectedRequirements.size }))
    if (!confirmed) return

    for (const reqId of selectedRequirements) {
      await markAsOrdered(reqId, null) // null = use net quantity as default
    }
    
    setSelectedRequirements(new Set())
  }

  const handleDelete = async (requirementId: string) => {
    const confirmed = confirm(t('hc.material_requirements_tab.confirm_delete'))
    if (!confirmed) return

    try {
      await deleteRequirement(requirementId)
      alert(t('hc.material_requirements_tab.deleted_ok'))
    } catch (error: any) {
      alert(t('hc.material_requirements_tab.error_deleting', { message: error.message }))
    }
  }

  const handleDeleteSelected = async () => {
    if (selectedRequirements.size === 0) return
    
    const confirmed = confirm(t('hc.material_requirements_tab.confirm_delete_selected', { count: selectedRequirements.size }))
    if (!confirmed) return

    try {
      for (const reqId of selectedRequirements) {
        await deleteRequirement(reqId)
      }
      alert(t('hc.material_requirements_tab.deleted_selected_ok', { count: selectedRequirements.size }))
      setSelectedRequirements(new Set())
    } catch (error: any) {
      alert(t('hc.material_requirements_tab.error_deleting_many', { message: error.message }))
    }
  }

  const handleExportCSV = () => {
    if (selectedRequirements.size === 0) {
      alert(t('stock.please_select_requirements_export'))
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
        'Quantity Ordered': r.quantity_ordered || 0,
        'Unit': r.unit_measure,
        'Status': r.status,
        'Period': `${r.period_start} to ${r.period_end}`
      }))

    downloadCSV(selectedData, `material-requirements-${new Date().toISOString().split('T')[0]}.csv`)
  }

  const handleGeneratePDF = () => {
    if (selectedRequirements.size === 0) {
      alert(t('stock.please_select_requirements_po'))
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
    
    const statusLabels: Record<string, string> = {
      pending: t('stock.pending'),
      ordered: t('stock.ordered'),
      received: t('stock.received')
    }

    return (
      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${styles[status as keyof typeof styles] || styles.pending}`}>
        {statusLabels[status] ?? status.charAt(0).toUpperCase() + status.slice(1)}
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
              <span className="font-medium text-gray-900">{t('stock.metrics_overview')}</span>
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
                      <p className="text-sm font-medium text-yellow-800">{t('stock.pending_requirements')}</p>
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
            <span className="font-medium text-gray-900">{t('stock.calculate_requirements')}</span>
          </div>
          <span className="text-sm text-gray-500">
            {isFiltersCollapsed ? t('common.show') : t('common.hide')}
          </span>
        </button>

        {!isFiltersCollapsed && (
          <div className="px-4 pb-4 space-y-4">
            {/* Date Filters */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  {t('common.start_date')}
                  <SmartTooltip content={t('hc.material_requirements_tab.tip_start_date')} />
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
                  {t('common.end_date')}
                  <SmartTooltip content={t('hc.material_requirements_tab.tip_end_date')} />
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
                  {t('common.material')}
                  <SmartTooltip content={t('hc.material_requirements_tab.tip_material')} />
                </label>
                <select
                  value={selectedMaterialId}
                  onChange={(e) => setSelectedMaterialId(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                >
                  <option value="">{t('stock.all_materials')}</option>
                  {materials.map(m => (
                    <option key={m.id} value={m.id}>{m.code} - {m.name}</option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  {t('common.status')}
                  <SmartTooltip content={t('hc.material_requirements_tab.tip_status')} />
                </label>
                <select
                  value={selectedStatus}
                  onChange={(e) => setSelectedStatus(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                >
                  <option value="">{t('common.all_status')}</option>
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
                {t('stock.quick_month_selection')}
                <SmartTooltip content={t('hc.material_requirements_tab.tip_months')} />
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
                    {t('hc.material_requirements_tab.first_semester')}
                  </button>
                  <button
                    onClick={handleSecondSemesterSelect}
                    className="px-3 py-1 text-sm font-medium rounded-md border border-teal-300 bg-teal-50 hover:bg-teal-100 hover:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500"
                  >
                    {t('hc.material_requirements_tab.second_semester')}
                  </button>
                  <button
                    onClick={handleYearSelect}
                    className="px-3 py-1 text-sm font-medium rounded-md border border-purple-300 bg-purple-50 hover:bg-purple-100 hover:border-purple-500 focus:outline-none focus:ring-2 focus:ring-purple-500"
                  >
                    {t('hc.material_requirements_tab.year')}
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
                {loadingRequirements ? t('stock.calculating') : t('stock.calculate_requirements')}
              </button>
              <SmartTooltip content={[
                t('hc.material_requirements_tab.calc_tip_intro'),
                '',
                t('hc.material_requirements_tab.calc_tip_s1'),
                t('hc.material_requirements_tab.calc_tip_s2'),
                t('hc.material_requirements_tab.calc_tip_s3'),
                t('hc.material_requirements_tab.calc_tip_s4'),
                t('hc.material_requirements_tab.calc_tip_s5'),
                t('hc.material_requirements_tab.calc_tip_s6'),
                '',
                t('hc.material_requirements_tab.calc_tip_formula'),
                '',
                t('hc.material_requirements_tab.calc_tip_unif_title'),
                t('hc.material_requirements_tab.calc_tip_unif1'),
                t('hc.material_requirements_tab.calc_tip_unif2'),
                t('hc.material_requirements_tab.calc_tip_unif3')
              ].join('\n')}>
                <Info className="h-5 w-5 text-blue-500 cursor-help" />
              </SmartTooltip>

              <button
                onClick={handleResetFilters}
                className="inline-flex items-center px-3 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                <RotateCcw className="h-4 w-4 mr-1" />
                {t('hc.material_requirements_tab.reset')}
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
              {t('stock.material_requirements_tab')} ({enrichedRequirements.length})
            </h3>
            <div className="flex items-center gap-2">
              {selectedRequirements.size > 0 && (
                <>
                  <button
                    onClick={handleMarkSelectedAsOrdered}
                    className="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                  >
                    <ShoppingCart className="h-4 w-4 mr-1" />
                    {t('stock.mark_as_ordered', { count: selectedRequirements.size })}
                  </button>
                  <button
                    onClick={handleExportCSV}
                    className="inline-flex items-center px-3 py-1.5 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                  >
                    <Download className="h-4 w-4 mr-1" />
                    {t('common.export_csv')}
                  </button>
                  <button
                    onClick={handleGeneratePDF}
                    className="inline-flex items-center px-3 py-1.5 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                  >
                    <FileText className="h-4 w-4 mr-1" />
                    {t('stock.purchase_order_pdf')}
                  </button>
                  <button
                    onClick={handleDeleteSelected}
                    className="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                  >
                    <Trash2 className="h-4 w-4 mr-1" />
                    {t('stock.delete_selected', { count: selectedRequirements.size })}
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
                      {t('common.select')}
                    </button>
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    {t('common.material')}
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    {t('stock.period')}
                  </th>
                  <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    {t('stock.quantity_needed')}
                  </th>
                  <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    {t('stock.current_stock')}
                  </th>
                  <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    {t('stock.net_quantity')}
                  </th>
                  <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    {t('stock.quantity_ordered')}
                  </th>
                  <th scope="col" className="px-6 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                    {t('common.status')}
                  </th>
                  <th scope="col" className="px-6 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                    {t('common.actions')}
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
                      <div className="text-sm font-bold text-blue-900">{req.net_quantity.toLocaleString()}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-right">
                      <div className="text-sm text-orange-900">{(req.quantity_ordered || 0).toLocaleString()}</div>
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
                            {t('stock.order')}
                          </button>
                        )}
                        {req.status === 'ordered' && (
                          <button
                            onClick={() => handleReceive(req)}
                            className="inline-flex items-center px-2 py-1 border border-transparent text-xs font-medium rounded text-green-700 bg-green-100 hover:bg-green-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                          >
                            <Package className="h-3 w-3 mr-1" />
                            {t('hc.material_requirements_tab.receive')}
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
