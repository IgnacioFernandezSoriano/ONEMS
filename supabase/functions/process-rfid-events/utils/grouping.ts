// ============================================
// GROUPING UTILITIES
// ============================================

import type { RFIDEvent } from '../types/interfaces.ts'

export function groupEventsByTagId(events: RFIDEvent[]): Map<string, RFIDEvent[]> {
  const groups = new Map<string, RFIDEvent[]>()

  for (const event of events) {
    if (!groups.has(event.tag_id)) {
      groups.set(event.tag_id, [])
    }
    groups.get(event.tag_id)!.push(event)
  }

  // Ensure chronological order within each group
  for (const [tagId, tagEvents] of groups) {
    tagEvents.sort((a, b) => {
      const timeA = new Date(a.read_local_date_time).getTime()
      const timeB = new Date(b.read_local_date_time).getTime()
      return timeA - timeB
    })
  }

  return groups
}
