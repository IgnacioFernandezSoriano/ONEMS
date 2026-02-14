import { useMemo, useState } from 'react'

interface SegmentDetail {
  from_city: string
  to_city: string
  from_center_name: string
  to_center_name: string
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

interface RoutePathData {
  id: string
  carrier_name: string
  product_name: string
  path_signature: string
  path_segments: any[]
  total_tags: number
  compliance_rate: number
  avg_natural_time_minutes: number
  avg_working_time_minutes: number
  expected_time_minutes: number
  on_time_percentage_std: number
  segment_details: SegmentDetail[]
}

interface Props {
  routePaths: RoutePathData[]
}

interface Node {
  id: string
  name: string
  x: number
  y: number
  totalTags: number
}

interface Edge {
  from: string
  to: string
  tags: number
  paths: RoutePathData[]
  aggregatedData: {
    avg_natural_time: number
    avg_working_time: number
    expected_time: number
    compliance_rate: number
    on_time_std: number
  }
}

export default function RouteFlowMap({ routePaths }: Props) {
  const [hoveredEdge, setHoveredEdge] = useState<string | null>(null)
  const [mousePos, setMousePos] = useState({ x: 0, y: 0 })

  const { nodes, edges } = useMemo(() => {
    // Extract unique cities and create nodes
    const citySet = new Set<string>()
    const cityTags = new Map<string, number>()

    routePaths.forEach(path => {
      path.path_segments.forEach((segment: any) => {
        if (segment.from) {
          citySet.add(segment.from)
          cityTags.set(segment.from, (cityTags.get(segment.from) || 0) + path.total_tags)
        }
        if (segment.to) {
          citySet.add(segment.to)
          cityTags.set(segment.to, (cityTags.get(segment.to) || 0) + path.total_tags)
        }
      })
    })

    const cities = Array.from(citySet)
    
    // Position nodes in a circle
    const centerX = 400
    const centerY = 300
    const radius = 200
    
    const nodeList: Node[] = cities.map((city, index) => {
      const angle = (index / cities.length) * 2 * Math.PI - Math.PI / 2
      return {
        id: city,
        name: city,
        x: centerX + radius * Math.cos(angle),
        y: centerY + radius * Math.sin(angle),
        totalTags: cityTags.get(city) || 0
      }
    })

    // Create edges from segments
    const edgeMap = new Map<string, Edge>()

    routePaths.forEach(path => {
      path.path_segments.forEach((segment: any) => {
        const key = `${segment.from}-${segment.to}`
        if (!edgeMap.has(key)) {
          edgeMap.set(key, {
            from: segment.from,
            to: segment.to,
            tags: 0,
            paths: [],
            aggregatedData: {
              avg_natural_time: 0,
              avg_working_time: 0,
              expected_time: 0,
              compliance_rate: 0,
              on_time_std: 0
            }
          })
        }
        const edge = edgeMap.get(key)!
        edge.tags += path.total_tags
        edge.paths.push(path)
      })
    })

    // Calculate aggregated data for each edge
    edgeMap.forEach(edge => {
      const totalTags = edge.tags
      let sumNaturalTime = 0
      let sumWorkingTime = 0
      let sumExpectedTime = 0
      let sumCompliance = 0
      let sumOnTimeStd = 0

      edge.paths.forEach(path => {
        const weight = path.total_tags / totalTags
        sumNaturalTime += path.avg_natural_time_minutes * weight
        sumWorkingTime += path.avg_working_time_minutes * weight
        sumExpectedTime += path.expected_time_minutes * weight
        sumCompliance += path.compliance_rate * weight
        sumOnTimeStd += path.on_time_percentage_std * weight
      })

      edge.aggregatedData = {
        avg_natural_time: sumNaturalTime,
        avg_working_time: sumWorkingTime,
        expected_time: sumExpectedTime,
        compliance_rate: sumCompliance,
        on_time_std: sumOnTimeStd
      }
    })

    return {
      nodes: nodeList,
      edges: Array.from(edgeMap.values())
    }
  }, [routePaths])

  const maxTags = Math.max(...edges.map(e => e.tags), 1)
  const maxNodeTags = Math.max(...nodes.map(n => n.totalTags), 1)

  const getStrokeWidth = (tags: number) => {
    return Math.max(2, (tags / maxTags) * 20)
  }

  const getNodeRadius = (tags: number) => {
    return Math.max(20, (tags / maxNodeTags) * 40)
  }

  const getNodePosition = (cityName: string) => {
    return nodes.find(n => n.id === cityName)
  }

  const formatJK = (minutes: number) => {
    const days = (minutes / (24 * 60)).toFixed(3)
    return `J+${days}`
  }

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

  const formatPercentDiff = (actual: number, expected: number) => {
    const diff = actual - expected
    const sign = diff >= 0 ? '+' : ''
    return `${sign}${diff.toFixed(1)}%`
  }

  if (nodes.length === 0) {
    return (
      <div className="p-12 text-center text-gray-500">
        <p>No route data available</p>
      </div>
    )
  }

  return (
    <div className="p-6 relative">
      <div className="mb-4">
        <h3 className="text-lg font-semibold text-gray-900 mb-2">Flow Map</h3>
        <p className="text-sm text-gray-600">
          Line thickness represents the number of tags. Hover over lines for details.
        </p>
      </div>

      <svg 
        width="800" 
        height="600" 
        className="mx-auto border border-gray-200 rounded-lg bg-gray-50"
        onMouseMove={(e) => {
          const rect = e.currentTarget.getBoundingClientRect()
          setMousePos({
            x: e.clientX - rect.left,
            y: e.clientY - rect.top
          })
        }}
      >
        {/* Draw edges first (behind nodes) */}
        {edges.map((edge, index) => {
          const fromNode = getNodePosition(edge.from)
          const toNode = getNodePosition(edge.to)
          
          if (!fromNode || !toNode) return null

          const strokeWidth = getStrokeWidth(edge.tags)
          const compliance = edge.aggregatedData.compliance_rate
          const strokeColor = compliance >= 90 ? '#10b981' : compliance >= 70 ? '#f59e0b' : '#ef4444'
          const edgeKey = `${edge.from}-${edge.to}`
          const isHovered = hoveredEdge === edgeKey

          return (
            <g 
              key={index}
              onMouseEnter={() => setHoveredEdge(edgeKey)}
              onMouseLeave={() => setHoveredEdge(null)}
              className="cursor-pointer"
            >
              {/* Invisible wider line for easier hovering */}
              <line
                x1={fromNode.x}
                y1={fromNode.y}
                x2={toNode.x}
                y2={toNode.y}
                stroke="transparent"
                strokeWidth={Math.max(strokeWidth + 10, 20)}
              />
              {/* Visible line */}
              <line
                x1={fromNode.x}
                y1={fromNode.y}
                x2={toNode.x}
                y2={toNode.y}
                stroke={strokeColor}
                strokeWidth={strokeWidth}
                strokeOpacity={isHovered ? 1 : 0.6}
                markerEnd="url(#arrowhead)"
                className="transition-all"
              />
              {/* Label */}
              <text
                x={(fromNode.x + toNode.x) / 2}
                y={(fromNode.y + toNode.y) / 2 - 5}
                textAnchor="middle"
                className="text-xs fill-gray-700 font-semibold pointer-events-none"
              >
                {edge.tags.toLocaleString()}
              </text>
            </g>
          )
        })}

        {/* Arrow marker definition */}
        <defs>
          <marker
            id="arrowhead"
            markerWidth="10"
            markerHeight="10"
            refX="9"
            refY="3"
            orient="auto"
          >
            <polygon points="0 0, 10 3, 0 6" fill="#6b7280" fillOpacity={0.6} />
          </marker>
        </defs>

        {/* Draw nodes */}
        {nodes.map((node, index) => {
          const radius = getNodeRadius(node.totalTags)
          
          return (
            <g key={index}>
              <circle
                cx={node.x}
                cy={node.y}
                r={radius}
                fill="#3b82f6"
                fillOpacity={0.8}
                stroke="#1e40af"
                strokeWidth={2}
                className="cursor-pointer hover:fill-opacity-100 transition-all"
              />
              <text
                x={node.x}
                y={node.y + radius + 20}
                textAnchor="middle"
                className="text-sm font-semibold fill-gray-900"
              >
                {node.name}
              </text>
              <text
                x={node.x}
                y={node.y + 5}
                textAnchor="middle"
                className="text-xs fill-white font-bold"
              >
                {node.totalTags.toLocaleString()}
              </text>
            </g>
          )
        })}
      </svg>

      {/* Hover Tooltip */}
      {hoveredEdge && (() => {
        const edge = edges.find(e => `${e.from}-${e.to}` === hoveredEdge)
        if (!edge) return null

        const data = edge.aggregatedData

        return (
          <div 
            className="absolute bg-gray-900 text-white text-xs rounded-lg p-4 shadow-lg z-50 w-80 pointer-events-none"
            style={{
              left: mousePos.x + 10,
              top: mousePos.y + 10
            }}
          >
            <div className="font-semibold mb-3 text-sm border-b border-gray-700 pb-2">
              {edge.from} → {edge.to}
            </div>
            <div className="space-y-2">
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <div className="text-gray-400 mb-1">Tags</div>
                  <div className="font-semibold">{edge.tags.toLocaleString()}</div>
                </div>
                <div>
                  <div className="text-gray-400 mb-1">Paths</div>
                  <div className="font-semibold">{edge.paths.length}</div>
                </div>
              </div>
              
              <div>
                <div className="text-gray-400 mb-1">J+K Standard</div>
                <div className="font-semibold font-mono">{formatJK(data.expected_time)}</div>
              </div>
              
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <div className="text-gray-400 mb-1">Natural Time</div>
                  <div className="font-semibold font-mono">{formatJK(data.avg_natural_time)}</div>
                  <div className={`text-xs ${data.avg_natural_time > data.expected_time ? 'text-red-400' : 'text-green-400'}`}>
                    {formatTimeDiff(data.avg_natural_time, data.expected_time)}
                  </div>
                </div>
                <div>
                  <div className="text-gray-400 mb-1">Working Time</div>
                  <div className="font-semibold font-mono">{formatJK(data.avg_working_time)}</div>
                  <div className={`text-xs ${data.avg_working_time > data.expected_time ? 'text-red-400' : 'text-green-400'}`}>
                    {formatTimeDiff(data.avg_working_time, data.expected_time)}
                  </div>
                </div>
              </div>
              
              <div className="grid grid-cols-3 gap-2">
                <div>
                  <div className="text-gray-400 mb-1">% Std</div>
                  <div className="font-semibold">{data.on_time_std.toFixed(0)}%</div>
                </div>
                <div>
                  <div className="text-gray-400 mb-1">% Real</div>
                  <div className={`font-semibold ${
                    data.compliance_rate >= 90 ? 'text-green-400' :
                    data.compliance_rate >= 70 ? 'text-yellow-400' :
                    'text-red-400'
                  }`}>
                    {data.compliance_rate.toFixed(1)}%
                  </div>
                </div>
                <div>
                  <div className="text-gray-400 mb-1">Diff %</div>
                  <div className={`font-semibold ${data.compliance_rate >= data.on_time_std ? 'text-green-400' : 'text-red-400'}`}>
                    {formatPercentDiff(data.compliance_rate, data.on_time_std)}
                  </div>
                </div>
              </div>
              
              <div className="text-xs text-gray-400 mt-2">
                Aggregated from {edge.paths.length} route path{edge.paths.length !== 1 ? 's' : ''}
              </div>
            </div>
          </div>
        )
      })()}

      {/* Legend */}
      <div className="mt-6 flex items-center justify-center gap-6 text-sm">
        <div className="flex items-center gap-2">
          <div className="w-4 h-1 bg-green-500"></div>
          <span className="text-gray-600">≥90% SLA</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-4 h-1 bg-yellow-500"></div>
          <span className="text-gray-600">70-89% SLA</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-4 h-1 bg-red-500"></div>
          <span className="text-gray-600">&lt;70% SLA</span>
        </div>
      </div>
    </div>
  )
}
