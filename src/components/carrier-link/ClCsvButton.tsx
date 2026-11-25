import { useState } from 'react'
import { Download, Loader2 } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { CSV_MAX_ROWS, csvFileName, downloadCsv, type CsvTable } from '@/lib/carrierLink/clCsv'

/** Boton "Descargar CSV": construye la tabla entera (con los filtros de la pantalla) y la descarga. */
export function ClCsvButton(props: { label?: string; fileBase: string; build: () => Promise<CsvTable>; disabled?: boolean }) {
  const { t } = useTranslation()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(false)
  const [truncated, setTruncated] = useState(false)

  const run = async () => {
    setBusy(true)
    setError(false)
    setTruncated(false)
    try {
      const table = await props.build()
      downloadCsv(csvFileName(props.fileBase), table)
      setTruncated(table.truncated)
    } catch {
      setError(true)
    } finally {
      setBusy(false)
    }
  }

  return (
    <span className="inline-flex flex-wrap items-center gap-2">
      <button
        type="button"
        className="inline-flex items-center gap-1 px-3 py-1.5 text-sm border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50"
        disabled={busy || props.disabled}
        onClick={() => void run()}
      >
        {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Download className="w-4 h-4" />}
        {props.label ?? t('cl.csv.download')}
      </button>
      {error && <span className="text-xs text-red-700">{t('cl.csv.error')}</span>}
      {truncated && (
        <span className="text-xs text-amber-800">
          {t('cl.csv.truncated', { max: new Intl.NumberFormat().format(CSV_MAX_ROWS) })}
        </span>
      )}
    </span>
  )
}
