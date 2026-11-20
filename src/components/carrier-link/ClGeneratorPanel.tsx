import { Loader2 } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { QuotaMatrix } from '@/components/carrier-link/QuotaMatrix'
import { toQuotaInputs } from '@/lib/carrierLink/generatorCapture'
import { QUOTA_CSV_TEMPLATE, type QuotaCsvError } from '@/lib/carrierLink/quotaCsv'
import { downloadCSV } from '@/lib/csvExport'
import type { ClMessage, ClPreview } from '@/hooks/carrierLink/useClGeneratorFlow'

const btnPrimary = 'inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50'
const btnSecondary = 'inline-flex items-center gap-2 px-4 py-2 border border-gray-300 rounded-md hover:bg-gray-50 disabled:opacity-50'

/** Máximo de errores del CSV listados (el resto se resume). */
const ERROR_LIST_LIMIT = 20

interface Props {
  cityName: (id: string) => string
  preview: ClPreview | null
  message: ClMessage | null
  csvErrors: QuotaCsvError[]
  busy: boolean
  saving: boolean
  /** Puntos del carrier cargados: se puede importar. */
  canImport: boolean
  onImport: (file: File) => void
  onSave: () => void
  onDiscard: () => void
}

/** Parte de Carrier Link del Generador de Asignaciones: importar CSV de cuotas, vista previa y guardar. Va fuera del <form>. */
export function ClGeneratorPanel({ cityName, preview, message, csvErrors, busy, saving, canImport, onImport, onSave, onDiscard }: Props) {
  const { t } = useTranslation()

  const handleFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (file) onImport(file)
  }

  return (
    <div className="space-y-4 mt-6">
      <div className="border rounded-lg p-4 space-y-2">
        <h3 className="font-medium">{t('cl.generator.csv.title')}</h3>
        <p className="text-sm text-gray-600">{t('cl.generator.csv.help')}</p>
        <div className="flex flex-wrap gap-3 items-center">
          <label className={canImport ? 'cursor-pointer' : 'cursor-not-allowed opacity-50'}>
            <input type="file" accept=".csv" onChange={handleFile} disabled={!canImport} className="hidden" />
            <span className="inline-flex items-center px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700">
              {t('hc.csv_handler.import_csv')}
            </span>
          </label>
          <button type="button" className={btnSecondary} onClick={() => downloadCSV('carrier_link_quotas_template.csv', QUOTA_CSV_TEMPLATE)}>
            {t('hc.csv_handler.download_template')}
          </button>
        </div>
        {csvErrors.length > 0 && (
          <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-900 space-y-1">
            <p className="font-medium">{t('cl.generator.csv.errors_title', { count: csvErrors.length })}</p>
            <ul className="list-disc ps-5">
              {csvErrors.slice(0, ERROR_LIST_LIMIT).map((e, i) => (
                <li key={i}>{t(e.key, e.vars)}</li>
              ))}
            </ul>
            {csvErrors.length > ERROR_LIST_LIMIT && <p>{t('cl.generator.csv.more_errors', { count: csvErrors.length - ERROR_LIST_LIMIT })}</p>}
          </div>
        )}
      </div>

      {message && (
        <p className={`text-sm ${message.kind === 'error' ? 'text-red-600' : 'text-green-700'}`}>{t(message.key, message.vars)}</p>
      )}
      {busy && (
        <p className="text-sm text-gray-500 inline-flex items-center gap-2">
          <Loader2 className="w-4 h-4 animate-spin" />
          {t('common.loading')}
        </p>
      )}

      {preview && (
        <div className="border rounded-lg p-4 space-y-3">
          <div className="flex flex-wrap items-center gap-3">
            <h3 className="font-semibold text-gray-900">{t('cl.plans.preview_title')}</h3>
            <span className="text-sm text-gray-700">
              {t('cl.generator.requested_vs_generated', { requested: preview.requested, generated: preview.generated })}
            </span>
            <div className="flex-1" />
            <button type="button" onClick={onSave} disabled={saving} className={btnPrimary}>
              {saving && <Loader2 className="w-4 h-4 animate-spin" />}
              {saving ? t('cl.plans.saving_quotas', { count: preview.quotas.length }) : t('cl.generator.save_plan')}
            </button>
            <button type="button" onClick={onDiscard} disabled={saving} className={btnSecondary}>
              {t('cl.plans.discard')}
            </button>
          </div>
          {preview.generated < preview.requested && (
            <p className="text-sm text-amber-800">{t('cl.generator.generated_less', { missing: preview.requested - preview.generated })}</p>
          )}
          <QuotaMatrix quotas={toQuotaInputs(preview.quotas)} cityName={cityName} showObtained={false} noStandard={preview.noStandard} />
        </div>
      )}
    </div>
  )
}
