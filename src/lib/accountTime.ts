// Utilidades puras de hora local de la cuenta y duraciones (sin React ni Supabase)

export type TimeUnit = 'hours' | 'days'

function buildFormatter(tz: string): Intl.DateTimeFormat {
  const opts: Intl.DateTimeFormatOptions = {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  }
  try {
    return new Intl.DateTimeFormat('en-GB', opts)
  } catch (e) {
    if (e instanceof RangeError) {
      // Zona invalida: reintentar en UTC
      return new Intl.DateTimeFormat('en-GB', { ...opts, timeZone: 'UTC' })
    }
    throw e
  }
}

// Formatea un instante ISO como dd/MM/yyyy HH:mm en la zona indicada
export function formatInTz(iso: string | null | undefined, tz: string): string {
  if (!iso) return ''
  const date = new Date(iso)
  if (isNaN(date.getTime())) return ''
  const parts = buildFormatter(tz).formatToParts(date)
  const get = (type: string) => parts.find(p => p.type === type)?.value ?? ''
  const hour = get('hour') === '24' ? '00' : get('hour')
  return `${get('day')}/${get('month')}/${get('year')} ${hour}:${get('minute')}`
}

export function formatDuration(hours: number | null | undefined, unit: TimeUnit): string {
  if (hours === null || hours === undefined || Number.isNaN(hours)) return 'N/A'
  if (unit === 'days') return `${(hours / 24).toFixed(2)} d`
  return Number.isInteger(hours) ? `${hours} h` : `${hours.toFixed(1)} h`
}

export function toUnit(hours: number, unit: TimeUnit): number {
  return unit === 'days' ? hours / 24 : hours
}

export function unitSuffix(unit: TimeUnit): 'h' | 'd' {
  return unit === 'hours' ? 'h' : 'd'
}

// Duraciones almacenadas en minutos (tramos, viajes, diagnostico) -> unidad elegida
export function formatMinutes(minutes: number | null | undefined, unit: TimeUnit): string {
  if (minutes === null || minutes === undefined || Number.isNaN(minutes)) return '-'
  return formatDuration(minutes / 60, unit)
}

// Diferencia en minutos con signo (+1.5 h / -0.20 d)
export function formatMinutesDiff(diffMinutes: number, unit: TimeUnit): string {
  const sign = diffMinutes > 0 ? '+' : diffMinutes < 0 ? '-' : ''
  return `${sign}${formatDuration(Math.abs(diffMinutes) / 60, unit)}`
}
