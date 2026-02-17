import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://sehbnpgzqljrsqimwyuz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDg5NDMxMSwiZXhwIjoyMDgwNDcwMzExfQ.8aPEi2qUYMiKBi__jAu-8gnkc3Z5b1jrPpbjBYQPf4k'
)

const DEMO2_ACCOUNT = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'

console.log('🧪 MINIMAL DEMO DATA GENERATION')
console.log('━'.repeat(60))
console.log('Purpose: Verify pipeline construction is correct')
console.log('Data: 5 tags, 2 centers, minimal but complete\n')

async function main() {
  // ========================================
  // STEP 1: Clean existing data
  // ========================================
  console.log('📦 STEP 1: Cleaning existing demo data...')
  
  await supabase.from('journey_paths').delete().eq('account_id', DEMO2_ACCOUNT)
  await supabase.from('journey_segments').delete().eq('account_id', DEMO2_ACCOUNT)
  await supabase.from('processed_events').delete().eq('account_id', DEMO2_ACCOUNT)
  await supabase.from('rfid_events_raw').delete().eq('account_id', DEMO2_ACCOUNT)
  await supabase.from('one_db').delete().eq('account_id', DEMO2_ACCOUNT)
  await supabase.from('readers').delete().eq('account_id', DEMO2_ACCOUNT)
  
  console.log('  ✅ Cleaned\n')
  
  // ========================================
  // STEP 2: Get reference data
  // ========================================
  console.log('📋 STEP 2: Loading reference data...')
  
  const { data: centers } = await supabase
    .from('postal_centers')
    .select('id, code, name, city')
    .eq('account_id', DEMO2_ACCOUNT)
    .in('city', ['Los Angeles', 'Baltimore'])
    .ilike('name', '%Local%')
    .order('city')
  
  const { data: carriers } = await supabase
    .from('carriers')
    .select('id, name')
    .eq('account_id', DEMO2_ACCOUNT)
    .limit(1)
  
  const { data: products } = await supabase
    .from('products')
    .select('id, code')
    .eq('account_id', DEMO2_ACCOUNT)
    .limit(1)
  
  if (!centers || centers.length < 2 || !carriers || !products) {
    console.error('  ❌ Missing reference data')
    console.log('     Centers:', centers?.length || 0)
    console.log('     Carriers:', carriers?.length || 0)
    console.log('     Products:', products?.length || 0)
    return
  }
  
  const laCenter = centers.find(c => c.city === 'Los Angeles')
  const balCenter = centers.find(c => c.city === 'Baltimore')
  const carrier = carriers[0]
  const product = products[0]
  
  console.log(`  ✅ LA Center: ${laCenter.name}`)
  console.log(`  ✅ BAL Center: ${balCenter.name}`)
  console.log(`  ✅ Carrier: ${carrier.name}`)
  console.log(`  ✅ Product: ${product.code}\n`)
  
  // ========================================
  // STEP 3: Skip allocation plan (not needed for demo)
  // ========================================
  console.log('ℹ️  STEP 3: Skipping allocation plan (using direct one_db)\n')
  
  // ========================================
  // STEP 5: Create Readers
  // ========================================
  console.log('📱 STEP 5: Creating readers...')
  
  const readers = [
    { center: laCenter, type: 'Entry', suffix: 'ENTRY' },
    { center: laCenter, type: 'Exit', suffix: 'EXIT' },
    { center: balCenter, type: 'Entry', suffix: 'ENTRY' },
    { center: balCenter, type: 'Exit', suffix: 'EXIT' }
  ].map(r => ({
    account_id: DEMO2_ACCOUNT,
    reader_id: `${r.center.code}-${r.suffix}`,
    name: `${r.center.name} - ${r.type} Reader`,
    description: `${r.type} reader for ${r.center.name}`,
    type: r.type,
    postal_center_id: r.center.id,
    is_active: true
  }))
  
  const { error: readerError } = await supabase.from('readers').insert(readers)
  
  if (readerError) {
    console.log(`  ⚠️  ${readerError.message}`)
  } else {
    console.log(`  ✅ Created ${readers.length} readers\n`)
  }
  
  // ========================================
  // STEP 4: Create ONE DB entries
  // ========================================
  console.log('📊 STEP 4: Creating ONE DB entries...')
  
  const baseTime = new Date('2026-02-15T08:00:00Z')
  const oneDbEntries = []
  
  for (let i = 1; i <= 5; i++) {
    const sentAt = new Date(baseTime.getTime() + i * 3600000) // +1 hour each
    const receivedAt = new Date(sentAt.getTime() + 2 * 24 * 3600000) // +2 days
    
    oneDbEntries.push({
      account_id: DEMO2_ACCOUNT,
      allocation_detail_id: null,
      tag_id: `DEMO-TAG-${String(i).padStart(3, '0')}`,
      plan_name: 'Demo - Route Path Analysis',
      carrier_name: carrier.name,
      product_name: product.code,
      origin_city_name: 'Los Angeles',
      destination_city_name: 'Baltimore',
      sent_at: sentAt.toISOString(),
      received_at: receivedAt.toISOString(),
      total_transit_days: 2,
      business_transit_days: 2,
      on_time_delivery: true,
      source_data_snapshot: { demo: true }
    })
  }
  
  const { error: oneDbError } = await supabase.from('one_db').insert(oneDbEntries)
  
  if (oneDbError) {
    console.error(`  ❌ ${oneDbError.message}`)
    return
  }
  
  console.log(`  ✅ Created ${oneDbEntries.length} ONE DB entries\n`)
  
  // ========================================
  // STEP 6: Create RFID Events
  // ========================================
  console.log('📝 STEP 6: Creating RFID events...')
  
  const events = []
  
  for (let i = 1; i <= 5; i++) {
    const tagId = `DEMO-TAG-${String(i).padStart(3, '0')}`
    let currentTime = new Date(baseTime.getTime() + i * 3600000) // Stagger by 1 hour
    
    // LA Entry
    events.push({
      account_id: DEMO2_ACCOUNT,
      event_id: `${tagId}-LA-ENTRY-${currentTime.getTime()}`,
      tag_id: tagId,
      reader_id: `${laCenter.code}-ENTRY`,
      read_local_datetime: currentTime.toISOString(),
      is_processed: false
    })
    
    // LA Exit (30 minutes later)
    currentTime = new Date(currentTime.getTime() + 30 * 60000)
    events.push({
      account_id: DEMO2_ACCOUNT,
      event_id: `${tagId}-LA-EXIT-${currentTime.getTime()}`,
      tag_id: tagId,
      reader_id: `${laCenter.code}-EXIT`,
      read_local_datetime: currentTime.toISOString(),
      is_processed: false
    })
    
    // Transit (24 hours)
    currentTime = new Date(currentTime.getTime() + 24 * 3600000)
    
    // BAL Entry
    events.push({
      account_id: DEMO2_ACCOUNT,
      event_id: `${tagId}-BAL-ENTRY-${currentTime.getTime()}`,
      tag_id: tagId,
      reader_id: `${balCenter.code}-ENTRY`,
      read_local_datetime: currentTime.toISOString(),
      is_processed: false
    })
    
    // BAL Exit (45 minutes later)
    currentTime = new Date(currentTime.getTime() + 45 * 60000)
    events.push({
      account_id: DEMO2_ACCOUNT,
      event_id: `${tagId}-BAL-EXIT-${currentTime.getTime()}`,
      tag_id: tagId,
      reader_id: `${balCenter.code}-EXIT`,
      read_local_datetime: currentTime.toISOString(),
      is_processed: false
    })
  }
  
  const { error: eventsError } = await supabase.from('rfid_events_raw').insert(events)
  
  if (eventsError) {
    console.error(`  ❌ ${eventsError.message}`)
    return
  }
  
  console.log(`  ✅ Created ${events.length} RFID events\n`)
  
  // ========================================
  // STEP 7: Run Pipeline
  // ========================================
  console.log('⚙️  STEP 7: Running pipeline...')
  
  const { data: result, error: pipeError } = await supabase.rpc('process_all_accounts_pipeline')
  
  if (pipeError) {
    console.error('  ❌ Pipeline error:', pipeError.message)
  } else {
    const demo2 = result?.find(r => r.account_id === DEMO2_ACCOUNT)
    if (demo2) {
      console.log('  ✅ Pipeline complete:')
      console.log(`     Events consolidated: ${demo2.events_consolidated}`)
      console.log(`     Segments created: ${demo2.segments_created}`)
      console.log(`     Paths created: ${demo2.paths_created || 0}`)
      console.log(`     Execution time: ${demo2.total_execution_time_ms}ms\n`)
    }
  }
  
  // ========================================
  // STEP 8: Verify Results
  // ========================================
  console.log('🔍 STEP 8: Verifying results...')
  
  const { data: paths, count } = await supabase
    .from('journey_paths')
    .select('*', { count: 'exact' })
    .eq('account_id', DEMO2_ACCOUNT)
  
  console.log(`\n  📊 Journey paths: ${count}`)
  
  if (paths && paths.length > 0) {
    const path = paths[0]
    console.log(`\n  ✅ Path found:`)
    console.log(`     ${path.origin_city_name} → ${path.destination_city_name}`)
    console.log(`     Tags: ${path.total_tags}`)
    console.log(`     Segments: ${path.segment_details?.length || 0}`)
    
    if (path.segment_details && path.segment_details.length > 0) {
      console.log(`\n  📍 Segment Details:`)
      path.segment_details.forEach((seg, idx) => {
        const from = seg.from_center_name || '❌ NULL'
        const to = seg.to_center_name || '❌ NULL'
        console.log(`     ${idx + 1}. [${seg.segment_type}] ${from} → ${to}`)
        console.log(`        Cities: ${seg.from_city} → ${seg.to_city}`)
        console.log(`        Compliance: ${seg.compliance_rate}%`)
        console.log(`        Warning: ${seg.warning_threshold}%, Critical: ${seg.critical_threshold}%`)
      })
      
      const hasNulls = path.segment_details.some(s => !s.from_center_name || !s.to_center_name)
      
      if (hasNulls) {
        console.log(`\n  ⚠️  WARNING: Some center names are NULL`)
      } else {
        console.log(`\n  ✅ SUCCESS: All center names populated!`)
      }
    }
  } else {
    console.log(`\n  ⚠️  No paths created - checking intermediate steps...`)
    
    const { count: segCount } = await supabase
      .from('journey_segments')
      .select('*', { count: 'exact', head: true })
      .eq('account_id', DEMO2_ACCOUNT)
    
    const { count: procCount } = await supabase
      .from('processed_events')
      .select('*', { count: 'exact', head: true })
      .eq('account_id', DEMO2_ACCOUNT)
    
    console.log(`     Processed events: ${procCount}`)
    console.log(`     Journey segments: ${segCount}`)
    
    if (segCount > 0) {
      const { data: segSample } = await supabase
        .from('journey_segments')
        .select('from_postal_center_city, to_postal_center_city, origin_city_name, destination_city_name')
        .eq('account_id', DEMO2_ACCOUNT)
        .limit(1)
      
      if (segSample && segSample.length > 0) {
        console.log(`\n     Sample segment:`)
        console.log(`       from_city: ${segSample[0].from_postal_center_city}`)
        console.log(`       to_city: ${segSample[0].to_postal_center_city}`)
        console.log(`       origin: ${segSample[0].origin_city_name}`)
        console.log(`       dest: ${segSample[0].destination_city_name}`)
      }
    }
  }
  
  console.log('\n' + '━'.repeat(60))
  console.log('✅ MINIMAL DEMO COMPLETE!')
  console.log('\nNext: Deploy SQL migrations and frontend updates')
}

main()
