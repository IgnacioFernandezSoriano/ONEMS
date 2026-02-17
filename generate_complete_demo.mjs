import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://sehbnpgzqljrsqimwyuz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDg5NDMxMSwiZXhwIjoyMDgwNDcwMzExfQ.8aPEi2qUYMiKBi__jAu-8gnkc3Z5b1jrPpbjBYQPf4k'
)

const DEMO2_ACCOUNT = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'

async function main() {
  console.log('🚀 Generating Complete Route Path Analysis Demo Data\n')
  console.log('━'.repeat(60))
  
  // ========================================
  // STEP 1: Clean existing data
  // ========================================
  console.log('\n📦 STEP 1: Cleaning existing data...')
  
  const tables = ['journey_paths', 'journey_segments', 'processed_events', 'rfid_events_raw']
  
  for (const table of tables) {
    const { error } = await supabase
      .from(table)
      .delete()
      .eq('account_id', DEMO2_ACCOUNT)
    
    if (error) {
      console.log(`  ⚠️  ${table}: ${error.message}`)
    } else {
      console.log(`  ✅ ${table}: cleared`)
    }
  }
  
  // ========================================
  // STEP 2: Get reference data
  // ========================================
  console.log('\n📋 STEP 2: Loading reference data...')
  
  // Get postal centers
  const { data: centers } = await supabase
    .from('postal_centers')
    .select('id, code, name, city')
    .eq('account_id', DEMO2_ACCOUNT)
    .order('city')
  
  console.log(`  ✅ Found ${centers?.length || 0} postal centers`)
  
  if (!centers || centers.length === 0) {
    console.error('  ❌ No postal centers found. Cannot generate demo data.')
    return
  }
  
  // Group centers by city for routing
  const centersByCity = {}
  centers.forEach(c => {
    if (!centersByCity[c.city]) centersByCity[c.city] = []
    centersByCity[c.city].push(c)
  })
  
  const cities = Object.keys(centersByCity)
  console.log(`  ✅ Cities: ${cities.join(', ')}`)
  
  // Get mobile readers
  const { data: readers } = await supabase
    .from('mobile_readers')
    .select('id, code, postal_center_id')
    .eq('account_id', DEMO2_ACCOUNT)
  
  console.log(`  ✅ Found ${readers?.length || 0} mobile readers`)
  
  // ========================================
  // STEP 3: Generate RFID events
  // ========================================
  console.log('\n📝 STEP 3: Generating RFID events...')
  
  // Generate 30 tags traveling: Los Angeles → Baltimore
  const events = []
  const baseTime = new Date('2026-02-15T08:00:00Z')
  
  // Define route
  const route = [
    centersByCity['Los Angeles']?.[0],  // Los Angeles Local Center
    centersByCity['Los Angeles']?.[1],  // Los Angeles Regional Center
    centersByCity['Baltimore']?.[1],    // Baltimore Regional Center
    centersByCity['Baltimore']?.[0]     // Baltimore Local Center
  ].filter(Boolean)
  
  console.log(`  Route: ${route.map(c => c.name).join(' → ')}`)
  
  for (let tagNum = 1; tagNum <= 30; tagNum++) {
    const tagId = `TAG-DEMO-${String(tagNum).padStart(4, '0')}`
    
    let currentTime = new Date(baseTime.getTime() + tagNum * 120000) // Stagger by 2 minutes
    
    for (let i = 0; i < route.length; i++) {
      const center = route[i]
      
      // Find readers for this center
      const centerReaders = readers?.filter(r => r.postal_center_id === center.id) || []
      const entryReader = centerReaders.find(r => r.code.includes('ENTRY')) || centerReaders[0]
      const exitReader = centerReaders.find(r => r.code.includes('EXIT')) || centerReaders[1] || centerReaders[0]
      
      if (!entryReader) {
        console.log(`  ⚠️  No reader found for ${center.name}, skipping`)
        continue
      }
      
      // Entry event
      events.push({
        account_id: DEMO2_ACCOUNT,
        event_id: `EVT-${tagId}-${center.code}-ENTRY-${currentTime.getTime()}`,
        tag_id: tagId,
        reader_id: entryReader.code,
        read_local_datetime: currentTime.toISOString(),
        is_processed: false,
        created_at: new Date().toISOString()
      })
      
      // Time in center: 30-90 minutes
      currentTime = new Date(currentTime.getTime() + (30 + Math.random() * 60) * 60000)
      
      // Exit event
      if (exitReader) {
        events.push({
          account_id: DEMO2_ACCOUNT,
          event_id: `EVT-${tagId}-${center.code}-EXIT-${currentTime.getTime()}`,
          tag_id: tagId,
          reader_id: exitReader.code,
          read_local_datetime: currentTime.toISOString(),
          is_processed: false,
          created_at: new Date().toISOString()
        })
      }
      
      // Transit time to next center: 60-180 minutes
      if (i < route.length - 1) {
        currentTime = new Date(currentTime.getTime() + (60 + Math.random() * 120) * 60000)
      }
    }
  }
  
  console.log(`  Generated ${events.length} events for 30 tags`)
  
  // Insert events in batches
  const batchSize = 100
  for (let i = 0; i < events.length; i += batchSize) {
    const batch = events.slice(i, i + batchSize)
    const { error } = await supabase
      .from('rfid_events_raw')
      .insert(batch)
    
    if (error) {
      console.error(`  ❌ Error inserting batch ${i / batchSize + 1}:`, error.message)
    } else {
      console.log(`  ✅ Inserted batch ${i / batchSize + 1} (${batch.length} events)`)
    }
  }
  
  // ========================================
  // STEP 4: Run pipeline
  // ========================================
  console.log('\n⚙️  STEP 4: Running EPCIS pipeline...')
  
  // Run full pipeline
  const { data: pipelineResult, error: pipelineError } = await supabase.rpc('process_all_accounts_pipeline')
  
  if (pipelineError) {
    console.error('  ❌ Pipeline error:', pipelineError.message)
  } else {
    console.log('  ✅ Pipeline complete')
    
    const demo2Result = pipelineResult?.find(r => r.account_id === DEMO2_ACCOUNT)
    if (demo2Result) {
      console.log(`     Events consolidated: ${demo2Result.events_consolidated}`)
      console.log(`     Segments created: ${demo2Result.segments_created}`)
      console.log(`     Paths created: ${demo2Result.paths_created}`)
      console.log(`     Execution time: ${demo2Result.total_execution_time_ms}ms`)
    }
  }
  
  // ========================================
  // STEP 5: Verify results
  // ========================================
  console.log('\n🔍 STEP 5: Verifying results...')
  
  const { data: paths, count } = await supabase
    .from('journey_paths')
    .select('*', { count: 'exact' })
    .eq('account_id', DEMO2_ACCOUNT)
  
  console.log(`  ✅ Created ${count} journey paths`)
  
  if (paths && paths.length > 0) {
    const path = paths[0]
    console.log(`\n  📊 Sample path:`)
    console.log(`     Origin: ${path.origin_city_name}`)
    console.log(`     Destination: ${path.destination_city_name}`)
    console.log(`     Total tags: ${path.total_tags}`)
    console.log(`     Segments: ${path.segment_details?.length || 0}`)
    
    if (path.segment_details && path.segment_details.length > 0) {
      console.log(`\n  📍 Segment details:`)
      path.segment_details.forEach((seg, idx) => {
        console.log(`     ${idx + 1}. ${seg.segment_type}: ${seg.from_center_name || 'NULL'} → ${seg.to_center_name || 'NULL'}`)
        console.log(`        Cities: ${seg.from_city} → ${seg.to_city}`)
        console.log(`        Compliance: ${seg.compliance_rate}%`)
      })
      
      const hasNulls = path.segment_details.some(s => !s.from_center_name || !s.to_center_name)
      if (hasNulls) {
        console.log(`\n  ⚠️  WARNING: Some center names are NULL`)
        console.log(`     This means the aggregate function needs to be deployed`)
      } else {
        console.log(`\n  ✅ All center names populated!`)
      }
    }
  } else {
    console.log(`\n  ⚠️  No paths created. Checking intermediate steps...`)
    
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
  console.log('✅ Demo data generation complete!')
  console.log('\nNext steps:')
  console.log('  1. Deploy frontend: ONEMS_FINAL_WITH_SQL_FIX.zip')
  console.log('  2. Open Route Path Analysis in the app')
  console.log('  3. Verify center names appear correctly')
}

main()
