import { createClient } from '@supabase/supabase-js'
import fs from 'fs'

const supabase = createClient(
  'https://sehbnpgzqljrsqimwyuz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTczNDQ1MTI2OSwiZXhwIjoyMDUwMDI3MjY5fQ.wLx8KHqzUZ8-kcVWxSvWRRnCBQrxH2-_FEeQqXfOECE'
)

async function deployAndAggregate() {
  console.log('📦 Deploying updated aggregate_journey_paths function...')
  
  const sql = fs.readFileSync('/tmp/deploy_function.sql', 'utf8')
  
  const { error: deployError } = await supabase.rpc('exec_sql', { sql_query: sql }).catch(async () => {
    // Try direct execution
    const { error } = await supabase.from('_sql').insert({ query: sql })
    return { error }
  })
  
  if (deployError) {
    console.error('❌ Deploy error:', deployError)
    // Continue anyway, function might already exist
  } else {
    console.log('✅ Function deployed')
  }
  
  console.log('\n🔄 Re-running aggregation with DEMO2 account...')
  
  const { data, error } = await supabase.rpc('aggregate_journey_paths', {
    p_account_id: 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
  })
  
  if (error) {
    console.error('❌ Aggregation error:', error)
    process.exit(1)
  }
  
  console.log('✅ Aggregation complete:', data)
  
  // Check results
  const { data: paths } = await supabase
    .from('journey_paths')
    .select('origin_city_name, destination_city_name')
    .eq('account_id', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e')
    .limit(5)
  
  console.log('\n📊 Sample journey paths with city names:')
  console.log(JSON.stringify(paths, null, 2))
}

deployAndAggregate()
