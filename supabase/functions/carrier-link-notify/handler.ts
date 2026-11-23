// Carrier Link v4.1: envio de los avisos de incidencias. La E/S va inyectada (Deps) para probarla sin red.
// Flujo: secreto -> cl_notify_claim (arriendo con un token propio) -> por aviso: texto + envio con
// Idempotency-Key = id del aviso (un reintento tras una caida no duplica el correo) -> cl_notify_result con el mismo
// token (si el arriendo se perdio, la base contesta 'lost' y no cambia nada). Nunca registra claves, correos ni textos.

import { type NotifyItem, renderEmail } from './render.ts'

export interface SendResult { ok: boolean; final?: boolean; code?: string; id?: string }

export interface Deps {
  secret: string
  from: string
  rpc: (fn: string, args: Record<string, unknown>) => Promise<unknown>
  send: (msg: { from: string; to: string[]; subject: string; text: string; idempotencyKey: string }) => Promise<SendResult>
  log: (msg: string) => void
  token?: () => string
  now?: () => number
  maxRounds?: number
  batch?: number
  leaseSeconds?: number
  budgetMs?: number
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

export function sameSecret(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false
  let d = 0
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return d === 0
}

const CODE = /^[A-Z0-9_]{1,40}$/
const errCode = (e: unknown) => {
  const c = (e as { code?: unknown })?.code
  return typeof c === 'string' && CODE.test(c) ? c : 'unknown'
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== 'POST') return json(405, { error: 'Method not allowed' })
  if (!sameSecret(req.headers.get('x-cl-notify-secret') ?? '', deps.secret)) return json(401, { error: 'Unauthorized' })
  await req.body?.cancel()
  if (!deps.from) {
    deps.log('carrier-link-notify: CL_NOTIFY_FROM missing')
    return json(500, { error: 'Not configured' })
  }

  const token = deps.token?.() ?? crypto.randomUUID()
  const now = deps.now ?? Date.now
  const t0 = now()
  const out = { sent: 0, retry: 0, failed: 0, lost: 0 }
  try {
    for (let round = 0; round < (deps.maxRounds ?? 5); round++) {
      if (now() - t0 > (deps.budgetMs ?? 100_000)) break
      const items = (await deps.rpc('cl_notify_claim', {
        p_token: token, p_limit: deps.batch ?? 20, p_lease_seconds: deps.leaseSeconds ?? 300,
      })) as NotifyItem[] | null
      if (!Array.isArray(items) || items.length === 0) break
      for (const it of items) {
        let r: SendResult
        try {
          const mail = renderEmail(it)
          r = await deps.send({ from: deps.from, to: it.to, subject: mail.subject, text: mail.text,
                                idempotencyKey: `cl-notify-${it.notification_id}` })
        } catch {
          r = { ok: false, code: 'CL_SEND_ERROR' }
        }
        const status = await deps.rpc('cl_notify_result', {
          p_notification_id: it.notification_id, p_token: token, p_ok: r.ok,
          p_error: r.ok ? null : (r.code && CODE.test(r.code) ? r.code : 'CL_SEND_ERROR'),
          p_final: !r.ok && !!r.final, p_provider_id: r.ok ? (r.id ?? null) : null,
        })
        if (status === 'sent') out.sent++
        else if (status === 'pending') out.retry++
        else if (status === 'failed') out.failed++
        else out.lost++
      }
    }
    return json(200, out)
  } catch (e) {
    deps.log(`carrier-link-notify error ${errCode(e)}`)
    return json(500, { error: 'Internal server error' })
  }
}
