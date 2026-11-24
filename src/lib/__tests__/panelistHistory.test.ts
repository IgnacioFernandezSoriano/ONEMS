import { describe, it, expect } from 'vitest'
import { filterEvents, linkHref, linkOption, eventTextKey, type HistoryEvent } from '../panelistHistory'

const ev = (type: HistoryEvent['type'], extra: Partial<HistoryEvent> = {}): HistoryEvent => ({
  id: type + Math.random(), at: '2027-03-20T10:00:00Z', type, subtype: null, status: null, data: {}, link: null, ...extra,
})

describe('panelistHistory', () => {
  const all = [ev('note'), ev('incident'), ev('gps'), ev('gps_ref'), ev('receipt'), ev('leave'), ev('notice')]

  it('filterEvents: todo, y gps incluye las referencias', () => {
    expect(filterEvents(all, 'all')).toHaveLength(7)
    expect(filterEvents(all, 'gps').map(e => e.type)).toEqual(['gps', 'gps_ref'])
    expect(filterEvents(all, 'note').map(e => e.type)).toEqual(['note'])
    expect(filterEvents(all, 'receipt').map(e => e.type)).toEqual(['receipt'])
  })

  it('linkHref abre el elemento concreto en cada pantalla', () => {
    expect(linkHref({ screen: 'reported', id: 'i1' })).toBe('/incidents/panelist-reported?incident=i1')
    expect(linkHref({ screen: 'availability', id: 'u1' })).toBe('/incidents/panelist-availability?unavailability=u1')
    expect(linkHref({ screen: 'receipts', id: 'c1' })).toBe('/incidents/receipts?case=c1')
  })

  it('linkOption: el permiso que hace falta para abrir el enlace', () => {
    expect(linkOption({ screen: 'reported', id: 'x' })).toBe('reported_incidents')
    expect(linkOption({ screen: 'availability', id: 'x' })).toBe('panelist_availability')
    expect(linkOption({ screen: 'receipts', id: 'x' })).toBe('receipts')
  })

  it('eventTextKey: por tipo, categoría y papel', () => {
    expect(eventTextKey(ev('incident', { subtype: 'parcel_damaged' }))).toBe('panelist_history.event.incident')
    expect(eventTextKey(ev('receipt', { data: { role: 'sender' } }))).toBe('panelist_history.event.receipt_sender')
    expect(eventTextKey(ev('receipt', { data: { role: 'receiver' } }))).toBe('panelist_history.event.receipt_receiver')
    expect(eventTextKey(ev('gps_ref', { data: { source: 'declined' } }))).toBe('panelist_history.event.gps_ref_declined')
    expect(eventTextKey(ev('gps_ref', { data: { source: 'declaration', kind: 'home' } }))).toBe('panelist_history.event.gps_ref_home')
    expect(eventTextKey(ev('note'))).toBe('panelist_history.event.note')
  })
})
