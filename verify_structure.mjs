import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://sehbnpgzqljrsqimwyuz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDg5NDMxMSwiZXhwIjoyMDgwNDcwMzExfQ.8aPEi2qUYMiKBi__jAu-8gnkc3Z5b1jrPpbjBYQPf4k'
)

const DEMO2_ACCOUNT = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'

async function checkStructure() {
  console.log('🔍 Checking database structure...\n')
  
  // 1. Check journey_segments structure
  console.log('1️⃣ Checking journey_segments...')
  const { data: segments, error: segError } = await supabase
    .from('journey_segments')
    .select('*')
    .eq('account_id', DEMO2_ACCOUNT)
    .limit(1)
  
  if (segError) {
    console.error('❌ Error:', segError)
  } else if (segments && segments.length > 0) {
    console.log('✅ journey_segments fields:')
    console.log(Object.keys(segments[0]).join(', '))
  }
  
  // 2. Check postal_centers structure
  console.log('\n2️⃣ Checking postal_centers...')
  const { data: centers, error: centerError } = await supabase
    .from('postal_centers')
    .select('*')
    .eq('account_id', DEMO2_ACCOUNT)
    .limit(1)
  
  if (centerError) {
    console.error('❌ Error:', centerError)
  } else if (centers && centers.length > 0) {
    console.log('✅ postal_centers fields:')
    console.log(Object.keys(centers[0]).join(', '))
    console.log('\nSample center:')
    console.log('  ID:', centers[0].id)
    console.log('  Name:', centers[0].name)
    console.log('  City:', centers[0].city)
    console.log('  Code:', centers[0].code)
  }
  
  // 3. Check journey_paths structure
  console.log('\n3️⃣ Checking journey_paths...')
  const { data: paths, error: pathError } = await supabase
    .from('journey_paths')
    .select('*')
    .eq('account_id', DEMO2_ACCOUNT)
    .limit(1)
  
  if (pathError) {
    console.error('❌ Error:', pathError)
  } else if (paths && paths.length > 0) {
    console.log('✅ journey_paths fields:')
    console.log(Object.keys(paths[0]).join(', '))
    console.log('\nSample path:')
    console.log('  Origin:', paths[0].origin_city_name)
    console.log('  Destination:', paths[0].destination_city_name)
    console.log('  Segment details keys:', paths[0].segment_details ? Object.keys(paths[0].segment_details[0] || {}).join(', ') : 'N/A')
  }
  
  // 4. Check SLAs structure
  console.log('\n4️⃣ Checking slas...')
  const { data: slas, error: slaError } = await supabase
    .from('slas')
    .select('*')
    .eq('account_id', DEMO2_ACCOUNT)
    .limit(1)
  
  if (slaError) {
    console.error('❌ Error:', slaError)
  } else if (slas && slas.length > 0) {
    console.log('✅ slas fields:')
    console.log(Object.keys(slas[0]).join(', '))
  }
  
  // 5. Check if aggregate function exists and its structure
  console.log('\n5️⃣ Testing aggregate_journey_paths function...')
  const { data: funcTest, error: funcError } = await supabase.rpc('aggregate_journey_paths', {
    p_account_id: DEMO2_ACCOUNT,
    p_since: new Date(Date.now() - 24*60*60*1000).toISOString()
  })
  
  if (funcError) {
    console.error('❌ Function error:', funcError.message)
  } else {
    console.log('✅ Function executed:', funcTest)
  }
  
  // 6. Check updated journey_paths after aggregation
  console.log('\n6️⃣ Checking journey_paths after aggregation...')
  const { data: updatedPaths, error: updatedError } = await supabase
    .from('journey_paths')
    .select('origin_city_name, destination_city_name, segment_details')
    .eq('account_id', DEMO2_ACCOUNT)
    .limit(1)
  
  if (updatedError) {
    console.error('❌ Error:', updatedError)
  } else if (updatedPaths && updatedPaths.length > 0) {
    console.log('✅ Updated path segment_details:')
    const seg = updatedPaths[0].segment_details?.[0]
    if (seg) {
      console.log('  Keys:', Object.keys(seg).join(', '))
      console.log('\n  Sample values:')
      console.log('    from_center_id:', seg.from_center_id)
      console.log('    from_center_name:', seg.from_center_name)
      console.log('    from_city:', seg.from_city)
      console.log('    segment_type:', seg.segment_type)
      console.log('    compliance_rate:', seg.compliance_rate)
    }
  }
}

checkStructure()
