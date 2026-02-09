import { useState, useEffect } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import type { SLAFormData, SLAType } from '@/lib/types_slas'
import type { PostalCenter, Reader } from '@/lib/types_postal_centers'

interface SLAFormProps {
  postalCenters: PostalCenter[]
  readers: Reader[]
  initialData?: Partial<SLAFormData>
  onSubmit: (data: SLAFormData) => Promise<void>
  onCancel: () => void
}

export function SLAForm({ postalCenters, readers, initialData, onSubmit, onCancel }: SLAFormProps) {
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

  // Filter readers by selected postal center for operational SLAs
  const filteredReaders = formData.postal_center_id
    ? readers.filter(r => r.postal_center_id === formData.postal_center_id)
    : []

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
        <>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              {t('postal_centers.postal_center')} *
            </label>
            <select
              value={formData.postal_center_id || ''}
              onChange={(e) => setFormData({ 
                ...formData, 
                postal_center_id: e.target.value,
                from_reader_id: undefined,
                to_reader_id: undefined,
              })}
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
              {t('slas.from_reader')} *
            </label>
            <select
              value={formData.from_reader_id || ''}
              onChange={(e) => setFormData({ ...formData, from_reader_id: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
              required
              disabled={!formData.postal_center_id}
            >
              <option value="">{t('common.select')}</option>
              {filteredReaders.map(r => (
                <option key={r.id} value={r.id}>
                  {r.reader_id} ({t(`readers.${r.type}`)})
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              {t('slas.to_reader')} *
            </label>
            <select
              value={formData.to_reader_id || ''}
              onChange={(e) => setFormData({ ...formData, to_reader_id: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
              required
              disabled={!formData.postal_center_id}
            >
              <option value="">{t('common.select')}</option>
              {filteredReaders
                .filter(r => r.id !== formData.from_reader_id)
                .map(r => (
                  <option key={r.id} value={r.id}>
                    {r.reader_id} ({t(`readers.${r.type}`)})
                  </option>
                ))}
            </select>
          </div>
        </>
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

      {/* Common Fields */}
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            {t('slas.expected_time')} *
          </label>
          <input
            type="number"
            value={formData.expected_time_minutes}
            onChange={(e) => setFormData({ ...formData, expected_time_minutes: parseInt(e.target.value) })}
            className="w-full px-3 py-2 border border-gray-300 rounded-md"
            required
            min="1"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            {t('slas.time_unit')} *
          </label>
          <select
            value={formData.time_unit}
            onChange={(e) => setFormData({ ...formData, time_unit: e.target.value as 'minutes' | 'hours' })}
            className="w-full px-3 py-2 border border-gray-300 rounded-md"
            required
          >
            <option value="minutes">{t('common.minutes')}</option>
            <option value="hours">{t('common.hours')}</option>
          </select>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            {t('slas.on_time_percentage')} *
          </label>
          <input
            type="number"
            value={formData.on_time_percentage}
            onChange={(e) => setFormData({ ...formData, on_time_percentage: parseInt(e.target.value) })}
            className="w-full px-3 py-2 border border-gray-300 rounded-md"
            required
            min="0"
            max="100"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            {t('slas.warning_threshold')} *
          </label>
          <input
            type="number"
            value={formData.warning_threshold}
            onChange={(e) => setFormData({ ...formData, warning_threshold: parseInt(e.target.value) })}
            className="w-full px-3 py-2 border border-gray-300 rounded-md"
            required
            min="0"
            max="100"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            {t('slas.critical_threshold')} *
          </label>
          <input
            type="number"
            value={formData.critical_threshold}
            onChange={(e) => setFormData({ ...formData, critical_threshold: parseInt(e.target.value) })}
            className="w-full px-3 py-2 border border-gray-300 rounded-md"
            required
            min="0"
            max="100"
          />
        </div>
      </div>

      <div className="flex items-center">
        <input
          type="checkbox"
          checked={formData.is_active}
          onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
          className="mr-2"
        />
        <label className="text-sm text-gray-700">{t('common.active')}</label>
      </div>

      {/* Actions */}
      <div className="flex justify-end gap-3">
        <button
          type="button"
          onClick={onCancel}
          className="px-4 py-2 text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          {t('common.cancel')}
        </button>
        <button
          type="submit"
          disabled={loading}
          className="px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50"
        >
          {loading ? t('common.saving') : t('common.save')}
        </button>
      </div>
    </form>
  )
}
