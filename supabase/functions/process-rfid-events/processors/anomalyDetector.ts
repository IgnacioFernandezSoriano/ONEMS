// ============================================
// ANOMALY DETECTOR
// ============================================

import type { RFIDEvent, TimeMetric, Anomaly, Severity } from '../types/interfaces.ts'

export function detectAnomalies(
  accountId: string,
  routeId: number,
  tagId: string,
  events: RFIDEvent[],
  metrics: TimeMetric[]
): Anomaly[] {
  const anomalies: Anomaly[] = []

  // —— 1. Single-event route (missing readings) ——
  if (events.length === 1) {
    anomalies.push({
      account_id: accountId,
      route_id: routeId,
      tag_id: tagId,
      anomaly_type: 'missing_reading',
      severity: 'high',
      description: `Package has only 1 reading at ${events[0].reader_id}, route incomplete`,
      reader_id: events[0].reader_id,
      detected_at: events[0].read_local_date_time,
      metadata: { event_count: 1 }
    })
  }

  // —— 2. Excessive delays ——
  for (const metric of metrics) {
    if (metric.is_delayed && metric.delay_hours !== null && metric.delay_hours > 0) {
      const severity = classifyDelaySeverity(metric.delay_hours)
      anomalies.push({
        account_id: accountId,
        route_id: routeId,
        tag_id: tagId,
        anomaly_type: 'excessive_delay',
        severity: severity,
        description: `Segment ${metric.from_reader_id} → ${metric.to_reader_id} delayed by ${metric.delay_hours} hours`,
        reader_id: metric.to_reader_id,
        detected_at: metric.segment_end_time,
        metadata: {
          expected_duration_hours: metric.expected_duration_hours,
          actual_duration_hours: metric.segment_duration_hours,
          delay_hours: metric.delay_hours,
          from_reader: metric.from_reader_id,
          to_reader: metric.to_reader_id
        }
      })
    }
  }

  // —— 3. Out-of-sequence detection (future: check against topology) ——
  // For MVP: detect temporal inconsistencies
  for (let i = 0; i < events.length - 1; i++) {
    const currentTime = new Date(events[i].read_local_date_time).getTime()
    const nextTime = new Date(events[i + 1].read_local_date_time).getTime()

    if (nextTime < currentTime) {
      anomalies.push({
        account_id: accountId,
        route_id: routeId,
        tag_id: tagId,
        anomaly_type: 'out_of_sequence',
        severity: 'medium',
        description: `Timestamp at ${events[i + 1].reader_id} is earlier than previous reader ${events[i].reader_id}`,
        reader_id: events[i + 1].reader_id,
        detected_at: events[i + 1].read_local_date_time,
        metadata: {
          previous_reader: events[i].reader_id,
          previous_time: events[i].read_local_date_time,
          current_time: events[i + 1].read_local_date_time
        }
      })
    }
  }

  // —— 4. Unknown readers (future: check against reader_config) ——
  // For MVP: skip this check (no reader_config table yet)

  return anomalies
}

function classifyDelaySeverity(delayHours: number): Severity {
  if (delayHours > 24) return 'critical'
  if (delayHours > 6) return 'high'
  if (delayHours > 2) return 'medium'
  return 'low' // 0 < delay ≤ 2 hours
}
