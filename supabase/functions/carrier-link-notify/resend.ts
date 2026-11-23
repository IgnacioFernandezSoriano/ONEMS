// Envio por la API de Resend (https://api.resend.com/emails). La clave solo viaja en la cabecera Authorization; el
// cuerpo de la respuesta de error nunca se lee ni se registra (podria repetir datos). Idempotency-Key: Resend no
// vuelve a enviar el mismo correo si se repite la clave (24 h).
import type { SendResult } from './handler.ts'

export type Fetch = (input: string, init: RequestInit) => Promise<Response>

export function makeResendSender(apiKey: string, fetchFn: Fetch = fetch) {
  return async (msg: { from: string; to: string[]; subject: string; text: string; idempotencyKey: string }): Promise<SendResult> => {
    if (!apiKey) return { ok: false, final: false, code: 'CL_NOT_CONFIGURED' }
    let r: Response
    try {
      r = await fetchFn('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': msg.idempotencyKey,
        },
        body: JSON.stringify({ from: msg.from, to: msg.to, subject: msg.subject, text: msg.text }),
      })
    } catch {
      return { ok: false, final: false, code: 'RESEND_NETWORK' }
    }
    if (r.ok) {
      let id: string | undefined
      try {
        const b = await r.json()
        id = typeof b?.id === 'string' && /^[A-Za-z0-9_-]{1,100}$/.test(b.id) ? b.id : undefined
      } catch { id = undefined }
      return { ok: true, id }
    }
    await r.body?.cancel()
    // 4xx (salvo 408/409/429) no mejora reintentando: definitivo.
    const final = r.status >= 400 && r.status < 500 && ![408, 409, 429].includes(r.status)
    return { ok: false, final, code: `RESEND_${r.status}` }
  }
}
