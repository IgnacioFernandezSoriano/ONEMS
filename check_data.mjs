import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://sehbnpgzqljrsqimwyuz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzQ0NTEyNjksImV4cCI6MjA1MDAyNzI2OX0.LZxsQGI5eoSU9-Xwu7M9oFWk8vZWLBBHfqPWPBCGnYI'
)

async function checkData() {
  // Check postal centers
  const { data: centers } = await supabase
    .from('postal_centers')
    .select('code, name, city, latitude, longitude')
    .eq('account_id', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e')
  
  console.log('=== POSTAL CENTERS ===')
  console.log(JSON.stringify(centers, null, 2))
  
  // Check journey paths
  const { data: paths } = await supabase
    .from('journey_paths')
    .select('origin_city_name, destination_city_name')
    .eq('account_id', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e')
    .limit(5)
  
  console.log('\n=== JOURNEY PATHS (sample) ===')
  console.log(JSON.stringify(paths, null, 2))
}

checkData()
