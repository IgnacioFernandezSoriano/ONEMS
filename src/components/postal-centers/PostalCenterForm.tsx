import { useState, useEffect } from 'react'
import { Button } from '@/components/common/Button'
import type { PostalCenter, PostalCenterFormData } from '@/lib/types_postal_centers'
import { useTranslation } from '@/hooks/useTranslation'

interface PostalCenterFormProps {
  postalCenter?: PostalCenter | null
  onSubmit: (data: PostalCenterFormData) => Promise<void>
  onCancel: () => void
}

export function PostalCenterForm({ postalCenter, onSubmit, onCancel }: PostalCenterFormProps) {
  const { t } = useTranslation()
  const [formData, setFormData] = useState<PostalCenterFormData>({
    code: '',
    name: '',
    description: '',
    opening_hour: '08:00:00',
    cutoff_time: '18:00:00',
    calculation_mode: 'natural_days',
    mixed_reader_gap_minutes: 10,
    is_active: true
  })
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (postalCenter) {
      setFormData({
        code: postalCenter.code,
        name: postalCenter.name,
        description: postalCenter.description || '',
        opening_hour: postalCenter.opening_hour || '08:00:00',
        cutoff_time: postalCenter.cutoff_time || '18:00:00',
        calculation_mode: postalCenter.calculation_mode || 'natural_days',
        mixed_reader_gap_minutes: postalCenter.mixed_reader_gap_minutes || 10,
        is_active: postalCenter.is_active
      })
    }
  }, [postalCenter])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setSubmitting(true)

    try {
      await onSubmit(formData)
    } catch (err: any) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
          {error}
        </div>
      )}

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('postal_centers.code')} *
        </label>
        <input
          type="text"
          value={formData.code}
          onChange={(e) => setFormData({ ...formData, code: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          required
          disabled={!!postalCenter} // Code cannot be changed after creation
          placeholder="HUB_MADRID"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('postal_centers.name')} *
        </label>
        <input
          type="text"
          value={formData.name}
          onChange={(e) => setFormData({ ...formData, name: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          required
          placeholder="Madrid Hub"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('postal_centers.description')}
        </label>
        <textarea
          value={formData.description}
          onChange={(e) => setFormData({ ...formData, description: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          rows={3}
          placeholder="Main distribution hub for Madrid region"
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('postal_centers.opening_hour')}
          </label>
          <input
            type="time"
            value={formData.opening_hour?.substring(0, 5) || ''}
            onChange={(e) => setFormData({ ...formData, opening_hour: e.target.value + ':00' })}
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('postal_centers.cutoff_time')}
          </label>
          <input
            type="time"
            value={formData.cutoff_time?.substring(0, 5) || ''}
            onChange={(e) => setFormData({ ...formData, cutoff_time: e.target.value + ':00' })}
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('postal_centers.calculation_mode')}
        </label>
        <select
          value={formData.calculation_mode || ''}
          onChange={(e) => setFormData({ ...formData, calculation_mode: e.target.value as 'natural_days' | 'working_days' | null })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="">-- {t('postal_centers.inherit_from_account')} --</option>
          <option value="natural_days">{t('postal_centers.natural_days')}</option>
          <option value="working_days">{t('postal_centers.working_days')}</option>
        </select>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('postal_centers.mixed_reader_gap_minutes')}
        </label>
        <input
          type="number"
          value={formData.mixed_reader_gap_minutes || ''}
          onChange={(e) => setFormData({ ...formData, mixed_reader_gap_minutes: e.target.value ? parseInt(e.target.value) : null })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          min="1"
          placeholder="10"
        />
        <p className="text-xs text-gray-500 mt-1">
          {t('postal_centers.mixed_reader_gap_help')}
        </p>
      </div>

      <div className="flex items-center">
        <input
          type="checkbox"
          id="is_active"
          checked={formData.is_active}
          onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
          className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
        />
        <label htmlFor="is_active" className="ml-2 block text-sm text-gray-700">
          {t('postal_centers.is_active')}
        </label>
      </div>

      <div className="flex justify-end gap-2 pt-4">
        <Button
          type="button"
          variant="secondary"
          onClick={onCancel}
          disabled={submitting}
        >
          {t('common.cancel')}
        </Button>
        <Button
          type="submit"
          disabled={submitting}
        >
          {submitting ? t('common.saving') : (postalCenter ? t('common.update') : t('common.create'))}
        </Button>
      </div>
    </form>
  )
}
