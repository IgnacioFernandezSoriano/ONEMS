// Una invocacion del worker de Carrier Link (entregas v4). Sin dependencias de red: la E/S llega en `io`, asi se
// prueba con ficheros generados y una base simulada (loader_test.ts).
//
//   1. cl_delivery_worker_claim(token): que hay que hacer.
//   2. 'load': lee el fichero de Storage por trozos (Range [offset, offset + chunkBytes)), calcula el sha256 de forma
//      incremental (solo los bytes nuevos: sha_offset), corta registros completos y los manda con
//      cl_delivery_load_rows en lotes de rowsPerRpc filas. Cada llamada guarda filas y cursor en la misma
//      transaccion: tras una caida se sigue en el ultimo lote confirmado. Al llegar al final, cl_delivery_load_done
//      con el sha256; la base compara con el declarado y sigue con su parte (pg_cron).
//   3. Retencion: borra por la API de Storage los ficheros que diga cl_delivery_sweep_list y lo confirma.
// Se para al agotar maxChunks, el tiempo (budgetMs) o la CPU aproximada (cpuBudgetMs, parte sincrona): devuelve
// 'more' y index.ts se vuelve a invocar con el mismo token (el arriendo sigue siendo suyo).

import { Sha256, type ShaState } from './sha256.ts'
import { bomLength, decode, FileError, type Format, isBlank, parseCsvHeader, splitRecords, toRecord } from './records.ts'

export interface DbError { code?: string; message?: string }

export interface WorkerIo {
  // deno-lint-ignore no-explicit-any
  rpc(fn: string, args: Record<string, unknown>): Promise<any>   // lanza DbError
  fetchRange(path: string, start: number, endExclusive: number): Promise<Uint8Array>   // lanza StorageError
  remove(paths: string[]): Promise<void>
  now(): number
}

export class StorageError extends Error {
  constructor(public status: number) { super('storage ' + status) }
}

export interface WorkerOptions {
  token: string
  chunkBytes: number
  maxChunks: number
  budgetMs: number
  cpuBudgetMs: number
  rowsPerRpc: number
  leaseSeconds: number
  sweepLimit: number
}

export const DEFAULTS: Omit<WorkerOptions, 'token'> = {
  chunkBytes: 4 * 1024 * 1024,
  maxChunks: 8,
  budgetMs: 100_000,
  cpuBudgetMs: 1_200,
  rowsPerRpc: 10_000,
  leaseSeconds: 120,
  sweepLimit: 100,
}

export interface LoadCursor {
  offset: number
  rows: number
  sha: ShaState | null
  sha_offset: number
  header: string[] | null
}

export type RunStatus = 'idle' | 'busy' | 'sql' | 'more' | 'loaded' | 'rejected' | 'failed' | 'lost'

export interface RunResult {
  status: RunStatus
  delivery_id?: string
  code?: string
  chunks?: number
  rows?: number
  swept?: number
}

// Errores de la base que significan "otro worker lleva esta entrega" o "ya no esta cargando": parar sin tocar nada.
const LOST = ['CL_LEASE_LOST', 'CL_CURSOR_MISMATCH', 'CL_DELIVERY_NOT_LOADING']
export function dbCode(e: unknown): string | null {
  const m = (e as DbError)?.message ?? ''
  const x = /^(CL_[A-Z0-9_]+)/.exec(m)
  return x ? x[1] : null
}

export async function runOnce(io: WorkerIo, opt: WorkerOptions): Promise<RunResult> {
  const t0 = io.now()
  const claim = await io.rpc('cl_delivery_worker_claim', { p_token: opt.token, p_lease_seconds: opt.leaseSeconds })
  let res: RunResult
  if (claim?.action === 'load') {
    res = await load(io, opt, claim, t0)
  } else {
    res = { status: (['busy', 'sql', 'idle'].includes(claim?.action) ? claim.action : 'idle') as RunStatus,
            delivery_id: claim?.delivery_id }
  }
  if (res.status !== 'more' && io.now() - t0 < opt.budgetMs) res.swept = await sweep(io, opt)
  return res
}

async function sweep(io: WorkerIo, opt: WorkerOptions): Promise<number> {
  const paths: string[] = await io.rpc('cl_delivery_sweep_list', { p_limit: opt.sweepLimit })
  if (!Array.isArray(paths) || paths.length === 0) return 0
  await io.remove(paths)
  return await io.rpc('cl_delivery_sweep_done', { p_paths: paths })
}

class StopError extends Error {
  constructor(public code: string) { super(code) }
}

