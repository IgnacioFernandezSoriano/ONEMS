import { useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import type { SLAFormData, SLAType } from '@/lib/types_slas'
import type { PostalCenter } from '@/lib/types_postal_centers'

interface SLAFormProps {
  postalCenters: PostalCenter[]
  initialData?: Partial<SLAFormData>
  onSubmit: (data: SLAFormData) => Promise<void>
  onCancel: () => void
}

export function SLAForm({ postalCenters, initialData, onSubmit, onCancel }: SLAFormProps) {
  const { t } = useTranslation()
  const [loading, setLoading] = useState(false)
  const [formData, setFormData] = useState<SLAFormData>({
    sla_type: initialData?.sla_type || 'operational',
    expected_time_minutes: initialData?.expected_time_minutes || 60,
    time_unit: initialData?.time_unit || 'minutes',
    on_time_percentage: initialData?.on_time_percentage || 95,
    warning_threshold: initialData?.warning_threshold || 90,
    critical_threshold: initialData?.critical_threshold || 80,
    is_active: initialData?.is_active ?? true,
    ...initialData,
  })

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      await onSubmit(formData)
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {/* SLA Type */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">
          {t('slas.sla_type')} *
        </label>
        <select
          value={formData.sla_type}
          onChange={(e) => setFormData({ ...formData, sla_type: e.target.value as SLAType })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          required
        >
          <option value="operational">{t('slas.operational')}</option>
          <option value="distribution">{t('slas.distribution')}</option>
        </select>
      </div>

      {/* Operational SLA Fields */}
      {formData.sla_type === 'operational' && (
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            {t('postal_centers.postal_center')} *
          </label>
          <select
            value={formData.postal_center_id || ''}
            onChange={(e) => setFormData({ 
              ...formData, 
              postal_center_id: e.target.value,
            })}
            className="w-full px-3 py-2 border border-gray-300 rounded-md"
            required
          >
            <option value="">{t('common.select')}</option>
            {postalCenters.map(pc => (
              <option key={pc.id} value={pc.id}>{pc.name}</option>
            ))}
          </select>
          <p className="mt-1 text-sm text-gray-500">
            {t('slas.operational_sla_description')}
          </p>
        </div>
      )}

      {/* Distribution SLA Fields */}
      {formData.sla_type === 'distribution' && (
        <>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              {t('slas.from_postal_center')} *
            </label>
            <select
              value={formData.from_postal_center_id || ''}
              onChange={(e) => setFormData({ ...formData, from_postal_center_id: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
              required
            >
              <option value="">{t('common.select')}</option>
              {postalCenters.map(pc => (
                <option key={pc.id} value={pc.id}>{pc.name}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              {t('slas.to_postal_center')} *
            </label>
            <select
              value={formData.to_postal_center_id || ''}
              onChange={(e) => setFormData({ ...formData, to_postal_center_id: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
              required
            >
              <option value="">{t('common.select')}</option>
              {postalCenters
                .filter(pc => pc.id !== formData.from_postal_center_id)
                .map(pc => (
                  <option key={pc.id} value={pc.id}>{pc.name}</option>
                ))}
            </select>
          </div>
        </>
      )}

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
            required
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
          {t('slas.on_time_percentage')} *
        </label>
        <input
          type="number"
          min="0"
          max="100"
          value={formData.on_time_percentage}
          onChange={(e) => setFormData({ ...formData, on_time_percentage: parseInt(e.target.value) })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          required
        />
      </div>

      {/* Warning Threshold */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">
          {t('slas.warning_threshold')} *
        </label>
        <input
          type="number"
          min="0"
          max="100"
          value={formData.warning_threshold}
          onChange={(e) => setFormData({ ...formData, warning_threshold: parseInt(e.target.value) })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          required
        />
      </div>

      {/* Critical Threshold */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">
          {t('slas.critical_threshold')} *
        </label>
        <input
          type="number"
          min="0"
          max="100"
          value={formData.critical_threshold}
          onChange={(e) => setFormData({ ...formData, critical_threshold: parseInt(e.target.value) })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          required
        />
      </div>

      {/* Active Status */}
      <div className="flex items-center">
        <input
          type="checkbox"
          id="is_active"
          checked={formData.is_active}
          onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
          className="h-4 w-4 text-blue-600 border-gray-300 rounded"
        />
        <label htmlFor="is_active" className="ml-2 text-sm text-gray-700">
          {t('common.active')}
        </label>
      </div>

      {/* Actions */}
      <div className="flex justify-end gap-2 pt-4 border-t">
        <button
          type="button"
          onClick={onCancel}
          className="px-4 py-2 text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
          disabled={loading}
        >
          {t('common.cancel')}
        </button>
        <button
          type="submit"
          className="px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50"
          disabled={loading}
        >
          {loading ? t('common.saving') : t('common.save')}
        </button>
      </div>
    </form>
  )
}
