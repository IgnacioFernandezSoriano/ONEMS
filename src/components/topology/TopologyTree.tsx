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
    try {
      await modal.onSubmit(data)
      setModal(null)
      // Estado de expansión se mantiene automáticamente
    } catch (error) {
      console.error('Error submitting:', error)
      throw error
    }
  }

  return (
    <>
      <div className="space-y-2">
        {regions.map((region) => {
          const regionCities = getCitiesForRegion(region.id)
          const isExpanded = expandedRegions.has(region.id)

          return (
            <div key={region.id} className="border rounded-lg bg-white">
              <div className="flex items-center gap-3 p-4 hover:bg-gray-50 transition-colors">
                {/* Expand/Collapse Button */}
                <button
                  onClick={() => toggleRegion(region.id)}
                  className="text-gray-400 hover:text-gray-600 transition-colors"
                >
                  <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                    {isExpanded ? (
                      <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
                    ) : (
                      <path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clipRule="evenodd" />
                    )}
                  </svg>
                </button>

                {/* Region Icon */}
                <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                  <svg className="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
                  </svg>
                </div>

                {/* Region Name + Status */}
                <div className="flex-1 flex items-center gap-3">
                  <span className="font-semibold text-gray-900">
                    {region.name}
                  </span>
                  <span className="text-sm text-gray-500">({region.code})</span>
                  <span
                    className={`text-xs font-medium px-2.5 py-0.5 rounded-full ${
                      region.status === 'active'
                        ? 'bg-green-100 text-green-700'
                        : 'bg-gray-100 text-gray-600'
                    }`}
                  >
                    {region.status === 'active' ? 'Active' : 'Inactive'}
                  </span>
                </div>

                {/* Action Buttons (Right Side) */}
                <div className="flex items-center gap-2">
                  <button
                    onClick={() =>
                      setModal({
                        type: 'city',
                        regionId: region.id,
                        onSubmit: onCreateCity,
                      })
                    }
                    className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                    </svg>
                    City
                  </button>
                  <button
                    onClick={() =>
                      setModal({
                        type: 'region',
                        region: region,
                        onSubmit: (data: any) => onUpdateRegion(region.id, data),
                      })
                    }
                    className="p-1.5 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
                    title="Edit region"
                  >
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                    </svg>
                  </button>
                  <button
                    onClick={() => {
                      if (confirm('Delete this region and all its cities/nodes?')) {
                        onDeleteRegion(region.id)
                      }
                    }}
                    className="p-1.5 text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                    title="Delete region"
                  >
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                  </button>
                </div>
              </div>

              {isExpanded && (
                <div className="pl-8 pb-2 space-y-1">
                  {regionCities.map((city) => {
                    const cityNodes = getNodesForCity(city.id)
                    const isCityExpanded = expandedCities.has(city.id)

                    return (
                      <div key={city.id} className="border-l-2 border-green-200 ml-4">
                        <div className="flex items-center gap-3 p-3 hover:bg-gray-50 transition-colors">
                          {/* Expand/Collapse Button */}
                          <button
                            onClick={() => toggleCity(city.id)}
                            className="text-gray-400 hover:text-gray-600 transition-colors ml-2"
                          >
                            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                              {isCityExpanded ? (
                                <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
                              ) : (
                                <path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clipRule="evenodd" />
                              )}
                            </svg>
                          </button>

                          {/* City Icon */}
                          <div className="w-8 h-8 bg-green-100 rounded-lg flex items-center justify-center">
                            <svg className="w-4 h-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
                            </svg>
                          </div>

                          {/* City Name + Classification + Status */}
                          <div className="flex-1 flex items-center gap-2">
                            <span className="font-medium text-gray-900">
                              {city.name}
                            </span>
                            <span className="text-sm text-gray-500">({city.code})</span>
                            {city.classification && (
                              <span className="text-xs font-medium bg-purple-100 text-purple-700 px-2 py-0.5 rounded-full">
                                Class {city.classification}
                              </span>
                            )}
                            <span
                              className={`text-xs font-medium px-2.5 py-0.5 rounded-full ${
                                city.status === 'active'
                                  ? 'bg-green-100 text-green-700'
                                  : 'bg-gray-100 text-gray-600'
                              }`}
                            >
                              {city.status === 'active' ? 'Active' : 'Inactive'}
                            </span>
                          </div>

                          {/* Action Buttons (Right Side) */}
                          <div className="flex items-center gap-2">
                            <button
                              onClick={() => onCreateNode({ city_id: city.id })}
                              className="flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
                            >
                              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                              </svg>
                              Node
                            </button>
                            <button
                              onClick={() =>
                                setModal({
                                  type: 'city',
                                  regionId: city.region_id,
                                  city: city,
                                  onSubmit: (data: any) => onUpdateCity(city.id, data),
                                })
                              }
                              className="p-1 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
                              title="Edit city"
                            >
                              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                              </svg>
                            </button>
                            <button
                              onClick={() => {
                                if (confirm('Delete this city and all its nodes?')) {
                                  onDeleteCity(city.id)
                                }
                              }}
                              className="p-1 text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                              title="Delete city"
                            >
                              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                              </svg>
                            </button>
                          </div>
                        </div>

                        {isCityExpanded && (
                          <div className="pl-12 space-y-1 py-2">
                            {cityNodes.map((node) => (
                              <div
                                key={node.id}
                                className="flex items-center gap-3 p-2.5 hover:bg-gray-50 transition-colors rounded-lg"
                              >
                                {/* Node Icon */}
                                <div className="w-7 h-7 bg-blue-100 rounded-lg flex items-center justify-center">
                                  <svg className="w-3.5 h-3.5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01" />
                                  </svg>
                                </div>

                                {/* Node ID + Status */}
                                <div className="flex-1 flex items-center gap-2">
                                  <span className="font-mono text-sm text-blue-600 font-medium">{node.auto_id}</span>
                                  <span
                                    className={`text-xs font-medium px-2.5 py-0.5 rounded-full ${
                                      node.status === 'active'
                                        ? 'bg-green-100 text-green-700'
                                        : 'bg-gray-100 text-gray-600'
                                    }`}
                                  >
                                    {node.status === 'active' ? 'Active' : 'Inactive'}
                                  </span>
                                </div>

                                {/* Delete Button */}
                                <button
                                  onClick={() => {
                                    if (confirm('Delete this node?')) {
                                      onDeleteNode(node.id)
                                    }
                                  }}
                                  className="p-1 text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                                  title="Delete node"
                                >
                                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                                  </svg>
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
