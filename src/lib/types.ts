export type Role = 'superadmin' | 'admin' | 'user'
export type Status = 'active' | 'inactive'

export type SupportedLanguage = 'en' | 'es' | 'fr' | 'ar'

export const SUPPORTED_LANGUAGES: { code: SupportedLanguage; name: string }[] = [
  { code: 'en', name: 'English' },
  { code: 'es', name: 'Español' },
  { code: 'fr', name: 'Français' },
  { code: 'ar', name: 'العربية' },
]

export interface Account {
  id: string
  name: string
  slug: string
  status: Status
  default_language: SupportedLanguage
  email_panelist_manager: string | null
  created_at: string
  updated_at: string
}

export interface Region {
  id: string
  account_id: string
  name: string
  code: string
  country_code?: string
  description?: string
  status: 'active' | 'inactive'
  created_at: string
  updated_at: string
}

export interface City {
  id: string
  account_id: string
  region_id: string
  name: string
  code: string
  classification?: 'A' | 'B' | 'C'  // Legacy field, use account_city_classification table instead
  population?: number
  latitude?: number
  longitude?: number
  status: 'active' | 'inactive'
  created_at: string
  updated_at: string
}

export interface Carrier {
  id: string
  account_id: string
  code: string
  name: string
  type?: string
  status: 'active' | 'inactive'
  created_at: string
  updated_at: string
}

export interface Product {
  id: string
  account_id: string
  carrier_id: string
  code: string
  description: string
  standard_delivery_hours: number
  time_unit: 'hours' | 'days'
  status: 'active' | 'inactive'
  created_at: string
  updated_at: string
}

export interface MaterialCatalog {
  id: string
  account_id: string
  code: string
  name: string
  unit_measure?: string
  min_stock?: number
  description?: string
  status: 'active' | 'inactive'
  is_blocking: boolean
  created_at: string
  updated_at: string
}

export interface ProductMaterial {
  id: string
  account_id: string
  product_id: string
  material_id: string
  quantity: number
  created_at: string
  updated_at: string
  material_catalog?: MaterialCatalog
}

export interface DeliveryStandard {
  id: string
  account_id: string
  carrier_id: string
  product_id: string
  origin_city_id: string
  destination_city_id: string
  standard_time: number | null
  success_percentage: number | null
  time_unit: 'hours' | 'days'
  warning_threshold?: number | null
  critical_threshold?: number | null
  threshold_type?: 'relative' | 'absolute'
  created_at: string
  updated_at: string
}

export interface DeliveryStandardWithDetails extends DeliveryStandard {
  carrier?: Carrier
  product?: Product
  origin_city?: City
  destination_city?: City
}

// Allocation Plans
export interface GeneratedAllocationPlan {
  id: string
  account_id: string
  plan_name: string
  carrier_id: string
  product_id: string
  total_samples: number
  start_date: string
  end_date: string
  status: 'draft' | 'pending' | 'applied'
  created_at: string
  updated_at: string
  created_by?: string
}

export interface GeneratedAllocationPlanDetail {
  id: string
  account_id: string
  plan_id: string
  origin_node_id: string
  destination_node_id: string
  fecha_programada: string
  week_number: number
  month: number
  year: number
  status: 'pending' | 'notified' | 'sent' | 'received' | 'cancelled' | 'invalid' | 'transfer_error';
  idtag?: string
  created_at: string
  updated_at: string
}

export interface AllocationPlan {
  id: string
  account_id: string
  plan_name: string
  carrier_id: string
  product_id: string
  total_samples: number
  start_date: string
  end_date: string
  status: 'active' | 'completed' | 'archived'
  applied_date: string
  created_at: string
  updated_at: string
  created_by?: string
  applied_by?: string
}

export interface AllocationPlanDetail {
  id: string
  account_id: string
  plan_id: string
  origin_node_id: string
  destination_node_id: string
  fecha_programada: string
  week_number: number
  month: number
  year: number
  status: 'pending' | 'notified' | 'sent' | 'received' | 'cancelled' | 'invalid' | 'transfer_error'
  // Tag and panelist fields
  tag_id?: string
  origin_panelist_id?: string
  destination_panelist_id?: string
  origin_panelist_name?: string
  destination_panelist_name?: string
  // Operation timestamps
  assigned_at?: string
  sent_at?: string
  delivered_at?: string
  received_at?: string;
  // Validation and transfer fields
  validation_errors?: string[] | null;
  transferred_to_one_db_at?: string | null;
  transfer_error_message?: string | null;
  // Reassignment fields
  original_origin_node_id?: string
  original_destination_node_id?: string
  reassignment_reason?: 'panelist_unavailable' | 'manual' | 'rebalancing'
  reassigned_at?: string
  reassigned_by?: string
  created_at: string
  updated_at: string
}

export interface GeneratedAllocationPlanWithDetails extends GeneratedAllocationPlan {
  carrier?: Carrier
  product?: Product
  details_count?: number
}

export interface AllocationPlanWithDetails extends AllocationPlan {
  carrier?: Carrier
  product?: Product
  details_count?: number
}

export interface AllocationPlanDetailWithRelations extends AllocationPlanDetail {
  plan?: AllocationPlan
  origin_node?: Node
  destination_node?: Node
  origin_city?: City
  destination_city?: City
  carrier?: Carrier
  product?: Product
  origin_panelist?: Panelist
  destination_panelist?: Panelist
  // Availability status fields from view
  origin_city_id?: string
  origin_city_name?: string
  origin_panelist_status?: string
  origin_availability_status?: 'unassigned' | 'unavailable' | 'available' | 'inactive'
  origin_unavailability_reason?: string
  destination_city_id?: string
  destination_city_name?: string
  destination_panelist_status?: string
  destination_availability_status?: 'unassigned' | 'unavailable' | 'available' | 'inactive'
  destination_unavailability_reason?: string
}

