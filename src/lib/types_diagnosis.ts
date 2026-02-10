// Types for Diagnosis DB - Sprint 6
// Tables: processed_events, journey_segments, incidents, journeys

// ============================================================================
// PROCESSED EVENTS
// ============================================================================

export type EventType = 'entry' | 'exit';
export type ReaderType = 'Entry' | 'Exit' | 'Mixed';

export interface ProcessedEvent {
  id: number;
  account_id: string;
  tag_id: string;
  reader_id: string;
  postal_center_id: string;
  event_type: EventType;
  
  // Timestamps
  timestamp: string; // ISO datetime
  analysis_datetime: string; // ISO datetime
  
  // Snapshot fields
  postal_center_code_snapshot: string;
  postal_center_name_snapshot: string;
  reader_id_snapshot: string;
  reader_type_snapshot: ReaderType;
  
  // Processing metadata
  is_consolidated: boolean;
  raw_event_count: number;
  
  // Audit fields
  created_at: string;
  processed_at: string | null;
}

export interface ProcessedEventFormData {
  tag_id: string;
  reader_id: string;
  postal_center_id: string;
  event_type: EventType;
  timestamp: string;
  analysis_datetime: string;
  postal_center_code_snapshot: string;
  postal_center_name_snapshot: string;
  reader_id_snapshot: string;
  reader_type_snapshot: ReaderType;
  raw_event_count?: number;
}

// ============================================================================
// JOURNEY SEGMENTS
// ============================================================================

export type SegmentType = 'operational' | 'distribution';
export type SLACompliance = 'on_time' | 'warning' | 'critical' | 'violated' | 'no_sla';

export interface JourneySegment {
  id: number;
  account_id: string;
  tag_id: string;
  segment_type: SegmentType;
  
  // Segment definition
  postal_center_id: string | null; // For operational
  from_postal_center_id: string | null; // For distribution
  to_postal_center_id: string | null; // For distribution
  
  // Event references
  entry_event_id: number | null;
  exit_event_id: number | null;
  
  // Timestamps
  entry_timestamp: string;
  exit_timestamp: string;
  entry_analysis_datetime: string;
  exit_analysis_datetime: string;
  
  // Calculated times (in minutes)
  actual_time_minutes: number;
  adjusted_time_minutes: number;
  pre_operational_wait_minutes: number | null;
  
  // SLA comparison
  sla_id: string | null;
  expected_time_minutes: number | null;
  sla_compliance: SLACompliance | null;
  
  // Snapshot fields
  postal_center_code_snapshot: string | null;
  postal_center_name_snapshot: string | null;
  from_postal_center_code_snapshot: string | null;
  from_postal_center_name_snapshot: string | null;
  to_postal_center_code_snapshot: string | null;
  to_postal_center_name_snapshot: string | null;
  
  // Audit fields
  created_at: string;
}

export interface JourneySegmentWithDetails extends JourneySegment {
  // Related entities (joined)
  postal_center?: {
    id: string;
    code: string;
    name: string;
  };
  from_postal_center?: {
    id: string;
    code: string;
    name: string;
  };
  to_postal_center?: {
    id: string;
    code: string;
    name: string;
  };
  sla?: {
    id: string;
    expected_time_minutes: number;
    on_time_percentage: number;
  };
}

export interface JourneySegmentFormData {
  tag_id: string;
  segment_type: SegmentType;
  postal_center_id?: string;
  from_postal_center_id?: string;
  to_postal_center_id?: string;
  entry_event_id?: number;
  exit_event_id?: number;
  entry_timestamp: string;
  exit_timestamp: string;
  entry_analysis_datetime: string;
  exit_analysis_datetime: string;
  actual_time_minutes: number;
  adjusted_time_minutes: number;
  pre_operational_wait_minutes?: number;
  sla_id?: string;
  expected_time_minutes?: number;
  sla_compliance?: SLACompliance;
}

// ============================================================================
// INCIDENTS
// ============================================================================

export type IncidentType =
  | 'exit_before_entry'
  | 'missing_entry'
  | 'missing_exit'
  | 'sla_violation'
  | 'stuck_sample'
  | 'missroute'
  | 'duplicate_event'
  | 'invalid_sequence';

export type IncidentSeverity = 'low' | 'medium' | 'high' | 'critical';

export interface Incident {
  id: number;
  account_id: string;
  incident_type: IncidentType;
  severity: IncidentSeverity;
  
  // Related entities
  tag_id: string | null;
  postal_center_id: string | null;
  reader_id: string | null;
  event_id: number | null;
  segment_id: number | null;
  
  // Incident details
  description: string;
  metadata: Record<string, any> | null; // JSONB
  
