import { useCallback, useEffect, useMemo, useState } from 'react'
import { Plus, Pencil, AlertTriangle, Loader2 } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { ClHelpLink } from '@/components/carrier-link/ClHelpLink'
import { usePermissions } from '@/contexts/PermissionsContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { ReadOnlyBadge } from '@/components/common/ReadOnlyBadge'
import { SelectAccountNotice } from '@/components/carrier-link/SelectAccountNotice'
import { QuotaMatrix } from '@/components/carrier-link/QuotaMatrix'
import { clErrorKey } from '@/lib/carrierLink/clErrors'
import { useLatestRequest } from '@/lib/latestRequest'
import { generateClQuotas, type ClQuota } from '@/lib/carrierLink/quotaCalculator'
import {
  routeKey,
  routesForPlan,
  routesWithoutStandard,
  setQuotasErrorKey,
  planSaveFollowUp,
  type PlanForm,
  type QuotaInput,
} from '@/lib/carrierLink/planView'
import { useClReadingPoints, useClCarriersAndCenters } from '@/hooks/carrierLink/useClReadingPoints'
import { useClConnectors } from '@/hooks/carrierLink/useClConnectors'
import {
  useClPlans,
  type ClPlan,
  type ClPlanStatus,
  type ClMissingPoint,
  type ClMissingStandard,
} from '@/hooks/carrierLink/useClPlans'

const input = 'w-full border border-gray-300 rounded-lg px-3 py-2 disabled:bg-gray-100 disabled:text-gray-500'
const btnPrimary = 'inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50'
const btnSecondary = 'inline-flex items-center gap-2 px-3 py-2 border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50'

const STATUS_STYLE: Record<ClPlanStatus, string> = {
  draft: 'bg-gray-200 text-gray-700',
  active: 'bg-green-100 text-green-800',
  closed: 'bg-blue-100 text-blue-800',
}

/** Máximo de rutas sin estándar listadas en el aviso (la tabla las marca todas con ⚠). */
const STANDARD_LIST_LIMIT = 30

interface EditorState {
  id: string | null
  status: ClPlanStatus
  form: PlanForm
}

interface Detail {
  quotas: QuotaInput[]
  missingPoints: ClMissingPoint[]
  missingStandards: ClMissingStandard[]
}

const toQuotaInput = (q: ClQuota): QuotaInput => ({
  origin_city_id: q.origin_city_id,
  destination_city_id: q.destination_city_id,
  iso_year: q.iso_year,
  iso_week: q.iso_week,
  samples_planned: q.samples,
  samples_carried_in: 0,
  samples_obtained: 0,
  status: 'pending',
})

