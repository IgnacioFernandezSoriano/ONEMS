import { useState } from 'react'

interface SegmentDetail {
  from_city: string
  to_city: string
  from_center_name: string
  to_center_name: string
  from_center_id: string
  to_center_id: string
  segment_type: 'operational' | 'distribution'
  avg_time_in_center_natural: number
  avg_time_in_center_working: number
  avg_transit_time_natural: number
  avg_transit_time_working: number
  avg_total_time_natural: number
  avg_total_time_working: number
  expected_time_minutes: number
  on_time_percentage_std: number
  compliance_rate: number
  warning_threshold: number
  critical_threshold: number
  tags_count: number
  calculation_mode: string
}

interface Props {
  segments: SegmentDetail[]
  postalCenters: any[]
  onSegmentClick: (segment: SegmentDetail) => void
}

export default function SegmentFlowDiagram({ segments, postalCenters, onSegmentClick }: Props) {
  // Create center lookup map
  const centerMap = new Map(postalCenters.map(c => [c.id, c]))
  const [hoveredIndex, setHoveredIndex] = useState<number | null>(null)

  const formatJK = (minutes: number) => {
    const days = minutes / (24 * 60)
    if (days < 1) return `${days.toFixed(2)} days`
    else if (days === Math.floor(days)) return `${Math.floor(days)} days`
    else return `${days.toFixed(2)} days`
  }

  const formatTimeDiff = (actual: number, expected: number) => {
    const diff = actual - expected
    const sign = diff >= 0 ? '+' : ''
    return `${sign}${formatJK(Math.abs(diff))}`
  }

  const getStatusColor = (compliance: number) => {
    if (compliance >= 90) return 'bg-green-500'
    if (compliance >= 80) return 'bg-yellow-500'
    return 'bg-red-500'
  }

  const getStatusBadge = (compliance: number) => {
    if (compliance >= 90) return { label: 'Compliant', bg: 'bg-green-100', text: 'text-green-800' }
    if (compliance >= 80) return { label: 'Warning', bg: 'bg-yellow-100', text: 'text-yellow-800' }
    return { label: 'Critical', bg: 'bg-red-100', text: 'text-red-800' }
  }

  // Get origin and destination info
  const firstSegment = segments[0]
  const lastSegment = segments[segments.length - 1]
  
  const originCity = firstSegment?.from_city || ''
  const originCenterName = firstSegment?.from_center_name || centerMap.get(firstSegment?.from_center_id)?.name || 'Unknown Center'
  
  const destCity = lastSegment?.to_city || lastSegment?.from_city || ''
  const destCenterId = lastSegment?.to_center_id || lastSegment?.from_center_id
  const destCenterName = lastSegment?.to_center_name || centerMap.get(destCenterId)?.name || 'Unknown Center'

  return (
    <div className="relative p-4 bg-white">
      {/* Title */}
      <div className="text-xs font-semibold text-gray-500 mb-3 uppercase tracking-wide">
        Segment Flow
      </div>
      
      <div className="flex items-center gap-2 overflow-x-auto pb-2">
        {/* ORIGIN CIRCLE */}
        <div className="flex-shrink-0 flex flex-col items-center">
          <div className="text-xs font-semibold text-blue-600 mb-1">Origin:</div>
          <div className="w-20 h-20 rounded-full border-2 border-blue-400 bg-blue-50 flex flex-col items-center justify-center">
            <div className="text-[10px] font-semibold text-gray-900 text-center px-1">
              {originCity}
            </div>
          </div>
        </div>

        {/* Arrow after origin */}
        <div className="px-2 text-gray-400 flex-shrink-0">→</div>

        {/* SEGMENTS */}
        {segments.map((segment, idx) => {
          const isHovered = hoveredIndex === idx
          const status = getStatusBadge(segment.compliance_rate)
          const centerName = segment.from_center_name || centerMap.get(segment.from_center_id)?.name || 'Unknown Center'
          
          return (
            <div key={idx} className="flex items-center flex-shrink-0">
              {/* Segment Box */}
              <div
                className={`relative group cursor-pointer transition-all ${
                  isHovered ? 'scale-105 z-10' : ''
                }`}
                onMouseEnter={() => setHoveredIndex(idx)}
                onMouseLeave={() => setHoveredIndex(null)}
                onClick={() => onSegmentClick(segment)}
              >
                {segment.segment_type === 'operational' ? (
                  /* Operational Box */
                  <div className={`px-3 py-2 rounded border-2 ${
                    isHovered ? 'border-blue-500 shadow-lg' : 'border-gray-300'
                  }`}>
                    <div className="text-xs font-semibold text-gray-900 whitespace-nowrap">
                      {centerName}
                    </div>
                    <div className="text-[10px] text-gray-500">{segment.from_city}</div>
                    <div className="text-[10px] text-gray-400">Operational</div>
                    <div className={`w-2 h-2 rounded-full ${getStatusColor(segment.compliance_rate)} mt-1`}></div>
                  </div>
                ) : (
                  /* Distribution Line */
                  <div className={`px-3 py-1 rounded-full border ${
                    isHovered ? 'border-blue-500 bg-blue-50 shadow-lg' : 'border-gray-300 bg-gray-50'
                  }`}>
                    <div className="text-xs font-semibold text-gray-700 whitespace-nowrap">
                      {segment.from_city} → {segment.to_city}
                    </div>
                    <div className={`w-2 h-2 rounded-full ${getStatusColor(segment.compliance_rate)} mx-auto mt-1`}></div>
                  </div>
                )}

                {/* Hover Tooltip */}
                {isHovered && (
                  <div className={`absolute top-full mt-2 z-20 bg-white border border-gray-300 rounded-lg shadow-xl p-3 w-72 ${
                    idx === 0 ? 'left-0' : idx === segments.length - 1 ? 'right-0' : 'left-1/2 transform -translate-x-1/2'
                  }`}>
                    <div className="text-xs space-y-1">
                      <div className="font-semibold text-gray-900 mb-2 pb-1 border-b">
                        {segment.segment_type === 'operational' 
                          ? centerName
                          : `${segment.from_city} → ${segment.to_city}`
                        }
                      </div>
                      
                      <div className="flex justify-between">
                        <span className="text-gray-600">Tags:</span>
                        <span className="font-medium">{segment.tags_count}</span>
                      </div>
                      
                      <div className="flex justify-between">
                        <span className="text-gray-600">J+K Std:</span>
                        <span className="font-medium">{formatJK(segment.expected_time_minutes)}</span>
                      </div>
                      
                      <div className="flex justify-between">
                        <span className="text-gray-600">J+K Natural:</span>
                        <span className="font-medium">
                          {formatJK(segment.avg_total_time_natural)}
                          <span className={segment.avg_total_time_natural <= segment.expected_time_minutes ? 'text-green-600' : 'text-red-600'}>
                            {' '}({formatTimeDiff(segment.avg_total_time_natural, segment.expected_time_minutes)})
                          </span>
                        </span>
                      </div>
                      
                      <div className="flex justify-between">
                        <span className="text-gray-600">J+K Working:</span>
                        <span className="font-medium">
                          {formatJK(segment.avg_total_time_working)}
                          <span className={segment.avg_total_time_working <= segment.expected_time_minutes ? 'text-green-600' : 'text-red-600'}>
                            {' '}({formatTimeDiff(segment.avg_total_time_working, segment.expected_time_minutes)})
                          </span>
                        </span>
                      </div>
                      
                      <div className="flex justify-between">
                        <span className="text-gray-600">% Std:</span>
                        <span className="font-medium">{segment.on_time_percentage_std.toFixed(0)}%</span>
                      </div>
                      
                      <div className="flex justify-between">
                        <span className="text-gray-600">% Real:</span>
                        <span className="font-medium">
                          {segment.compliance_rate.toFixed(1)}%
                          <span className={segment.compliance_rate >= segment.on_time_percentage_std ? 'text-green-600' : 'text-red-600'}>
                            {' '}({segment.compliance_rate >= segment.on_time_percentage_std ? '+' : ''}
                            {(segment.compliance_rate - segment.on_time_percentage_std).toFixed(1)}%)
                          </span>
                        </span>
                      </div>
                      
                      <div className="flex justify-between items-center mt-2 pt-2 border-t">
                        <span className="text-gray-600">Status:</span>
                        <span className={`px-2 py-0.5 rounded text-xs font-semibold ${status.bg} ${status.text}`}>
                          {status.label}
                        </span>
                      </div>
                    </div>
                  </div>
                )}
              </div>

              {/* Arrow between segments */}
              {idx < segments.length - 1 && (
                <div className="px-2 text-gray-400 flex-shrink-0">
                  →
                </div>
              )}
            </div>
          )
        })}

        {/* Arrow before destination */}
        <div className="px-2 text-gray-400 flex-shrink-0">→</div>

        {/* DESTINATION CIRCLE */}
        <div className="flex-shrink-0 flex flex-col items-center">
          <div className="text-xs font-semibold text-blue-600 mb-1">Destination:</div>
          <div className="w-20 h-20 rounded-full border-2 border-blue-400 bg-blue-50 flex flex-col items-center justify-center">
            <div className="text-[10px] font-semibold text-gray-900 text-center px-1">
              {destCity}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
