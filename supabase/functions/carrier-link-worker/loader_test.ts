// deno-lint-ignore-file require-await no-explicit-any no-import-prefix
// Worker contra ficheros generados y una base simulada que aplica las mismas reglas que las RPC de
// 20261124100100_cl_process_delivery.sql (arriendo, cursor, filas consecutivas, max_rows, sha256, zona de paso
// perdida). Cubre: registro partido entre trozos, CRLF, campo CSV entre comillas con salto de linea, BOM, lineas en
// blanco, caida a mitad de fichero y reanudacion, sha256 distinto, registro demasiado largo, fichero inexistente.
import { assert, assertEquals, assertRejects } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { DEFAULTS, runOnce, StorageError, type WorkerIo, type WorkerOptions } from './loader.ts'

async function sha(b: Uint8Array): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', b.slice() as Uint8Array<ArrayBuffer>))
  return Array.from(d, (x) => x.toString(16).padStart(2, '0')).join('')
}

interface Load { offset: number; rows: number; sha: unknown; sha_offset: number; header: string[] | null }

class FakeDb implements WorkerIo {
  clock = 1_000_000
  status = 'received'
  phase = ''
  error: string | null = null
  load: Load = { offset: 0, rows: 0, sha: null, sha_offset: 0, header: null }
  lease: { token: string | null; until: number } = { token: null, until: 0 }
  rows = new Map<number, unknown>()
  calls: string[] = []
  removed: string[] = []
  crashAfterLoadRows = Infinity        // simula que se cae la red / la invocacion tras N lotes
  crashed = false
  storageStatus = 0                    // != 0 -> fetchRange falla con ese estado
  maxRows = 1_000_000
  sweep: string[] = []

  constructor(public file: Uint8Array, public declared: string, public format: 'jsonl' | 'csv',
              public fields = ['trk', 'ts', 'office', 'evt', 'svc', 'weight']) {}

  now() { return this.clock }

  async fetchRange(_p: string, start: number, end: number) {
    if (this.storageStatus) throw new StorageError(this.storageStatus)
    return this.file.slice(start, end)
  }
  async remove(paths: string[]) { this.removed.push(...paths) }

  private check(a: Record<string, any>) {
    if (this.status !== 'processing' || this.phase !== 'load') throw { message: 'CL_DELIVERY_NOT_LOADING' }
    if (a.p_token !== this.lease.token) throw { message: 'CL_LEASE_LOST' }
    if (a.p_from_offset !== this.load.offset) throw { message: 'CL_CURSOR_MISMATCH' }
  }

