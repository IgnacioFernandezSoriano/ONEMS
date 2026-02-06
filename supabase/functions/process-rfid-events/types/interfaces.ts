// ============================================
// TYPE DEFINITIONS - RFID Calculation Module
// ============================================

export interface RFIDEvent {
  id: number
  event_id: string
  read_local_date_time: string
  reader_id: string
  tag_id: string
  account_id: string
  ingested_at: string
  processed_at: string | null
  created_at: string
}

export interface Route {
  account_id: string
  tag_id: string
  route_start_time: string
  route_end_time: string
  total_duration_hours: number
  reader_sequence: string[]
  event_count: number
  is_complete: boolean
}

export interface RouteWithId extends Route {
  id: number
}

export interface TimeMetric {
  account_id: string
  route_id: number
  tag_id: string
  from_reader_id: string
  to_reader_id: string
  segment_duration_hours: number
  segment_start_time: string
  segment_end_time: string
  expected_duration_hours: number
  is_delayed: boolean
  delay_hours: number | null
}

export type AnomalyType = 'missing_reading' | 'excessive_delay' | 'duplicate_reading' | 'out_of_sequence'
export type Severity = 'low' | 'medium' | 'high' | 'critical'

export interface Anomaly {
  account_id: string
  route_id: number | null
  tag_id: string
  anomaly_type: AnomalyType
  severity: Severity
  description: string
  reader_id: string | null
  detected_at: string
  metadata: Record<string, any>
}

export interface ProcessingStats {
  processed: number
  routes: number
  anomalies: number
  errors: number
}

export interface ConsolidationResult {
  cleaned: RFIDEvent[]
  duplicateAnomalies: Omit<Anomaly, 'route_id'>[]
}
