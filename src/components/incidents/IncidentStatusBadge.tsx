import { useTranslation } from '@/hooks/useTranslation'
import type { IncidentStatus } from '@/lib/types'

const STATUS_CLASSES: Record<IncidentStatus, string> = {
  new: 'bg-gray-100 text-gray-800',
  auto_resolved: 'bg-green-100 text-green-800',
  pending_manager: 'bg-yellow-100 text-yellow-800',
  resolved: 'bg-blue-100 text-blue-800',
}

export function IncidentStatusBadge({ status }: { status: IncidentStatus }) {
  const { t } = useTranslation()
  return (
    <span className={`px-2 py-1 rounded text-xs font-medium ${STATUS_CLASSES[status] ?? STATUS_CLASSES.new}`}>
      {t('incidents.status.' + status)}
    </span>
  )
}
