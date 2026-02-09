// Types for SLAs (Service Level Agreements) - Network Diagnostics Module
// Sprint 5: SLAs Configuration

import type { PostalCenter } from './types_postal_centers'
import type { Reader } from './types_postal_centers'

export type SLAType = 'operational' | 'distribution'
export type TimeUnit = 'minutes' | 'hours'

// Base SLA interface
export interface SLA {
  id: string
  account_id: string
  sla_type: SLAType
  
  // Operational SLA fields (within a postal center)
  postal_center_id: string | null
  from_reader_id: string | null
  to_reader_id: string | null
  
  // Distribution SLA fields (between postal centers)
  from_postal_center_id: string | null
  to_postal_center_id: string | null
  
  // Common fields
  expected_time_minutes: number
  time_unit: TimeUnit
  on_time_percentage: number
  warning_threshold: number
  critical_threshold: number
  is_active: boolean
  
  created_at: string
  updated_at: string
  created_by: string | null
  updated_by: string | null
}

// SLA with joined details for display
export interface SLAWithDetails extends SLA {
  // For operational SLAs
  postal_center?: PostalCenter
  from_reader?: Reader
  to_reader?: Reader
  
  // For distribution SLAs
  from_postal_center?: PostalCenter
  to_postal_center?: PostalCenter
}

// Form data for creating/editing SLAs
export interface SLAFormData {
  sla_type: SLAType
  
  // Operational SLA fields
  postal_center_id?: string
  from_reader_id?: string
  to_reader_id?: string
  
  // Distribution SLA fields
  from_postal_center_id?: string
  to_postal_center_id?: string
  
  // Common fields
  expected_time_minutes: number
  time_unit: TimeUnit
  on_time_percentage: number
  warning_threshold: number
  critical_threshold: number
  is_active: boolean
}

// Filters for SLAs list
export interface SLAFilters {
  sla_type: SLAType | ''
  postal_center_id: string
  from_postal_center_id: string
  to_postal_center_id: string
  status: 'active' | 'inactive' | ''
}

// Generate combinations request
export interface GenerateCombinationsRequest {
  sla_type: SLAType
  
  // For operational SLAs
  postal_center_ids?: string[]
  
  // For distribution SLAs
  from_postal_center_ids?: string[]
  to_postal_center_ids?: string[]
  
  // Default values for generated SLAs
  expected_time_minutes: number
  time_unit: TimeUnit
  on_time_percentage: number
  warning_threshold: number
  critical_threshold: number
}
