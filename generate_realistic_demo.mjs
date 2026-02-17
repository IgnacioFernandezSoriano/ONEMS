import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://sehbnpgzqljrsqimwyuz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDg5NDMxMSwiZXhwIjoyMDgwNDcwMzExfQ.8aPEi2qUYMiKBi__jAu-8gnkc3Z5b1jrPpbjBYQPf4k'
)

const DEMO2 = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'

console.log('🚀 Generating Realistic Demo Data for Route Path Analysis\n')

// ============================================================================
// STEP 1: Get existing data
// ============================================================================
console.log('📊 Step 1: Getting existing postal centers and readers...')

const { data: centers } = await supabase
  .from('postal_centers')
  .select('id, name, city, code')
  .eq('account_id', DEMO2)
  .in('city', ['Los Angeles', 'Baltimore'])

const laCenter = centers.find(c => c.name === 'Los Angeles Local Center')
const balCenter = centers.find(c => c.city === 'Baltimore')

console.log(`  ✅ Los Angeles: ${laCenter.name} (${laCenter.id})`)
console.log(`  ✅ Baltimore: ${balCenter.name} (${balCenter.id})`)

const { data: readers } = await supabase
  .from('readers')
  .select('reader_id, type, postal_center_id')
  .eq('account_id', DEMO2)
  .in('postal_center_id', [laCenter.id, balCenter.id])

console.log(`  ✅ Found ${readers.length} readers`)

// ============================================================================
// STEP 2: Clean existing demo data
// ============================================================================
console.log('\n🧹 Step 2: Cleaning existing demo data...')

await supabase
  .from('journey_paths')
  .delete()
  .eq('account_id', DEMO2)

await supabase
  .from('journey_segments')
  .delete()
  .eq('account_id', DEMO2)

await supabase
  .from('processed_events')
  .delete()
  .eq('account_id', DEMO2)

await supabase
  .from('rfid_events_raw')
  .delete()
  .eq('account_id', DEMO2)
  .like('tag_id', 'DEMO-TAG-%')

console.log('  ✅ Cleaned all demo data')

// ============================================================================
// STEP 3: Generate realistic RFID events
// ============================================================================
console.log('\n📦 Step 3: Generating realistic RFID events...')

// Start on Friday to include weekend in transit
const baseDate = new Date('2026-02-13T08:00:00Z') // Friday Feb 13, 2026
const tags = ['DEMO-TAG-001', 'DEMO-TAG-002', 'DEMO-TAG-003', 'DEMO-TAG-004', 'DEMO-TAG-005']

const events = []
let eventCounter = 1

for (const tag of tags) {
  // Variación de tiempo para cada tag (para simular diferentes velocidades de envío)
  const tagVariation = Math.floor(Math.random() * 12) // 0-12 horas de variación
  
  // Entry Los Angeles: 2026-02-15 08:00 + variación
  const laEntry = new Date(baseDate)
  laEntry.setHours(laEntry.getHours() + tagVariation)
  
  // Exit Los Angeles: 2-4 horas después
  const laExit = new Date(laEntry)
  laExit.setHours(laExit.getHours() + 2 + Math.floor(Math.random() * 2))
  
  // Entry Baltimore: 3 días después para incluir fin de semana (Viernes salida → Lunes llegada)
  // Esto hará que natural_time sea ~3 días pero working_time sea ~1 día (excluyendo sábado y domingo)
  const balEntry = new Date(laExit)
  balEntry.setDate(balEntry.getDate() + 3) // Cruza sábado y domingo
  balEntry.setHours(balEntry.getHours() + Math.floor(Math.random() * 4))
  
  // Exit Baltimore: 1-3 horas después
  const balExit = new Date(balEntry)
  balExit.setHours(balExit.getHours() + 1 + Math.floor(Math.random() * 2))
  
  // LA Entry
  events.push({
    account_id: DEMO2,
    event_id: `DEMO-EVENT-${String(eventCounter++).padStart(4, '0')}`,
    tag_id: tag,
    reader_id: readers.find(r => r.postal_center_id === laCenter.id && r.type === 'Entry')?.reader_id,
    read_local_datetime: laEntry.toISOString()
  })
  
  // LA Exit
  events.push({
    account_id: DEMO2,
    event_id: `DEMO-EVENT-${String(eventCounter++).padStart(4, '0')}`,
    tag_id: tag,
    reader_id: readers.find(r => r.postal_center_id === laCenter.id && r.type === 'Exit')?.reader_id,
    read_local_datetime: laExit.toISOString()
  })
  
  // Baltimore Entry
  events.push({
    account_id: DEMO2,
    event_id: `DEMO-EVENT-${String(eventCounter++).padStart(4, '0')}`,
    tag_id: tag,
    reader_id: readers.find(r => r.postal_center_id === balCenter.id && r.type === 'Entry')?.reader_id,
    read_local_datetime: balEntry.toISOString()
  })
  
  // Baltimore Exit
  events.push({
    account_id: DEMO2,
    event_id: `DEMO-EVENT-${String(eventCounter++).padStart(4, '0')}`,
    tag_id: tag,
    reader_id: readers.find(r => r.postal_center_id === balCenter.id && r.type === 'Exit')?.reader_id,
    read_local_datetime: balExit.toISOString()
  })
  
  console.log(`  ✅ ${tag}:`)
  console.log(`     LA Entry:  ${laEntry.toISOString()}`)
  console.log(`     LA Exit:   ${laExit.toISOString()} (+${Math.round((laExit - laEntry) / 3600000)}h)`)
  console.log(`     BAL Entry: ${balEntry.toISOString()} (+${Math.round((balEntry - laExit) / 3600000)}h transit)`)
  console.log(`     BAL Exit:  ${balExit.toISOString()} (+${Math.round((balExit - balEntry) / 3600000)}h)`)
}

