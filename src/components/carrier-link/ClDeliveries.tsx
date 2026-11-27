import { Fragment, useEffect, useRef, useState } from 'react'
import { ChevronDown, ChevronRight, Loader2, Upload, CheckCircle } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import type { ClDeliveryRow } from '@/hooks/carrierLink/useClDeliveries'
import { clErrorKey } from '@/lib/carrierLink/clErrors'
import {
  DELIVERY_STATUS_STYLE,
  deliveryErrorKey,
  deliveryPhaseKey,
  deliveryProgressPercent,
  deliveryStatusKey,
  fmtBytes,
  isDeliveryInFlight,
  manualFileCheck,
  manualPeriodError,
  periodLabel,
  reasonKey,
  rejectedReasons,
  runManualDelivery,
  type DeliveryFormat,
  type DeliverySummary,
  type ManualDeliveryApi,
  type ManualDeliveryStep,
} from '@/lib/carrierLink/deliveryView'
import { sha256Blob } from '@/lib/carrierLink/sha256'

const btnPrimary = 'inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50'
const btnSecondary = 'px-3 py-2 border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50'
const input = 'border border-gray-300 rounded-lg px-3 py-2 text-sm'

const fmtTime = (s: string | null) => (s ? new Date(s).toLocaleString() : '-')
const n = (v: number | null, locale: string) => (v === null ? '-' : new Intl.NumberFormat(locale).format(v))

/** Pie de tabla con total y paginas (mismo aspecto que Monitor y Muestras). */
export function ClPager(props: { page: number; total: number; pageSize: number; loading: boolean; onPage: (p: number) => void }) {
  const { t } = useTranslation()
  const last = Math.max(0, Math.ceil(props.total / props.pageSize) - 1)
  return (
    <div className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 border-t border-gray-100 text-sm text-gray-600">
      <span>{t('cl.monitor.total', { count: props.total })}</span>
      <div className="flex items-center gap-2">
        <button
          type="button"
          className="px-3 py-1 border border-gray-300 rounded-lg disabled:opacity-50"
          disabled={props.page === 0 || props.loading}
          onClick={() => props.onPage(Math.max(0, props.page - 1))}
        >
          {t('cl.samples.prev')}
        </button>
        <span>{t('cl.samples.page', { page: props.page + 1, pages: last + 1 })}</span>
        <button
          type="button"
          className="px-3 py-1 border border-gray-300 rounded-lg disabled:opacity-50"
          disabled={props.page >= last || props.loading}
          onClick={() => props.onPage(props.page + 1)}
        >
          {t('cl.samples.next')}
        </button>
      </div>
    </div>
  )
}

export function DeliveryStatusBadge({ status }: { status: string }) {
  const { t } = useTranslation()
  return (
    <span className={`px-2 py-0.5 rounded-full text-xs font-medium whitespace-nowrap ${DELIVERY_STATUS_STYLE[status] ?? 'bg-gray-100 text-gray-700'}`}>
      {t(deliveryStatusKey(status))}
    </span>
  )
}

