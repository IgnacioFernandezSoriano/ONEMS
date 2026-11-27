import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  INCIDENT_STATUSES,
  INCIDENT_STATUS_FILTERS,
  INCIDENT_TYPES,
  closedHowKey,
  filtersFromSearch,
  incidentStatusKey,
  incidentTypeKey,
  incidentsLink,
  isIncidentEditable,
  notificationCounts,
  parseIncident,
  parseIncidentList,
  periodDetailLines,
  statusParam,
} from '../carrierLink/incidentView'

describe('tipos, estados y cierre', () => {
  it('los tipos son los del CHECK de cl_incidents y los filtros de cl_incidents_list', () => {
    const sql = readFileSync(resolve(__dirname, '../../../supabase/migrations/20261124200300_cl_incidents.sql'), 'utf8')
    for (const type of INCIDENT_TYPES) expect(sql).toContain(`'${type}'`)
    expect(sql).toMatch(/p_status NOT IN \('open','in_progress','resolved','unresolved'\)/)
  })
  it('claves de tipo y estado; desconocido -> unknown', () => {
    expect(incidentTypeKey('missing_delivery')).toBe('cl.incidents.type.missing_delivery')
    expect(incidentTypeKey('raro')).toBe('cl.incidents.type.unknown')
    expect(incidentStatusKey('in_progress')).toBe('cl.incidents.status.in_progress')
    expect(incidentStatusKey('raro')).toBe('cl.incidents.status.unknown')
  })
  it('distingue cierre a mano y automático; abierta no tiene', () => {
    expect(closedHowKey({ status: 'resolved', closed_how: 'manual' })).toBe('cl.incidents.closed.manual')
    expect(closedHowKey({ status: 'resolved', closed_how: 'auto' })).toBe('cl.incidents.closed.auto')
    expect(closedHowKey({ status: 'open', closed_how: null })).toBeNull()
  })
  it('solo se edita o cierra lo no resuelto', () => {
    expect(isIncidentEditable('open')).toBe(true)
    expect(isIncidentEditable('in_progress')).toBe(true)
    expect(isIncidentEditable('resolved')).toBe(false)
  })
})

describe('filtros', () => {
  it('statusParam: "all" = sin filtro', () => {
    expect(statusParam('all')).toBeNull()
    expect(statusParam('unresolved')).toBe('unresolved')
  })
  it('desde la URL, ignorando valores raros', () => {
    const id = '0f000000-0000-0000-0000-0000000000a1'
    expect(filtersFromSearch(new URLSearchParams(`status=resolved&type=unknown_data&feed=${id}`))).toEqual({
      status: 'resolved',
      type: 'unknown_data',
      feedId: id,
    })
    expect(filtersFromSearch(new URLSearchParams('status=x&type=y&feed=1;drop'))).toEqual({ status: 'unresolved', type: null, feedId: null })
  })
  it('enlace desde el Monitor (ida y vuelta)', () => {
    const link = incidentsLink({ type: 'high_rejection', feedId: '0f000000-0000-0000-0000-0000000000a1' })
    expect(link).toBe('/carrier-link/incidents?type=high_rejection&feed=0f000000-0000-0000-0000-0000000000a1')
    expect(filtersFromSearch(new URLSearchParams(link.split('?')[1]))).toMatchObject({ type: 'high_rejection', status: 'unresolved' })
    expect(incidentsLink({})).toBe('/carrier-link/incidents')
  })
})

