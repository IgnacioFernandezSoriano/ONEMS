import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://sehbnpgzqljrsqimwyuz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDg5NDMxMSwiZXhwIjoyMDgwNDcwMzExfQ.8aPEi2qUYMiKBi__jAu-8gnkc3Z5b1jrPpbjBYQPf4k'
)

const DEMO2_ACCOUNT = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'

async function main() {
  console.log('🚀 Generating Simple Route Path Demo\n')
  console.log('━'.repeat(60))
  
  // ========================================
  // STEP 1: Clean existing data
  // ========================================
  console.log('\n📦 STEP 1: Cleaning existing data...')
  
  await supabase.from('journey_paths').delete().eq('account_id', DEMO2_ACCOUNT)
  await supabase.from('journey_segments').delete().eq('account_id', DEMO2_ACCOUNT)
  await supabase.from('processed_events').delete().eq('account_id', DEMO2_ACCOUNT)
  await supabase.from('rfid_events_raw').delete().eq('account_id', DEMO2_ACCOUNT)
  
  console.log('  ✅ Data cleaned')
  
  // ========================================
  // STEP 2: Get postal centers
  // ========================================
  console.log('\n📋 STEP 2: Loading postal centers...')
  
  const { data: centers } = await supabase
    .from('postal_centers')
    .select('id, code, name, city')
    .eq('account_id', DEMO2_ACCOUNT)
    .order('city')
  
  if (!centers || centers.length < 2) {
    console.error('  ❌ Need at least 2 postal centers')
    return
  }
  
  // Select 4 centers for the route
  const route = centers.slice(0, 4)
  console.log(`  ✅ Route: ${route.map(c => c.name).join(' → ')}`)
  
  // ========================================
  // STEP 3: Create mobile readers
  // ========================================
  console.log('\n📱 STEP 3: Creating mobile readers...')
  
  const readers = []
  for (const center of route) {
    // Entry reader
    readers.push({
      account_id: DEMO2_ACCOUNT,
      code: `${center.code}-ENTRY`,
      description: `Entry reader for ${center.name}`,
      postal_center_id: center.id,
      is_active: true,
      created_at: new Date().toISOString()
    })
    
    // Exit reader
    readers.push({
      account_id: DEMO2_ACCOUNT,
      code: `${center.code}-EXIT`,
      description: `Exit reader for ${center.name}`,
      postal_center_id: center.id,
      is_active: true,
      created_at: new Date().toISOString()
    })
  }
  
  const { error: readerError } = await supabase
    .from('mobile_readers')
    .insert(readers)
  
  if (readerError) {
    console.log(`  ⚠️  Readers may already exist: ${readerError.message}`)
  } else {
    console.log(`  ✅ Created ${readers.length} readers`)
  }
  
  // ========================================
  // STEP 4: Generate RFID events
  // ========================================
  console.log('\n📝 STEP 4: Generating RFID events...')
  
  const events = []
  const baseTime = new Date('2026-02-15T08:00:00Z')
  
  // Generate 30 tags
  for (let tagNum = 1; tagNum <= 30; tagNum++) {
    const tagId = `DEMO-TAG-${String(tagNum).padStart(4, '0')}`
    
    let currentTime = new Date(baseTime.getTime() + tagNum * 120000) // Stagger by 2 min
    
    for (let i = 0; i < route.length; i++) {
      const center = route[i]
      
      // Entry event
      events.push({
        account_id: DEMO2_ACCOUNT,
        event_id: `${tagId}-${center.code}-ENTRY-${currentTime.getTime()}`,
        tag_id: tagId,
        reader_id: `${center.code}-ENTRY`,
        read_local_datetime: currentTime.toISOString(),
        is_processed: false
      })
      
      // Time in center: 30-90 minutes
      currentTime = new Date(currentTime.getTime() + (30 + Math.random() * 60) * 60000)
      
      // Exit event
      events.push({
        account_id: DEMO2_ACCOUNT,
        event_id: `${tagId}-${center.code}-EXIT-${currentTime.getTime()}`,
        tag_id: tagId,
        reader_id: `${center.code}-EXIT`,
        read_local_datetime: currentTime.toISOString(),
        is_processed: false
      })
      
      // Transit time: 60-180 minutes
      if (i < route.length - 1) {
        currentTime = new Date(currentTime.getTime() + (60 + Math.random() * 120) * 60000)
      }
    }
  }
  
  console.log(`  Generated ${events.length} events for 30 tags`)
  
  // Insert in batches
  const batchSize = 100
  for (let i = 0; i < events.length; i += batchSize) {
    const batch = events.slice(i, i + batchSize)
    const { error } = await supabase.from('rfid_events_raw').insert(batch)
    
    if (error) {
      console.error(`  ❌ Batch ${Math.floor(i/batchSize) + 1} error:`, error.message)
    } else {
      console.log(`  ✅ Batch ${Math.floor(i/batchSize) + 1} inserted (${batch.length} events)`)
    }
  }
  
  // ========================================
  // STEP 5: Run pipeline
  // ========================================
  console.log('\n⚙️  STEP 5: Running pipeline...')
  
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
    }
  }
  
  // ========================================
  // STEP 6: Verify results
  // ========================================
  console.log('\n🔍 STEP 6: Verifying results...')
  
  const { data: paths, count } = await supabase
    .from('journey_paths')
    .select('*', { count: 'exact' })
    .eq('account_id', DEMO2_ACCOUNT)
  
  console.log(`  Journey paths: ${count}`)
  
  if (paths && paths.length > 0) {
    const path = paths[0]
    console.log(`\n  📊 Path: ${path.origin_city_name} → ${path.destination_city_name}`)
    console.log(`     Tags: ${path.total_tags}`)
    console.log(`     Segments: ${path.segment_details?.length || 0}`)
    
    if (path.segment_details && path.segment_details.length > 0) {
      console.log(`\n  📍 Segments:`)
      path.segment_details.forEach((seg, idx) => {
        const fromName = seg.from_center_name || '❌ NULL'
        const toName = seg.to_center_name || '❌ NULL'
        console.log(`     ${idx + 1}. [${seg.segment_type}] ${fromName} → ${toName}`)
        console.log(`        ${seg.from_city} → ${seg.to_city}`)
      })
      
      const hasNulls = path.segment_details.some(s => !s.from_center_name || !s.to_center_name)
      if (hasNulls) {
        console.log(`\n  ⚠️  Some center names are NULL`)
      } else {
        console.log(`\n  ✅ All center names populated!`)
      }
    }
  } else {
    // Check intermediate tables
    const { count: segCount } = await supabase
      .from('journey_segments')
      .select('*', { count: 'exact', head: true })
      .eq('account_id', DEMO2_ACCOUNT)
    
    const { count: procCount } = await supabase
      .from('processed_events')
      .select('*', { count: 'exact', head: true })
      .eq('account_id', DEMO2_ACCOUNT)
    
    console.log(`\n  ⚠️  No paths created`)
    console.log(`     Processed events: ${procCount}`)
    console.log(`     Journey segments: ${segCount}`)
    
    if (segCount > 0) {
      // Check segment sample
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
  
  console.log('\n━'.repeat(60))
  console.log('✅ Demo complete!')
}

main()
