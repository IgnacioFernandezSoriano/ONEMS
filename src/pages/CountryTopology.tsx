import { useState, useMemo } from 'react'
import { useTopology } from '@/hooks/useTopology'
import { TopologyTree } from '@/components/topology/TopologyTree'
import { SmartTooltip } from '@/components/common/SmartTooltip'
import { Modal } from '@/components/common/Modal'
import { RegionForm } from '@/components/topology/RegionForm'

import { useTranslation } from '@/hooks/useTranslation';
export function CountryTopology() {
  const { t } = useTranslation();
  const {
    regions,
    cities,
    nodes,
    panelists,
    loading,
    error,
    createRegion,
    updateRegion,
    deleteRegion,
    createCity,
    updateCity,
    deleteCity,
    createNode,
    updateNode,
    deleteNode,
  } = useTopology()

  // State for filters and UI
  const [activeTab, setActiveTab] = useState<'topology' | 'without-panelists'>('topology')
  const [searchTerm, setSearchTerm] = useState('')
  const [filterRegion, setFilterRegion] = useState<string>('all')
  const [filterCity, setFilterCity] = useState<string>('all')
  const [filterPanelistStatus, setFilterPanelistStatus] = useState<string>('all')
  const [expandAll, setExpandAll] = useState(false)
  const [showRegionModal, setShowRegionModal] = useState(false)

  // Calculate nodes with/without panelists
  const nodesWithPanelists = useMemo(() => {
    const panelistNodeIds = new Set(panelists.map(p => p.node_id))
    return nodes.map(node => ({
      ...node,
      hasPanelist: panelistNodeIds.has(node.id),
      panelist: panelists.find(p => p.node_id === node.id)
    }))
  }, [nodes, panelists])

  const nodesWithoutPanelists = useMemo(() => {
    return nodesWithPanelists.filter(n => !n.hasPanelist)
  }, [nodesWithPanelists])

  // Filtered data
  const filteredData = useMemo(() => {
    let filteredRegions = regions
    let filteredCities = cities
    let filteredNodes = nodesWithPanelists

    // Search filter
    if (searchTerm) {
      const term = searchTerm.toLowerCase()
      const matchingRegions = regions.filter(r => 
        r.name.toLowerCase().includes(term) || 
        r.code?.toLowerCase().includes(term)
      )
      const matchingCities = cities.filter(c => 
        c.name.toLowerCase().includes(term) || 
        c.code?.toLowerCase().includes(term)
      )
      const matchingNodes = filteredNodes.filter(n => 
        n.auto_id?.toLowerCase().includes(term)
      )

      const matchingRegionIds = new Set([
        ...matchingRegions.map(r => r.id),
        ...matchingCities.map(c => c.region_id),
        ...matchingNodes.map(n => {
          const city = cities.find(c => c.id === n.city_id)
          return city?.region_id
        }).filter(Boolean)
      ])

      const matchingCityIds = new Set([
        ...matchingCities.map(c => c.id),
        ...matchingNodes.map(n => n.city_id)
      ])

      filteredRegions = regions.filter(r => matchingRegionIds.has(r.id))
      filteredCities = cities.filter(c => matchingCityIds.has(c.id))
      filteredNodes = filteredNodes.filter(n => {
        const city = cities.find(c => c.id === n.city_id)
        return matchingCityIds.has(n.city_id) || matchingRegionIds.has(city?.region_id)
      })
    }

    // Region filter
    if (filterRegion !== 'all') {
      filteredRegions = filteredRegions.filter(r => r.id === filterRegion)
      filteredCities = filteredCities.filter(c => c.region_id === filterRegion)
      filteredNodes = filteredNodes.filter(n => {
        const city = cities.find(c => c.id === n.city_id)
        return city?.region_id === filterRegion
      })
    }

    // City filter
    if (filterCity !== 'all') {
      filteredCities = filteredCities.filter(c => c.id === filterCity)
      filteredNodes = filteredNodes.filter(n => n.city_id === filterCity)
    }

    // Panelist status filter
    if (filterPanelistStatus === 'with') {
      filteredNodes = filteredNodes.filter(n => n.hasPanelist)
    } else if (filterPanelistStatus === 'without') {
      filteredNodes = filteredNodes.filter(n => !n.hasPanelist)
    }

    return {
      regions: filteredRegions,
      cities: filteredCities,
      nodes: filteredNodes
    }
  }, [regions, cities, nodesWithPanelists, searchTerm, filterRegion, filterCity, filterPanelistStatus])

  // Export CSV for nodes without panelists
  const exportNodesWithoutPanelistsCSV = () => {
    const csvData = nodesWithoutPanelists.map(node => {
      const city = cities.find(c => c.id === node.city_id)
      const region = regions.find(r => r.id === city?.region_id)
      return {
        'Node ID': node.auto_id || '',
        'City': city?.name || '',
        'Region': region?.name || '',
        'Status': node.status || 'active'
      }
    })

    const headers = Object.keys(csvData[0] || {})
    const csvContent = [
      headers.join(','),
      ...csvData.map(row => headers.map(h => `"${row[h as keyof typeof row]}"`).join(','))
    ].join('\\n')

    const blob = new Blob([csvContent], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = `nodes-without-panelists-${new Date().toISOString().split('T')[0]}.csv`
    link.click()
    URL.revokeObjectURL(url)
  }

  if (loading) {
    return (
      <div className="p-8">
        <div className="text-center text-gray-600">Loading topology...</div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="p-8">
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
          Error: {error}
        </div>
      </div>
    )
  }

  const stats = {
    regions: regions.length,
    cities: cities.length,
    nodes: nodes.length,
    nodesWithPanelists: nodesWithPanelists.filter(n => n.hasPanelist).length,
    nodesWithoutPanelists: nodesWithoutPanelists.length,
  }

  return (
    <div className="p-8">
      {/* Header with Tooltip and Create Button */}
      <div className="mb-6">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-bold text-gray-900">{t('topology.title')}</h1>
            <SmartTooltip content="About Country Topology - Purpose: Define and manage your country's network infrastructure hierarchy in a three-level structure. Structure: Regions (top-level geographic divisions like Norte, Sur, Centro), Cities (urban centers within each region like Madrid, Barcelona), and Nodes (specific delivery points or addresses within cities). Usage: This topology is used throughout the system for allocation planning, reporting, and territory equity analysis.">
              <svg className="w-5 h-5 text-gray-400 hover:text-gray-600 cursor-help" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </SmartTooltip>
          </div>
          
          {/* Create Region Button */}
          <button
            onClick={() => setShowRegionModal(true)}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors shadow-sm"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
            </svg>
            {t('topology.create_region')}
          </button>
        </div>
        <p className="text-gray-600">
          {t('topology.description')}
        </p>
      </div>

      {/* Statistics Cards */}
      <div className="grid grid-cols-5 gap-4 mb-6">
        {/* Regions */}
        <div className="bg-gradient-to-br from-blue-50 to-white border border-blue-100 rounded-xl p-4 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-blue-700">{t('countrytopology.regions')}</span>
            <div className="w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
              </svg>
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900">{stats.regions}</div>
        </div>

        {/* Cities */}
        <div className="bg-gradient-to-br from-green-50 to-white border border-green-100 rounded-xl p-4 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-green-700">{t('reporting.cities')}</span>
            <div className="w-8 h-8 bg-green-100 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
              </svg>
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900">{stats.cities}</div>
        </div>

        {/* Total Nodes */}
        <div className="bg-gradient-to-br from-purple-50 to-white border border-purple-100 rounded-xl p-4 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-purple-700">{t('topology.total_nodes')}</span>
            <div className="w-8 h-8 bg-purple-100 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900">{stats.nodes}</div>
        </div>

        {/* Nodes with Panelists */}
        <div className="bg-gradient-to-br from-emerald-50 to-white border border-emerald-100 rounded-xl p-4 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-emerald-700">{t('topology.with_panelists')}</span>
            <div className="w-8 h-8 bg-emerald-100 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900">{stats.nodesWithPanelists}</div>
        </div>

        {/* Nodes without Panelists */}
        <div className="bg-gradient-to-br from-amber-50 to-white border border-amber-100 rounded-xl p-4 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-amber-700">{t('topology.without_panelists')}</span>
            <div className="w-8 h-8 bg-amber-100 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900">{stats.nodesWithoutPanelists}</div>
        </div>
      </div>

      {/* Tabs */}
      <div className="mb-6">
        <div className="border-b border-gray-200">
          <nav className="-mb-px flex space-x-8">
            <button
              onClick={() => setActiveTab('topology')}
              className={`py-4 px-1 border-b-2 font-medium text-sm transition-colors ${
                activeTab === 'topology'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              {t('topology.topology_tree')}
            </button>
            <button
              onClick={() => setActiveTab('without-panelists')}
              className={`py-4 px-1 border-b-2 font-medium text-sm transition-colors flex items-center gap-2 ${
                activeTab === 'without-panelists'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              {t('topology.nodes_without_panelists')}
              {stats.nodesWithoutPanelists > 0 && (
                <span className="bg-amber-100 text-amber-800 text-xs font-semibold px-2 py-0.5 rounded-full">
                  {stats.nodesWithoutPanelists}
                </span>
              )}
            </button>
          </nav>
        </div>
      </div>

      {/* Filters */}
      {activeTab === 'topology' && (
        <div className="bg-white border border-gray-200 rounded-lg p-4 mb-6">
          <div className="flex items-center gap-4 flex-wrap">
            {/* Search */}
            <div className="flex-1 min-w-[200px]">
              <div className="relative">
                <input
                  type="text"
                  placeholder={t('topology.search_placeholder')}
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
                <svg className="absolute left-3 top-2.5 w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                </svg>
              </div>
            </div>

            {/* Region Filter */}
            <div className="min-w-[180px]">
              <select
                value={filterRegion}
                onChange={(e) => {
                  setFilterRegion(e.target.value)
                  setFilterCity('all')
                }}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="all">{t('topology.all_regions')}</option>
                {regions.map(region => (
                  <option key={region.id} value={region.id}>{region.name}</option>
                ))}
              </select>
            </div>

            {/* City Filter */}
            <div className="min-w-[180px]">
              <select
                value={filterCity}
                onChange={(e) => setFilterCity(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                disabled={filterRegion !== 'all'}
              >
                <option value="all">{t('topology.all_cities')}</option>
                {(filterRegion === 'all' ? cities : cities.filter(c => c.region_id === filterRegion)).map(city => (
                  <option key={city.id} value={city.id}>{city.name}</option>
                ))}
              </select>
            </div>

            {/* Panelist Status Filter */}
            <div className="min-w-[180px]">
              <select
                value={filterPanelistStatus}
                onChange={(e) => setFilterPanelistStatus(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="all">{t('topology.all_nodes')}</option>
                <option value="with">With Panelist</option>
                <option value="without">Without Panelist</option>
              </select>
            </div>

            {/* Expand/Collapse All Button */}
            <button
              onClick={() => setExpandAll(!expandAll)}
              className="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors flex items-center gap-2"
            >
              {expandAll ? (
                <>
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 12H4" />
                  </svg>
                  Collapse All
                </>
              ) : (
                <>
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                  </svg>
                  {t('topology.expand_all')}
                </>
              )}
            </button>

            {/* Clear Filters */}
            {(searchTerm || filterRegion !== 'all' || filterCity !== 'all' || filterPanelistStatus !== 'all') && (
              <button
                onClick={() => {
                  setSearchTerm('')
                  setFilterRegion('all')
                  setFilterCity('all')
                  setFilterPanelistStatus('all')
                }}
                className="px-4 py-2 text-gray-600 hover:text-gray-800 transition-colors"
              >
                Clear Filters
              </button>
            )}
          </div>
        </div>
      )}

      {/* Content */}
      {activeTab === 'topology' ? (
        <div className="bg-gray-50 p-6 rounded-lg">
          {filteredData.regions.length === 0 && !searchTerm && (
            <div className="text-center py-8 mb-6">
              <div className="text-4xl mb-4">🗺️</div>
              <h3 className="text-lg font-semibold mb-2">No topology defined yet</h3>
              <p className="text-gray-600 mb-4">
                Start by creating your first region to build your country topology
              </p>
            </div>
          )}
          
          {filteredData.regions.length === 0 && searchTerm && (
            <div className="text-center py-8">
              <div className="text-4xl mb-4">🔍</div>
              <h3 className="text-lg font-semibold mb-2">No results found</h3>
              <p className="text-gray-600">
                Try adjusting your search or filters
              </p>
            </div>
          )}
          
          {filteredData.regions.length > 0 && (
            <TopologyTree
              regions={filteredData.regions}
              cities={filteredData.cities}
              nodes={filteredData.nodes}
              panelists={panelists}
              expandAll={expandAll}
              onCreateRegion={createRegion}
              onCreateCity={createCity}
              onCreateNode={createNode}
              onUpdateRegion={updateRegion}
              onUpdateCity={updateCity}
              onUpdateNode={updateNode}
              onDeleteRegion={deleteRegion}
              onDeleteCity={deleteCity}
              onDeleteNode={deleteNode}
            />
          )}
        </div>
      ) : (
        <div className="bg-white border border-gray-200 rounded-lg p-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h3 className="text-lg font-semibold text-gray-900">Nodes without Panelists</h3>
              <p className="text-sm text-gray-600 mt-1">
                These nodes need panelist assignment to be operational
              </p>
            </div>
            <button
              onClick={exportNodesWithoutPanelistsCSV}
              disabled={nodesWithoutPanelists.length === 0}
              className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors shadow-sm disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
              Download CSV
            </button>
          </div>

          {nodesWithoutPanelists.length === 0 ? (
            <div className="text-center py-12">
              <div className="text-4xl mb-4">✅</div>
              <h3 className="text-lg font-semibold mb-2 text-gray-900">All nodes have panelists!</h3>
              <p className="text-gray-600">
                Every node in your topology has a panelist assigned
              </p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-gray-200">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Node ID
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      City
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Region
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Status
                    </th>
                  </tr>
                </thead>
                <tbody className="bg-white divide-y divide-gray-200">
                  {nodesWithoutPanelists.map(node => {
                    const city = cities.find(c => c.id === node.city_id)
                    const region = regions.find(r => r.id === city?.region_id)
                    return (
                      <tr key={node.id} className="hover:bg-gray-50">
                        <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                          {node.auto_id}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                          {city?.name || '-'}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                          {region?.name || '-'}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <span className="px-2 py-1 text-xs font-medium rounded-full bg-amber-100 text-amber-800">
                            Pending Panelist
                          </span>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* Create Region Modal */}
      {showRegionModal && (
        <Modal
          isOpen={showRegionModal}
          title={t('topology.create_region')}
          onClose={() => setShowRegionModal(false)}
        >
          <RegionForm
            onSubmit={async (data) => {
              await createRegion(data)
              setShowRegionModal(false)
            }}
            onCancel={() => setShowRegionModal(false)}
          />
        </Modal>
      )}
    </div>
  )
}
