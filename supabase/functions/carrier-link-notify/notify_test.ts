// deno-lint-ignore-file no-import-prefix
import { assert, assertEquals, assertStringIncludes } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { formatPeriods, LANGS, type NotifyItem, pickLang, renderEmail, TYPES } from './render.ts'
import { boundedBatch, type Deps, DEFAULT_BATCH, DEFAULT_LEASE_SECONDS, handle, RESULT_MARGIN_MS, type SendResult } from './handler.ts'
import { makeResendSender, SEND_TIMEOUT_MS } from './resend.ts'

const SECRET = 'notify-secret-value-123'
const RESEND_KEY = 're_SUPERSECRET_api_key'

const item = (o: Partial<NotifyItem> = {}): NotifyItem => ({
  notification_id: '11111111-1111-1111-1111-111111111111', recipient_kind: 'account_manager',
  to: ['am@t.l', 'do@t.l'], language: 'en', incident_type: 'missing_delivery', event: 'opened',
  connector: 'Feed One', open_periods: 1, periods: [{ period_start: '2026-11-10', period_end: '2026-11-10' }], ...o,
})

// ---------------------------------------------------------------- render
Deno.test('render: every type in every language, connector and periods, no placeholders left', () => {
  const seen = new Set<string>()
  for (const lang of LANGS) {
    for (const t of TYPES) {
      const m = renderEmail(item({
        language: lang, incident_type: t,
        periods: [{ period_start: '2026-11-16', period_end: '2026-11-22', rejected: 30, shipments: 100, products: 2, points: 1, missing: 4 }],
      }))
      assertStringIncludes(m.subject, 'Feed One')
      assertStringIncludes(m.text, 'Feed One')
      assertStringIncludes(m.text, '2026-11-16 – 2026-11-22')
      assert(!/\{\w+\}/.test(m.subject + m.text), `${lang}/${t}: placeholder left`)
      if (t === 'high_rejection') { assertStringIncludes(m.text, '30'); assertStringIncludes(m.text, '100') }
      if (t === 'quota_unfilled') assertStringIncludes(m.text, '4')
      seen.add(m.subject)
    }
  }
  assertEquals(seen.size, LANGS.length * TYPES.length, 'each language/type has its own subject')
})

Deno.test('render: language of the account, fallback en', () => {
  assertEquals(pickLang('ES'), 'es')
  assertEquals(pickLang('pt-BR'), 'pt')
  assertEquals(pickLang('de'), 'en')
  assertEquals(pickLang(null), 'en')
  assertStringIncludes(renderEmail(item({ language: 'fr' })).subject, 'Livraison non reçue')
  assertStringIncludes(renderEmail(item({ language: 'ar' })).subject, 'لم يتم استلام التسليم')
  assertStringIncludes(renderEmail(item({ language: 'pt' })).text, 'Não foi recebida')
  assertEquals(renderEmail(item({ language: 'xx' })).subject, renderEmail(item({ language: 'en' })).subject)
})

Deno.test('render: carrier footer vs account footer; pending count only when more than this notice', () => {
  assertStringIncludes(renderEmail(item({ recipient_kind: 'carrier' })).text, 'automatic notice from ONEMS')
  assertStringIncludes(renderEmail(item()).text, 'Carrier Link > Incidents')
  assert(!renderEmail(item()).text.includes('still pending'))
  assertStringIncludes(renderEmail(item({ open_periods: 3 })).text, 'still pending in this incident: 3')
})

Deno.test('render: only periods and counts; junk fields and control characters never reach the email', () => {
  const m = renderEmail(item({
    connector: 'Feed\r\nBcc: x@y',
    // deno-lint-ignore no-explicit-any
    periods: [{ period_start: '2026-11-10', period_end: '2026-11-11', item_id: 'SECRET-ITEM', error: 'CL_X' } as any,
              { period_start: 'not-a-date' }],
  }))
  assert(!m.subject.includes('\n') && !m.subject.includes('\r'))
  assert(!(m.subject + m.text).includes('SECRET-ITEM') && !(m.subject + m.text).includes('CL_X'))
  assertEquals(formatPeriods([{ period_start: '2026-11-10', period_end: '2026-11-10' }, { period_start: 'x' }]), '2026-11-10')
})

