import { useState, useEffect } from 'react'
import { useAccount } from '../../contexts/AccountContext'
import { supabase } from '../../lib/supabase'
import { Play, RefreshCw, AlertCircle, CheckCircle, Clock, Database, GitBranch, Map, Zap } from 'lucide-react'

interface PhaseStatus {
  name: string
  status: 'idle' | 'running' | 'ready' | 'error'
  lastRun: Date | null
  duration: number | null
  metrics: Record<string, any>
}

interface PipelineMetrics {
  rawEventsPending: number
  processedEvents: number
  journeySegments: number
  uniqueRoutes: number
}

interface LogEntry {
  timestamp: Date
  message: string
  type: 'info' | 'success' | 'warning' | 'error'
}

export default function PipelineMonitor() {
  const { effectiveAccountId } = useAccount()
  const [autoRefresh, setAutoRefresh] = useState(false)
  const [metrics, setMetrics] = useState<PipelineMetrics>({
    rawEventsPending: 0,
    processedEvents: 0,
    journeySegments: 0,
    uniqueRoutes: 0
  })
  
  const [phases, setPhases] = useState<Record<string, PhaseStatus>>({
    consolidation: {
      name: 'Phase 2: Consolidation',
      status: 'ready',
      lastRun: null,
      duration: null,
      metrics: {}
    },
    segments: {
      name: 'Phase 3: Segment Building',
      status: 'ready',
      lastRun: null,
      duration: null,
      metrics: {}
    },
    aggregation: {
      name: 'Phase 4: Route Aggregation',
      status: 'ready',
      lastRun: null,
      duration: null,
      metrics: {}
    }
  })
  
  const [logs, setLogs] = useState<LogEntry[]>([])
  const [recentIncidents, setRecentIncidents] = useState<any[]>([])

  // Load metrics
  const loadMetrics = async () => {
    if (!effectiveAccountId) return

    try {
      const { data: status } = await supabase.rpc('rpc_get_pipeline_status')
      
      if (status) {
        setMetrics({
          rawEventsPending: status.raw_events_pending || 0,
          processedEvents: status.processed_events || 0,
          journeySegments: status.journey_segments || 0,
          uniqueRoutes: status.unique_routes || 0
        })
      }
    } catch (error) {
      console.error('Error loading metrics:', error)
    }
  }

  // Load recent incidents
  const loadIncidents = async () => {
    if (!effectiveAccountId) return

    try {
      const { data } = await supabase.rpc('rpc_get_recent_incidents', {
        p_limit: 10
      })
      
      if (data) {
        setRecentIncidents(data)
      }
    } catch (error) {
      console.error('Error loading incidents:', error)
    }
  }

  // Add log entry
  const addLog = (message: string, type: LogEntry['type'] = 'info') => {
    setLogs(prev => {
      const newLogs = [...prev, { timestamp: new Date(), message, type }]
      return newLogs.slice(-100) // Keep last 100 entries
    })
  }

  // Run phase
  const runPhase = async (phaseKey: string) => {
    if (!effectiveAccountId) return

    setPhases(prev => ({
      ...prev,
      [phaseKey]: { ...prev[phaseKey], status: 'running' }
    }))

    addLog(`${phases[phaseKey].name} started...`, 'info')

    try {
      const { data, error } = await supabase.rpc('rpc_execute_pipeline_phase', {
        p_phase: phaseKey
      })

      if (error) throw error

      const duration = data.duration_seconds || 0
      
      setPhases(prev => ({
        ...prev,
        [phaseKey]: {
          ...prev[phaseKey],
          status: 'ready',
          lastRun: new Date(),
          duration,
          metrics: data
        }
      }))

      addLog(`✅ ${phases[phaseKey].name} completed in ${duration.toFixed(2)}s`, 'success')
      
      if (data.events_processed) {
        addLog(`Processed ${data.events_processed} events`, 'info')
      }
      if (data.events_created) {
        addLog(`Created ${data.events_created} consolidated events`, 'info')
      }
      if (data.segments_created) {
        addLog(`Created ${data.segments_created} segments`, 'info')
      }
      if (data.paths_created) {
        addLog(`Created ${data.paths_created} unique paths`, 'info')
      }

      await loadMetrics()
      await loadIncidents()
    } catch (error: any) {
      setPhases(prev => ({
        ...prev,
        [phaseKey]: { ...prev[phaseKey], status: 'error' }
      }))
      addLog(`❌ ${phases[phaseKey].name} failed: ${error.message}`, 'error')
    }
  }

  // Run full pipeline
  const runFullPipeline = async () => {
    addLog('🚀 Starting full pipeline execution...', 'info')
    for (const phaseKey of ['consolidation', 'segments', 'aggregation']) {
      await runPhase(phaseKey)
    }
    addLog('✅ Full pipeline execution completed', 'success')
  }

  // Clear logs
  const clearLogs = () => {
    setLogs([])
    addLog('Logs cleared', 'info')
  }

  // Auto-refresh
  useEffect(() => {
    if (autoRefresh) {
      const interval = setInterval(() => {
        loadMetrics()
        loadIncidents()
      }, 30000) // 30 seconds

      return () => clearInterval(interval)
    }
  }, [autoRefresh])

  // Initial load
  useEffect(() => {
    loadMetrics()
    loadIncidents()
  }, [effectiveAccountId])

  const getStatusColor = (status: PhaseStatus['status']) => {
    switch (status) {
      case 'idle': return 'bg-gray-100 text-gray-700'
      case 'running': return 'bg-blue-100 text-blue-700'
      case 'ready': return 'bg-green-100 text-green-700'
      case 'error': return 'bg-red-100 text-red-700'
    }
  }

  const getLogColor = (type: LogEntry['type']) => {
    switch (type) {
      case 'info': return 'text-gray-600'
      case 'success': return 'text-green-600'
      case 'warning': return 'text-yellow-600'
      case 'error': return 'text-red-600'
    }
  }

  const formatTimestamp = (date: Date) => {
    return date.toLocaleTimeString('en-US', { hour12: false })
  }

  const formatRelativeTime = (date: Date | null) => {
    if (!date) return 'Never'
    const seconds = Math.floor((new Date().getTime() - date.getTime()) / 1000)
    if (seconds < 60) return `${seconds}s ago`
    const minutes = Math.floor(seconds / 60)
    if (minutes < 60) return `${minutes}m ago`
    const hours = Math.floor(minutes / 60)
    return `${hours}h ago`
  }

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-bold text-gray-900">EPCIS Pipeline Monitor</h1>
        <div className="flex items-center gap-2">
          <label className="flex items-center gap-2 text-sm text-gray-600">
            <input
              type="checkbox"
              checked={autoRefresh}
              onChange={(e) => setAutoRefresh(e.target.checked)}
              className="rounded border-gray-300"
            />
            Auto Refresh (30s)
          </label>
          <button
            onClick={() => { loadMetrics(); loadIncidents(); }}
            className="p-2 hover:bg-gray-100 rounded-lg"
          >
            <RefreshCw className="w-5 h-5 text-gray-600" />
          </button>
        </div>
      </div>

      {/* Metrics Overview */}
      <div className="grid grid-cols-4 gap-4">
        <div className="bg-white rounded-lg shadow p-4">
          <div className="flex items-center gap-2 text-gray-600 mb-2">
            <Database className="w-5 h-5" />
            <span className="text-sm font-medium">Raw Events</span>
          </div>
          <div className="text-3xl font-bold text-gray-900">{metrics.rawEventsPending.toLocaleString()}</div>
          <div className="text-sm text-gray-500">pending</div>
        </div>

        <div className="bg-white rounded-lg shadow p-4">
          <div className="flex items-center gap-2 text-gray-600 mb-2">
            <CheckCircle className="w-5 h-5" />
            <span className="text-sm font-medium">Processed</span>
          </div>
          <div className="text-3xl font-bold text-gray-900">{metrics.processedEvents.toLocaleString()}</div>
          <div className="text-sm text-gray-500">events</div>
        </div>

        <div className="bg-white rounded-lg shadow p-4">
          <div className="flex items-center gap-2 text-gray-600 mb-2">
            <GitBranch className="w-5 h-5" />
            <span className="text-sm font-medium">Segments</span>
          </div>
          <div className="text-3xl font-bold text-gray-900">{metrics.journeySegments.toLocaleString()}</div>
          <div className="text-sm text-gray-500">segments</div>
        </div>

        <div className="bg-white rounded-lg shadow p-4">
          <div className="flex items-center gap-2 text-gray-600 mb-2">
            <Map className="w-5 h-5" />
            <span className="text-sm font-medium">Routes</span>
          </div>
          <div className="text-3xl font-bold text-gray-900">{metrics.uniqueRoutes.toLocaleString()}</div>
          <div className="text-sm text-gray-500">unique paths</div>
        </div>
      </div>

      {/* Pipeline Phases */}
      <div className="bg-white rounded-lg shadow p-6">
        <h2 className="text-xl font-semibold text-gray-900 mb-4">Pipeline Phases</h2>
        
        <div className="space-y-4">
          {Object.entries(phases).map(([key, phase]) => (
            <div key={key} className="border border-gray-200 rounded-lg p-4">
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-3">
                  <h3 className="font-semibold text-gray-900">{phase.name}</h3>
                  <span className={`px-2 py-1 rounded-full text-xs font-semibold ${getStatusColor(phase.status)}`}>
                    {phase.status === 'running' && <RefreshCw className="w-3 h-3 inline animate-spin mr-1" />}
                    {phase.status.charAt(0).toUpperCase() + phase.status.slice(1)}
                  </span>
                </div>
                <button
                  onClick={() => runPhase(key)}
                  disabled={phase.status === 'running'}
                  className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <Play className="w-4 h-4" />
                  Run Now
                </button>
              </div>
              
              <div className="flex items-center gap-4 text-sm text-gray-600">
                <span>Last run: {formatRelativeTime(phase.lastRun)}</span>
                {phase.duration && <span>Duration: {phase.duration.toFixed(2)}s</span>}
              </div>
              
              {Object.keys(phase.metrics).length > 0 && (
                <div className="mt-2 text-sm text-gray-600">
                  {JSON.stringify(phase.metrics)}
                </div>
              )}
            </div>
          ))}
        </div>

        <div className="mt-6">
          <button
            onClick={runFullPipeline}
            className="w-full flex items-center justify-center gap-2 px-6 py-3 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 font-semibold"
          >
            <Zap className="w-5 h-5" />
            Run Full Pipeline
          </button>
        </div>
      </div>

      {/* Recent Incidents */}
      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-semibold text-gray-900">Recent Incidents</h2>
          <span className="text-sm text-gray-500">Last 10 unresolved</span>
        </div>
        
        {recentIncidents.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <CheckCircle className="w-12 h-12 mx-auto mb-2 text-green-500" />
            <p>No recent incidents</p>
          </div>
        ) : (
          <div className="space-y-2">
            {recentIncidents.map((incident, idx) => (
              <div key={idx} className="flex items-center gap-3 p-3 border border-gray-200 rounded-lg">
                <AlertCircle className="w-5 h-5 text-yellow-600 flex-shrink-0" />
                <div className="flex-1">
                  <span className="font-medium text-gray-900">{incident.incident_type}</span>
                  <span className="text-gray-600"> | Tag: {incident.tag_id?.slice(0, 10)}...</span>
                </div>
                <span className="text-sm text-gray-500">{formatRelativeTime(new Date(incident.created_at))}</span>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Execution Log */}
      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-semibold text-gray-900">Execution Log</h2>
          <button
            onClick={clearLogs}
            className="text-sm text-gray-600 hover:text-gray-900"
          >
            Clear Log
          </button>
        </div>
        
        <div className="bg-gray-50 rounded-lg p-4 h-64 overflow-y-auto font-mono text-sm">
          {logs.length === 0 ? (
            <div className="text-gray-500 text-center py-8">No log entries yet</div>
          ) : (
            logs.map((log, idx) => (
              <div key={idx} className={getLogColor(log.type)}>
                [{formatTimestamp(log.timestamp)}] {log.message}
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  )
}
