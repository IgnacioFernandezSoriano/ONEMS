import { describe, it, expect } from 'vitest'
import {
  MANUAL_MAX_BYTES,
  MANUAL_MAX_ROWS,
  canUploadManually,
  countBatchRows,
  manualFileError,
  parseManualIngest,
  parseManualSample,
  parseManualFinish,
  runManualBatch,
  samplingTotals,
  progressPercent,
  type ManualBatchApi,
} from '../carrierLink/manualBatch'

const S1 = '91000000-0000-0000-0000-0000000000b1'
const S2 = '91000000-0000-0000-0000-0000000000b2'
const ingestOk = (needs = true) => ({
  ingest: {
    batch: 'bbbb0000-0000-0000-0000-000000000001',
    status: 'validated',
    strata: [
      { stratum_id: S1, rows: 4, candidates: 2, candidates_valid: 1, population_size: 48, rejected: {}, rows_rejected: {} },
      { stratum_id: S2, rows: 2, candidates: 1, candidates_valid: 1, population_size: 10, rejected: {}, rows_rejected: {} },
    ],
  },
  needs_sampling: needs,
})
const run = (sid: string, req: number, sel: number) => ({
  batch_id: 'b', stratum_id: sid, samples_required: req, samples_selected: sel, candidates_valid: sel,
})

/** API falsa que registra el orden de las llamadas. */
function fakeApi(over: Partial<ManualBatchApi> = {}, ingest: unknown = ingestOk()) {
  const calls: string[] = []
  const api: ManualBatchApi = {
    ingest: async () => {
      calls.push('ingest')
      return ingest
    },
    sample: async (b, s) => {
      calls.push(`sample:${s}`)
      return run(s, 2, 1)
    },
    finish: async () => {
      calls.push('finish')
      return { batch_id: 'b', status: 'sampled', demand_status: 'partial', strata_pending: [] }
    },
    ...over,
  }
  return { api, calls }
}

describe('canUploadManually', () => {
  it('solo conectores activos', () => {
    expect(canUploadManually('active')).toBe(true)
    expect(canUploadManually('testing')).toBe(false)
    expect(canUploadManually('paused')).toBe(false)
  })
})

describe('countBatchRows / manualFileError', () => {
  const batch = (n: number) => ({ strata: [{ rows: Array(n).fill({}) }, 'x', { rows: 'no' }] })
  it('cuenta como la Edge Function (solo estratos objeto con rows array)', () => {
    expect(countBatchRows(batch(3))).toBe(3)
    expect(countBatchRows(null)).toBe(0)
    expect(countBatchRows({ strata: 'x' })).toBe(0)
  })
  it('topes de 5 MB y 5.000 lecturas', () => {
    expect(manualFileError(MANUAL_MAX_BYTES + 1, batch(1))).toBe('cl.error.cl_body_too_large')
    expect(manualFileError(MANUAL_MAX_BYTES, batch(MANUAL_MAX_ROWS))).toBeNull()
    expect(manualFileError(10, batch(MANUAL_MAX_ROWS + 1))).toBe('cl.error.cl_too_many_rows')
  })
  it('un JSON que no es objeto no se envía', () => {
    expect(manualFileError(10, [1, 2])).toBe('cl.connectors.dry_run.bad_json')
    expect(manualFileError(10, null)).toBe('cl.connectors.dry_run.bad_json')
  })
})

describe('parseManualIngest', () => {
  it('lote nuevo: estratos del resumen y needs_sampling', () => {
    const r = parseManualIngest(ingestOk())
    expect(r.batchId).toBe('bbbb0000-0000-0000-0000-000000000001')
    expect(r.needsSampling).toBe(true)
    expect(r.strataIds).toEqual([S1, S2])
    expect(r.summary.status).toBe('validated')
    expect(r.summary.strata).toHaveLength(2)
  })
  it('needs_sampling solo si la base lo dice y hay lote validado', () => {
    expect(parseManualIngest(ingestOk(false)).needsSampling).toBe(false)
    expect(parseManualIngest({ ingest: { status: 'rejected', batch: 'x', strata: [] }, needs_sampling: true }).needsSampling).toBe(false)
    expect(parseManualIngest({ ingest: { status: 'validated', batch: null }, needs_sampling: true }).needsSampling).toBe(false)
    expect(parseManualIngest(null)).toMatchObject({ batchId: null, needsSampling: false, strataIds: [] })
  })
})

