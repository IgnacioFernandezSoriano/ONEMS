import { useState } from 'react'
import { Modal } from '@/components/common/Modal'
import { RegionForm } from './RegionForm'
import { CityForm } from './CityForm'

import type { Region, City, Node } from '@/lib/types'

interface TopologyTreeProps {
  regions: Region[]
  cities: City[]
  nodes: Node[]
  onCreateRegion: (data: any) => Promise<void>
  onCreateCity: (data: any) => Promise<void>
  onCreateNode: (data: any) => Promise<void>
  onUpdateRegion: (id: string, data: any) => Promise<void>
  onUpdateCity: (id: string, data: any) => Promise<void>
  onUpdateNode: (id: string, data: any) => Promise<void>
  onDeleteRegion: (id: string) => Promise<void>
  onDeleteCity: (id: string) => Promise<void>
  onDeleteNode: (id: string) => Promise<void>
}

export function TopologyTree({
  regions,
  cities,
  nodes,
  onCreateRegion,
  onCreateCity,
  onCreateNode,
  onUpdateRegion,
  onUpdateCity,
  onUpdateNode,
  onDeleteRegion,
  onDeleteCity,
  onDeleteNode,
}: TopologyTreeProps) {
  const [expandedRegions, setExpandedRegions] = useState<Set<string>>(new Set())
  const [expandedCities, setExpandedCities] = useState<Set<string>>(new Set())
  const [modal, setModal] = useState<any>(null)

  const toggleRegion = (id: string) => {
    const newExpanded = new Set(expandedRegions)
    if (newExpanded.has(id)) {
      newExpanded.delete(id)
    } else {
      newExpanded.add(id)
    }
    setExpandedRegions(newExpanded)
  }

  const toggleCity = (id: string) => {
    const newExpanded = new Set(expandedCities)
    if (newExpanded.has(id)) {
      newExpanded.delete(id)
    } else {
      newExpanded.add(id)
    }
    setExpandedCities(newExpanded)
  }

  const getCitiesForRegion = (regionId: string) => {
    return cities.filter((c) => c.region_id === regionId)
  }

  const getNodesForCity = (cityId: string) => {
    return nodes.filter((n) => n.city_id === cityId)
  }

  const handleSubmit = async (data: any) => {
    await modal.onSubmit(data)
    setModal(null)
  }

  return (
    <>
      <div className="space-y-2">
        {regions.map((region) => {
          const regionCities = getCitiesForRegion(region.id)
          const isExpanded = expandedRegions.has(region.id)

          return (
            <div key={region.id} className="border rounded-lg bg-white">
              <div className="flex items-center gap-2 p-3 hover:bg-gray-50">
                <button
                  onClick={() => toggleRegion(region.id)}
                  className="text-gray-500 hover:text-gray-700"
                >
                  {isExpanded ? '▼' : '▶'}
                </button>
                <span className="text-xl">📍</span>
                <span className="font-medium flex-1">
                  {region.name} ({region.code})
                </span>
                <span
                  className={`text-xs px-2 py-1 rounded ${
                    region.status === 'active'
                      ? 'bg-green-100 text-green-700'
                      : 'bg-gray-100 text-gray-700'
                  }`}
                >
                  {region.status}
                </span>
                <button
                  onClick={() =>
                    setModal({
                      type: 'region',
                      region: region,
                      onSubmit: (data: any) => onUpdateRegion(region.id, data),
                    })
                  }
                  className="px-3 py-1 text-sm text-blue-600 hover:bg-blue-50 rounded"
                >
                  Edit
                </button>
                <button
                  onClick={() =>
                    setModal({
                      type: 'city',
                      regionId: region.id,
                      onSubmit: onCreateCity,
                    })
                  }
                  className="px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"
                >
                  + City
                </button>
                <button
                  onClick={() => {
                    if (confirm('Delete this region and all its cities/nodes?')) {
                      onDeleteRegion(region.id)
                    }
                  }}
                  className="px-3 py-1 text-sm text-red-600 hover:bg-red-50 rounded"
                >
                  Delete
                </button>
              </div>

              {isExpanded && (
                <div className="pl-8 pb-2 space-y-1">
                  {regionCities.map((city) => {
                    const cityNodes = getNodesForCity(city.id)
                    const isCityExpanded = expandedCities.has(city.id)

                    return (
                      <div key={city.id} className="border-l-2 border-gray-200">
                        <div className="flex items-center gap-2 p-2 hover:bg-gray-50">
                          <button
                            onClick={() => toggleCity(city.id)}
                            className="text-gray-500 hover:text-gray-700 ml-2"
                          >
                            {isCityExpanded ? '▼' : '▶'}
                          </button>
                          <span className="text-lg">🏙️</span>
                          <span className="flex-1">
                            {city.name} ({city.code})
                            {city.classification && (
                              <span className="ml-2 text-xs bg-purple-100 text-purple-700 px-2 py-0.5 rounded">
                                Class {city.classification}
                              </span>
                            )}
                          </span>
                          <span
                            className={`text-xs px-2 py-1 rounded ${
                              city.status === 'active'
                                ? 'bg-green-100 text-green-700'
                                : 'bg-gray-100 text-gray-700'
                            }`}
                          >
                            {city.status}
                          </span>
                          <button
                            onClick={() =>
                              setModal({
                                type: 'city',
                                regionId: city.region_id,
                                city: city,
                                onSubmit: (data: any) => onUpdateCity(city.id, data),
                              })
                            }
                            className="px-2 py-1 text-xs text-blue-600 hover:bg-blue-50 rounded"
                          >
                            Edit
                          </button>
                          <button
                            onClick={() => onCreateNode({ city_id: city.id })}
                            className="px-2 py-1 text-xs bg-green-600 text-white rounded hover:bg-green-700"
                          >
                            + Node
                          </button>
                          <button
                            onClick={() => {
                              if (confirm('Delete this city and all its nodes?')) {
                                onDeleteCity(city.id)
                              }
                            }}
                            className="px-2 py-1 text-xs text-red-600 hover:bg-red-50 rounded"
                          >
                            Delete
                          </button>
                        </div>

                        {isCityExpanded && (
                          <div className="pl-8 space-y-1">
                            {cityNodes.map((node) => (
                              <div
                                key={node.id}
                                className="flex items-center gap-2 p-2 hover:bg-gray-50 text-sm"
                              >
                                <span className="text-base">🔷</span>
                                <span className="font-mono text-blue-600 flex-1">{node.auto_id}</span>
                                <span
                                  className={`text-xs px-2 py-1 rounded ${
                                    node.status === 'active'
                                      ? 'bg-green-100 text-green-700'
                                      : 'bg-gray-100 text-gray-700'
                                  }`}
                                >
                                  {node.status}
                                </span>
                                <button
                                  onClick={() => {
                                    if (confirm('Delete this node?')) {
                                      onDeleteNode(node.id)
                                    }
                                  }}
                                  className="px-2 py-1 text-xs text-red-600 hover:bg-red-50 rounded"
                                >
                                  Delete
                                </button>
                              </div>
                            ))}
                          </div>
                        )}
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          )
        })}

        <button
          onClick={() => setModal({ type: 'region', onSubmit: onCreateRegion })}
          className="w-full p-4 border-2 border-dashed border-gray-300 rounded-lg hover:border-blue-500 hover:bg-blue-50 text-gray-600 hover:text-blue-600 font-medium"
        >
          + Add Region
        </button>
      </div>

      {modal && (
        <Modal
          isOpen={true}
          onClose={() => setModal(null)}
          title={
            modal.type === 'region'
              ? modal.region
                ? 'Edit Region'
                : 'Create Region'
              : modal.city
              ? 'Edit City'
              : 'Create City'
          }
        >
          {modal.type === 'region' && (
            <RegionForm
              region={modal.region}
              onSubmit={handleSubmit}
              onCancel={() => setModal(null)}
            />
          )}
          {modal.type === 'city' && (
            <CityForm
              city={modal.city}
              regionId={modal.regionId}
              onSubmit={handleSubmit}
              onCancel={() => setModal(null)}
            />
          )}

        </Modal>
      )}
    </>
  )
}
