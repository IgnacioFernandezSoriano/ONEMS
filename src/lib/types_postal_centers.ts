// Types for Network Diagnostics Module - Postal Centers and Readers

export interface PostalCenter {
  id: string
  account_id: string
  code: string
  name: string
  description?: string
  opening_hour?: string // TIME format "HH:MM:SS" (deprecated, use weekly_schedule)
  cutoff_time?: string // TIME format "HH:MM:SS" (deprecated, use weekly_schedule)
  calculation_mode?: 'natural_days' | 'working_days' | null
  city?: string
  state?: string
  country?: string
  latitude?: number
  longitude?: number
  timezone?: string
  is_active: boolean
  created_at: string
  updated_at: string
  created_by?: string
  updated_by?: string
  deleted_at?: string | null // Soft delete timestamp
}

export interface Reader {
  id: string
  account_id: string
  postal_center_id: string
  reader_id: string // ID del lector en EPCIS
  name: string
  description?: string
  type: 'Entry' | 'Exit' | 'Mixed'
  mixed_reader_gap_minutes?: number | null
  is_active: boolean
  created_at: string
  updated_at: string
  created_by?: string
  updated_by?: string
  deleted_at?: string | null // Soft delete timestamp
}

export interface PostalCenterWithReaders extends PostalCenter {
  readers?: Reader[]
}

export interface PostalCenterFormData {
  code: string
  name: string
  description?: string
  calculation_mode?: 'natural_days' | 'working_days' | null
  city?: string
  state?: string
  country?: string
  latitude?: number
  longitude?: number
  timezone?: string
  is_active: boolean
}

export interface ReaderFormData {
  reader_id: string
  name: string
  description?: string
  type: 'Entry' | 'Exit' | 'Mixed'
  postal_center_id?: string | null
  mixed_reader_gap_minutes?: number | null
  is_active: boolean
}