/** Lista de entregas: periodo, estado y fase, recuentos; una fila se despliega con motivos, error y fechas. */
export function ClDeliveriesTable(props: {
  rows: ClDeliveryRow[]
  loading: boolean
  /** Nombre del conector por id (Monitor: varias a la vez). Sin el, no hay columna de conector. */
  feedName?: (feedId: string) => string
}) {
  const { t, locale } = useTranslation()
  const [open, setOpen] = useState<string | null>(null)
  const cols = props.feedName ? 9 : 8
  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-sm">
        <thead className="bg-gray-50 text-gray-600">
          <tr>
            <th className="px-2 py-2" />
            <th className="text-start px-3 py-2">{t('cl.deliveries.col.period')}</th>
            {props.feedName && <th className="text-start px-3 py-2">{t('cl.connectors.connector')}</th>}
            <th className="text-start px-3 py-2">{t('cl.deliveries.col.status')}</th>
            <th className="text-end px-3 py-2">{t('cl.deliveries.col.rows')}</th>
            <th className="text-end px-3 py-2">{t('cl.deliveries.col.valid')}</th>
            <th className="text-end px-3 py-2">{t('cl.deliveries.col.rejected')}</th>
            <th className="text-end px-3 py-2">{t('cl.deliveries.col.drawn')}</th>
            <th className="text-end px-3 py-2">{t('cl.deliveries.col.alerts')}</th>
          </tr>
        </thead>
        <tbody>
          {props.loading && props.rows.length === 0 && (
            <tr>
              <td colSpan={cols} className="px-3 py-4 text-center text-gray-500">
                <Loader2 className="w-4 h-4 animate-spin inline" />
              </td>
            </tr>
          )}
          {!props.loading && props.rows.length === 0 && (
            <tr>
              <td colSpan={cols} className="px-3 py-4 text-center text-gray-500">
                {t('cl.deliveries.empty')}
              </td>
            </tr>
          )}
          {props.rows.map((d) => {
            const isOpen = open === d.id
            const phaseKey = deliveryPhaseKey(d.status, d.phase)
            const pct = deliveryProgressPercent(d)
            const shipRejected =
              d.shipments_total !== null && d.shipments_valid !== null ? Math.max(0, d.shipments_total - d.shipments_valid) : null
            return (
              <Fragment key={d.id}>
                <tr className="border-t border-gray-100 align-top">
                  <td className="px-2 py-2">
                    <button
                      type="button"
                      aria-expanded={isOpen}
                      title={t('cl.deliveries.details')}
                      onClick={() => setOpen(isOpen ? null : d.id)}
                      className="text-gray-500 hover:text-gray-800"
                    >
                      {isOpen ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4 rtl:rotate-180" />}
                    </button>
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap">
                    <span dir="auto">{periodLabel(d.period_start, d.period_end, locale)}</span>
                    <div className="text-xs text-gray-500">
                      {t(`cl.deliveries.source.${d.source === 'manual' ? 'manual' : 'api'}`)}
                      {d.is_test && <span className="ms-1 text-amber-700">· {t('cl.deliveries.test')}</span>}
                    </div>
                  </td>
                  {props.feedName && <td className="px-3 py-2">{props.feedName(d.feed_id)}</td>}
                  <td className="px-3 py-2 min-w-[10rem]">
                    <DeliveryStatusBadge status={d.status} />
                    {phaseKey && <div className="text-xs text-gray-600 mt-1">{t(phaseKey)}</div>}
                    {pct !== null && d.status === 'processing' && (
                      <div className="h-1.5 w-full rounded bg-gray-200 overflow-hidden mt-1" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct}>
                        <div className="h-full bg-blue-600" style={{ width: `${pct}%` }} />
                      </div>
                    )}
                    {d.status === 'failed' && <div className="text-xs text-amber-700 mt-1">{t('cl.deliveries.retrying', { attempts: d.attempts })}</div>}
                  </td>
                  <td className="px-3 py-2 text-end">{n(d.rows_total, locale)}</td>
                  <td className="px-3 py-2 text-end">{n(d.shipments_valid, locale)}</td>
                  <td className="px-3 py-2 text-end">
                    {n(d.rows_rejected, locale)} / {n(shipRejected, locale)}
                  </td>
                  <td className="px-3 py-2 text-end">{n(d.shipments_drawn, locale)}</td>
                  <td className={`px-3 py-2 text-end ${d.alerts > 0 ? 'text-amber-700 font-medium' : ''}`}>{d.alerts}</td>
                </tr>
                {isOpen && (
                  <tr className="bg-gray-50">
                    <td />
                    <td colSpan={cols - 1} className="px-3 py-3">
                      <DeliveryDetail d={d} />
                    </td>
                  </tr>
                )}
              </Fragment>
            )
          })}
        </tbody>
      </table>
      <p className="px-3 py-1 text-xs text-gray-500">{t('cl.deliveries.rejected_hint')}</p>
    </div>
  )
}

function DeliveryDetail({ d }: { d: ClDeliveryRow }) {
  const { t, locale } = useTranslation()
  const reasons = rejectedReasons(d.rejected_reasons)
  const errKey = deliveryErrorKey(d.error)
  const list = (items: { reason: string; count: number }[]) =>
    items.length === 0 ? '-' : items.map((r) => `${t(reasonKey(r.reason), undefined, r.reason)}: ${n(r.count, locale)}`).join(', ')
  return (
    <dl className="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-1 text-sm">
      {errKey && (
        <div className="md:col-span-2 text-red-700">
          <dt className="inline font-medium">{t('cl.deliveries.error')}: </dt>
          <dd className="inline">{t(errKey)}</dd>
        </div>
      )}
      <div>
        <dt className="inline text-gray-600">{t('cl.deliveries.rows_rejected_by_reason')}: </dt>
        <dd className="inline">{list(reasons.rows)}</dd>
      </div>
      <div>
        <dt className="inline text-gray-600">{t('cl.deliveries.shipments_rejected_by_reason')}: </dt>
        <dd className="inline">{list(reasons.shipments)}</dd>
      </div>
      <div>
        <dt className="inline text-gray-600">{t('cl.deliveries.shipments_total')}: </dt>
        <dd className="inline">{n(d.shipments_total, locale)}</dd>
      </div>
      <div>
        <dt className="inline text-gray-600">{t('cl.deliveries.file')}: </dt>
        <dd className="inline">
          {d.format.toUpperCase()} · {fmtBytes(d.file_bytes, locale)}
        </dd>
      </div>
      <div>
        <dt className="inline text-gray-600">{t('cl.deliveries.created_at')}: </dt>
        <dd className="inline">{fmtTime(d.created_at)}</dd>
      </div>
      <div>
        <dt className="inline text-gray-600">{t('cl.deliveries.received_at')}: </dt>
        <dd className="inline">{fmtTime(d.received_at)}</dd>
      </div>
      <div>
        <dt className="inline text-gray-600">{t('cl.deliveries.finished_at')}: </dt>
        <dd className="inline">{fmtTime(d.finished_at)}</dd>
      </div>
      <div>
        <dt className="inline text-gray-600">{t('cl.deliveries.attempts')}: </dt>
        <dd className="inline">{d.attempts}</dd>
      </div>
    </dl>
  )
}

