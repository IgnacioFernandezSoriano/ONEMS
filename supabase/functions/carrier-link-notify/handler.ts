// Carrier Link v4.1: envio de los avisos de incidencias. La E/S va inyectada (Deps) para probarla sin red.
// Flujo: secreto -> cl_notify_claim (arriendo con un token propio) -> por aviso: texto + envio con
// Idempotency-Key = id del aviso (un reintento tras una caida no duplica el correo) -> cl_notify_result con el mismo
// token (si el arriendo se perdio, la base contesta 'lost' y no cambia nada). Nunca registra claves, correos ni textos.

import { type NotifyItem, renderEmail } from './render.ts'
import { SEND_TIMEOUT_MS } from './resend.ts'

/** Defaults: 10 per claim x 20 s worst-case send = 200 s, well under the 300 s lease. */
export const DEFAULT_BATCH = 10
export const DEFAULT_LEASE_SECONDS = 300
/** Time kept in reserve after the last send for cl_notify_result. */
export const RESULT_MARGIN_MS = 10_000

/** Claim size bounded so that size x worst-case send time (+ margin) fits in the lease. */
export function boundedBatch(requested: number, leaseSeconds: number, sendTimeoutMs = SEND_TIMEOUT_MS): number {
  const fit = Math.floor((leaseSeconds * 1000 - RESULT_MARGIN_MS) / sendTimeoutMs)
  return Math.max(1, Math.min(requested, fit))
}

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
  sendTimeoutMs?: number
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
  const out = { sent: 0, retry: 0, failed: 0, skipped: 0, lost: 0 }
  const budgetMs = deps.budgetMs ?? 100_000
  const leaseSeconds = deps.leaseSeconds ?? DEFAULT_LEASE_SECONDS
  const sendTimeoutMs = deps.sendTimeoutMs ?? SEND_TIMEOUT_MS
  const limit = boundedBatch(deps.batch ?? DEFAULT_BATCH, leaseSeconds, sendTimeoutMs)
  try {
    rounds: for (let round = 0; round < (deps.maxRounds ?? 5); round++) {
      if (now() - t0 > budgetMs) break
      const claimedAt = now()
      const items = (await deps.rpc('cl_notify_claim', {
        p_token: token, p_limit: limit, p_lease_seconds: leaseSeconds,
      })) as NotifyItem[] | null
      if (!Array.isArray(items) || items.length === 0) break
      for (const it of items) {
        // Never start a send that could end after our lease (another run could claim it again) or past the run budget.
        // The items left in 'sending' are claimed again when the lease expires; the Idempotency-Key covers a resend.
        if (now() - claimedAt + sendTimeoutMs + RESULT_MARGIN_MS > leaseSeconds * 1000 || now() - t0 > budgetMs) {
          break rounds
        }
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
        else if (status === 'skipped') out.skipped++   // its incident was closed meanwhile: not retried
        else out.lost++
      }
    }
    return json(200, out)
  } catch (e) {
    deps.log(`carrier-link-notify error ${errCode(e)}`)
    return json(500, { error: 'Internal server error' })
  }
}
