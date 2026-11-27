// Prints the extraction SQL for a GET /config JSON (the body, or {http_status, body}).
//   deno run --allow-read supabase/functions/carrier-link-ingest/query_cli.ts <config.json> [postgresql|oracle|sqlserver] [--json]
// Used by tools/carrier-simulator/e2e/query_pg_check.py and to regenerate docs examples. No network, no database.
import { QUERY_DBS, buildCarrierQuery, type ConnectorConfig, type QueryDb } from './query.ts'

const [path, dbArg = 'postgresql', flag] = Deno.args
if (!path || !(QUERY_DBS as readonly string[]).includes(dbArg)) {
  console.error('usage: query_cli.ts <config.json> [postgresql|oracle|sqlserver] [--json]')
  Deno.exit(2)
}
const raw = JSON.parse(await Deno.readTextFile(path))
const cfg = (raw && typeof raw === 'object' && 'body' in raw ? raw.body : raw) as ConnectorConfig
const q = buildCarrierQuery(cfg, dbArg as QueryDb)
console.log(flag === '--json' ? JSON.stringify(q, null, 2) : q.sql)