describe('lectura de las RPC', () => {
  it('lista', () => {
    const r = parseIncidentList({
      total: 3,
      items: [
        {
          id: 'i1', incident_type: 'missing_delivery', status: 'open', feed_id: 'f1', feed_name: 'Feed', plan_id: null,
          periods_count: 2, last_period: { period_start: '2026-11-10', period_end: '2026-11-10' }, assignee_id: null,
          assignee_name: null, opened_at: 'x', updated_at: 'y', closed_at: null, closed_how: null,
        },
        'basura',
      ],
    })
    expect(r.total).toBe(3)
    expect(r.items).toHaveLength(1)
    expect(r.items[0]).toMatchObject({ id: 'i1', periods_count: 2, last_period: { period_start: '2026-11-10' } })
    expect(parseIncidentList(null)).toEqual({ total: 0, items: [] })
  })
  it('detalle: periodos, valores desconocidos y avisos sin direcciones', () => {
    const d = parseIncident({
      id: 'i1', incident_type: 'unknown_data', status: 'resolved', closed_how: 'auto', feed_id: 'f1', carrier_notified: false,
      periods: [{ key: 'k1', period_start: '2026-11-10', period_end: '2026-11-10', detected_at: 'z', products: 2, points: 1 }],
      details: { products: ['ZZ', 'YY'], points: [{ place_ref: 'NBO', mode_ref: null }] },
      notifications: [
        { recipient_kind: 'account_manager', event: 'opened', status: 'sent', attempts: 1, periods_count: 1, to: 'nunca@x.y' },
      ],
    })
    expect(d.periods[0]).toMatchObject({ key: 'k1', products: 2, points: 1 })
    expect(d.unknown_products).toEqual(['ZZ', 'YY'])
    expect(d.unknown_points).toEqual([{ place_ref: 'NBO', mode_ref: null }])
    expect(JSON.stringify(d.notifications)).not.toContain('@')
  })
  it('líneas de detalle por tipo', () => {
    const p = parseIncident({
      periods: [{ period_start: 'a', period_end: 'a', error: 'CL_SHA256_MISMATCH', rejected: 30, shipments: 100, ratio: 0.3, missing: 4 }],
    }).periods[0]
    const ek = (c: string) => `E:${c}`
    expect(periodDetailLines('delivery_rejected', p, ek)).toEqual([
      { key: 'cl.incidents.detail.rejected_error', params: { error: 'E:CL_SHA256_MISMATCH' } },
    ])
    expect(periodDetailLines('high_rejection', p, ek)[0].params).toEqual({ rejected: 30, shipments: 100, percent: 30 })
    expect(periodDetailLines('quota_unfilled', p, ek)[0].params).toEqual({ missing: 4 })
    expect(periodDetailLines('missing_delivery', p, ek)).toEqual([])
  })
  it('recuento de avisos por destinatario y estado (cuenta primero)', () => {
    const n = (recipient_kind: string, status: string) => ({
      recipient_kind, status, event: 'opened', attempts: 1, periods_count: 1, created_at: null, sent_at: null,
    })
    expect(notificationCounts([n('carrier', 'sent'), n('account_manager', 'sent'), n('account_manager', 'failed'), n('account_manager', 'pending'), n('carrier', 'skipped')])).toEqual([
      { kind: 'account_manager', sent: 1, pending: 1, failed: 1, skipped: 0 },
      { kind: 'carrier', sent: 1, pending: 0, failed: 0, skipped: 1 },
    ])
  })
})

describe('traducciones de incidencias', () => {
  const keys = [
    ...INCIDENT_TYPES.map((x) => `cl.incidents.type.${x}`),
    ...INCIDENT_TYPES.map((x) => `cl.incidents.explain.${x}`),
    'cl.incidents.type.unknown',
    ...INCIDENT_STATUSES.map((x) => `cl.incidents.status.${x}`),
    'cl.incidents.status.unknown',
    ...INCIDENT_STATUS_FILTERS.map((x) => `cl.incidents.filter.status.${x}`),
    'cl.incidents.closed.manual',
    'cl.incidents.closed.auto',
    'cl.incidents.detail.rejected_error',
    'cl.incidents.detail.high_rejection',
    'cl.incidents.detail.unknown_data',
    'cl.incidents.detail.quota_unfilled',
    'cl.incidents.recipient.account',
    'cl.incidents.recipient.carrier',
    'menu.cl_incidents',
  ]
  for (const lang of ['en', 'es', 'fr', 'ar', 'pt']) {
    it(`${lang}.csv`, () => {
      const csv = readFileSync(resolve(__dirname, `../../../public/locales/${lang}.csv`), 'utf8')
      const have = new Set(csv.split(/\r?\n/).map((l) => l.slice(0, l.indexOf(','))))
      expect(keys.filter((k) => !have.has(k))).toEqual([])
    })
  }
})
