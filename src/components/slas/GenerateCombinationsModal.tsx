import { useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import type { GenerateCombinationsRequest } from '@/lib/types_slas'
import type { PostalCenter } from '@/lib/types_postal_centers'

interface GenerateCombinationsModalProps {
  postalCenters: PostalCenter[]
  onGenerate: (request: GenerateCombinationsRequest) => Promise<{ inserted_count: number; skipped_count: number }>
  onClose: () => void
}

export function GenerateCombinationsModal({ postalCenters, onGenerate, onClose }: GenerateCombinationsModalProps) {
  const { t } = useTranslation()
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<{ inserted_count: number; skipped_count: number } | null>(null)
  const [formData, setFormData] = useState<GenerateCombinationsRequest>({
    expected_time_minutes: 60,
    time_unit: 'minutes',
    on_time_percentage: 95,
    warning_threshold: 90,
    critical_threshold: 80,
  })

  const totalOperationalSLAs = postalCenters.length
  const totalDistributionSLAs = postalCenters.length * (postalCenters.length - 1)
  const totalSLAs = totalOperationalSLAs + totalDistributionSLAs

  const handleGenerate = async () => {
    setLoading(true)
    try {
      const res = await onGenerate(formData)
      setResult(res)
    } finally {
      setLoading(false)
    }
  }

  const handleClose = () => {
    onClose()
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg p-6 max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        <h2 className="text-xl font-semibold mb-4">{t('slas.generate_network_slas')}</h2>

        {!result ? (
          <>
            {/* Network Summary */}
            <div className="mb-6 p-4 bg-blue-50 rounded-lg">
              <h3 className="font-medium text-blue-900 mb-2">{t('slas.network_summary')}</h3>
              <div className="space-y-1 text-sm text-blue-800">
                <p>• {t('slas.active_postal_centers')}: <strong>{postalCenters.length}</strong></p>
                <p>• {t('slas.operational_slas_to_generate')}: <strong>{totalOperationalSLAs}</strong> ({t('slas.one_per_center')})</p>
                <p>• {t('slas.distribution_slas_to_generate')}: <strong>{totalDistributionSLAs}</strong> ({t('slas.all_center_pairs')})</p>
                <p className="pt-2 border-t border-blue-200">• <strong>{t('common.total')}: {totalSLAs} SLAs</strong></p>
              </div>
            </div>

            {/* Default Values Form */}
            <div className="space-y-4 mb-6">
              <h3 className="font-medium text-gray-900">{t('slas.default_values')}</h3>

              {/* Expected Time */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t('slas.expected_time')} *
                </label>
                <div className="flex gap-2">
                  <input
                    type="number"
                    min="1"
                    value={formData.expected_time_minutes}
                    onChange={(e) => setFormData({ ...formData, expected_time_minutes: parseInt(e.target.value) })}
                    className="flex-1 px-3 py-2 border border-gray-300 rounded-md"
                  />
                  <select
                    value={formData.time_unit}
                    onChange={(e) => setFormData({ ...formData, time_unit: e.target.value as 'minutes' | 'hours' })}
                    className="px-3 py-2 border border-gray-300 rounded-md"
                  >
                    <option value="minutes">{t('common.minutes')}</option>
                    <option value="hours">{t('common.hours')}</option>
                  </select>
                </div>
              </div>

              {/* On-Time Percentage */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t('slas.on_time_percentage')} (%)
                </label>
                <input
                  type="number"
                  min="0"
                  max="100"
                  value={formData.on_time_percentage}
                  onChange={(e) => setFormData({ ...formData, on_time_percentage: parseInt(e.target.value) })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md"
                />
              </div>

              {/* Warning Threshold */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t('slas.warning_threshold')} (%)
                </label>
                <input
                  type="number"
                  min="0"
                  max="100"
                  value={formData.warning_threshold}
                  onChange={(e) => setFormData({ ...formData, warning_threshold: parseInt(e.target.value) })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md"
                />
              </div>

              {/* Critical Threshold */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t('slas.critical_threshold')} (%)
                </label>
                <input
                  type="number"
                  min="0"
                  max="100"
                  value={formData.critical_threshold}
                  onChange={(e) => setFormData({ ...formData, critical_threshold: parseInt(e.target.value) })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md"
                />
              </div>
            </div>

            {/* Actions */}
            <div className="flex justify-end gap-2 pt-4 border-t">
              <button
                onClick={handleClose}
                className="px-4 py-2 text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
                disabled={loading}
              >
                {t('common.cancel')}
              </button>
              <button
                onClick={handleGenerate}
                className="px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50"
                disabled={loading || postalCenters.length === 0}
              >
                {loading ? t('common.generating') : t('slas.generate_network_slas')}
              </button>
            </div>
          </>
        ) : (
          <>
            {/* Success Result */}
            <div className="mb-6 p-4 bg-green-50 rounded-lg">
              <h3 className="font-medium text-green-900 mb-2">✅ {t('common.success')}</h3>
              <div className="space-y-1 text-sm text-green-800">
                <p>• {t('slas.slas_created')}: <strong>{result.inserted_count}</strong></p>
                <p>• {t('slas.slas_skipped')}: <strong>{result.skipped_count}</strong> ({t('slas.already_exist')})</p>
              </div>
            </div>

            {/* Close Button */}
            <div className="flex justify-end">
              <button
                onClick={handleClose}
                className="px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700"
              >
                {t('common.close')}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
