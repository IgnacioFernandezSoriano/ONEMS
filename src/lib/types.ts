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
  classification?: 'A' | 'B' | 'C'
  latitude?: number
  longitude?: number
  status: 'active' | 'inactive'
  created_at: string
  updated_at: string
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
