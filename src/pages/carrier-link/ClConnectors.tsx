import { useEffect, useMemo, useRef, useState } from 'react'
import { Plus, Pencil, Trash2, Copy, CheckCircle, Ban, Upload } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { ClHelpLink } from '@/components/carrier-link/ClHelpLink'
import { ClBadge } from '@/components/carrier-link/ClBadge'
import { usePermissions } from '@/contexts/PermissionsContext'
import { useAuth } from '@/contexts/AuthContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { useIsUpuAccountManager } from '@/hooks/useIsUpuAccountManager'
import { ReadOnlyBadge } from '@/components/common/ReadOnlyBadge'
import { SelectAccountNotice } from '@/components/carrier-link/SelectAccountNotice'
import { useClCarriersAndCenters } from '@/hooks/carrierLink/useClReadingPoints'
import { useClConnectors, type ClFeed, type ClFeedForm, type ClConnectorResult } from '@/hooks/carrierLink/useClConnectors'
import { clErrorKey } from '@/lib/carrierLink/clErrors'
import {
  STANDARD_FIELDS,
  REQUIRED_STANDARD_FIELDS,
  CONNECTOR_STATUSES,
  ISO_DAYS,
  validateFieldMappings,
  validateCalendar,
  canManageCarrierKeys,
  connectorErrorKey,
  parseDryRunResult,
  dryRunOutcome,
  type ConnectorStatus,
  type StandardField,
  type DryRunSummary,
} from '@/lib/carrierLink/connectorConfig'
import {
  canUploadManually,
  manualFileError,
  runManualBatch,
  samplingTotals,
  progressPercent,
  storedBatchMessageKey,
  type ManualBatchOutcome,
} from '@/lib/carrierLink/manualBatch'

type T = (key: string, vars?: Record<string, unknown>, fallback?: string) => string

const input = 'border border-gray-300 rounded-lg px-3 py-2'
const btnPrimary = 'inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50'
const btnSecondary = 'px-3 py-2 border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50'

const STATUS_STYLE: Record<ConnectorStatus, string> = {
  testing: 'bg-amber-100 text-amber-800',
  active: 'bg-green-100 text-green-800',
  paused: 'bg-gray-200 text-gray-700',
}

/** Iniciales de lunes (1) a domingo (7) en el idioma de la pantalla. 2024-01-01 fue lunes. */
function weekdayInitials(locale: string): string[] {
  let fmt: Intl.DateTimeFormat
  try {
    fmt = new Intl.DateTimeFormat(locale, { weekday: 'narrow', timeZone: 'UTC' })
  } catch {
    fmt = new Intl.DateTimeFormat('en', { weekday: 'narrow', timeZone: 'UTC' })
  }
  return ISO_DAYS.map((d) => fmt.format(new Date(Date.UTC(2024, 0, d))))
}

const hourLabel = (h: number) => `${String(h).padStart(2, '0')}:00`
const fmtDate = (s: string | null) => (s ? new Date(s).toLocaleDateString() : '-')

function emptyFeedForm(carrierId: string): ClFeedForm {
  return { carrier_id: carrierId, name: '', extraction_model: '', emit_days: [1], emit_hour: 3, emit_timezone: '' }
}

