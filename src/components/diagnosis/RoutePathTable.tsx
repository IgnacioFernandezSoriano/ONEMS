import { useState } from 'react'
import { ChevronDown, ChevronRight, AlertCircle, Info } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import SegmentTable from './SegmentTable'

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
  carrier_id: string
  carrier_name: string
  product_id: string
  product_name: string
  origin_city_name: string
  destination_city_name: string
  path_signature: string
  total_tags: number
  avg_natural_time_minutes: number
  avg_working_time_minutes: number
  compliance_rate: number
  percent_real: number
  segment_details: SegmentDetail[]
  
  // Aggregated SLA
  expected_time_minutes: number
}

interface Props {
  routePaths: RoutePathData[]
  postalCenters: any[]
}

export default function RoutePathTable({ routePaths, postalCenters }: Props) {
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set())
  const [hoveredSegment, setHoveredSegment] = useState<string | null>(null)
  const [segmentCounts, setSegmentCounts] = useState<Record<string, number>>({})
  const [segmentTotals, setSegmentTotals] = useState<Record<string, any>>({})
  const navigate = useNavigate()

  // Calculate weighted average on_time_percentage_std from segment_details
  const calculateWeightedStd = (segmentDetails: SegmentDetail[]) => {
    if (!segmentDetails || segmentDetails.length === 0) return 95
    
    const totalTags = segmentDetails.reduce((sum, seg) => sum + (seg.tags_count || 0), 0)
    if (totalTags === 0) return 95
    
    const weightedSum = segmentDetails.reduce((sum, seg) => {
      return sum + (seg.on_time_percentage_std || 95) * (seg.tags_count || 0)
    }, 0)
    
    return weightedSum / totalTags
  }

  const toggleRow = (id: string) => {
    const newExpanded = new Set(expandedRows)
    if (newExpanded.has(id)) {
      newExpanded.delete(id)
    } else {
      newExpanded.add(id)
    }
    setExpandedRows(newExpanded)
  }

  // Convert minutes to J+K format (in days)
  const formatJK = (minutes: number) => {
    const days = minutes / (24 * 60)
    
    if (days < 1) {
      // Less than 1 day: 2 decimals
      return `${days.toFixed(2)} days`
    } else if (days === Math.floor(days)) {
      // Complete day: no decimals
      return `${Math.floor(days)} days`
    } else {
      // Partial day: 2 decimals
      return `${days.toFixed(2)} days`
    }
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
              <th className="px-3 py-2 text-right text-xs font-semibold text-gray-600 uppercase">Seg</th>
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
              const totals = segmentTotals[path.id]
              
              // Use calculated totals from segments if available, otherwise use path data
              const jkStd = totals?.jk_std_minutes ?? path.expected_time_minutes
              const naturalTime = totals?.natural_time_minutes ?? path.avg_natural_time_minutes
              const workingTime = totals?.working_time_minutes ?? path.avg_working_time_minutes
              const stdPercentage = totals?.std_percentage ?? calculateWeightedStd(path.segment_details)
              const realPercentage = totals?.real_percentage ?? path.percent_real
              
              const timeDiffNatural = naturalTime - jkStd
              const timeDiffWorking = workingTime - jkStd
              const percentDiff = realPercentage - stdPercentage
              
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
                    <td className="px-3 py-2 text-right font-semibold text-gray-700">
                      {segmentCounts[path.id] || (path.path_signature.split(' | ').length * 2 + 1)}
                    </td>
                    <td className="px-3 py-2 text-right font-mono text-gray-900">
                      {formatJK(jkStd)}
                    </td>
                    <td className="px-3 py-2 text-right">
                      <div className="font-mono text-gray-900">{formatJK(naturalTime)}</div>
                      <div className={`text-xs font-semibold ${getTimeDiffColor(naturalTime, jkStd)}`}>
                        {formatTimeDiff(naturalTime, jkStd)}
                      </div>
                    </td>
                    <td className="px-3 py-2 text-right">
                      <div className="font-mono text-gray-900">{formatJK(workingTime)}</div>
                      <div className={`text-xs font-semibold ${getTimeDiffColor(workingTime, jkStd)}`}>
                        {formatTimeDiff(workingTime, jkStd)}
                      </div>
                    </td>
                    <td className="px-3 py-2 text-right font-semibold text-gray-700">
                      {stdPercentage.toFixed(0)}%
                    </td>
                    <td className="px-3 py-2 text-right">
                      <span className={`px-2 py-1 rounded-full text-xs font-semibold ${getComplianceColor(realPercentage, 90, 80)}`}>
                        {realPercentage.toFixed(1)}%
                      </span>
                    </td>
                    <td className="px-3 py-2 text-right">
                      <span className={`font-semibold ${percentDiff >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                        {formatPercentDiff(realPercentage, stdPercentage)}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-right">
                      <span className={`px-2 py-0.5 rounded text-xs font-semibold ${
                        realPercentage >= 90 ? 'bg-green-100 text-green-800' :
                        realPercentage >= 80 ? 'bg-yellow-100 text-yellow-800' :
                        'bg-red-100 text-red-800'
                      }`}>
                        {realPercentage >= 90 ? 'Compliant' : realPercentage >= 80 ? 'Warning' : 'Critical'}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-right font-semibold text-gray-900">
                      {path.total_tags.toLocaleString()}
                    </td>
                  </tr>

                  {/* Expanded Segments - Table */}
                  {isExpanded && (
                    <tr>
                      <td colSpan={13} className="px-3 py-3 bg-gray-50">
                        <div className="space-y-2">
                          <div className="text-xs font-semibold text-gray-600 uppercase mb-2">Segment Details</div>
                          <SegmentTable 
                            pathId={path.id}
                            pathSignature={path.path_signature}
                            accountId="f4d823d2-93e6-4755-9a89-9da87e7fa86e"
                            carrierId={path.carrier_id}
                            carrierName={path.carrier_name}
                            productId={path.product_id}
                            productName={path.product_name}
                            originCity={path.origin_city_name}
                            destinationCity={path.destination_city_name}
                            onSegmentCountChange={(count) => {
                              setSegmentCounts(prev => ({ ...prev, [path.id]: count }))
                            }}
                            onSegmentsCalculated={(totals) => {
                              setSegmentTotals(prev => ({ ...prev, [path.id]: totals }))
                            }}
                          />
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
