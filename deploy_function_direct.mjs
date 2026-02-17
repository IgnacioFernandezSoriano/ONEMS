import { createClient } from '@supabase/supabase-js'
import fs from 'fs'

const supabase = createClient(
  'https://sehbnpgzqljrsqimwyuz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTczNDQ1MTI2OSwiZXhwIjoyMDUwMDI3MjY5fQ.wLx8KHqzUZ8-kcVWxSvWRRnCBQrxH2-_FEeQqXfOECE'
)

async function main() {
  console.log('🔄 Re-running aggregation with updated function...')
  console.log('Note: Function should be deployed manually via Supabase Dashboard SQL Editor')
  console.log('SQL file: /tmp/ONEMS/supabase/migrations/20260214_phase4_aggregate_journey_paths.sql\n')
  
  // Clear existing data
  console.log('🗑️  Clearing existing journey_paths...')
  const { error: deleteError } = await supabase
    .from('journey_paths')
    .delete()
    .eq('account_id', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e')
  
  if (deleteError) {
    console.error('❌ Delete error:', deleteError)
  } else {
    console.log('✅ Cleared existing paths')
  }
  
  // Run aggregation
  console.log('\n🔄 Running aggregate_journey_paths...')
  const { data, error } = await supabase.rpc('aggregate_journey_paths', {
    p_account_id: 'f4d823d2-93e6-4755-9a89-9da87e7fa86e',
    p_since: '2024-01-01T00:00:00Z'
  })
  
  if (error) {
    console.error('❌ Aggregation error:', error)
    process.exit(1)
  }
  
  console.log('✅ Aggregation complete:', data)
  
  // Check results
  const { data: paths, error: pathsError } = await supabase
    .from('journey_paths')
    .select('id, origin_city_name, destination_city_name, segment_details')
    .eq('account_id', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e')
    .limit(1)
  
  if (pathsError) {
    console.error('❌ Query error:', pathsError)
  } else {
    console.log('\n📊 Sample journey path:')
    console.log('Origin:', paths[0]?.origin_city_name)
    console.log('Destination:', paths[0]?.destination_city_name)
    console.log('\nSegment details (first segment):')
    if (paths[0]?.segment_details && paths[0].segment_details.length > 0) {
      const seg = paths[0].segment_details[0]
      console.log('  from_center_name:', seg.from_center_name)
      console.log('  to_center_name:', seg.to_center_name)
      console.log('  from_city:', seg.from_city)
      console.log('  to_city:', seg.to_city)
      console.log('  segment_type:', seg.segment_type)
      console.log('  compliance_rate:', seg.compliance_rate)
    }
  }
}

main()