type UploadPhase =
  | { step: 'idle' }
  | { step: 'hashing'; done: number; total: number }
  | { step: ManualDeliveryStep }
  | { step: 'done'; summary: DeliverySummary }

/**
 * Subida manual de una entrega (para transportistas que mandan ficheros): periodo + fichero JSON Lines o CSV, huella
 * calculada en el navegador por trozos, y el mismo camino que la API (abrir, subir, completar). Despues la lista de
 * entregas muestra el avance del proceso en segundo plano.
 */
export function ClManualDeliveryUpload(props: {
  feedStatus: string
  defaultPeriod: { period_start: string; period_end: string } | null
  maxFileBytes: number | null
  api: (file: Blob) => ManualDeliveryApi
  onDone: () => void
}) {
  const { t, locale } = useTranslation()
  const [start, setStart] = useState(props.defaultPeriod?.period_start ?? '')
  const [end, setEnd] = useState(props.defaultPeriod?.period_end ?? '')
  const [file, setFile] = useState<File | null>(null)
  const [phase, setPhase] = useState<UploadPhase>({ step: 'idle' })
  const [err, setErr] = useState<string | null>(null)
  const [confirming, setConfirming] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)
  const abortRef = useRef<AbortController | null>(null)
  const busy = phase.step !== 'idle' && phase.step !== 'done'
  const paused = props.feedStatus === 'paused'

  // El periodo propuesto llega despues (calendario): se rellena si el usuario aun no ha escrito nada.
  useEffect(() => {
    if (!props.defaultPeriod) return
    setStart((s) => s || props.defaultPeriod!.period_start)
    setEnd((e) => e || props.defaultPeriod!.period_end)
  }, [props.defaultPeriod])

  // Mientras se calcula la huella o se sube, avisar antes de cerrar la pestaña.
  useEffect(() => {
    if (!busy) return
    const onBeforeUnload = (e: BeforeUnloadEvent) => {
      e.preventDefault()
      e.returnValue = ''
    }
    window.addEventListener('beforeunload', onBeforeUnload)
    return () => window.removeEventListener('beforeunload', onBeforeUnload)
  }, [busy])

  useEffect(() => () => abortRef.current?.abort(), [])

  const check = (): { format: DeliveryFormat } | null => {
    const pe = manualPeriodError(start, end)
    if (pe) {
      setErr(pe)
      return null
    }
    if (!file) {
      setErr('cl.deliveries.upload.file_required')
      return null
    }
    const fc = manualFileCheck(file, props.maxFileBytes)
    if ('errorKey' in fc) {
      setErr(fc.errorKey)
      return null
    }
    return fc
  }

  const send = async () => {
    setConfirming(false)
    const fc = check()
    if (!fc || !file) return
    setErr(null)
    const ctrl = new AbortController()
    abortRef.current = ctrl
    try {
      setPhase({ step: 'hashing', done: 0, total: file.size })
      const sha256 = await sha256Blob(file, { signal: ctrl.signal, onProgress: (done, total) => setPhase({ step: 'hashing', done, total }) })
      const summary = await runManualDelivery(
        props.api(file),
        { periodStart: start, periodEnd: end, sha256, format: fc.format },
        (s) => setPhase({ step: s }),
      )
      setPhase({ step: 'done', summary })
      props.onDone()
    } catch (e) {
      const ex = e as { name?: string; message?: string; code?: string }
      if (ex.name !== 'AbortError') setErr(clErrorKey(ex))
      setPhase({ step: 'idle' })
    } finally {
      abortRef.current = null
    }
  }

  const reset = () => {
    setPhase({ step: 'idle' })
    setFile(null)
    setErr(null)
    if (fileRef.current) fileRef.current.value = ''
  }

  const pct = phase.step === 'hashing' && phase.total > 0 ? Math.floor((phase.done / phase.total) * 100) : null

  return (
    <div className="border border-gray-200 rounded-lg p-3 space-y-3">
      <h3 className="font-medium text-gray-900">{t('cl.deliveries.upload.title')}</h3>
      <p className="text-sm text-gray-600">{t('cl.deliveries.upload.help')}</p>
      {paused ? (
        <p className="text-sm text-amber-700">{t('cl.deliveries.upload.paused')}</p>
      ) : (
        <>
          {props.feedStatus === 'testing' && <p className="text-sm text-amber-700">{t('cl.deliveries.upload.testing')}</p>}
          <div className="flex flex-wrap items-end gap-3">
            <label className="text-sm">
              <span className="block mb-1 text-gray-700">{t('cl.deliveries.upload.period_start')}</span>
              <input type="date" className={input} value={start} disabled={busy} onChange={(e) => setStart(e.target.value)} />
            </label>
            <label className="text-sm">
              <span className="block mb-1 text-gray-700">{t('cl.deliveries.upload.period_end')}</span>
              <input type="date" className={input} value={end} disabled={busy} onChange={(e) => setEnd(e.target.value)} />
            </label>
            <input
              ref={fileRef}
              type="file"
              accept=".jsonl,.ndjson,.csv,application/x-ndjson,text/csv"
              className="hidden"
              onChange={(e) => {
                setFile(e.target.files?.[0] ?? null)
                setErr(null)
                setConfirming(false)
                if (phase.step === 'done') setPhase({ step: 'idle' })
              }}
            />
            <button type="button" disabled={busy} className={btnSecondary} onClick={() => fileRef.current?.click()}>
              <Upload className="w-4 h-4 inline me-1" />
              {t('cl.deliveries.upload.choose')}
            </button>
            {file && (
              <span className="text-sm text-gray-600" dir="auto">
                {file.name} · {fmtBytes(file.size, locale)}
              </span>
            )}
          </div>
          {!busy && phase.step !== 'done' && !confirming && (
            <button
              type="button"
              disabled={!file}
              className={btnPrimary}
              onClick={() => {
                if (check()) {
                  setErr(null)
                  setConfirming(true)
                }
              }}
            >
              {t('cl.deliveries.upload.send')}
            </button>
          )}
          {confirming && (
            <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 space-y-2">
              <p className="text-sm text-amber-900">
                {t('cl.deliveries.upload.confirm', { period: periodLabel(start, end, locale) })}
              </p>
              <div className="flex flex-wrap gap-2">
                <button type="button" className={btnSecondary} onClick={() => setConfirming(false)}>
                  {t('common.cancel')}
                </button>
                <button type="button" className={btnPrimary} onClick={() => void send()}>
                  {t('cl.deliveries.upload.send')}
                </button>
              </div>
            </div>
          )}
          {busy && (
            <div className="space-y-1">
              <p className="text-sm text-amber-700">{t('cl.deliveries.upload.do_not_leave')}</p>
              <p className="text-sm text-gray-700">
                {phase.step === 'hashing' ? t('cl.deliveries.upload.hashing', { percent: pct ?? 0 }) : t(`cl.deliveries.upload.step.${phase.step}`)}
              </p>
              {pct !== null && (
                <div className="h-2 w-full rounded bg-gray-200 overflow-hidden" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct}>
                  <div className="h-full bg-blue-600 transition-all" style={{ width: `${pct}%` }} />
                </div>
              )}
              {phase.step === 'hashing' && (
                <button type="button" className={btnSecondary} onClick={() => abortRef.current?.abort()}>
                  {t('common.cancel')}
                </button>
              )}
            </div>
          )}
          {phase.step === 'done' && <UploadResult summary={phase.summary} onClose={reset} />}
          {err && <p className="text-sm text-red-600">{t(err)}</p>}
        </>
      )}
    </div>
  )
}

function UploadResult({ summary, onClose }: { summary: DeliverySummary; onClose: () => void }) {
  const { t } = useTranslation()
  const errKey = deliveryErrorKey(summary.error)
  const ok = summary.status === 'received' || isDeliveryInFlight(summary.status) || summary.status === 'processed'
  return (
    <div className="space-y-2">
      <p className={`text-sm ${ok ? 'text-green-700' : 'text-red-600'}`}>
        {ok && <CheckCircle className="inline w-4 h-4 me-1" />}
        {summary.existing
          ? t('cl.deliveries.upload.existing', { status: t(deliveryStatusKey(summary.status)) })
          : ok
            ? t('cl.deliveries.upload.received')
            : t('cl.deliveries.upload.rejected')}
      </p>
      {errKey && <p className="text-sm text-red-600">{t(errKey)}</p>}
      <button type="button" className={btnSecondary} onClick={onClose}>
        {t('common.close')}
      </button>
    </div>
  )
}
