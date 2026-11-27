import { useEffect, useMemo, useRef, useState } from 'react'
import { Plus, Pencil, Trash2, Copy, CheckCircle, Ban } from 'lucide-react'
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
import {
  useClConnectors,
  useClFeedCalendar,
  type ClFeed,
  type ClFeedForm,
  type ClConnectorResult,
} from '@/hooks/carrierLink/useClConnectors'
import { useClDeliveries, DELIVERIES_PAGE_SIZE } from '@/hooks/carrierLink/useClDeliveries'
import { ClDeliveriesTable, ClManualDeliveryUpload, ClPager, DeliveryStatusBadge } from '@/components/carrier-link/ClDeliveries'
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
  type ConnectorStatus,
  type StandardField,
} from '@/lib/carrierLink/connectorConfig'
import { GRACE_HOURS_MAX, deliveryFrequency, graceHoursOf, parseGraceHours, periodLabel } from '@/lib/carrierLink/deliveryView'

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
                saveGraceHours={cl.saveGraceHours}
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
              <DeliveriesSection key={`dl-${feed.id}`} t={t} feed={feed} cl={cl} accountId={accountId} readOnly={readOnly} />
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
  saveGraceHours: Cl['saveGraceHours']
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
      <DeliveryCalendar t={t} feed={feed} readOnly={readOnly} saveGraceHours={props.saveGraceHours} />
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

/**
 * Calendario de entregas: frecuencia (diaria ... semanal), proximo periodo a entregar (lo calcula la base) y margen de
 * "no recibido" antes de abrir una incidencia (editable con Edit).
 */
function DeliveryCalendar(props: { t: T; feed: ClFeed; readOnly: boolean; saveGraceHours: Cl['saveGraceHours'] }) {
  const { t, feed, readOnly } = props
  const { locale } = useTranslation()
  const { calendar, error } = useClFeedCalendar(feed.id, feed)
  const grace = graceHoursOf(feed.config)
  const [draft, setDraft] = useState<string | null>(null)
  const { busy, err, setErr, exec } = useWriteState()
  const frequency = calendar?.frequency ?? deliveryFrequency(feed.emit_days)

  const save = async () => {
    const h = parseGraceHours(draft ?? '')
    if (h === null) return setErr('cl.connectors.grace.invalid')
    if (await exec(() => props.saveGraceHours(feed.id, h))) setDraft(null)
  }

  return (
    <div className="rounded-lg bg-gray-50 border border-gray-200 p-3 space-y-1 text-sm">
      <p className="text-gray-800">
        <span className="font-medium">{t(`cl.connectors.frequency.${frequency}`)}</span>
        {frequency === 'several_per_week' && ` (${t('cl.connectors.per_week', { count: new Set(feed.emit_days).size })})`}
      </p>
      {error && <p className="text-red-600">{t(clErrorKey(error))}</p>}
      {calendar && (
        <>
          <p className="text-gray-700">
            {calendar.next_period
              ? t(calendar.next_period.deliverable ? 'cl.connectors.next_period_now' : 'cl.connectors.next_period', {
                  period: periodLabel(calendar.next_period.period_start, calendar.next_period.period_end, locale),
                  due: calendar.next_period.due_at ? new Date(calendar.next_period.due_at).toLocaleString() : '-',
                })
              : t('cl.connectors.no_next_period')}
          </p>
          {calendar.last_delivery && (
            <p className="text-gray-600 flex flex-wrap items-center gap-2">
              {t('cl.connectors.last_delivery', {
                period: periodLabel(calendar.last_delivery.period_start, calendar.last_delivery.period_end, locale),
              })}
              <DeliveryStatusBadge status={calendar.last_delivery.status} />
            </p>
          )}
        </>
      )}
      <div className="flex flex-wrap items-center gap-2 text-gray-700">
        <span>{t('cl.connectors.grace.label')}:</span>
        {readOnly || draft === null ? (
          <>
            <span className="font-medium">{t('cl.connectors.grace.hours', { count: grace })}</span>
            {!readOnly && (
              <button
                type="button"
                title={t('common.edit')}
                className="text-blue-600 hover:text-blue-800"
                onClick={() => {
                  setErr(null)
                  setDraft(String(grace))
                }}
              >
                <Pencil className="w-4 h-4" />
              </button>
            )}
          </>
        ) : (
          <>
            <input
              type="number"
              min={0}
              max={GRACE_HOURS_MAX}
              step={1}
              className={`${input} py-1 w-24`}
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
            />
            <button type="button" className="text-gray-600 hover:underline" onClick={() => setDraft(null)}>
              {t('common.cancel')}
            </button>
            <button type="button" disabled={busy} className="text-blue-600 hover:underline disabled:opacity-40" onClick={() => void save()}>
              {t('common.save')}
            </button>
          </>
        )}
      </div>
      <p className="text-xs text-gray-500">{t('cl.connectors.grace.help')}</p>
      {err && <p className="text-red-600">{t(err)}</p>}
    </div>
  )
}

/** Entregas del conector (paginadas en el servidor, con avance mientras se procesan) y subida manual (con Edit). */
function DeliveriesSection(props: { t: T; feed: ClFeed; cl: Cl; accountId: string | null; readOnly: boolean }) {
  const { t, feed, cl, accountId, readOnly } = props
  const [page, setPage] = useState(0)
  const filters = useMemo(() => ({ feedId: feed.id, status: null, from: null, to: null }), [feed.id])
  const deliveries = useClDeliveries(accountId, filters, page, 10_000)
  const [version, setVersion] = useState(0)
  const { calendar } = useClFeedCalendar(readOnly ? null : feed.id, version)

  return (
    <Section title={t('cl.deliveries.title')} help={t('cl.deliveries.help')}>
      {!readOnly && (
        <ClManualDeliveryUpload
          feedStatus={feed.status}
          defaultPeriod={calendar?.next_period ?? null}
          maxFileBytes={calendar?.max_file_bytes ?? null}
          api={(file) => cl.manualDeliveryApi(feed.id, file)}
          onDone={() => {
            setPage(0)
            setVersion((v) => v + 1)
            void deliveries.refetch()
          }}
        />
      )}
      {deliveries.error && <p className="text-sm text-red-600">{t(clErrorKey(deliveries.error))}</p>}
      <div className="bg-white border border-gray-200 rounded-lg">
        <ClDeliveriesTable rows={deliveries.rows} loading={deliveries.loading} />
        <ClPager page={page} total={deliveries.total} pageSize={DELIVERIES_PAGE_SIZE} loading={deliveries.loading} onPage={setPage} />
      </div>
    </Section>
  )
}
