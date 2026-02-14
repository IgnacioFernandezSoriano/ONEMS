import { useState } from 'react'
import { ChevronDown, ChevronRight, AlertCircle, Info } from 'lucide-react'
import { useNavigate } from 'react-router-dom'

interface SegmentDetail {
  from_city: string
  to_city: string
  from_center_name: string
  to_center_name: string
  from_center_id: string
  to_center_id: string
  segment_type: 'operational' | 'distribution'
  
  // Times in minutes
  avg_time_in_center_natural: number
  avg_time_in_center_working: number
  avg_transit_time_natural: number
  avg_transit_time_working: number
  avg_total_time_natural: number
  avg_total_time_working: number
  
  // SLA data
  expected_time_minutes: number  // J+K Std in minutes
  on_time_percentage_std: number  // % Std (e.g., 95)
  compliance_rate: number  // % Real
  warning_threshold: number  // e.g., 90
  critical_threshold: number  // e.g., 80
  
  tags_count: number
  calculation_mode: string
}

interface RoutePathData {
  id: string
  carrier_name: string
  product_name: string
  origin_city_name: string
  destination_city_name: string
  path_signature: string
  total_tags: number
  avg_natural_time_minutes: number
  avg_working_time_minutes: number
  compliance_rate: number
  segment_details: SegmentDetail[]
  
  // Aggregated SLA
  expected_time_minutes: number
  on_time_percentage_std: number
}

interface Props {
  routePaths: RoutePathData[]
}

