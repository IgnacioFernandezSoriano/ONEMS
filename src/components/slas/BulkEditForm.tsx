import { useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import type { SLAFormData } from '@/lib/types_slas'

interface BulkEditFormProps {
  selectedCount: number
  onSubmit: (data: Partial<SLAFormData>) => Promise<void>
  onCancel: () => void
}

export function BulkEditForm({ selectedCount, onSubmit, onCancel }: BulkEditFormProps) {
  const { t } = useTranslation()
  const [loading, setLoading] = useState(false)
  const [formData, setFormData] = useState<{
    expected_time_value?: number
    expected_time_unit?: 'minutes' | 'hours' | 'days'
    on_time_percentage?: number
    warning_threshold?: number
    critical_threshold?: number
    is_active?: boolean
  }>({})

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    
    try {
      const updateData: Partial<SLAFormData> = {}
      
      // Convert time to minutes if provided
      if (formData.expected_time_value !== undefined && formData.expected_time_unit) {
        let minutes = formData.expected_time_value
        if (formData.expected_time_unit === 'hours') {
          minutes = minutes * 60
        } else if (formData.expected_time_unit === 'days') {
          minutes = minutes * 24 * 60
        }
        updateData.expected_time_minutes = minutes
      }
      
      // Add other fields if provided
      if (formData.on_time_percentage !== undefined) {
        updateData.on_time_percentage = formData.on_time_percentage
      }
      if (formData.warning_threshold !== undefined) {
        updateData.warning_threshold = formData.warning_threshold
      }
      if (formData.critical_threshold !== undefined) {
        updateData.critical_threshold = formData.critical_threshold
      }
      if (formData.is_active !== undefined) {
        updateData.is_active = formData.is_active
      }
      
      await onSubmit(updateData)
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <div className="p-4 bg-blue-50 rounded-lg">
        <p className="text-sm text-blue-800">
          {t('common.bulk_edit_description', { count: selectedCount })}
        </p>
      </div>

      {/* Expected Time */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">
          {t('slas.expected_time')}
        </label>
        <div className="flex gap-2">
          <input
            type="number"
            min="0"
            step="0.001"
            value={formData.expected_time_value || ''}
            onChange={(e) => setFormData({ 
              ...formData, 
              expected_time_value: e.target.value ? parseFloat(e.target.value) : undefined,
              expected_time_unit: formData.expected_time_unit || 'days'
            })}
            className="flex-1 px-3 py-2 border border-gray-300 rounded-md"
            placeholder={t('common.leave_empty_to_skip')}
          />
          <select
            value={formData.expected_time_unit || 'days'}
            onChange={(e) => setFormData({ 
              ...formData, 
              expected_time_unit: e.target.value as 'minutes' | 'hours' | 'days' 
            })}
            className="px-3 py-2 border border-gray-300 rounded-md"
            disabled={formData.expected_time_value === undefined}
          >
            <option value="minutes">{t('common.minutes')}</option>
            <option value="hours">{t('common.hours')}</option>
            <option value="days">{t('common.days')}</option>
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
          value={formData.on_time_percentage || ''}
          onChange={(e) => setFormData({ 
            ...formData, 
            on_time_percentage: e.target.value ? parseInt(e.target.value) : undefined 
          })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder={t('common.leave_empty_to_skip')}
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
          value={formData.warning_threshold || ''}
          onChange={(e) => setFormData({ 
            ...formData, 
            warning_threshold: e.target.value ? parseInt(e.target.value) : undefined 
          })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder={t('common.leave_empty_to_skip')}
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
          value={formData.critical_threshold || ''}
          onChange={(e) => setFormData({ 
            ...formData, 
            critical_threshold: e.target.value ? parseInt(e.target.value) : undefined 
          })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder={t('common.leave_empty_to_skip')}
        />
      </div>

      {/* Active Status */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">
          {t('common.status')}
        </label>
        <select
          value={formData.is_active === undefined ? '' : formData.is_active ? 'true' : 'false'}
          onChange={(e) => setFormData({ 
            ...formData, 
            is_active: e.target.value === '' ? undefined : e.target.value === 'true' 
          })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
        >
          <option value="">{t('common.leave_empty_to_skip')}</option>
          <option value="true">{t('common.active')}</option>
          <option value="false">{t('common.inactive')}</option>
        </select>
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
