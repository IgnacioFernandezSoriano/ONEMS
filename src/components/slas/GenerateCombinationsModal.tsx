import { useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import type { GenerateCombinationsRequest, SLAType } from '@/lib/types_slas'
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
    sla_type: 'operational',
    postal_center_ids: [],
    from_postal_center_ids: [],
    to_postal_center_ids: [],
    expected_time_minutes: 60,
    time_unit: 'minutes',
    on_time_percentage: 95,
    warning_threshold: 90,
    critical_threshold: 80,
  })

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
    if (result) {
      onClose() // Refresh parent
    } else {
      onClose()
    }
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg p-6 max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        <h2 className="text-xl font-semibold mb-4">{t('slas.generate_combinations')}</h2>

        {result ? (
          <div className="space-y-4">
            <div className="bg-green-50 border border-green-200 rounded-md p-4">
              <p className="text-green-800">
                {t('slas.combinations_generated', { 
                  inserted: result.inserted_count,
                  skipped: result.skipped_count 
                })}
              </p>
            </div>
            <div className="flex justify-end">
              <button
                onClick={handleClose}
                className="px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700"
              >
                {t('common.close')}
              </button>
            </div>
          </div>
        ) : (
          <div className="space-y-6">
            {/* SLA Type */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('slas.sla_type')} *
              </label>
              <select
                value={formData.sla_type}
                onChange={(e) => setFormData({ ...formData, sla_type: e.target.value as SLAType })}
                className="w-full px-3 py-2 border border-gray-300 rounded-md"
              >
                <option value="operational">{t('slas.operational')}</option>
                <option value="distribution">{t('slas.distribution')}</option>
              </select>
            </div>

            {/* Operational: Select Postal Centers */}
            {formData.sla_type === 'operational' && (
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t('slas.select_postal_centers')} *
                </label>
                <div className="border border-gray-300 rounded-md p-3 max-h-48 overflow-y-auto">
                  {postalCenters.map(pc => (
                    <label key={pc.id} className="flex items-center mb-2">
                      <input
                        type="checkbox"
                        checked={formData.postal_center_ids?.includes(pc.id)}
                        onChange={(e) => {
                          const ids = formData.postal_center_ids || []
                          setFormData({
                            ...formData,
                            postal_center_ids: e.target.checked
                              ? [...ids, pc.id]
                              : ids.filter(id => id !== pc.id),
                          })
                        }}
                        className="mr-2"
                      />
                      <span className="text-sm">{pc.name}</span>
                    </label>
                  ))}
                </div>
                <p className="text-xs text-gray-500 mt-1">
                  {t('slas.operational_combinations_hint')}
                </p>
              </div>
            )}

            {/* Distribution: Select From/To Centers */}
            {formData.sla_type === 'distribution' && (
              <>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t('slas.from_postal_centers')} *
                  </label>
                  <div className="border border-gray-300 rounded-md p-3 max-h-48 overflow-y-auto">
                    {postalCenters.map(pc => (
                      <label key={pc.id} className="flex items-center mb-2">
                        <input
                          type="checkbox"
                          checked={formData.from_postal_center_ids?.includes(pc.id)}
                          onChange={(e) => {
                            const ids = formData.from_postal_center_ids || []
                            setFormData({
                              ...formData,
                              from_postal_center_ids: e.target.checked
                                ? [...ids, pc.id]
                                : ids.filter(id => id !== pc.id),
                            })
                          }}
                          className="mr-2"
                        />
                        <span className="text-sm">{pc.name}</span>
                      </label>
                    ))}
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t('slas.to_postal_centers')} *
                  </label>
                  <div className="border border-gray-300 rounded-md p-3 max-h-48 overflow-y-auto">
                    {postalCenters.map(pc => (
                      <label key={pc.id} className="flex items-center mb-2">
                        <input
                          type="checkbox"
                          checked={formData.to_postal_center_ids?.includes(pc.id)}
                          onChange={(e) => {
                            const ids = formData.to_postal_center_ids || []
                            setFormData({
                              ...formData,
                              to_postal_center_ids: e.target.checked
                                ? [...ids, pc.id]
                                : ids.filter(id => id !== pc.id),
                            })
                          }}
                          className="mr-2"
                        />
                        <span className="text-sm">{pc.name}</span>
                      </label>
                    ))}
                  </div>
                </div>
              </>
            )}

            {/* Default Values */}
            <div className="border-t pt-4">
              <h3 className="text-sm font-medium text-gray-700 mb-3">{t('slas.default_values')}</h3>
              
              <div className="grid grid-cols-2 gap-4 mb-4">
                <div>
                  <label className="block text-sm text-gray-700 mb-1">
                    {t('slas.expected_time')} *
                  </label>
                  <input
                    type="number"
                    value={formData.expected_time_minutes}
                    onChange={(e) => setFormData({ ...formData, expected_time_minutes: parseInt(e.target.value) })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md"
                    min="1"
                  />
                </div>

                <div>
                  <label className="block text-sm text-gray-700 mb-1">
                    {t('slas.time_unit')} *
                  </label>
                  <select
                    value={formData.time_unit}
                    onChange={(e) => setFormData({ ...formData, time_unit: e.target.value as 'minutes' | 'hours' })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md"
                  >
                    <option value="minutes">{t('common.minutes')}</option>
                    <option value="hours">{t('common.hours')}</option>
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div>
                  <label className="block text-sm text-gray-700 mb-1">
                    {t('slas.on_time_percentage')} *
                  </label>
                  <input
                    type="number"
                    value={formData.on_time_percentage}
                    onChange={(e) => setFormData({ ...formData, on_time_percentage: parseInt(e.target.value) })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md"
                    min="0"
                    max="100"
                  />
                </div>

                <div>
                  <label className="block text-sm text-gray-700 mb-1">
                    {t('slas.warning_threshold')} *
                  </label>
                  <input
                    type="number"
                    value={formData.warning_threshold}
                    onChange={(e) => setFormData({ ...formData, warning_threshold: parseInt(e.target.value) })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md"
                    min="0"
                    max="100"
                  />
                </div>

                <div>
                  <label className="block text-sm text-gray-700 mb-1">
                    {t('slas.critical_threshold')} *
                  </label>
                  <input
                    type="number"
                    value={formData.critical_threshold}
                    onChange={(e) => setFormData({ ...formData, critical_threshold: parseInt(e.target.value) })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md"
                    min="0"
                    max="100"
                  />
                </div>
              </div>
            </div>

            {/* Actions */}
            <div className="flex justify-end gap-3">
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2 text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
              >
                {t('common.cancel')}
              </button>
              <button
                onClick={handleGenerate}
                disabled={loading}
                className="px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50"
              >
                {loading ? t('common.generating') : t('common.generate')}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