  // Resolution
  is_resolved: boolean;
  resolved_at: string | null;
  resolved_by: string | null;
  resolution_notes: string | null;
  
  // Audit fields
  detected_at: string;
  created_at: string;
}

export interface IncidentWithDetails extends Incident {
  // Related entities (joined)
  postal_center?: {
    id: string;
    code: string;
    name: string;
  };
  reader?: {
    id: string;
    reader_id: string;
    name: string;
  };
  resolved_by_user?: {
    id: string;
    email: string;
  };
}

export interface IncidentFormData {
  incident_type: IncidentType;
  severity: IncidentSeverity;
  tag_id?: string;
  postal_center_id?: string;
  reader_id?: string;
  event_id?: number;
  segment_id?: number;
  description: string;
  metadata?: Record<string, any>;
}

export interface IncidentResolutionData {
  is_resolved: boolean;
  resolved_at?: string;
  resolved_by?: string;
  resolution_notes?: string;
}

// ============================================================================
// JOURNEYS
// ============================================================================

export type JourneyStatus = 'in_progress' | 'completed' | 'anomalous' | 'stuck';

export interface JourneyPathStep {
  center_id: string;
  code: string;
  name: string;
  entry_time: string;
  exit_time: string | null;
}

export interface Journey {
  id: number;
  account_id: string;
  tag_id: string;
  
  // Route information
  origin_city_id: string | null;
  destination_city_id: string | null;
  origin_city_name: string | null;
  destination_city_name: string | null;
  
  // Journey path
  route_path: JourneyPathStep[]; // JSONB array
  total_centers_visited: number;
  
  // Calculated times (in minutes)
  total_actual_time_minutes: number | null;
  total_adjusted_time_minutes: number | null;
  total_operational_time_minutes: number | null;
  total_distribution_time_minutes: number | null;
  total_pre_operational_wait_minutes: number | null;
  
  // Journey status
  journey_status: JourneyStatus;
  is_missroute: boolean;
  missroute_reason: string | null;
  
  // Timestamps
  first_event_timestamp: string | null;
  last_event_timestamp: string | null;
  
  // SLA summary
  total_sla_violations: number;
  total_segments: number;
  on_time_segments: number;
  
  // Audit fields
  created_at: string;
  updated_at: string;
}

export interface JourneyWithDetails extends Journey {
  // Related entities (joined)
  origin_city?: {
    id: string;
    name: string;
  };
  destination_city?: {
    id: string;
    name: string;
  };
  segments?: JourneySegmentWithDetails[];
  incidents?: IncidentWithDetails[];
}

export interface JourneyFormData {
  tag_id: string;
  origin_city_id?: string;
  destination_city_id?: string;
  origin_city_name?: string;
  destination_city_name?: string;
  route_path: JourneyPathStep[];
  journey_status: JourneyStatus;
  is_missroute?: boolean;
  missroute_reason?: string;
}

// ============================================================================
// FILTERS
// ============================================================================

export interface ProcessedEventFilters {
  tag_id?: string;
  postal_center_id?: string;
  reader_id?: string;
  event_type?: EventType;
  start_date?: string;
  end_date?: string;
  is_consolidated?: boolean;
}

export interface JourneySegmentFilters {
  tag_id?: string;
  segment_type?: SegmentType;
  postal_center_id?: string;
  from_postal_center_id?: string;
  to_postal_center_id?: string;
  sla_compliance?: SLACompliance;
  start_date?: string;
  end_date?: string;
}

export interface IncidentFilters {
  tag_id?: string;
  incident_type?: IncidentType;
  severity?: IncidentSeverity;
  postal_center_id?: string;
  is_resolved?: boolean;
  start_date?: string;
  end_date?: string;
}

export interface JourneyFilters {
  tag_id?: string;
  origin_city_id?: string;
  destination_city_id?: string;
  journey_status?: JourneyStatus;
  is_missroute?: boolean;
  start_date?: string;
  end_date?: string;
}

// ============================================================================
// UTILITY TYPES
// ============================================================================

export interface TimeCalculation {
  actual_minutes: number;
  adjusted_minutes: number;
  pre_operational_wait_minutes?: number;
  non_working_minutes: number;
}

export interface SLAPerformance {
  expected_minutes: number;
  actual_minutes: number;
  adjusted_minutes: number;
  compliance: SLACompliance;
  deviation_minutes: number;
  deviation_percentage: number;
}

export interface JourneyStatistics {
  total_journeys: number;
  completed_journeys: number;
  in_progress_journeys: number;
  anomalous_journeys: number;
  stuck_journeys: number;
  missroute_count: number;
  missroute_percentage: number;
  average_actual_time_minutes: number;
  average_adjusted_time_minutes: number;
  total_incidents: number;
  total_sla_violations: number;
}