export interface Node {
  id: string
  account_id: string
  city_id: string
  auto_id: string
  status: 'active' | 'inactive'
  created_at: string
  updated_at: string
}

export interface Panelist {
  id: string
  account_id: string
  panelist_code: string
  name: string
  email: string
  mobile: string
  telegram_id?: string
  address_line1?: string
  address_line2?: string
  postal_code?: string
  address_city?: string
  address_country?: string
  /** Panelist's residence city, referencing the account's city catalog (cities.id).
   *  `address_city` is kept as optional free-text detail (locality/neighbourhood). */
  city_id?: string | null
  node_id: string
  language: SupportedLanguage
  status: 'active' | 'inactive' | 'unavailable_temp'
  created_at: string
  updated_at: string
  created_by?: string
  updated_by?: string
}

export interface PanelistUnavailability {
  id: string
  account_id: string
  panelist_id: string
  start_date: string
  end_date: string
  reason: 'vacation' | 'sick_leave' | 'personal' | 'training' | 'other'
  notes?: string
  status: 'active' | 'cancelled'
  created_at: string
  updated_at: string
  created_by?: string
  updated_by?: string
}

export interface PanelistWithNode extends Panelist {
  node?: Node
  city?: City
  region?: Region
}

export interface PanelistUnavailabilityWithPanelist extends PanelistUnavailability {
  panelist?: Panelist
}

export type PanelistAvailabilityStatus = 'available' | 'unavailable' | 'inactive' | 'no_panelist'

export interface NodeWithPanelist extends Node {
  panelist?: Panelist
  panelist_availability?: PanelistAvailabilityStatus
}

export interface Profile {
  id: string
  email: string
  full_name: string | null
  role: Role
  account_id: string | null
  status: Status
  preferred_language?: string
  created_at: string
  updated_at: string
}

export interface ProfileWithAccount extends Profile {
  account?: Account
}

export type Database = {
  public: {
    Tables: {
      accounts: {
        Row: Account
        Insert: {
          name: string
          slug: string
          status?: Status
        }
        Update: {
          name?: string
          slug?: string
          status?: Status
        }
      }
      profiles: {
        Row: Profile
        Insert: {
          id: string
          email: string
          full_name?: string | null
          role: Role
          account_id?: string | null
          status?: Status
        }
        Update: {
          email?: string
          full_name?: string | null
          role?: Role
          account_id?: string | null
          status?: Status
        }
      }
    }
  }
}

export type ProposalAction = 'reroute' | 'shift_date' | 'cancel' | 'none'
export type ProposalStatus = 'pending' | 'confirmed' | 'dismissed'
export type AffectedRole = 'origin' | 'destination'

export interface ReassignmentProposal {
  id: string
  account_id: string
  unavailability_id: string
  allocation_plan_detail_id: string
  affected_role: AffectedRole
  sample_status_at_detection: string | null
  suggested_action: ProposalAction
  suggested_target_node_id: string | null
  suggested_date: string | null
  suggested_reason: string | null
  final_action: string | null
  final_target_node_id: string | null
  final_date: string | null
  status: ProposalStatus
  confirmed_by: string | null
  confirmed_at: string | null
  created_at: string
  updated_at: string
  // joins (opcionales, poblados por el hook)
  detail?: { id: string; fecha_programada: string; status: string; origin_node_id: string; destination_node_id: string } | null
  suggested_target_node?: { id: string; auto_id: string } | null
}

export interface IncidentInboxRow {
  unavailability_id: string
  panelist_name: string
  panelist_code: string
  node_label: string
  city_name: string
  start_date: string
  end_date: string
  affected_count: number
  origin_count: number
  destination_count: number
  pending_count: number
}

export interface RerouteCandidate {
  node_id: string
  node_name: string
  city_id: string
  is_available: boolean
}

export interface UnavailabilityHeader {
  unavailability_id: string
  panelist_name: string
  panelist_code: string
  start_date: string
  end_date: string
  reason: string | null
  node_id: string | null
  node_code: string | null
  city_id: string | null
  city_name: string | null
}

export interface CityLoadWeek {
  week_number: number
  week_start_date: string
  week_end_date: string
}

export interface CityNodeLoadRow {
  node_id: string
  node_code: string
  saturation_level: 'normal' | 'high' | 'saturated'
  counts: Record<number, { sent: number; received: number }> // week_number -> {send, receive}
  total: { sent: number; received: number }
}

export type ReportedIncidentCategory =
  | 'missing_materials' | 'unreadable_label_receipt' | 'parcel_damaged' | 'parcel_returned'
  | 'how_to_send' | 'unavailability_request' | 'tag_photo_problem' | 'contact_data_change' | 'other'

export type ReportedIncidentStatus = 'open' | 'in_progress' | 'resolved' | 'dismissed'

export interface ReportedIncident {
  id: string
  account_id: string
  panelist_id: string
  category: ReportedIncidentCategory
  status: ReportedIncidentStatus
  description: string | null
  photo_url: string | null
  allocation_plan_detail_id: string | null
  linked_unavailability_id: string | null
  payload: Record<string, any> | null
  resolution_note: string | null
  reply_to_panelist: string | null
  reply_status: 'none' | 'pending_send' | 'sent'
  reported_at: string
  // joins para la bandeja
  panelist_name?: string
  panelist_code?: string
}