  async rpc(fn: string, a: Record<string, any>): Promise<any> {
    this.calls.push(fn)
    if (this.crashed) throw new Error('network down')
    const cloned = JSON.parse(JSON.stringify(a))     // como viaja por HTTP
    switch (fn) {
      case 'cl_delivery_worker_claim': {
        if (this.status === 'received' || this.status === 'failed') {
          this.status = 'processing'; this.phase = 'load'
          this.load = { offset: 0, rows: 0, sha: null, sha_offset: 0, header: null }
        } else if (this.status !== 'processing') return { action: 'idle' }
        if (this.phase !== 'load') return { action: 'sql', phase: this.phase }
        if (this.lease.token !== cloned.p_token && this.lease.until > this.clock) return { action: 'busy' }
        this.lease = { token: cloned.p_token, until: this.clock + cloned.p_lease_seconds * 1000 }
        if (this.load.rows > 0 && !this.rows.has(this.load.rows)) {
          this.load = { offset: 0, rows: 0, sha: null, sha_offset: 0, header: null }
        }
        return { action: 'load', delivery_id: 'd1', file_path: 'a/f/d1.' + this.format, format: this.format,
                 file_bytes: this.file.length, fields: this.fields, load: JSON.parse(JSON.stringify(this.load)) }
      }
      case 'cl_delivery_load_rows': {
        this.check(cloned)
        if (this.calls.filter((c) => c === 'cl_delivery_load_rows').length > this.crashAfterLoadRows) {
          this.crashed = true
          throw new Error('network down')
        }
        const rows = cloned.p_rows as { n: number; r: unknown }[]
        const next = cloned.p_load as Load
        rows.forEach((x, i) => assertEquals(x.n, this.load.rows + i + 1, 'consecutive rows'))
        assertEquals(next.rows, this.load.rows + rows.length)
        assert(next.offset >= this.load.offset)
        if (next.rows > this.maxRows) { this.abort('rejected', 'CL_TOO_MANY_ROWS'); return { stop: true, error: 'CL_TOO_MANY_ROWS' } }
        for (const x of rows) if (!this.rows.has(x.n)) this.rows.set(x.n, x.r)
        this.load = next
        this.lease.until = this.clock + cloned.p_lease_seconds * 1000
        return { stop: false }
      }
      case 'cl_delivery_load_done': {
        this.check(cloned)
        assertEquals(cloned.p_from_offset, this.file.length)
        if (cloned.p_sha256 !== this.declared || cloned.p_bytes !== this.file.length) {
          this.abort('rejected', 'CL_SHA256_MISMATCH'); return { phase: 'abort', error: 'CL_SHA256_MISMATCH' }
        }
        this.phase = 'resolve'; this.lease = { token: null, until: 0 }
        return { phase: 'resolve', rows_total: this.load.rows }
      }
      case 'cl_delivery_load_fail': {
        if (cloned.p_token !== this.lease.token) throw { message: 'CL_LEASE_LOST' }
        this.abort(cloned.p_final ? 'rejected' : 'failed', cloned.p_code)
        return { phase: 'abort' }
      }
      case 'cl_delivery_sweep_list': return this.sweep
      case 'cl_delivery_sweep_done': { const n = cloned.p_paths.length; this.sweep = []; return n }
    }
    throw new Error('unknown rpc ' + fn)
  }

  abort(status: string, code: string) {
    this.phase = 'abort'; this.error = code; this.rows.clear(); this.status = status   // la base vacia y cierra
  }
}

const opts = (o: Partial<WorkerOptions> = {}): WorkerOptions =>
  ({ ...DEFAULTS, token: 'token-aaaa-1', chunkBytes: 64, rowsPerRpc: 3, ...o })

function genJsonl(n: number, eol = '\n'): { text: string; expected: unknown[] } {
  const expected: unknown[] = []
  let text = ''
  for (let i = 1; i <= n; i++) {
    const rec = { trk: 'TRK' + i, ts: '2026-11-1' + (i % 7) + ' 08:0' + (i % 10), office: i % 2 ? 'NBO' : 'MBA',
                  evt: i % 3 ? 'ADM' : null, svc: 'EXP', weight: i * 1.5, name: 'Persona ' + i, ñ: 'ünïcödé ' + i }
    text += JSON.stringify(rec) + eol
    if (i % 17 === 0) text += eol            // lineas en blanco: no cuentan como fila
    const { name: _n, ñ: _x, ...keep } = rec
    expected.push(keep)
  }
  return { text, expected }
}

async function runToEnd(db: FakeDb, o: WorkerOptions, max = 500) {
  let last
  for (let i = 0; i < max; i++) {
    last = await runOnce(db, o)
    if (last.status !== 'more') return last
  }
  throw new Error('did not finish')
}

const enc = (s: string) => new TextEncoder().encode(s)

