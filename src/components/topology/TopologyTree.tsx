import { useState, useEffect } from 'react'
import { Modal } from '@/components/common/Modal'
import { RegionForm } from './RegionForm'
import { CityForm } from './CityForm'

import type { Region, City, Node } from '@/lib/types'

interface TopologyTreeProps {
  regions: Region[]
  cities: City[]
  nodes: (Node & { hasPanelist?: boolean; panelist?: any })[]
  panelists: any[]
  expandAll: boolean
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
  panelists,
  expandAll,
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

  // Handle expandAll prop changes
  useEffect(() => {
    if (expandAll) {
      setExpandedRegions(new Set(regions.map(r => r.id)))
      setExpandedCities(new Set(cities.map(c => c.id)))
    } else {
      setExpandedRegions(new Set())
      setExpandedCities(new Set())
    }
  }, [expandAll, regions, cities])

  const toggleRegion = (id: string) => {
    const newExpanded = new Set(expandedRegions)
    if (newExpanded.has(id)) {
      newExpanded.delete(id)
      // Also collapse all cities in this region
      const regionCities = getCitiesForRegion(id)
      const newExpandedCities = new Set(expandedCities)
      regionCities.forEach(city => newExpandedCities.delete(city.id))
      setExpandedCities(newExpandedCities)
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

  const expandRegionAndCities = (regionId: string) => {
    const newExpandedRegions = new Set(expandedRegions)
    newExpandedRegions.add(regionId)
    setExpandedRegions(newExpandedRegions)

    const regionCities = getCitiesForRegion(regionId)
    const newExpandedCities = new Set(expandedCities)
    regionCities.forEach(city => newExpandedCities.add(city.id))
    setExpandedCities(newExpandedCities)
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
            <div key={region.id} className="border rounded-lg bg-white shadow-sm">
              <div className="flex items-center gap-3 p-4 hover:bg-gray-50 transition-colors">
                {/* Expand/Collapse Button */}
                <button
                  onClick={() => toggleRegion(region.id)}
                  className="text-gray-400 hover:text-gray-600 transition-colors"
                  title={isExpanded ? 'Collapse region' : 'Expand region'}
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

                {/* Action Buttons */}
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => expandRegionAndCities(region.id)}
                    className="px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
                    title="Expand all cities in this region"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4" />
                    </svg>
                  </button>
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
                  {regionCities.length === 0 && (
                    <div className="text-sm text-gray-500 italic p-4">
                      No cities in this region yet
                    </div>
                  )}
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
                            title={isCityExpanded ? 'Collapse city' : 'Expand city'}
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

                          {/* Action Buttons */}
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
                          <div className="pl-6 pb-2 space-y-1">
                            {cityNodes.length === 0 && (
                              <div className="text-sm text-gray-500 italic p-3 ml-4">
                                No nodes in this city yet
                              </div>
                            )}
                            {cityNodes.map((node) => (
                              <div
                                key={node.id}
                                className="flex items-center gap-3 p-2 ml-4 hover:bg-gray-50 transition-colors rounded-lg"
                              >
                                {/* Node Icon */}
                                <div className="w-7 h-7 bg-purple-100 rounded-lg flex items-center justify-center ml-4">
                                  <svg className="w-3.5 h-3.5 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                                  </svg>
                                </div>

                                {/* Node ID */}
                                <div className="flex-1 flex items-center gap-2">
                                  <span className="text-sm font-medium text-gray-900">
                                    {node.auto_id}
                                  </span>
                                  
                                  {/* Panelist Status Badge */}
                                  {node.hasPanelist ? (
                                    <span className="inline-flex items-center gap-1 text-xs font-medium bg-emerald-100 text-emerald-700 px-2 py-0.5 rounded-full">
                                      <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                                      </svg>
                                      Panelist Assigned
                                    </span>
                                  ) : (
                                    <span className="inline-flex items-center gap-1 text-xs font-medium bg-amber-100 text-amber-700 px-2 py-0.5 rounded-full">
                                      <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                                      </svg>
                                      Pending Panelist
                                    </span>
                                  )}

                                  <span
                                    className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                                      node.status === 'active'
                                        ? 'bg-green-100 text-green-700'
                                        : 'bg-gray-100 text-gray-600'
                                    }`}
                                  >
                                    {node.status === 'active' ? 'Active' : 'Inactive'}
                                  </span>
                                </div>

                                {/* Action Buttons */}
                                <div className="flex items-center gap-1">
                                  <button
                                    onClick={() =>
                                      setModal({
                                        type: 'node',
                                        cityId: node.city_id,
                                        node: node,
                                        onSubmit: (data: any) => onUpdateNode(node.id, data),
                                      })
                                    }
                                    className="p-1 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
                                    title="Edit node"
                                  >
                                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                                    </svg>
                                  </button>
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
              : modal.type === 'city'
              ? modal.city
                ? 'Edit City'
                : 'Create City'
              : 'Node Details'
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
