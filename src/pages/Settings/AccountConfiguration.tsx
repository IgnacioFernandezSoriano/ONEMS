import { useState, useRef } from 'react'
import { useAccountConfig } from '../../hooks/useAccountConfig'
import { useLocale } from '../../contexts/LocaleContext'
import { Save, Calendar, Clock, Settings as SettingsIcon, Plus, Trash2, Upload, Download } from 'lucide-react'

export function AccountConfiguration() {
  const { t } = useLocale()
  const {
    config,
    nonWorkingDays,
    weeklySchedule,
    loading,
    updateConfig,
    addNonWorkingDay,
    deleteNonWorkingDay,
    updateWeeklySchedule,
    bulkImportNonWorkingDays,
  } = useAccountConfig()

  const [calculationMode, setCalculationMode] = useState<'natural_days' | 'working_days'>(
    config?.calculation_mode || 'natural_days'
  )
  const [mixedReaderGap, setMixedReaderGap] = useState(
    config?.mixed_reader_gap_minutes || 10
  )
  const [saving, setSaving] = useState(false)
  const [showAddHoliday, setShowAddHoliday] = useState(false)
  const [newHolidayDate, setNewHolidayDate] = useState('')
  const [newHolidayReason, setNewHolidayReason] = useState('')
  const fileInputRef = useRef<HTMLInputElement>(null)

  const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']

  const handleSaveConfig = async () => {
    setSaving(true)
    const result = await updateConfig({
      calculation_mode: calculationMode,
      mixed_reader_gap_minutes: mixedReaderGap,
    })
    setSaving(false)

    if (result.success) {
      alert(t('account_config.saved_successfully'))
    } else {
      alert(`Error: ${result.error}`)
    }
  }

  const handleAddHoliday = async () => {
    if (!newHolidayDate || !newHolidayReason) {
      alert(t('account_config.fill_all_fields'))
      return
    }

    const result = await addNonWorkingDay(newHolidayDate, newHolidayReason)
    if (result.success) {
      setNewHolidayDate('')
      setNewHolidayReason('')
      setShowAddHoliday(false)
    } else {
      alert(`Error: ${result.error}`)
    }
  }

  const handleDeleteHoliday = async (id: string) => {
    if (!confirm(t('account_config.confirm_delete_holiday'))) return
    await deleteNonWorkingDay(id)
  }

  const handleUpdateSchedule = async (
    dayOfWeek: number,
    field: 'opening_hour' | 'cutoff_time' | 'is_working_day',
    value: string | boolean
  ) => {
    const result = await updateWeeklySchedule(dayOfWeek, { [field]: value })
    if (!result.success) {
      alert(`Error updating schedule: ${result.error}`)
    }
  }

  const handleDownloadTemplate = () => {
    const csv = 'date,reason\n2026-01-01,New Year\n2026-12-25,Christmas'
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'holidays_template.csv'
    a.click()
    URL.revokeObjectURL(url)
  }

  const handleImportCSV = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (!file) return

    const text = await file.text()
    const lines = text.split('\n').slice(1) // Skip header
    const holidays: Array<{ date: string; reason: string }> = []

    for (const line of lines) {
      const [date, reason] = line.split(',')
      if (date && reason) {
        holidays.push({ date: date.trim(), reason: reason.trim() })
      }
    }

    if (holidays.length === 0) {
      alert(t('account_config.no_valid_holidays'))
      return
    }

    const result = await bulkImportNonWorkingDays(holidays)
    if (result.success) {
      alert(t('account_config.imported_successfully', { count: holidays.length }))
    } else {
      alert(`Error: ${result.error}`)
    }

    // Reset file input
    if (fileInputRef.current) {
      fileInputRef.current.value = ''
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">{t('common.loading')}</div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white">
            {t('account_config.title')}
          </h1>
          <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {t('account_config.description')}
          </p>
        </div>
      </div>

      {/* Global Configuration */}
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
        <div className="flex items-center gap-2 mb-4">
          <SettingsIcon className="w-5 h-5 text-gray-500" />
          <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
            {t('account_config.global_settings')}
          </h2>
        </div>

        <div className="space-y-4">
          {/* Calculation Mode */}
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              {t('account_config.calculation_mode')}
            </label>
            <select
              value={calculationMode}
              onChange={(e) => setCalculationMode(e.target.value as 'natural_days' | 'working_days')}
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:text-white"
            >
              <option value="natural_days">{t('account_config.natural_days')}</option>
              <option value="working_days">{t('account_config.working_days')}</option>
            </select>
            <p className="mt-1 text-xs text-gray-500 dark:text-gray-400">
              {t('account_config.calculation_mode_help')}
            </p>
          </div>

          {/* Mixed Reader Gap */}
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              {t('account_config.mixed_reader_gap')}
            </label>
            <input
              type="number"
              min="1"
              max="60"
              value={mixedReaderGap}
              onChange={(e) => setMixedReaderGap(parseInt(e.target.value))}
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:text-white"
            />
            <p className="mt-1 text-xs text-gray-500 dark:text-gray-400">
              {t('account_config.mixed_reader_gap_help')}
            </p>
          </div>

          {/* Save Button */}
          <button
            onClick={handleSaveConfig}
            disabled={saving}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
          >
            <Save className="w-4 h-4" />
            {saving ? t('common.saving') : t('common.save')}
          </button>
        </div>
      </div>

      {/* Non-Working Days */}
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <Calendar className="w-5 h-5 text-gray-500" />
            <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
              {t('account_config.non_working_days')}
            </h2>
          </div>
          <div className="flex gap-2">
            <button
              onClick={handleDownloadTemplate}
              className="flex items-center gap-2 px-3 py-1.5 bg-gray-600 text-white text-sm rounded-lg hover:bg-gray-700"
            >
              <Download className="w-4 h-4" />
              {t('account_config.download_template')}
            </button>
            <button
              onClick={() => fileInputRef.current?.click()}
              className="flex items-center gap-2 px-3 py-1.5 bg-green-600 text-white text-sm rounded-lg hover:bg-green-700"
            >
              <Upload className="w-4 h-4" />
              {t('account_config.import_csv')}
            </button>
            <input
              ref={fileInputRef}
              type="file"
              accept=".csv"
              onChange={handleImportCSV}
              className="hidden"
            />
            <button
              onClick={() => setShowAddHoliday(!showAddHoliday)}
              className="flex items-center gap-2 px-3 py-1.5 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700"
            >
              <Plus className="w-4 h-4" />
              {t('account_config.add_holiday')}
            </button>
          </div>
        </div>

        {showAddHoliday && (
          <div className="mb-4 p-4 bg-gray-50 dark:bg-gray-700 rounded-lg space-y-3">
            <input
              type="date"
              value={newHolidayDate}
              onChange={(e) => setNewHolidayDate(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg dark:bg-gray-800 dark:text-white"
            />
            <input
              type="text"
              placeholder={t('account_config.holiday_reason')}
              value={newHolidayReason}
              onChange={(e) => setNewHolidayReason(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg dark:bg-gray-800 dark:text-white"
            />
            <div className="flex gap-2">
              <button
                onClick={handleAddHoliday}
                className="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700"
              >
                {t('common.add')}
              </button>
              <button
                onClick={() => setShowAddHoliday(false)}
                className="px-4 py-2 bg-gray-300 dark:bg-gray-600 text-gray-700 dark:text-white rounded-lg hover:bg-gray-400 dark:hover:bg-gray-500"
              >
                {t('common.cancel')}
              </button>
            </div>
          </div>
        )}

        <div className="space-y-2">
          {nonWorkingDays.length === 0 ? (
            <p className="text-sm text-gray-500 dark:text-gray-400 text-center py-4">
              {t('account_config.no_holidays')}
            </p>
          ) : (
            nonWorkingDays.map((holiday) => (
              <div
                key={holiday.id}
                className="flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-700 rounded-lg"
              >
                <div>
                  <p className="font-medium text-gray-900 dark:text-white">
                    {new Date(holiday.date).toLocaleDateString()}
                  </p>
                  <p className="text-sm text-gray-500 dark:text-gray-400">{holiday.reason}</p>
                </div>
                <button
                  onClick={() => handleDeleteHoliday(holiday.id)}
                  className="p-2 text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg"
                >
                  <Trash2 className="w-4 h-4" />
                </button>
              </div>
            ))
          )}
        </div>
      </div>

      {/* Weekly Schedule */}
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
        <div className="flex items-center gap-2 mb-4">
          <Clock className="w-5 h-5 text-gray-500" />
          <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
            {t('account_config.weekly_schedule')}
          </h2>
        </div>

        <div className="space-y-3">
          {dayNames.map((dayName, dayOfWeek) => {
            const schedule = weeklySchedule.find((s) => s.day_of_week === dayOfWeek)
            return (
              <div
                key={dayOfWeek}
                className="flex items-center gap-4 p-3 bg-gray-50 dark:bg-gray-700 rounded-lg"
              >
                <div className="w-24">
                  <p className="font-medium text-gray-900 dark:text-white">{dayName}</p>
                </div>
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={schedule?.is_working_day ?? true}
                    onChange={(e) =>
                      handleUpdateSchedule(dayOfWeek, 'is_working_day', e.target.checked)
                    }
                    className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                  />
                  <span className="text-sm text-gray-700 dark:text-gray-300">
                    {t('account_config.working_day')}
                  </span>
                </label>
                {(schedule?.is_working_day ?? true) && (
                  <>
                    <div className="flex items-center gap-2">
                      <label className="text-xs text-gray-500">{t('account_config.opening')}:</label>
                      <input
                        type="time"
                        value={schedule?.opening_hour || '08:00'}
                        onChange={(e) =>
                          handleUpdateSchedule(dayOfWeek, 'opening_hour', e.target.value)
                        }
                        className="px-3 py-1.5 border border-gray-300 dark:border-gray-600 rounded-lg dark:bg-gray-800 dark:text-white"
                      />
                    </div>
                    <div className="flex items-center gap-2">
                      <label className="text-xs text-gray-500">{t('account_config.cutoff')}:</label>
                      <input
                        type="time"
                        value={schedule?.cutoff_time || '18:00'}
                        onChange={(e) =>
                          handleUpdateSchedule(dayOfWeek, 'cutoff_time', e.target.value)
                        }
                        className="px-3 py-1.5 border border-gray-300 dark:border-gray-600 rounded-lg dark:bg-gray-800 dark:text-white"
                      />
                    </div>
                  </>
                )}
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
