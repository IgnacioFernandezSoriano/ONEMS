import { useMemo } from 'react'

interface RoutePathData {
  id: string
  path_signature: string
  path_segments: any[]
  total_tags: number
  compliance_rate: number
  segment_details: any[]
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
}

export default function RouteFlowMap({ routePaths }: Props) {
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
            paths: []
          })
        }
        const edge = edgeMap.get(key)!
        edge.tags += path.total_tags
        edge.paths.push(path)
      })
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

  if (nodes.length === 0) {
    return (
      <div className="p-12 text-center text-gray-500">
        <p>No route data available</p>
      </div>
    )
  }

  return (
    <div className="p-6">
      <div className="mb-4">
        <h3 className="text-lg font-semibold text-gray-900 mb-2">Flow Map</h3>
        <p className="text-sm text-gray-600">
          Line thickness represents the number of tags taking each route segment
        </p>
      </div>

      <svg width="800" height="600" className="mx-auto border border-gray-200 rounded-lg bg-gray-50">
        {/* Draw edges first (behind nodes) */}
        {edges.map((edge, index) => {
          const fromNode = getNodePosition(edge.from)
          const toNode = getNodePosition(edge.to)
          
          if (!fromNode || !toNode) return null

          const strokeWidth = getStrokeWidth(edge.tags)
          const compliance = edge.paths.reduce((sum, p) => sum + p.compliance_rate * p.total_tags, 0) / edge.tags
          const strokeColor = compliance >= 90 ? '#10b981' : compliance >= 70 ? '#f59e0b' : '#ef4444'

          return (
            <g key={index}>
              <line
                x1={fromNode.x}
                y1={fromNode.y}
                x2={toNode.x}
                y2={toNode.y}
                stroke={strokeColor}
                strokeWidth={strokeWidth}
                strokeOpacity={0.6}
                markerEnd="url(#arrowhead)"
              />
              {/* Label */}
              <text
                x={(fromNode.x + toNode.x) / 2}
                y={(fromNode.y + toNode.y) / 2 - 5}
                textAnchor="middle"
                className="text-xs fill-gray-700 font-semibold"
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
