import { useTopology } from '@/hooks/useTopology'
import { TopologyTree } from '@/components/topology/TopologyTree'
import { PageHeader } from '@/components/common/PageHeader'
import { SmartTooltip } from '@/components/common/SmartTooltip'

export function CountryTopology() {
  const {
    regions,
    cities,
    nodes,
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
  }

  return (
    <div className="p-8">
      {/* Header with Tooltip and Create Button */}
      <div className="mb-6">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-bold text-gray-900">Country Topology</h1>
            <SmartTooltip content="About Country Topology - Purpose: Define and manage your country's network infrastructure hierarchy in a three-level structure. Structure: Regions (top-level geographic divisions like Norte, Sur, Centro), Cities (urban centers within each region like Madrid, Barcelona), and Nodes (specific delivery points or addresses within cities). Usage: This topology is used throughout the system for allocation planning, reporting, and territory equity analysis.">
              <svg className="w-5 h-5 text-gray-400 hover:text-gray-600 cursor-help" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </SmartTooltip>
          </div>
          
          {/* Create Region Button */}
          <button
            onClick={() => createRegion({ name: '', code: '' })}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors shadow-sm"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
            </svg>
            Create Region
          </button>
        </div>
        <p className="text-gray-600">
          Define and manage your country network infrastructure hierarchy
        </p>
      </div>

      {/* Statistics Cards */}
      <div className="grid grid-cols-3 gap-6 mb-8">
        {/* Regions */}
        <div className="bg-gradient-to-br from-blue-50 to-white border border-blue-100 rounded-xl p-6 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-blue-700">Regions</span>
            <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
              </svg>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">{stats.regions}</div>
          <div className="text-xs text-gray-500 mt-1">Geographic divisions</div>
        </div>

        {/* Cities */}
        <div className="bg-gradient-to-br from-green-50 to-white border border-green-100 rounded-xl p-6 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-green-700">Cities</span>
            <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
              </svg>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">{stats.cities}</div>
          <div className="text-xs text-gray-500 mt-1">Urban centers</div>
        </div>

        {/* Nodes */}
        <div className="bg-gradient-to-br from-purple-50 to-white border border-purple-100 rounded-xl p-6 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-purple-700">Nodes</span>
            <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">{stats.nodes}</div>
          <div className="text-xs text-gray-500 mt-1">Delivery points</div>
        </div>
      </div>

      <div className="bg-gray-50 p-6 rounded-lg">
        {regions.length === 0 && (
          <div className="text-center py-8 mb-6">
            <div className="text-4xl mb-4">🗺️</div>
            <h3 className="text-lg font-semibold mb-2">No topology defined yet</h3>
            <p className="text-gray-600 mb-4">
              Start by creating your first region to build your country topology
            </p>
          </div>
        )}
        
        <TopologyTree
          regions={regions}
          cities={cities}
          nodes={nodes}
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
      </div>
    </div>
  )
}
