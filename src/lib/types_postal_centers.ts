// Types for Network Diagnostics Module - Postal Centers and Readers

export interface PostalCenter {
  id: string
  account_id: string
  code: string
  name: string
  description?: string
  opening_hour?: string // TIME format "HH:MM:SS"
  cutoff_time?: string // TIME format "HH:MM:SS"
  calculation_mode?: 'natural_days' | 'working_days' | null
  mixed_reader_gap_minutes?: number | null
  is_active: boolean
  created_at: string
  updated_at: string
  created_by?: string
  updated_by?: string
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
}

export interface PostalCenterWithReaders extends PostalCenter {
  readers?: Reader[]
}

export interface PostalCenterFormData {
  code: string
  name: string
  description?: string
  opening_hour?: string
  cutoff_time?: string
  calculation_mode?: 'natural_days' | 'working_days' | null
  mixed_reader_gap_minutes?: number | null
  is_active: boolean
}

export interface ReaderFormData {
  reader_id: string
  name: string
  description?: string
  type: 'Entry' | 'Exit' | 'Mixed'
  mixed_reader_gap_minutes?: number | null
  is_active: boolean
}
