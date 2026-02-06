import { createClient } from '@supabase/supabase-js'

const supabaseUrl = (window as any).ENV?.VITE_SUPABASE_URL || import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = (window as any).ENV?.VITE_SUPABASE_ANON_KEY || import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Missing Supabase environment variables')
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
