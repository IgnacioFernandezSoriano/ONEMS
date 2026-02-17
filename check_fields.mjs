import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://sehbnpgzqljrsqimwyuz.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzQ0NTEyNjksImV4cCI6MjA1MDAyNzI2OX0.LZxsQGI5eoSU9-Xwu7M9oFWk8vZWLBBHfqPWPBCGnYI'
)

const { data, error } = await supabase
  .from('journey_paths')
  .select('*')
  .eq('account_id', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e')
  .limit(1)

if (error) {
  console.error('Error:', error)
} else {
  console.log('Available fields:')
  console.log(Object.keys(data[0]).sort())
}
