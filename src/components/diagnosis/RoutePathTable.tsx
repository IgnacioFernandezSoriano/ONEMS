import { useState } from 'react'
import { ChevronDown, ChevronRight, Clock, TrendingUp, AlertCircle } from 'lucide-react'
import { useNavigate } from 'react-router-dom'

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
  segment_details: any[]
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

  const formatTime = (minutes: number) => {
    if (minutes < 60) return `${Math.round(minutes)}m`
    const hours = Math.floor(minutes / 60)
    const mins = Math.round(minutes % 60)
    return `${hours}h ${mins}m`
  }

  const getComplianceColor = (rate: number) => {
    if (rate >= 90) return 'text-green-600 bg-green-50'
    if (rate >= 70) return 'text-yellow-600 bg-yellow-50'
    return 'text-red-600 bg-red-50'
  }

  const handleSegmentClick = (segment: any) => {
    // Navigate to J+K report for this segment
    const params = new URLSearchParams({
      from_center: segment.from_center_id,
      to_center: segment.to_center_id,
      // Add more filters as needed
    })
    navigate(`/diagnosis/jk-performance-segments?${params}`)
  }

  return (
    <div className="p-6">
      <div className="mb-4">
        <h3 className="text-lg font-semibold text-gray-900 mb-2">Route Details</h3>
        <p className="text-sm text-gray-600">
          Click on rows to expand segments. Hover over segments for details. Click segments to view J+K report.
        </p>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase tracking-wider w-8"></th>
              <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase tracking-wider">
                Route
              </th>
              <th className="px-4 py-3 text-right text-xs font-semibold text-gray-600 uppercase tracking-wider">
                Tags
              </th>
              <th className="px-4 py-3 text-right text-xs font-semibold text-gray-600 uppercase tracking-wider">
                Natural Time
              </th>
              <th className="px-4 py-3 text-right text-xs font-semibold text-gray-600 uppercase tracking-wider">
                Working Time
              </th>
              <th className="px-4 py-3 text-right text-xs font-semibold text-gray-600 uppercase tracking-wider">
                SLA Compliance
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {routePaths.map((path) => {
              const isExpanded = expandedRows.has(path.id)
              
              return (
                <>
                  {/* Main Row */}
                  <tr
                    key={path.id}
                    className="hover:bg-gray-50 cursor-pointer"
                    onClick={() => toggleRow(path.id)}
                  >
                    <td className="px-4 py-3">
                      {isExpanded ? (
                        <ChevronDown className="w-4 h-4 text-gray-600" />
                      ) : (
                        <ChevronRight className="w-4 h-4 text-gray-600" />
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <div className="font-medium text-gray-900">{path.path_signature}</div>
                      <div className="text-sm text-gray-500">
                        {path.segment_details.length} segment{path.segment_details.length !== 1 ? 's' : ''}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-right font-semibold text-gray-900">
                      {path.total_tags.toLocaleString()}
                    </td>
                    <td className="px-4 py-3 text-right text-gray-700">
                      {formatTime(path.avg_natural_time_minutes)}
                    </td>
                    <td className="px-4 py-3 text-right text-gray-700">
                      {formatTime(path.avg_working_time_minutes)}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <span className={`px-2 py-1 rounded-full text-xs font-semibold ${getComplianceColor(path.compliance_rate)}`}>
                        {path.compliance_rate.toFixed(1)}%
                      </span>
                    </td>
                  </tr>

                  {/* Expanded Segments */}
                  {isExpanded && (
                    <tr>
                      <td colSpan={6} className="px-4 py-4 bg-gray-50">
                        <div className="space-y-2">
                          {path.segment_details.map((segment: any, idx: number) => {
                            const segmentKey = `${path.id}-${idx}`
                            const isHovered = hoveredSegment === segmentKey
                            
                            return (
                              <div
                                key={idx}
                                className="bg-white border border-gray-200 rounded-lg p-4 hover:border-blue-400 hover:shadow-md transition-all cursor-pointer relative"
                                onMouseEnter={() => setHoveredSegment(segmentKey)}
                                onMouseLeave={() => setHoveredSegment(null)}
                                onClick={(e) => {
                                  e.stopPropagation()
                                  handleSegmentClick(segment)
                                }}
                              >
                                <div className="flex items-center justify-between">
                                  <div className="flex-1">
                                    <div className="font-semibold text-gray-900 mb-1">
                                      {segment.from_city} → {segment.to_city}
                                    </div>
                                    <div className="text-sm text-gray-600">
                                      {segment.from_center_name} → {segment.to_center_name}
                                    </div>
                                  </div>

                                  <div className="flex items-center gap-6 text-sm">
                                    <div className="text-right">
                                      <div className="text-gray-600 mb-1">In Center</div>
                                      <div className="font-semibold text-gray-900">
                                        {formatTime(segment.avg_time_in_center_natural || 0)}
                                      </div>
                                      <div className="text-xs text-gray-500">
                                        ({formatTime(segment.avg_time_in_center_working || 0)} working)
                                      </div>
                                    </div>

                                    <div className="text-right">
                                      <div className="text-gray-600 mb-1">Transit</div>
                                      <div className="font-semibold text-gray-900">
                                        {formatTime(segment.avg_transit_time_natural || 0)}
                                      </div>
                                      <div className="text-xs text-gray-500">
                                        ({formatTime(segment.avg_transit_time_working || 0)} working)
                                      </div>
                                    </div>

                                    <div className="text-right">
                                      <div className="text-gray-600 mb-1">Total</div>
                                      <div className="font-semibold text-gray-900">
                                        {formatTime(segment.avg_total_time_natural || 0)}
                                      </div>
                                      <div className="text-xs text-gray-500">
                                        SLA: {formatTime(segment.expected_time_minutes || 0)}
                                      </div>
                                    </div>

                                    <div className="text-right">
                                      <div className="text-gray-600 mb-1">Compliance</div>
                                      <div className={`font-semibold ${
                                        segment.compliance_rate >= 90 ? 'text-green-600' :
                                        segment.compliance_rate >= 70 ? 'text-yellow-600' :
                                        'text-red-600'
                                      }`}>
                                        {segment.compliance_rate?.toFixed(1) || 0}%
                                      </div>
                                    </div>

                                    <div className="text-right">
                                      <div className="text-gray-600 mb-1">Tags</div>
                                      <div className="font-semibold text-gray-900">
                                        {segment.tags_count?.toLocaleString() || 0}
                                      </div>
                                    </div>
                                  </div>
                                </div>

                                {/* Hover Tooltip */}
                                {isHovered && (
                                  <div className="absolute top-full left-0 mt-2 bg-gray-900 text-white text-xs rounded-lg p-3 shadow-lg z-10 w-64">
                                    <div className="font-semibold mb-2">Segment Details</div>
                                    <div className="space-y-1">
                                      <div className="flex justify-between">
                                        <span>Calculation Mode:</span>
                                        <span className="font-semibold">{segment.calculation_mode || 'natural_days'}</span>
                                      </div>
                                      <div className="flex justify-between">
                                        <span>Avg Delay:</span>
                                        <span className="font-semibold">
                                          {formatTime((segment.avg_total_time_natural || 0) - (segment.expected_time_minutes || 0))}
                                        </span>
                                      </div>
                                      <div className="mt-2 pt-2 border-t border-gray-700 text-blue-300">
                                        Click to view J+K report →
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
