import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://sehbnpgzqljrsqimwyuz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDg5NDMxMSwiZXhwIjoyMDgwNDcwMzExfQ.8aPEi2qUYMiKBi__jAu-8gnkc3Z5b1jrPpbjBYQPf4k'
)

const DEMO2_ACCOUNT = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'

async function runAggregation() {
  console.log('🔄 Running aggregate_journey_paths for DEMO2 account...\n')
  
  // Clear existing paths
  console.log('🗑️  Clearing existing journey_paths...')
  const { error: deleteError } = await supabase
    .from('journey_paths')
    .delete()
    .eq('account_id', DEMO2_ACCOUNT)
  
  if (deleteError) {
    console.error('❌ Delete error:', deleteError)
  } else {
    console.log('✅ Cleared existing paths\n')
  }
  
  // Run aggregation
  console.log('⚙️  Executing aggregate_journey_paths...')
  const { data, error } = await supabase.rpc('aggregate_journey_paths', {
    p_account_id: DEMO2_ACCOUNT,
    p_since: null  // Use default (last 24 hours) or NULL to process all
  })
  
  if (error) {
    console.error('❌ Aggregation error:', error)
    console.error('\nPossible causes:')
    console.error('  1. Function not deployed yet - run SQL from /tmp/DEPLOY_THIS_SQL.sql first')
    console.error('  2. Syntax error in function - check Supabase logs')
    process.exit(1)
  }
  
  console.log('✅ Aggregation complete!')
  console.log('   Paths created:', data.paths_created)
  console.log('   Duration:', data.duration_seconds, 'seconds\n')
  
  // Verify results
  console.log('🔍 Verifying results...')
  const { data: paths, error: pathsError } = await supabase
    .from('journey_paths')
    .select('origin_city_name, destination_city_name, total_tags, segment_details')
    .eq('account_id', DEMO2_ACCOUNT)
    .order('total_tags', { ascending: false })
    .limit(3)
  
  if (pathsError) {
    console.error('❌ Query error:', pathsError)
  } else {
    console.log(`\n📊 Top ${paths.length} paths by volume:\n`)
    paths.forEach((path, idx) => {
      console.log(`${idx + 1}. ${path.origin_city_name} → ${path.destination_city_name}`)
      console.log(`   Tags: ${path.total_tags}`)
      console.log(`   Segments: ${path.segment_details?.length || 0}`)
      
      if (path.segment_details && path.segment_details.length > 0) {
        const seg = path.segment_details[0]
        console.log(`   First segment:`)
        console.log(`     - from_center_name: ${seg.from_center_name || 'NULL'}`)
        console.log(`     - to_center_name: ${seg.to_center_name || 'NULL'}`)
        console.log(`     - segment_type: ${seg.segment_type}`)
        console.log(`     - compliance_rate: ${seg.compliance_rate}%`)
      }
      console.log('')
    })
    
    // Check for NULL center names
    const hasNulls = paths.some(p => 
      p.segment_details?.some(s => !s.from_center_name || !s.to_center_name)
    )
    
    if (hasNulls) {
      console.log('⚠️  WARNING: Some center names are still NULL')
      console.log('   This means postal_centers table might not have matching IDs')
    } else {
      console.log('✅ All center names populated successfully!')
    }
  }
}

runAggregation()
