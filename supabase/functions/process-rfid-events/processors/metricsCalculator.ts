// ============================================
// METRICS CALCULATOR
// ============================================

import type { RFIDEvent, TimeMetric } from '../types/interfaces.ts'
import { diffInHours, roundToDecimals } from '../utils/dateUtils.ts'

const DEFAULT_EXPECTED_HOURS = 2.0 // MVP fixed value

export function calculateTimeMetrics(
  accountId: string,
  routeId: number,
  tagId: string,
  events: RFIDEvent[]
): TimeMetric[] {
  const metrics: TimeMetric[] = []

  if (events.length < 2) {
    return metrics // No segments possible
  }

  for (let i = 0; i < events.length - 1; i++) {
    const fromEvent = events[i]
    const toEvent = events[i + 1]

    // Skip if same reader (already consolidated, but defensive)
    if (fromEvent.reader_id === toEvent.reader_id) {
      continue
    }

    const segmentDurationHours = diffInHours(
      fromEvent.read_local_date_time,
      toEvent.read_local_date_time
    )

    const expectedHours = getExpectedDuration(fromEvent.reader_id, toEvent.reader_id)
    const isDelayed = segmentDurationHours > expectedHours
    const delayHours = isDelayed ? roundToDecimals(segmentDurationHours - expectedHours, 2) : null

    metrics.push({
      account_id: accountId,
      route_id: routeId,
      tag_id: tagId,
      from_reader_id: fromEvent.reader_id,
      to_reader_id: toEvent.reader_id,
      segment_duration_hours: roundToDecimals(segmentDurationHours, 2),
      segment_start_time: fromEvent.read_local_date_time,
      segment_end_time: toEvent.read_local_date_time,
      expected_duration_hours: expectedHours,
      is_delayed: isDelayed,
      delay_hours: delayHours
    })
  }

  return metrics
}

function getExpectedDuration(fromReader: string, toReader: string): number {
  // MVP Phase: Return fixed value
  return DEFAULT_EXPECTED_HOURS

  // Future Phase: Query historical average
  // const result = await query(`
  //   SELECT AVG(segment_duration_hours) as avg_duration
  //   FROM diagnosis_time_metrics
  //   WHERE from_reader_id = $1 AND to_reader_id = $2 AND is_delayed = false
  //   HAVING COUNT(*) >= 10
  // `, [fromReader, toReader])
  // return result?.avg_duration ?? DEFAULT_EXPECTED_HOURS
}