// ---------------------------------------------------------------- handler
function deps(items: NotifyItem[][], send: (m: Parameters<Deps['send']>[0]) => Promise<SendResult>, o: Partial<Deps> = {}) {
  const rpcCalls: { fn: string; args: Record<string, unknown> }[] = []
  const logs: string[] = []
  const sends: Parameters<Deps['send']>[0][] = []
  let round = 0
  const d: Deps = {
    secret: SECRET, from: 'ONEMS <alerts@onems.example>',
    rpc: (fn, args) => {
      rpcCalls.push({ fn, args })
      if (fn === 'cl_notify_claim') return Promise.resolve(items[round++] ?? [])
      return Promise.resolve(args.p_ok ? 'sent' : (args.p_final ? 'failed' : 'pending'))
    },
    send: (m) => { sends.push(m); return send(m) },
    log: (m) => logs.push(m),
    token: () => 'tok-test-0001',
    ...o,
  }
  return { d, rpcCalls, logs, sends }
}
const req = (secret = SECRET, method = 'POST') =>
  new Request('http://x/carrier-link-notify', { method, headers: { 'x-cl-notify-secret': secret }, body: method === 'POST' ? '{}' : undefined })

Deno.test('handler: secret and method', async () => {
  const { d, rpcCalls } = deps([[item()]], () => Promise.resolve({ ok: true }))
  assertEquals((await handle(req('wrong'), d)).status, 401)
  assertEquals((await handle(req(''), d)).status, 401)
  assertEquals((await handle(new Request('http://x', { method: 'GET' }), d)).status, 405)
  assertEquals(rpcCalls.length, 0)
  assertEquals((await handle(req(), { ...d, from: '' })).status, 500)
})

Deno.test('handler: claims with a lease, sends with Idempotency-Key = notification id, reports with the same token', async () => {
  const a = item(); const b = item({ notification_id: '22222222-2222-2222-2222-222222222222', recipient_kind: 'carrier', to: ['ops@c.example'] })
  const { d, rpcCalls, sends } = deps([[a, b]], () => Promise.resolve({ ok: true, id: 're_1' }))
  const r = await handle(req(), d)
  assertEquals(r.status, 200)
  assertEquals(await r.json(), { sent: 2, retry: 0, failed: 0, skipped: 0, lost: 0 })
  const claim = rpcCalls.filter((c) => c.fn === 'cl_notify_claim')
  assertEquals(claim[0].args, { p_token: 'tok-test-0001', p_limit: 10, p_lease_seconds: 300 })
  assertEquals(claim.length, 2, 'claims until the queue is empty')
  assertEquals(sends.map((s) => s.idempotencyKey), [`cl-notify-${a.notification_id}`, `cl-notify-${b.notification_id}`])
  assertEquals(sends[1].to, ['ops@c.example'])
  const res = rpcCalls.filter((c) => c.fn === 'cl_notify_result')
  assertEquals(res.map((c) => c.args.p_token), ['tok-test-0001', 'tok-test-0001'])
  assertEquals(res[0].args, { p_notification_id: a.notification_id, p_token: 'tok-test-0001', p_ok: true, p_error: null,
                              p_final: false, p_provider_id: 're_1' })
})

Deno.test('handler: a retried notification is sent with the same idempotency key (no double send); lost lease is counted, not resent', async () => {
  const a = item()
  // Round 1: provider times out (retry); round 2: the DB hands it back (lease expired) and it goes out.
  let n = 0
  const { d, sends, rpcCalls } = deps([[a], [a]], () => Promise.resolve(n++ === 0 ? { ok: false, code: 'RESEND_NETWORK' } : { ok: true }))
  const out = await (await handle(req(), d)).json()
  assertEquals(out, { sent: 1, retry: 1, failed: 0, skipped: 0, lost: 0 })
  assertEquals(new Set(sends.map((s) => s.idempotencyKey)).size, 1)
  assertEquals(rpcCalls.find((c) => c.fn === 'cl_notify_result')?.args.p_error, 'RESEND_NETWORK')

  const lost = deps([[a]], () => Promise.resolve({ ok: true }), { rpc: (fn) => Promise.resolve(fn === 'cl_notify_claim' ? (n++ < 3 ? [a] : []) : 'lost') })
  n = 0
  const o2 = await (await handle(req(), lost.d)).json()
  assertEquals(o2.lost, 3)
  assertEquals(o2.sent, 0)
})

