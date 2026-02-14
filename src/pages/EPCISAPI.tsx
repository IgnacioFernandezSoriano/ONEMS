import { useState } from 'react'
import { useLocale } from '../contexts/LocaleContext'
import { Key, Copy, RefreshCw, AlertCircle, CheckCircle, Code, BookOpen, TestTube, BarChart3, Shield, Play } from 'lucide-react'

export function EPCISAPI() {
  const { t } = useLocale()
  const [activeTab, setActiveTab] = useState<'overview' | 'documentation' | 'testing' | 'usage'>('overview')
  const [copied, setCopied] = useState(false)

  // TODO: Implement API key management hook
  const apiKey = null // Placeholder
  const apiEndpoint = 'https://sehbnpgzqljrsqimwyuz.supabase.co/rest/v1/rpc'

  const handleCopyEndpoint = () => {
    navigator.clipboard.writeText(apiEndpoint)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const tabs = [
    { id: 'overview', label: 'Overview', icon: Key },
    { id: 'documentation', label: 'Documentation', icon: BookOpen },
    { id: 'testing', label: 'Testing', icon: TestTube },
    { id: 'usage', label: 'Usage', icon: BarChart3 }
  ]

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">EPCIS Pipeline API</h1>
        <p className="text-gray-600">
          REST API for EPCIS event ingestion and pipeline management. Includes endpoints for manual execution,
          status monitoring, and journey path queries.
        </p>
      </div>

      {/* Tabs */}
      <div className="border-b border-gray-200 mb-6">
        <nav className="-mb-px flex space-x-8">
          {tabs.map((tab) => {
            const Icon = tab.icon
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as any)}
                className={`flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm transition-colors ${
                  activeTab === tab.id
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                <Icon className="w-5 h-5" />
                {tab.label}
              </button>
            )
          })}
        </nav>
      </div>

      {/* Tab Content */}
      {activeTab === 'overview' && (
        <div className="space-y-6">
          {/* API Endpoint */}
          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center gap-2 mb-4">
              <Code className="w-5 h-5 text-blue-600" />
              <h2 className="text-xl font-semibold text-gray-900">API Endpoint</h2>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Base URL
              </label>
              <div className="flex gap-2">
                <input
                  type="text"
                  value={apiEndpoint}
                  readOnly
                  className="flex-1 px-4 py-2 border border-gray-300 rounded-lg bg-gray-50 font-mono text-sm"
                />
                <button
                  onClick={handleCopyEndpoint}
                  className="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50 flex items-center gap-2"
                >
                  {copied ? <CheckCircle className="w-4 h-4 text-green-600" /> : <Copy className="w-4 h-4" />}
                  {copied ? 'Copied' : 'Copy'}
                </button>
              </div>
            </div>
          </div>

          {/* Authentication */}
          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center gap-2 mb-4">
              <Shield className="w-5 h-5 text-blue-600" />
              <h2 className="text-xl font-semibold text-gray-900">Authentication</h2>
            </div>

            <p className="text-gray-600 mb-4">
              All API requests require authentication using your Supabase JWT token.
            </p>

            <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
              <div className="flex gap-2">
                <AlertCircle className="w-5 h-5 text-yellow-600 flex-shrink-0 mt-0.5" />
                <div className="text-sm text-yellow-800">
                  <p className="font-medium mb-1">Security Note</p>
                  <p>Use your Supabase authentication token for all API calls. The token is automatically included when using the Supabase client.</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'documentation' && (
        <div className="bg-white rounded-lg shadow p-6 space-y-8">
          {/* Available Endpoints */}
          <section>
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Available Endpoints</h2>
            
            {/* Execute Pipeline Phase */}
            <div className="border border-gray-200 rounded-lg p-4 mb-4">
              <div className="flex items-center gap-2 mb-2">
                <span className="px-2 py-1 bg-blue-100 text-blue-700 text-xs font-semibold rounded">POST</span>
                <code className="text-sm font-mono">/rpc/rpc_execute_pipeline_phase</code>
              </div>
              <p className="text-gray-600 text-sm mb-4">Manually execute EPCIS pipeline phases</p>

              <h3 className="font-semibold text-gray-900 mb-2">Parameters</h3>
              <table className="w-full text-sm mb-4">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="text-left p-2 font-semibold">Parameter</th>
                    <th className="text-left p-2 font-semibold">Type</th>
                    <th className="text-left p-2 font-semibold">Description</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_phase</td>
                    <td className="p-2">TEXT</td>
                    <td className="p-2">'consolidation', 'segments', 'aggregation', or 'all'</td>
                  </tr>
                </tbody>
              </table>

              <h3 className="font-semibold text-gray-900 mb-2">Example Request</h3>
              <div className="bg-gray-50 rounded-lg p-4 font-mono text-sm overflow-x-auto">
                <pre>{`POST /rest/v1/rpc/rpc_execute_pipeline_phase
Content-Type: application/json
Authorization: Bearer YOUR_JWT_TOKEN

{
  "p_phase": "all"
}`}</pre>
              </div>
            </div>

            {/* Get Pipeline Status */}
            <div className="border border-gray-200 rounded-lg p-4 mb-4">
              <div className="flex items-center gap-2 mb-2">
                <span className="px-2 py-1 bg-green-100 text-green-700 text-xs font-semibold rounded">POST</span>
                <code className="text-sm font-mono">/rpc/rpc_get_pipeline_status</code>
              </div>
              <p className="text-gray-600 text-sm mb-4">Get current status of EPCIS pipeline</p>

              <h3 className="font-semibold text-gray-900 mb-2">Example Request</h3>
              <div className="bg-gray-50 rounded-lg p-4 font-mono text-sm overflow-x-auto">
                <pre>{`POST /rest/v1/rpc/rpc_get_pipeline_status
Content-Type: application/json
Authorization: Bearer YOUR_JWT_TOKEN`}</pre>
              </div>
            </div>

            {/* Query Journey Paths */}
            <div className="border border-gray-200 rounded-lg p-4 mb-4">
              <div className="flex items-center gap-2 mb-2">
                <span className="px-2 py-1 bg-green-100 text-green-700 text-xs font-semibold rounded">POST</span>
                <code className="text-sm font-mono">/rpc/rpc_query_journey_paths</code>
              </div>
              <p className="text-gray-600 text-sm mb-4">Query aggregated journey paths with filters</p>

              <h3 className="font-semibold text-gray-900 mb-2">Parameters</h3>
              <table className="w-full text-sm mb-4">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="text-left p-2 font-semibold">Parameter</th>
                    <th className="text-left p-2 font-semibold">Type</th>
                    <th className="text-left p-2 font-semibold">Required</th>
                    <th className="text-left p-2 font-semibold">Description</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_carrier_id</td>
                    <td className="p-2">UUID</td>
                    <td className="p-2">No</td>
                    <td className="p-2">Filter by carrier</td>
                  </tr>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_product_id</td>
                    <td className="p-2">UUID</td>
                    <td className="p-2">No</td>
                    <td className="p-2">Filter by product</td>
                  </tr>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_origin_city</td>
                    <td className="p-2">TEXT</td>
                    <td className="p-2">No</td>
                    <td className="p-2">Filter by origin city</td>
                  </tr>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_destination_city</td>
                    <td className="p-2">TEXT</td>
                    <td className="p-2">No</td>
                    <td className="p-2">Filter by destination city</td>
                  </tr>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_min_tags</td>
                    <td className="p-2">INTEGER</td>
                    <td className="p-2">No</td>
                    <td className="p-2">Minimum number of tags</td>
                  </tr>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_limit</td>
                    <td className="p-2">INTEGER</td>
                    <td className="p-2">No</td>
                    <td className="p-2">Max results (default: 100)</td>
                  </tr>
                </tbody>
              </table>
            </div>

            {/* Ingest EPCIS Events */}
            <div className="border border-gray-200 rounded-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <span className="px-2 py-1 bg-blue-100 text-blue-700 text-xs font-semibold rounded">POST</span>
                <code className="text-sm font-mono">/rpc/rpc_ingest_epcis_events</code>
              </div>
              <p className="text-gray-600 text-sm mb-4">Bulk insert EPCIS events from external system</p>

              <h3 className="font-semibold text-gray-900 mb-2">Example Request</h3>
              <div className="bg-gray-50 rounded-lg p-4 font-mono text-sm overflow-x-auto">
                <pre>{`POST /rest/v1/rpc/rpc_ingest_epcis_events
Content-Type: application/json
Authorization: Bearer YOUR_JWT_TOKEN

{
  "p_events": [
    {
      "TagId": "30B1D226A8240000B000650C",
      "ReaderId": "J11DBRA02100000319",
      "ReadLocalDateTime": "2024-05-07T09:53:06.238-03:30"
    }
  ]
}`}</pre>
              </div>
            </div>
          </section>
        </div>
      )}

      {activeTab === 'testing' && (
        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">API Testing</h2>
          <p className="text-gray-600 mb-6">
            Use the Supabase client or any HTTP client to test the API endpoints. See the Documentation tab for request examples.
          </p>

          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
            <div className="flex gap-2">
              <AlertCircle className="w-5 h-5 text-blue-600 flex-shrink-0 mt-0.5" />
              <div className="text-sm text-blue-800">
                <p className="font-medium mb-1">Testing Tip</p>
                <p>For interactive testing, navigate to the Pipeline Monitor page where you can manually execute each phase and view results.</p>
              </div>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'usage' && (
        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">API Usage</h2>
          <p className="text-gray-600 mb-6">
            Monitor your API usage and performance metrics.
          </p>

          <div className="text-center text-gray-500 py-12">
            Usage statistics coming soon
          </div>
        </div>
      )}
    </div>
  )
}
