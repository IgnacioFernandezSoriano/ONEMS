import { useState, useEffect, useMemo } from 'react'
import { usePanelists } from '@/lib/hooks/usePanelists'
import { supabase } from '@/lib/supabase'
import type { Node, City, Panelist } from '@/lib/types'
import { PanelistUnavailabilityComponent } from '@/components/PanelistUnavailability'
import { SmartTooltip } from '@/components/common/SmartTooltip'

import { useTranslation } from '@/hooks/useTranslation';
export function Panelists() {
  const { t } = useTranslation();
  const { panelists, loading, error, createPanelist, updatePanelist, deletePanelist } = usePanelists()
  const [showModal, setShowModal] = useState(false)
  const [editingPanelist, setEditingPanelist] = useState<any>(null)
  const [nodes, setNodes] = useState<Node[]>([])
  const [cities, setCities] = useState<City[]>([])
  
  // Tab state
  const [activeTab, setActiveTab] = useState<'panelists' | 'unavailability'>('panelists')
  
  // Filters state
  const [showFilters, setShowFilters] = useState(true)
  const [filters, setFilters] = useState({
    city_id: '',
    node_id: '',
    status: '',
    search: '',
  })

  // Selection state
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  
  // Form state
  const [formData, setFormData] = useState({
    panelist_code: '',
    name: '',
    email: '',
    mobile: '',
    telegram_id: '',
    address_line1: '',
    address_line2: '',
    postal_code: '',
    address_city: '',
    address_country: '',
    node_id: '',
    status: 'active' as 'active' | 'inactive',
  })

  useEffect(() => {
    fetchNodes()
    fetchCities()
  }, [])

  const fetchNodes = async () => {
    const { data } = await supabase
      .from('nodes')
      .select('*, city:cities(*)')
      .eq('status', 'active')
      .order('auto_id')
    if (data) setNodes(data as any)
  }

  const fetchCities = async () => {
    const { data } = await supabase
      .from('cities')
      .select('*')
      .eq('status', 'active')
      .order('name')
    if (data) setCities(data)
  }

  // Filtered panelists
  const filteredPanelists = useMemo(() => {
    if (!panelists) return []
    
    return panelists.filter(panelist => {
      if (filters.city_id && panelist.node?.city_id !== filters.city_id) return false
      if (filters.node_id && panelist.node_id !== filters.node_id) return false
      if (filters.status && panelist.status !== filters.status) return false
      if (filters.search) {
        const search = filters.search.toLowerCase()
        const matchesCode = panelist.panelist_code?.toLowerCase().includes(search)
        const matchesName = panelist.name.toLowerCase().includes(search)
        const matchesEmail = panelist.email.toLowerCase().includes(search)
        if (!matchesCode && !matchesName && !matchesEmail) return false
      }
      return true
    })
  }, [panelists, filters])

  // Selection handlers
  const handleSelectAll = () => {
    if (selectedIds.size === filteredPanelists.length) {
      setSelectedIds(new Set())
    } else {
      setSelectedIds(new Set(filteredPanelists.map(p => p.id)))
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
  const handleBulkActivate = async () => {
    if (!confirm(`Activate ${selectedIds.size} panelists?`)) return
    
    for (const id of selectedIds) {
      await updatePanelist(id, { status: 'active' })
    }
    setSelectedIds(new Set())
  }

  const handleBulkDeactivate = async () => {
    if (!confirm(`Deactivate ${selectedIds.size} panelists?`)) return
    
    for (const id of selectedIds) {
      await updatePanelist(id, { status: 'inactive' })
    }
    setSelectedIds(new Set())
  }

  const handleBulkDelete = async () => {
    if (!confirm(`Delete ${selectedIds.size} panelists? This action cannot be undone.`)) return
    
    for (const id of selectedIds) {
      await deletePanelist(id)
    }
    setSelectedIds(new Set())
  }

  const handleOpenModal = (panelist?: any) => {
    if (panelist) {
      setEditingPanelist(panelist)
      setFormData({
        panelist_code: panelist.panelist_code || '',
        name: panelist.name,
        email: panelist.email,
        mobile: panelist.mobile,
        telegram_id: panelist.telegram_id || '',
        address_line1: panelist.address_line1 || '',
        address_line2: panelist.address_line2 || '',
        postal_code: panelist.postal_code || '',
        address_city: panelist.address_city || '',
        address_country: panelist.address_country || '',
        node_id: panelist.node_id,
        status: panelist.status,
      })
    } else {
      setEditingPanelist(null)
      setFormData({
        panelist_code: '',
        name: '',
        email: '',
        mobile: '',
        telegram_id: '',
        address_line1: '',
        address_line2: '',
        postal_code: '',
        address_city: '',
        address_country: '',
        node_id: '',
        status: 'active',
      })
    }
    setShowModal(true)
  }

  const handleCloseModal = () => {
    setShowModal(false)
    setEditingPanelist(null)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    try {
      if (editingPanelist) {
        await updatePanelist(editingPanelist.id, formData)
      } else {
        await createPanelist(formData)
      }
      handleCloseModal()
    } catch (err) {
      console.error('Error saving panelist:', err)
      alert('Error saving panelist')
    }
  }

  const handleToggleStatus = async (panelist: any) => {
    const newStatus = panelist.status === 'active' ? 'inactive' : 'active'
    await updatePanelist(panelist.id, { status: newStatus })
  }

  const handleDelete = async (id: string) => {
    if (!confirm('Are you sure you want to delete this panelist?')) return
    await deletePanelist(id)
  }

  const clearFilters = () => {
    setFilters({
      city_id: '',
      node_id: '',
      status: '',
      search: '',
    })
  }

  if (loading) return <div className="p-6">Loading...</div>
  if (error) return <div className="p-6 text-red-600">Error: {error}</div>

  // Calculate stats
  const stats = {
    total: panelists?.length || 0,
    active: panelists?.filter(p => p.status === 'active').length || 0,
    inactive: panelists?.filter(p => p.status === 'inactive').length || 0,
  }

  return (
    <div className="p-8">
      {/* Header with Tooltip and Create Button */}
      <div className="mb-6">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-bold text-gray-900">{t('panelists.management')}</h1>
            <SmartTooltip content="About Panelists Management - Purpose: Manage the network of panelists who send and receive shipments across your topology. Key Features: Register panelists with contact details, assign them to specific nodes, track availability periods, manage Telegram integration for notifications, and monitor panelist activity. Usage: Add panelists, assign to nodes, set unavailability periods, configure Telegram for automated notifications, and use in allocation planning.">
              <svg className="w-5 h-5 text-gray-400 hover:text-gray-600 cursor-help" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </SmartTooltip>
          </div>
        </div>
        <p className="text-gray-600">
          {t('panelists.manage_availability')}
        </p>
      </div>

      {/* Statistics Cards */}
      <div className="grid grid-cols-3 gap-6 mb-8">
        {/* Total Panelists */}
        <div className="bg-gradient-to-br from-blue-50 to-white border border-blue-100 rounded-xl p-6 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-blue-700">Total Panelists</span>
            <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
              </svg>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">{stats.total}</div>
          <div className="text-xs text-gray-500 mt-1">{t('panelists.all_in_system')}</div>
        </div>

        {/* Active Panelists */}
        <div className="bg-gradient-to-br from-green-50 to-white border border-green-100 rounded-xl p-6 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-green-700">{t('common.active')}</span>
            <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">{stats.active}</div>
          <div className="text-xs text-gray-500 mt-1">{t('panelists.available_for_deliveries')}</div>
        </div>

        {/* Inactive Panelists */}
        <div className="bg-gradient-to-br from-gray-50 to-white border border-gray-200 rounded-xl p-6 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-gray-700">{t('common.inactive')}</span>
            <div className="w-10 h-10 bg-gray-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
              </svg>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">{stats.inactive}</div>
          <div className="text-xs text-gray-500 mt-1">{t('panelists.not_available')}</div>
        </div>
      </div>

      {/* Tabs with Tooltips */}
      <div className="mb-6 border-b border-gray-200">
        <nav className="-mb-px flex space-x-8">
          <div className="flex items-center gap-2">
            <button
              onClick={() => setActiveTab('panelists')}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'panelists'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              Panelists
            </button>
            <SmartTooltip content="Panelists Tab - View and manage all panelists in your network. Filter by city, node, or status. Use bulk operations to activate, deactivate, or delete multiple panelists at once.">
              <svg className="w-4 h-4 text-gray-400 hover:text-gray-600 cursor-help" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </SmartTooltip>
          </div>
          
          <div className="flex items-center gap-2">
            <button
              onClick={() => setActiveTab('unavailability')}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === 'unavailability'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              {t('panelists.unavailability_periods')}
            </button>
            <SmartTooltip content="Unavailability Periods - Define time periods when panelists are not available for deliveries (vacations, sick leave, etc.). This ensures accurate allocation planning and prevents assignments to unavailable panelists.">
              <svg className="w-4 h-4 text-gray-400 hover:text-gray-600 cursor-help" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </SmartTooltip>
          </div>
        </nav>
      </div>

      {/* Panelists Tab Content */}
      {activeTab === 'panelists' && (
        <>
          {/* Filters Section */}
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
                {(filters.search || filters.city_id || filters.node_id || filters.status) && (
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
                <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
                  {/* Search Input */}
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
                      placeholder={t('panelists.search_placeholder')}
                      className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                    />
                  </div>

                  {/* City Select */}
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      <div className="flex items-center gap-1">
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
                        </svg>
                        City
                      </div>
                    </label>
                    <select
                      value={filters.city_id}
                      onChange={(e) => setFilters({ ...filters, city_id: e.target.value, node_id: '' })}
                      className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                    >
                      <option value="">{t('common.all_cities')}</option>
                      {cities.map(city => (
                        <option key={city.id} value={city.id}>{city.name}</option>
                      ))}
                    </select>
                  </div>

                  {/* Node Select */}
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      <div className="flex items-center gap-1">
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01" />
                        </svg>
                        Node
                        {filters.city_id && <span className="text-xs text-gray-500 font-normal">(filtered by city)</span>}
                      </div>
                    </label>
                    <select
                      value={filters.node_id}
                      onChange={(e) => setFilters({ ...filters, node_id: e.target.value })}
                      className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                    >
                      <option value="">{t('common.all_nodes')}</option>
                      {nodes
                        .filter((node: any) => !filters.city_id || node.city_id === filters.city_id)
                        .map((node: any) => (
                          <option key={node.id} value={node.id}>
                            {node.auto_id} {node.city?.name ? `- ${node.city.name}` : ''}
                          </option>
                        ))}
              </select>
            </div>

                  {/* Status Select */}
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      <div className="flex items-center gap-1">
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                        </svg>
                        Status
                      </div>
                    </label>
                    <select
                      value={filters.status}
                      onChange={(e) => setFilters({ ...filters, status: e.target.value })}
                      className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                    >
                      <option value="">{t('common.all_status')}</option>
                      <option value="active">{t('common.active')}</option>
                      <option value="inactive">{t('common.inactive')}</option>
                    </select>
                  </div>
                </div>
              </div>
            )}
          </div>

      {/* Bulk Operations Panel */}
      {selectedIds.size > 0 && (
        <div className="bg-gradient-to-r from-blue-50 to-blue-100 border border-blue-200 rounded-xl p-4 mb-6 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center">
                <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
                </svg>
              </div>
              <div>
                <div className="text-sm font-semibold text-blue-900">
                  {selectedIds.size} panelist{selectedIds.size > 1 ? 's' : ''} selected
                </div>
                <div className="text-xs text-blue-700">
                  Choose an action to apply to all selected items
                </div>
              </div>
            </div>
            <div className="flex gap-2">
              <button
                onClick={handleBulkActivate}
                className="flex items-center gap-1.5 px-3 py-2 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700 transition-colors shadow-sm"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                Activate
              </button>
              <button
                onClick={handleBulkDeactivate}
                className="flex items-center gap-1.5 px-3 py-2 bg-yellow-600 text-white text-sm font-medium rounded-lg hover:bg-yellow-700 transition-colors shadow-sm"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                Deactivate
              </button>
              <button
                onClick={handleBulkDelete}
                className="flex items-center gap-1.5 px-3 py-2 bg-red-600 text-white text-sm font-medium rounded-lg hover:bg-red-700 transition-colors shadow-sm"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
                Delete
              </button>
              <button
                onClick={() => setSelectedIds(new Set())}
                className="flex items-center gap-1.5 px-3 py-2 bg-white text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-50 transition-colors shadow-sm border border-gray-300"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
                Clear
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Table */}
      <div className="bg-white rounded-lg shadow overflow-hidden">
        {/* Table Header */}
        <div className="p-4 border-b flex justify-between items-center">
          <div>
            <h2 className="text-xl font-bold">{t('panelists.panelists')}</h2>
            <p className="text-sm text-gray-600 mt-1">
              Manage panelist profiles and assignments
            </p>
          </div>
          <button
            onClick={() => handleOpenModal()}
            className="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
          >
            {t('panelists.add_panelist')}
          </button>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className="px-6 py-3 text-left">
                  <input
                    type="checkbox"
                    checked={selectedIds.size === filteredPanelists.length && filteredPanelists.length > 0}
                    onChange={handleSelectAll}
                    className="rounded"
                  />
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('panelists.code')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('users.name')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('users.email')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('panelists.mobile')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('topology.node')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('topology.city')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('common.status')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('common.actions')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {filteredPanelists.length > 0 ? (
                filteredPanelists.map((panelist) => (
                  <tr key={panelist.id} className="hover:bg-gray-50">
                    <td className="px-6 py-4">
                      <input
                        type="checkbox"
                        checked={selectedIds.has(panelist.id)}
                        onChange={() => handleSelectOne(panelist.id)}
                        className="rounded"
                      />
                    </td>
                    <td className="px-6 py-4 text-sm font-mono">{panelist.panelist_code}</td>
                    <td className="px-6 py-4 text-sm">{panelist.name}</td>
                    <td className="px-6 py-4 text-sm">{panelist.email}</td>
                    <td className="px-6 py-4 text-sm">{panelist.mobile}</td>
                    <td className="px-6 py-4 text-sm font-mono">{panelist.node?.auto_id || '-'}</td>
                    <td className="px-6 py-4 text-sm">{panelist.city?.name || '-'}</td>
                    <td className="px-6 py-4">
                      <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                        panelist.status === 'active' 
                          ? 'bg-green-100 text-green-800' 
                          : 'bg-gray-100 text-gray-800'
                      }`}>
                        {panelist.status}
                      </span>
                    </td>
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => handleOpenModal(panelist)}
                          className="p-1.5 text-blue-600 hover:bg-blue-50 rounded-lg transition-colors"
                          title="Edit panelist"
                        >
                          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                          </svg>
                        </button>
                        <button
                          onClick={() => handleToggleStatus(panelist)}
                          className={`p-1.5 rounded-lg transition-colors ${
                            panelist.status === 'active'
                              ? 'text-yellow-600 hover:bg-yellow-50'
                              : 'text-green-600 hover:bg-green-50'
                          }`}
                          title={panelist.status === 'active' ? 'Deactivate panelist' : 'Activate panelist'}
                        >
                          {panelist.status === 'active' ? (
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
                            </svg>
                          ) : (
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                            </svg>
                          )}
                        </button>
                        <button
                          onClick={() => handleDelete(panelist.id)}
                          className="p-1.5 text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                          title="Delete panelist"
                        >
                          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                          </svg>
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={9} className="px-6 py-4 text-center text-gray-500">
                    No panelists found. {filters.search || filters.city_id || filters.node_id || filters.status ? 'Try adjusting your filters.' : 'Click "Add Panelist" to create one.'}
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
                {editingPanelist ? 'Edit Panelist' : 'Add Panelist'}
              </h2>
            </div>
            <form onSubmit={handleSubmit} className="flex flex-col flex-1 min-h-0">
              <div className="flex-1 overflow-y-auto p-6 space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Panelist Code <span className="text-gray-400 text-xs">(auto-generated if empty)</span>
                </label>
                <input
                  type="text"
                  value={formData.panelist_code}
                  onChange={(e) => setFormData({ ...formData, panelist_code: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  placeholder="Leave empty to auto-generate"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Name
                </label>
                <input
                  type="text"
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  required
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Email
                </label>
                <input
                  type="email"
                  value={formData.email}
                  onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  required
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Mobile
                </label>
                <input
                  type="tel"
                  value={formData.mobile}
                  onChange={(e) => setFormData({ ...formData, mobile: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  required
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Telegram ID
                </label>
                <input
                  type="text"
                  value={formData.telegram_id}
                  onChange={(e) => setFormData({ ...formData, telegram_id: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  placeholder="@username or numeric ID"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Address Line 1
                </label>
                <input
                  type="text"
                  value={formData.address_line1}
                  onChange={(e) => setFormData({ ...formData, address_line1: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  placeholder="Street address"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Address Line 2
                </label>
                <input
                  type="text"
                  value={formData.address_line2}
                  onChange={(e) => setFormData({ ...formData, address_line2: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  placeholder="Apartment, suite, etc. (optional)"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Postal Code
                  </label>
                  <input
                    type="text"
                    value={formData.postal_code}
                    onChange={(e) => setFormData({ ...formData, postal_code: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    City
                  </label>
                  <input
                    type="text"
                    value={formData.address_city}
                    onChange={(e) => setFormData({ ...formData, address_city: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Country
                </label>
                <input
                  type="text"
                  value={formData.address_country}
                  onChange={(e) => setFormData({ ...formData, address_country: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Node
                </label>
                <select
                  value={formData.node_id}
                  onChange={(e) => setFormData({ ...formData, node_id: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  required
                >
                  <option value="">Select a node</option>
                  {nodes.map((node: any) => (
                    <option key={node.id} value={node.id}>
                      {node.auto_id} - {node.city?.name || ''}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Status
                </label>
                <select
                  value={formData.status}
                  onChange={(e) => setFormData({ ...formData, status: e.target.value as 'active' | 'inactive' })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                >
                  <option value="active">{t('common.active')}</option>
                  <option value="inactive">{t('common.inactive')}</option>
                </select>
              </div>
              </div>

              <div className="border-t p-6 flex gap-2">
                <button
                  type="submit"
                  className="flex-1 bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
                >
                  {editingPanelist ? 'Update' : 'Create'}
                </button>
                <button
                  type="button"
                  onClick={handleCloseModal}
                  className="flex-1 bg-gray-200 text-gray-700 px-4 py-2 rounded-lg hover:bg-gray-300"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
        </>
      )}

      {/* Unavailability Tab Content */}
      {activeTab === 'unavailability' && (
        <PanelistUnavailabilityComponent />
      )}
    </div>
  )
}