export default function RoutePathTable({ routePaths }: Props) {
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set())
  const [hoveredSegment, setHoveredSegment] = useState<string | null>(null)
  const navigate = useNavigate()

  const toggleRow = (id: string) => {
    const newExpanded = new Set(expandedRows)
    if (newExpanded.has(id)) {
      newExpanded.delete(id)
    } else {
      newExpanded.add(id)
    }
    setExpandedRows(newExpanded)
  }

  // Convert minutes to J+K format
  const formatJK = (minutes: number) => {
    const days = (minutes / (24 * 60)).toFixed(3)
    return `J+${days}`
  }

  // Format time difference
  const formatTimeDiff = (actual: number, expected: number) => {
    const diff = actual - expected
    const sign = diff >= 0 ? '+' : ''
    const minutes = Math.abs(diff)
    
    if (minutes < 60) {
      return `${sign}${Math.round(minutes)}m`
    }
    const hours = Math.floor(minutes / 60)
    const mins = Math.round(minutes % 60)
    return `${sign}${hours}h ${mins}m`
  }

  // Format percentage difference
  const formatPercentDiff = (actual: number, expected: number) => {
    const diff = actual - expected
    const sign = diff >= 0 ? '+' : ''
    return `${sign}${diff.toFixed(1)}%`
  }

  // Get color for compliance
  const getComplianceColor = (rate: number, warning: number, critical: number) => {
    if (rate >= warning) return 'text-green-600 bg-green-50'
    if (rate >= critical) return 'text-yellow-600 bg-yellow-50'
    return 'text-red-600 bg-red-50'
  }

  // Get color for time difference
  const getTimeDiffColor = (actual: number, expected: number) => {
    const diff = actual - expected
    if (diff <= 0) return 'text-green-600'
    if (diff <= expected * 0.1) return 'text-yellow-600'
    return 'text-red-600'
  }

  const handleSegmentClick = (segment: SegmentDetail) => {
    const params = new URLSearchParams({
      from_center: segment.from_center_id,
      to_center: segment.to_center_id,
    })
    navigate(`/diagnosis/jk-performance-segments?${params}`)
  }

  return (
    <div className="p-6">
      <div className="mb-4">
        <h3 className="text-lg font-semibold text-gray-900 mb-2">Route Performance Details</h3>
        <p className="text-sm text-gray-600">
          Click rows to expand segments. Click segments to view J+K report.
        </p>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-semibold text-gray-600 uppercase w-8"></th>
              <th className="px-3 py-2 text-left text-xs font-semibold text-gray-600 uppercase">Carrier</th>
              <th className="px-3 py-2 text-left text-xs font-semibold text-gray-600 uppercase">Product</th>
              <th className="px-3 py-2 text-left text-xs font-semibold text-gray-600 uppercase">Origin</th>
              <th className="px-3 py-2 text-left text-xs font-semibold text-gray-600 uppercase">Destination</th>
              <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">
                <div className="flex items-center justify-end gap-1">
                  J+K Std
                  <Info className="w-3 h-3 text-gray-400" />
                </div>
              </th>
              <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">
                <div className="flex items-center justify-end gap-1">
                  Natural Time
                  <Info className="w-3 h-3 text-gray-400" />
                </div>
              </th>
              <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">
                <div className="flex items-center justify-end gap-1">
                  Working Time
                  <Info className="w-3 h-3 text-gray-400" />
                </div>
              </th>
              <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">% Std</th>
              <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">% Real</th>
              <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">Diff %</th>
              <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">Threshold</th>
              <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">Tags</th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {routePaths.map((path) => {
              const isExpanded = expandedRows.has(path.id)
              const timeDiffNatural = path.avg_natural_time_minutes - path.expected_time_minutes
              const timeDiffWorking = path.avg_working_time_minutes - path.expected_time_minutes
              const percentDiff = path.compliance_rate - path.on_time_percentage_std
              
              return (
                <>
                  {/* Main Row */}
                  <tr
                    key={path.id}
                    className="hover:bg-gray-50 cursor-pointer"
                    onClick={() => toggleRow(path.id)}
                  >
                    <td className="px-3 py-2">
                      {isExpanded ? (
                        <ChevronDown className="w-4 h-4 text-gray-600" />
                      ) : (
                        <ChevronRight className="w-4 h-4 text-gray-600" />
                      )}
                    </td>
                    <td className="px-3 py-2 font-medium text-gray-900">{path.carrier_name}</td>
                    <td className="px-3 py-2 text-gray-700">{path.product_name}</td>
                    <td className="px-3 py-2 text-gray-700">{path.origin_city_name}</td>
                    <td className="px-3 py-2 text-gray-700">{path.destination_city_name}</td>
                    <td className="px-3 py-2 text-right font-mono text-gray-900">
                      {formatJK(path.expected_time_minutes)}
                    </td>
                    <td className="px-3 py-2 text-right">
                      <div className="font-mono text-gray-900">{formatJK(path.avg_natural_time_minutes)}</div>
                      <div className={`text-xs font-semibold ${getTimeDiffColor(path.avg_natural_time_minutes, path.expected_time_minutes)}`}>
                        {formatTimeDiff(path.avg_natural_time_minutes, path.expected_time_minutes)}
                      </div>
                    </td>
                    <td className="px-3 py-2 text-right">
                      <div className="font-mono text-gray-900">{formatJK(path.avg_working_time_minutes)}</div>
                      <div className={`text-xs font-semibold ${getTimeDiffColor(path.avg_working_time_minutes, path.expected_time_minutes)}`}>
                        {formatTimeDiff(path.avg_working_time_minutes, path.expected_time_minutes)}
                      </div>
                    </td>
                    <td className="px-3 py-2 text-right font-semibold text-gray-700">
                      {path.on_time_percentage_std.toFixed(0)}%
                    </td>
                    <td className="px-3 py-2 text-right">
                      <span className={`px-2 py-1 rounded-full text-xs font-semibold ${getComplianceColor(path.compliance_rate, 90, 80)}`}>
                        {path.compliance_rate.toFixed(1)}%
                      </span>
                    </td>
                    <td className="px-3 py-2 text-right">
                      <span className={`font-semibold ${percentDiff >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                        {formatPercentDiff(path.compliance_rate, path.on_time_percentage_std)}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-right text-xs text-gray-600">
                      <div>W: 90%</div>
                      <div>C: 80%</div>
                    </td>
                    <td className="px-3 py-2 text-right font-semibold text-gray-900">
                      {path.total_tags.toLocaleString()}
                    </td>
                  </tr>

                  {/* Expanded Segments */}
                  {isExpanded && (
                    <tr>
                      <td colSpan={13} className="px-3 py-3 bg-gray-50">
                        <div className="space-y-2">
                          <div className="text-xs font-semibold text-gray-600 uppercase mb-2">Segment Details</div>
                          {path.segment_details.map((segment: SegmentDetail, idx: number) => {
                            const segmentKey = `${path.id}-${idx}`
                            const isHovered = hoveredSegment === segmentKey
                            const segTimeDiffNat = segment.avg_total_time_natural - segment.expected_time_minutes
                            const segTimeDiffWork = segment.avg_total_time_working - segment.expected_time_minutes
                            const segPercentDiff = segment.compliance_rate - segment.on_time_percentage_std
                            
                            return (
                              <div
                                key={idx}
                                className="bg-white border border-gray-200 rounded-lg p-3 hover:border-blue-400 hover:shadow-md transition-all cursor-pointer relative"
                                onMouseEnter={() => setHoveredSegment(segmentKey)}
                                onMouseLeave={() => setHoveredSegment(null)}
                                onClick={(e) => {
                                  e.stopPropagation()
                                  handleSegmentClick(segment)
                                }}
                              >
                                <div className="grid grid-cols-12 gap-2 items-center text-xs">
                                  <div className="col-span-2">
                                    <div className="font-semibold text-gray-900">{segment.from_city} → {segment.to_city}</div>
                                    <div className="text-xs text-gray-500">{segment.segment_type}</div>
                                  </div>
                                  <div className="col-span-1 text-right font-mono text-gray-900">
                                    {formatJK(segment.expected_time_minutes)}
                                  </div>
                                  <div className="col-span-2 text-right">
                                    <div className="font-mono text-gray-900">{formatJK(segment.avg_total_time_natural)}</div>
                                    <div className={`text-xs font-semibold ${getTimeDiffColor(segment.avg_total_time_natural, segment.expected_time_minutes)}`}>
                                      {formatTimeDiff(segment.avg_total_time_natural, segment.expected_time_minutes)}
                                    </div>
                                  </div>
                                  <div className="col-span-2 text-right">
                                    <div className="font-mono text-gray-900">{formatJK(segment.avg_total_time_working)}</div>
                                    <div className={`text-xs font-semibold ${getTimeDiffColor(segment.avg_total_time_working, segment.expected_time_minutes)}`}>
                                      {formatTimeDiff(segment.avg_total_time_working, segment.expected_time_minutes)}
                                    </div>
                                  </div>
                                  <div className="col-span-1 text-right font-semibold text-gray-700">
                                    {segment.on_time_percentage_std.toFixed(0)}%
                                  </div>
                                  <div className="col-span-1 text-right">
                                    <span className={`px-2 py-0.5 rounded-full text-xs font-semibold ${getComplianceColor(segment.compliance_rate, segment.warning_threshold, segment.critical_threshold)}`}>
                                      {segment.compliance_rate.toFixed(1)}%
                                    </span>
                                  </div>
                                  <div className="col-span-1 text-right">
                                    <span className={`font-semibold ${segPercentDiff >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                                      {formatPercentDiff(segment.compliance_rate, segment.on_time_percentage_std)}
                                    </span>
                                  </div>
                                  <div className="col-span-1 text-right text-xs text-gray-600">
                                    <div>W: {segment.warning_threshold}%</div>
                                    <div>C: {segment.critical_threshold}%</div>
                                  </div>
                                  <div className="col-span-1 text-right font-semibold text-gray-900">
                                    {segment.tags_count.toLocaleString()}
                                  </div>
                                </div>

                                {/* Hover Tooltip */}
                                {isHovered && (
                                  <div className="absolute top-full left-0 mt-2 bg-gray-900 text-white text-xs rounded-lg p-4 shadow-lg z-10 w-96">
                                    <div className="font-semibold mb-3 text-sm border-b border-gray-700 pb-2">
                                      {segment.from_center_name} → {segment.to_center_name}
                                    </div>
                                    <div className="space-y-2">
                                      <div className="grid grid-cols-2 gap-2">
                                        <div>
                                          <div className="text-gray-400 mb-1">Segment Type</div>
                                          <div className="font-semibold">{segment.segment_type}</div>
                                        </div>
                                        <div>
                                          <div className="text-gray-400 mb-1">Calculation Mode</div>
                                          <div className="font-semibold">{segment.calculation_mode}</div>
                                        </div>
                                      </div>
                                      
                                      {segment.segment_type === 'operational' && (
                                        <div>
                                          <div className="text-gray-400 mb-1">Time in Center</div>
                                          <div className="font-semibold">
                                            Natural: {formatJK(segment.avg_time_in_center_natural)} | 
                                            Working: {formatJK(segment.avg_time_in_center_working)}
                                          </div>
                                        </div>
                                      )}
                                      
                                      {segment.segment_type === 'distribution' && (
                                        <div>
                                          <div className="text-gray-400 mb-1">Transit Time</div>
                                          <div className="font-semibold">
                                            Natural: {formatJK(segment.avg_transit_time_natural)} | 
                                            Working: {formatJK(segment.avg_transit_time_working)}
                                          </div>
                                        </div>
                                      )}
                                      
                                      <div>
                                        <div className="text-gray-400 mb-1">SLA Performance</div>
                                        <div className="font-semibold">
                                          Target: {segment.on_time_percentage_std}% | 
                                          Actual: {segment.compliance_rate.toFixed(1)}% | 
                                          Diff: {formatPercentDiff(segment.compliance_rate, segment.on_time_percentage_std)}
                                        </div>
                                      </div>
                                      
                                      <div>
                                        <div className="text-gray-400 mb-1">Tags Processed</div>
                                        <div className="font-semibold">{segment.tags_count.toLocaleString()}</div>
                                      </div>
                                      
                                      <div className="mt-3 pt-3 border-t border-gray-700 text-blue-300">
                                        Click to view detailed J+K report →
                                      </div>
                                    </div>
                                  </div>
                                )}
                              </div>
                            )
                          })}
                        </div>
                      </td>
                    </tr>
                  )}
                </>
              )
            })}
          </tbody>
        </table>

        {routePaths.length === 0 && (
          <div className="text-center py-12 text-gray-500">
            <AlertCircle className="w-12 h-12 mx-auto mb-4 text-gray-300" />
            <p>No route paths found</p>
          </div>
        )}
      </div>
    </div>
  )
}