Deno.test('handler: permanent errors are final, send exceptions become CL_SEND_ERROR', async () => {
  const { d, rpcCalls } = deps([[item(), item({ notification_id: '33333333-3333-3333-3333-333333333333' })]], (m) =>
    m.idempotencyKey.endsWith('1111') ? Promise.resolve({ ok: false, final: true, code: 'RESEND_422' }) : Promise.reject(new Error('boom')))
  const out = await (await handle(req(), d)).json()
  assertEquals(out, { sent: 0, retry: 1, failed: 1, skipped: 0, lost: 0 })
  const res = rpcCalls.filter((c) => c.fn === 'cl_notify_result').map((c) => [c.args.p_error, c.args.p_final])
  assertEquals(res, [['RESEND_422', true], ['CL_SEND_ERROR', false]])
})

Deno.test('handler: a failed send whose incident was closed meanwhile is counted as skipped, not retried', async () => {
  let claims = 0
  const { d } = deps([], () => Promise.resolve({ ok: false, code: 'RESEND_500' }),
    { rpc: (fn) => Promise.resolve(fn === 'cl_notify_claim' ? (claims++ === 0 ? [item()] : []) : 'skipped') })
  assertEquals(await (await handle(req(), d)).json(), { sent: 0, retry: 0, failed: 0, skipped: 1, lost: 0 })
})

Deno.test('lease: claim size x worst-case send fits in the lease; a larger batch is clamped (final review #10)', async () => {
  assert(DEFAULT_BATCH * SEND_TIMEOUT_MS + RESULT_MARGIN_MS <= DEFAULT_LEASE_SECONDS * 1000, 'defaults fit the lease')
  assertEquals(boundedBatch(50, 300), 14)
  assertEquals(boundedBatch(5, 300), 5)
  assertEquals(boundedBatch(20, 10), 1, 'never zero')
  const { d, rpcCalls } = deps([[item()]], () => Promise.resolve({ ok: true }), { batch: 50 })
  await (await handle(req(), d)).body?.cancel()
  const c = rpcCalls.find((x) => x.fn === 'cl_notify_claim')!.args
  assertEquals(c.p_limit, 14)
  assert((c.p_limit as number) * SEND_TIMEOUT_MS + RESULT_MARGIN_MS <= (c.p_lease_seconds as number) * 1000)
})

Deno.test('lease: no send starts that could end after the lease; the rest stay claimed for the next run', async () => {
  // Worst case: every send takes the full timeout, and the claim hands back more than fits (20 items).
  let clock = 0
  const many = Array.from({ length: 20 }, (_, i) => item({ notification_id: `11111111-1111-1111-1111-${String(i).padStart(12, '0')}` }))
  const finishedAt: number[] = []
  const { d, rpcCalls, sends } = deps([many, many], () => { clock += SEND_TIMEOUT_MS; finishedAt.push(clock); return Promise.resolve({ ok: true }) },
    { now: () => clock, budgetMs: 10_000_000 })
  const out = await (await handle(req(), d)).json()
  assertEquals(sends.length, 14)
  assertEquals(out.sent, 14)
  assert(Math.max(...finishedAt) + RESULT_MARGIN_MS <= DEFAULT_LEASE_SECONDS * 1000, 'every send ended inside the lease')
  assertEquals(rpcCalls.filter((c) => c.fn === 'cl_notify_claim').length, 1, 'no new claim once the lease is spent')
})

