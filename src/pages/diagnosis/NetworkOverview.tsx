import { useState, useEffect } from 'react'
import { useAccount } from '../../contexts/AccountContext'
import { supabase } from '../../lib/supabase'
import { Activity, TrendingUp, Clock, Database, AlertTriangle, CheckCircle, Info } from 'lucide-react'

interface HealthScore {
  health_score: number
  on_time_delivery_rate: number
  avg_transit_time_hours: number
  avg_processing_time_hours: number
  total_items: number
  total_routes: number
  total_centers: number
  total_sla_violations: number
}

export default function NetworkOverview() {
  const { selectedAccountId } = useAccount()
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [healthScore, setHealthScore] = useState<HealthScore | null>(null)
  const [autoFindings, setAutoFindings] = useState<string[]>([])

  useEffect(() => {
    if (selectedAccountId) {
      loadData()
    }
  }, [selectedAccountId])

  const loadData = async () => {
    setLoading(true)
    setError(null)
    
    try {
      console.log('Loading health score for account:', selectedAccountId)
      
      const { data: healthData, error: healthError } = await supabase
        .rpc('calculate_network_health_score', {
          p_account_id: selectedAccountId,
        })

      if (healthError) {
        console.error('Health score error:', healthError)
        throw healthError
      }
      
      console.log('Health data received:', healthData)
      
      if (healthData && healthData.length > 0) {
        setHealthScore(healthData[0])
        generateAutoFindings(healthData[0])
      } else {
        setError('No data available')
      }
    } catch (err: any) {
      console.error('Error loading network overview data:', err)
      setError(err.message || 'Failed to load data')
    } finally {
      setLoading(false)
    }
  }

  const generateAutoFindings = (health: HealthScore) => {
    const findings: string[] = []

    if (health.health_score >= 80) {
      findings.push(`Network health is excellent (${health.health_score.toFixed(1)}/100). Overall performance is strong.`)
    } else if (health.health_score >= 60) {
      findings.push(`Network health is moderate (${health.health_score.toFixed(1)}/100). Some areas need attention.`)
    } else {
      findings.push(`Network health is concerning (${health.health_score.toFixed(1)}/100). Immediate action recommended.`)
    }

    if (health.on_time_delivery_rate < 80) {
      findings.push(`On-time delivery rate is ${health.on_time_delivery_rate.toFixed(1)}%, below the 80% target.`)
    }

    if (health.avg_transit_time_hours > 48) {
      findings.push(`Average transit time is ${health.avg_transit_time_hours.toFixed(1)} hours, which may indicate delays.`)
    }

    if (health.avg_processing_time_hours > 4) {
      findings.push(`Average processing time at centers is ${health.avg_processing_time_hours.toFixed(1)} hours, above optimal levels.`)
    }

    if (health.total_sla_violations > 0) {
      const violationRate = (health.total_sla_violations / health.total_items) * 100
      findings.push(`${health.total_sla_violations} SLA violations detected (${violationRate.toFixed(1)}% of total items).`)
    }

    setAutoFindings(findings)
  }

  const getHealthScoreColor = (score: number) => {
    if (score >= 80) return 'text-green-600'
    if (score >= 60) return 'text-yellow-600'
    return 'text-red-600'
  }

  const getHealthScoreBgColor = (score: number) => {
    if (score >= 80) return 'bg-green-50 border-green-200'
    if (score >= 60) return 'bg-yellow-50 border-yellow-200'
    return 'bg-red-50 border-red-200'
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto mb-4"></div>
          <p className="text-gray-600">Loading network overview...</p>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <AlertTriangle className="h-12 w-12 text-red-500 mx-auto mb-4" />
          <p className="text-gray-900 font-semibold mb-2">Error loading data</p>
          <p className="text-gray-600">{error}</p>
          <button
            onClick={loadData}
            className="mt-4 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
          >
            Retry
          </button>
        </div>
      </div>
    )
  }

  if (!healthScore) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <AlertTriangle className="h-12 w-12 text-yellow-500 mx-auto mb-4" />
          <p className="text-gray-600">No data available for the selected account.</p>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-6 p-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Network Overview</h1>
        <p className="text-gray-600 mt-1">
          Comprehensive health assessment and performance summary of your postal network
        </p>
      </div>

      {/* Health Score Card */}
      <div className={`border-2 rounded-lg p-6 ${getHealthScoreBgColor(healthScore.health_score)}`}>
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold text-gray-700 mb-2">Network Health Score</h2>
            <div className={`text-5xl font-bold ${getHealthScoreColor(healthScore.health_score)}`}>
              {healthScore.health_score.toFixed(1)}
              <span className="text-2xl text-gray-500">/100</span>
            </div>
          </div>
          <Activity className={`h-16 w-16 ${getHealthScoreColor(healthScore.health_score)}`} />
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-white border border-gray-200 rounded-lg p-4 group relative">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-gray-600 flex items-center gap-1">
              On-Time Delivery
              <div className="relative">
                <Info className="h-4 w-4 text-gray-400 cursor-help" />
                <div className="invisible group-hover:visible absolute left-0 top-6 w-72 bg-gray-900 text-white text-xs rounded-lg p-3 z-50 shadow-xl">
                  <p className="font-semibold mb-1">Calculation:</p>
                  <p className="mb-2">Percentage of items delivered without SLA violations across the entire network.</p>
                  <p className="font-semibold mb-1">Interpretation:</p>
                  <p>&gt;80%: Excellent compliance with quality standards</p>
                  <p>60-80%: Acceptable, but improvement needed</p>
                  <p>&lt;60%: Critical issues requiring immediate attention</p>
                </div>
              </div>
            </span>
            <TrendingUp className="h-5 w-5 text-blue-500" />
          </div>
          <div className="text-2xl font-bold text-gray-900">
            {healthScore.on_time_delivery_rate.toFixed(1)}%
          </div>
          <p className="text-xs text-gray-500 mt-1">
            {healthScore.total_items.toLocaleString()} total items
          </p>
        </div>

        <div className="bg-white border border-gray-200 rounded-lg p-4 group relative">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-gray-600 flex items-center gap-1">
              Avg Transit Time
              <div className="relative">
                <Info className="h-4 w-4 text-gray-400 cursor-help" />
                <div className="invisible group-hover:visible absolute left-0 top-6 w-72 bg-gray-900 text-white text-xs rounded-lg p-3 z-50 shadow-xl">
                  <p className="font-semibold mb-1">Calculation:</p>
                  <p className="mb-2">Average operational time (excluding non-working hours) from induction to delivery across all completed journeys.</p>
                  <p className="font-semibold mb-1">Interpretation:</p>
                  <p>&lt;24h: Exceptional speed (domestic express)</p>
                  <p>24-48h: Good performance (standard service)</p>
                  <p>&gt;48h: Potential bottlenecks or inefficiencies</p>
                </div>
              </div>
            </span>
            <Clock className="h-5 w-5 text-purple-500" />
          </div>
          <div className="text-2xl font-bold text-gray-900">
            {healthScore.avg_transit_time_hours.toFixed(1)}h
          </div>
          <p className="text-xs text-gray-500 mt-1">End-to-end delivery</p>
        </div>

        <div className="bg-white border border-gray-200 rounded-lg p-4 group relative">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-gray-600 flex items-center gap-1">
              Avg Processing Time
              <div className="relative">
                <Info className="h-4 w-4 text-gray-400 cursor-help" />
                <div className="invisible group-hover:visible absolute left-0 top-6 w-72 bg-gray-900 text-white text-xs rounded-lg p-3 z-50 shadow-xl">
                  <p className="font-semibold mb-1">Calculation:</p>
                  <p className="mb-2">Average adjusted time (excluding pre-operational waits) items spend at postal centers during processing segments.</p>
                  <p className="font-semibold mb-1">Interpretation:</p>
                  <p>&lt;2h: Highly efficient operations</p>
                  <p>2-4h: Normal processing capacity</p>
                  <p>&gt;4h: Congestion or operational inefficiencies</p>
                </div>
              </div>
            </span>
            <Database className="h-5 w-5 text-green-500" />
          </div>
          <div className="text-2xl font-bold text-gray-900">
            {healthScore.avg_processing_time_hours.toFixed(1)}h
          </div>
          <p className="text-xs text-gray-500 mt-1">At postal centers</p>
        </div>

        <div className="bg-white border border-gray-200 rounded-lg p-4 group relative">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-gray-600 flex items-center gap-1">
              Network Coverage
              <div className="relative">
                <Info className="h-4 w-4 text-gray-400 cursor-help" />
                <div className="invisible group-hover:visible absolute left-0 top-6 w-72 bg-gray-900 text-white text-xs rounded-lg p-3 z-50 shadow-xl">
                  <p className="font-semibold mb-1">Calculation:</p>
                  <p className="mb-2">Total number of unique origin-destination routes with recorded traffic, and total active postal centers.</p>
                  <p className="font-semibold mb-1">Interpretation:</p>
                  <p>Higher route count indicates broader network connectivity and service reach. Compare against expected topology to identify gaps.</p>
                </div>
              </div>
            </span>
            <CheckCircle className="h-5 w-5 text-indigo-500" />
          </div>
          <div className="text-2xl font-bold text-gray-900">
            {healthScore.total_routes}
          </div>
          <p className="text-xs text-gray-500 mt-1">
            {healthScore.total_centers} centers
          </p>
        </div>
      </div>

      {/* Automatic Findings */}
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
        <h3 className="text-lg font-semibold text-gray-900 mb-3 flex items-center">
          <Activity className="h-5 w-5 mr-2 text-blue-600" />
          Automatic Findings
        </h3>
        <ul className="space-y-2">
          {autoFindings.map((finding, index) => (
            <li key={index} className="flex items-start">
              <span className="text-blue-600 mr-2">•</span>
              <span className="text-gray-700">{finding}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}
