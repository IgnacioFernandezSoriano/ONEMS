import React from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'

interface SegmentData {
  segment_name: string
  segment_type: 'center' | 'transit'
  from_center_id: string | null
  to_center_id: string | null
  jk_std_minutes: number
  natural_time_minutes: number
  working_time_minutes: number
  std_percentage: number
  real_percentage: number
  diff_percentage: number
  threshold: 'Compliant' | 'Warning' | 'Critical'
  warning_threshold: number
  critical_threshold: number
  order: number
}

interface SegmentTotals {
  jk_std_minutes: number
  natural_time_minutes: number
  working_time_minutes: number
  std_percentage: number
  real_percentage: number
}

interface SegmentTableProps {
  pathId: string
  pathSignature: string
  accountId: string
  carrierId: string
  carrierName: string
  productId: string
  productName: string
  originCity: string
  destinationCity: string
  onSegmentCountChange?: (count: number) => void
  onSegmentsCalculated?: (totals: SegmentTotals) => void
}

export default function SegmentTable({ pathId, pathSignature, accountId, carrierId, carrierName, productId, productName, originCity, destinationCity, onSegmentCountChange, onSegmentsCalculated }: SegmentTableProps) {
  const navigate = useNavigate()
  const [segments, setSegments] = React.useState<SegmentData[]>([])
  const [loading, setLoading] = React.useState(true)
  const [error, setError] = React.useState<string | null>(null)

  React.useEffect(() => {
    loadSegments()
  }, [pathId, pathSignature])

  const loadSegments = async () => {
    setLoading(true)
    setError(null)
    
    try {
      // 1. Get all journey_segments for this path
      const { data: journeySegments, error: segmentsError } = await supabase
        .from('journey_segments')
        .select('*')
        .eq('account_id', accountId)
        .eq('carrier_id', carrierId)
        .eq('product_id', productId)
        .eq('origin_city_name', originCity)
        .eq('destination_city_name', destinationCity)
        .order('entry_timestamp')

      if (segmentsError) throw segmentsError

      // Load postal centers for names
      const { data: centers } = await supabase
        .from('postal_centers')
        .select('id, name')
        .eq('account_id', accountId)

      const centerMap = new Map(centers?.map(c => [c.id, c.name]) || [])

      // 2. Get SLAs
      const { data: slas, error: slasError } = await supabase
        .from('slas')
        .select('*')
        .eq('account_id', accountId)
        .eq('is_active', true)

      if (slasError) throw slasError

      // 3. Group segments by from_postal_center_id -> to_postal_center_id
      const segmentGroups = new Map<string, any[]>()
      
      journeySegments?.forEach(seg => {
        // Operational segments: group by postal_center_id
        // Distribution segments: group by from_postal_center_id|to_postal_center_id
        const key = seg.segment_type === 'operational'
          ? `operational|${seg.postal_center_id}`
          : `distribution|${seg.from_postal_center_id}|${seg.to_postal_center_id}`
        if (!segmentGroups.has(key)) {
          segmentGroups.set(key, [])
        }
        segmentGroups.get(key)!.push(seg)
      })
      
      const orderedSegments = Array.from(segmentGroups.values())

      // 4. Build segment data array
      const segmentDataArray: SegmentData[] = []
      let order = 0

      orderedSegments.forEach((segs, segIndex) => {
        const firstSeg = segs[0]
        const totalTags = segs.length

        // Calculate averages
        const avgNaturalCenter = segs.reduce((sum, s) => sum + (s.natural_time_in_center_minutes || 0), 0) / totalTags
        const avgNaturalTransit = segs.reduce((sum, s) => sum + (s.natural_transit_time_minutes || 0), 0) / totalTags
        const avgWorkingCenter = segs.reduce((sum, s) => sum + (s.working_time_in_center_minutes || 0), 0) / totalTags
        const avgWorkingTransit = segs.reduce((sum, s) => sum + (s.working_transit_time_minutes || 0), 0) / totalTags

        // Find SLAs
        const centerSLA = slas?.find(sla => 
          sla.sla_type === 'operational' && 
          sla.postal_center_id === (firstSeg.segment_type === 'operational' 
            ? firstSeg.postal_center_id 
            : firstSeg.from_postal_center_id)
        )
        
        const transitSLA = slas?.find(sla => 
          sla.sla_type === 'distribution' && 
          sla.from_postal_center_id === firstSeg.from_postal_center_id &&
          sla.to_postal_center_id === firstSeg.to_postal_center_id
        )

        const fromCenterName = firstSeg.segment_type === 'operational'
          ? (centerMap.get(firstSeg.postal_center_id) || firstSeg.postal_center_name_snapshot)
          : (centerMap.get(firstSeg.from_postal_center_id) || firstSeg.from_postal_center_city)
        const toCenterName = centerMap.get(firstSeg.to_postal_center_id) || firstSeg.to_postal_center_city

        // Center segment - only for operational segments
        if (firstSeg.segment_type === 'operational' && (avgNaturalCenter > 0 || centerSLA)) {
          const jkStd = centerSLA?.expected_time_minutes || 0
          const stdPercentage = centerSLA?.on_time_percentage || 95
          const warningThreshold = centerSLA?.warning_threshold || 90
          const criticalThreshold = centerSLA?.critical_threshold || 80
          
          // Calculate % Real: tags that met the SLA
          const tagsOnTime = segs.filter(s => (s.natural_time_in_center_minutes || 0) <= jkStd).length
          const realPercentage = totalTags > 0 ? (tagsOnTime / totalTags) * 100 : 0
          const diffPercentage = realPercentage - stdPercentage

          const threshold = realPercentage >= warningThreshold ? 'Compliant' :
                           realPercentage >= criticalThreshold ? 'Warning' : 'Critical'

          segmentDataArray.push({
            segment_name: `${fromCenterName} (Center)`,
            segment_type: 'center',
            from_center_id: firstSeg.segment_type === 'operational' ? firstSeg.postal_center_id : firstSeg.from_postal_center_id,
            to_center_id: null,
            jk_std_minutes: jkStd,
            natural_time_minutes: Math.round(avgNaturalCenter),
            working_time_minutes: Math.round(avgWorkingCenter),
            std_percentage: stdPercentage,
            real_percentage: Math.round(realPercentage),
            diff_percentage: diffPercentage,
            threshold,
            warning_threshold: warningThreshold,
            critical_threshold: criticalThreshold,
            order: order++
          })
        }

        // Transit segment - only for distribution segments
        if (firstSeg.segment_type === 'distribution' && (avgNaturalTransit > 0 || transitSLA)) {
          const jkStd = transitSLA?.expected_time_minutes || 0
          const stdPercentage = transitSLA?.on_time_percentage || 95
          const warningThreshold = transitSLA?.warning_threshold || 90
          const criticalThreshold = transitSLA?.critical_threshold || 80
          
          const tagsOnTime = segs.filter(s => (s.natural_transit_time_minutes || 0) <= jkStd).length
          const realPercentage = totalTags > 0 ? (tagsOnTime / totalTags) * 100 : 0
          const diffPercentage = realPercentage - stdPercentage

          const threshold = realPercentage >= warningThreshold ? 'Compliant' :
                           realPercentage >= criticalThreshold ? 'Warning' : 'Critical'

          segmentDataArray.push({
            segment_name: `${fromCenterName} → ${toCenterName}`,
            segment_type: 'transit',
            from_center_id: firstSeg.from_postal_center_id,
            to_center_id: firstSeg.to_postal_center_id,
            jk_std_minutes: jkStd,
            natural_time_minutes: Math.round(avgNaturalTransit),
            working_time_minutes: Math.round(avgWorkingTransit),
            std_percentage: stdPercentage,
            real_percentage: Math.round(realPercentage),
            diff_percentage: diffPercentage,
            threshold,
            warning_threshold: warningThreshold,
            critical_threshold: criticalThreshold,
            order: order++
          })
        }

        // No need to add destination center - all operational centers are already in journey_segments
      })
      
      setSegments(segmentDataArray)
      onSegmentCountChange?.(segmentDataArray.length)
      
      // Calculate totals for header
      if (segmentDataArray.length > 0) {
        const totalJkStd = segmentDataArray.reduce((sum, seg) => sum + seg.jk_std_minutes, 0)
        const totalNaturalTime = segmentDataArray.reduce((sum, seg) => sum + seg.natural_time_minutes, 0)
        const totalWorkingTime = segmentDataArray.reduce((sum, seg) => sum + seg.working_time_minutes, 0)
        
        // Average % STD (weighted by segment count)
        const avgStdPercentage = segmentDataArray.reduce((sum, seg) => sum + seg.std_percentage, 0) / segmentDataArray.length
        
        // Average % REAL (excluding segments with 0 or no data)
        const segmentsWithReal = segmentDataArray.filter(seg => seg.real_percentage > 0)
        const avgRealPercentage = segmentsWithReal.length > 0
          ? segmentsWithReal.reduce((sum, seg) => sum + seg.real_percentage, 0) / segmentsWithReal.length
          : 0
        
        // Notify parent with calculated totals
        if (onSegmentsCalculated) {
          onSegmentsCalculated({
            jk_std_minutes: totalJkStd,
            natural_time_minutes: totalNaturalTime,
            working_time_minutes: totalWorkingTime,
            std_percentage: avgStdPercentage,
            real_percentage: avgRealPercentage
          })
        }
      }
    } catch (err: any) {
      console.error('Error loading segments:', err)
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const formatTime = (minutes: number) => {
    if (minutes === 0) return '-'
    
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

  const getThresholdColor = (threshold: string) => {
    switch (threshold) {
      case 'Compliant':
        return 'bg-green-100 text-green-800'
      case 'Warning':
        return 'bg-yellow-100 text-yellow-800'
      case 'Critical':
        return 'bg-red-100 text-red-800'
      default:
        return 'bg-gray-100 text-gray-800'
    }
  }

  const handleSegmentClick = (segment: SegmentData) => {
    // Build URL params for J+K Performance
    const params = new URLSearchParams()
    params.set('carrier_id', carrierId)
    params.set('product_id', productId)
    
    if (segment.segment_type === 'center' && segment.from_center_id) {
      params.set('from_center_id', segment.from_center_id)
      params.set('segment_type', 'operational')
    } else if (segment.segment_type === 'transit' && segment.from_center_id && segment.to_center_id) {
      params.set('from_center_id', segment.from_center_id)
      params.set('to_center_id', segment.to_center_id)
      params.set('segment_type', 'distribution')
    }
    
    // Open in new tab
    window.open(`/diagnosis/jk-performance-segments?${params.toString()}`, '_blank')
  }

  if (loading) {
    return <div className="text-center py-4 text-gray-500">Loading segments...</div>
  }

  if (error) {
    return <div className="text-center py-4 text-red-500">Error: {error}</div>
  }

  if (segments.length === 0) {
    return <div className="text-center py-4 text-gray-500">No segments found</div>
  }

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-100">
          <tr>
            <th className="px-3 py-2 text-left text-xs font-semibold text-gray-600 uppercase">Segment</th>
            <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">J+K STD</th>
            <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">Natural Time</th>
            <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">Working Time</th>
            <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">% STD</th>
            <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">% Real</th>
            <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">Diff %</th>
            <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">Threshold</th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {segments.map((segment, index) => (
            <tr 
              key={index} 
              onClick={() => handleSegmentClick(segment)}
              className="hover:bg-blue-50 cursor-pointer transition-colors"
            >
              <td className="px-3 py-2 text-sm font-medium text-gray-900">
                {segment.segment_name}
                <span className="ml-2 text-xs text-gray-500">
                  ({segment.segment_type === 'center' ? 'Center' : 'Transit'})
                </span>
              </td>
              <td className="px-3 py-2 text-right text-sm font-mono text-gray-900">
                {formatTime(segment.jk_std_minutes)}
              </td>
              <td className="px-3 py-2 text-right text-sm font-mono text-gray-900">
                {formatTime(segment.natural_time_minutes)}
              </td>
              <td className="px-3 py-2 text-right text-sm font-mono text-gray-900">
                {formatTime(segment.working_time_minutes)}
              </td>
              <td className="px-3 py-2 text-right text-sm font-semibold text-gray-700">
                {segment.std_percentage}%
              </td>
              <td className="px-3 py-2 text-right">
                {segment.real_percentage !== null && segment.real_percentage !== undefined ? (
                  <span className={`px-2 py-1 rounded-full text-xs font-semibold ${
                    segment.real_percentage >= segment.warning_threshold 
                      ? 'bg-green-100 text-green-800' 
                      : segment.real_percentage >= segment.critical_threshold
                      ? 'bg-yellow-100 text-yellow-800'
                      : 'bg-red-100 text-red-800'
                  }`}>
                    {segment.real_percentage}%
                  </span>
                ) : (
                  <span className="text-gray-400">-</span>
                )}
              </td>
              <td className="px-3 py-2 text-right">
                {segment.real_percentage !== null && segment.real_percentage !== undefined ? (
                  <span className={`font-semibold ${
                    segment.diff_percentage >= 0 ? 'text-green-600' : 'text-red-600'
                  }`}>
                    {segment.diff_percentage > 0 ? '+' : ''}{segment.diff_percentage.toFixed(1)}%
                  </span>
                ) : (
                  <span className="text-gray-400">-</span>
                )}
              </td>
              <td className="px-3 py-2 text-right">
                {segment.real_percentage !== null && segment.real_percentage !== undefined ? (
                  <span className={`px-2 py-0.5 rounded text-xs font-semibold ${getThresholdColor(segment.threshold)}`}>
                    {segment.threshold}
                  </span>
                ) : (
                  <span className="text-gray-400">-</span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