const { error: eventsError } = await supabase
  .from('rfid_events_raw')
  .insert(events)

if (eventsError) {
  console.error('❌ Error inserting events:', eventsError)
  process.exit(1)
}

console.log(`\n  ✅ Inserted ${events.length} RFID events`)

// ============================================================================
// STEP 4: Run pipeline
// ============================================================================
console.log('\n⚙️  Step 4: Running pipeline...')

// Consolidate events
const { data: consolidateResult } = await supabase.rpc('consolidate_rfid_events', {
  p_account_id: DEMO2
})

console.log(`  ✅ Consolidated: ${consolidateResult?.events_consolidated || 0} events`)

// Build segments
const { data: segmentsResult } = await supabase.rpc('build_journey_segments', {
  p_account_id: DEMO2
})

console.log(`  ✅ Built: ${segmentsResult?.segments_created || 0} segments`)

// Update segment cities
await supabase.rpc('exec_sql', {
  sql: `
    UPDATE journey_segments js
    SET from_postal_center_city = pc.city
    FROM postal_centers pc
    WHERE pc.id = js.from_postal_center_id
      AND js.account_id = '${DEMO2}'
      AND js.from_postal_center_city IS NULL;
      
    UPDATE journey_segments js
    SET to_postal_center_city = pc.city
    FROM postal_centers pc
    WHERE pc.id = js.to_postal_center_id
      AND js.account_id = '${DEMO2}'
      AND js.to_postal_center_city IS NULL;
      
    UPDATE journey_segments js
    SET 
      origin_city_name = pe.origin_city_name,
      destination_city_name = pe.destination_city_name
    FROM (
      SELECT DISTINCT ON (tag_id) 
        tag_id, 
        origin_city_name, 
        destination_city_name
      FROM processed_events
      WHERE account_id = '${DEMO2}'
    ) pe
    WHERE pe.tag_id = js.tag_id
      AND js.account_id = '${DEMO2}'
      AND js.origin_city_name IS NULL;
  `
})

console.log('  ✅ Updated segment cities')

// Update SLA references
await supabase.rpc('exec_sql', {
  sql: `
    UPDATE journey_segments js
    SET 
      sla_id = s.id,
      expected_time_minutes = s.expected_time_minutes
    FROM slas s
    WHERE js.account_id = '${DEMO2}'
      AND s.account_id = js.account_id
      AND s.sla_type = 'distribution'
      AND s.from_postal_center_id = js.from_postal_center_id
      AND s.to_postal_center_id = js.to_postal_center_id
      AND s.carrier_id = js.carrier_id
      AND s.is_active = true;
  `
})

console.log('  ✅ Updated SLA references')

// Aggregate paths
const { data: pathsResult } = await supabase.rpc('aggregate_journey_paths', {
  p_account_id: DEMO2,
  p_since: '2020-01-01T00:00:00Z'
})

console.log(`  ✅ Aggregated: ${pathsResult?.paths_created || 0} paths`)

// ============================================================================
// STEP 5: Verify results
// ============================================================================
console.log('\n✅ Step 5: Verification...')

const { data: path } = await supabase
  .from('journey_paths')
  .select('*')
  .eq('account_id', DEMO2)
  .single()

console.log('\n📊 Journey Path Results:')
console.log(`  Origin: ${path.origin_city_name}`)
console.log(`  Destination: ${path.destination_city_name}`)
console.log(`  Total Tags: ${path.total_tags}`)
console.log(`  Natural Time: ${path.avg_natural_time_minutes} minutes (${(path.avg_natural_time_minutes / 1440).toFixed(2)} days)`)
console.log(`  Working Time: ${path.avg_working_time_minutes} minutes (${(path.avg_working_time_minutes / 1440).toFixed(2)} days)`)
console.log(`  Expected Time: ${path.expected_time_minutes} minutes (${(path.expected_time_minutes / 1440).toFixed(2)} days)`)
console.log(`  Compliance: ${path.compliance_rate}%`)
console.log(`  Segment Details:`)
path.segment_details.forEach((seg, i) => {
  console.log(`    ${i + 1}. ${seg.from_center_name} → ${seg.to_center_name}`)
  console.log(`       Type: ${seg.segment_type}`)
  console.log(`       Natural: ${seg.avg_total_time_natural} min`)
  console.log(`       Working: ${seg.avg_total_time_working} min`)
  console.log(`       Expected: ${seg.expected_time_minutes} min`)
})

console.log('\n🎉 Demo data generation complete!')
console.log('\n📍 Next: Check https://onem-dev.netlify.app/diagnosis/route-path-analysis')
