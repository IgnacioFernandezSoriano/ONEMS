import fs from 'fs'
import fetch from 'node-fetch'

const SUPABASE_URL = 'https://sehbnpgzqljrsqimwyuz.supabase.co'
const SERVICE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlaGJucGd6cWxqcnNxaW13eXV6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTczNDQ1MTI2OSwiZXhwIjoyMDUwMDI3MjY5fQ.wLx8KHqzUZ8-kcVWxSvWRRnCBQrxH2-_FEeQqXfOECE'

async function executeSQLFile(filePath) {
  console.log(`📄 Reading SQL from: ${filePath}`)
  const sql = fs.readFileSync(filePath, 'utf8')
  
  console.log('🚀 Executing SQL via Supabase REST API...')
  
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/exec`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`
    },
    body: JSON.stringify({ query: sql })
  })
  
  if (!response.ok) {
    const error = await response.text()
    console.error('❌ SQL execution failed:', error)
    return false
  }
  
  console.log('✅ SQL executed successfully')
  return true
}

async function main() {
  const sqlFile = '/tmp/ONEMS/supabase/migrations/20260214_phase4_aggregate_journey_paths.sql'
  
  const success = await executeSQLFile(sqlFile)
  
  if (!success) {
    console.log('\n⚠️  Direct SQL execution not available.')
    console.log('📋 Please execute the SQL manually:')
    console.log('   1. Open Supabase Dashboard SQL Editor')
    console.log('   2. Copy content from:', sqlFile)
    console.log('   3. Execute the SQL')
    console.log('\nThen run: node /tmp/ONEMS/deploy_function_direct.mjs')
  }
}

main()
