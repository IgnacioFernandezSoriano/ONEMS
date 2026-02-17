import { useEffect, useRef, useMemo, useState } from 'react'
import { MapContainer, TileLayer, CircleMarker, Polyline, Tooltip, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { supabase } from '@/lib/supabase'

// Fix for default marker icons in Leaflet with Webpack/Vite
delete (L.Icon.Default.prototype as any)._getIconUrl
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png',
  iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
})

interface RoutePathData {
  id: string
  carrier_id: string
  product_id: string
  origin_city_name: string
  destination_city_name: string
  total_tags: number
  avg_natural_time_minutes: number
  avg_working_time_minutes: number
  expected_time_minutes: number
  compliance_rate: number
  segment_details?: any[]
}

interface PostalCenter {
  code: string
  name: string
  city: string
  latitude: number | null
  longitude: number | null
}

interface Props {
  routePaths: RoutePathData[]
}

// Component to auto-fit bounds
function AutoFitBounds({ centers }: { centers: PostalCenter[] }) {
  const map = useMap()

  useEffect(() => {
    const validCenters = centers.filter(c => c.latitude != null && c.longitude != null)
    if (validCenters.length === 0) return

    const bounds = L.latLngBounds(
      validCenters.map(c => [c.latitude!, c.longitude!])
    )

    map.fitBounds(bounds, { padding: [50, 50] })
  }, [centers, map])

  return null
}

