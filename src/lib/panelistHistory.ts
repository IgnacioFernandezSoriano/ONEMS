// Historial del panelista: tipos de la respuesta de public.panelist_history y utilidades puras
// (spec docs/superpowers/specs/2026-11-24-historial-panelista-design.md).
import type { AccessOption } from '@/lib/access'

export type HistoryEventType = 'note' | 'incident' | 'gps' | 'receipt' | 'leave' | 'notice' | 'gps_ref'
export type HistoryFilter = 'all' | 'note' | 'incident' | 'receipt' | 'gps' | 'leave' | 'notice'
export const HISTORY_FILTERS: HistoryFilter[] = ['all', 'note', 'incident', 'receipt', 'gps', 'leave', 'notice']

export interface HistoryLink { screen: 'reported' | 'availability' | 'receipts'; id: string }

export interface HistoryEvent {
  id: string
  at: string
  type: HistoryEventType
  subtype: string | null
  status: string | null
  data: Record<string, any>
  link: HistoryLink | null
}

export interface HistoryPanelist {
  id: string; code: string; name: string; mobile: string | null; city: string | null; node: string | null
  pobox: boolean; created: string | null; status: string | null; language: string | null
}

export interface HistoryStats {
  sent_30d: number; scheduled_30d: number; receipt_problems_30d: number; gps_said_no_30d: number
  leave_days_year: number; pobox_ref: boolean; home_ref: boolean; ref_needs_review: boolean
}

export interface HistoryCursor { before: string; before_id: string }

export interface HistoryPage {
  panelist: HistoryPanelist
  stats: HistoryStats
  events: HistoryEvent[]
  next: HistoryCursor | null
  can_write: boolean
}

export function filterEvents(events: HistoryEvent[], f: HistoryFilter): HistoryEvent[] {
  if (f === 'all') return events
  if (f === 'gps') return events.filter(e => e.type === 'gps' || e.type === 'gps_ref')
  return events.filter(e => e.type === f)
}

const LINK_PATH: Record<HistoryLink['screen'], [string, string]> = {
  reported: ['/incidents/panelist-reported', 'incident'],
  availability: ['/incidents/panelist-availability', 'unavailability'],
  receipts: ['/incidents/receipts', 'case'],
}

export function linkHref(link: HistoryLink): string {
  const [path, param] = LINK_PATH[link.screen]
  return `${path}?${param}=${encodeURIComponent(link.id)}`
}

export function linkOption(link: HistoryLink): AccessOption {
  return link.screen === 'reported' ? 'reported_incidents'
    : link.screen === 'availability' ? 'panelist_availability' : 'receipts'
}

/** Clave i18n de la línea principal del evento. */
export function eventTextKey(e: HistoryEvent): string {
  const base = 'panelist_history.event.'
  if (e.type === 'receipt') return base + (e.data?.role === 'sender' ? 'receipt_sender' : 'receipt_receiver')
  if (e.type === 'gps_ref') return base + (e.data?.source === 'declined' ? 'gps_ref_declined' : `gps_ref_${e.data?.kind === 'home' ? 'home' : 'pobox'}`)
  return base + e.type
}

/** Motivos de panelist_unavailability (CHECK de la BD) y su clave i18n. */
export const LEAVE_REASONS = ['vacation', 'sick_leave', 'personal', 'training', 'other', 'materials'] as const
export function leaveReasonKey(reason: string): string {
  return `panelist_history.leave_reason.${reason}`
}
