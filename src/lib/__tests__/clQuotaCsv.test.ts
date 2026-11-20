import { describe, it, expect } from 'vitest'
import { parseQuotaCsv, quotasToCsv, QUOTA_CSV_TEMPLATE, type QuotaCsvContext } from '../carrierLink/quotaCsv'

const ctx: QuotaCsvContext = {
  cities: [
    { id: 'id-nbo', code: 'NBO', name: 'Nairobi' },
    { id: 'id-msa', code: 'MSA', name: 'Mombasa' },
    { id: 'id-ksm', code: 'KSM', name: 'Kisumu' },
    { id: 'id-x1', code: 'X1', name: 'Twin' },
    { id: 'id-x2', code: 'X2', name: 'Twin' },
  ],
  // 2026-01-05 is the Monday of 2026-W02; 2026-02-01 is a Sunday (W05).
  startDate: '2026-01-05',
  endDate: '2026-02-01',
  originCityIds: ['id-nbo', 'id-msa'],
  destinationCityIds: ['id-nbo', 'id-msa'],
}

const csv = (...rows: string[]) => ['origin_city,destination_city,week,samples', ...rows].join('\n')

describe('parseQuotaCsv', () => {
  it('lee código o nombre de ciudad y semana ISO o fecha', () => {
    const r = parseQuotaCsv(csv('NBO,MSA,2026-W02,3', 'mombasa,Nairobi,2026-01-14,2'), ctx)
    expect(r.errors).toEqual([])
    expect(r.quotas).toEqual([
      { origin_city_id: 'id-nbo', destination_city_id: 'id-msa', iso_year: 2026, iso_week: 2, samples: 3 },
      { origin_city_id: 'id-msa', destination_city_id: 'id-nbo', iso_year: 2026, iso_week: 3, samples: 2 },
    ])
  })

  it('acepta punto y coma, comillas, BOM y líneas vacías; omite las filas con 0 muestras', () => {
    const text = String.fromCharCode(0xfeff) + 'origin_city;destination_city;week;samples\r\n"NBO";MSA;2026-W5;1\r\n\r\nNBO;MSA;2026-W04;0\r\n'
    const r = parseQuotaCsv(text, ctx)
    expect(r.errors).toEqual([])
    expect(r.quotas).toEqual([{ origin_city_id: 'id-nbo', destination_city_id: 'id-msa', iso_year: 2026, iso_week: 5, samples: 1 }])
  })

  it('columnas en otro orden', () => {
    const r = parseQuotaCsv('samples,week,destination_city,origin_city\n2,2026-W03,MSA,NBO', ctx)
    expect(r.errors).toEqual([])
    expect(r.quotas[0]).toMatchObject({ origin_city_id: 'id-nbo', destination_city_id: 'id-msa', samples: 2 })
  })

  it('falta una columna: error de fichero', () => {
    const r = parseQuotaCsv('origin_city,destination_city,samples\nNBO,MSA,1', ctx)
    expect(r.quotas).toEqual([])
    expect(r.errors).toEqual([{ row: 1, key: 'cl.generator.csv.missing_columns', vars: { columns: 'week' } }])
  })

  it('fichero sin filas de datos', () => {
    expect(parseQuotaCsv(csv(), ctx).errors).toEqual([{ row: 1, key: 'cl.generator.csv.empty' }])
    expect(parseQuotaCsv(csv('NBO,MSA,2026-W02,0'), ctx).errors).toEqual([{ row: 1, key: 'cl.generator.csv.empty' }])
  })

  it('errores por fila con su número de línea', () => {
    const r = parseQuotaCsv(
      csv(
        'NBO,Atlantis,2026-W02,1', // 2 ciudad desconocida
        'NBO,NBO,2026-W02,1', // 3 misma ciudad
        'NBO,MSA,2026-W40,1', // 4 semana fuera del plan
        'NBO,MSA,semana,1', // 5 semana ilegible
        'NBO,MSA,2026-W02,1.5', // 6 muestras no enteras
        'NBO,MSA,2026-W02,-1', // 7 muestras negativas
        'NBO,MSA,2026-W03,1', // 8 ok
        'NBO,MSA,2026-01-12,1', // 9 duplicada de la 8 (misma semana W03)
        'KSM,MSA,2026-W02,1', // 10 ruta sin puntos (Kisumu no tiene punto de inicio)
        'Twin,MSA,2026-W02,1', // 11 nombre ambiguo = desconocida
        'NBO,MSA,2026-W54,1', // 12 semana inexistente
      ),
      ctx,
    )
    expect(r.errors).toEqual([
      { row: 2, key: 'cl.generator.csv.unknown_city', vars: { row: 2, city: 'Atlantis' } },
      { row: 3, key: 'cl.generator.csv.same_city', vars: { row: 3 } },
      { row: 4, key: 'cl.generator.csv.week_outside', vars: { row: 4, week: '2026-W40' } },
      { row: 5, key: 'cl.generator.csv.bad_week', vars: { row: 5, week: 'semana' } },
      { row: 6, key: 'cl.generator.csv.bad_samples', vars: { row: 6, value: '1.5' } },
      { row: 7, key: 'cl.generator.csv.bad_samples', vars: { row: 7, value: '-1' } },
      { row: 9, key: 'cl.generator.csv.duplicate', vars: { row: 9, first: 8 } },
      { row: 10, key: 'cl.generator.csv.no_points', vars: { row: 10, origin: 'KSM', destination: 'MSA' } },
      { row: 11, key: 'cl.generator.csv.unknown_city', vars: { row: 11, city: 'Twin' } },
      { row: 12, key: 'cl.generator.csv.bad_week', vars: { row: 12, week: '2026-W54' } },
    ])
    expect(r.quotas).toEqual([])
  })

  it('una semana que solo toca el plan por un extremo está dentro', () => {
    // 2026-W01 = 2025-12-29..2026-01-04: termina antes del inicio -> fuera; W06 empieza 2026-02-02 -> fuera.
    const r = parseQuotaCsv(csv('NBO,MSA,2026-W01,1', 'NBO,MSA,2026-W06,1'), ctx)
    expect(r.errors.map((e) => e.key)).toEqual(['cl.generator.csv.week_outside', 'cl.generator.csv.week_outside'])
    const inside = parseQuotaCsv(csv('NBO,MSA,2026-W02,1'), { ...ctx, startDate: '2026-01-11' })
    expect(inside.errors).toEqual([])
  })
})

