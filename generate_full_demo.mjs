import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://sehbnpgzqljrsqimwyuz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDg5NDMxMSwiZXhwIjoyMDgwNDcwMzExfQ.8aPEi2qUYMiKBi__jAu-8gnkc3Z5b1jrPpbjBYQPf4k'
)

const DEMO2_ACCOUNT = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'

async function main() {
  console.log('🚀 COMPLETE ROUTE PATH ANALYSIS DEMO\n')
  console.log('━'.repeat(60))
  
  // ========================================
  // STEP 1: Clean data
  // ========================================
  console.log('\n📦 STEP 1: Cleaning data...')
  
  await supabase.from('journey_paths').delete().eq('account_id', DEMO2_ACCOUNT)
  await supabase.from('journey_segments').delete().eq('account_id', DEMO2_ACCOUNT)
  await supabase.from('processed_events').delete().eq('account_id', DEMO2_ACCOUNT)
  await supabase.from('rfid_events_raw').delete().eq('account_id', DEMO2_ACCOUNT)
  await supabase.from('one_db').delete().eq('account_id', DEMO2_ACCOUNT)
  
  console.log('  ✅ Cleaned')
  
  // ========================================
  // STEP 2: Get reference data
  // ========================================
  console.log('\n📋 STEP 2: Loading reference data...')
  
  const { data: centers } = await supabase
    .from('postal_centers')
    .select('id, code, name, city')
    .eq('account_id', DEMO2_ACCOUNT)
    .order('city')
  
  const { data: carriers } = await supabase
    .from('carriers')
    .select('id, name')
    .eq('account_id', DEMO2_ACCOUNT)
  
  const { data: products } = await supabase
    .from('products')
    .select('id, code, description')
    .eq('account_id', DEMO2_ACCOUNT)
  
  if (!centers || !carriers || !products) {
    console.error('  ❌ Missing reference data')
    return
  }
  
  // Select route: Los Angeles → Baltimore
  const laCenter = centers.find(c => c.city === 'Los Angeles' && c.name.includes('Local'))
  const balCenter = centers.find(c => c.city === 'Baltimore' && c.name.includes('Local'))
  
  const route = [laCenter, balCenter].filter(Boolean)
  
  if (route.length < 2) {
    console.error('  ❌ Need Los Angeles and Baltimore centers')
    return
  }
  
  const carrier = carriers[0]
  const product = products[0]
  
  console.log(`  ✅ Carrier: ${carrier.name}`)
  console.log(`  ✅ Product: ${product.code}`)
  console.log(`  ✅ Route: ${route.map(c => `${c.name} (${c.city})`).join(' → ')}`)
  
  // ========================================
  // STEP 3: Create readers
  // ========================================
  console.log('\n📱 STEP 3: Creating readers...')
  
  const readers = []
  for (const center of route) {
    readers.push({
      account_id: DEMO2_ACCOUNT,
      reader_id: `${center.code}-ENTRY`,  // LPI
      name: `${center.name} - Entry Reader`,
      description: `Entry reader for ${center.name}`,
      type: 'entry',
      postal_center_id: center.id,
      is_active: true,
      created_at: new Date().toISOString()
    })
    
    readers.push({
      account_id: DEMO2_ACCOUNT,
      reader_id: `${center.code}-EXIT`,  // LPI
      name: `${center.name} - Exit Reader`,
      description: `Exit reader for ${center.name}`,
      type: 'exit',
      postal_center_id: center.id,
      is_active: true,
      created_at: new Date().toISOString()
    })
  }
  
  const { error: readerError } = await supabase.from('readers').insert(readers)
  
  if (readerError) {
    console.log(`  ⚠️  ${readerError.message}`)
  } else {
    console.log(`  ✅ Created ${readers.length} readers`)
  }
  
  // ========================================
  // STEP 4: Create ONE DB entries
  // ========================================
  console.log('\n📊 STEP 4: Creating ONE DB entries...')
  
  const oneDbEntries = []
  for (let i = 1; i <= 30; i++) {
    oneDbEntries.push({
      account_id: DEMO2_ACCOUNT,
      tag_id: `DEMO-TAG-${String(i).padStart(4, '0')}`,
      plan_name: 'Route Path Analysis Demo',
      carrier_name: carrier.name,
      product_name: product.code,
      origin_city_name: route[0].city,
      destination_city_name: route[1].city,
      created_at: new Date().toISOString()
    })
  }
  
  const { error: oneDbError } = await supabase.from('one_db').insert(oneDbEntries)
  
  if (oneDbError) {
    console.error(`  ❌ ${oneDbError.message}`)
    return
  }
  
  console.log(`  ✅ Created ${oneDbEntries.length} ONE DB entries`)
  
  // ========================================
  // STEP 5: Generate RFID events
  // ========================================
  console.log('\n📝 STEP 5: Generating RFID events...')
  
  const events = []
  const baseTime = new Date('2026-02-15T08:00:00Z')
  
  for (let tagNum = 1; tagNum <= 30; tagNum++) {
    const tagId = `DEMO-TAG-${String(tagNum).padStart(4, '0')}`
    let currentTime = new Date(baseTime.getTime() + tagNum * 120000) // Stagger 2 min
    
    for (let i = 0; i < route.length; i++) {
      const center = route[i]
      
      // Entry
      events.push({
        account_id: DEMO2_ACCOUNT,
        event_id: `${tagId}-${center.code}-ENTRY-${currentTime.getTime()}`,
        tag_id: tagId,
        reader_id: `${center.code}-ENTRY`,
        read_local_datetime: currentTime.toISOString(),
        is_processed: false
      })
      
      // Time in center: 30-90 min
      currentTime = new Date(currentTime.getTime() + (30 + Math.random() * 60) * 60000)
      
      // Exit
      events.push({
        account_id: DEMO2_ACCOUNT,
        event_id: `${tagId}-${center.code}-EXIT-${currentTime.getTime()}`,
        tag_id: tagId,
        reader_id: `${center.code}-EXIT`,
        read_local_datetime: currentTime.toISOString(),
        is_processed: false
      })
      
      // Transit: 60-180 min
      if (i < route.length - 1) {
        currentTime = new Date(currentTime.getTime() + (60 + Math.random() * 120) * 60000)
      }
    }
  }
  
  console.log(`  Generated ${events.length} events`)
  
  // Insert in batches
  for (let i = 0; i < events.length; i += 100) {
    const batch = events.slice(i, i + 100)
    const { error } = await supabase.from('rfid_events_raw').insert(batch)
    
    if (error) {
      console.error(`  ❌ Batch error: ${error.message}`)
    } else {
      console.log(`  ✅ Batch ${Math.floor(i/100) + 1} inserted`)
    }
  }
  
  // ========================================
  // STEP 6: Run pipeline
  // ========================================
  console.log('\n⚙️  STEP 6: Running pipeline...')
  
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
      console.log(`     Execution time: ${demo2.total_execution_time_ms}ms`)
    }
  }
  
  // ========================================
  // STEP 7: Verify results
  // ========================================
  console.log('\n🔍 STEP 7: Verifying results...')
  
  const { data: paths, count } = await supabase
    .from('journey_paths')
    .select('*', { count: 'exact' })
    .eq('account_id', DEMO2_ACCOUNT)
  
  console.log(`\n  📊 Journey paths: ${count}`)
  
  if (paths && paths.length > 0) {
    const path = paths[0]
    console.log(`\n  Path: ${path.origin_city_name} → ${path.destination_city_name}`)
    console.log(`  Tags: ${path.total_tags}`)
    console.log(`  Segments: ${path.segment_details?.length || 0}`)
    
    if (path.segment_details && path.segment_details.length > 0) {
      console.log(`\n  📍 Segment Details:`)
      path.segment_details.forEach((seg, idx) => {
        const from = seg.from_center_name || '❌ NULL'
        const to = seg.to_center_name || '❌ NULL'
        console.log(`     ${idx + 1}. [${seg.segment_type}] ${from} → ${to}`)
        console.log(`        ${seg.from_city} → ${seg.to_city}`)
        console.log(`        Compliance: ${seg.compliance_rate}%`)
      })
      
      const hasNulls = path.segment_details.some(s => !s.from_center_name || !s.to_center_name)
      
      if (hasNulls) {
        console.log(`\n  ⚠️  WARNING: Some center names are NULL`)
      } else {
        console.log(`\n  ✅ SUCCESS: All center names populated!`)
      }
    }
  } else {
    console.log(`\n  ⚠️  No paths created`)
    
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
  }
  
  console.log('\n━'.repeat(60))
  console.log('✅ DEMO COMPLETE!')
  console.log('\nYou can now:')
  console.log('  1. Deploy frontend: ONEMS_FINAL_WITH_SQL_FIX.zip')
  console.log('  2. Open Route Path Analysis')
  console.log('  3. Select: Carrier A → Los Angeles → Baltimore')
  console.log('  4. Verify center names appear in Segment Flow')
}

main()