export function ClPlans() {
  const { t } = useTranslation()
  const { canEdit } = usePermissions()
  const accountId = useEffectiveAccountId()
  const readOnly = !canEdit('cl_plans')

  const cl = useClPlans(accountId)
  const { carriers } = useClCarriersAndCenters(accountId)
  const { feeds } = useClConnectors(accountId)

  const [selectedId, setSelectedId] = useState<string | null>(null)
  const selected = cl.plans.find((p) => p.id === selectedId) ?? null
  const { points, loading: pointsLoading } = useClReadingPoints(accountId, selected?.carrier_id ?? null)

  const [editor, setEditor] = useState<EditorState | null>(null)
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)

  const beginDetail = useLatestRequest()
  const beginGenerate = useLatestRequest()
  const [detail, setDetail] = useState<Detail | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [preview, setPreview] = useState<ClQuota[] | null>(null)
  const [previewNoStandard, setPreviewNoStandard] = useState<Set<string>>(new Set())
  const [generating, setGenerating] = useState(false)
  const [savingQuotas, setSavingQuotas] = useState(false)
  const [confirmActivate, setConfirmActivate] = useState(false)
  const [activating, setActivating] = useState(false)
  const [message, setMessage] = useState<{ kind: 'error' | 'info'; key: string; vars?: Record<string, unknown> } | null>(null)

  const { quotas: loadQuotas, missingPoints: loadMissingPoints, missingStandards: loadMissingStandards } = cl

  const loadDetail = useCallback(
    async (planId: string) => {
      const isStale = beginDetail()
      setDetailLoading(true)
      try {
        const [quotas, missingPoints, missingStandards] = await Promise.all([
          loadQuotas(planId),
          loadMissingPoints(planId),
          loadMissingStandards(planId),
        ])
        if (isStale()) return
        setDetail({ quotas, missingPoints, missingStandards })
      } catch (e) {
        if (isStale()) return
        setDetail(null)
        setMessage({ kind: 'error', key: clErrorKey(e as { message?: string; code?: string }) })
      } finally {
        if (!isStale()) setDetailLoading(false)
      }
    },
    [beginDetail, loadQuotas, loadMissingPoints, loadMissingStandards],
  )

  // Al cambiar de plan (o de cuenta) se descarta la vista previa y se recargan las cuotas.
  useEffect(() => {
    beginGenerate() // una generación en curso del plan anterior queda descartada
    setPreview(null)
    setGenerating(false)
    setConfirmActivate(false)
    setMessage(null)
    setDetail(null)
    if (selectedId) void loadDetail(selectedId)
    else beginDetail()
  }, [selectedId, loadDetail, beginDetail, beginGenerate])

  useEffect(() => {
    setSelectedId(null)
    setEditor(null)
  }, [accountId])

  const noStandard = useMemo(
    () => new Set((detail?.missingStandards ?? []).map((s) => routeKey(s.origin_city_id, s.destination_city_id))),
    [detail],
  )
  const previewInput = useMemo(() => (preview ? preview.map(toQuotaInput) : null), [preview])

  const productLabel = (id: string) => {
    const p = cl.products.find((x) => x.id === id)
    return p ? `${p.code} - ${p.description}` : ''
  }

  // ---------------------------------------------------------------- formulario
  const emptyForm = (): PlanForm => ({
    plan_name: '',
    carrier_id: carriers[0]?.id ?? '',
    product_id: '',
    feed_id: '',
    start_date: '',
    end_date: '',
    total_samples: 0,
    feed_diagnosis: false,
  })

  const openNew = () => {
    setFormError(null)
    setEditor({ id: null, status: 'draft', form: emptyForm() })
  }

  const openEdit = (p: ClPlan) => {
    setFormError(null)
    setEditor({
      id: p.id,
      status: p.status,
      form: {
        plan_name: p.plan_name,
        carrier_id: p.carrier_id,
        product_id: p.product_id,
        feed_id: p.feed_id ?? '',
        start_date: p.start_date,
        end_date: p.end_date,
        total_samples: p.total_samples,
        feed_diagnosis: p.feed_diagnosis,
      },
    })
  }

  const setField = <K extends keyof PlanForm>(k: K, v: PlanForm[K]) =>
    setEditor((e) => {
      if (!e) return e
      const form = { ...e.form, [k]: v }
      // El producto y el conector dependen del carrier.
      if (k === 'carrier_id') {
        form.product_id = ''
        form.feed_id = ''
      }
      return { ...e, form }
    })

  const save = async () => {
    if (!editor) return
    setSaving(true)
    setFormError(null)
    const res = editor.id ? await cl.update(editor.id, editor.form, editor.status) : await cl.create(editor.form)
    setSaving(false)
    if (!res.success) {
      setFormError(res.key ?? clErrorKey(res.error))
      return
    }
    setEditor(null)
    if (res.id) {
      setSelectedId(res.id)
      return
    }
    const before = cl.plans.find((p) => p.id === editor.id) ?? null
    const followUp = planSaveFollowUp({
      editedId: editor.id,
      selectedId,
      status: editor.status,
      before,
      after: editor.form,
      hadPreview: !!preview,
      hasSavedQuotas: (detail?.quotas.length ?? 0) > 0,
    })
    if (followUp.clearPreview) {
      beginGenerate() // una generación en curso usa el total/fechas viejos: queda descartada
      setGenerating(false)
      setPreview(null)
      setConfirmActivate(false)
      setMessage(followUp.regenerateNotice ? { kind: 'info', key: 'cl.plans.regenerate_notice' } : null)
      if (editor.id) void loadDetail(editor.id)
    }
  }

  // ---------------------------------------------------------------- cuotas y activación
  const generate = async () => {
    if (!selected || pointsLoading) return
    // Puntos aún del carrier anterior (un render tras cambiar de plan): no se genera nada.
    const routes = routesForPlan(points, selected.carrier_id)
    if (!routes) return
    setMessage(null)
    if (routes.length === 0) {
      setPreview(null)
      setMessage({ kind: 'error', key: 'cl.plans.no_routes' })
      return
    }
    const quotas = generateClQuotas({
      totalSamples: selected.total_samples,
      startDate: selected.start_date,
      endDate: selected.end_date,
      routes,
      nonWorkingDays: cl.nonWorkingDays,
      workingDows: cl.workingDows,
    })
    const isStale = beginGenerate()
    setGenerating(true)
    let standards: { origin_city_id: string; destination_city_id: string }[] | null = null
    try {
      standards = await cl.standardRoutes(selected.carrier_id, selected.product_id)
    } catch {
      standards = null // sin estándares legibles no se marca ⚠ en la vista previa; tras guardar lo dice la base
    }
    if (isStale()) return
    setGenerating(false)
    setPreviewNoStandard(standards ? routesWithoutStandard(quotas, standards) : new Set())
    setPreview(quotas)
  }

  const saveQuotas = async () => {
    if (!selected || !preview) return
    setSavingQuotas(true)
    setMessage(null)
    const res = await cl.setQuotas(selected.id, preview)
    setSavingQuotas(false)
    if (!res.success) {
      setMessage({ kind: 'error', key: setQuotasErrorKey(res.error) })
      return
    }
    setMessage({ kind: 'info', key: 'cl.plans.quotas_saved', vars: { count: preview.length } })
    setPreview(null)
    await loadDetail(selected.id)
  }

  const activate = async () => {
    if (!selected) return
    setActivating(true)
    setMessage(null)
    const res = await cl.activate(selected.id)
    setActivating(false)
    setConfirmActivate(false)
    if (!res.success) {
      setMessage({ kind: 'error', key: clErrorKey(res.error) })
      return
    }
    void loadDetail(selected.id)
  }

  const missingPoints = detail?.missingPoints ?? []
  const missingStandards = detail?.missingStandards ?? []
  const hasSavedQuotas = (detail?.quotas.length ?? 0) > 0
  const canActivate =
    !readOnly && selected?.status === 'draft' && !preview && !detailLoading && hasSavedQuotas && missingPoints.length === 0

  const editorCarrierFeeds = editor ? feeds.filter((f) => f.carrier_id === editor.form.carrier_id) : []
  const editorProducts = editor ? cl.products.filter((p) => p.carrier_id === editor.form.carrier_id) : []
  const locked = !!editor && editor.status !== 'draft'

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-bold text-gray-900">{t('cl.plans.title')}</h1>
        <ClHelpLink section="plans" />
        {readOnly && <ReadOnlyBadge />}
      </div>
      <p className="text-sm text-gray-600">{t('cl.plans.help')}</p>

      {accountId === null ? (
        <SelectAccountNotice />
      ) : (
        <>
          {!readOnly && (
            <button type="button" onClick={openNew} disabled={carriers.length === 0} className={btnPrimary}>
              <Plus className="w-4 h-4" />
              {t('cl.plans.new')}
            </button>
          )}
          {cl.error && <p className="text-sm text-red-600">{t(clErrorKey(cl.error))}</p>}

          <div className="bg-white rounded-lg border border-gray-200 overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead className="bg-gray-50 text-gray-600">
                <tr>
                  <th className="text-start px-4 py-2">{t('cl.plans.name')}</th>
                  <th className="text-start px-4 py-2">{t('cl.plans.product')}</th>
                  <th className="text-start px-4 py-2">{t('cl.plans.carrier')}</th>
                  <th className="text-start px-4 py-2">{t('cl.plans.period')}</th>
                  <th className="text-end px-4 py-2">{t('cl.plans.total')}</th>
                  <th className="text-start px-4 py-2">{t('cl.plans.status')}</th>
                </tr>
              </thead>
              <tbody>
                {cl.loading && (
                  <tr>
                    <td className="px-4 py-3 text-gray-500" colSpan={6}>
                      {t('common.loading')}
                    </td>
                  </tr>
                )}
                {!cl.loading && cl.plans.length === 0 && (
                  <tr>
                    <td className="px-4 py-3 text-gray-500" colSpan={6}>
                      {t('cl.plans.empty')}
                    </td>
                  </tr>
                )}
                {cl.plans.map((p) => (
                  <tr
                    key={p.id}
                    onClick={() => setSelectedId(p.id)}
                    className={`border-t border-gray-100 cursor-pointer hover:bg-gray-50 ${p.id === selectedId ? 'bg-blue-50' : ''}`}
                  >
                    <td className="px-4 py-2 font-medium">{p.plan_name}</td>
                    <td className="px-4 py-2">{p.product_label ?? '-'}</td>
                    <td className="px-4 py-2">{p.carrier_name ?? '-'}</td>
                    <td className="px-4 py-2 whitespace-nowrap">
                      {p.start_date} → {p.end_date}
                    </td>
                    <td className="px-4 py-2 text-end">{p.total_samples}</td>
                    <td className="px-4 py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs ${STATUS_STYLE[p.status]}`}>{t(`cl.plans.status.${p.status}`)}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {selected && (
            <div className="bg-white rounded-lg border border-gray-200 p-4 space-y-4">
              <div className="flex flex-wrap items-center gap-3">
                <h2 className="text-lg font-semibold text-gray-900">{selected.plan_name}</h2>
                <span className={`px-2 py-0.5 rounded-full text-xs ${STATUS_STYLE[selected.status]}`}>
                  {t(`cl.plans.status.${selected.status}`)}
                </span>
                <span className="text-sm text-gray-600">
                  {selected.product_label ?? '-'} · {selected.carrier_name ?? '-'} · {selected.start_date} → {selected.end_date} ·{' '}
                  {t('cl.plans.samples', { count: selected.total_samples })}
                </span>
                <div className="flex-1" />
                {!readOnly && selected.status !== 'closed' && (
                  <button type="button" onClick={() => openEdit(selected)} className={btnSecondary}>
                    <Pencil className="w-4 h-4" />
                    {t('common.edit')}
                  </button>
                )}
                {!readOnly && selected.status === 'draft' && (
                  <button
                    type="button"
                    onClick={() => void generate()}
                    disabled={pointsLoading || generating || savingQuotas || routesForPlan(points, selected.carrier_id) === null}
                    className={btnSecondary}
                  >
                    {generating && <Loader2 className="w-4 h-4 animate-spin" />}
                    {t('cl.plans.generate')}
                  </button>
                )}
                {!readOnly && selected.status === 'draft' && (
                  <button
                    type="button"
                    onClick={() => setConfirmActivate(true)}
                    disabled={!canActivate}
                    title={missingPoints.length > 0 ? t('cl.plans.activate_blocked') : undefined}
                    className={btnPrimary}
                  >
                    {t('cl.plans.activate')}
                  </button>
                )}
              </div>

              {message && (
                <p className={`text-sm ${message.kind === 'error' ? 'text-red-600' : 'text-green-700'}`}>{t(message.key, message.vars)}</p>
              )}

              {confirmActivate && (
                <div className="rounded-lg border border-blue-200 bg-blue-50 p-4 space-y-3">
                  <p className="text-sm text-blue-900">{t('cl.plans.activate_confirm', { name: selected.plan_name })}</p>
                  <div className="flex gap-2">
                    <button type="button" onClick={() => setConfirmActivate(false)} className={btnSecondary}>
                      {t('common.cancel')}
                    </button>
                    <button type="button" onClick={() => void activate()} disabled={activating} className={btnPrimary}>
                      {activating && <Loader2 className="w-4 h-4 animate-spin" />}
                      {t('cl.plans.activate')}
                    </button>
                  </div>
                </div>
              )}

              {!preview && selected.status === 'draft' && missingPoints.length > 0 && (
                <div className="rounded-lg border border-red-200 bg-red-50 p-4 space-y-1">
                  <p className="font-medium text-red-900">{t('cl.plans.missing_points_title')}</p>
                  <p className="text-sm text-red-900">{t('cl.plans.missing_points_help')}</p>
                  <ul className="text-sm text-red-900 list-disc ps-5">
                    {missingPoints.map((m) => (
                      <li key={`${m.city_id}|${m.missing}`}>
                        {m.city_name}: {t(`cl.plans.missing.${m.missing}`)}
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {!preview && missingStandards.length > 0 && (
                <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 space-y-1">
                  <p className="font-medium text-amber-900 inline-flex items-center gap-2">
                    <AlertTriangle className="w-4 h-4" />
                    {t('cl.plans.missing_standards_title', { count: missingStandards.length })}
                  </p>
                  <p className="text-sm text-amber-900">{t('cl.plans.missing_standards_help')}</p>
                  <ul className="text-sm text-amber-900 list-disc ps-5">
                    {missingStandards.slice(0, STANDARD_LIST_LIMIT).map((s) => (
                      <li key={routeKey(s.origin_city_id, s.destination_city_id)}>
                        {cl.cityName(s.origin_city_id)} → {cl.cityName(s.destination_city_id)}: ⚠ {t('cl.plans.no_standard')}
                      </li>
                    ))}
                  </ul>
                  {missingStandards.length > STANDARD_LIST_LIMIT && (
                    <p className="text-sm text-amber-900">{t('cl.plans.more', { count: missingStandards.length - STANDARD_LIST_LIMIT })}</p>
                  )}
                </div>
              )}

              {previewInput ? (
                <div className="space-y-3">
                  <div className="flex flex-wrap items-center gap-3">
                    <h3 className="font-semibold text-gray-900">{t('cl.plans.preview_title')}</h3>
                    <button type="button" onClick={() => void saveQuotas()} disabled={savingQuotas} className={btnPrimary}>
                      {savingQuotas && <Loader2 className="w-4 h-4 animate-spin" />}
                      {savingQuotas ? t('cl.plans.saving_quotas', { count: previewInput.length }) : t('cl.plans.save_quotas')}
                    </button>
                    <button type="button" onClick={() => setPreview(null)} disabled={savingQuotas} className={btnSecondary}>
                      {t('cl.plans.discard')}
                    </button>
                  </div>
                  <QuotaMatrix quotas={previewInput} cityName={cl.cityName} showObtained={false} noStandard={previewNoStandard} />
                </div>
              ) : detailLoading ? (
                <p className="text-sm text-gray-500">{t('common.loading')}</p>
              ) : hasSavedQuotas ? (
                <div className="space-y-3">
                  <h3 className="font-semibold text-gray-900">{t('cl.plans.quotas_title')}</h3>
                  <QuotaMatrix
                    quotas={detail!.quotas}
                    cityName={cl.cityName}
                    showObtained={selected.status !== 'draft'}
                    noStandard={noStandard}
                  />
                </div>
              ) : (
                detail && <p className="text-sm text-gray-500">{t('cl.plans.no_quotas')}</p>
              )}
            </div>
          )}
        </>
      )}

      {editor && !readOnly && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg shadow-xl w-full max-w-lg p-6 space-y-4 max-h-[90vh] overflow-y-auto">
            <h2 className="text-lg font-semibold">{editor.id ? t('cl.plans.edit') : t('cl.plans.new')}</h2>
            {locked && <p className="text-sm text-gray-600">{t('cl.plans.locked_hint')}</p>}
            <label className="block text-sm">
              <span className="block mb-1">{t('cl.plans.name')}</span>
              <input className={input} value={editor.form.plan_name} onChange={(e) => setField('plan_name', e.target.value)} />
            </label>
            <label className="block text-sm">
              <span className="block mb-1">{t('cl.plans.carrier')}</span>
              <select
                className={input}
                disabled={locked}
                value={editor.form.carrier_id}
                onChange={(e) => setField('carrier_id', e.target.value)}
              >
                <option value="">{t('cl.plans.select')}</option>
                {carriers.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name} ({c.code})
                  </option>
                ))}
              </select>
            </label>
            <label className="block text-sm">
              <span className="block mb-1">{t('cl.plans.product')}</span>
              <select
                className={input}
                disabled={locked}
                value={editor.form.product_id}
                onChange={(e) => setField('product_id', e.target.value)}
              >
                <option value="">{t('cl.plans.select')}</option>
                {editorProducts.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.code} - {p.description}
                  </option>
                ))}
                {locked && editor.form.product_id && !editorProducts.some((p) => p.id === editor.form.product_id) && (
                  <option value={editor.form.product_id}>{productLabel(editor.form.product_id) || selected?.product_label}</option>
                )}
              </select>
            </label>
            <label className="block text-sm">
              <span className="block mb-1">{t('cl.plans.connector')}</span>
              <select className={input} disabled={locked} value={editor.form.feed_id} onChange={(e) => setField('feed_id', e.target.value)}>
                <option value="">{t('cl.plans.no_connector')}</option>
                {editorCarrierFeeds.map((f) => (
                  <option key={f.id} value={f.id}>
                    {f.name}
                  </option>
                ))}
              </select>
              <span className="text-xs text-gray-500">{t('cl.plans.connector_hint')}</span>
            </label>
            <div className="grid grid-cols-2 gap-3">
              <label className="block text-sm">
                <span className="block mb-1">{t('cl.plans.start')}</span>
                <input
                  type="date"
                  className={input}
                  disabled={locked}
                  value={editor.form.start_date}
                  onChange={(e) => setField('start_date', e.target.value)}
                />
              </label>
              <label className="block text-sm">
                <span className="block mb-1">{t('cl.plans.end')}</span>
                <input type="date" className={input} value={editor.form.end_date} onChange={(e) => setField('end_date', e.target.value)} />
              </label>
            </div>
            <label className="block text-sm">
              <span className="block mb-1">{t('cl.plans.total')}</span>
              <input
                type="number"
                min={1}
                step={1}
                className={input}
                value={editor.form.total_samples || ''}
                onChange={(e) => setField('total_samples', Number(e.target.value))}
              />
              {editor.status === 'draft' && editor.id && <span className="text-xs text-gray-500">{t('cl.plans.total_hint')}</span>}
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={editor.form.feed_diagnosis} onChange={(e) => setField('feed_diagnosis', e.target.checked)} />
              {t('cl.plans.feed_diagnosis')}
            </label>
            {formError && <p className="text-sm text-red-600">{t(formError)}</p>}
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setEditor(null)} className="px-4 py-2 border border-gray-300 rounded-lg">
                {t('common.cancel')}
              </button>
              <button type="button" disabled={saving} onClick={() => void save()} className={btnPrimary}>
                {saving ? t('common.saving') : t('common.save')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
