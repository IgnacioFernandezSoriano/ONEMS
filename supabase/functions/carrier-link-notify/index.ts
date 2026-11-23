// Carrier Link v4.1: correos de incidencias. Lo llama pg_cron cada minuto (cl_notify_kick, por pg_net) con la cabecera
// x-cl-notify-secret cuando hay avisos debidos en cl_notifications.
// Variables (nunca en git): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (automaticas), CL_NOTIFY_SECRET (= secreto
// cl_notify_secret de Vault), RESEND_API_KEY, CL_NOTIFY_FROM (remitente verificado en Resend, p. ej.
// "ONEMS <alerts@dominio>"). Solo registra codigos, nunca claves, correos ni textos.

import { handle } from './handler.ts'
import { makeResendSender } from './resend.ts'

const url = Deno.env.get('SUPABASE_URL') ?? ''
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

async function rpc(fn: string, args: Record<string, unknown>): Promise<unknown> {
  const r = await fetch(`${url}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args),
  })
  const text = await r.text()
  let body: { code?: string } | null = null
  try { body = text ? JSON.parse(text) : null } catch { body = null }
  if (!r.ok) throw { code: typeof body?.code === 'string' ? body.code : `HTTP_${r.status}` }
  return body
}

Deno.serve((req) =>
  handle(req, {
    secret: Deno.env.get('CL_NOTIFY_SECRET') ?? '',
    from: Deno.env.get('CL_NOTIFY_FROM') ?? '',
    rpc,
    send: makeResendSender(Deno.env.get('RESEND_API_KEY') ?? ''),
    log: (m) => console.error(m),
  })
)
