import { useState, useMemo } from 'react'
import { useDeliveryStandards } from '@/hooks/useDeliveryStandards'
import { GenerateCombinationsModal } from '@/components/delivery-standards/GenerateCombinationsModal'
import { DeliveryStandardForm } from '@/components/delivery-standards/DeliveryStandardForm'
import { Modal } from '@/components/common/Modal'
import { Button } from '@/components/common/Button'
import type { DeliveryStandardWithDetails } from '@/lib/types'

import { useTranslation } from '@/hooks/useTranslation';
export function DeliveryStandards() {
  const { t } = useTranslation();
  const {
    standards,
    carriers,
    products,
    cities,
    loading,
    error,
    createStandard,
    generateCombinations,
    updateStandard,
    updateMultiple,
    deleteStandard,
    deleteMultiple,
  } = useDeliveryStandards()

  const [showGenerateModal, setShowGenerateModal] = useState(false)
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [showEditModal, setShowEditModal] = useState(false)
  const [editingStandard, setEditingStandard] = useState<DeliveryStandardWithDetails | null>(null)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [showBulkEdit, setShowBulkEdit] = useState(false)
  const [showFilters, setShowFilters] = useState(false)
  const [bulkEditData, setBulkEditData] = useState({
    standard_time: '',
    success_percentage: '',
    time_unit: 'hours' as 'hours' | 'days',
    warning_threshold: '',
    critical_threshold: '',
    threshold_type: 'relative' as 'relative' | 'absolute',
  })

  // Filters
  const [filters, setFilters] = useState({
    carrier_id: '',
    product_id: '',
    origin_city_id: '',
    destination_city_id: '',
    origin_classification: '',
    destination_classification: '',
    pending_only: false,
  })

  // Filtered standards
  const filteredStandards = useMemo(() => {
    return standards.filter((std) => {
      if (filters.carrier_id && std.carrier_id !== filters.carrier_id) return false
      if (filters.product_id && std.product_id !== filters.product_id) return false
      if (filters.origin_city_id && std.origin_city_id !== filters.origin_city_id) return false
      if (filters.destination_city_id && std.destination_city_id !== filters.destination_city_id)
        return false
      if (
        filters.origin_classification &&
        std.origin_city?.classification !== filters.origin_classification
      )
        return false
      if (
        filters.destination_classification &&
        std.destination_city?.classification !== filters.destination_classification
      )
        return false
      if (filters.pending_only && std.standard_time != null && std.success_percentage != null)
        return false

      return true
    })
  }, [standards, filters])

  const handleSelectAll = () => {
    if (selectedIds.size === filteredStandards.length) {
      setSelectedIds(new Set())
    } else {
      setSelectedIds(new Set(filteredStandards.map((s) => s.id)))
    }
  }

  const handleToggleSelect = (id: string) => {
    const newSelected = new Set(selectedIds)
    if (newSelected.has(id)) {
      newSelected.delete(id)
    } else {
      newSelected.add(id)
    }
    setSelectedIds(newSelected)
  }

  const handleBulkUpdate = async () => {
    if (selectedIds.size === 0) {
      alert(t('common.please_select_at_least_one'))
      return
    }

    const updateData: any = {}
    if (bulkEditData.standard_time) {
      updateData.standard_time = parseFloat(bulkEditData.standard_time)
    }
    if (bulkEditData.success_percentage) {
      updateData.success_percentage = parseFloat(bulkEditData.success_percentage)
    }
    if (bulkEditData.warning_threshold) {
      updateData.warning_threshold = parseFloat(bulkEditData.warning_threshold)
    }
    if (bulkEditData.critical_threshold) {
      updateData.critical_threshold = parseFloat(bulkEditData.critical_threshold)
    }
    // Always update time_unit and threshold_type from bulk edit form
    updateData.time_unit = bulkEditData.time_unit
    updateData.threshold_type = bulkEditData.threshold_type

    try {
      await updateMultiple(Array.from(selectedIds), updateData)
      setShowBulkEdit(false)
      setSelectedIds(new Set())
      setBulkEditData({ standard_time: '', success_percentage: '', time_unit: 'hours', warning_threshold: '', critical_threshold: '', threshold_type: 'relative' })
      alert(`Updated ${selectedIds.size} records successfully`)
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    }
  }

  const handleBulkDelete = async () => {
    if (selectedIds.size === 0) {
      alert(t('common.please_select_at_least_one'))
      return
    }

    if (!confirm(`Delete ${selectedIds.size} selected records?`)) return

    try {
      await deleteMultiple(Array.from(selectedIds))
      setSelectedIds(new Set())
      alert(`Deleted ${selectedIds.size} records successfully`)
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    }
  }

  const handleExportCSV = () => {
    if (selectedIds.size === 0) {
      alert(t('common.please_select_at_least_one'))
      return
    }

    // Get selected records
    const selectedRecords = filteredStandards.filter(s => selectedIds.has(s.id))

    // Define headers
    const headers = [
      'ID',
      'Carrier',
      'Product',
      'Origin City',
      'Origin Classification',
      'Destination City',
      'Destination Classification',
      'Standard Time',
      'Time Unit',
      'Success %',
      'Warning Threshold',
      'Critical Threshold',
      'Threshold Type',
      'Created Date',
      'Created Time',
      'Updated Date',
      'Updated Time'
    ]

    // Map records to CSV rows
    const rows = selectedRecords.map(record => {
      const createdAt = record.created_at ? new Date(record.created_at) : null
      const updatedAt = record.updated_at ? new Date(record.updated_at) : null

      return [
        record.id,
        record.carrier?.name || '',
        record.product?.description || '',
        record.origin_city?.name || '',
        record.origin_city?.classification || '',
        record.destination_city?.name || '',
        record.destination_city?.classification || '',
        record.standard_time != null ? record.standard_time : '',
        record.time_unit || '',
        record.success_percentage != null ? record.success_percentage : '',
        record.warning_threshold != null ? record.warning_threshold : '',
        record.critical_threshold != null ? record.critical_threshold : '',
        record.threshold_type || '',
        createdAt ? createdAt.toISOString().split('T')[0] : '',
        createdAt ? createdAt.toISOString().split('T')[1].split('.')[0] : '',
        updatedAt ? updatedAt.toISOString().split('T')[0] : '',
        updatedAt ? updatedAt.toISOString().split('T')[1].split('.')[0] : ''
      ]
    })

    // Create CSV with semicolon delimiter
    const csv = [headers, ...rows].map(row => row.join(';')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `delivery-standards-${new Date().toISOString().split('T')[0]}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  const handleCreate = async (data: any) => {
    try {
      await createStandard(data)
      setShowCreateModal(false)
      alert(t('delivery_standards.created'))
    } catch (error: any) {
      alert(`Error: ${error.message}`)
      throw error
    }
  }

  const handleEdit = async (data: any) => {
    if (!editingStandard) return
    try {
      await updateStandard(editingStandard.id, data)
      setShowEditModal(false)
      setEditingStandard(null)
      alert(t('delivery_standards.updated'))
    } catch (error: any) {
      alert(`Error: ${error.message}`)
      throw error
    }
  }

  const handleDelete = async (id: string) => {
    if (!confirm(t('delivery_standards.confirm_delete'))) return
    try {
      await deleteStandard(id)
      alert(t('delivery_standards.deleted'))
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    }
  }

  const handleInlineUpdate = async (
    id: string,
    field: 'standard_time' | 'success_percentage' | 'time_unit',
    value: any
  ) => {
    try {
      await updateStandard(id, { [field]: value })
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">{ t('delivery_standards.loading_standards')}</div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-red-500">{ t('common.error')}: {error}</div>
      </div>
    )
  }

  return (
    <div className="p-8">
      {/* Header */}
      <div className="mb-8">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-bold text-gray-900">{ t('delivery_standards.title')}</h1>
            <div className="group relative">
              <svg className="w-5 h-5 text-gray-400 hover:text-blue-600 cursor-help transition-colors" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
              </svg>
              <div className="absolute left-0 top-6 w-80 bg-gray-900 text-white text-sm rounded-lg p-4 opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all duration-200 z-50 shadow-xl">
                <div className="font-semibold mb-2">{ t('common.about')} { t('delivery_standards.title')}</div>
                <div className="space-y-2 text-gray-200">
                  <p><strong>Purpose:</strong> Define expected delivery times (J+K) and success rates between city pairs for each carrier-product combination.</p>
                  <p><strong>Key Metrics:</strong></p>
                  <ul className="list-disc list-inside ml-2 space-y-1">
                    <li><strong>J+K:</strong> Standard delivery time (e.g., J+2 means 2 days from pickup)</li>
                    <li><strong>Std %:</strong> Target percentage of deliveries meeting the J+K standard</li>
                    <li><strong>Thresholds:</strong> Warning and critical deviation levels for performance monitoring</li>
                  </ul>
                  <p><strong>Usage:</strong> These standards are used for compliance reporting, carrier performance evaluation, and SLA management.</p>
                </div>
                <div className="absolute -top-1 left-4 w-2 h-2 bg-gray-900 transform rotate-45"></div>
              </div>
            </div>
          </div>
        </div>
        <p className="text-gray-600 mt-2">
          Manage delivery time standards between cities for each carrier and product
        </p>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
        <div className="bg-gradient-to-br from-blue-50 to-white p-6 rounded-xl border border-blue-100 hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-3xl font-bold text-gray-900">{standards.length}</div>
              <div className="text-xs text-gray-500 mt-1">Total Standards</div>
            </div>
            <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center">
              <svg className="w-6 h-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
              </svg>
            </div>
          </div>
        </div>
        <div className="bg-gradient-to-br from-green-50 to-white p-6 rounded-xl border border-green-100 hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-3xl font-bold text-gray-900">
                {standards.filter((s) => s.standard_time != null && s.success_percentage != null).length}
              </div>
              <div className="text-xs text-gray-500 mt-1">{t('deliverystandards.configured')}</div>
            </div>
            <div className="w-12 h-12 bg-green-100 rounded-lg flex items-center justify-center">
              <svg className="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
        </div>
        <div className="bg-gradient-to-br from-amber-50 to-white p-6 rounded-xl border border-amber-100 hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-3xl font-bold text-gray-900">
                {standards.filter((s) => s.standard_time == null || s.success_percentage == null).length}
              </div>
              <div className="text-xs text-gray-500 mt-1">{t('stock.pending')}</div>
            </div>
            <div className="w-12 h-12 bg-amber-100 rounded-lg flex items-center justify-center">
              <svg className="w-6 h-6 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
        </div>
        <div className="bg-gradient-to-br from-purple-50 to-white p-6 rounded-xl border border-purple-100 hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-3xl font-bold text-gray-900">{selectedIds.size}</div>
              <div className="text-xs text-gray-500 mt-1">{t('deliverystandards.selected')}</div>
            </div>
            <div className="w-12 h-12 bg-purple-100 rounded-lg flex items-center justify-center">
              <svg className="w-6 h-6 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
              </svg>
            </div>
          </div>
        </div>
      </div>

      {/* Bulk Edit Panel */}
      {showBulkEdit && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <h3 className="font-medium text-blue-900 mb-3">
            Bulk Edit {selectedIds.size} Records
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Standard Time
              </label>
              <input
                type="number"
                step="0.01"
                value={bulkEditData.standard_time}
                onChange={(e) =>
                  setBulkEditData({ ...bulkEditData, standard_time: e.target.value })
                }
                className="w-full px-3 py-2 border border-gray-300 rounded-md"
                placeholder="e.g., 24"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Success %
              </label>
              <input
                type="number"
                step="0.01"
                min="0"
                max="100"
                value={bulkEditData.success_percentage}
                onChange={(e) =>
                  setBulkEditData({ ...bulkEditData, success_percentage: e.target.value })
                }
                className="w-full px-3 py-2 border border-gray-300 rounded-md"
                placeholder="e.g., 85"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Time Unit</label>
              <select
                value={bulkEditData.time_unit}
                onChange={(e) =>
                  setBulkEditData({
                    ...bulkEditData,
                    time_unit: e.target.value as 'hours' | 'days',
                  })
                }
                className="w-full px-3 py-2 border border-gray-300 rounded-md"
              >
                <option value="hours">{t('deliverystandards.hours')}</option>
                <option value="days">{t('deliverystandards.days')}</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Warning Threshold (%)
              </label>
              <input
                type="number"
                step="0.01"
                min="0"
                max="100"
                value={bulkEditData.warning_threshold}
                onChange={(e) =>
                  setBulkEditData({ ...bulkEditData, warning_threshold: e.target.value })
                }
                className="w-full px-3 py-2 border border-gray-300 rounded-md"
                placeholder="e.g., 10"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Critical Threshold (%)
              </label>
              <input
                type="number"
                step="0.01"
                min="0"
                max="100"
                value={bulkEditData.critical_threshold}
                onChange={(e) =>
                  setBulkEditData({ ...bulkEditData, critical_threshold: e.target.value })
                }
                className="w-full px-3 py-2 border border-gray-300 rounded-md"
                placeholder="e.g., 20"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                Threshold Type
                <span className="group relative">
                  <svg className="w-4 h-4 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                    <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                  </svg>
                  <div className="invisible group-hover:visible absolute z-10 w-80 p-3 bg-gray-900 text-white text-xs rounded-lg shadow-lg -top-2 left-6">
                    <div className="font-semibold mb-2">Tipo de Cálculo de Thresholds:</div>
                    <div className="space-y-2">
                      <div>
                        <span className="font-semibold text-blue-300">Relativo:</span> Los thresholds se calculan como % del Success %.<br/>
                        <span className="text-gray-300">Ejemplo: Success=95%, Warning=5% → Límite=90.25% (95% - 95%×5%)</span>
                      </div>
                      <div>
                        <span className="font-semibold text-green-300">Absoluto:</span> Los thresholds se calculan como % del 100%.<br/>
                        <span className="text-gray-300">Ejemplo: Success=95%, Warning=10% → Límite=90% (100% - 10%)</span>
                      </div>
                    </div>
                  </div>
                </span>
              </label>
              <select
                value={bulkEditData.threshold_type}
                onChange={(e) =>
                  setBulkEditData({
                    ...bulkEditData,
                    threshold_type: e.target.value as 'relative' | 'absolute',
                  })
                }
                className="w-full px-3 py-2 border border-gray-300 rounded-md"
              >
                <option value="relative">Relativo (% del Success %)</option>
                <option value="absolute">Absoluto (% del 100%)</option>
              </select>
            </div>
          </div>
          <div className="flex items-end gap-2 mt-4">
            <Button onClick={handleBulkUpdate} className="flex-1">
              Apply
            </Button>
            <Button variant="secondary" onClick={() => setShowBulkEdit(false)}>
              Cancel
            </Button>
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="bg-white rounded-lg shadow p-4 mb-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <button
              onClick={() => setShowFilters(!showFilters)}
              className="p-1 hover:bg-gray-100 rounded transition-colors"
              title={showFilters ? "Collapse filters" : "Expand filters"}
            >
              {showFilters ? (
                <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 15l7-7 7 7" />
                </svg>
              ) : (
                <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                </svg>
              )}
            </button>
            <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
            </svg>
            <h3 className="text-lg font-semibold text-gray-900">{t('stock.filters')}</h3>
            {(filters.carrier_id || filters.product_id || filters.origin_city_id || filters.destination_city_id || filters.origin_classification || filters.destination_classification || filters.pending_only) && (
              <span className="text-xs bg-blue-100 text-blue-700 px-2 py-0.5 rounded-full font-medium">
                Active
              </span>
            )}
          </div>
          <div className="flex items-center gap-2">
            <Button onClick={() => setShowCreateModal(true)}>+ Create Standard</Button>
            <Button onClick={() => setShowGenerateModal(true)}>⚡ Generate Combinations</Button>
            {selectedIds.size > 0 && (
              <>
                <Button variant="secondary" onClick={() => setShowBulkEdit(!showBulkEdit)}>
                  ✏️ Bulk Edit ({selectedIds.size})
                </Button>
                <Button variant="secondary" onClick={handleBulkDelete}>
                  🗑️ Delete Selected
                </Button>
                <Button variant="secondary" onClick={handleExportCSV}>
                  📥 Export CSV ({selectedIds.size})
                </Button>
              </>
            )}
            <button
              onClick={() => setFilters({
                carrier_id: '',
                product_id: '',
                origin_city_id: '',
                destination_city_id: '',
                origin_classification: '',
                destination_classification: '',
                pending_only: false,
              })}
              className="flex items-center gap-2 px-3 py-1.5 text-sm text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
              title="Reset all filters"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
              Reset
            </button>
          </div>
        </div>
        
        {showFilters && (
          <div className="border-t border-gray-200 pt-4">
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div>
            <label className="flex items-center gap-1 text-sm font-medium text-gray-700 mb-1">
              Carrier
              <span className="group relative">
                <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                </svg>
                <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                  Filter standards by specific carrier. Shows only standards for the selected carrier.
                </div>
              </span>
            </label>
            <select
              value={filters.carrier_id}
              onChange={(e) => setFilters({ ...filters, carrier_id: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
            >
              <option value="">All Carriers</option>
              {carriers.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="flex items-center gap-1 text-sm font-medium text-gray-700 mb-1">
              Product
              <span className="group relative">
                <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                </svg>
                <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                  Filter standards by carrier product/service type. Shows only standards for the selected product.
                </div>
              </span>
            </label>
            <select
              value={filters.product_id}
              onChange={(e) => setFilters({ ...filters, product_id: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
            >
              <option value="">All Products</option>
              {products.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.description}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="flex items-center gap-1 text-sm font-medium text-gray-700 mb-1">
              Origin City
              <span className="group relative">
                <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                </svg>
                <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                  Filter standards by origin city (where packages are picked up). Shows only routes starting from the selected city.
                </div>
              </span>
            </label>
            <select
              value={filters.origin_city_id}
              onChange={(e) => setFilters({ ...filters, origin_city_id: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
            >
              <option value="">All Cities</option>
              {cities.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="flex items-center gap-1 text-sm font-medium text-gray-700 mb-1">
              Destination City
              <span className="group relative">
                <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                </svg>
                <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                  Filter standards by destination city (where packages are delivered). Shows only routes ending in the selected city.
                </div>
              </span>
            </label>
            <select
              value={filters.destination_city_id}
              onChange={(e) => setFilters({ ...filters, destination_city_id: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
            >
              <option value="">All Cities</option>
              {cities.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="flex items-center gap-1 text-sm font-medium text-gray-700 mb-1">
              Origin Type
              <span className="group relative">
                <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                </svg>
                <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                  Filter by origin city classification (A, B, or C). Shows only routes starting from cities of the selected type.
                </div>
              </span>
            </label>
            <select
              value={filters.origin_classification}
              onChange={(e) =>
                setFilters({ ...filters, origin_classification: e.target.value })
              }
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
            >
              <option value="">All Types</option>
              <option value="A">Type A</option>
              <option value="B">Type B</option>
              <option value="C">Type C</option>
            </select>
          </div>
          <div>
            <label className="flex items-center gap-1 text-sm font-medium text-gray-700 mb-1">
              Destination Type
              <span className="group relative">
                <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                </svg>
                <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                  Filter by destination city classification (A, B, or C). Shows only routes ending in cities of the selected type.
                </div>
              </span>
            </label>
            <select
              value={filters.destination_classification}
              onChange={(e) =>
                setFilters({ ...filters, destination_classification: e.target.value })
              }
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
            >
              <option value="">All Types</option>
              <option value="A">Type A</option>
              <option value="B">Type B</option>
              <option value="C">Type C</option>
            </select>
          </div>
          <div className="flex items-end">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={filters.pending_only}
                onChange={(e) => setFilters({ ...filters, pending_only: e.target.checked })}
                className="rounded"
              />
              <span className="flex items-center gap-1 text-sm font-medium text-gray-700">
                Pending Only
                <span className="group relative">
                  <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                    <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                  </svg>
                  <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                    Show only standards that are not yet configured (missing J+K or Std % values). Useful for identifying routes that need configuration.
                  </div>
                </span>
              </span>
            </label>
          </div>
            </div>
          </div>
        )}
      </div>

      {/* Table */}
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left">
                  <input
                    type="checkbox"
                    checked={
                      filteredStandards.length > 0 &&
                      selectedIds.size === filteredStandards.length
                    }
                    onChange={handleSelectAll}
                    className="rounded"
                  />
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  <div className="flex items-center gap-1">
                    Carrier
                    <span className="group relative">
                      <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                        Logistics carrier responsible for delivery (e.g., DHL, FedEx)
                      </div>
                    </span>
                  </div>
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  <div className="flex items-center gap-1">
                    Product
                    <span className="group relative">
                      <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                        Carrier's product/service type (e.g., Express, Standard, Economy)
                      </div>
                    </span>
                  </div>
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  <div className="flex items-center gap-1">
                    Origin
                    <span className="group relative">
                      <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                        City where the package is picked up (origin city)
                      </div>
                    </span>
                  </div>
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  <div className="flex items-center gap-1">
                    Destination
                    <span className="group relative">
                      <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                        City where the package is delivered (destination city)
                      </div>
                    </span>
                  </div>
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  <div className="flex items-center gap-1">
                    J+K
                    <span className="group relative">
                      <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                        Standard delivery time (J+K notation). J = pickup day, K = number of days. Example: J+2 means delivery within 2 days from pickup.
                      </div>
                    </span>
                  </div>
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  <div className="flex items-center gap-1">
                    Unit
                    <span className="group relative">
                      <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                        Time unit for the J+K value (hours or days)
                      </div>
                    </span>
                  </div>
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  <div className="flex items-center gap-1">
                    Std %
                    <span className="group relative">
                      <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                        Target percentage of deliveries that must meet the J+K standard. Example: 85% means at least 85 out of 100 deliveries should arrive within J+K time.
                      </div>
                    </span>
                  </div>
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  <div className="flex items-center gap-1">
                    Warning %
                    <span className="group relative">
                      <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                        Acceptable deviation from Std % without penalty. Example: If Std % is 85% and Warning is 10%, performance between 75-85% triggers a warning but no penalty.
                      </div>
                    </span>
                  </div>
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  <div className="flex items-center gap-1">
                    Critical %
                    <span className="group relative">
                      <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                        Critical deviation from Std % that triggers penalties. Example: If Std % is 85% and Critical is 20%, performance below 65% results in carrier penalties.
                      </div>
                    </span>
                  </div>
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  <div className="flex items-center gap-1">
                    Type
                    <span className="group relative">
                      <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                        Threshold calculation type: Relative (percentage-based) or Absolute (fixed value)
                      </div>
                    </span>
                  </div>
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  <div className="flex items-center gap-1">
                    Actions
                    <span className="group relative">
                      <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                        Edit or delete this delivery standard
                      </div>
                    </span>
                  </div>
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {filteredStandards.map((std) => (
                <tr
                  key={std.id}
                  className={selectedIds.has(std.id) ? 'bg-blue-50' : 'hover:bg-gray-50'}
                >
                  <td className="px-4 py-4">
                    <input
                      type="checkbox"
                      checked={selectedIds.has(std.id)}
                      onChange={() => handleToggleSelect(std.id)}
                      className="rounded"
                    />
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-900">{std.carrier?.name}</td>
                  <td className="px-6 py-4 text-sm text-gray-900">{std.product?.description}</td>
                  <td className="px-6 py-4 text-sm">
                    <div>{std.origin_city?.name}</div>
                    {std.origin_city?.classification && (
                      <div className="text-xs text-gray-500">
                        Type {std.origin_city.classification}
                      </div>
                    )}
                  </td>
                  <td className="px-6 py-4 text-sm">
                    <div>{std.destination_city?.name}</div>
                    {std.destination_city?.classification && (
                      <div className="text-xs text-gray-500">
                        Type {std.destination_city.classification}
                      </div>
                    )}
                  </td>
                  <td className="px-6 py-4">
                    <input
                      type="number"
                      step="0.01"
                      value={std.standard_time || ''}
                      onChange={(e) =>
                        handleInlineUpdate(
                          std.id,
                          'standard_time',
                          e.target.value ? parseFloat(e.target.value) : null
                        )
                      }
                      className="w-20 px-2 py-1 border border-gray-300 rounded text-sm"
                      placeholder="--"
                    />
                  </td>
                  <td className="px-6 py-4">
                    <select
                      value={std.time_unit}
                      onChange={(e) =>
                        handleInlineUpdate(std.id, 'time_unit', e.target.value)
                      }
                      className="px-2 py-1 border border-gray-300 rounded text-sm"
                    >
                      <option value="hours">{t('deliverystandards.hours')}</option>
                      <option value="days">{t('deliverystandards.days')}</option>
                    </select>
                  </td>
                  <td className="px-6 py-4">
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      max="100"
                      value={std.success_percentage || ''}
                      onChange={(e) =>
                        handleInlineUpdate(
                          std.id,
                          'success_percentage',
                          e.target.value ? parseFloat(e.target.value) : null
                        )
                      }
                      className="w-20 px-2 py-1 border border-gray-300 rounded text-sm"
                      placeholder="--"
                    />
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-500">
                    {std.warning_threshold != null ? `${std.warning_threshold}%` : '-'}
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-500">
                    {std.critical_threshold != null ? `${std.critical_threshold}%` : '-'}
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-500">
                    {std.threshold_type === 'relative' ? 'Rel' : std.threshold_type === 'absolute' ? 'Abs' : '-'}
                  </td>
                  <td className="px-6 py-4">
                    <div className="flex gap-2">
                      <button
                        onClick={() => {
                          setEditingStandard(std)
                          setShowEditModal(true)
                        }}
                        className="text-blue-600 hover:text-blue-800 text-sm"
                      >
                        Edit
                      </button>
                      <button
                        onClick={() => handleDelete(std.id)}
                        className="text-red-600 hover:text-red-800 text-sm"
                      >
                        Delete
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          {filteredStandards.length === 0 && (
            <div className="text-center py-12 text-gray-500">
              No delivery standards found. Generate combinations to get started.
            </div>
          )}
        </div>
      </div>

      {/* Generate Modal */}
      <GenerateCombinationsModal
        isOpen={showGenerateModal}
        onClose={() => setShowGenerateModal(false)}
        carriers={carriers}
        products={products}
        cities={cities}
        onGenerate={generateCombinations}
      />

      {/* Create Modal */}
      <Modal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        title="Create Delivery Standard"
      >
        <DeliveryStandardForm
          carriers={carriers}
          products={products}
          cities={cities}
          onSubmit={handleCreate}
          onCancel={() => setShowCreateModal(false)}
        />
      </Modal>

      {/* Edit Modal */}
      <Modal
        isOpen={showEditModal}
        onClose={() => {
          setShowEditModal(false)
          setEditingStandard(null)
        }}
        title="Edit Delivery Standard"
      >
        {editingStandard && (
          <DeliveryStandardForm
            standard={editingStandard}
            carriers={carriers}
            products={products}
            cities={cities}
            onSubmit={handleEdit}
            onCancel={() => {
              setShowEditModal(false)
              setEditingStandard(null)
            }}
          />
        )}
      </Modal>
    </div>
  )
}
