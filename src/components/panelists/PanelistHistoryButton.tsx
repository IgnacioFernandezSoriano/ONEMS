import { useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { usePermissions } from '@/contexts/PermissionsContext'
import { PanelistHistoryDrawer } from './PanelistHistoryDrawer'

/** Botón «📋 Historial»: solo para quien puede ver Panelists (decisión de Ignacio 24/11). */
export function PanelistHistoryButton({ panelistId, className = '' }: { panelistId: string | null | undefined; className?: string }) {
  const { t } = useTranslation()
  const { canView } = usePermissions()
  const [open, setOpen] = useState(false)
  if (!panelistId || !canView('panelists')) return null
  return (
    <>
      <button type="button" onClick={e => { e.stopPropagation(); setOpen(true) }}
              className={`inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded border border-gray-300 text-gray-700 hover:bg-gray-50 ${className}`}>
        📋 {t('panelist_history.button')}
      </button>
      {open && <PanelistHistoryDrawer panelistId={panelistId} onClose={() => setOpen(false)} />}
    </>
  )
}
