import { describe, it, expect, vi } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  DELIVERY_ERROR_CODES,
  DELIVERY_PHASES,
  DELIVERY_STATUSES,
  MANUAL_DELIVERY_MAX_BYTES,
  deliveryErrorKey,
  deliveryFrequency,
  deliveryPhaseKey,
  deliveryProgressPercent,
  deliveryStatusKey,
  formatFromFileName,
  graceHoursOf,
  isDeliveryFinal,
  isDeliveryInFlight,
  manualFileCheck,
  manualPeriodError,
  parseFeedCalendar,
  parseGraceHours,
  periodLabel,
  rejectedReasons,
  runManualDelivery,
  withGraceHours,
  type ManualDeliveryApi,
} from '../carrierLink/deliveryView'

describe('estados y fases', () => {
  it('clave de estado conocida o "unknown"', () => {
    expect(deliveryStatusKey('processed')).toBe('cl.delivery.status.processed')
    expect(deliveryStatusKey('raro')).toBe('cl.delivery.status.unknown')
  })
  it('finales y en curso', () => {
    expect(['processed', 'rejected'].every(isDeliveryFinal)).toBe(true)
    expect(isDeliveryFinal('failed')).toBe(false)
    expect(['received', 'processing', 'failed'].every(isDeliveryInFlight)).toBe(true)
    expect(isDeliveryInFlight('pending_upload')).toBe(false)
  })
  it('la fase solo se muestra en processing y si es conocida', () => {
    expect(deliveryPhaseKey('processing', 'draw')).toBe('cl.delivery.phase.draw')
    expect(deliveryPhaseKey('processing', 'abort')).toBeNull()
    expect(deliveryPhaseKey('processed', 'done')).toBeNull()
    expect(deliveryPhaseKey('processing', null)).toBeNull()
  })
  it('avance: la carga pesa la mitad por bytes; las fases siguientes el resto; nunca 100 sin terminar', () => {
    const base = { status: 'processing', file_bytes: 1000, bytes_loaded: 500 }
    expect(deliveryProgressPercent({ ...base, phase: 'load' })).toBe(25)
    expect(deliveryProgressPercent({ ...base, phase: 'load', file_bytes: null })).toBe(0)
    expect(deliveryProgressPercent({ ...base, phase: 'resolve' })).toBe(57)
    expect(deliveryProgressPercent({ ...base, phase: 'cleanup' })).toBe(99)
    expect(deliveryProgressPercent({ ...base, phase: 'raro' })).toBe(0)
    expect(deliveryProgressPercent({ ...base, status: 'processed', phase: 'done' })).toBe(100)
    expect(deliveryProgressPercent({ ...base, status: 'received', phase: null })).toBeNull()
  })
})

describe('motivos y errores', () => {
  it('rejected_reasons ordenados, sin ceros, tolerante', () => {
    expect(rejectedReasons({ rows: { bad_timestamp: 2, unknown_product: 5, x: 0 }, shipments: { no_end: 3 } })).toEqual({
      rows: [
        { reason: 'unknown_product', count: 5 },
        { reason: 'bad_timestamp', count: 2 },
      ],
      shipments: [{ reason: 'no_end', count: 3 }],
    })
    expect(rejectedReasons(null)).toEqual({ rows: [], shipments: [] })
  })
  it('el error guardado (con SQLSTATE o con dígitos) da su clave', () => {
    expect(deliveryErrorKey('CL_PROCESSING_ERROR 23505')).toBe('cl.error.cl_processing_error')
    expect(deliveryErrorKey('CL_SHA256_MISMATCH')).toBe('cl.error.cl_sha256_mismatch')
    expect(deliveryErrorKey(null)).toBeNull()
  })
})

