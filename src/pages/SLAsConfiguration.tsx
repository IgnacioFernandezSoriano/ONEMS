import { useState, useMemo } from 'react'
import { useSLAs } from '@/hooks/useSLAs'
import { GenerateCombinationsModal } from '@/components/slas/GenerateCombinationsModal'
import { SLAForm } from '@/components/slas/SLAForm'
import { Modal } from '@/components/common/Modal'
import { Button } from '@/components/common/Button'
import type { SLAWithDetails } from '@/lib/types_slas'
import { useTranslation } from '@/hooks/useTranslation'

export function SLAsConfiguration() {
  const { t } = useTranslation()
  const {
    slas,
    postalCenters,
    readers,
    loading,
    error,
    createSLA,
    generateCombinations,
    updateSLA,
    updateMultiple,
    deleteSLA,
    deleteMultiple,
  } = useSLAs()

  const [showGenerateModal, setShowGenerateModal] = useState(false)
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [showFilters, setShowFilters] = useState(false)
  const [editingCell, setEditingCell] = useState<{ id: string; field: string } | null>(null)
  const [editValue, setEditValue] = useState('')

  // Filters
  const [filters, setFilters] = useState({
    sla_type: '',
    postal_center_id: '',
    from_postal_center_id: '',
    to_postal_center_id: '',
    status: '',
  })

  // Filtered SLAs
  const filteredSLAs = useMemo(() => {
    return slas.filter((sla) => {
      if (filters.sla_type && sla.sla_type !== filters.sla_type) return false
      if (filters.postal_center_id && sla.postal_center_id !== filters.postal_center_id) return false
      if (filters.from_postal_center_id && sla.from_postal_center_id !== filters.from_postal_center_id) return false
      if (filters.to_postal_center_id && sla.to_postal_center_id !== filters.to_postal_center_id) return false
      if (filters.status === 'active' && !sla.is_active) return false
      if (filters.status === 'inactive' && sla.is_active) return false
      return true
    })
  }, [slas, filters])

  const handleSelectAll = () => {
    if (selectedIds.size === filteredSLAs.length) {
      setSelectedIds(new Set())
    } else {
      setSelectedIds(new Set(filteredSLAs.map((s) => s.id)))
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

  const handleCellEdit = async (id: string, field: string, value: string) => {
    try {
      const numValue = parseFloat(value)
      if (isNaN(numValue)) return

      await updateSLA(id, { [field]: numValue } as any)
      setEditingCell(null)
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    }
  }

  const handleExportCSV = () => {
    if (selectedIds.size === 0) {
      alert(t('common.please_select_at_least_one'))
      return
    }

    const selectedRecords = filteredSLAs.filter(s => selectedIds.has(s.id))

    const headers = [
      'ID',
      'SLA Type',
      'Postal Center',
      'From Reader',
      'To Reader',
      'From Postal Center',
      'To Postal Center',
      'Expected Time (min)',
      'Time Unit',
      'On-Time %',
      'Warning Threshold',
      'Critical Threshold',
      'Active',
      'Created At',
    ]

    const rows = selectedRecords.map(record => [
      record.id,
      record.sla_type,
      record.postal_center?.name || '',
      record.from_reader?.reader_id || '',
      record.to_reader?.reader_id || '',
      record.from_postal_center?.name || '',
      record.to_postal_center?.name || '',
      record.expected_time_minutes,
      record.time_unit,
      record.on_time_percentage,
      record.warning_threshold,
      record.critical_threshold,
      record.is_active ? 'Yes' : 'No',
      record.created_at,
    ])

    const csvContent = [headers, ...rows]
      .map(row => row.map(cell => `"${cell}"`).join(','))
      .join('\n')

    const blob = new Blob([csvContent], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `slas_export_${new Date().toISOString().split('T')[0]}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  const resetFilters = () => {
    setFilters({
      sla_type: '',
      postal_center_id: '',
      from_postal_center_id: '',
      to_postal_center_id: '',
      status: '',
    })
  }

  if (loading) return <div className="p-6">Loading...</div>
  if (error) return <div className="p-6 text-red-600">Error: {error}</div>

  return (
    <div className="p-6">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">{t('slas.title')}</h1>
        <p className="text-gray-600">{t('slas.description')}</p>
      </div>

      {/* Actions */}
      <div className="mb-4 flex gap-3 flex-wrap">
        <Button onClick={() => setShowCreateModal(true)}>
          {t('slas.create_sla')}
        </Button>
        <Button onClick={() => setShowGenerateModal(true)}>
          {t('slas.generate_combinations')}
        </Button>
        <Button
          onClick={handleBulkDelete}
          disabled={selectedIds.size === 0}
          variant="danger"
        >
          {t('common.delete_selected')} ({selectedIds.size})
        </Button>
        <Button
          onClick={handleExportCSV}
          disabled={selectedIds.size === 0}
        >
          {t('common.export_csv')} ({selectedIds.size})
        </Button>
        <Button onClick={() => setShowFilters(!showFilters)}>
          {showFilters ? t('common.hide_filters') : t('common.show_filters')}
        </Button>
      </div>

      {/* Filters */}
      {showFilters && (
        <div className="mb-4 p-4 bg-gray-50 rounded-lg">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                {t('slas.sla_type')}
              </label>
              <select
                value={filters.sla_type}
                onChange={(e) => setFilters({ ...filters, sla_type: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-md"
              >
                <option value="">{t('common.all')}</option>
                <option value="operational">{t('slas.operational')}</option>
                <option value="distribution">{t('slas.distribution')}</option>
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                {t('postal_centers.postal_center')}
              </label>
              <select
                value={filters.postal_center_id}
                onChange={(e) => setFilters({ ...filters, postal_center_id: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-md"
              >
                <option value="">{t('common.all')}</option>
                {postalCenters.map(pc => (
                  <option key={pc.id} value={pc.id}>{pc.name}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                {t('common.status')}
              </label>
              <select
                value={filters.status}
                onChange={(e) => setFilters({ ...filters, status: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-md"
              >
                <option value="">{t('common.all')}</option>
                <option value="active">{t('common.active')}</option>
                <option value="inactive">{t('common.inactive')}</option>
              </select>
            </div>
          </div>

          <div className="mt-3">
            <Button onClick={resetFilters} variant="secondary">
              {t('common.reset_filters')}
            </Button>
          </div>
        </div>
      )}

      {/* Table */}
      <div className="bg-white rounded-lg shadow overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-4 py-3">
                <input
                  type="checkbox"
                  checked={selectedIds.size === filteredSLAs.length && filteredSLAs.length > 0}
                  onChange={handleSelectAll}
                />
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('slas.sla_type')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('slas.route')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('slas.expected_time')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('slas.on_time_percentage')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('slas.warning_threshold')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('slas.critical_threshold')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('common.status')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('common.actions')}
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {filteredSLAs.map((sla) => (
              <tr key={sla.id} className="hover:bg-gray-50">
                <td className="px-4 py-3">
                  <input
                    type="checkbox"
                    checked={selectedIds.has(sla.id)}
                    onChange={() => handleToggleSelect(sla.id)}
                  />
                </td>
                <td className="px-4 py-3 text-sm">
                  {t(`slas.${sla.sla_type}`)}
                </td>
                <td className="px-4 py-3 text-sm">
                  {sla.sla_type === 'operational' ? (
                    <div>
                      <div className="font-medium">{sla.postal_center?.name}</div>
                      <div className="text-gray-500 text-xs">
                        {sla.from_reader?.reader_id} → {sla.to_reader?.reader_id}
                      </div>
                    </div>
                  ) : (
                    <div className="text-xs">
                      {sla.from_postal_center?.name} → {sla.to_postal_center?.name}
                    </div>
                  )}
                </td>
                <td className="px-4 py-3 text-sm">
                  {editingCell?.id === sla.id && editingCell?.field === 'expected_time_minutes' ? (
                    <input
                      type="number"
                      value={editValue}
                      onChange={(e) => setEditValue(e.target.value)}
                      onBlur={() => handleCellEdit(sla.id, 'expected_time_minutes', editValue)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') handleCellEdit(sla.id, 'expected_time_minutes', editValue)
                        if (e.key === 'Escape') setEditingCell(null)
                      }}
                      className="w-20 px-2 py-1 border rounded"
                      autoFocus
                    />
                  ) : (
                    <span
                      onClick={() => {
                        setEditingCell({ id: sla.id, field: 'expected_time_minutes' })
                        setEditValue(sla.expected_time_minutes.toString())
                      }}
                      className="cursor-pointer hover:bg-blue-50 px-2 py-1 rounded"
                    >
                      {sla.expected_time_minutes} {t(`common.${sla.time_unit}`)}
                    </span>
                  )}
                </td>
                <td className="px-4 py-3 text-sm">
                  {editingCell?.id === sla.id && editingCell?.field === 'on_time_percentage' ? (
                    <input
                      type="number"
                      value={editValue}
                      onChange={(e) => setEditValue(e.target.value)}
                      onBlur={() => handleCellEdit(sla.id, 'on_time_percentage', editValue)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') handleCellEdit(sla.id, 'on_time_percentage', editValue)
                        if (e.key === 'Escape') setEditingCell(null)
                      }}
                      className="w-16 px-2 py-1 border rounded"
                      autoFocus
                    />
                  ) : (
                    <span
                      onClick={() => {
                        setEditingCell({ id: sla.id, field: 'on_time_percentage' })
                        setEditValue(sla.on_time_percentage.toString())
                      }}
                      className="cursor-pointer hover:bg-blue-50 px-2 py-1 rounded"
                    >
                      {sla.on_time_percentage}%
                    </span>
                  )}
                </td>
                <td className="px-4 py-3 text-sm">
                  {sla.warning_threshold}%
                </td>
                <td className="px-4 py-3 text-sm">
                  {sla.critical_threshold}%
                </td>
                <td className="px-4 py-3">
                  <span className={`px-2 py-1 text-xs rounded ${sla.is_active ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'}`}>
                    {sla.is_active ? t('common.active') : t('common.inactive')}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <button
                    onClick={async () => {
                      if (confirm(t('common.confirm_delete'))) {
                        await deleteSLA(sla.id)
                      }
                    }}
                    className="text-red-600 hover:text-red-800 text-sm"
                  >
                    {t('common.delete')}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {filteredSLAs.length === 0 && (
          <div className="p-6 text-center text-gray-500">
            {t('common.no_results')}
          </div>
        )}
      </div>

      {/* Modals */}
      {showCreateModal && (
        <Modal isOpen={showCreateModal} onClose={() => setShowCreateModal(false)} title={t('slas.create_sla')}>
          <SLAForm
            postalCenters={postalCenters}
            readers={readers}
            onSubmit={async (data) => {
              await createSLA(data)
              setShowCreateModal(false)
            }}
            onCancel={() => setShowCreateModal(false)}
          />
        </Modal>
      )}

      {showGenerateModal && (
        <GenerateCombinationsModal
          postalCenters={postalCenters}
          onGenerate={generateCombinations}
          onClose={() => setShowGenerateModal(false)}
        />
      )}
    </div>
  )
}
