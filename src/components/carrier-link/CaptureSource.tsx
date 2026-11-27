import { useTranslation } from '@/hooks/useTranslation'

/** Origen de una lectura o tramo del diagnostico (columna capture_source): lector RFID o escaneo del carrier. */
export type CaptureSource = 'rfid' | 'carrier'
/** Filtro de origen en las pantallas de diagnostico: '' = todos. */
export type CaptureSourceFilter = '' | CaptureSource

/** Etiqueta del origen (RFID / Carrier). Filas sin la columna (BD sin la migracion) cuentan como RFID. */
export function CaptureSourceBadge({ source }: { source?: string | null }) {
  const { t } = useTranslation()
  const carrier = source === 'carrier'
  return (
    <span
      className={`px-2 py-1 text-xs font-medium rounded-full ${
        carrier ? 'bg-amber-100 text-amber-800' : 'bg-gray-100 text-gray-700'
      }`}
    >
      {t(carrier ? 'cl.capture_origin.carrier' : 'cl.capture_origin.rfid')}
    </span>
  )
}

/** Selector "Origen" (Todos / RFID / Carrier) para las pantallas de diagnostico. */
export function CaptureSourceSelect({
  value,
  onChange,
  className,
  labelClassName,
}: {
  value: CaptureSourceFilter
  onChange: (v: CaptureSourceFilter) => void
  className?: string
  labelClassName?: string
}) {
  const { t } = useTranslation()
  return (
    <div>
      <label className={labelClassName ?? 'block text-sm font-medium text-gray-700 mb-1'}>{t('cl.capture_origin.label')}</label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value as CaptureSourceFilter)}
        className={className ?? 'w-full border border-gray-300 rounded-lg px-3 py-2'}
      >
        <option value="">{t('common.all')}</option>
        <option value="rfid">{t('cl.capture_origin.rfid')}</option>
        <option value="carrier">{t('cl.capture_origin.carrier')}</option>
      </select>
    </div>
  )
}