export default function RoutePathMapLeaflet({ routePaths }: Props) {
  const mapRef = useRef<L.Map>(null)
  const [centers, setCenters] = useState<PostalCenter[]>([])
  const [loading, setLoading] = useState(true)

  // Fetch postal centers with coordinates
  useEffect(() => {
    const fetchCenters = async () => {
      const { data, error } = await supabase
        .from('postal_centers')
        .select('code, name, city, latitude, longitude')
        .not('latitude', 'is', null)
        .not('longitude', 'is', null)

      if (!error && data) {
        setCenters(data)
      }
      setLoading(false)
    }

    fetchCenters()
  }, [])

  // Build center lookup map by city name
  const centerMap = useMemo(() => {
    const map = new Map<string, PostalCenter>()
    centers.forEach(c => map.set(c.city, c))
    return map
  }, [centers])

  // Build routes with coordinates
  const routesWithCoords = useMemo(() => {
    return routePaths
      .map(path => {
        const origin = centerMap.get(path.origin_city_name)
        const destination = centerMap.get(path.destination_city_name)

        if (!origin || !destination || 
            origin.latitude == null || origin.longitude == null ||
            destination.latitude == null || destination.longitude == null) {
          return null
        }

        return {
          ...path,
          originCenter: origin,
          destinationCenter: destination
        }
      })
      .filter(Boolean) as Array<RoutePathData & {
        originCenter: PostalCenter
        destinationCenter: PostalCenter
      }>
  }, [routePaths, centerMap])

  // Get unique centers from routes
  const activeCenters = useMemo(() => {
    const centerSet = new Set<string>()
    routesWithCoords.forEach(route => {
      centerSet.add(route.originCenter.code)
      centerSet.add(route.destinationCenter.code)
    })
    return centers.filter(c => centerSet.has(c.code))
  }, [routesWithCoords, centers])

  // Calculate center stats with operational metrics
  const centerStats = useMemo(() => {
    const stats = new Map<string, { 
      inbound: number
      outbound: number
      operational_segments: any[]
    }>()
    
    routesWithCoords.forEach(route => {
      const origin = route.originCenter.code
      const dest = route.destinationCenter.code

      if (!stats.has(origin)) stats.set(origin, { inbound: 0, outbound: 0, operational_segments: [] })
      if (!stats.has(dest)) stats.set(dest, { inbound: 0, outbound: 0, operational_segments: [] })

      stats.get(origin)!.outbound += route.total_tags
      stats.get(dest)!.inbound += route.total_tags
      
      // Collect operational segments
      if (route.segment_details) {
        route.segment_details.forEach((seg: any) => {
          if (seg.segment_type === 'operational') {
            const centerCity = seg.from_city
            const centerCode = route.originCenter.city === centerCity ? origin : dest
            if (stats.has(centerCode)) {
              stats.get(centerCode)!.operational_segments.push(seg)
            }
          }
        })
      }
    })

    return stats
  }, [routesWithCoords])

  // Calculate aggregated metrics from segment_details
  const calculateWeightedStd = (segmentDetails: any[]) => {
    if (!segmentDetails || segmentDetails.length === 0) return 95
    
    const totalTags = segmentDetails.reduce((sum, seg) => sum + (seg.tags_count || 0), 0)
    if (totalTags === 0) return 95
    
    const weightedSum = segmentDetails.reduce((sum, seg) => {
      return sum + (seg.on_time_percentage_std || 95) * (seg.tags_count || 0)
    }, 0)
    
    return weightedSum / totalTags
  }

  const getThresholdsFromSegments = (segmentDetails: any[]) => {
    // Get thresholds from first distribution segment
    const distSegment = segmentDetails?.find(seg => seg.segment_type === 'distribution')
    return {
      warning: distSegment?.warning_threshold || 90,
      critical: distSegment?.critical_threshold || 80
    }
  }

  // Get circle radius based on tag volume
  const getRadius = (code: string) => {
    const stat = centerStats.get(code)
    if (!stat) return 8
    const total = stat.inbound + stat.outbound
    return Math.max(8, Math.min(30, Math.sqrt(total) * 2))
  }

  // Get color based on compliance rate
  const getRouteColor = (complianceRate: number) => {
    if (complianceRate >= 90) return '#10b981' // green
    if (complianceRate >= 80) return '#f59e0b' // yellow
    return '#ef4444' // red
  }

  // Get line weight based on tag volume
  const getLineWeight = (tags: number) => {
    return Math.max(2, Math.min(8, Math.sqrt(tags) / 2))
  }

  if (loading) {
    return (
      <div className="bg-gray-50 border border-gray-200 rounded-lg p-8 text-center">
        <p className="text-gray-600">Loading map...</p>
      </div>
    )
  }

  if (routesWithCoords.length === 0) {
    return (
      <div className="bg-gray-50 border border-gray-200 rounded-lg p-8 text-center">
        <p className="text-gray-600">
          No route data with valid coordinates available. Please ensure postal centers have latitude and longitude data.
        </p>
      </div>
    )
  }

  return (
    <div className="relative h-[400px] bg-white border border-gray-200 rounded-lg overflow-hidden">
      <MapContainer
        ref={mapRef}
        center={[39.8283, -98.5795]} // Center of USA
        zoom={4}
        style={{ height: '100%', width: '100%' }}
        zoomControl={true}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />

        <AutoFitBounds centers={activeCenters} />

        {/* Draw route segments */}
        {routesWithCoords.map((route, routeIdx) => {
          // Get distribution segments (actual routes between centers)
          const distributionSegments = (route.segment_details || []).filter(
            (seg: any) => seg.segment_type === 'distribution' && seg.from_city && seg.to_city
          )

          return distributionSegments.map((segment: any, segIdx: number) => {
            const fromCenter = centerMap.get(segment.from_city)
            const toCenter = centerMap.get(segment.to_city)

            if (!fromCenter || !toCenter || 
                fromCenter.latitude == null || fromCenter.longitude == null ||
                toCenter.latitude == null || toCenter.longitude == null) {
              return null
            }

            const positions: [number, number][] = [
              [fromCenter.latitude, fromCenter.longitude],
              [toCenter.latitude, toCenter.longitude]
            ]

            return (
              <Polyline
                key={`route-${routeIdx}-seg-${segIdx}`}
                positions={positions}
                pathOptions={{
                  color: getRouteColor(segment.compliance_rate || route.compliance_rate),
                  weight: getLineWeight(segment.tags_count || 1),
                  opacity: 0.6
                }}
              >
              <Tooltip sticky>
                <div className="text-xs" style={{ minWidth: '280px' }}>
                  <div className="font-semibold mb-2 pb-1 border-b border-gray-300">
                    {segment.from_city} → {segment.to_city}
                  </div>
                  <div className="space-y-1">
                    <div className="flex justify-between">
                      <span className="text-gray-600">Tags:</span>
                      <span className="font-medium">{segment.tags_count}</span>
                    </div>
                    
                    {/* J+K Std */}
                    <div className="flex justify-between">
                      <span className="text-gray-600">J+K Std:</span>
                      <span className="font-medium">{(segment.expected_time_minutes / 60).toFixed(1)}h</span>
                    </div>
                    
                    {/* J+K Natural Real */}
                    <div className="flex justify-between">
                      <span className="text-gray-600">J+K Natural Real:</span>
                      <span className="font-medium">
                        {(segment.avg_total_time_natural / 60).toFixed(1)}h
                        <span style={{
                          color: segment.avg_total_time_natural <= segment.expected_time_minutes ? '#10b981' : '#ef4444',
                          marginLeft: '4px'
                        }}>
                          ({segment.avg_total_time_natural <= segment.expected_time_minutes ? '-' : '+'}
                          {Math.abs(segment.avg_total_time_natural - segment.expected_time_minutes).toFixed(0)}min)
                        </span>
                      </span>
                    </div>
                    
                    {/* J+K Working Real */}
                    <div className="flex justify-between">
                      <span className="text-gray-600">J+K Working Real:</span>
                      <span className="font-medium">
                        {(segment.avg_total_time_working / 60).toFixed(1)}h
                        <span style={{
                          color: segment.avg_total_time_working <= segment.expected_time_minutes ? '#10b981' : '#ef4444',
                          marginLeft: '4px'
                        }}>
                          ({segment.avg_total_time_working <= segment.expected_time_minutes ? '-' : '+'}
                          {Math.abs(segment.avg_total_time_working - segment.expected_time_minutes).toFixed(0)}min)
                        </span>
                      </span>
                    </div>
                    
                    {/* % Std */}
                    <div className="flex justify-between">
                      <span className="text-gray-600">% Std:</span>
                      <span className="font-medium">{segment.on_time_percentage_std}%</span>
                    </div>
                    
                    {/* % Real */}
                    <div className="flex justify-between">
                      <span className="text-gray-600">% Real:</span>
                      <span className="font-medium">
                        {segment.compliance_rate}%
                        {(() => {
                          const diff = segment.compliance_rate - segment.on_time_percentage_std
                          return (
                            <span style={{
                              color: diff >= 0 ? '#10b981' : '#ef4444',
                              marginLeft: '4px'
                            }}>
                              ({diff >= 0 ? '+' : ''}{diff.toFixed(1)}%)
                            </span>
                          )
                        })()}
                      </span>
                    </div>
                    
                    {/* Threshold Status */}
                    {(() => {
                      const isCompliant = segment.compliance_rate >= segment.warning_threshold
                      const isWarning = segment.compliance_rate >= segment.critical_threshold && segment.compliance_rate < segment.warning_threshold
                      const isCritical = segment.compliance_rate < segment.critical_threshold
                      
                      return (
                        <div className="flex justify-between items-center mt-2 pt-1 border-t border-gray-300">
                          <span className="text-gray-600">Status:</span>
                          <span className="font-semibold px-2 py-0.5 rounded" style={{
                            backgroundColor: isCompliant ? '#d1fae5' : isWarning ? '#fef3c7' : '#fee2e2',
                            color: isCompliant ? '#065f46' : isWarning ? '#92400e' : '#991b1b'
                          }}>
                            {isCompliant ? '✓ Compliant' : isWarning ? '⚠ Warning' : '✗ Critical'}
                            <span className="text-xs ml-1">({segment.warning_threshold}%/{segment.critical_threshold}%)</span>
                          </span>
                        </div>
                      )
                    })()}
                  </div>
                </div>
              </Tooltip>
            </Polyline>
            )
          })
        })}

        {/* Draw center markers */}
        {activeCenters.map((center) => {
          const stat = centerStats.get(center.code)
          if (!stat) return null

          return (
            <CircleMarker
              key={center.code}
              center={[center.latitude!, center.longitude!]}
              radius={getRadius(center.code)}
              pathOptions={{
                fillColor: '#3b82f6',
                fillOpacity: 0.7,
                color: '#1e40af',
                weight: 2
              }}
             >
              <Tooltip sticky>
                <div className="text-xs" style={{ minWidth: '280px' }}>
                  <div className="font-semibold mb-2 pb-1 border-b border-gray-300">
                    {center.name}
                  </div>
                  <div className="text-gray-600 mb-2">{center.city}</div>
                  
                  {stat.operational_segments.length > 0 ? (() => {
                    // Calculate aggregated operational metrics
                    const totalTags = stat.operational_segments.reduce((sum, seg) => sum + (seg.tags_count || 0), 0)
                    const avgNatural = stat.operational_segments.reduce((sum, seg) => sum + (seg.avg_total_time_natural || 0) * (seg.tags_count || 0), 0) / (totalTags || 1)
                    const avgWorking = stat.operational_segments.reduce((sum, seg) => sum + (seg.avg_total_time_working || 0) * (seg.tags_count || 0), 0) / (totalTags || 1)
                    const avgExpected = stat.operational_segments.reduce((sum, seg) => sum + (seg.expected_time_minutes || 0) * (seg.tags_count || 0), 0) / (totalTags || 1)
                    const avgStd = stat.operational_segments.reduce((sum, seg) => sum + (seg.on_time_percentage_std || 95) * (seg.tags_count || 0), 0) / (totalTags || 1)
                    const avgCompliance = stat.operational_segments.reduce((sum, seg) => sum + (seg.compliance_rate || 0) * (seg.tags_count || 0), 0) / (totalTags || 1)
                    const avgWarning = stat.operational_segments.reduce((sum, seg) => sum + (seg.warning_threshold || 90) * (seg.tags_count || 0), 0) / (totalTags || 1)
                    const avgCritical = stat.operational_segments.reduce((sum, seg) => sum + (seg.critical_threshold || 80) * (seg.tags_count || 0), 0) / (totalTags || 1)
                    
                    return (
                      <div className="space-y-1">
                        <div className="flex justify-between">
                          <span className="text-gray-600">Tags:</span>
                          <span className="font-medium">{totalTags}</span>
                        </div>
                        
                        <div className="flex justify-between">
                          <span className="text-gray-600">J+K Std:</span>
                          <span className="font-medium">{(avgExpected / 60).toFixed(1)}h</span>
                        </div>
                        
                        <div className="flex justify-between">
                          <span className="text-gray-600">J+K Natural Real:</span>
                          <span className="font-medium">
                            {(avgNatural / 60).toFixed(1)}h
                            <span style={{
                              color: avgNatural <= avgExpected ? '#10b981' : '#ef4444',
                              marginLeft: '4px'
                            }}>
                              ({avgNatural <= avgExpected ? '-' : '+'}
                              {Math.abs(avgNatural - avgExpected).toFixed(0)}min)
                            </span>
                          </span>
                        </div>
                        
                        <div className="flex justify-between">
                          <span className="text-gray-600">J+K Working Real:</span>
                          <span className="font-medium">
                            {(avgWorking / 60).toFixed(1)}h
                            <span style={{
                              color: avgWorking <= avgExpected ? '#10b981' : '#ef4444',
                              marginLeft: '4px'
                            }}>
                              ({avgWorking <= avgExpected ? '-' : '+'}
                              {Math.abs(avgWorking - avgExpected).toFixed(0)}min)
                            </span>
                          </span>
                        </div>
                        
                        <div className="flex justify-between">
                          <span className="text-gray-600">% Std:</span>
                          <span className="font-medium">{avgStd.toFixed(0)}%</span>
                        </div>
                        
                        <div className="flex justify-between">
                          <span className="text-gray-600">% Real:</span>
                          <span className="font-medium">
                            {avgCompliance.toFixed(1)}%
                            <span style={{
                              color: avgCompliance >= avgStd ? '#10b981' : '#ef4444',
                              marginLeft: '4px'
                            }}>
                              ({avgCompliance >= avgStd ? '+' : ''}
                              {(avgCompliance - avgStd).toFixed(1)}%)
                            </span>
                          </span>
                        </div>
                        
                        <div className="flex justify-between items-center mt-2 pt-2 border-t border-gray-200">
                          <span className="text-gray-600">Status:</span>
                          <span className="px-2 py-0.5 rounded text-xs font-semibold" style={{
                            backgroundColor: avgCompliance >= avgWarning ? '#dcfce7' : avgCompliance >= avgCritical ? '#fef3c7' : '#fee2e2',
                            color: avgCompliance >= avgWarning ? '#166534' : avgCompliance >= avgCritical ? '#92400e' : '#991b1b'
                          }}>
                            {avgCompliance >= avgWarning ? '✓ Compliant' : avgCompliance >= avgCritical ? '⚠ Warning' : '✗ Critical'} ({avgWarning.toFixed(0)}%/{avgCritical.toFixed(0)}%)
                          </span>
                        </div>
                        
                        <div className="mt-2 pt-2 border-t border-gray-200 text-gray-500">
                          <div>Inbound: {stat.inbound} tags</div>
                          <div>Outbound: {stat.outbound} tags</div>
                        </div>
                      </div>
                    )
                  })() : (
                    <div className="space-y-1">
                      <div>Inbound: {stat.inbound} tags</div>
                      <div>Outbound: {stat.outbound} tags</div>
                      <div className="text-gray-500 mt-2">No operational data</div>
                    </div>
                  )}
                </div>
              </Tooltip>
            </CircleMarker>
          )
        })}
      </MapContainer>

      {/* Legend */}
      <div className="absolute bottom-4 right-4 bg-white p-3 rounded-lg shadow-lg border border-gray-200 text-xs">
        <div className="font-semibold mb-2">Route Compliance</div>
        <div className="space-y-1">
          <div className="flex items-center gap-2">
            <div className="w-8 h-0.5 bg-green-500"></div>
            <span>≥90%</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-8 h-0.5 bg-yellow-500"></div>
            <span>80-90%</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-8 h-0.5 bg-red-500"></div>
            <span>&lt;80%</span>
          </div>
        </div>
      </div>
    </div>
  )
}
