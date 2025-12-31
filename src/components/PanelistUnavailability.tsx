import { useState, useEffect, useMemo } from 'react'
import { usePanelistUnavailability } from '@/lib/hooks/usePanelistUnavailability'
import { supabase } from '@/lib/supabase'
import type { Panelist, PanelistUnavailability } from '@/lib/types'

import { useTranslation } from '@/hooks/useTranslation';
export function PanelistUnavailabilityComponent() {
  const { t } = useTranslation();
  const { unavailabilityPeriods, loading, error, createUnavailabilityPeriod, updateUnavailabilityPeriod, deleteUnavailabilityPeriod } = usePanelistUnavailability()
  const [showModal, setShowModal] = useState(false)
  const [editingPeriod, setEditingPeriod] = useState<any>(null)
  const [panelists, setPanelists] = useState<Panelist[]>([])
  
  // Filters state
  const [showFilters, setShowFilters] = useState(true)
  const [filters, setFilters] = useState({
    panelist_id: '',
    status: '',
    reason: '',
    date_range: 'all' as 'all' | 'current' | 'upcoming' | 'past',
    search: '',
  })

  // Selection state
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  
  // Form state
  const [formData, setFormData] = useState({
    panelist_id: '',
    start_date: '',
    end_date: '',
    reason: 'vacation' as 'vacation' | 'sick' | 'personal' | 'training' | 'other',
    notes: '',
    status: 'active' as 'active' | 'cancelled',
  })

  useEffect(() => {
    fetchPanelists()
  }, [])

  const fetchPanelists = async () => {
    const { data } = await supabase
      .from('panelists')
      .select('*, node:nodes(*, city:cities(*))')
      .eq('status', 'active')
      .order('panelist_code')
    if (data) setPanelists(data as any)
  }

  // Filtered periods
  const filteredPeriods = useMemo(() => {
    if (!unavailabilityPeriods) return []
    
    const today = new Date().toISOString().split('T')[0]
    
    return unavailabilityPeriods.filter(period => {
      if (filters.panelist_id && period.panelist_id !== filters.panelist_id) return false
      if (filters.status && period.status !== filters.status) return false
      if (filters.reason && period.reason !== filters.reason) return false
      
      // Date range filter
      if (filters.date_range === 'current') {
        if (period.start_date > today || period.end_date < today) return false
      } else if (filters.date_range === 'upcoming') {
        if (period.start_date <= today) return false
      } else if (filters.date_range === 'past') {
        if (period.end_date >= today) return false
      }
      
      if (filters.search) {
        const search = filters.search.toLowerCase()
        const matchesPanelist = period.panelist?.name?.toLowerCase().includes(search)
        const matchesNotes = period.notes?.toLowerCase().includes(search)
        if (!matchesPanelist && !matchesNotes) return false
      }
      return true
    })
  }, [unavailabilityPeriods, filters])

  // Selection handlers
  const handleSelectAll = () => {
    if (selectedIds.size === filteredPeriods.length) {
      setSelectedIds(new Set())
    } else {
      setSelectedIds(new Set(filteredPeriods.map(p => p.id)))
    }
  }

  const handleSelectOne = (id: string) => {
    const newSelected = new Set(selectedIds)
    if (newSelected.has(id)) {
      newSelected.delete(id)
    } else {
      newSelected.add(id)
    }
    setSelectedIds(newSelected)
  }

  // Bulk operations
  const handleBulkCancel = async () => {
    if (!confirm(`Are you sure you want to cancel ${selectedIds.size} unavailability period(s)?`)) return
    
    for (const id of selectedIds) {
      await updateUnavailabilityPeriod(id, { status: 'cancelled' })
    }
    setSelectedIds(new Set())
  }

  const handleBulkDelete = async () => {
    if (!confirm(`Are you sure you want to delete ${selectedIds.size} unavailability period(s)? This action cannot be undone.`)) return
    
    for (const id of selectedIds) {
      await deleteUnavailabilityPeriod(id)
    }
    setSelectedIds(new Set())
  }

  const clearFilters = () => {
    setFilters({
      panelist_id: '',
      status: '',
      reason: '',
      date_range: 'all',
      search: '',
    })
  }

  const handleOpenModal = (period?: any) => {
    if (period) {
      setEditingPeriod(period)
      setFormData({
        panelist_id: period.panelist_id,
        start_date: period.start_date,
        end_date: period.end_date,
        reason: period.reason,
        notes: period.notes || '',
        status: period.status,
      })
    } else {
      setEditingPeriod(null)
      setFormData({
        panelist_id: '',
        start_date: '',
        end_date: '',
        reason: 'vacation',
        notes: '',
        status: 'active',
      })
    }
    setShowModal(true)
  }

  const handleCloseModal = () => {
    setShowModal(false)
    setEditingPeriod(null)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    try {
      if (editingPeriod) {
        await updateUnavailabilityPeriod(editingPeriod.id, formData)
      } else {
        await createUnavailabilityPeriod(formData)
      }
      handleCloseModal()
    } catch (err) {
      console.error('Error saving unavailability period:', err)
      alert('Error saving unavailability period')
    }
  }

  const handleDelete = async (id: string) => {
    if (!confirm('Are you sure you want to delete this unavailability period?')) return
    await deleteUnavailabilityPeriod(id)
  }

  const handleToggleStatus = async (period: any) => {
    const newStatus = period.status === 'active' ? 'cancelled' : 'active'
    await updateUnavailabilityPeriod(period.id, { status: newStatus })
  }

  const getStatusBadgeClass = (status: string) => {
    switch (status) {
      case 'active':
        return 'bg-green-100 text-green-800'
      case 'cancelled':
        return 'bg-gray-100 text-gray-800'
      default:
        return 'bg-gray-100 text-gray-800'
    }
  }

  const getReasonBadgeClass = (reason: string) => {
    switch (reason) {
      case 'vacation':
        return 'bg-blue-100 text-blue-800'
      case 'sick':
        return 'bg-red-100 text-red-800'
      case 'personal':
        return 'bg-purple-100 text-purple-800'
      case 'training':
        return 'bg-yellow-100 text-yellow-800'
      case 'other':
        return 'bg-gray-100 text-gray-800'
      default:
        return 'bg-gray-100 text-gray-800'
    }
  }

  const isCurrentPeriod = (startDate: string, endDate: string) => {
    const today = new Date().toISOString().split('T')[0]
    return startDate <= today && endDate >= today
  }

  if (loading) return <div className="p-6">Loading...</div>
  if (error) return <div className="p-6 text-red-600">Error: {error}</div>

  return (
    <div>
      <div className="flex justify-between items-center mb-6">
        <div>
          <h2 className="text-xl font-bold">{t('unavailability.title')}</h2>
          <p className="text-sm text-gray-600 mt-1">
            {t('unavailability.description')}
          </p>
        </div>
        <button
          onClick={() => handleOpenModal()}
          className="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
        >
          {t('unavailability.add_period')}
        </button>
      </div>

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
            {(filters.search || filters.panelist_id || filters.date_range !== 'all' || filters.reason || filters.status) && (
              <span className="text-xs bg-blue-100 text-blue-700 px-2 py-0.5 rounded-full font-medium">
                Active
              </span>
            )}
          </div>
          <button
            onClick={clearFilters}
            className="flex items-center gap-2 px-3 py-1.5 text-sm text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
            title="Reset all filters"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            Reset
          </button>
        </div>
        
        {showFilters && (
          <div className="border-t border-gray-200 pt-4">
            <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  <div className="flex items-center gap-1">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                    </svg>
                    Search
                  </div>
                </label>
                <input
                  type="text"
                  value={filters.search}
                  onChange={(e) => setFilters({ ...filters, search: e.target.value })}
                  placeholder={t('unavailability.search_placeholder')}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  <div className="flex items-center gap-1">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                    </svg>
                    {t('unavailability.panelist')}
                  </div>
                </label>
                <select
                  value={filters.panelist_id}
                  onChange={(e) => setFilters({ ...filters, panelist_id: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                >
                  <option value="">{t('unavailability.all_panelists')}</option>
                  {panelists.map(panelist => (
                    <option key={panelist.id} value={panelist.id}>
                      {panelist.panelist_code} - {panelist.name}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  <div className="flex items-center gap-1">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                    {t('unavailability.date_range')}
                  </div>
                </label>
                <select
                  value={filters.date_range}
                  onChange={(e) => setFilters({ ...filters, date_range: e.target.value as any })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                >
                  <option value="all">{t('unavailability.all_periods')}</option>
                  <option value="current">{t('unavailability.current_periods')}</option>
                  <option value="upcoming">{t('unavailability.upcoming_periods')}</option>
                  <option value="past">{t('unavailability.past_periods')}</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  <div className="flex items-center gap-1">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z" />
                    </svg>
                    {t('unavailability.reason')}
                  </div>
                </label>
                <select
                  value={filters.reason}
                  onChange={(e) => setFilters({ ...filters, reason: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                >
                  <option value="">{t('unavailability.all_reasons')}</option>
                  <option value="vacation">{t('unavailability.reason_vacation')}</option>
                  <option value="sick">{t('unavailability.reason_sick')}</option>
                  <option value="personal">{t('unavailability.reason_personal')}</option>
                  <option value="training">{t('unavailability.reason_training')}</option>
                  <option value="other">{t('unavailability.reason_other')}</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  <div className="flex items-center gap-1">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    {t('unavailability.status')}
                  </div>
                </label>
                <select
                  value={filters.status}
                  onChange={(e) => setFilters({ ...filters, status: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                >
                  <option value="">{t('common.all_status')}</option>
                  <option value="active">{t('common.active')}</option>
                  <option value="cancelled">{t('stock.cancelled')}</option>
                </select>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Bulk Operations Panel */}
      {selectedIds.size > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6 flex items-center justify-between">
          <span className="text-sm font-medium text-blue-900">
            {selectedIds.size} period(s) selected
          </span>
          <div className="flex gap-2">
            <button
              onClick={handleBulkCancel}
              className="px-3 py-1 bg-yellow-600 text-white text-sm rounded hover:bg-yellow-700"
            >
              {t('unavailability.cancel_periods')}
            </button>
            <button
              onClick={handleBulkDelete}
              className="px-3 py-1 bg-red-600 text-white text-sm rounded hover:bg-red-700"
            >
              {t('unavailability.delete')}
            </button>
            <button
              onClick={() => setSelectedIds(new Set())}
              className="px-3 py-1 bg-gray-200 text-gray-700 text-sm rounded hover:bg-gray-300"
            >
              Clear Selection
            </button>
          </div>
        </div>
      )}

      {/* Table */}
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className="px-6 py-3 text-left">
                  <input
                    type="checkbox"
                    checked={selectedIds.size === filteredPeriods.length && filteredPeriods.length > 0}
                    onChange={handleSelectAll}
                    className="rounded"
                  />
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('stock.panelist')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Start Date</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">End Date</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('panelistunavailability.tsx.duration')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('panelistunavailability.tsx.reason')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('common.status')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('stock.notes')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('common.actions')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {filteredPeriods.length > 0 ? (
                filteredPeriods.map((period) => {
                  const isCurrent = isCurrentPeriod(period.start_date, period.end_date)
                  const duration = Math.ceil((new Date(period.end_date).getTime() - new Date(period.start_date).getTime()) / (1000 * 60 * 60 * 24)) + 1
                  
                  return (
                    <tr key={period.id} className={`hover:bg-gray-50 ${isCurrent ? 'bg-yellow-50' : ''}`}>
                      <td className="px-6 py-4">
                        <input
                          type="checkbox"
                          checked={selectedIds.has(period.id)}
                          onChange={() => handleSelectOne(period.id)}
                          className="rounded"
                        />
                      </td>
                      <td className="px-6 py-4 text-sm">
                        <div className="font-medium">{period.panelist?.name || '-'}</div>
                        <div className="text-gray-500 text-xs font-mono">{period.panelist?.panelist_code || '-'}</div>
                      </td>
                      <td className="px-6 py-4 text-sm">{period.start_date}</td>
                      <td className="px-6 py-4 text-sm">{period.end_date}</td>
                      <td className="px-6 py-4 text-sm">
                        {duration} day{duration !== 1 ? 's' : ''}
                        {isCurrent && <span className="ml-2 text-xs text-yellow-700 font-semibold">● ACTIVE NOW</span>}
                      </td>
                      <td className="px-6 py-4">
                        <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${getReasonBadgeClass(period.reason)}`}>
                          {period.reason}
                        </span>
                      </td>
                      <td className="px-6 py-4">
                        <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${getStatusBadgeClass(period.status)}`}>
                          {period.status}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-sm max-w-xs truncate">{period.notes || '-'}</td>
                      <td className="px-6 py-4 text-sm">
                        <div className="flex gap-2">
                          <button
                            onClick={() => handleOpenModal(period)}
                            className="text-blue-600 hover:text-blue-800"
                          >
                            {t('unavailability.edit')}
                          </button>
                          <button
                            onClick={() => handleToggleStatus(period)}
                            className="text-yellow-600 hover:text-yellow-800"
                          >
                            {period.status === 'active' ? t('unavailability.cancel') : t('unavailability.activate')}
                          </button>
                          <button
                            onClick={() => handleDelete(period.id)}
                            className="text-red-600 hover:text-red-800"
                          >
                            {t('unavailability.delete')}
                          </button>
                        </div>
                      </td>
                    </tr>
                  )
                })
              ) : (
                <tr>
                  <td colSpan={9} className="px-6 py-4 text-center text-gray-500">
                    No unavailability periods found. {filters.search || filters.panelist_id || filters.status || filters.reason || filters.date_range !== 'all' ? 'Try adjusting your filters.' : 'Click "Add Unavailability Period" to create one.'}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Modal */}
      {showModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg w-full max-w-md max-h-[90vh] flex flex-col">
            <div className="p-6 border-b">
              <h2 className="text-xl font-bold">
                {editingPeriod ? t('unavailability.edit_period') : t('unavailability.add_period_modal')}
              </h2>
            </div>
            <form onSubmit={handleSubmit} className="flex flex-col flex-1 min-h-0">
              <div className="flex-1 overflow-y-auto p-6 space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Panelist <span className="text-red-500">*</span>
                  </label>
                  <select
                    value={formData.panelist_id}
                    onChange={(e) => setFormData({ ...formData, panelist_id: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                    required
                  >
                    <option value="">Select a panelist</option>
                    {panelists.map((panelist: any) => (
                      <option key={panelist.id} value={panelist.id}>
                        {panelist.panelist_code} - {panelist.name}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-1">
                      Start Date <span className="text-red-500">*</span>
                    </label>
                    <input
                      type="date"
                      value={formData.start_date}
                      onChange={(e) => setFormData({ ...formData, start_date: e.target.value })}
                      className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                      required
                    />
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-1">
                      End Date <span className="text-red-500">*</span>
                    </label>
                    <input
                      type="date"
                      value={formData.end_date}
                      onChange={(e) => setFormData({ ...formData, end_date: e.target.value })}
                      className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                      required
                      min={formData.start_date}
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Reason <span className="text-red-500">*</span>
                  </label>
                  <select
                    value={formData.reason}
                    onChange={(e) => setFormData({ ...formData, reason: e.target.value as any })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                    required
                  >
                    <option value="vacation">{t('panelistunavailability.tsx.vacation')}</option>
                    <option value="sick">Sick Leave</option>
                    <option value="personal">{t('panelistunavailability.tsx.personal')}</option>
                    <option value="training">{t('panelistunavailability.tsx.training')}</option>
                    <option value="other">{t('panelistunavailability.tsx.other')}</option>
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Notes
                  </label>
                  <textarea
                    value={formData.notes}
                    onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                    rows={3}
                    placeholder="Additional information about this unavailability period..."
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Status
                  </label>
                  <select
                    value={formData.status}
                    onChange={(e) => setFormData({ ...formData, status: e.target.value as any })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  >
                    <option value="active">{t('common.active')}</option>
                    <option value="cancelled">{t('stock.cancelled')}</option>
                  </select>
                </div>
              </div>

              <div className="border-t p-6 flex gap-2">
                <button
                  type="submit"
                  className="flex-1 bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
                >
                  {editingPeriod ? 'Update' : 'Create'}
                </button>
                <button
                  type="button"
                  onClick={handleCloseModal}
                  className="flex-1 bg-gray-200 text-gray-700 px-4 py-2 rounded-lg hover:bg-gray-300"
                >
                  {t('unavailability.cancel')}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  )
}
