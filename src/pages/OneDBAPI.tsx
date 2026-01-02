import { useState } from 'react'
import { useOneDBAPI } from '../hooks/useOneDBAPI'
import { useLocale } from '../contexts/LocaleContext'
import { Key, Copy, RefreshCw, AlertCircle, CheckCircle, Code, BookOpen, TestTube, BarChart3, Shield } from 'lucide-react'

export function OneDBAPI() {
  const { t } = useLocale()
  const { apiKey, loading, error, usageStats, generateApiKey, regenerateApiKey, refreshStats } = useOneDBAPI()
  const [activeTab, setActiveTab] = useState<'overview' | 'documentation' | 'testing' | 'usage'>('overview')
  const [copied, setCopied] = useState(false)
  const [generating, setGenerating] = useState(false)
  const [testStartDate, setTestStartDate] = useState('2024-01-01')
  const [testEndDate, setTestEndDate] = useState('2024-12-31')
  const [testLimit, setTestLimit] = useState('100')
  const [testResponse, setTestResponse] = useState<any>(null)
  const [testing, setTesting] = useState(false)

  const apiEndpoint = 'https://sehbnpgzqljrsqimwyuz.supabase.co/functions/v1/onedb-api'

  const handleCopyApiKey = () => {
    if (apiKey) {
      navigator.clipboard.writeText(apiKey.api_key)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    }
  }

  const handleCopyEndpoint = () => {
    navigator.clipboard.writeText(apiEndpoint)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const handleGenerateKey = async () => {
    try {
      setGenerating(true)
      await generateApiKey()
    } catch (err) {
      console.error('Failed to generate API key:', err)
    } finally {
      setGenerating(false)
    }
  }

  const handleRegenerateKey = async () => {
    if (!confirm(t('onedb_api.confirm_regenerate'))) return
    
    try {
      setGenerating(true)
      await regenerateApiKey()
    } catch (err) {
      console.error('Failed to regenerate API key:', err)
    } finally {
      setGenerating(false)
    }
  }

  const handleTestApi = async () => {
    if (!apiKey) return

    try {
      setTesting(true)
      const url = `${apiEndpoint}?start_date=${testStartDate}&end_date=${testEndDate}&limit=${testLimit}`
      
      const response = await fetch(url, {
        headers: {
          'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ4OTQzMTEsImV4cCI6MjA4MDQ3MDMxMX0.C-LsSmfOo38Tqc_PwP1c-nFyK1PeVj_mCBqanYsgoeg',
          'X-API-Key': apiKey.api_key,
          'Content-Type': 'application/json'
        }
      })

      const data = await response.json()
      setTestResponse(data)
      refreshStats()
    } catch (err: any) {
      setTestResponse({ success: false, error: err.message })
    } finally {
      setTesting(false)
    }
  }

  const tabs = [
    { id: 'overview', label: t('onedb_api.tab_overview'), icon: Key },
    { id: 'documentation', label: t('onedb_api.tab_documentation'), icon: BookOpen },
    { id: 'testing', label: t('onedb_api.tab_testing'), icon: TestTube },
    { id: 'usage', label: t('onedb_api.tab_usage'), icon: BarChart3 }
  ]

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">{t('onedb_api.title')}</h1>
        <p className="text-gray-600">{t('onedb_api.description')}</p>
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
          {/* API Credentials */}
          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center gap-2 mb-4">
              <Shield className="w-5 h-5 text-blue-600" />
              <h2 className="text-xl font-semibold text-gray-900">{t('onedb_api.credentials_section')}</h2>
            </div>

            {!apiKey ? (
              <div className="space-y-4">
                <p className="text-gray-600">{t('onedb_api.no_api_key')}</p>
                <button
                  onClick={handleGenerateKey}
                  disabled={generating || loading}
                  className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                >
                  <Key className="w-4 h-4" />
                  {generating ? t('onedb_api.generating') : t('onedb_api.generate_key')}
                </button>
              </div>
            ) : (
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t('onedb_api.api_key_label')}
                  </label>
                  <div className="flex gap-2">
                    <input
                      type="text"
                      value={apiKey.api_key}
                      readOnly
                      className="flex-1 px-4 py-2 border border-gray-300 rounded-lg bg-gray-50 font-mono text-sm"
                    />
                    <button
                      onClick={handleCopyApiKey}
                      className="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50 flex items-center gap-2"
                    >
                      {copied ? <CheckCircle className="w-4 h-4 text-green-600" /> : <Copy className="w-4 h-4" />}
                      {copied ? t('onedb_api.copied') : t('onedb_api.copy')}
                    </button>
                  </div>
                  <p className="text-xs text-gray-500 mt-2">
                    {t('onedb_api.created_at')}: {new Date(apiKey.created_at).toLocaleString()}
                  </p>
                </div>

                <button
                  onClick={handleRegenerateKey}
                  disabled={generating}
                  className="flex items-center gap-2 px-4 py-2 border border-red-300 text-red-700 rounded-lg hover:bg-red-50"
                >
                  <RefreshCw className="w-4 h-4" />
                  {t('onedb_api.regenerate_key')}
                </button>

                <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
                  <div className="flex gap-2">
                    <AlertCircle className="w-5 h-5 text-yellow-600 flex-shrink-0 mt-0.5" />
                    <div className="text-sm text-yellow-800">
                      <p className="font-medium mb-1">{t('onedb_api.security_warning_title')}</p>
                      <p>{t('onedb_api.security_warning_text')}</p>
                    </div>
                  </div>
                </div>
              </div>
            )}
          </div>

          {/* API Endpoint */}
          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center gap-2 mb-4">
              <Code className="w-5 h-5 text-blue-600" />
              <h2 className="text-xl font-semibold text-gray-900">{t('onedb_api.endpoint_section')}</h2>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('onedb_api.base_url')}
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
                  {copied ? t('onedb_api.copied') : t('onedb_api.copy')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'documentation' && (
        <div className="bg-white rounded-lg shadow p-6 space-y-8">
          {/* Authentication */}
          <section>
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">{t('onedb_api.authentication_title')}</h2>
            <p className="text-gray-600 mb-4">{t('onedb_api.authentication_description')}</p>
            
            <div className="bg-gray-50 rounded-lg p-4 font-mono text-sm space-y-2">
              <div className="text-gray-700">Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...</div>
              <div className="text-gray-700">X-API-Key: YOUR_API_KEY</div>
            </div>
            <p className="text-sm text-gray-500 mt-2">
              {t('onedb_api.auth_note')}
            </p>
          </section>

          {/* Endpoints */}
          <section>
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">{t('onedb_api.endpoints_title')}</h2>
            
            <div className="border border-gray-200 rounded-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <span className="px-2 py-1 bg-green-100 text-green-700 text-xs font-semibold rounded">GET</span>
                <code className="text-sm font-mono">/api/onedb/records</code>
              </div>
              <p className="text-gray-600 text-sm mb-4">{t('onedb_api.endpoint_description')}</p>

              <h3 className="font-semibold text-gray-900 mb-2">{t('onedb_api.query_parameters')}</h3>
              <table className="w-full text-sm">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="text-left p-2 font-semibold">{t('onedb_api.parameter')}</th>
                    <th className="text-left p-2 font-semibold">{t('onedb_api.type')}</th>
                    <th className="text-left p-2 font-semibold">{t('onedb_api.required')}</th>
                    <th className="text-left p-2 font-semibold">{t('onedb_api.description')}</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200">
                  <tr>
                    <td className="p-2 font-mono">start_date</td>
                    <td className="p-2">string</td>
                    <td className="p-2 text-red-600">{t('onedb_api.yes')}</td>
                    <td className="p-2">{t('onedb_api.start_date_desc')}</td>
                  </tr>
                  <tr>
                    <td className="p-2 font-mono">end_date</td>
                    <td className="p-2">string</td>
                    <td className="p-2 text-red-600">{t('onedb_api.yes')}</td>
                    <td className="p-2">{t('onedb_api.end_date_desc')}</td>
                  </tr>
                  <tr>
                    <td className="p-2 font-mono">limit</td>
                    <td className="p-2">integer</td>
                    <td className="p-2 text-gray-500">{t('onedb_api.no')}</td>
                    <td className="p-2">{t('onedb_api.limit_desc')}</td>
                  </tr>
                  <tr>
                    <td className="p-2 font-mono">offset</td>
                    <td className="p-2">integer</td>
                    <td className="p-2 text-gray-500">{t('onedb_api.no')}</td>
                    <td className="p-2">{t('onedb_api.offset_desc')}</td>
                  </tr>
                </tbody>
              </table>
              
              <div className="mt-4 p-4 bg-blue-50 border border-blue-200 rounded-lg">
                <p className="text-sm text-blue-800">
                  <strong>ℹ️ {t('onedb_api.max_records_note')}</strong>
                </p>
              </div>
            </div>
          </section>

          {/* Examples */}
          <section>
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">{t('onedb_api.examples_title')}</h2>

            {/* cURL Example */}
            <div className="mb-6">
              <h3 className="font-semibold text-gray-900 mb-2">cURL</h3>
              <div className="bg-gray-900 text-gray-100 rounded-lg p-4 font-mono text-sm overflow-x-auto">
                <pre>{`curl -X GET "${apiEndpoint}?start_date=2024-01-01&end_date=2024-12-31&limit=100" \\
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \\
  -H "X-API-Key: YOUR_API_KEY" \\
  -H "Content-Type: application/json"`}</pre>
              </div>
            </div>

            {/* Python Example */}
            <div className="mb-6">
              <h3 className="font-semibold text-gray-900 mb-2">Python</h3>
              <div className="bg-gray-900 text-gray-100 rounded-lg p-4 font-mono text-sm overflow-x-auto">
                <pre>{`import requests

url = "${apiEndpoint}"
headers = {
    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "X-API-Key": "YOUR_API_KEY",
    "Content-Type": "application/json"
}
params = {
    "start_date": "2024-01-01",
    "end_date": "2024-12-31",
    "limit": 100
}

response = requests.get(url, headers=headers, params=params)
data = response.json()

if data["success"]:
    print(f"Total records: {data['pagination']['total']}")
    for record in data["data"]:
        print(record)
else:
    print(f"Error: {data['error']}")`}</pre>
              </div>
            </div>

            {/* JavaScript Example */}
            <div className="mb-6">
              <h3 className="font-semibold text-gray-900 mb-2">JavaScript</h3>
              <div className="bg-gray-900 text-gray-100 rounded-lg p-4 font-mono text-sm overflow-x-auto">
                <pre>{`const url = new URL("${apiEndpoint}");
url.searchParams.append("start_date", "2024-01-01");
url.searchParams.append("end_date", "2024-12-31");
url.searchParams.append("limit", "100");

const response = await fetch(url, {
  headers: {
    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "X-API-Key": "YOUR_API_KEY",
    "Content-Type": "application/json"
  }
});

const data = await response.json();

if (data.success) {
  console.log(\`Total records: \${data.pagination.total}\`);
  data.data.forEach(record => console.log(record));
} else {
  console.error(\`Error: \${data.error}\`);
}`}</pre>
              </div>
            </div>
          </section>

          {/* Response Format */}
          <section>
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">{t('onedb_api.response_format')}</h2>
            <div className="bg-gray-900 text-gray-100 rounded-lg p-4 font-mono text-sm overflow-x-auto">
              <pre>{`{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "sent": "2024-06-15",
      "origin_city": "Madrid",
      "destination_city": "Barcelona",
      "carrier": "Carrier A",
      "product": "Express",
      "material": "Material X",
      "quantity": 100,
      // ... all other fields from ONE DB
    }
  ],
  "pagination": {
    "total": 5420,
    "limit": 100,
    "offset": 0,
    "has_more": true
  },
  "meta": {
    "response_time_ms": 245,
    "rate_limit": {
      "limit": 10,
      "remaining": 9,
      "reset_at": "2024-01-01T12:01:00Z"
    }
  }
}`}</pre>
            </div>
          </section>

          {/* Rate Limiting */}
          <section>
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">{t('onedb_api.rate_limiting_title')}</h2>
            <p className="text-gray-600 mb-4">{t('onedb_api.rate_limiting_description')}</p>
            
            <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
              <p className="text-blue-800 font-semibold">{t('onedb_api.rate_limit_info')}</p>
            </div>
          </section>

          {/* Error Codes */}
          <section>
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">{t('onedb_api.error_codes_title')}</h2>
            <table className="w-full text-sm border border-gray-200 rounded-lg">
              <thead className="bg-gray-50">
                <tr>
                  <th className="text-left p-3 font-semibold">{t('onedb_api.status_code')}</th>
                  <th className="text-left p-3 font-semibold">{t('onedb_api.description')}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                <tr>
                  <td className="p-3 font-mono">200</td>
                  <td className="p-3">{t('onedb_api.status_200')}</td>
                </tr>
                <tr>
                  <td className="p-3 font-mono">400</td>
                  <td className="p-3">{t('onedb_api.status_400')}</td>
                </tr>
                <tr>
                  <td className="p-3 font-mono">401</td>
                  <td className="p-3">{t('onedb_api.status_401')}</td>
                </tr>
                <tr>
                  <td className="p-3 font-mono">429</td>
                  <td className="p-3">{t('onedb_api.status_429')}</td>
                </tr>
                <tr>
                  <td className="p-3 font-mono">500</td>
                  <td className="p-3">{t('onedb_api.status_500')}</td>
                </tr>
              </tbody>
            </table>
          </section>
        </div>
      )}

      {activeTab === 'testing' && (
        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">{t('onedb_api.api_tester_title')}</h2>
          
          {!apiKey ? (
            <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
              <p className="text-yellow-800">{t('onedb_api.generate_key_first')}</p>
            </div>
          ) : (
            <div className="space-y-6">
              {/* Test Form */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t('onedb_api.start_date')}
                  </label>
                  <input
                    type="date"
                    value={testStartDate}
                    onChange={(e) => setTestStartDate(e.target.value)}
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t('onedb_api.end_date')}
                  </label>
                  <input
                    type="date"
                    value={testEndDate}
                    onChange={(e) => setTestEndDate(e.target.value)}
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t('onedb_api.limit')}
                  </label>
                  <input
                    type="number"
                    value={testLimit}
                    onChange={(e) => setTestLimit(e.target.value)}
                    min="1"
                    max="1000"
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg"
                  />
                </div>
              </div>

              <button
                onClick={handleTestApi}
                disabled={testing}
                className="flex items-center gap-2 px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
              >
                <TestTube className="w-5 h-5" />
                {testing ? t('onedb_api.testing') : t('onedb_api.test_api')}
              </button>

              {/* Response */}
              {testResponse && (
                <div>
                  <h3 className="font-semibold text-gray-900 mb-2">{t('onedb_api.response')}</h3>
                  <div className="bg-gray-900 text-gray-100 rounded-lg p-4 font-mono text-sm overflow-x-auto max-h-96">
                    <pre>{JSON.stringify(testResponse, null, 2)}</pre>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {activeTab === 'usage' && (
        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">{t('onedb_api.usage_statistics')}</h2>
          
          {!apiKey ? (
            <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
              <p className="text-yellow-800">{t('onedb_api.generate_key_first')}</p>
            </div>
          ) : usageStats ? (
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              <div className="bg-blue-50 rounded-lg p-6">
                <div className="text-blue-600 text-sm font-medium mb-2">{t('onedb_api.total_calls_month')}</div>
                <div className="text-3xl font-bold text-blue-900">{usageStats.total_calls_this_month}</div>
              </div>
              
              <div className="bg-green-50 rounded-lg p-6">
                <div className="text-green-600 text-sm font-medium mb-2">{t('onedb_api.calls_last_hour')}</div>
                <div className="text-3xl font-bold text-green-900">{usageStats.calls_last_hour}</div>
                <div className="text-xs text-green-600 mt-1">{t('onedb_api.limit_10_per_minute')}</div>
              </div>
              
              <div className="bg-purple-50 rounded-lg p-6">
                <div className="text-purple-600 text-sm font-medium mb-2">{t('onedb_api.last_call')}</div>
                <div className="text-lg font-semibold text-purple-900">
                  {usageStats.last_call 
                    ? new Date(usageStats.last_call).toLocaleString()
                    : t('onedb_api.never')}
                </div>
              </div>
            </div>
          ) : (
            <p className="text-gray-600">{t('onedb_api.loading_stats')}</p>
          )}
        </div>
      )}
    </div>
  )
}
