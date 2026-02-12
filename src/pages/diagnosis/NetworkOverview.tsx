import { useState, useEffect } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import { supabase } from '../../lib/supabase'
import { Activity, TrendingUp, Clock, Database, AlertCircle, Info } from 'lucide-react'

interface HealthScore {
  health_score: number
  on_time_delivery_rate: number
  avg_transit_time_hours: number
  avg_processing_time_hours: number
  data_quality_score: number
  total_items: number
  total_routes: number
  total_centers: number
  total_sla_violations: number
}

export default function NetworkOverview() {
  const { profile } = useAuth()
  const accountId = profile?.account_id
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [healthScore, setHealthScore] = useState<HealthScore | null>(null)

  useEffect(() => {
    let mounted = true

    const loadData = async () => {
      console.log('[NetworkOverview] accountId:', accountId)
      
      if (!accountId) {
        console.log('[NetworkOverview] No account ID, skipping load')
        setLoading(false)
        return
      }

      setLoading(true)
      setError(null)

      try {
        console.log('[NetworkOverview] Calling RPC with account:', accountId)
        
        const { data, error: rpcError } = await supabase.rpc('calculate_network_health_score', {
          p_account_id: accountId,
        })
        
        console.log('[NetworkOverview] RPC response:', { data, error: rpcError })

        if (!mounted) return

        if (rpcError) {
          console.error('RPC error:', rpcError)
          setError(rpcError.message)
          setLoading(false)
          return
        }

        if (data && data.length > 0) {
          console.log('[NetworkOverview] Setting health score:', data[0])
          setHealthScore(data[0])
        } else {
          console.log('[NetworkOverview] No data returned')
          setHealthScore(null)
        }
      } catch (err) {
        if (!mounted) return
        console.error('Error loading data:', err)
        setError(err instanceof Error ? err.message : 'Unknown error')
      } finally {
        if (mounted) {
          setLoading(false)
        }
      }
    }

    loadData()

    return () => {
      mounted = false
    }
  }, [accountId])

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
      <div className="p-6">
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
          <div>
            <h3 className="font-semibold text-red-900">Error loading data</h3>
            <p className="text-red-700 text-sm mt-1">{error}</p>
          </div>
        </div>
      </div>
    )
  }

  if (!healthScore) {
    return (
      <div className="p-6">
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 flex items-start gap-3">
          <Info className="w-5 h-5 text-yellow-600 flex-shrink-0 mt-0.5" />
          <div>
            <h3 className="font-semibold text-yellow-900">No data available</h3>
            <p className="text-yellow-700 text-sm mt-1">
              No journey data found for this account. Please ensure data has been ingested.
            </p>
          </div>
        </div>
      </div>
    )
  }

  const getHealthColor = (score: number) => {
    if (score >= 80) return 'text-green-600'
    if (score >= 60) return 'text-yellow-600'
    return 'text-red-600'
  }

  const getHealthBgColor = (score: number) => {
    if (score >= 80) return 'bg-green-50 border-green-200'
    if (score >= 60) return 'bg-yellow-50 border-yellow-200'
    return 'bg-red-50 border-red-200'
  }

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Network Overview</h1>
        <p className="text-gray-600 mt-1">Comprehensive health assessment of the postal network</p>
      </div>

      {/* Health Score Card */}
      <div className={`border rounded-lg p-6 ${getHealthBgColor(healthScore.health_score)}`}>
        <div className="flex items-center justify-between">
          <div>
            <div className="flex items-center gap-2 mb-2">
              <Activity className="w-5 h-5 text-gray-600" />
              <h2 className="text-lg font-semibold text-gray-900">Network Health Score</h2>
            </div>
            <p className="text-sm text-gray-600">
              Weighted average of key performance indicators
            </p>
          </div>
          <div className="text-right">
            <div className={`text-5xl font-bold ${getHealthColor(healthScore.health_score)}`}>
              {healthScore.health_score.toFixed(1)}
            </div>
            <div className="text-sm text-gray-500 mt-1">out of 100</div>
          </div>
        </div>
      </div>

      {/* KPI Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* On-time Delivery Rate */}
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <TrendingUp className="w-4 h-4 text-blue-600" />
            <h3 className="font-semibold text-gray-900">On-time Delivery</h3>
            <button className="ml-auto text-gray-400 hover:text-gray-600" title="Percentage of journeys meeting SLA targets">
              <Info className="w-4 h-4" />
            </button>
          </div>
          <div className="text-3xl font-bold text-blue-600">
            {healthScore.on_time_delivery_rate.toFixed(1)}%
          </div>
          <p className="text-xs text-gray-500 mt-1">{healthScore.total_items.toLocaleString()} items</p>
        </div>

        {/* Avg Transit Time */}
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <Clock className="w-4 h-4 text-purple-600" />
            <h3 className="font-semibold text-gray-900">Avg Transit Time</h3>
            <button className="ml-auto text-gray-400 hover:text-gray-600" title="Average end-to-end transit time across all routes">
              <Info className="w-4 h-4" />
            </button>
          </div>
          <div className="text-3xl font-bold text-purple-600">
            {healthScore.avg_transit_time_hours.toFixed(1)}h
          </div>
          <p className="text-xs text-gray-500 mt-1">{healthScore.total_routes} routes</p>
        </div>

        {/* Avg Processing Time */}
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <Database className="w-4 h-4 text-orange-600" />
            <h3 className="font-semibold text-gray-900">Avg Processing Time</h3>
            <button className="ml-auto text-gray-400 hover:text-gray-600" title="Average time items spend at postal centers">
              <Info className="w-4 h-4" />
            </button>
          </div>
          <div className="text-3xl font-bold text-orange-600">
            {healthScore.avg_processing_time_hours.toFixed(1)}h
          </div>
          <p className="text-xs text-gray-500 mt-1">{healthScore.total_centers} centers</p>
        </div>

        {/* Data Quality */}
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <Activity className="w-4 h-4 text-green-600" />
            <h3 className="font-semibold text-gray-900">Data Quality</h3>
            <button className="ml-auto text-gray-400 hover:text-gray-600" title="Percentage of complete journeys with valid data">
              <Info className="w-4 h-4" />
            </button>
          </div>
          <div className="text-3xl font-bold text-green-600">
            {healthScore.data_quality_score.toFixed(1)}%
          </div>
          <p className="text-xs text-gray-500 mt-1">Data completeness</p>
        </div>
      </div>

      {/* Summary Stats */}
      <div className="bg-gray-50 border border-gray-200 rounded-lg p-4">
        <h3 className="font-semibold text-gray-900 mb-3">Network Summary</h3>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
          <div>
            <div className="text-gray-600">Total Items</div>
            <div className="text-lg font-semibold text-gray-900">{healthScore.total_items.toLocaleString()}</div>
          </div>
          <div>
            <div className="text-gray-600">Active Routes</div>
            <div className="text-lg font-semibold text-gray-900">{healthScore.total_routes}</div>
          </div>
          <div>
            <div className="text-gray-600">Postal Centers</div>
            <div className="text-lg font-semibold text-gray-900">{healthScore.total_centers}</div>
          </div>
          <div>
            <div className="text-gray-600">SLA Violations</div>
            <div className="text-lg font-semibold text-red-600">{healthScore.total_sla_violations.toLocaleString()}</div>
          </div>
        </div>
      </div>
    </div>
  )
}
