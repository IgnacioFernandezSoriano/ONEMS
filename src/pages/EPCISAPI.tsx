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
    { id: 'overview', label: t('hc.epcisapi.tab_overview'), icon: Key },
    { id: 'documentation', label: t('hc.epcisapi.tab_documentation'), icon: BookOpen },
    { id: 'testing', label: t('hc.epcisapi.tab_testing'), icon: TestTube },
    { id: 'usage', label: t('hc.epcisapi.tab_usage'), icon: BarChart3 }
  ]

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">{t('hc.epcisapi.title')}</h1>
        <p className="text-gray-600">
          {t('hc.epcisapi.subtitle')}
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
              <h2 className="text-xl font-semibold text-gray-900">{t('hc.epcisapi.api_endpoint')}</h2>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('hc.epcisapi.base_url')}
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
                  {copied ? t('hc.epcisapi.copied') : t('hc.epcisapi.copy')}
                </button>
              </div>
            </div>
          </div>

          {/* Authentication */}
          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center gap-2 mb-4">
              <Shield className="w-5 h-5 text-blue-600" />
              <h2 className="text-xl font-semibold text-gray-900">{t('hc.epcisapi.authentication')}</h2>
            </div>

            <p className="text-gray-600 mb-4">
              {t('hc.epcisapi.auth_requirement')}
            </p>

            <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
              <div className="flex gap-2">
                <AlertCircle className="w-5 h-5 text-yellow-600 flex-shrink-0 mt-0.5" />
                <div className="text-sm text-yellow-800">
                  <p className="font-medium mb-1">{t('hc.epcisapi.security_note')}</p>
                  <p>{t('hc.epcisapi.security_note_text')}</p>
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
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">{t('hc.epcisapi.available_endpoints')}</h2>
            
            {/* Execute Pipeline Phase */}
            <div className="border border-gray-200 rounded-lg p-4 mb-4">
              <div className="flex items-center gap-2 mb-2">
                <span className="px-2 py-1 bg-blue-100 text-blue-700 text-xs font-semibold rounded">POST</span>
                <code className="text-sm font-mono">/rpc/rpc_execute_pipeline_phase</code>
              </div>
              <p className="text-gray-600 text-sm mb-4">{t('hc.epcisapi.execute_phase_desc')}</p>

              <h3 className="font-semibold text-gray-900 mb-2">{t('hc.epcisapi.parameters')}</h3>
              <table className="w-full text-sm mb-4">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="text-left p-2 font-semibold">{t('hc.epcisapi.parameter')}</th>
                    <th className="text-left p-2 font-semibold">{t('hc.epcisapi.type')}</th>
                    <th className="text-left p-2 font-semibold">{t('hc.epcisapi.description')}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_phase</td>
                    <td className="p-2">TEXT</td>
                    <td className="p-2">{t('hc.epcisapi.phase_values')}</td>
                  </tr>
                </tbody>
              </table>

              <h3 className="font-semibold text-gray-900 mb-2">{t('hc.epcisapi.example_request')}</h3>
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
              <p className="text-gray-600 text-sm mb-4">{t('hc.epcisapi.status_desc')}</p>

              <h3 className="font-semibold text-gray-900 mb-2">{t('hc.epcisapi.example_request')}</h3>
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
              <p className="text-gray-600 text-sm mb-4">{t('hc.epcisapi.query_desc')}</p>

              <h3 className="font-semibold text-gray-900 mb-2">{t('hc.epcisapi.parameters')}</h3>
              <table className="w-full text-sm mb-4">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="text-left p-2 font-semibold">{t('hc.epcisapi.parameter')}</th>
                    <th className="text-left p-2 font-semibold">{t('hc.epcisapi.type')}</th>
                    <th className="text-left p-2 font-semibold">{t('hc.epcisapi.required')}</th>
                    <th className="text-left p-2 font-semibold">{t('hc.epcisapi.description')}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_carrier_id</td>
                    <td className="p-2">UUID</td>
                    <td className="p-2">{t('hc.epcisapi.no')}</td>
                    <td className="p-2">{t('hc.epcisapi.filter_carrier')}</td>
                  </tr>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_product_id</td>
                    <td className="p-2">UUID</td>
                    <td className="p-2">{t('hc.epcisapi.no')}</td>
                    <td className="p-2">{t('hc.epcisapi.filter_product')}</td>
                  </tr>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_origin_city</td>
                    <td className="p-2">TEXT</td>
                    <td className="p-2">{t('hc.epcisapi.no')}</td>
                    <td className="p-2">{t('hc.epcisapi.filter_origin_city')}</td>
                  </tr>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_destination_city</td>
                    <td className="p-2">TEXT</td>
                    <td className="p-2">{t('hc.epcisapi.no')}</td>
                    <td className="p-2">{t('hc.epcisapi.filter_destination_city')}</td>
                  </tr>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_min_tags</td>
                    <td className="p-2">INTEGER</td>
                    <td className="p-2">{t('hc.epcisapi.no')}</td>
                    <td className="p-2">{t('hc.epcisapi.min_tags')}</td>
                  </tr>
                  <tr className="border-t">
                    <td className="p-2 font-mono">p_limit</td>
                    <td className="p-2">INTEGER</td>
                    <td className="p-2">{t('hc.epcisapi.no')}</td>
                    <td className="p-2">{t('hc.epcisapi.max_results')}</td>
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
              <p className="text-gray-600 text-sm mb-4">{t('hc.epcisapi.ingest_desc')}</p>

              <h3 className="font-semibold text-gray-900 mb-2">{t('hc.epcisapi.example_request')}</h3>
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
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">{t('hc.epcisapi.api_testing')}</h2>
          <p className="text-gray-600 mb-6">
            {t('hc.epcisapi.testing_text')}
          </p>

          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
            <div className="flex gap-2">
              <AlertCircle className="w-5 h-5 text-blue-600 flex-shrink-0 mt-0.5" />
              <div className="text-sm text-blue-800">
                <p className="font-medium mb-1">{t('hc.epcisapi.testing_tip')}</p>
                <p>{t('hc.epcisapi.testing_tip_text')}</p>
              </div>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'usage' && (
        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">{t('hc.epcisapi.api_usage')}</h2>
          <p className="text-gray-600 mb-6">
            {t('hc.epcisapi.usage_text')}
          </p>

          <div className="text-center text-gray-500 py-12">
            {t('hc.epcisapi.usage_coming_soon')}
          </div>
        </div>
      )}
    </div>
  )
}