Deno.test('jsonl: records split across chunk boundaries, blank lines, unicode -> all rows, hash ok', async () => {
  for (const chunk of [7, 64, 100, 333, 1 << 20]) {
    for (const eol of ['\n', '\r\n']) {
      const { text, expected } = genJsonl(120, eol)
      const file = enc(text)
      const db = new FakeDb(file, await sha(file), 'jsonl')
      const res = await runToEnd(db, opts({ chunkBytes: Math.max(chunk, 160), maxChunks: 5 }))
      assertEquals(res.status, 'loaded', `chunk ${chunk}`)
      assertEquals(db.phase, 'resolve')
      assertEquals([...db.rows.keys()], expected.map((_, i) => i + 1))
      assertEquals([...db.rows.values()], expected, `chunk ${chunk} eol ${JSON.stringify(eol)}`)
    }
  }
})

Deno.test('csv: header, CRLF, quoted field with newline and comma, BOM, bad rows -> null', async () => {
  const text = '﻿trk,ts,office,name,weight\r\n' +
    'A1,2026-11-10 08:00,NBO,"Perez, Juan",1\r\n' +
    'A2,"2026-11-10\n09:00",MBA,"multi\r\nline ""quoted""",2\r\n' +
    '\r\n' +
    'A3,2026-11-10 10:00,NBO,x\r\n' +            // columnas de menos -> null
    'A4,2026-11-10 11:00,"HUB",y,4'               // sin salto final
  const file = enc(text)
  for (const chunk of [60, 80, 1000]) {
    const db = new FakeDb(file, await sha(file), 'csv')
    const res = await runToEnd(db, opts({ chunkBytes: chunk, rowsPerRpc: 2, maxChunks: 3 }))
    assertEquals(res.status, 'loaded', `chunk ${chunk}`)
    assertEquals(db.load.header, ['trk', 'ts', 'office', 'name', 'weight'])
    assertEquals([...db.rows.values()], [
      { trk: 'A1', ts: '2026-11-10 08:00', office: 'NBO', weight: '1' },
      { trk: 'A2', ts: '2026-11-10\n09:00', office: 'MBA', weight: '2' },
      null,
      { trk: 'A4', ts: '2026-11-10 11:00', office: 'HUB', weight: '4' },
    ], `chunk ${chunk}`)
  }
})

Deno.test('crash mid-file: next invocation resumes from the last confirmed batch, hash still matches', async () => {
  const { text, expected } = genJsonl(300)
  const file = enc(text)
  const db = new FakeDb(file, await sha(file), 'jsonl')
  db.crashAfterLoadRows = 7
  // La invocacion se cae (tampoco puede avisar a la base): el error sale del worker.
  await assertRejects(() => runOnce(db, opts({ chunkBytes: 500, maxChunks: 1000 })))
  const confirmed = db.load.rows
  assert(confirmed > 0 && confirmed < 300)
  db.crashAfterLoadRows = Infinity
  db.crashed = false
  // Otro worker antes de que caduque el arriendo: ocupado.
  assertEquals((await runOnce(db, opts({ token: 'token-bbbb-2' }))).status, 'busy')
  db.clock += 10 * 60_000
  const res = await runToEnd(db, opts({ token: 'token-bbbb-2', chunkBytes: 777, maxChunks: 2 }))
  assertEquals(res.status, 'loaded')
  assertEquals([...db.rows.values()], expected)
})

Deno.test('staging lost (UNLOGGED after a server crash): reload from byte 0', async () => {
  const { text, expected } = genJsonl(50)
  const file = enc(text)
  const db = new FakeDb(file, await sha(file), 'jsonl')
  assertEquals((await runOnce(db, opts({ chunkBytes: 300, maxChunks: 2 }))).status, 'more')
  db.rows.clear()
  const res = await runToEnd(db, opts({ chunkBytes: 300, maxChunks: 2 }))
  assertEquals(res.status, 'loaded')
  assertEquals([...db.rows.values()], expected)
})

Deno.test('hash mismatch -> rejected CL_SHA256_MISMATCH', async () => {
  const file = enc(genJsonl(20).text)
  const db = new FakeDb(file, '0'.repeat(64), 'jsonl')
  const res = await runToEnd(db, opts({ chunkBytes: 200 }))
  assertEquals(res.status, 'rejected')
  assertEquals(db.error, 'CL_SHA256_MISMATCH')
  assertEquals(db.rows.size, 0)
})

