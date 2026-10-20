import { useState, useEffect, useRef } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { fmtDay } from '@/lib/incidentFormat'
import { IncidentStatusBadge } from '@/components/incidents/IncidentStatusBadge'
import type { UnavailabilityHeader } from '@/lib/types'

// Motivo de la baja (panelist_unavailability.reason) -> clave i18n existente.
const UNAVAIL_REASON_KEY: Record<string, string> = {
  vacation: 'unavailability.reason_vacation',
  sick_leave: 'unavailability.reason_sick',
  sick: 'unavailability.reason_sick',
  personal: 'unavailability.reason_personal',
  training: 'unavailability.reason_training',
  materials: 'unavailability.reason_materials',
  other: 'unavailability.reason_other',
}

// Codigo que la BD escribe en final_resolution al cancelar la baja (la UI lo traduce).
const CANCELLED_CODE = 'unavailability_cancelled'

// auto_summary = 'shift=1;reroute=0;cancel=0;info=2;pending=1' -> solo los contadores > 0.
function parseSummary(s: string | null): { key: string; n: number }[] {
  if (!s) return []
  return s.split(';')
    .map(part => {
      const [k, v] = part.split('=')
      return { key: (k ?? '').trim(), n: Number(v) }
    })
    .filter(e => e.key && Number.isFinite(e.n) && e.n > 0)
}

// Separa el codigo de cancelacion (lineas que son exactamente el codigo) del texto libre.
function splitResolution(text: string | null): { cancelled: boolean; free: string } {
  if (!text) return { cancelled: false, free: '' }
  const lines = text.split('\n')
  const cancelled = lines.some(l => l.trim() === CANCELLED_CODE)
  const free = lines.filter(l => l.trim() !== CANCELLED_CODE).join('\n')
  return { cancelled, free }
}

interface Props {
  header: UnavailabilityHeader
  onSaveResolution: (text: string) => Promise<void>
}

export function IncidentHeader({ header, onSaveResolution }: Props) {
  const { t } = useTranslation()
  const { cancelled, free } = splitResolution(header.final_resolution)
  const [draft, setDraft] = useState(free)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)
  const savedTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Si la BD cambia el texto (p. ej. tras recargar), se refleja en el borrador.
  useEffect(() => { setDraft(free) }, [free])
  useEffect(() => () => { if (savedTimer.current) clearTimeout(savedTimer.current) }, [])

  const summary = parseSummary(header.auto_summary)

  const handleSave = async () => {
    if (saving) return
    setSaving(true); setSaveError(null); setSaved(false)
    try {
      // Se conserva el codigo de cancelacion para que la BD no lo vuelva a anadir.
      const body = draft.trim()
      const text = cancelled ? (body ? `${CANCELLED_CODE}\n${body}` : CANCELLED_CODE) : body
      await onSaveResolution(text)
      setSaved(true)
      if (savedTimer.current) clearTimeout(savedTimer.current)
      savedTimer.current = setTimeout(() => setSaved(false), 2500)
    } catch (err: any) {
      setSaveError(err?.message ?? String(err))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="bg-white rounded-lg shadow p-4 mb-6 space-y-4">
      <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
        <div>
          <div className="text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.panelist')}</div>
          <div className="text-sm font-medium">{header.panelist_name}</div>
          <div className="text-xs text-gray-500 font-mono">{header.panelist_code}</div>
        </div>
        <div>
          <div className="text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.node')}</div>
          <div className="text-sm">{header.node_code ?? '-'}{header.city_name ? ` · ${header.city_name}` : ''}</div>
        </div>
        <div>
          <div className="text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.dates')}</div>
          <div className="text-sm">{fmtDay(header.start_date)} – {fmtDay(header.end_date)}</div>
        </div>
        <div>
          <div className="text-xs font-medium text-gray-500 uppercase">{t('incidents.detail.cause')}</div>
          <div className="text-sm">
            {header.reason ? t(UNAVAIL_REASON_KEY[header.reason] ?? '', undefined, header.reason) : '-'}
          </div>
        </div>
        <div>
          <div className="text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.status')}</div>
          <div className="mt-1"><IncidentStatusBadge status={header.incident_status} /></div>
        </div>
      </div>

      <div>
        <div className="text-xs font-medium text-gray-500 uppercase">{t('incidents.detail.summary')}</div>
        <div className="text-sm text-gray-800">
          {summary.length > 0
            ? summary.map(e => t('incidents.summary.' + e.key, { n: e.n }, `${e.key}=${e.n}`)).join(' · ')
            : t('incidents.summary.none')}
        </div>
      </div>

      <div>
        <label htmlFor="incident-final-resolution" className="block text-xs font-medium text-gray-500 uppercase mb-1">
          {t('incidents.detail.final_resolution')}
        </label>
        {cancelled && (
          <div className="text-sm text-gray-700 mb-1">{t('incidents.resolution.unavailability_cancelled')}</div>
        )}
        <textarea
          id="incident-final-resolution"
          value={draft}
          onChange={e => { setDraft(e.target.value); setSaved(false) }}
          placeholder={t('incidents.detail.final_resolution_placeholder')}
          rows={3}
          className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm"
        />
        <div className="mt-2 flex items-center gap-3">
          <button
            type="button"
            onClick={handleSave}
            disabled={saving || draft === free}
            className="bg-blue-600 text-white px-4 py-1.5 rounded-lg text-sm hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {saving ? t('common.loading') : t('incidents.detail.save')}
          </button>
          {saved && <span className="text-sm text-green-700" role="status">{t('incidents.detail.saved')}</span>}
          {saveError && <span className="text-sm text-red-600" role="alert">{t('common.error')}: {saveError}</span>}
        </div>
      </div>
    </div>
  )
}