describe('quotasToCsv', () => {
  it('mismo formato que la plantilla de importación (vuelve a importarse igual)', () => {
    const text = quotasToCsv(
      [
        { origin_city_id: 'id-nbo', destination_city_id: 'id-msa', iso_year: 2026, iso_week: 2, samples_planned: 3 },
        { origin_city_id: 'id-msa', destination_city_id: 'id-nbo', iso_year: 2026, iso_week: 3, samples_planned: 0 },
      ],
      (id) => ctx.cities.find((c) => c.id === id)?.code ?? id,
    )
    expect(text).toBe(`${QUOTA_CSV_TEMPLATE}\nNBO,MSA,2026-W02,3\nMSA,NBO,2026-W03,0`)
    const back = parseQuotaCsv(text, ctx)
    expect(back.errors).toEqual([])
    expect(back.quotas).toEqual([{ origin_city_id: 'id-nbo', destination_city_id: 'id-msa', iso_year: 2026, iso_week: 2, samples: 3 }])
  })

  it('pone entre comillas un valor con coma', () => {
    expect(quotasToCsv([{ origin_city_id: 'a', destination_city_id: 'b', iso_year: 2026, iso_week: 10, samples_planned: 1 }], (id) =>
      id === 'a' ? 'Dakar, Plateau' : 'Thiès',
    )).toBe(`${QUOTA_CSV_TEMPLATE}\n"Dakar, Plateau",Thiès,2026-W10,1`)
  })
})
