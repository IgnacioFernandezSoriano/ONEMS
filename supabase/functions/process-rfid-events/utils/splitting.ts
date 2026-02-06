// ============================================
// SPLITTING UTILITIES
// ============================================

import type { RFIDEvent } from '../types/interfaces.ts'
import { diffInHours } from './dateUtils.ts'

const GAP_THRESHOLD_HOURS = 24

export function splitMultipleRoutes(events: RFIDEvent[]): RFIDEvent[][] {
  if (events.length <= 1) {
    return [events]
  }

  const routeGroups: RFIDEvent[][] = []
  let currentGroup: RFIDEvent[] = [events[0]]

  for (let i = 1; i < events.length; i++) {
    const gapHours = diffInHours(
      events[i - 1].read_local_date_time,
      events[i].read_local_date_time
    )

    if (gapHours > GAP_THRESHOLD_HOURS) {
      // New route detected
      routeGroups.push(currentGroup)
      currentGroup = [events[i]]
    } else {
      currentGroup.push(events[i])
    }
  }

  // Don't forget the last group
  routeGroups.push(currentGroup)

  return routeGroups
}
