import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://sehbnpgzqljrsqimwyuz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDg5NDMxMSwiZXhwIjoyMDgwNDcwMzExfQ.8aPEi2qUYMiKBi__jAu-8gnkc3Z5b1jrPpbjBYQPf4k'
)

const DEMO2_ACCOUNT = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'

async function verify() {
  console.log('🔍 Verifying center names in journey_paths...\n')
  
  const { data: paths, error } = await supabase
    .from('journey_paths')
    .select('id, origin_city_name, destination_city_name, segment_details')
    .eq('account_id', DEMO2_ACCOUNT)
    .limit(10)
  
  if (error) {
    console.error('❌ Error:', error)
    return
  }
  
  if (!paths || paths.length === 0) {
    console.log('⚠️  No journey_paths found. Run aggregation first:')
    console.log('   node /tmp/ONEMS/run_aggregation_demo2.mjs')
    return
  }
  
  console.log(`Found ${paths.length} paths. Checking segment_details...\n`)
  
  let totalSegments = 0
  let segmentsWithNames = 0
  let segmentsWithNulls = 0
  
  paths.forEach((path, pathIdx) => {
    console.log(`Path ${pathIdx + 1}: ${path.origin_city_name} → ${path.destination_city_name}`)
    
    if (!path.segment_details || path.segment_details.length === 0) {
      console.log('  ⚠️  No segment_details found\n')
      return
    }
    
    path.segment_details.forEach((seg, segIdx) => {
      totalSegments++
      
      const hasFromName = seg.from_center_name && seg.from_center_name !== null
      const hasToName = seg.to_center_name && seg.to_center_name !== null
      
      if (hasFromName && hasToName) {
        segmentsWithNames++
      } else {
        segmentsWithNulls++
      }
      
      console.log(`  Segment ${segIdx + 1}:`)
      console.log(`    Type: ${seg.segment_type}`)
      console.log(`    From: ${seg.from_center_name || '❌ NULL'} (${seg.from_city})`)
      console.log(`    To: ${seg.to_center_name || '❌ NULL'} (${seg.to_city})`)
      console.log(`    Compliance: ${seg.compliance_rate}%`)
      console.log(`    Tags: ${seg.tags_count}`)
    })
    console.log('')
  })
  
  console.log('━'.repeat(60))
  console.log('SUMMARY:')
  console.log(`  Total segments: ${totalSegments}`)
  console.log(`  ✅ With center names: ${segmentsWithNames} (${((segmentsWithNames/totalSegments)*100).toFixed(1)}%)`)
  console.log(`  ❌ With NULL names: ${segmentsWithNulls} (${((segmentsWithNulls/totalSegments)*100).toFixed(1)}%)`)
  console.log('━'.repeat(60))
  
  if (segmentsWithNulls > 0) {
    console.log('\n⚠️  ISSUE DETECTED: Some center names are NULL')
    console.log('\nPossible causes:')
    console.log('  1. from_postal_center_id in journey_segments does not match postal_centers.id')
    console.log('  2. postal_centers table is missing some centers')
    console.log('  3. Account isolation issue (wrong account_id)')
    
    console.log('\n🔧 Debugging steps:')
    console.log('  1. Check journey_segments:')
    console.log('     SELECT DISTINCT from_postal_center_id FROM journey_segments WHERE account_id = \'f4d823d2-93e6-4755-9a89-9da87e7fa86e\' LIMIT 5;')
    console.log('  2. Check postal_centers:')
    console.log('     SELECT id, name FROM postal_centers WHERE account_id = \'f4d823d2-93e6-4755-9a89-9da87e7fa86e\';')
    console.log('  3. Check for ID mismatches:')
    console.log('     SELECT js.from_postal_center_id, pc.name FROM journey_segments js LEFT JOIN postal_centers pc ON pc.id = js.from_postal_center_id WHERE js.account_id = \'f4d823d2-93e6-4755-9a89-9da87e7fa86e\' LIMIT 10;')
  } else {
    console.log('\n✅ SUCCESS: All center names are populated correctly!')
  }
}

verify()
