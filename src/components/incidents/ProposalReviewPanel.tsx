import { useTranslation } from '@/hooks/useTranslation'

export function ProposalReviewPanel({ unavailabilityId, onBack }: { unavailabilityId: string; onBack: () => void }) {
  const { t } = useTranslation()
  return (
    <div>
      <button onClick={onBack} className="text-blue-600 hover:text-blue-800 mb-4">← {t('incidents.detail.back')}</button>
      <p className="text-gray-500">Detalle en construcción ({unavailabilityId}).</p>
    </div>
  )
}