export function ClConnectors() {
  const { t, locale } = useTranslation()
  const { canEdit } = usePermissions()
  const { profile } = useAuth()
  const accountId = useEffectiveAccountId()
  const readOnly = !canEdit('cl_connectors')
  const { isUpuAm } = useIsUpuAccountManager(accountId)
  const canKeys = !readOnly && canManageCarrierKeys({ isSuperadmin: profile?.role === 'superadmin', isUpuAm })

  const { carriers, error: lookupError } = useClCarriersAndCenters(accountId)
  const cl = useClConnectors(accountId)
  const [carrierId, setCarrierId] = useState('')
  const [feedId, setFeedId] = useState('')
  const [editor, setEditor] = useState<{ id: string | null; form: ClFeedForm } | null>(null)
  const [deleting, setDeleting] = useState<ClFeed | null>(null)
  const [busy, setBusy] = useState(false)
  const [modalError, setModalError] = useState<string | null>(null)

  const days = useMemo(() => weekdayInitials(locale), [locale])
  const carrierFeeds = useMemo(() => cl.feeds.filter((f) => f.carrier_id === carrierId), [cl.feeds, carrierId])
  const feed = carrierFeeds.find((f) => f.id === feedId) ?? null

  useEffect(() => {
    if (!carrierId && carriers.length > 0) setCarrierId(carriers[0].id)
  }, [carriers, carrierId])

  useEffect(() => {
    if (!carrierFeeds.some((f) => f.id === feedId)) setFeedId(carrierFeeds[0]?.id ?? '')
  }, [carrierFeeds, feedId])

  const saveFeed = async () => {
    if (!editor) return
    if (!editor.form.name.trim()) return setModalError('cl.connectors.error.name_required')
    const cal = validateCalendar({
      emit_days: editor.form.emit_days,
      emit_hour: editor.form.emit_hour,
      emit_timezone: editor.form.emit_timezone.trim() || null,
    })
    if (!cal.ok) return setModalError(`cl.connectors.error.${cal.error}`)
    setBusy(true)
    setModalError(null)
    const res = await cl.saveFeed(editor.id, editor.form)
    setBusy(false)
    if (res.success) setEditor(null)
    else setModalError(connectorErrorKey(res.error))
  }

  const confirmDelete = async () => {
    if (!deleting) return
    setBusy(true)
    const res = await cl.removeFeed(deleting.id)
    setBusy(false)
    if (res.success) setDeleting(null)
    else setModalError(connectorErrorKey(res.error))
  }

  const toggleDay = (d: number) =>
    setEditor((e) =>
      e
        ? {
            ...e,
            form: {
              ...e.form,
              emit_days: e.form.emit_days.includes(d) ? e.form.emit_days.filter((x) => x !== d) : [...e.form.emit_days, d],
            },
          }
        : e,
    )

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-bold text-gray-900">{t('cl.connectors.title')}</h1>
        <ClBadge />
        <ClHelpLink section="connectors" />
        {readOnly && <ReadOnlyBadge />}
      </div>
      <p className="text-sm text-gray-600">{t('cl.connectors.help')}</p>

      {accountId === null ? (
        <SelectAccountNotice />
      ) : (
        <>
          <div className="flex flex-wrap items-end gap-3">
            <label className="text-sm text-gray-700">
              <span className="block mb-1">{t('cl.connectors.carrier')}</span>
              <select className={`${input} min-w-[14rem]`} value={carrierId} onChange={(e) => setCarrierId(e.target.value)}>
                {carriers.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name} ({c.code})
                  </option>
                ))}
              </select>
            </label>
            {carrierFeeds.length > 1 && (
              <label className="text-sm text-gray-700">
                <span className="block mb-1">{t('cl.connectors.connector')}</span>
                <select className={`${input} min-w-[14rem]`} value={feedId} onChange={(e) => setFeedId(e.target.value)}>
                  {carrierFeeds.map((f) => (
                    <option key={f.id} value={f.id}>
                      {f.name}
                    </option>
                  ))}
                </select>
              </label>
            )}
            {!readOnly && (
              <button
                type="button"
                disabled={!carrierId}
                className={btnPrimary}
                onClick={() => {
                  setModalError(null)
                  setEditor({ id: null, form: emptyFeedForm(carrierId) })
                }}
              >
                <Plus className="w-4 h-4" />
                {t('cl.connectors.add')}
              </button>
            )}
          </div>

          {lookupError && <p className="text-sm text-red-600">{t(clErrorKey(lookupError))}</p>}
          {!lookupError && carriers.length === 0 && <p className="text-sm text-gray-500">{t('cl.reading_points.no_carriers')}</p>}
          {cl.error && <p className="text-sm text-red-600">{t(clErrorKey(cl.error))}</p>}
          {cl.loading && <p className="text-sm text-gray-500">{t('common.loading')}</p>}
          {!cl.loading && carrierId && carrierFeeds.length === 0 && (
            <p className="text-sm text-gray-500">{t('cl.connectors.empty')}</p>
          )}

          {feed && (
            <>
              <FeedCard
                key={`card-${feed.id}`}
                t={t}
                feed={feed}
                days={days}
                readOnly={readOnly}
                setStatus={cl.setStatus}
                onEdit={() => {
                  setModalError(null)
                  setEditor({
                    id: feed.id,
                    form: {
                      carrier_id: feed.carrier_id,
                      name: feed.name,
                      extraction_model: feed.extraction_model ?? '',
                      emit_days: [...feed.emit_days],
                      emit_hour: feed.emit_hour,
                      emit_timezone: feed.emit_timezone ?? '',
                    },
                  })
                }}
                onDelete={() => {
                  setModalError(null)
                  setDeleting(feed)
                }}
                mappingOk={validateFieldMappings(cl.mappings(feed.id).fields).ok}
              />
              <FieldMappingsSection key={`fm-${feed.carrier_id}`} t={t} carrierId={feed.carrier_id} cl={cl} feedId={feed.id} readOnly={readOnly} />
              <ValueMappingsSection key={`vm-${feed.carrier_id}`} t={t} carrierId={feed.carrier_id} cl={cl} feedId={feed.id} readOnly={readOnly} />
              <ExtraFieldsSection key={`ef-${feed.carrier_id}`} t={t} carrierId={feed.carrier_id} cl={cl} feedId={feed.id} readOnly={readOnly} />
              <KeysSection key={`k-${feed.id}`} t={t} feedId={feed.id} cl={cl} canKeys={canKeys} />
              {!readOnly && <DryRunSection key={`dr-${feed.id}`} t={t} feedId={feed.id} cl={cl} />}
              {!readOnly && <ManualBatchSection key={`mb-${feed.id}`} t={t} feed={feed} cl={cl} />}
            </>
          )}
        </>
      )}

      {editor && !readOnly && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg shadow-xl w-full max-w-lg p-6 space-y-4">
            <h2 className="text-lg font-semibold">{editor.id ? t('cl.connectors.edit') : t('cl.connectors.add')}</h2>
            <label className="block text-sm">
              <span className="block mb-1">{t('cl.connectors.name')}</span>
              <input
                className={`w-full ${input}`}
                value={editor.form.name}
                onChange={(e) => setEditor({ ...editor, form: { ...editor.form, name: e.target.value } })}
              />
            </label>
            <label className="block text-sm">
              <span className="block mb-1">{t('cl.connectors.extraction_model')}</span>
              <input
                className={`w-full ${input}`}
                value={editor.form.extraction_model}
                onChange={(e) => setEditor({ ...editor, form: { ...editor.form, extraction_model: e.target.value } })}
              />
            </label>
            <fieldset className="text-sm">
              <legend className="mb-1">{t('cl.connectors.emit_days')}</legend>
              <div className="flex gap-1">
                {ISO_DAYS.map((d, i) => (
                  <button
                    key={d}
                    type="button"
                    aria-pressed={editor.form.emit_days.includes(d)}
                    onClick={() => toggleDay(d)}
                    className={`w-9 h-9 rounded-full border ${
                      editor.form.emit_days.includes(d) ? 'bg-blue-600 text-white border-blue-600' : 'border-gray-300 text-gray-700'
                    }`}
                  >
                    {days[i]}
                  </button>
                ))}
              </div>
            </fieldset>
            <div className="flex gap-3">
              <label className="block text-sm">
                <span className="block mb-1">{t('cl.connectors.emit_hour')}</span>
                <select
                  className={input}
                  value={editor.form.emit_hour}
                  onChange={(e) => setEditor({ ...editor, form: { ...editor.form, emit_hour: Number(e.target.value) } })}
                >
                  {Array.from({ length: 24 }, (_, h) => (
                    <option key={h} value={h}>
                      {hourLabel(h)}
                    </option>
                  ))}
                </select>
              </label>
              <label className="block text-sm flex-1">
                <span className="block mb-1">{t('cl.connectors.emit_timezone')}</span>
                <input
                  className={`w-full ${input}`}
                  value={editor.form.emit_timezone}
                  placeholder={t('cl.connectors.account_timezone')}
                  onChange={(e) => setEditor({ ...editor, form: { ...editor.form, emit_timezone: e.target.value } })}
                />
              </label>
            </div>
            <p className="text-xs text-gray-500">{t('cl.connectors.calendar_hint')}</p>
            {modalError && <p className="text-sm text-red-600">{t(modalError)}</p>}
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setEditor(null)} className={btnSecondary}>
                {t('common.cancel')}
              </button>
              <button type="button" disabled={busy} onClick={() => void saveFeed()} className={btnPrimary}>
                {busy ? t('common.saving') : t('common.save')}
              </button>
            </div>
          </div>
        </div>
      )}

      {deleting && !readOnly && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg shadow-xl w-full max-w-md p-6 space-y-4">
            <h2 className="text-lg font-semibold">{t('cl.connectors.delete_title')}</h2>
            <p className="text-sm text-gray-700">{t('cl.connectors.delete_confirm', { name: deleting.name })}</p>
            {modalError && <p className="text-sm text-red-600">{t(modalError)}</p>}
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setDeleting(null)} className={btnSecondary}>
                {t('common.cancel')}
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={() => void confirmDelete()}
                className="px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 disabled:opacity-50"
              >
                {t('common.delete')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

type Cl = ReturnType<typeof useClConnectors>

function Section({ title, help, children }: { title: string; help?: string; children: React.ReactNode }) {
  return (
    <section className="bg-white rounded-lg border border-gray-200 p-4 space-y-3">
      <h2 className="font-semibold text-gray-900">{title}</h2>
      {help && <p className="text-sm text-gray-600">{help}</p>}
      {children}
    </section>
  )
}

function FeedCard(props: {
  t: T
  feed: ClFeed
  days: string[]
  readOnly: boolean
  mappingOk: boolean
  setStatus: Cl['setStatus']
  onEdit: () => void
  onDelete: () => void
}) {
  const { t, feed, days, readOnly } = props
  const [pending, setPending] = useState<ConnectorStatus | null>(null)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  const apply = async () => {
    if (!pending) return
    setBusy(true)
    const res = await props.setStatus(feed.id, pending)
    setBusy(false)
    if (res.success) {
      setPending(null)
      setErr(null)
    } else setErr(connectorErrorKey(res.error))
  }

  return (
    <Section title={feed.name}>
      <div className="flex flex-wrap items-center gap-3 text-sm">
        <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_STYLE[feed.status]}`}>
          {t(`cl.connectors.status.${feed.status}`)}
        </span>
        <span className="text-gray-700">
          {t('cl.connectors.calendar')}: {feed.emit_days.map((d) => days[d - 1]).join(' ')} · {hourLabel(feed.emit_hour)} ·{' '}
          {feed.emit_timezone ?? t('cl.connectors.account_timezone')}
        </span>
        {feed.extraction_model && (
          <span className="text-gray-500">
            {t('cl.connectors.extraction_model')}: {feed.extraction_model}
          </span>
        )}
        <span className="text-gray-500">
          {t('cl.connectors.last_batch')}: {fmtDate(feed.last_batch_at)}
        </span>
        {!readOnly && (
          <div className="flex gap-2 ms-auto">
            <button type="button" title={t('common.edit')} onClick={props.onEdit} className="text-blue-600 hover:text-blue-800">
              <Pencil className="w-4 h-4" />
            </button>
            <button type="button" title={t('common.delete')} onClick={props.onDelete} className="text-red-600 hover:text-red-800">
              <Trash2 className="w-4 h-4" />
            </button>
          </div>
        )}
      </div>
      {feed.last_error && <p className="text-sm text-red-600">{t('cl.connectors.last_error')}: {feed.last_error}</p>}
      {feed.status === 'testing' && <p className="text-sm text-amber-800">{t('cl.connectors.testing_hint')}</p>}
      {!props.mappingOk && <p className="text-sm text-amber-800">{t('cl.connectors.mapping_incomplete')}</p>}

      {!readOnly && (
        <div className="flex flex-wrap gap-2">
          {CONNECTOR_STATUSES.filter((s) => s !== feed.status).map((s) => (
            <button key={s} type="button" className={btnSecondary} onClick={() => setPending(s)}>
              {t(`cl.connectors.set_status.${s}`)}
            </button>
          ))}
        </div>
      )}
      {pending && !readOnly && (
        <div className="border border-blue-200 bg-blue-50 rounded-lg p-3 space-y-2 text-sm">
          <p>{t(`cl.connectors.status_confirm.${pending}`)}</p>
          {err && <p className="text-red-600">{t(err)}</p>}
          <div className="flex gap-2">
            <button type="button" className={btnSecondary} onClick={() => setPending(null)}>
              {t('common.cancel')}
            </button>
            <button type="button" disabled={busy} className={btnPrimary} onClick={() => void apply()}>
              {t(`cl.connectors.set_status.${pending}`)}
            </button>
          </div>
        </div>
      )}
    </Section>
  )
}

/** Muestra el error traducido de una escritura y devuelve si fue bien. */
function useWriteState() {
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const exec = async (op: () => Promise<ClConnectorResult>) => {
    setBusy(true)
    setErr(null)
    const res = await op()
    setBusy(false)
    if (!res.success) setErr(connectorErrorKey(res.error))
    return res.success
  }
  return { busy, err, setErr, exec }
}

function FieldMappingsSection(props: { t: T; carrierId: string; feedId: string; cl: Cl; readOnly: boolean }) {
  const { t, carrierId, cl, readOnly } = props
  const { fields } = cl.mappings(props.feedId)
  const [draft, setDraft] = useState<Record<string, { carrier_field: string; format: string; timezone: string }>>({})
  const { busy, err, exec } = useWriteState()
  const check = validateFieldMappings(fields)

  const rowOf = (sf: StandardField) => {
    const saved = fields.find((m) => m.standard_field === sf)
    return (
      draft[sf] ?? {
        carrier_field: saved?.carrier_field ?? '',
        format: saved?.format ?? '',
        timezone: saved?.timezone ?? '',
      }
    )
  }
  const setRow = (sf: StandardField, k: 'carrier_field' | 'format' | 'timezone', v: string) =>
    setDraft((d) => ({ ...d, [sf]: { ...rowOf(sf), [k]: v } }))
  const clearDraft = (sf: StandardField) =>
    setDraft((d) => {
      const n = { ...d }
      delete n[sf]
      return n
    })

  const save = async (sf: StandardField) => {
    const r = rowOf(sf)
    if (!r.carrier_field.trim()) return
    if (await exec(() => cl.saveFieldMapping(carrierId, { standard_field: sf, ...r }))) clearDraft(sf)
  }
  const remove = async (sf: StandardField) => {
    const saved = fields.find((m) => m.standard_field === sf)
    if (saved && (await exec(() => cl.removeFieldMapping(saved.id)))) clearDraft(sf)
  }

  return (
    <Section title={t('cl.connectors.fields.title')} help={t('cl.connectors.fields.help')}>
      {!check.ok && check.missing.length > 0 && (
        <p className="text-sm text-amber-800">
          {t('cl.connectors.fields.missing', { fields: check.missing.map((f) => t(`cl.connectors.field.${f}`)).join(', ') })}
        </p>
      )}
      <div className="overflow-x-auto">
        <table className="min-w-full text-sm">
          <thead className="bg-gray-50 text-gray-600">
            <tr>
              <th className="text-start px-3 py-2">{t('cl.connectors.fields.standard')}</th>
              <th className="text-start px-3 py-2">{t('cl.connectors.fields.carrier_field')}</th>
              <th className="text-start px-3 py-2">{t('cl.connectors.fields.format')}</th>
              <th className="text-start px-3 py-2">{t('cl.connectors.fields.timezone')}</th>
              {!readOnly && <th />}
            </tr>
          </thead>
          <tbody>
            {STANDARD_FIELDS.map((sf) => {
              const r = rowOf(sf)
              const saved = fields.find((m) => m.standard_field === sf)
              const dirty = !!draft[sf]
              return (
                <tr key={sf} className="border-t border-gray-100">
                  <td className="px-3 py-2">
                    {t(`cl.connectors.field.${sf}`)}
                    {REQUIRED_STANDARD_FIELDS.includes(sf) && <span className="text-red-600"> *</span>}
                  </td>
                  <td className="px-3 py-2">
                    {readOnly ? (
                      r.carrier_field || '-'
                    ) : (
                      <input className={`${input} py-1`} value={r.carrier_field} onChange={(e) => setRow(sf, 'carrier_field', e.target.value)} />
                    )}
                  </td>
                  <td className="px-3 py-2">
                    {readOnly ? (
                      r.format || '-'
                    ) : (
                      <input className={`${input} py-1`} value={r.format} onChange={(e) => setRow(sf, 'format', e.target.value)} />
                    )}
                  </td>
                  <td className="px-3 py-2">
                    {readOnly ? (
                      r.timezone || '-'
                    ) : (
                      <input
                        className={`${input} py-1`}
                        value={r.timezone}
                        placeholder={t('cl.connectors.account_timezone')}
                        onChange={(e) => setRow(sf, 'timezone', e.target.value)}
                      />
                    )}
                  </td>
                  {!readOnly && (
                    <td className="px-3 py-2">
                      <div className="flex gap-2">
                        <button
                          type="button"
                          disabled={busy || !dirty || !r.carrier_field.trim()}
                          onClick={() => void save(sf)}
                          className="text-blue-600 hover:underline disabled:opacity-40"
                        >
                          {t('common.save')}
                        </button>
                        {saved && (
                          <button
                            type="button"
                            title={t('common.delete')}
                            disabled={busy}
                            onClick={() => void remove(sf)}
                            className="text-red-600 hover:text-red-800"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        )}
                      </div>
                    </td>
                  )}
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
      {err && <p className="text-sm text-red-600">{t(err)}</p>}
    </Section>
  )
}

function ValueMappingsSection(props: { t: T; carrierId: string; feedId: string; cl: Cl; readOnly: boolean }) {
  const { t, carrierId, cl, readOnly } = props
  const { values, products } = cl.mappings(props.feedId)
  const [carrierValue, setCarrierValue] = useState('')
  const [onemsValue, setOnemsValue] = useState('')
  const { busy, err, exec } = useWriteState()

  const productLabel = (code: string) => {
    const p = products.find((x) => x.code === code)
    return p ? `${p.code} - ${p.description}` : code
  }
  const add = async () => {
    if (!carrierValue.trim() || !onemsValue) return
    if (await exec(() => cl.saveValueMapping(carrierId, carrierValue, onemsValue))) {
      setCarrierValue('')
      setOnemsValue('')
    }
  }

  return (
    <Section title={t('cl.connectors.values.title')} help={t('cl.connectors.values.help')}>
      {values.length === 0 && <p className="text-sm text-gray-500">{t('cl.connectors.values.empty')}</p>}
      {values.length > 0 && (
        <table className="min-w-full text-sm">
          <thead className="bg-gray-50 text-gray-600">
            <tr>
              <th className="text-start px-3 py-2">{t('cl.connectors.values.carrier_value')}</th>
              <th className="text-start px-3 py-2">{t('cl.connectors.values.product')}</th>
              {!readOnly && <th />}
            </tr>
          </thead>
          <tbody>
            {values.map((v) => (
              <tr key={v.id} className="border-t border-gray-100">
                <td className="px-3 py-2">{v.carrier_value}</td>
                <td className="px-3 py-2">{productLabel(v.onems_value)}</td>
                {!readOnly && (
                  <td className="px-3 py-2 text-end">
                    <button
                      type="button"
                      title={t('common.delete')}
                      disabled={busy}
                      onClick={() => void exec(() => cl.removeValueMapping(v.id))}
                      className="text-red-600 hover:text-red-800"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {!readOnly && (
        <div className="flex flex-wrap items-end gap-2">
          <input
            className={input}
            value={carrierValue}
            placeholder={t('cl.connectors.values.carrier_value')}
            onChange={(e) => setCarrierValue(e.target.value)}
          />
          <select className={input} value={onemsValue} onChange={(e) => setOnemsValue(e.target.value)}>
            <option value="">{t('cl.connectors.values.select_product')}</option>
            {products.map((p) => (
              <option key={p.id} value={p.code}>
                {p.code} - {p.description}
              </option>
            ))}
          </select>
          <button type="button" disabled={busy || !carrierValue.trim() || !onemsValue} onClick={() => void add()} className={btnPrimary}>
            <Plus className="w-4 h-4" />
            {t('common.add')}
          </button>
        </div>
      )}
      {err && <p className="text-sm text-red-600">{t(err)}</p>}
    </Section>
  )
}

function ExtraFieldsSection(props: { t: T; carrierId: string; feedId: string; cl: Cl; readOnly: boolean }) {
  const { t, carrierId, cl, readOnly } = props
  const { extras } = cl.mappings(props.feedId)
  const [field, setField] = useState('')
  const { busy, err, exec } = useWriteState()

  const add = async () => {
    if (!field.trim()) return
    if (await exec(() => cl.saveExtraField(carrierId, field))) setField('')
  }

  return (
    <Section title={t('cl.connectors.extras.title')} help={t('cl.connectors.extras.help')}>
      {extras.length === 0 && <p className="text-sm text-gray-500">{t('cl.connectors.extras.empty')}</p>}
      <div className="flex flex-wrap gap-2">
        {extras.map((x) => (
          <span key={x.id} className="inline-flex items-center gap-1 px-2 py-1 rounded-full bg-gray-100 text-sm">
            {x.carrier_field}
            {!readOnly && (
              <button
                type="button"
                title={t('common.delete')}
                disabled={busy}
                onClick={() => void exec(() => cl.removeExtraField(x.id))}
                className="text-red-600 hover:text-red-800"
              >
                <Trash2 className="w-3 h-3" />
              </button>
            )}
          </span>
        ))}
      </div>
      {!readOnly && (
        <div className="flex flex-wrap items-end gap-2">
          <input
            className={input}
            value={field}
            placeholder={t('cl.connectors.extras.field')}
            onChange={(e) => setField(e.target.value)}
          />
          <button type="button" disabled={busy || !field.trim()} onClick={() => void add()} className={btnPrimary}>
            <Plus className="w-4 h-4" />
            {t('common.add')}
          </button>
        </div>
      )}
      {err && <p className="text-sm text-red-600">{t(err)}</p>}
    </Section>
  )
}

function KeysSection(props: { t: T; feedId: string; cl: Cl; canKeys: boolean }) {
  const { t, feedId, cl, canKeys } = props
  const keys = cl.keys(feedId)
  const [formOpen, setFormOpen] = useState(false)
  const [name, setName] = useState('')
  const [expires, setExpires] = useState('')
  const [issued, setIssued] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [deactivating, setDeactivating] = useState<string | null>(null)
  const issuedRef = useRef<HTMLInputElement>(null)

  const issue = async () => {
    if (!name.trim()) return setErr('onedb_api.key_name_required')
    if (name.trim().length > 80) return setErr('onedb_api.key_name_too_long')
    setBusy(true)
    setErr(null)
    try {
      // Caduca al final del día elegido (hora local).
      const expiresAt = expires ? new Date(`${expires}T23:59:59`).toISOString() : null
      const k = await cl.issueKey(feedId, name, expiresAt)
      setIssued(k.api_key)
      setFormOpen(false)
      setName('')
      setExpires('')
    } catch (e) {
      const ex = e as { message?: string; code?: string }
      setErr(ex.code === '22023' ? 'cl.connectors.keys.invalid' : connectorErrorKey(ex))
    } finally {
      setBusy(false)
    }
  }

  const copy = () => {
    if (!issued) return
    navigator.clipboard
      .writeText(issued)
      .then(() => {
        setCopied(true)
        setTimeout(() => setCopied(false), 2000)
      })
      .catch(() => issuedRef.current?.select())
  }

  const deactivate = async (id: string) => {
    setBusy(true)
    const res = await cl.deactivateKey(id)
    setBusy(false)
    if (res.success) {
      setDeactivating(null)
      setErr(null)
    } else setErr(connectorErrorKey(res.error))
  }

  return (
    <Section title={t('cl.connectors.keys.title')} help={t('cl.connectors.keys.help')}>
      {issued && (
        <div className="bg-green-50 border border-green-300 rounded-lg p-4 space-y-3">
          <p className="font-medium text-green-900">{t('onedb_api.new_key_title')}</p>
          <div className="flex gap-2">
            <input
              ref={issuedRef}
              type="text"
              value={issued}
              readOnly
              onFocus={(e) => e.currentTarget.select()}
              className="flex-1 px-4 py-2 border border-gray-300 rounded-lg bg-white font-mono text-sm"
            />
            <button type="button" onClick={copy} className="px-4 py-2 border border-gray-300 rounded-lg bg-white hover:bg-gray-50 flex items-center gap-2">
              {copied ? <CheckCircle className="w-4 h-4 text-green-600" /> : <Copy className="w-4 h-4" />}
              {copied ? t('onedb_api.copied') : t('onedb_api.copy')}
            </button>
          </div>
          <p className="text-sm text-green-900">{t('onedb_api.new_key_warning')}</p>
          <button type="button" onClick={() => setIssued(null)} className="px-4 py-2 bg-green-700 text-white rounded-lg hover:bg-green-800">
            {t('onedb_api.new_key_dismiss')}
          </button>
        </div>
      )}

      {canKeys && cl.keysError && <p className="text-sm text-red-600">{t(clErrorKey(cl.keysError))}</p>}
      {keys.length === 0 && !(canKeys && cl.keysError) && <p className="text-sm text-gray-500">{t('cl.connectors.keys.empty')}</p>}
      {keys.length > 0 && (
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-gray-50 text-gray-600">
              <tr>
                <th className="text-start px-3 py-2">{t('cl.connectors.keys.name')}</th>
                <th className="text-start px-3 py-2">{t('cl.connectors.keys.prefix')}</th>
                <th className="text-start px-3 py-2">{t('cl.connectors.keys.expires')}</th>
                <th className="text-start px-3 py-2">{t('cl.connectors.keys.last_used')}</th>
                <th className="text-start px-3 py-2">{t('common.status')}</th>
                {canKeys && <th />}
              </tr>
            </thead>
            <tbody>
              {keys.map((k) => (
                <tr key={k.id} className="border-t border-gray-100">
                  <td className="px-3 py-2">{k.name ?? '-'}</td>
                  <td className="px-3 py-2 font-mono">{k.key_prefix ? `${k.key_prefix}…` : '-'}</td>
                  <td className="px-3 py-2">{k.expires_at ? fmtDate(k.expires_at) : t('cl.connectors.keys.never')}</td>
                  <td className="px-3 py-2">{fmtDate(k.last_used_at)}</td>
                  <td className="px-3 py-2">{k.is_active ? t('common.active') : t('cl.connectors.keys.inactive')}</td>
                  {canKeys && (
                    <td className="px-3 py-2 text-end">
                      {k.is_active && deactivating !== k.id && (
                        <button
                          type="button"
                          title={t('onedb_api.deactivate_key')}
                          onClick={() => setDeactivating(k.id)}
                          className="text-red-600 hover:text-red-800"
                        >
                          <Ban className="w-4 h-4" />
                        </button>
                      )}
                      {deactivating === k.id && (
                        <span className="inline-flex gap-2 items-center">
                          <span>{t('cl.connectors.keys.deactivate_confirm')}</span>
                          <button type="button" className="text-gray-600 hover:underline" onClick={() => setDeactivating(null)}>
                            {t('common.cancel')}
                          </button>
                          <button type="button" disabled={busy} className="text-red-600 hover:underline" onClick={() => void deactivate(k.id)}>
                            {t('onedb_api.deactivate_key')}
                          </button>
                        </span>
                      )}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {canKeys && !formOpen && (
        <button
          type="button"
          className={btnPrimary}
          onClick={() => {
            setErr(null)
            setFormOpen(true)
          }}
        >
          <Plus className="w-4 h-4" />
          {t('cl.connectors.keys.new')}
        </button>
      )}
      {canKeys && formOpen && (
        <div className="border border-gray-200 rounded-lg p-3 flex flex-wrap items-end gap-3">
          <label className="text-sm">
            <span className="block mb-1">{t('onedb_api.key_name_label')}</span>
            <input className={input} value={name} maxLength={80} onChange={(e) => setName(e.target.value)} />
          </label>
          <label className="text-sm">
            <span className="block mb-1">{t('cl.connectors.keys.expires_optional')}</span>
            <input type="date" className={input} value={expires} onChange={(e) => setExpires(e.target.value)} />
          </label>
          <button type="button" className={btnSecondary} onClick={() => setFormOpen(false)}>
            {t('common.cancel')}
          </button>
          <button type="button" disabled={busy} className={btnPrimary} onClick={() => void issue()}>
            {t('cl.connectors.keys.issue')}
          </button>
        </div>
      )}
      {err && <p className="text-sm text-red-600">{t(err)}</p>}
    </Section>
  )
}

function DryRunSection(props: { t: T; feedId: string; cl: Cl }) {
  const { t, feedId, cl } = props
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [result, setResult] = useState<DryRunSummary | null>(null)
  const [fileName, setFileName] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)

  const onFile = async (file: File | undefined) => {
    if (!file) return
    setFileName(file.name)
    setErr(null)
    setResult(null)
    let payload: unknown
    try {
      payload = JSON.parse(await file.text())
    } catch {
      setErr('cl.connectors.dry_run.bad_json')
      return
    }
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
      setErr('cl.connectors.dry_run.bad_json')
      return
    }
    setBusy(true)
    try {
      const summary = parseDryRunResult(await cl.dryRun(feedId, payload))
      if (dryRunOutcome(summary) === 'unknown') setErr('cl.error.generic')
      else setResult(summary)
    } catch (e) {
      setErr(clErrorKey(e as { message?: string; code?: string }))
    } finally {
      setBusy(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  return (
    <Section title={t('cl.connectors.dry_run.title')} help={t('cl.connectors.dry_run.help')}>
      <div className="flex flex-wrap items-center gap-3">
        <input
          ref={fileRef}
          type="file"
          accept=".json,application/json"
          className="hidden"
          onChange={(e) => void onFile(e.target.files?.[0])}
        />
        <button type="button" disabled={busy} className={btnPrimary} onClick={() => fileRef.current?.click()}>
          <Upload className="w-4 h-4" />
          {busy ? t('cl.connectors.dry_run.running') : t('cl.connectors.dry_run.choose')}
        </button>
        {fileName && <span className="text-sm text-gray-600">{fileName}</span>}
      </div>
      {err && <p className="text-sm text-red-600">{t(err)}</p>}
      {result && <DryRunResultView t={t} result={result} />}
    </Section>
  )
}

/** Resultado de un ensayo (lo usan "Probar lote" y la vista previa de "Cargar lote"). */
function DryRunResultView(props: { t: T; result: DryRunSummary }) {
  const { t, result } = props
  const reasonList = (items: { reason: string; count: number }[]) =>
    items.length === 0 ? '-' : items.map((r) => `${t(`cl.reason.${r.reason}`, undefined, r.reason)}: ${r.count}`).join(', ')
  const n = (v: number | null) => (v === null ? '-' : v)
  return (
    <div className="space-y-2">
      {result.replayed && <p className="text-sm text-amber-700">{t('cl.connectors.dry_run.replayed')}</p>}
      <p className="text-sm font-medium">
        {dryRunOutcome(result) === 'accepted' ? t('cl.connectors.dry_run.validated') : t('cl.connectors.dry_run.rejected')}
      </p>
      {result.reason === 'selection_method' && (
        <p className="text-sm text-red-600">{t('cl.connectors.dry_run.bad_method', { expected: result.expected ?? '' })}</p>
      )}
      {dryRunOutcome(result) === 'accepted' && result.strata.length > 0 && (
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-gray-50 text-gray-600">
              <tr>
                <th className="text-start px-3 py-2">{t('cl.connectors.dry_run.stratum')}</th>
                <th className="text-start px-3 py-2">{t('cl.connectors.dry_run.rows')}</th>
                <th className="text-start px-3 py-2">{t('cl.connectors.dry_run.candidates')}</th>
                <th className="text-start px-3 py-2">{t('cl.connectors.dry_run.valid')}</th>
                <th className="text-start px-3 py-2">{t('cl.connectors.dry_run.rejected_by_reason')}</th>
                <th className="text-start px-3 py-2">{t('cl.connectors.dry_run.rows_rejected')}</th>
              </tr>
            </thead>
            <tbody>
              {result.strata.map((s, i) => (
                <tr key={`${s.stratum_id}-${i}`} className="border-t border-gray-100">
                  <td className="px-3 py-2 font-mono" title={s.stratum_id}>
                    {i + 1}. {s.stratum_id.slice(0, 8)}
                  </td>
                  <td className="px-3 py-2">{n(s.rows)}</td>
                  <td className="px-3 py-2">{n(s.candidates)}</td>
                  <td className="px-3 py-2">{n(s.candidates_valid)}</td>
                  <td className="px-3 py-2">{reasonList(s.rejected)}</td>
                  <td className="px-3 py-2">{reasonList(s.rows_rejected)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

type ManualPhase =
  | { step: 'idle' }
  | { step: 'checking' }
  | { step: 'preview'; payload: unknown; preview: DryRunSummary }
  | { step: 'running'; payload: unknown; done: number; total: number }
  | { step: 'result'; payload: unknown; outcome: ManualBatchOutcome }

const DEMAND_STATUSES = ['open', 'fulfilled', 'partial', 'failed']

/**
 * Carga manual de un lote real (carriers que mandan ficheros): fichero JSON → ensayo automático → confirmación en la
 * página → entrada, sorteo por estrato (con progreso) y cierre, igual que la API del conector.
 */
function ManualBatchSection(props: { t: T; feed: ClFeed; cl: Cl }) {
  const { t, feed, cl } = props
  const [phase, setPhase] = useState<ManualPhase>({ step: 'idle' })
  const [err, setErr] = useState<string | null>(null)
  const [fileName, setFileName] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)
  const allowed = canUploadManually(feed.status)
  const busy = phase.step === 'checking' || phase.step === 'running'
  const running = phase.step === 'running'

  // Mientras se carga, avisar antes de cerrar o recargar la pestaña (el lote quedaría a medio sortear).
  useEffect(() => {
    if (!running) return
    const onBeforeUnload = (e: BeforeUnloadEvent) => {
      e.preventDefault()
      e.returnValue = ''
    }
    window.addEventListener('beforeunload', onBeforeUnload)
    return () => window.removeEventListener('beforeunload', onBeforeUnload)
  }, [running])

  const onFile = async (file: File | undefined) => {
    if (!file) return
    setFileName(file.name)
    setErr(null)
    setPhase({ step: 'idle' })
    if (fileRef.current) fileRef.current.value = ''
    let payload: unknown
    try {
      payload = JSON.parse(await file.text())
    } catch {
      setErr('cl.connectors.dry_run.bad_json')
      return
    }
    const local = manualFileError(file.size, payload)
    if (local) {
      setErr(local)
      return
    }
    setPhase({ step: 'checking' })
    try {
      const preview = parseDryRunResult(await cl.dryRun(feed.id, payload))
      if (dryRunOutcome(preview) === 'unknown') {
        setErr('cl.error.generic')
        setPhase({ step: 'idle' })
      } else setPhase({ step: 'preview', payload, preview })
    } catch (e) {
      setErr(clErrorKey(e as { message?: string; code?: string }))
      setPhase({ step: 'idle' })
    }
  }

  const load = async (payload: unknown) => {
    setErr(null)
    setPhase({ step: 'running', payload, done: 0, total: 0 })
    try {
      const outcome = await runManualBatch(
        {
          ingest: (p) => cl.manualIngest(feed.id, p),
          sample: (b, s) => cl.manualSample(feed.id, b, s),
          finish: (b) => cl.manualFinish(feed.id, b),
        },
        payload,
        (done, total) => setPhase({ step: 'running', payload, done, total }),
      )
      setPhase({ step: 'result', payload, outcome })
    } catch (e) {
      setErr(clErrorKey(e as { message?: string; code?: string }))
      setPhase({ step: 'idle' })
    }
    void cl.refetch()
  }

  const cancel = () => {
    setPhase({ step: 'idle' })
    setFileName('')
    setErr(null)
  }

  const demandStatus = (s: string | null) =>
    s && DEMAND_STATUSES.includes(s) ? t(`cl.connectors.manual.demand_status.${s}`) : (s ?? '-')

  return (
    <Section title={t('cl.connectors.manual.title')} help={t('cl.connectors.manual.help')}>
      {!allowed && (
        <p className="text-sm text-amber-700">
          {feed.status === 'testing' ? t('cl.connectors.manual.only_active_testing') : t('cl.connectors.manual.only_active_paused')}
        </p>
      )}
      {allowed && (
        <div className="flex flex-wrap items-center gap-3">
          <input
            ref={fileRef}
            type="file"
            accept=".json,application/json"
            className="hidden"
            onChange={(e) => void onFile(e.target.files?.[0])}
          />
          <button
            type="button"
            disabled={busy || phase.step === 'preview'}
            className={btnPrimary}
            onClick={() => fileRef.current?.click()}
          >
            <Upload className="w-4 h-4" />
            {phase.step === 'checking' ? t('cl.connectors.dry_run.running') : t('cl.connectors.manual.choose')}
          </button>
          {fileName && <span className="text-sm text-gray-600">{fileName}</span>}
        </div>
      )}
      {err && <p className="text-sm text-red-600">{t(err)}</p>}

      {phase.step === 'preview' && (
        <div className="space-y-3">
          <DryRunResultView t={t} result={phase.preview} />
          {dryRunOutcome(phase.preview) === 'accepted' ? (
            <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 space-y-2">
              <p className="text-sm text-amber-900">{t('cl.connectors.manual.confirm_text')}</p>
              <div className="flex flex-wrap gap-2">
                <button type="button" className={btnSecondary} onClick={cancel}>
                  {t('common.cancel')}
                </button>
                <button type="button" className={btnPrimary} onClick={() => void load(phase.payload)}>
                  {t('cl.connectors.manual.confirm')}
                </button>
              </div>
            </div>
          ) : (
            <div className="flex flex-wrap items-center gap-2">
              <p className="text-sm text-red-600">{t('cl.connectors.manual.not_loadable')}</p>
              <button type="button" className={btnSecondary} onClick={cancel}>
                {t('common.close')}
              </button>
            </div>
          )}
        </div>
      )}

      {phase.step === 'running' && (
        <div className="space-y-1">
          <p className="text-sm text-amber-700">{t('cl.connectors.manual.do_not_leave')}</p>
          <p className="text-sm text-gray-700">
            {phase.total === 0
              ? t('cl.connectors.manual.ingesting')
              : t('cl.connectors.manual.sampling', { done: phase.done, total: phase.total })}
          </p>
          <div
            className="h-2 w-full rounded bg-gray-200 overflow-hidden"
            role="progressbar"
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={progressPercent(phase.done, phase.total)}
          >
            <div className="h-full bg-blue-600 transition-all" style={{ width: `${progressPercent(phase.done, phase.total)}%` }} />
          </div>
        </div>
      )}

      {phase.step === 'result' && (
        <ManualBatchResult
          t={t}
          outcome={phase.outcome}
          demandStatus={demandStatus}
          onRetry={() => void load(phase.payload)}
          onClose={cancel}
        />
      )}
    </Section>
  )
}

function ManualBatchResult(props: {
  t: T
  outcome: ManualBatchOutcome
  demandStatus: (s: string | null) => string
  onRetry: () => void
  onClose: () => void
}) {
  const { t, outcome, demandStatus, onRetry, onClose } = props
  const close = (
    <button type="button" className={btnSecondary} onClick={onClose}>
      {t('common.close')}
    </button>
  )

  if (outcome.kind === 'stored') {
    const msgKey = storedBatchMessageKey(outcome.ingest)
    const rejected = msgKey === 'cl.connectors.manual.rejected'
    return (
      <div className="space-y-2">
        <p className={`text-sm ${rejected ? 'text-red-600' : 'text-amber-700'}`}>
          {t(msgKey, { status: outcome.ingest.batchStatus ?? '-' })}
        </p>
        {rejected && outcome.ingest.summary.reason === 'selection_method' && (
          <p className="text-sm text-red-600">
            {t('cl.connectors.dry_run.bad_method', { expected: outcome.ingest.summary.expected ?? '' })}
          </p>
        )}
        {close}
      </div>
    )
  }

  const totals = samplingTotals(outcome.sampling)
  const rows = (
    <div className="overflow-x-auto">
      <table className="min-w-full text-sm">
        <thead className="bg-gray-50 text-gray-600">
          <tr>
            <th className="text-start px-3 py-2">{t('cl.connectors.dry_run.stratum')}</th>
            <th className="text-start px-3 py-2">{t('cl.connectors.manual.required')}</th>
            <th className="text-start px-3 py-2">{t('cl.connectors.manual.selected')}</th>
          </tr>
        </thead>
        <tbody>
          {outcome.sampling.map((s, i) => (
            <tr key={`${s.stratum_id}-${i}`} className="border-t border-gray-100">
              <td className="px-3 py-2 font-mono" title={s.stratum_id}>
                {i + 1}. {s.stratum_id.slice(0, 8)}
              </td>
              <td className="px-3 py-2">{s.samples_required ?? '-'}</td>
              <td className="px-3 py-2">{s.samples_selected ?? '-'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )

  if (outcome.kind === 'failed') {
    const { failed } = outcome
    const idx = failed.stratum_id === null ? 0 : outcome.ingest.strataIds.indexOf(failed.stratum_id) + 1
    return (
      <div className="space-y-2">
        <p className="text-sm text-red-600">
          {failed.stage === 'finish'
            ? t('cl.connectors.manual.failed_finish', { error: t(failed.errorKey) })
            : t('cl.connectors.manual.failed', { n: idx, total: outcome.ingest.strataIds.length, error: t(failed.errorKey) })}
        </p>
        <p className="text-sm text-gray-700">{t('cl.connectors.manual.failed_resume')}</p>
        {outcome.sampling.length > 0 && rows}
        <div className="flex flex-wrap gap-2">
          {close}
          <button type="button" className={btnPrimary} onClick={onRetry}>
            {t('cl.connectors.manual.retry')}
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-2">
      <p className="text-sm font-medium text-green-700">
        <CheckCircle className="inline w-4 h-4 me-1" />
        {t('cl.connectors.manual.done', { selected: totals.selected, required: totals.required })}
      </p>
      <p className="text-sm text-gray-700">
        {t('cl.connectors.manual.demand', { status: demandStatus(outcome.finish.demand_status) })}
      </p>
      {outcome.finish.status === 'pending' && (
        <p className="text-sm text-amber-700">
          {t('cl.connectors.manual.strata_pending', { count: outcome.finish.strata_pending.length })}
        </p>
      )}
      {rows}
      {close}
    </div>
  )
}
