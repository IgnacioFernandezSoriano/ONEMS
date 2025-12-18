export type Role = 'superadmin' | 'admin' | 'user'
export type Status = 'active' | 'inactive'

export interface Account {
  id: string
  name: string
  slug: string
  status: Status
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
  node_id: string
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
  reason: 'vacation' | 'sick' | 'personal' | 'training' | 'other'
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
