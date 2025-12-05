import { useTopology } from '@/hooks/useTopology'
import { TopologyTree } from '@/components/topology/TopologyTree'
import { PageHeader } from '@/components/common/PageHeader'

export function NetworkTopology() {
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
      <PageHeader title="Network Topology" />
      <p className="text-gray-600 mb-6">
        Define and manage your network infrastructure hierarchy
      </p>

      <div className="grid grid-cols-3 gap-4 mb-6">
        <div className="bg-white p-4 rounded-lg border">
          <div className="text-2xl font-bold text-blue-600">{stats.regions}</div>
          <div className="text-sm text-gray-600">Regions</div>
        </div>
        <div className="bg-white p-4 rounded-lg border">
          <div className="text-2xl font-bold text-green-600">{stats.cities}</div>
          <div className="text-sm text-gray-600">Cities</div>
        </div>
        <div className="bg-white p-4 rounded-lg border">
          <div className="text-2xl font-bold text-purple-600">{stats.nodes}</div>
          <div className="text-sm text-gray-600">Nodes</div>
        </div>
      </div>

      <div className="bg-gray-50 p-6 rounded-lg">
        {regions.length === 0 ? (
          <div className="text-center py-12">
            <div className="text-4xl mb-4">🗺️</div>
            <h3 className="text-lg font-semibold mb-2">No topology defined yet</h3>
            <p className="text-gray-600 mb-4">
              Start by creating your first region to build your network topology
            </p>
          </div>
        ) : (
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
        )}
      </div>
    </div>
  )
}
