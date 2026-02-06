import { useState } from 'react'
import { PageHeader } from '@/components/common/PageHeader'
import { Button } from '@/components/common/Button'
import { useTranslation } from '@/hooks/useTranslation'
import { useGenerateEpcisData } from '@/hooks/useGenerateEpcisData'
import { useProcessRfidEvents } from '@/hooks/useProcessRfidEvents'
import { Database, CheckCircle, AlertCircle, Play } from 'lucide-react'

export function EpcisGenerator() {
  const { t } = useTranslation()
  const { generateData, loading, error } = useGenerateEpcisData()
  const { processEvents, loading: processing, result: processResult, error: processError } = useProcessRfidEvents()
  const [formData, setFormData] = useState({
    startDate: '',
    endDate: '',
    itemCount: '100',
    maxEventsPerItem: '10',
  })
  const [result, setResult] = useState<any>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setResult(null)

    const response = await generateData({
      startDate: formData.startDate,
      endDate: formData.endDate,
      itemCount: parseInt(formData.itemCount),
      maxEventsPerItem: parseInt(formData.maxEventsPerItem),
    })

    if (response) {
      setResult(response)
    }
  }

  const handleChange = (field: string, value: string) => {
    setFormData({ ...formData, [field]: value })
  }

  return (
    <div className="p-8">
      <PageHeader
        title={t('admin.epcis_generator')}
      />

      <div className="mt-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
        <div className="flex">
          <div className="flex-shrink-0">
            <Database className="h-5 w-5 text-blue-400" />
          </div>
          <div className="ml-3 flex-1">
            <h3 className="text-sm font-medium text-blue-800">
              {t('admin.about_epcis_generator')}
            </h3>
            <div className="mt-2 text-sm text-blue-700">
              <p>
                {t('admin.epcis_generator_info')}
              </p>
            </div>
          </div>
        </div>
      </div>

      <div className="mt-8 bg-white shadow rounded-lg">
        <form onSubmit={handleSubmit} className="p-6 space-y-6">
          {/* Date Range */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label htmlFor="startDate" className="block text-sm font-medium text-gray-700">
                {t('admin.epcis_start_date')}
              </label>
              <input
                type="date"
                id="startDate"
                value={formData.startDate}
                onChange={(e) => handleChange('startDate', e.target.value)}
                required
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>

            <div>
              <label htmlFor="endDate" className="block text-sm font-medium text-gray-700">
                {t('admin.epcis_end_date')}
              </label>
              <input
                type="date"
                id="endDate"
                value={formData.endDate}
                onChange={(e) => handleChange('endDate', e.target.value)}
                required
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
          </div>

          {/* Numeric Inputs */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label htmlFor="itemCount" className="block text-sm font-medium text-gray-700">
                {t('admin.epcis_item_count')}
              </label>
              <input
                type="number"
                id="itemCount"
                value={formData.itemCount}
                onChange={(e) => handleChange('itemCount', e.target.value)}
                required
                min="1"
                max="10000"
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
              <p className="mt-1 text-xs text-gray-500">
                {t('admin.epcis_item_count_help')}
              </p>
            </div>

            <div>
              <label htmlFor="maxEventsPerItem" className="block text-sm font-medium text-gray-700">
                {t('admin.epcis_max_events')}
              </label>
              <input
                type="number"
                id="maxEventsPerItem"
                value={formData.maxEventsPerItem}
                onChange={(e) => handleChange('maxEventsPerItem', e.target.value)}
                required
                min="2"
                max="50"
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
              <p className="mt-1 text-xs text-gray-500">
                {t('admin.epcis_max_events_help')}
              </p>
            </div>
          </div>

          {/* Submit Button */}
          <div className="flex justify-end">
            <Button
              type="submit"
              disabled={loading}
              className="inline-flex items-center"
            >
              {loading ? (
                <>
                  <div className="inline-block animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2"></div>
                  {t('admin.generating')}
                </>
              ) : (
                <>
                  <Database className="h-4 w-4 mr-2" />
                  {t('admin.epcis_generate_button')}
                </>
              )}
            </Button>
          </div>
        </form>
      </div>

      {/* Error Message */}
      {error && (
        <div className="mt-6 bg-red-50 border border-red-200 rounded-lg p-4">
          <div className="flex">
            <div className="flex-shrink-0">
              <AlertCircle className="h-5 w-5 text-red-400" />
            </div>
            <div className="ml-3">
              <h3 className="text-sm font-medium text-red-800">Error</h3>
              <p className="mt-1 text-sm text-red-700">{error}</p>
            </div>
          </div>
        </div>
      )}

      {/* Process Events Section */}
      <div className="mt-8 bg-white border border-gray-200 rounded-lg p-6">
        <h3 className="text-lg font-medium text-gray-900 mb-4">
          {t('admin.epcis_process_title')}
        </h3>
        <p className="text-sm text-gray-600 mb-4">
          {t('admin.epcis_process_description')}
        </p>
        <Button
          onClick={() => processEvents()}
          disabled={processing}
          className="inline-flex items-center"
        >
          {processing ? (
            <>
              <div className="inline-block animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2"></div>
              {t('admin.processing')}
            </>
          ) : (
            <>
              <Play className="h-4 w-4 mr-2" />
              {t('admin.epcis_process_button')}
            </>
          )}
        </Button>
      </div>

      {/* Process Error */}
      {processError && (
        <div className="mt-6 bg-red-50 border border-red-200 rounded-lg p-4">
          <div className="flex">
            <div className="flex-shrink-0">
              <AlertCircle className="h-5 w-5 text-red-400" />
            </div>
            <div className="ml-3">
              <h3 className="text-sm font-medium text-red-800">Error</h3>
              <p className="mt-1 text-sm text-red-700">{processError}</p>
            </div>
          </div>
        </div>
      )}

      {/* Process Success */}
      {processResult && processResult.success && (
        <div className="mt-6 bg-green-50 border border-green-200 rounded-lg p-6">
          <div className="flex items-start">
            <div className="flex-shrink-0">
              <CheckCircle className="h-6 w-6 text-green-400" />
            </div>
            <div className="ml-3 flex-1">
              <h3 className="text-lg font-medium text-green-800">
                {t('admin.epcis_process_success')}
              </h3>
              <p className="mt-2 text-sm text-green-700">{processResult.message}</p>
              
              <div className="mt-4 grid grid-cols-1 md:grid-cols-4 gap-4">
                <div className="bg-white rounded-lg p-4 border border-green-200">
                  <p className="text-sm font-medium text-gray-600">{t('admin.epcis_processed')}</p>
                  <p className="mt-1 text-2xl font-bold text-green-600">{processResult.stats.processed}</p>
                </div>
                <div className="bg-white rounded-lg p-4 border border-green-200">
                  <p className="text-sm font-medium text-gray-600">{t('admin.epcis_routes')}</p>
                  <p className="mt-1 text-2xl font-bold text-green-600">{processResult.stats.routes}</p>
                </div>
                <div className="bg-white rounded-lg p-4 border border-green-200">
                  <p className="text-sm font-medium text-gray-600">{t('admin.epcis_anomalies')}</p>
                  <p className="mt-1 text-2xl font-bold text-green-600">{processResult.stats.anomalies}</p>
                </div>
                <div className="bg-white rounded-lg p-4 border border-green-200">
                  <p className="text-sm font-medium text-gray-600">{t('admin.epcis_errors')}</p>
                  <p className="mt-1 text-2xl font-bold text-red-600">{processResult.stats.errors}</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Success Message with Stats */}
      {result && result.success && (
        <div className="mt-6 bg-green-50 border border-green-200 rounded-lg p-6">
          <div className="flex items-start">
            <div className="flex-shrink-0">
              <CheckCircle className="h-6 w-6 text-green-400" />
            </div>
            <div className="ml-3 flex-1">
              <h3 className="text-lg font-medium text-green-800">
                {t('admin.epcis_generation_success')}
              </h3>
              <p className="mt-2 text-sm text-green-700">{result.message}</p>
              
              <div className="mt-4 grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="bg-white rounded-lg p-4 border border-green-200">
                  <p className="text-sm font-medium text-gray-600">{t('admin.epcis_items_generated')}</p>
                  <p className="mt-1 text-2xl font-bold text-green-600">{result.stats.items}</p>
                </div>
                <div className="bg-white rounded-lg p-4 border border-green-200">
                  <p className="text-sm font-medium text-gray-600">{t('admin.epcis_total_events')}</p>
                  <p className="mt-1 text-2xl font-bold text-green-600">{result.stats.totalEvents}</p>
                </div>
                <div className="bg-white rounded-lg p-4 border border-green-200">
                  <p className="text-sm font-medium text-gray-600">{t('admin.epcis_avg_events')}</p>
                  <p className="mt-1 text-2xl font-bold text-green-600">{result.stats.avgEventsPerItem}</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
