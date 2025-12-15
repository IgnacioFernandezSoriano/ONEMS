import { useState, useMemo } from 'react'
import { useDeliveryStandards } from '@/hooks/useDeliveryStandards'
import { GenerateCombinationsModal } from '@/components/delivery-standards/GenerateCombinationsModal'
import { DeliveryStandardForm } from '@/components/delivery-standards/DeliveryStandardForm'
import { Modal } from '@/components/common/Modal'
import { Button } from '@/components/common/Button'
import type { DeliveryStandardWithDetails } from '@/lib/types'

export function DeliveryStandards() {
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
      alert('Please select at least one record')
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
      alert('Please select at least one record')
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

  const handleCreate = async (data: any) => {
    try {
      await createStandard(data)
      setShowCreateModal(false)
      alert('Delivery standard created successfully')
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
      alert('Delivery standard updated successfully')
    } catch (error: any) {
      alert(`Error: ${error.message}`)
      throw error
    }
  }

  const handleDelete = async (id: string) => {
    if (!confirm('Delete this delivery standard?')) return
    try {
      await deleteStandard(id)
      alert('Delivery standard deleted successfully')
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
        <div className="text-gray-500">Loading delivery standards...</div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-red-500">Error: {error}</div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Delivery Standards</h1>
        <p className="text-gray-600 mt-1">
          Manage delivery time standards between cities for each carrier and product
        </p>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="bg-white p-6 rounded-lg border">
          <div className="text-3xl font-bold text-blue-600">{standards.length}</div>
          <div className="text-sm text-gray-600 mt-1">Total Standards</div>
        </div>
        <div className="bg-white p-6 rounded-lg border">
          <div className="text-3xl font-bold text-green-600">
            {standards.filter((s) => s.standard_time != null && s.success_percentage != null).length}
          </div>
          <div className="text-sm text-gray-600 mt-1">Configured</div>
        </div>
        <div className="bg-white p-6 rounded-lg border">
          <div className="text-3xl font-bold text-amber-600">
            {standards.filter((s) => s.standard_time == null || s.success_percentage == null).length}
          </div>
          <div className="text-sm text-gray-600 mt-1">Pending</div>
        </div>
        <div className="bg-white p-6 rounded-lg border">
          <div className="text-3xl font-bold text-purple-600">{selectedIds.size}</div>
          <div className="text-sm text-gray-600 mt-1">Selected</div>
        </div>
      </div>

      {/* Actions */}
      <div className="flex gap-2 flex-wrap">
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
          </>
        )}
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
                <option value="hours">Hours</option>
                <option value="days">Days</option>
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
      <div className="bg-white rounded-lg border p-4">
        <h3 className="font-medium text-gray-900 mb-3">Filters</h3>
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Carrier</label>
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
            <label className="block text-sm font-medium text-gray-700 mb-1">Product</label>
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
            <label className="block text-sm font-medium text-gray-700 mb-1">Origin City</label>
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
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Destination City
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
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Origin Type
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
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Destination Type
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
              <span className="text-sm font-medium text-gray-700">Pending Only</span>
            </label>
          </div>
          <div className="flex items-end">
            <Button
              variant="secondary"
              onClick={() =>
                setFilters({
                  carrier_id: '',
                  product_id: '',
                  origin_city_id: '',
                  destination_city_id: '',
                  origin_classification: '',
                  destination_classification: '',
                  pending_only: false,
                })
              }
              className="w-full"
            >
              Clear Filters
            </Button>
          </div>
        </div>
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
                  Carrier
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Product
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Origin
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Destination
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Time
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Success %
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Unit
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  <div className="flex items-center gap-1">
                    Warning %
                    <span className="group relative">
                      <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                        <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                      </svg>
                      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                        Desviación sin penalización
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
                        Desviación con penalización
                      </div>
                    </span>
                  </div>
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Type
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Actions
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
                  <td className="px-6 py-4">
                    <select
                      value={std.time_unit}
                      onChange={(e) =>
                        handleInlineUpdate(std.id, 'time_unit', e.target.value)
                      }
                      className="px-2 py-1 border border-gray-300 rounded text-sm"
                    >
                      <option value="hours">Hours</option>
                      <option value="days">Days</option>
                    </select>
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
