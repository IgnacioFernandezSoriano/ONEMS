// LOCAL ONLY. What the server does in the background after POST /deliveries/{id}/complete, run against the local
// Postgres (127.0.0.1:5433, onems_t): the REAL loader of supabase/functions/carrier-link-worker (claim, load rows,
// sha256, load_done) reading the file from the local storage stub of the simulator, then the pg_cron procedure
// CALL public.cl_delivery_process_run() (DB phases with COMMIT between steps). It repeats until no delivery is left
// in received/processing (a failed delivery waits 5 minutes for its retry, as on the server: not waited for here).
//
//   deno run --allow-read --allow-run --allow-env tools/carrier-simulator/e2e/local_worker.ts --storage <dir>
//
// The RPCs are called with named arguments like PostgREST through public.zz_sim_call (created by e2e/fixture.sql in
// the local test database only).
import { DEFAULTS, runOnce, type WorkerIo } from '../../../supabase/functions/carrier-link-worker/loader.ts'

// psql: $PSQL, else the portable Postgres under the user's home (the local test setup).
const HOME = Deno.env.get('USERPROFILE') ?? Deno.env.get('HOME') ?? '.'
const PSQL = Deno.env.get('PSQL') ?? `${HOME}/pgportable/pgsql/bin/psql.exe`
const DB = Deno.env.get('SIM_DB') ?? 'onems_t'
const CONN = ['-h', '127.0.0.1', '-p', '5433', '-U', 'postgres', '-d', DB, '-v', 'ON_ERROR_STOP=1', '-X', '-q', '-At']

const i = Deno.args.indexOf('--storage')
if (i < 0 || !Deno.args[i + 1]) {
  console.error('usage: local_worker.ts --storage <dir>')
  Deno.exit(2)
}
const STORAGE = Deno.args[i + 1]

async function psql(sql: string): Promise<string> {
  const p = new Deno.Command(PSQL, {
    args: CONN, stdin: 'piped', stdout: 'piped', stderr: 'piped',
    env: { PGPASSWORD: Deno.env.get('PGPASSWORD') ?? 'postgres' },
  }).spawn()
  const w = p.stdin.getWriter()
  await w.write(new TextEncoder().encode(sql))
  await w.close()
  const o = await p.output()
  if (!o.success) {
    const err = new TextDecoder().decode(o.stderr)
    throw { message: err.replace(/^.*ERROR:\s+/s, '').split('\n')[0] }
  }
  return new TextDecoder().decode(o.stdout).trim()
}

const q = (s: string) => `'${s.replaceAll("'", "''")}'`

const io: WorkerIo = {
  async rpc(fn, args) {
    const out = await psql(`SELECT public.zz_sim_call(${q(fn)}, ${q(JSON.stringify(args))}::jsonb);`)
    return out === '' ? null : JSON.parse(out)
  },
  async fetchRange(path, start, end) {
    const data = await Deno.readFile(`${STORAGE}/${path}`)
    return data.slice(start, Math.min(end, data.length))
  },
  async remove(paths) {
    for (const p of paths) { try { await Deno.remove(`${STORAGE}/${p}`) } catch { /* already gone */ } }
  },
  now: () => Date.now(),
}

// One fixed token: every tick is the same "worker", so a lease left by an earlier tick is still its own.
const opt = { ...DEFAULTS, token: 'sim-local-worker-0001' }
for (let round = 0; round < 50; round++) {
  let res = await runOnce(io, opt)
  for (let n = 0; res.status === 'more' && n < 1000; n++) res = await runOnce(io, opt)
  await psql('CALL public.cl_delivery_process_run();')
  const left = await psql(`SELECT count(*) FROM public.cl_deliveries WHERE status IN ('received','processing')`)
  if (left === '0') break
}
