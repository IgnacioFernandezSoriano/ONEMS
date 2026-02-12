import { useState, useEffect } from 'react'
import { Button } from '@/components/common/Button'
import { Plus, Trash2 } from 'lucide-react'
import type { PostalCenter, PostalCenterFormData } from '@/lib/types_postal_centers'
import { useTranslation } from '@/hooks/useTranslation'
import { useAccountConfig } from '@/hooks/useAccountConfig'

interface PostalCenterFormProps {
  postalCenter?: PostalCenter | null
  onSubmit: (data: PostalCenterFormData & { weeklySchedule?: WeeklyScheduleDay[]; centerHolidays?: { date: string; reason: string }[] }) => Promise<void>
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
    calculation_mode: config?.calculation_mode || 'natural_days',
    city: '',
    state: '',
    country: 'USA',
    latitude: undefined,
    longitude: undefined,
    timezone: 'America/New_York',
    is_active: true
  }) const [weeklySchedule, setWeeklySchedule] = useState<WeeklyScheduleDay[]>([])
  const [centerHolidays, setCenterHolidays] = useState<{ date: string; reason: string }[]>([])
  const [newHoliday, setNewHoliday] = useState({ date: '', reason: '' })
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
        city: postalCenter.city || '',
        state: postalCenter.state || '',
        country: postalCenter.country || 'USA',
        latitude: postalCenter.latitude,
        longitude: postalCenter.longitude,
        timezone: postalCenter.timezone || 'America/New_York',
        is_active: postalCenter.is_active
      })
      // Load center-specific weekly schedule and holidays from database
      loadWeeklySchedule(postalCenter.id)
      loadCenterHolidays(postalCenter.id)
    }
  }, [postalCenter])

  const loadWeeklySchedule = async (postalCenterId: string) => {
    try {
      const { supabase } = await import('@/lib/supabase')
      const { data, error } = await supabase
        .from('weekly_schedule')
        .select('*')
        .eq('postal_center_id', postalCenterId)
        .order('day_of_week')
      
      if (error) throw error
      if (data) {
        setWeeklySchedule(data)
      }
    } catch (err) {
      console.error('Error loading weekly schedule:', err)
    }
  }

  const loadCenterHolidays = async (postalCenterId: string) => {
    try {
      const { supabase } = await import('@/lib/supabase')
      const { data, error } = await supabase
        .from('non_working_days')
        .select('date, reason')
        .eq('postal_center_id', postalCenterId)
        .order('date')
      
      if (error) throw error
      if (data) {
        setCenterHolidays(data)
      }
    } catch (err) {
      console.error('Error loading center holidays:', err)
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setSubmitting(true)

    try {
      await onSubmit({ ...formData, weeklySchedule, centerHolidays })
    } catch (err: any) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  const handleAddHoliday = () => {
    if (newHoliday.date && newHoliday.reason) {
      setCenterHolidays([...centerHolidays, { ...newHoliday }])
      setNewHoliday({ date: '', reason: '' })
    }
  }

  const handleRemoveHoliday = (index: number) => {
    setCenterHolidays(centerHolidays.filter((_, i) => i !== index))
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

        {/* Location Information */}
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              City
            </label>
            <input
              type="text"
              value={formData.city || ''}
              onChange={(e) => setFormData({ ...formData, city: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
              placeholder="New York"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              State
            </label>
            <input
              type="text"
              value={formData.state || ''}
              onChange={(e) => setFormData({ ...formData, state: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
              placeholder="NY"
            />
          </div>
        </div>

        <div className="grid grid-cols-3 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Country
            </label>
            <input
              type="text"
              value={formData.country || 'USA'}
              onChange={(e) => setFormData({ ...formData, country: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
              placeholder="USA"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Latitude
            </label>
            <input
              type="number"
              step="0.000001"
              value={formData.latitude || ''}
              onChange={(e) => setFormData({ ...formData, latitude: e.target.value ? parseFloat(e.target.value) : undefined })}
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
              placeholder="40.712776"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Longitude
            </label>
            <input
              type="number"
              step="0.000001"
              value={formData.longitude || ''}
              onChange={(e) => setFormData({ ...formData, longitude: e.target.value ? parseFloat(e.target.value) : undefined })}
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
              placeholder="-74.005974"
            />
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Timezone
          </label>
          <select
            value={formData.timezone || 'America/New_York'}
            onChange={(e) => setFormData({ ...formData, timezone: e.target.value })}
            className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-white"
          >
            <option value="America/New_York">Eastern Time (America/New_York)</option>
            <option value="America/Chicago">Central Time (America/Chicago)</option>
            <option value="America/Denver">Mountain Time (America/Denver)</option>
            <option value="America/Los_Angeles">Pacific Time (America/Los_Angeles)</option>
            <option value="America/Phoenix">Arizona Time (America/Phoenix)</option>
            <option value="America/Anchorage">Alaska Time (America/Anchorage)</option>
            <option value="Pacific/Honolulu">Hawaii Time (Pacific/Honolulu)</option>
          </select>
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
                      <label className="text-xs text-gray-500 min-w-[60px]">{t('common.opening')}:</label>
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
                      <label className="text-xs text-gray-500 min-w-[60px]">{t('common.cutoff')}:</label>
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

        {/* Center-Specific Holidays */}
        <div className="mt-4">
          <h4 className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            {t('postal_centers.center_holidays')}
            <span className="ml-2 px-2 py-0.5 text-xs bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200 rounded">
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
              placeholder="YYYY-MM-DD"
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
                    <span className="text-sm text-gray-900 dark:text-white font-medium">{holiday.date}</span>
                    <span className="ml-3 text-sm text-gray-600 dark:text-gray-400">{holiday.reason}</span>
                  </div>
                  <button
                    type="button"
                    onClick={() => handleRemoveHoliday(index)}
                    className="text-red-600 hover:text-red-800 dark:hover:text-red-400"
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
