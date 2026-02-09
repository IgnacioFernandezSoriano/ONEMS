import { useState, useEffect } from 'react'
import { Button } from '@/components/common/Button'
import { Trash2, Plus } from 'lucide-react'
import type { PostalCenter, PostalCenterFormData } from '@/lib/types_postal_centers'
import { useTranslation } from '@/hooks/useTranslation'
import { useAccountConfig } from '@/hooks/useAccountConfig'

interface PostalCenterFormProps {
  postalCenter?: PostalCenter | null
  onSubmit: (data: PostalCenterFormData & { holidays?: { date: string; reason: string }[] }) => Promise<void>
  onCancel: () => void
}

interface Holiday {
  date: string
  reason: string
}

export function PostalCenterForm({ postalCenter, onSubmit, onCancel }: PostalCenterFormProps) {
  const { t } = useTranslation()
  const { config, nonWorkingDays: accountHolidays } = useAccountConfig()
  
  const [formData, setFormData] = useState<PostalCenterFormData>({
    code: '',
    name: '',
    description: '',
    calculation_mode: null,
    mixed_reader_gap_minutes: null,
    is_active: true
  })
  
  const [centerHolidays, setCenterHolidays] = useState<Holiday[]>([])
  const [newHoliday, setNewHoliday] = useState<Holiday>({ date: '', reason: '' })
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (postalCenter) {
      setFormData({
        code: postalCenter.code,
        name: postalCenter.name,
        description: postalCenter.description || '',
        calculation_mode: postalCenter.calculation_mode || null,
        mixed_reader_gap_minutes: postalCenter.mixed_reader_gap_minutes || null,
        is_active: postalCenter.is_active
      })
      // TODO: Load center-specific holidays from database
    }
  }, [postalCenter])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setSubmitting(true)

    try {
      await onSubmit({ ...formData, holidays: centerHolidays })
    } catch (err: any) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  const handleAddHoliday = () => {
    if (newHoliday.date && newHoliday.reason) {
      setCenterHolidays([...centerHolidays, newHoliday])
      setNewHoliday({ date: '', reason: '' })
    }
  }

  const handleRemoveHoliday = (index: number) => {
    setCenterHolidays(centerHolidays.filter((_, i) => i !== index))
  }

  // Get inherited values
  const inheritedCalculationMode = config?.calculation_mode || 'natural_days'
  const inheritedMixedReaderGap = config?.mixed_reader_gap_minutes || 10

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
          {error}
        </div>
      )}

      {/* Basic Information */}
      <div className="space-y-4">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
          {t('postal_centers.basic_info')}
        </h3>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            {t('postal_centers.code')} *
          </label>
          <input
            type="text"
            value={formData.code}
            onChange={(e) => setFormData({ ...formData, code: e.target.value })}
            className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
            required
            disabled={!!postalCenter}
            placeholder="HUB_MADRID"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            {t('postal_centers.name')} *
          </label>
          <input
            type="text"
            value={formData.name}
            onChange={(e) => setFormData({ ...formData, name: e.target.value })}
            className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
            required
            placeholder="Madrid Hub"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            {t('postal_centers.description')}
          </label>
          <textarea
            value={formData.description}
            onChange={(e) => setFormData({ ...formData, description: e.target.value })}
            className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
            rows={3}
            placeholder="Main distribution hub for Madrid region"
          />
        </div>

        <div className="flex items-center">
          <input
            type="checkbox"
            id="is_active"
            checked={formData.is_active}
            onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
            className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
          />
          <label htmlFor="is_active" className="ml-2 block text-sm text-gray-700 dark:text-gray-300">
            {t('postal_centers.is_active')}
          </label>
        </div>
      </div>

      {/* Configuration (Inherited from Account) */}
      <div className="space-y-4 pt-4 border-t border-gray-200 dark:border-gray-700">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
          {t('postal_centers.configuration')}
        </h3>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            {t('postal_centers.calculation_mode')}
          </label>
          <select
            value={formData.calculation_mode || ''}
            onChange={(e) => setFormData({ ...formData, calculation_mode: e.target.value as 'natural_days' | 'working_days' | null })}
            className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
          >
            <option value="">
              {t('postal_centers.inherit_from_account')} ({t(`postal_centers.${inheritedCalculationMode}`)})
            </option>
            <option value="natural_days">{t('postal_centers.natural_days')}</option>
            <option value="working_days">{t('postal_centers.working_days')}</option>
          </select>
          {!formData.calculation_mode && (
            <p className="text-xs text-blue-600 dark:text-blue-400 mt-1">
              ✓ {t('postal_centers.inheriting_from_account')}: {t(`postal_centers.${inheritedCalculationMode}`)}
            </p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            {t('postal_centers.mixed_reader_gap_minutes')}
          </label>
          <input
            type="number"
            value={formData.mixed_reader_gap_minutes ?? ''}
            onChange={(e) => setFormData({ ...formData, mixed_reader_gap_minutes: e.target.value ? parseInt(e.target.value) : null })}
            className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
            min="1"
            placeholder={`${inheritedMixedReaderGap} (${t('postal_centers.from_account')})`}
          />
          {formData.mixed_reader_gap_minutes === null && (
            <p className="text-xs text-blue-600 dark:text-blue-400 mt-1">
              ✓ {t('postal_centers.inheriting_from_account')}: {inheritedMixedReaderGap} {t('postal_centers.minutes')}
            </p>
          )}
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
            {t('postal_centers.mixed_reader_gap_help')}
          </p>
        </div>
      </div>

      {/* Holidays (Non-Working Days) */}
      <div className="space-y-4 pt-4 border-t border-gray-200 dark:border-gray-700">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
          {t('postal_centers.holidays')}
        </h3>

        {/* Account Holidays (Inherited, Read-only) */}
        <div>
          <h4 className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            {t('postal_centers.inherited_holidays')}
            <span className="ml-2 px-2 py-0.5 text-xs bg-blue-100 text-blue-800 rounded">
              {t('postal_centers.from_account')}
            </span>
          </h4>
          {accountHolidays && accountHolidays.length > 0 ? (
            <div className="space-y-1 max-h-40 overflow-y-auto bg-gray-50 dark:bg-gray-800 p-3 rounded">
              {accountHolidays.map((holiday, index) => (
                <div key={index} className="flex justify-between text-sm text-gray-600 dark:text-gray-400">
                  <span>{holiday.date}</span>
                  <span>{holiday.reason}</span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {t('postal_centers.no_account_holidays')}
            </p>
          )}
        </div>

        {/* Center-Specific Holidays */}
        <div>
          <h4 className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            {t('postal_centers.center_holidays')}
            <span className="ml-2 px-2 py-0.5 text-xs bg-orange-100 text-orange-800 rounded">
              {t('postal_centers.specific')}
            </span>
          </h4>
          
          {/* Add Holiday Form */}
          <div className="flex gap-2 mb-3">
            <input
              type="date"
              value={newHoliday.date}
              onChange={(e) => setNewHoliday({ ...newHoliday, date: e.target.value })}
              className="flex-1 px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
            />
            <input
              type="text"
              value={newHoliday.reason}
              onChange={(e) => setNewHoliday({ ...newHoliday, reason: e.target.value })}
              placeholder={t('postal_centers.holiday_reason')}
              className="flex-1 px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
            />
            <Button
              type="button"
              onClick={handleAddHoliday}
              disabled={!newHoliday.date || !newHoliday.reason}
              size="sm"
            >
              <Plus className="h-4 w-4" />
            </Button>
          </div>

          {/* Center Holidays List */}
          {centerHolidays.length > 0 ? (
            <div className="space-y-2">
              {centerHolidays.map((holiday, index) => (
                <div key={index} className="flex justify-between items-center bg-white dark:bg-gray-700 p-2 rounded border border-gray-200 dark:border-gray-600">
                  <div className="flex-1">
                    <span className="text-sm text-gray-900 dark:text-white">{holiday.date}</span>
                    <span className="ml-3 text-sm text-gray-600 dark:text-gray-400">{holiday.reason}</span>
                  </div>
                  <button
                    type="button"
                    onClick={() => handleRemoveHoliday(index)}
                    className="text-red-600 hover:text-red-800"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {t('postal_centers.no_center_holidays')}
            </p>
          )}
        </div>
      </div>

      {/* Actions */}
      <div className="flex justify-end gap-2 pt-4 border-t border-gray-200 dark:border-gray-700">
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
