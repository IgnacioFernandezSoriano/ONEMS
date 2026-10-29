import { useTimeUnit } from '../../hooks/useTimeUnit'
import { useTranslation } from '../../hooks/useTranslation'

const ACTIVE = 'bg-blue-600 text-white'
const INACTIVE = 'bg-white text-gray-700 border border-gray-300 hover:bg-gray-50'

export function TimeUnitToggle() {
  const { unit, setUnit } = useTimeUnit()
  const { t } = useTranslation()

  return (
    <div role="group" className="inline-flex">
      <button
        type="button"
        aria-pressed={unit === 'hours'}
        onClick={() => setUnit('hours')}
        className={`px-3 py-1.5 text-sm font-medium rounded-l-md transition-colors ${unit === 'hours' ? ACTIVE : INACTIVE}`}
      >
        {t('common.unit_hours')}
      </button>
      <button
        type="button"
        aria-pressed={unit === 'days'}
        onClick={() => setUnit('days')}
        className={`px-3 py-1.5 text-sm font-medium rounded-r-md transition-colors ${unit === 'days' ? ACTIVE : INACTIVE}`}
      >
        {t('common.unit_days')}
      </button>
    </div>
  )
}