Deno.test('record longer than a chunk -> rejected CL_RECORD_TOO_LONG', async () => {
  const file = enc('{"trk":"' + 'x'.repeat(500) + '"}\n{"trk":"b"}\n')
  const db = new FakeDb(file, await sha(file), 'jsonl')
  const res = await runToEnd(db, opts({ chunkBytes: 100 }))
  assertEquals([res.status, res.code], ['rejected', 'CL_RECORD_TOO_LONG'])
})

Deno.test('invalid UTF-8 -> rejected CL_BAD_ENCODING; bad json line -> null row', async () => {
  const bad = new Uint8Array([...enc('{"trk":"a"}\n{"trk":"'), 0xff, 0xfe, ...enc('"}\n')])
  const db = new FakeDb(bad, await sha(bad), 'jsonl')
  assertEquals((await runToEnd(db, opts())).code, 'CL_BAD_ENCODING')
  const file = enc('{"trk":"a"}\nnot json\n[1]\n{"trk":"b","other":1}\n')
  const db2 = new FakeDb(file, await sha(file), 'jsonl')
  assertEquals((await runToEnd(db2, opts())).status, 'loaded')
  assertEquals([...db2.rows.values()], [{ trk: 'a' }, null, null, { trk: 'b' }])
})

Deno.test('empty file loads 0 rows; csv with duplicate header is rejected', async () => {
  const empty = new Uint8Array(0)
  const db = new FakeDb(empty, await sha(empty), 'jsonl')
  assertEquals((await runToEnd(db, opts())).status, 'loaded')
  assertEquals(db.load.rows, 0)
  const csv = enc('trk,trk\n1,2\n')
  const db2 = new FakeDb(csv, await sha(csv), 'csv')
  assertEquals((await runToEnd(db2, opts())).code, 'CL_BAD_CSV_HEADER')
})

Deno.test('storage errors: 404 -> rejected CL_FILE_MISSING, 500 -> failed CL_STORAGE_ERROR', async () => {
  const file = enc(genJsonl(5).text)
  const db = new FakeDb(file, await sha(file), 'jsonl')
  db.storageStatus = 404
  assertEquals(await runOnce(db, opts()), { status: 'rejected', delivery_id: 'd1', code: 'CL_FILE_MISSING', swept: 0 })
  const db2 = new FakeDb(file, await sha(file), 'jsonl')
  db2.storageStatus = 500
  assertEquals((await runOnce(db2, opts())).status, 'failed')
  assertEquals(db2.status, 'failed')
})

Deno.test('max_rows exceeded -> rejected by the database, worker stops', async () => {
  const file = enc(genJsonl(40).text)
  const db = new FakeDb(file, await sha(file), 'jsonl')
  db.maxRows = 10
  const res = await runToEnd(db, opts({ chunkBytes: 4000 }))
  assertEquals([res.status, res.code], ['rejected', 'CL_TOO_MANY_ROWS'])
})

Deno.test('budget: maxChunks stops with more; idle sweeps expired files through the Storage API', async () => {
  const file = enc(genJsonl(30).text)
  const db = new FakeDb(file, await sha(file), 'jsonl')
  const r1 = await runOnce(db, opts({ chunkBytes: 200, maxChunks: 1 }))
  assertEquals(r1.status, 'more')
  assertEquals(r1.chunks, 1)
  await runToEnd(db, opts({ chunkBytes: 200, maxChunks: 3 }))
  db.sweep = ['a/f/old1.jsonl', 'a/f/old2.csv']
  const r2 = await runOnce(db, opts())
  assertEquals([r2.status, r2.swept], ['sql', 2])
  assertEquals(db.removed, ['a/f/old1.jsonl', 'a/f/old2.csv'])
})
