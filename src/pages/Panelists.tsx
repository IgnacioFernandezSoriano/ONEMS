import { useState, useEffect, useMemo } from 'react'
import { usePanelists } from '@/lib/hooks/usePanelists'
import { supabase } from '@/lib/supabase'
import type { Node, City, Panelist } from '@/lib/types'
import { PanelistUnavailabilityComponent } from '@/components/PanelistUnavailability'

export function Panelists() {
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

  return (
    <div className="p-6">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold">Panelists Management</h1>
        {activeTab === 'panelists' && (
          <button
            onClick={() => handleOpenModal()}
            className="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
          >
            + Add Panelist
          </button>
        )}
      </div>

      {/* Tabs */}
      <div className="mb-6 border-b border-gray-200">
        <nav className="-mb-px flex space-x-8">
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
          <button
            onClick={() => setActiveTab('unavailability')}
            className={`py-4 px-1 border-b-2 font-medium text-sm ${
              activeTab === 'unavailability'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            Unavailability Periods
          </button>
        </nav>
      </div>

      {/* Panelists Tab Content */}
      {activeTab === 'panelists' && (
        <>
          {/* Filters */}
          <div className="bg-white rounded-lg shadow mb-6">
        <div 
          className="p-4 flex justify-between items-center cursor-pointer border-b"
          onClick={() => setShowFilters(!showFilters)}
        >
          <h2 className="font-semibold">Filters</h2>
          <span className="text-gray-500">{showFilters ? '▼' : '▶'}</span>
        </div>
        
        {showFilters && (
          <div className="p-4 grid grid-cols-1 md:grid-cols-4 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Search
              </label>
              <input
                type="text"
                value={filters.search}
                onChange={(e) => setFilters({ ...filters, search: e.target.value })}
                placeholder="Code, name, email..."
                className="w-full px-3 py-2 border border-gray-300 rounded-lg"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                City
              </label>
              <select
                value={filters.city_id}
                onChange={(e) => setFilters({ ...filters, city_id: e.target.value, node_id: '' })}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg"
              >
                <option value="">All Cities</option>
                {cities.map(city => (
                  <option key={city.id} value={city.id}>{city.name}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Node {filters.city_id && <span className="text-xs text-gray-500">(filtered by city)</span>}
              </label>
              <select
                value={filters.node_id}
                onChange={(e) => setFilters({ ...filters, node_id: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg"
              >
                <option value="">All Nodes</option>
                {nodes
                  .filter((node: any) => !filters.city_id || node.city_id === filters.city_id)
                  .map((node: any) => (
                    <option key={node.id} value={node.id}>
                      {node.auto_id} {node.city?.name ? `- ${node.city.name}` : ''}
                    </option>
                  ))}
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Status
              </label>
              <select
                value={filters.status}
                onChange={(e) => setFilters({ ...filters, status: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg"
              >
                <option value="">All Status</option>
                <option value="active">Active</option>
                <option value="inactive">Inactive</option>
              </select>
            </div>

            <div className="md:col-span-4 flex justify-end">
              <button
                onClick={clearFilters}
                className="text-sm text-gray-600 hover:text-gray-800"
              >
                Clear Filters
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Bulk Operations Panel */}
      {selectedIds.size > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6 flex items-center justify-between">
          <span className="text-sm font-medium text-blue-900">
            {selectedIds.size} panelist(s) selected
          </span>
          <div className="flex gap-2">
            <button
              onClick={handleBulkActivate}
              className="px-3 py-1 bg-green-600 text-white text-sm rounded hover:bg-green-700"
            >
              Activate
            </button>
            <button
              onClick={handleBulkDeactivate}
              className="px-3 py-1 bg-yellow-600 text-white text-sm rounded hover:bg-yellow-700"
            >
              Deactivate
            </button>
            <button
              onClick={handleBulkDelete}
              className="px-3 py-1 bg-red-600 text-white text-sm rounded hover:bg-red-700"
            >
              Delete
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
                    checked={selectedIds.size === filteredPanelists.length && filteredPanelists.length > 0}
                    onChange={handleSelectAll}
                    className="rounded"
                  />
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Code</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Email</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Mobile</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Node</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">City</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actions</th>
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
                    <td className="px-6 py-4 text-sm">
                      <div className="flex gap-2">
                        <button
                          onClick={() => handleOpenModal(panelist)}
                          className="text-blue-600 hover:text-blue-800"
                        >
                          Edit
                        </button>
                        <button
                          onClick={() => handleToggleStatus(panelist)}
                          className="text-yellow-600 hover:text-yellow-800"
                        >
                          {panelist.status === 'active' ? 'Deactivate' : 'Activate'}
                        </button>
                        <button
                          onClick={() => handleDelete(panelist.id)}
                          className="text-red-600 hover:text-red-800"
                        >
                          Delete
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
                  <option value="active">Active</option>
                  <option value="inactive">Inactive</option>
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
