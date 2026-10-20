import { ProposalReviewPanel } from '@/components/incidents/ProposalReviewPanel'

interface Props {
  unavailabilityId: string
  onBack: () => void
}

// Envoltorio temporal: la Tarea 4 sustituye su cuerpo por el nuevo panel de detalle.
export function IncidentReviewPanel({ unavailabilityId, onBack }: Props) {
  return <ProposalReviewPanel unavailabilityId={unavailabilityId} onBack={onBack} />
}
