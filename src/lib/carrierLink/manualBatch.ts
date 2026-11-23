import { clErrorKey } from './clErrors'
import { parseDryRunResult, type ConnectorStatus, type DryRunSummary } from './connectorConfig'

/** Mismos topes que la Edge Function carrier-link-ingest (MAX_BODY_BYTES, MAX_ROWS). */
export const MANUAL_MAX_BYTES = 5 * 1024 * 1024
export const MANUAL_MAX_ROWS = 5000

/** La carga manual es un lote real: solo con el conector activo (en prueba solo hay ensayos; pausado no acepta lotes). */
export function canUploadManually(status: ConnectorStatus): boolean {
  return status === 'active'
}

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const str = (v: unknown): string | null => (typeof v === 'string' ? v : null)

/** Lecturas del lote, contadas como la Edge Function (solo estratos objeto con rows array). */
export function countBatchRows(batch: unknown): number {
  if (!isObj(batch) || !Array.isArray(batch.strata)) return 0
  let n = 0
  for (const s of batch.strata) if (isObj(s) && Array.isArray(s.rows)) n += s.rows.length
  return n
}

/** Comprobación local del fichero antes de llamar a la base: clave i18n del error, o null si se puede enviar. */
export function manualFileError(sizeBytes: number, batch: unknown): string | null {
  if (sizeBytes > MANUAL_MAX_BYTES) return 'cl.error.cl_body_too_large'
  if (!isObj(batch)) return 'cl.connectors.dry_run.bad_json'
  if (countBatchRows(batch) > MANUAL_MAX_ROWS) return 'cl.error.cl_too_many_rows'
  return null
}

export interface ManualIngest {
  summary: DryRunSummary
  batchId: string | null
  /** El lote guardado sigue pendiente de sorteo (nuevo, o uno que se quedó a medias). */
  needsSampling: boolean
  /** Estratos a sortear, en el orden del resumen (nunca del fichero), como summaryStratumIds de la Edge Function. */
  strataIds: string[]
}

/** Lee lo que devuelve cl_manual_ingest: { ingest, needs_sampling }. */
export function parseManualIngest(data: unknown): ManualIngest {
  const o = isObj(data) ? data : {}
  const ingest = isObj(o.ingest) ? o.ingest : {}
  const strata = Array.isArray(ingest.strata) ? ingest.strata : []
  const summary = parseDryRunResult(ingest)
  return {
    summary: { ...summary, replayed: false },
    batchId: str(ingest.batch),
    needsSampling: o.needs_sampling === true && str(ingest.batch) !== null && summary.status === 'validated',
    strataIds: strata.filter(isObj).map((s) => str(s.stratum_id)).filter((s): s is string => s !== null),
  }
}

export interface ManualSample {
  stratum_id: string
  samples_required: number | null
  samples_selected: number | null
  candidates_valid: number | null
}

/** Lee el resumen de un sorteo (cl_run_summary). */
export function parseManualSample(data: unknown, stratumId: string): ManualSample {
  const o = isObj(data) ? data : {}
  return {
    stratum_id: str(o.stratum_id) ?? stratumId,
    samples_required: num(o.samples_required),
    samples_selected: num(o.samples_selected),
    candidates_valid: num(o.candidates_valid),
  }
}

export interface ManualFinish {
  /** 'sampled' = lote cerrado; 'pending' = faltan estratos por sortear. */
  status: string | null
  demand_status: string | null
  strata_pending: string[]
}

export function parseManualFinish(data: unknown): ManualFinish {
  const o = isObj(data) ? data : {}
  return {
    status: str(o.status),
    demand_status: str(o.demand_status),
    strata_pending: Array.isArray(o.strata_pending) ? o.strata_pending.map(str).filter((s): s is string => s !== null) : [],
  }
}

export type ManualBatchError = { message?: string; code?: string }

export interface ManualBatchApi {
  ingest: (payload: unknown) => Promise<unknown>
  sample: (batchId: string, stratumId: string) => Promise<unknown>
  finish: (batchId: string) => Promise<unknown>
}

export type ManualBatchOutcome =
  /** Lote no sorteable: rechazado (método de selección) o ya cargado antes (se muestra su resumen guardado). */
  | { kind: 'stored'; ingest: ManualIngest }
  | { kind: 'done'; ingest: ManualIngest; sampling: ManualSample[]; finish: ManualFinish }
  /** Falló el sorteo de un estrato: lo ya sorteado queda guardado; volver a cargar el fichero lo retoma. */
  | { kind: 'failed'; ingest: ManualIngest; sampling: ManualSample[]; failed: { stratum_id: string; errorKey: string } }

/**
 * Carga real de un lote, en el mismo orden que la Edge Function: entrada, sorteo de cada estrato del resumen (una
 * llamada por estrato) y cierre. Un error de la entrada o del cierre se lanza; el de un sorteo se devuelve como 'failed'.
 */
export async function runManualBatch(
  api: ManualBatchApi,
  payload: unknown,
  onProgress?: (done: number, total: number) => void,
): Promise<ManualBatchOutcome> {
  const ingest = parseManualIngest(await api.ingest(payload))
  if (!ingest.needsSampling || !ingest.batchId) return { kind: 'stored', ingest }
  const total = ingest.strataIds.length
  const sampling: ManualSample[] = []
  onProgress?.(0, total)
  for (const sid of ingest.strataIds) {
    try {
      sampling.push(parseManualSample(await api.sample(ingest.batchId, sid), sid))
    } catch (e) {
      return { kind: 'failed', ingest, sampling, failed: { stratum_id: sid, errorKey: clErrorKey(e as ManualBatchError) } }
    }
    onProgress?.(sampling.length, total)
  }
  const finish = parseManualFinish(await api.finish(ingest.batchId))
  return { kind: 'done', ingest, sampling, finish }
}

/** Totales del sorteo para el resumen final. */
export function samplingTotals(sampling: ManualSample[]): { required: number; selected: number } {
  return sampling.reduce(
    (a, s) => ({ required: a.required + (s.samples_required ?? 0), selected: a.selected + (s.samples_selected ?? 0) }),
    { required: 0, selected: 0 },
  )
}

/** Porcentaje entero de la barra de progreso. */
export function progressPercent(done: number, total: number): number {
  if (total <= 0) return 0
  return Math.min(100, Math.max(0, Math.round((done / total) * 100)))
}