describe('traducciones de entregas', () => {
  const extra = [
    ...DELIVERY_STATUSES.map((s) => `cl.delivery.status.${s}`),
    'cl.delivery.status.unknown',
    ...DELIVERY_PHASES.map((p) => `cl.delivery.phase.${p}`),
    ...DELIVERY_ERROR_CODES.map((c) => `cl.error.${c.toLowerCase()}`),
    // Motivos de rechazo que escribe el proceso v4 (filas y envíos).
    ...['bad_record', 'bad_value', 'missing_field', 'bad_timestamp', 'unknown_product', 'unknown_reading_point'].map((r) => `cl.reason.${r}`),
    ...['already_sampled', 'product_mismatch', 'no_start', 'same_reading', 'no_end', 'start_after_end', 'reader_without_city',
      'end_out_of_period', 'no_stratum'].map((r) => `cl.reason.${r}`),
    ...['daily', 'weekly', 'several_per_week'].map((f) => `cl.connectors.frequency.${f}`),
  ]
  for (const lang of ['en', 'es', 'fr', 'ar', 'pt']) {
    it(`${lang}.csv tiene estados, fases, errores, motivos y frecuencias`, () => {
      const csv = readFileSync(resolve(__dirname, `../../../public/locales/${lang}.csv`), 'utf8')
      const keys = new Set(csv.split(/\r?\n/).map((l) => l.slice(0, l.indexOf(','))))
      expect(extra.filter((k) => !keys.has(k))).toEqual([])
    })
  }
  it('el proceso no escribe códigos que la lista no tenga', () => {
    const dir = resolve(__dirname, '../../../supabase')
    const files = [
      'migrations/20261124200100_cl_process_delivery.sql',
      'migrations/20261124200200_cl_delivery_api.sql',
      'functions/carrier-link-worker/loader.ts',
      'functions/carrier-link-worker/records.ts',
    ]
    const written = new Set<string>()
    for (const f of files) {
      const src = readFileSync(resolve(dir, f), 'utf8')
      for (const m of src.matchAll(/'(CL_[A-Z0-9_]+)'/g)) written.add(m[1])
    }
    const known = new Set<string>(DELIVERY_ERROR_CODES)
    const clErrors = readFileSync(resolve(__dirname, '../carrierLink/clErrors.ts'), 'utf8')
    expect([...written].filter((c) => !known.has(c) && !clErrors.includes(`'${c}'`))).toEqual([])
  })
})

describe('periodos y calendario', () => {
  it('etiqueta de un día o de un rango, sin moverse de día', () => {
    expect(periodLabel('2026-11-23', '2026-11-23', 'en')).toBe('Nov 23, 2026')
    expect(periodLabel('2026-11-23', '2026-11-29', 'en')).toBe('Nov 23, 2026 – Nov 29, 2026')
    expect(periodLabel(null, '2026-11-29', 'en')).toBe('-')
  })
  it('frecuencia como cl_connector_config', () => {
    expect(deliveryFrequency([1, 2, 3, 4, 5, 6, 7])).toBe('daily')
    expect(deliveryFrequency([1])).toBe('weekly')
    expect(deliveryFrequency([1, 4])).toBe('several_per_week')
  })
  it('periodo de la subida manual', () => {
    expect(manualPeriodError('', '2026-11-01')).toBe('cl.deliveries.upload.period_required')
    expect(manualPeriodError('2026-11-05', '2026-11-01')).toBe('cl.deliveries.upload.period_order')
    expect(manualPeriodError('2026-11-01', '2026-11-08')).toBe('cl.deliveries.upload.period_too_long')
    expect(manualPeriodError('2026-11-01', '2026-11-07')).toBeNull()
    expect(manualPeriodError('2026-11-01', '2026-11-01')).toBeNull()
  })
  it('lee el calendario de la base sin fiarse de su forma', () => {
    const c = parseFeedCalendar({
      calendar: { frequency: 'weekly', deliveries_per_week: 1, delivery_days: [1], delivery_hour: 3, timezone: 'Africa/Nairobi' },
      next_period: { period_start: '2026-11-23', period_end: '2026-11-29', due_at: '2026-11-30T00:00:00Z', deliverable: false },
      last_delivery: null,
      missing_grace_hours: 12,
      max_file_bytes: 1000,
    })
    expect(c).toMatchObject({ frequency: 'weekly', delivery_days: [1], missing_grace_hours: 12, max_file_bytes: 1000, last_delivery: null })
    expect(c.next_period).toEqual({ period_start: '2026-11-23', period_end: '2026-11-29', due_at: '2026-11-30T00:00:00Z', deliverable: false })
    expect(parseFeedCalendar(null)).toMatchObject({ frequency: null, next_period: null, delivery_days: [] })
  })
})

