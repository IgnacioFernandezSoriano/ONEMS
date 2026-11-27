// Carrier Link v4: worker de entregas. Lo llama pg_cron cada minuto (cl_delivery_kick_worker, por pg_net) y se
// vuelve a llamar a si mismo mientras quede fichero por cargar (mismo token: conserva el arriendo). Solo carga el
// fichero en la zona de paso y borra ficheros caducados; el resto lo hace la base (cl_delivery_process_run).
// Variables: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, CL_WORKER_SECRET (= secreto cl_worker_secret de Vault) y,
// opcionales, CL_WORKER_CHUNK_BYTES, CL_WORKER_MAX_CHUNKS, CL_WORKER_BUDGET_MS, CL_WORKER_CPU_BUDGET_MS,
// CL_WORKER_ROWS_PER_RPC, CL_WORKER_MAX_HOPS. Nunca registra contenido del fichero (puede haber datos personales).

import { DEFAULTS, runOnce, StorageError, type WorkerIo, type WorkerOptions } from './loader.ts'

const BUCKET = 'cl-deliveries'
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

function envInt(name: string, def: number, min: number, max: number): number {
  const v = Number(Deno.env.get(name))
  return Number.isFinite(v) && v >= min && v <= max ? Math.trunc(v) : def
}

function sameSecret(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false
  let d = 0
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return d === 0
}

function makeIo(url: string, key: string): WorkerIo {
  const auth = { apikey: key, Authorization: `Bearer ${key}` }
  const objectPath = (p: string) => p.split('/').map(encodeURIComponent).join('/')
  return {
    async rpc(fn, args) {
      const r = await fetch(`${url}/rest/v1/rpc/${fn}`, {
        method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' }, body: JSON.stringify(args),
      })
      const text = await r.text()
      const body = text ? JSON.parse(text) : null
      if (!r.ok) throw { code: body?.code, message: body?.message ?? `http ${r.status}` }
      return body
    },
    async fetchRange(path, start, endExclusive) {
      if (endExclusive <= start) return new Uint8Array(0)
      const r = await fetch(`${url}/storage/v1/object/authenticated/${BUCKET}/${objectPath(path)}`, {
        headers: { ...auth, Range: `bytes=${start}-${endExclusive - 1}` },
      })
      if (r.status !== 206 && !(r.status === 200 && start === 0)) {
        await r.body?.cancel()
        throw new StorageError(r.status === 400 || r.status === 404 ? 404 : r.status)
      }
      const b = new Uint8Array(await r.arrayBuffer())
      // 200 sin Range (fichero pequeno entero): se recorta a lo pedido.
      return r.status === 200 ? b.subarray(0, endExclusive - start) : b
    },
    async remove(paths) {
      const r = await fetch(`${url}/storage/v1/object/${BUCKET}`, {
        method: 'DELETE', headers: { ...auth, 'Content-Type': 'application/json' }, body: JSON.stringify({ prefixes: paths }),
      })
      await r.body?.cancel()
      if (!r.ok) throw new StorageError(r.status)
    },
    now: () => Date.now(),
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'Method not allowed' })
  const secret = Deno.env.get('CL_WORKER_SECRET') ?? ''
  if (!sameSecret(req.headers.get('x-cl-worker-secret') ?? '', secret)) return json(401, { error: 'Unauthorized' })

  // deno-lint-ignore no-explicit-any
  let body: any = {}
  try { body = await req.json() } catch { body = {} }
  const token = typeof body?.token === 'string' && /^[A-Za-z0-9-]{8,100}$/.test(body.token) ? body.token : crypto.randomUUID()
  const hop = Number.isInteger(body?.hop) && body.hop >= 0 ? body.hop : 0

  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const opt: WorkerOptions = {
    token,
    chunkBytes: envInt('CL_WORKER_CHUNK_BYTES', DEFAULTS.chunkBytes, 64 * 1024, 32 * 1024 * 1024),
    maxChunks: envInt('CL_WORKER_MAX_CHUNKS', DEFAULTS.maxChunks, 1, 1000),
    budgetMs: envInt('CL_WORKER_BUDGET_MS', DEFAULTS.budgetMs, 1_000, 300_000),
    cpuBudgetMs: envInt('CL_WORKER_CPU_BUDGET_MS', DEFAULTS.cpuBudgetMs, 100, 60_000),
    rowsPerRpc: envInt('CL_WORKER_ROWS_PER_RPC', DEFAULTS.rowsPerRpc, 100, 50_000),
    leaseSeconds: DEFAULTS.leaseSeconds,
    sweepLimit: DEFAULTS.sweepLimit,
  }
  try {
    const res = await runOnce(makeIo(url, key), opt)
    // Queda fichero: otra invocacion con el mismo token (pg_cron la relanza igualmente si esta se pierde).
    if (res.status === 'more' && hop < envInt('CL_WORKER_MAX_HOPS', 200, 0, 10_000)) {
      const next = fetch(`${url}/functions/v1/carrier-link-worker`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-cl-worker-secret': secret, Authorization: `Bearer ${key}` },
        body: JSON.stringify({ token, hop: hop + 1 }),
      }).then((r) => r.body?.cancel()).catch(() => {})
      // deno-lint-ignore no-explicit-any
      const rt = (globalThis as any).EdgeRuntime
      if (rt?.waitUntil) rt.waitUntil(next)
      else await next
    }
    return json(200, res)
  } catch (e) {
    // Solo el codigo: los mensajes pueden llevar valores del fichero.
    console.error('carrier-link-worker error', (e as { code?: string })?.code ?? 'unknown')
    return json(500, { error: 'Internal server error' })
  }
})
