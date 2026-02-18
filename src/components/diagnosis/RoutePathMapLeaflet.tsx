import { useEffect, useRef, useMemo, useState } from 'react'
import { MapContainer, TileLayer, CircleMarker, Polyline, Tooltip, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'

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
  path_signature: string
  total_tags: number
  avg_natural_time_minutes: number
  avg_working_time_minutes: number
  expected_time_minutes: number
  compliance_rate: number
}

interface PostalCenter {
  id: string
  code: string
  name: string
  city: string
  latitude: number
  longitude: number
}

interface SegmentData {
  fromCenter: PostalCenter
  toCenter: PostalCenter
  segmentType: 'center' | 'transit'
  jkStd: number
  naturalTime: number
  workingTime: number
  stdPercentage: number
  realPercentage: number
  threshold: string
  tags: number
}

interface Props {
  routePaths: RoutePathData[]
}

// Component to auto-fit bounds
function AutoFitBounds({ centers }: { centers: PostalCenter[] }) {
  const map = useMap()

  useEffect(() => {
    if (centers.length === 0) return

    const bounds = L.latLngBounds(
      centers.map(c => [c.latitude, c.longitude])
    )

    map.fitBounds(bounds, { padding: [50, 50] })
  }, [centers, map])

  return null
}

export default function RoutePathMapLeaflet({ routePaths }: Props) {
  const { effectiveAccountId } = useAccount()
  const mapRef = useRef<L.Map>(null)
  const [segments, setSegments] = useState<SegmentData[]>([])
  const [loading, setLoading] = useState(true)

  // Fetch segments for all routes
  useEffect(() => {
    const fetchSegments = async () => {
      if (!effectiveAccountId || routePaths.length === 0) {
        setLoading(false)
        return
      }

      try {
        // Get all journey_segments
        const { data: journeySegments, error: segmentsError } = await supabase
          .from('journey_segments')
          .select('*')
          .eq('account_id', effectiveAccountId)
          .order('entry_timestamp')

        if (segmentsError) throw segmentsError

        // Get postal centers with coordinates
        const { data: centers, error: centersError } = await supabase
          .from('postal_centers')
          .select('id, code, name, city, latitude, longitude')
          .eq('account_id', effectiveAccountId)

        if (centersError) throw centersError

        // Create lookup map for centers
        const centerMap = new Map(centers?.map(c => [c.id, c]) || [])

        // Get SLAs
        const { data: slas, error: slasError } = await supabase
          .from('slas')
          .select('*')
          .eq('account_id', effectiveAccountId)
          .eq('is_active', true)

        if (slasError) throw slasError

        // Process each route
        const allSegments: SegmentData[] = []

        routePaths.forEach(route => {
          const pathCities = route.path_signature.split(' | ')
          
          pathCities.forEach(pathSegment => {
            const matchingSegs = journeySegments?.filter(seg => {
              const segPath = `${seg.from_postal_center_city}→${seg.to_postal_center_city}`
              return segPath === pathSegment
            }) || []

            if (matchingSegs.length === 0) return

            const firstSeg = matchingSegs[0]
            const totalTags = matchingSegs.length

            // Get centers from map
            const fromCenter = centerMap.get(firstSeg.from_postal_center_id)
            const toCenter = centerMap.get(firstSeg.to_postal_center_id)
            
            // Skip if centers don't exist or don't have coordinates
            
            if (!fromCenter || !toCenter ||
                fromCenter.latitude == null || fromCenter.longitude == null ||
                toCenter.latitude == null || toCenter.longitude == null) {
              return
            }

            // Calculate averages
            const avgNaturalCenter = matchingSegs.reduce((sum, s) => sum + (s.natural_time_in_center_minutes || 0), 0) / totalTags
            const avgNaturalTransit = matchingSegs.reduce((sum, s) => sum + (s.natural_transit_time_minutes || 0), 0) / totalTags
            const avgWorkingCenter = matchingSegs.reduce((sum, s) => sum + (s.working_time_in_center_minutes || 0), 0) / totalTags
            const avgWorkingTransit = matchingSegs.reduce((sum, s) => sum + (s.working_transit_time_minutes || 0), 0) / totalTags

            // Find SLAs
            const centerSLA = slas?.find(sla => 
              sla.sla_type === 'operational' && 
              sla.postal_center_id === firstSeg.from_postal_center_id
            )
            
            const transitSLA = slas?.find(sla => 
              sla.sla_type === 'distribution' && 
              sla.from_postal_center_id === firstSeg.from_postal_center_id &&
              sla.to_postal_center_id === firstSeg.to_postal_center_id
            )

            // Add center segment
            if (avgNaturalCenter > 0 || centerSLA) {
              const jkStd = centerSLA?.expected_time_minutes || 0
              const stdPercentage = centerSLA?.on_time_percentage || 95
              const warningThreshold = centerSLA?.warning_threshold || 90
              const criticalThreshold = centerSLA?.critical_threshold || 80
              
              const tagsOnTime = matchingSegs.filter(s => (s.natural_time_in_center_minutes || 0) <= jkStd).length
              const realPercentage = totalTags > 0 ? (tagsOnTime / totalTags) * 100 : 0

              const threshold = realPercentage >= warningThreshold ? 'Compliant' :
                               realPercentage >= criticalThreshold ? 'Warning' : 'Critical'

              allSegments.push({
                fromCenter,
                toCenter: fromCenter, // Same center for operational
                segmentType: 'center',
                jkStd,
                naturalTime: avgNaturalCenter,
                workingTime: avgWorkingCenter,
                stdPercentage,
                realPercentage,
                threshold,
                tags: totalTags
              })
            }

            // Add transit segment
            if (avgNaturalTransit > 0 || transitSLA) {
              const jkStd = transitSLA?.expected_time_minutes || 0
              const stdPercentage = transitSLA?.on_time_percentage || 95
              const warningThreshold = transitSLA?.warning_threshold || 90
              const criticalThreshold = transitSLA?.critical_threshold || 80
              
              const tagsOnTime = matchingSegs.filter(s => (s.natural_transit_time_minutes || 0) <= jkStd).length
              const realPercentage = totalTags > 0 ? (tagsOnTime / totalTags) * 100 : 0

              const threshold = realPercentage >= warningThreshold ? 'Compliant' :
                               realPercentage >= criticalThreshold ? 'Warning' : 'Critical'

              allSegments.push({
                fromCenter,
                toCenter,
                segmentType: 'transit',
                jkStd,
                naturalTime: avgNaturalTransit,
                workingTime: avgWorkingTransit,
                stdPercentage,
                realPercentage,
                threshold,
                tags: totalTags
              })
            }
          })
        })

        setSegments(allSegments)
      } catch (err: any) {
        console.error('Error loading map segments:', err)
      } finally {
        setLoading(false)
      }
    }

    fetchSegments()
  }, [effectiveAccountId, routePaths])

  // Get unique centers
  const uniqueCenters = useMemo(() => {
    const centerMap = new Map<string, PostalCenter>()
    segments.forEach(seg => {
      centerMap.set(seg.fromCenter.id, seg.fromCenter)
      if (seg.segmentType === 'transit') {
        centerMap.set(seg.toCenter.id, seg.toCenter)
      }
    })
    return Array.from(centerMap.values())
  }, [segments])

  // Format time for display
  const formatTime = (minutes: number) => {
    const days = Math.floor(minutes / 1440)
    const hours = Math.floor((minutes % 1440) / 60)
    const mins = Math.round(minutes % 60)
    
    if (days > 0) {
      return `${days.toFixed(2)} days`
    } else if (hours > 0) {
      return `${hours}h ${mins}m`
    } else {
      return `${mins}m`
    }
  }

  // Get color based on threshold
  const getColor = (threshold: string) => {
    switch (threshold) {
      case 'Compliant': return '#10b981'
      case 'Warning': return '#f59e0b'
      case 'Critical': return '#ef4444'
      default: return '#6b7280'
    }
  }

  if (loading) {
    return (
      <div className="bg-gray-50 border border-gray-200 rounded-lg p-8 text-center">
        <p className="text-gray-600">Loading map...</p>
      </div>
    )
  }

  if (segments.length === 0) {
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

        <AutoFitBounds centers={uniqueCenters} />

        {/* Draw transit segments as lines */}
        {segments.filter(seg => seg.segmentType === 'transit').map((segment, idx) => {
          const positions: [number, number][] = [
            [segment.fromCenter.latitude, segment.fromCenter.longitude],
            [segment.toCenter.latitude, segment.toCenter.longitude]
          ]

          return (
            <Polyline
              key={`transit-${idx}`}
              positions={positions}
              pathOptions={{
                color: getColor(segment.threshold),
                weight: Math.max(2, Math.min(8, Math.sqrt(segment.tags) / 2)),
                opacity: 0.6
              }}
            >
              <Tooltip sticky>
                <div className="text-xs" style={{ minWidth: '280px' }}>
                  <div className="font-semibold mb-2 pb-1 border-b border-gray-300">
                    {segment.fromCenter.name} → {segment.toCenter.name}
                  </div>
                  <div className="space-y-1">
                    <div className="flex justify-between">
                      <span className="text-gray-600">Type:</span>
                      <span className="font-medium">Transit</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Tags:</span>
                      <span className="font-medium">{segment.tags}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">J+K STD:</span>
                      <span className="font-medium">{formatTime(segment.jkStd)}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Natural Time:</span>
                      <span className="font-medium">
                        {formatTime(segment.naturalTime)}
                        <span style={{
                          color: segment.naturalTime <= segment.jkStd ? '#10b981' : '#ef4444',
                          marginLeft: '4px'
                        }}>
                          ({segment.naturalTime <= segment.jkStd ? '-' : '+'}
                          {Math.abs(segment.naturalTime - segment.jkStd).toFixed(0)}min)
                        </span>
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Working Time:</span>
                      <span className="font-medium">
                        {formatTime(segment.workingTime)}
                        <span style={{
                          color: segment.workingTime <= segment.jkStd ? '#10b981' : '#ef4444',
                          marginLeft: '4px'
                        }}>
                          ({segment.workingTime <= segment.jkStd ? '-' : '+'}
                          {Math.abs(segment.workingTime - segment.jkStd).toFixed(0)}min)
                        </span>
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">% STD:</span>
                      <span className="font-medium">{segment.stdPercentage}%</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">% Real:</span>
                      <span className="font-medium">
                        {segment.realPercentage.toFixed(1)}%
                        <span style={{
                          color: segment.realPercentage >= segment.stdPercentage ? '#10b981' : '#ef4444',
                          marginLeft: '4px'
                        }}>
                          ({segment.realPercentage >= segment.stdPercentage ? '+' : ''}
                          {(segment.realPercentage - segment.stdPercentage).toFixed(1)}%)
                        </span>
                      </span>
                    </div>
                    <div className="flex justify-between items-center mt-2 pt-1 border-t border-gray-300">
                      <span className="text-gray-600">Status:</span>
                      <span className="font-semibold px-2 py-0.5 rounded" style={{
                        backgroundColor: segment.threshold === 'Compliant' ? '#d1fae5' : 
                                       segment.threshold === 'Warning' ? '#fef3c7' : '#fee2e2',
                        color: segment.threshold === 'Compliant' ? '#065f46' : 
                               segment.threshold === 'Warning' ? '#92400e' : '#991b1b'
                      }}>
                        {segment.threshold === 'Compliant' ? '✓ Compliant' : 
                         segment.threshold === 'Warning' ? '⚠ Warning' : '✗ Critical'}
                      </span>
                    </div>
                  </div>
                </div>
              </Tooltip>
            </Polyline>
          )
        })}

        {/* Draw center markers */}
        {uniqueCenters.map((center) => {
          // Find all center segments for this center
          const centerSegments = segments.filter(s => 
            s.segmentType === 'center' && s.fromCenter.id === center.id
          )

          if (centerSegments.length === 0) {
            return (
              <CircleMarker
                key={center.id}
                center={[center.latitude, center.longitude]}
                radius={8}
                pathOptions={{
                  fillColor: '#3b82f6',
                  fillOpacity: 0.7,
                  color: '#1e40af',
                  weight: 2
                }}
              >
                <Tooltip sticky>
                  <div className="text-xs" style={{ minWidth: '200px' }}>
                    <div className="font-semibold mb-2 pb-1 border-b border-gray-300">
                      {center.name}
                    </div>
                    <div className="text-gray-600">{center.city}</div>
                    <div className="mt-2 text-gray-500">Transit point (no operational data)</div>
                  </div>
                </Tooltip>
              </CircleMarker>
            )
          }

          // Calculate aggregated metrics
          const totalTags = centerSegments.reduce((sum, s) => sum + s.tags, 0)
          const avgNatural = centerSegments.reduce((sum, s) => sum + s.naturalTime * s.tags, 0) / totalTags
          const avgWorking = centerSegments.reduce((sum, s) => sum + s.workingTime * s.tags, 0) / totalTags
          const avgJkStd = centerSegments.reduce((sum, s) => sum + s.jkStd * s.tags, 0) / totalTags
          const avgStdPct = centerSegments.reduce((sum, s) => sum + s.stdPercentage * s.tags, 0) / totalTags
          const avgRealPct = centerSegments.reduce((sum, s) => sum + s.realPercentage * s.tags, 0) / totalTags

          const threshold = centerSegments[0].threshold

          return (
            <CircleMarker
              key={center.id}
              center={[center.latitude, center.longitude]}
              radius={Math.max(8, Math.min(30, Math.sqrt(totalTags) * 2))}
              pathOptions={{
                fillColor: getColor(threshold),
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
                  
                  <div className="space-y-1">
                    <div className="flex justify-between">
                      <span className="text-gray-600">Tags:</span>
                      <span className="font-medium">{totalTags}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">J+K STD:</span>
                      <span className="font-medium">{formatTime(avgJkStd)}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Natural Time:</span>
                      <span className="font-medium">
                        {formatTime(avgNatural)}
                        <span style={{
                          color: avgNatural <= avgJkStd ? '#10b981' : '#ef4444',
                          marginLeft: '4px'
                        }}>
                          ({avgNatural <= avgJkStd ? '-' : '+'}
                          {Math.abs(avgNatural - avgJkStd).toFixed(0)}min)
                        </span>
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Working Time:</span>
                      <span className="font-medium">
                        {formatTime(avgWorking)}
                        <span style={{
                          color: avgWorking <= avgJkStd ? '#10b981' : '#ef4444',
                          marginLeft: '4px'
                        }}>
                          ({avgWorking <= avgJkStd ? '-' : '+'}
                          {Math.abs(avgWorking - avgJkStd).toFixed(0)}min)
                        </span>
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">% STD:</span>
                      <span className="font-medium">{avgStdPct.toFixed(0)}%</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">% Real:</span>
                      <span className="font-medium">
                        {avgRealPct.toFixed(1)}%
                        <span style={{
                          color: avgRealPct >= avgStdPct ? '#10b981' : '#ef4444',
                          marginLeft: '4px'
                        }}>
                          ({avgRealPct >= avgStdPct ? '+' : ''}
                          {(avgRealPct - avgStdPct).toFixed(1)}%)
                        </span>
                      </span>
                    </div>
                    <div className="flex justify-between items-center mt-2 pt-2 border-t border-gray-200">
                      <span className="text-gray-600">Status:</span>
                      <span className="px-2 py-0.5 rounded text-xs font-semibold" style={{
                        backgroundColor: threshold === 'Compliant' ? '#dcfce7' : 
                                       threshold === 'Warning' ? '#fef3c7' : '#fee2e2',
                        color: threshold === 'Compliant' ? '#166534' : 
                               threshold === 'Warning' ? '#92400e' : '#991b1b'
                      }}>
                        {threshold === 'Compliant' ? '✓ Compliant' : 
                         threshold === 'Warning' ? '⚠ Warning' : '✗ Critical'}
                      </span>
                    </div>
                  </div>
                </div>
              </Tooltip>
            </CircleMarker>
          )
        })}
      </MapContainer>

      {/* Legend */}
      <div className="absolute bottom-4 right-4 bg-white p-3 rounded-lg shadow-lg border border-gray-200 text-xs">
        <div className="font-semibold mb-2">Segment Compliance</div>
        <div className="space-y-1">
          <div className="flex items-center gap-2">
            <div className="w-8 h-0.5 bg-green-500"></div>
            <span>Compliant</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-8 h-0.5 bg-yellow-500"></div>
            <span>Warning</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-8 h-0.5 bg-red-500"></div>
            <span>Critical</span>
          </div>
        </div>
      </div>
    </div>
  )
}