describe('fichero de la subida manual', () => {
  it('formato por extensión; comprimido o desconocido, no', () => {
    expect(formatFromFileName('ENTREGA.JSONL')).toEqual({ format: 'jsonl' })
    expect(formatFromFileName('a.ndjson')).toEqual({ format: 'jsonl' })
    expect(formatFromFileName('a.csv')).toEqual({ format: 'csv' })
    expect(formatFromFileName('a.jsonl.gz')).toEqual({ errorKey: 'cl.error.cl_compression_unsupported' })
    expect(formatFromFileName('a.zip')).toEqual({ errorKey: 'cl.error.cl_compression_unsupported' })
    expect(formatFromFileName('a.json')).toEqual({ errorKey: 'cl.deliveries.upload.bad_extension' })
  })
  it('tamaño: vacío no; tope del conector o del bucket', () => {
    expect(manualFileCheck({ name: 'a.csv', size: 0 }, null)).toEqual({ errorKey: 'cl.deliveries.upload.empty_file' })
    expect(manualFileCheck({ name: 'a.csv', size: 1001 }, 1000)).toEqual({ errorKey: 'cl.error.cl_file_too_large' })
    expect(manualFileCheck({ name: 'a.csv', size: 1000 }, 1000)).toEqual({ format: 'csv' })
    expect(manualFileCheck({ name: 'a.csv', size: MANUAL_DELIVERY_MAX_BYTES + 1 }, null)).toEqual({ errorKey: 'cl.error.cl_file_too_large' })
  })
})

describe('margen de no recibido', () => {
  it('lee el config como la base (0..168, si no 6)', () => {
    expect(graceHoursOf({ missing_grace_hours: 12 })).toBe(12)
    expect(graceHoursOf({ missing_grace_hours: 0 })).toBe(0)
    expect(graceHoursOf({ missing_grace_hours: 200 })).toBe(6)
    expect(graceHoursOf({ missing_grace_hours: '12' })).toBe(6)
    expect(graceHoursOf(null)).toBe(6)
  })
  it('valida el formulario y conserva las demás claves', () => {
    expect(parseGraceHours('24')).toBe(24)
    expect(parseGraceHours('169')).toBeNull()
    expect(parseGraceHours('-1')).toBeNull()
    expect(parseGraceHours('1.5')).toBeNull()
    expect(parseGraceHours('')).toBeNull()
    expect(withGraceHours({ max_file_bytes: 1000, missing_grace_hours: 6 }, 24)).toEqual({ max_file_bytes: 1000, missing_grace_hours: 24 })
    expect(withGraceHours(null, 3)).toEqual({ missing_grace_hours: 3 })
  })
})

describe('runManualDelivery (mismo camino que la API)', () => {
  const args = { periodStart: '2026-11-23', periodEnd: '2026-11-23', sha256: 'a'.repeat(64), format: 'jsonl' as const }
  const api = (over: Partial<ManualDeliveryApi>, openStatus = 'pending_upload'): ManualDeliveryApi => ({
    open: vi.fn(async () => ({ delivery_id: 'd1', status: openStatus, file_path: 'acc/feed/d1.jsonl', existing: openStatus !== 'pending_upload' })),
    upload: vi.fn(async () => ({ error: null })),
    complete: vi.fn(async () => ({ delivery_id: 'd1', status: 'received', file_path: 'acc/feed/d1.jsonl' })),
    ...over,
  })

  it('abrir, subir a la ruta de la base y completar, en ese orden', async () => {
    const a = api({})
    const steps: string[] = []
    const r = await runManualDelivery(a, args, (s) => steps.push(s))
    expect(steps).toEqual(['opening', 'uploading', 'completing'])
    expect(a.upload).toHaveBeenCalledWith('acc/feed/d1.jsonl', 'jsonl')
    expect(a.complete).toHaveBeenCalledWith('d1')
    expect(r.status).toBe('received')
  })
  it('la misma entrega ya recibida: no se sube otra vez', async () => {
    const a = api({}, 'processed')
    const r = await runManualDelivery(a, args)
    expect(a.upload).not.toHaveBeenCalled()
    expect(a.complete).not.toHaveBeenCalled()
    expect(r).toMatchObject({ status: 'processed', existing: true })
  })
  it('fichero ya subido (409): se completa igual; otro error de subida se lanza', async () => {
    const dup = api({ upload: vi.fn(async () => ({ error: { message: 'The resource already exists', statusCode: '409' } })) })
    expect((await runManualDelivery(dup, args)).status).toBe('received')
    const bad = api({ upload: vi.fn(async () => ({ error: { message: 'new row violates row-level security policy', statusCode: '403' } })) })
    await expect(runManualDelivery(bad, args)).rejects.toMatchObject({ statusCode: '403' })
    expect(bad.complete).not.toHaveBeenCalled()
  })
  it('un error al abrir se lanza tal cual (p. ej. periodo no cerrado)', async () => {
    const a = api({ open: vi.fn(async () => Promise.reject({ message: 'CL_PERIOD_NOT_CLOSED', code: '22023' })) })
    await expect(runManualDelivery(a, args)).rejects.toMatchObject({ message: 'CL_PERIOD_NOT_CLOSED' })
    expect(a.upload).not.toHaveBeenCalled()
  })
})