describe('parseManualSample / parseManualFinish', () => {
  it('lee el sorteo sin fiarse de la forma', () => {
    expect(parseManualSample(run(S1, 2, 1), S1)).toEqual({ stratum_id: S1, samples_required: 2, samples_selected: 1, candidates_valid: 1 })
    expect(parseManualSample('x', S2)).toEqual({ stratum_id: S2, samples_required: null, samples_selected: null, candidates_valid: null })
  })
  it('lee el cierre', () => {
    expect(parseManualFinish({ status: 'pending', demand_status: 'open', strata_pending: [S2, 3] })).toEqual({
      status: 'pending', demand_status: 'open', strata_pending: [S2],
    })
    expect(parseManualFinish(undefined)).toEqual({ status: null, demand_status: null, strata_pending: [] })
  })
})

describe('runManualBatch', () => {
  it('mismo orden que la Edge Function: entrada, un sorteo por estrato, cierre; con progreso', async () => {
    const { api, calls } = fakeApi()
    const progress: [number, number][] = []
    const r = await runManualBatch(api, {}, (d, t) => progress.push([d, t]))
    expect(calls).toEqual(['ingest', `sample:${S1}`, `sample:${S2}`, 'finish'])
    expect(progress).toEqual([[0, 2], [1, 2], [2, 2]])
    expect(r.kind).toBe('done')
    if (r.kind === 'done') {
      expect(r.sampling.map((s) => s.stratum_id)).toEqual([S1, S2])
      expect(r.finish.demand_status).toBe('partial')
    }
  })
  it('lote ya cargado o rechazado: solo la entrada', async () => {
    const { api, calls } = fakeApi({}, ingestOk(false))
    const r = await runManualBatch(api, {})
    expect(calls).toEqual(['ingest'])
    expect(r.kind).toBe('stored')
  })
  it('fallo de un sorteo: se para, sin cierre, con el código traducible y lo ya sorteado', async () => {
    const { api, calls } = fakeApi({
      sample: async (_b, s) => {
        calls.push(`sample:${s}`)
        if (s === S2) throw { code: '22023', message: 'CL_DEMAND_NOT_OPEN: demand is fulfilled' }
        return run(s, 1, 1)
      },
    })
    const r = await runManualBatch(api, {})
    expect(calls).toEqual(['ingest', `sample:${S1}`, `sample:${S2}`])
    expect(r).toMatchObject({ kind: 'failed', failed: { stratum_id: S2, errorKey: 'cl.error.cl_demand_not_open' } })
    if (r.kind === 'failed') expect(r.sampling).toHaveLength(1)
  })
  it('error de la entrada: se lanza sin sortear', async () => {
    const { api, calls } = fakeApi({
      ingest: async () => {
        calls.push('ingest')
        throw { code: '22023', message: 'CL_FEED_PAUSED: the connector is paused' }
      },
    })
    await expect(runManualBatch(api, {})).rejects.toMatchObject({ message: expect.stringContaining('CL_FEED_PAUSED') })
    expect(calls).toEqual(['ingest'])
  })
})

describe('samplingTotals / progressPercent', () => {
  it('suma pedidas y elegidas', () => {
    expect(samplingTotals([parseManualSample(run(S1, 2, 1), S1), parseManualSample(run(S2, 3, 3), S2)])).toEqual({ required: 5, selected: 4 })
    expect(samplingTotals([])).toEqual({ required: 0, selected: 0 })
  })
  it('porcentaje acotado', () => {
    expect(progressPercent(0, 0)).toBe(0)
    expect(progressPercent(1, 3)).toBe(33)
    expect(progressPercent(5, 3)).toBe(100)
  })
})
