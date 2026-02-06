// ============================================
// CONSOLIDATION UTILITIES
// ============================================

import type { RFIDEvent, ConsolidationResult, Anomaly } from '../types/interfaces.ts'
import { diffInMinutes } from './dateUtils.ts'

const DUPLICATE_THRESHOLD_MINUTES = 5

export function consolidateDuplicates(events: RFIDEvent[]): ConsolidationResult {
  const cleaned: RFIDEvent[] = []
  const duplicateAnomalies: Omit<Anomaly, 'route_id'>[] = []

  for (let i = 0; i < events.length; i++) {
    const currentEvent = events[i]

    if (cleaned.length > 0) {
      const lastCleaned = cleaned[cleaned.length - 1]

      // Check if this is a duplicate of the last cleaned event
      if (currentEvent.reader_id === lastCleaned.reader_id) {
        const timeDiffMinutes = diffInMinutes(
          lastCleaned.read_local_date_time,
          currentEvent.read_local_date_time
        )

        if (timeDiffMinutes < DUPLICATE_THRESHOLD_MINUTES) {
          // This is a duplicate - skip it, record anomaly
          duplicateAnomalies.push({
            account_id: currentEvent.account_id,
            tag_id: currentEvent.tag_id,
            anomaly_type: 'duplicate_reading',
            severity: 'low',
            description: `Duplicate reading at ${currentEvent.reader_id} within ${timeDiffMinutes.toFixed(1)} minutes`,
            reader_id: currentEvent.reader_id,
            detected_at: currentEvent.read_local_date_time,
            metadata: {
              original_event_id: lastCleaned.event_id,
              duplicate_event_id: currentEvent.event_id,
              time_diff_minutes: timeDiffMinutes
            }
          })
          continue // Skip this event
        }
      }
    }

    // Not a duplicate, add to cleaned list
    cleaned.push(currentEvent)
  }

  return { cleaned, duplicateAnomalies }
}
