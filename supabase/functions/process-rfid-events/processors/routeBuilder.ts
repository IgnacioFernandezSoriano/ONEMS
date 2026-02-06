// ============================================
// ROUTE BUILDER
// ============================================

import type { RFIDEvent, Route } from '../types/interfaces.ts'
import { diffInHours, roundToDecimals } from '../utils/dateUtils.ts'

export function buildRoute(accountId: string, tagId: string, events: RFIDEvent[]): Route {
  const firstEvent = events[0]
  const lastEvent = events[events.length - 1]

  const totalDurationHours = diffInHours(
    firstEvent.read_local_date_time,
    lastEvent.read_local_date_time
  )

  // Build reader_sequence: ordered unique readers, removing consecutive duplicates
  const readerSequence: string[] = []
  for (const event of events) {
    if (readerSequence.length === 0 || readerSequence[readerSequence.length - 1] !== event.reader_id) {
      readerSequence.push(event.reader_id)
    }
  }

  // is_complete = true if >= 2 events (MVP: 2+ events = complete)
  const isComplete = events.length >= 2

  return {
    account_id: accountId,
    tag_id: tagId,
    route_start_time: firstEvent.read_local_date_time,
    route_end_time: lastEvent.read_local_date_time,
    total_duration_hours: roundToDecimals(totalDurationHours, 2),
    reader_sequence: readerSequence,
    event_count: events.length, // NOTE: count of ORIGINAL events, not cleaned
    is_complete: isComplete
  }
}
