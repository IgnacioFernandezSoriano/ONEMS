import { useState, useEffect } from 'react'
import { Button } from '@/components/common/Button'
import type { PostalCenter, PostalCenterFormData } from '@/lib/types_postal_centers'
import { useTranslation } from '@/hooks/useTranslation'
import { useAccountConfig } from '@/hooks/useAccountConfig'

interface PostalCenterFormProps {
  postalCenter?: PostalCenter | null
  onSubmit: (data: PostalCenterFormData & { weeklySchedule?: WeeklyScheduleDay[] }) => Promise<void>
  onCancel: () => void
}

interface WeeklyScheduleDay {
  day_of_week: number
  is_working_day: boolean
  opening_hour: string | null
  cutoff_time: string | null
}

export function PostalCenterForm({ postalCenter, onSubmit, onCancel }: PostalCenterFormProps) {
  const { t } = useTranslation()
  const { config, nonWorkingDays: accountHolidays, weeklySchedule: accountWeeklySchedule } = useAccountConfig()
  
  const [formData, setFormData] = useState<PostalCenterFormData>({
    code: '',
    name: '',
    description: '',
    calculation_mode: null,
    mixed_reader_gap_minutes: null,
    is_active: true
  })
  
  const [weeklySchedule, setWeeklySchedule] = useState<WeeklyScheduleDay[]>([])
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const dayNames = [
    t('common.sunday'), 
    t('common.monday'), 
    t('common.tuesday'), 
    t('common.wednesday'), 
    t('common.thursday'), 
    t('common.friday'), 
    t('common.saturday')
  ]

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
      // TODO: Load center-specific weekly schedule from database
    }
  }, [postalCenter])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setSubmitting(true)

    try {
      await onSubmit({ ...formData, weeklySchedule })
    } catch (err: any) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  const handleUpdateSchedule = (dayOfWeek: number, field: string, value: any) => {
    setWeeklySchedule((prev) => {
      const existing = prev.find((s) => s.day_of_week === dayOfWeek)
      if (existing) {
        return prev.map((s) =>
          s.day_of_week === dayOfWeek ? { ...s, [field]: value } : s
        )
      } else {
        const accountSchedule = accountWeeklySchedule?.find((s) => s.day_of_week === dayOfWeek)
        return [...prev, { 
          day_of_week: dayOfWeek, 
          is_working_day: accountSchedule?.is_working_day ?? true, 
          opening_hour: accountSchedule?.opening_hour || '08:00', 
          cutoff_time: accountSchedule?.cutoff_time || '18:00', 
          [field]: value 
        }]
      }
    })
  }

  // Get inherited values
  const inheritedCalculationMode = config?.calculation_mode || 'natural_days'
  const inheritedMixedReaderGap = config?.mixed_reader_gap_minutes || 10
  const effectiveCalculationMode = formData.calculation_mode || inheritedCalculationMode

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

      {/* Weekly Schedule - Only for Working Days mode */}
      {effectiveCalculationMode === 'working_days' && (
      <div className="space-y-4 pt-4 border-t border-gray-200 dark:border-gray-700">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
          {t('postal_centers.weekly_schedule')}
        </h3>
        <p className="text-xs text-gray-500 dark:text-gray-400">
          {t('postal_centers.weekly_schedule_help')}
        </p>

        <div className="space-y-3">
          {dayNames.map((dayName, dayOfWeek) => {
            const centerSchedule = weeklySchedule.find((s) => s.day_of_week === dayOfWeek)
            const accountSchedule = accountWeeklySchedule?.find((s) => s.day_of_week === dayOfWeek)
            const isInherited = !centerSchedule
            const schedule = centerSchedule || accountSchedule || { is_working_day: true, opening_hour: '08:00', cutoff_time: '18:00' }
            
            return (
              <div
                key={dayOfWeek}
                className="p-3 bg-gray-50 dark:bg-gray-700 rounded-lg space-y-2"
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <p className="font-medium text-gray-900 dark:text-white min-w-[100px]">{dayName}</p>
                    {isInherited && (
                      <span className="text-xs px-2 py-0.5 bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200 rounded">
                        {t('postal_centers.inherited')}
                      </span>
                    )}
                  </div>
                  <label className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      checked={schedule.is_working_day}
                      onChange={(e) =>
                        handleUpdateSchedule(dayOfWeek, 'is_working_day', e.target.checked)
                      }
                      className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span className="text-sm text-gray-700 dark:text-gray-300">
                      {t('account_config.working_day')}
                    </span>
                  </label>
                </div>
                {schedule.is_working_day && (
                  <div className="flex items-center gap-4 pl-4">
                    <div className="flex items-center gap-2">
                      <label className="text-xs text-gray-500 min-w-[60px]">{t('account_config.opening')}:</label>
                      <input
                        type="time"
                        value={schedule.opening_hour || '08:00'}
                        onChange={(e) =>
                          handleUpdateSchedule(dayOfWeek, 'opening_hour', e.target.value)
                        }
                        className="px-3 py-1.5 border border-gray-300 dark:border-gray-600 rounded-lg dark:bg-gray-800 dark:text-white"
                      />
                    </div>
                    <div className="flex items-center gap-2">
                      <label className="text-xs text-gray-500 min-w-[60px]">{t('account_config.cutoff')}:</label>
                      <input
                        type="time"
                        value={schedule.cutoff_time || '18:00'}
                        onChange={(e) =>
                          handleUpdateSchedule(dayOfWeek, 'cutoff_time', e.target.value)
                        }
                        className="px-3 py-1.5 border border-gray-300 dark:border-gray-600 rounded-lg dark:bg-gray-800 dark:text-white"
                      />
                    </div>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      </div>
      )}

      {/* Holidays (Non-Working Days) - Inherited from Account (Read-only) */}
      {effectiveCalculationMode === 'working_days' && accountHolidays && accountHolidays.length > 0 && (
      <div className="space-y-4 pt-4 border-t border-gray-200 dark:border-gray-700">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
          {t('postal_centers.holidays')}
          <span className="ml-2 px-2 py-0.5 text-xs bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200 rounded">
            {t('postal_centers.inherited_from_account')}
          </span>
        </h3>
        <p className="text-xs text-gray-500 dark:text-gray-400">
          {t('postal_centers.holidays_inherited_help')}
        </p>

        <div className="space-y-1 max-h-60 overflow-y-auto bg-gray-50 dark:bg-gray-800 p-3 rounded">
          {accountHolidays.map((holiday, index) => (
            <div key={index} className="flex justify-between text-sm text-gray-600 dark:text-gray-400 py-1">
              <span className="font-medium">{holiday.date}</span>
              <span>{holiday.reason}</span>
            </div>
          ))}
        </div>
      </div>
      )}

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