Deno.test('no secret, address or text is ever logged', async () => {
  const logs: string[] = []
  // DB error that echoes the secret, and a provider error body that echoes the API key.
  const fetchMock = () => Promise.resolve(new Response(JSON.stringify({ message: `bad key ${RESEND_KEY}` }), { status: 401 }))
  const send = makeResendSender(RESEND_KEY, fetchMock)
  const { d } = deps([[item()]], send, {
    log: (m) => logs.push(m),
    rpc: (fn) => fn === 'cl_notify_claim' ? Promise.resolve([item()])
                                         : Promise.reject({ code: 'XX000', message: `secret ${SECRET} am@t.l` }),
  })
  const r = await handle(req(), d)
  assertEquals(r.status, 500)
  const body = await r.text()
  const all = logs.join('\n') + body
  for (const s of [SECRET, RESEND_KEY, 'am@t.l', 'Feed One', '2026-11-10']) assert(!all.includes(s), `leaked: ${s}`)
  assertEquals(logs, ['carrier-link-notify error XX000'])
})

// ---------------------------------------------------------------- resend (HTTP mocked)
Deno.test('resend: request shape, idempotency header, key only in Authorization; status mapping', async () => {
  const calls: { url: string; init: RequestInit }[] = []
  const ok = makeResendSender(RESEND_KEY, (url, init) => {
    calls.push({ url, init })
    return Promise.resolve(new Response(JSON.stringify({ id: 're_abc-1' }), { status: 200 }))
  })
  const r = await ok({ from: 'f@x', to: ['a@b.c'], subject: 's', text: 't', idempotencyKey: 'cl-notify-1' })
  assertEquals(r, { ok: true, id: 're_abc-1' })
  assertEquals(calls[0].url, 'https://api.resend.com/emails')
  const h = calls[0].init.headers as Record<string, string>
  assertEquals(h.Authorization, `Bearer ${RESEND_KEY}`)
  assertEquals(h['Idempotency-Key'], 'cl-notify-1')
  assert(!String(calls[0].init.body).includes(RESEND_KEY))
  assertEquals(JSON.parse(String(calls[0].init.body)), { from: 'f@x', to: ['a@b.c'], subject: 's', text: 't' })

  const st = (s: number) => makeResendSender(RESEND_KEY, () => Promise.resolve(new Response('{}', { status: s })))
  const m = { from: 'f', to: ['a@b.c'], subject: 's', text: 't', idempotencyKey: 'k' }
  assertEquals(await st(422)(m), { ok: false, final: true, code: 'RESEND_422' })
  assertEquals(await st(429)(m), { ok: false, final: false, code: 'RESEND_429' })
  assertEquals(await st(503)(m), { ok: false, final: false, code: 'RESEND_503' })
  const net = makeResendSender(RESEND_KEY, () => Promise.reject(new Error(RESEND_KEY)))
  assertEquals(await net(m), { ok: false, final: false, code: 'RESEND_NETWORK' })
  assertEquals(await makeResendSender('')(m), { ok: false, final: false, code: 'CL_NOT_CONFIGURED' })
})

Deno.test('resend: a hung call times out as a retryable failure and is aborted (fix round 1)', async () => {
  assertEquals(SEND_TIMEOUT_MS, 20_000)
  let aborted = false
  const hung = makeResendSender(RESEND_KEY, (_url, init) => new Promise<Response>((_res, rej) => {
    init.signal?.addEventListener('abort', () => { aborted = true; rej(new Error('aborted')) })
  }), 20)
  const m = { from: 'f', to: ['a@b.c'], subject: 's', text: 't', idempotencyKey: 'k' }
  assertEquals(await hung(m), { ok: false, final: false, code: 'RESEND_TIMEOUT' })
  assert(aborted, 'request aborted')
  // A fetch that ignores the signal still yields to the timeout.
  const deaf = makeResendSender(RESEND_KEY, () => new Promise<Response>(() => {}), 20)
  assertEquals(await deaf(m), { ok: false, final: false, code: 'RESEND_TIMEOUT' })
})