// deno-lint-ignore no-explicit-any
async function load(io: WorkerIo, opt: WorkerOptions, claim: any, t0: number): Promise<RunResult> {
  const id: string = claim.delivery_id
  const path: string = claim.file_path
  const format: Format = claim.format
  const size: number = Number(claim.file_bytes)
  const allowed = new Set<string>(claim.fields ?? [])
  const cur: LoadCursor = { ...claim.load }
  let cpu = 0
  let chunks = 0

  const fail = async (code: string, final: boolean): Promise<RunResult> => {
    try {
      await io.rpc('cl_delivery_load_fail', { p_delivery_id: id, p_token: opt.token, p_code: code, p_final: final })
    } catch (e) {
      if (LOST.includes(dbCode(e) ?? '')) return { status: 'lost', delivery_id: id }
      throw e
    }
    return { status: final ? 'rejected' : 'failed', delivery_id: id, code }
  }

  try {
    if (!Number.isFinite(size) || size < 0) return await fail('CL_FILE_SIZE_UNKNOWN', false)
    const hasher = new Sha256(cur.sha)
    if (hasher.length !== cur.sha_offset) return await fail('CL_BAD_SHA_STATE', false)
    while (true) {
      if (cur.offset >= size) {
        const done = await io.rpc('cl_delivery_load_done', {
          p_delivery_id: id, p_token: opt.token, p_from_offset: cur.offset, p_sha256: hasher.hex(), p_bytes: hasher.length,
        })
        if (done?.phase === 'resolve') return { status: 'loaded', delivery_id: id, chunks, rows: cur.rows }
        if (done?.phase === 'load') return { status: 'more', delivery_id: id, chunks, code: done?.error }   // zona perdida
        return { status: 'rejected', delivery_id: id, code: done?.error, chunks }
      }
      if (chunks >= opt.maxChunks || io.now() - t0 >= opt.budgetMs || cpu >= opt.cpuBudgetMs) {
        return { status: 'more', delivery_id: id, chunks, rows: cur.rows }
      }
      const chunkStart = cur.offset
      const end = Math.min(chunkStart + opt.chunkBytes, size)
      let bytes: Uint8Array
      try {
        bytes = await io.fetchRange(path, chunkStart, end)
      } catch (e) {
        if (e instanceof StorageError) {
          return await fail(e.status === 404 ? 'CL_FILE_MISSING' : 'CL_STORAGE_ERROR', e.status === 404)
        }
        throw e
      }
      if (bytes.length !== end - chunkStart) return await fail('CL_STORAGE_SHORT_READ', false)
      chunks++

      let mark = performance.now()
      if (cur.sha_offset < end) {
        hasher.update(bytes.subarray(cur.sha_offset - chunkStart))
        cur.sha_offset = end
      }
      const isLast = end === size
      const { spans, consumed } = splitRecords(bytes, format, isLast)
      if (consumed === 0 && !isLast) return await fail('CL_RECORD_TOO_LONG', true)
      const skip = bomLength(bytes, chunkStart)

      let batch: { n: number; r: Record<string, unknown> | null }[] = []
      // Guarda las filas del lote y el cursor = byte siguiente a su ultimo registro (rel, desde el inicio del trozo).
      const flush = async (rel: number) => {
        const next: LoadCursor = { offset: chunkStart + rel, rows: cur.rows + batch.length, sha: hasher.state(),
                                   sha_offset: cur.sha_offset, header: cur.header }
        cpu += performance.now() - mark
        const r = await io.rpc('cl_delivery_load_rows', {
          p_delivery_id: id, p_token: opt.token, p_from_offset: cur.offset, p_rows: batch, p_load: next,
          p_lease_seconds: opt.leaseSeconds,
        })
        mark = performance.now()
        if (r?.stop) throw new StopError(r.error ?? 'CL_STOPPED')
        cur.offset = next.offset
        cur.rows = next.rows
        batch = []
      }
      for (const s of spans) {
        const line = decode(bytes.subarray(s.start === 0 ? Math.min(skip, s.end) : s.start, s.end))
        if (!isBlank(line)) {
          if (format === 'csv' && cur.header === null) cur.header = parseCsvHeader(line)
          else batch.push({ n: cur.rows + batch.length + 1, r: toRecord(line, format, cur.header, allowed) })
        }
        if (batch.length >= opt.rowsPerRpc) await flush(s.next)
      }
      if (batch.length > 0 || chunkStart + consumed > cur.offset) await flush(consumed)
      cpu += performance.now() - mark
    }
  } catch (e) {
    if (e instanceof StopError) return { status: 'rejected', delivery_id: id, code: e.code }
    if (e instanceof FileError) return await fail(e.code, e.final)
    const code = dbCode(e)
    if (code && LOST.includes(code)) return { status: 'lost', delivery_id: id }
    return await fail('CL_WORKER_ERROR', false)
  }
}
