import { useEffect, useMemo, useState } from 'react'
import { Loader2, AlertTriangle, X } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { ClHelpLink } from '@/components/carrier-link/ClHelpLink'
import { ClBadge } from '@/components/carrier-link/ClBadge'
import { usePermissions } from '@/contexts/PermissionsContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { ReadOnlyBadge } from '@/components/common/ReadOnlyBadge'
import { SelectAccountNotice } from '@/components/carrier-link/SelectAccountNotice'
import { clErrorKey } from '@/lib/carrierLink/clErrors'
import { useClPlans } from '@/hooks/carrierLink/useClPlans'
import { useClSamples, CL_ALL_PLANS, type ClSampleScan } from '@/hooks/carrierLink/useClSamples'
import { SAMPLES_PAGE_SIZE, clampPage, planWeekKeys, transitLabel } from '@/lib/carrierLink/sampleView'

const input = 'border border-gray-300 rounded-lg px-3 py-2 text-sm'

function fmt(d: string | null) {
  return d ? new Date(d).toLocaleString() : '-'
}

export function ClSamples() {
  const { t } = useTranslation()
  const { canEdit } = usePermissions()
  const accountId = useEffectiveAccountId()
  const readOnly = !canEdit('cl_samples')
  const { plans, cityName, loading: plansLoading } = useClPlans(accountId)

  const [planId, setPlanId] = useState<string | null>(null)
  const [week, setWeek] = useState<string | null>(null)
  const [origin, setOrigin] = useState('')
  const [destination, setDestination] = useState('')
  const [misroutedOnly, setMisroutedOnly] = useState(false)
  const [page, setPage] = useState(0)
  const [openId, setOpenId] = useState<string | null>(null)
  const [scanRows, setScanRows] = useState<ClSampleScan[] | null>(null)
  const [scanError, setScanError] = useState(false)

  // Por defecto: el plan activo mas reciente (la lista ya viene de mas reciente a mas antiguo).
  useEffect(() => {
    if (planId && plans.some((p) => p.id === planId)) return
    const def = plans.find((p) => p.status === 'active') ?? plans[0]
    setPlanId(def?.id ?? null)
  }, [plans, planId])

  const plan = plans.find((p) => p.id === planId) ?? null
  const weeks = useMemo(() => (plan ? planWeekKeys(plan.start_date, plan.end_date) : []), [plan])
  const route = origin || destination ? `${origin}>${destination}` : null
  // Se espera a la lista de planes (sin consultas dobles). Sin planes visibles (p. ej. sin View en cl_plans): todas las
  // muestras de la cuenta.
  const ready = !plansLoading && (planId === null ? plans.length === 0 : plans.some((p) => p.id === planId))
  const samplesScope = !ready ? null : (planId ?? CL_ALL_PLANS)
  const {
    samples,
    total,
    scans,
    cities,
    loading: samplesLoading,
    error,
  } = useClSamples(accountId, samplesScope, { week, route, misroutedOnly }, page)
  const loading = samplesLoading || !ready

  const resetPage = () => {
    setPage(0)
    setOpenId(null)
  }
  const lastPage = Math.max(0, Math.ceil(total / SAMPLES_PAGE_SIZE) - 1)

  // Si el total se reduce (o el servidor responde 416) y la página queda fuera de rango, se ajusta y se recarga.
  useEffect(() => {
    if (loading) return
    const c = clampPage(page, total)
    if (c !== page) setPage(c)
  }, [loading, page, total])

  useEffect(() => {
    if (!openId) {
      setScanRows(null)
      return
    }
    let cancelled = false
    setScanRows(null)
    setScanError(false)
    scans(openId)
      .then((r) => !cancelled && setScanRows(r))
      .catch(() => !cancelled && setScanError(true))
    return () => {
      cancelled = true
    }
  }, [openId, scans])

  const name = (id: string | null) => (id ? cityName(id) : '-')
  const open = samples.find((s) => s.id === openId) ?? null

  const citySelect = (value: string, set: (v: string) => void) => (
    <select
      className={input}
      value={value}
      onChange={(e) => {
        set(e.target.value)
        resetPage()
      }}
    >
      <option value="">{t('cl.samples.all')}</option>
      {cities.map((c) => (
        <option key={c.id} value={c.id}>
          {c.name}
        </option>
      ))}
    </select>
  )

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-bold text-gray-900">{t('cl.samples.title')}</h1>
        <ClBadge />
        <ClHelpLink section="samples" />
        {readOnly && <ReadOnlyBadge />}
      </div>
      <p className="text-sm text-gray-600">{t('cl.samples.help')}</p>
      {accountId === null && <SelectAccountNotice />}

      {accountId !== null && (
        <>
          <div className="flex flex-wrap items-end gap-3">
            <label className="text-sm">
              <span className="block text-gray-600 mb-1">{t('cl.samples.plan')}</span>
              <select
                className={input}
                value={planId ?? ''}
                onChange={(e) => {
                  setPlanId(e.target.value || null)
                  setWeek(null)
                  resetPage()
                }}
              >
                {plans.length === 0 && <option value="">-</option>}
                {plans.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.plan_name}
                    {p.product_label ? ` (${p.product_label})` : ''}
                  </option>
                ))}
              </select>
            </label>
            <label className="text-sm">
              <span className="block text-gray-600 mb-1">{t('cl.samples.week')}</span>
              <select
                className={input}
                value={week ?? ''}
                onChange={(e) => {
                  setWeek(e.target.value || null)
                  resetPage()
                }}
              >
                <option value="">{t('cl.samples.all')}</option>
                {weeks.map((w) => (
                  <option key={w} value={w}>
                    {w}
                  </option>
                ))}
              </select>
            </label>
            <label className="text-sm">
              <span className="block text-gray-600 mb-1">{t('cl.samples.origin')}</span>
              {citySelect(origin, setOrigin)}
            </label>
            <label className="text-sm">
              <span className="block text-gray-600 mb-1">{t('cl.samples.destination')}</span>
              {citySelect(destination, setDestination)}
            </label>
            <label className="flex items-center gap-2 text-sm pb-2">
              <input
                type="checkbox"
                checked={misroutedOnly}
                onChange={(e) => {
                  setMisroutedOnly(e.target.checked)
                  resetPage()
                }}
              />
              {t('cl.samples.misrouted_only')}
            </label>
          </div>

          {error && (
            <div className="flex items-center gap-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">
              <AlertTriangle className="w-4 h-4" /> {t(clErrorKey(error))}
            </div>
          )}

          <div className="flex gap-4 items-start">
            <div className="flex-1 overflow-x-auto bg-white border border-gray-200 rounded-lg">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-left text-gray-600">
                  <tr>
                    <th className="px-3 py-2">{t('cl.samples.item')}</th>
                    <th className="px-3 py-2">{t('cl.samples.route')}</th>
                    <th className="px-3 py-2">{t('cl.samples.start')}</th>
                    <th className="px-3 py-2">{t('cl.samples.end')}</th>
                    <th className="px-3 py-2">{t('cl.samples.transit')}</th>
                    <th className="px-3 py-2">{t('cl.samples.on_time')}</th>
                    <th className="px-3 py-2">{t('cl.samples.misrouted')}</th>
                  </tr>
                </thead>
                <tbody>
                  {loading && (
                    <tr>
                      <td colSpan={7} className="px-3 py-4 text-center text-gray-500">
                        <Loader2 className="w-4 h-4 animate-spin inline" />
                      </td>
                    </tr>
                  )}
                  {!loading && samples.length === 0 && (
                    <tr>
                      <td colSpan={7} className="px-3 py-4 text-center text-gray-500">
                        {t('cl.samples.empty')}
                      </td>
                    </tr>
                  )}
                  {!loading &&
                    samples.map((s) => {
                      const tr = s.start_at && s.end_at ? transitLabel(s.start_at, s.end_at) : null
                      return (
                        <tr
                          key={s.id}
                          onClick={() => setOpenId(s.id)}
                          className={`border-t border-gray-100 cursor-pointer hover:bg-gray-50 ${openId === s.id ? 'bg-blue-50' : ''}`}
                        >
                          <td className="px-3 py-2 font-mono">{s.item_id}</td>
                          <td className="px-3 py-2">
                            {name(s.origin_city_id)} {'->'} {name(s.destination_city_id)}
                          </td>
                          <td className="px-3 py-2">{fmt(s.start_at)}</td>
                          <td className="px-3 py-2">{fmt(s.end_at)}</td>
                          <td className="px-3 py-2">
                            {tr ? t('cl.samples.transit_value', { days: tr.days, hours: tr.hours }) : '-'}
                          </td>
                          <td className="px-3 py-2">
                            {s.on_time_delivery === null ? '-' : s.on_time_delivery ? t('cl.samples.yes') : t('cl.samples.no')}
                          </td>
                          <td className="px-3 py-2">
                            {s.possible_misrouting && (
                              <span className="px-2 py-0.5 rounded-full text-xs bg-amber-100 text-amber-800">
                                {t('cl.samples.misrouted')}
                              </span>
                            )}
                          </td>
                        </tr>
                      )
                    })}
                </tbody>
              </table>
              <div className="flex items-center justify-between px-3 py-2 border-t border-gray-100 text-sm text-gray-600">
                <span>{t('cl.samples.total', { count: total })}</span>
                <div className="flex items-center gap-2">
                  <button
                    className="px-3 py-1 border border-gray-300 rounded-lg disabled:opacity-50"
                    disabled={page === 0 || loading}
                    onClick={() => {
                      setPage((p) => Math.max(0, p - 1))
                      setOpenId(null)
                    }}
                  >
                    {t('cl.samples.prev')}
                  </button>
                  <span>{t('cl.samples.page', { page: page + 1, pages: lastPage + 1 })}</span>
                  <button
                    className="px-3 py-1 border border-gray-300 rounded-lg disabled:opacity-50"
                    disabled={page >= lastPage || loading}
                    onClick={() => {
                      setPage((p) => p + 1)
                      setOpenId(null)
                    }}
                  >
                    {t('cl.samples.next')}
                  </button>
                </div>
              </div>
            </div>

            {openId && (
              <aside className="w-80 shrink-0 bg-white border border-gray-200 rounded-lg p-4 space-y-3">
                <div className="flex items-start justify-between">
                  <div>
                    <h2 className="font-semibold text-gray-900">{t('cl.samples.scans')}</h2>
                    {open && <p className="text-xs font-mono text-gray-500">{open.item_id}</p>}
                  </div>
                  <button aria-label={t('cl.samples.close')} onClick={() => setOpenId(null)}>
                    <X className="w-4 h-4" />
                  </button>
                </div>
                {scanError && <p className="text-sm text-red-700">{t('cl.error.generic')}</p>}
                {!scanError && scanRows === null && <Loader2 className="w-4 h-4 animate-spin" />}
                {scanRows?.length === 0 && <p className="text-sm text-gray-500">{t('cl.samples.no_scans')}</p>}
                <ol className="space-y-2">
                  {scanRows?.map((r) => (
                    <li key={r.id} className="text-sm border-l-2 border-blue-300 pl-3">
                      <div className="font-medium">{t(`cl.samples.role.${r.role}`)}</div>
                      <div className="text-gray-700">
                        {r.place ?? '-'}
                        {r.mode ? ` / ${r.mode}` : ''}
                      </div>
                      <div className="text-xs text-gray-500">{fmt(r.scan_at)}</div>
                    </li>
                  ))}
                </ol>
              </aside>
            )}
          </div>
        </>
      )}
    </div>
  )
}
