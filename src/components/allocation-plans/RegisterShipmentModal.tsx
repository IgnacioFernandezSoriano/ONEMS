import { useState, useEffect } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import type { AllocationPlanDetailWithRelations } from '@/lib/types'

interface Props {
  detail: AllocationPlanDetailWithRelations
  panelists: any[]
  onClose: () => void
  onRegister: (data: {
    tag_id: string
    sent_at: string
    origin_panelist_id: string | null
    origin_panelist_name: string | null
  }) => Promise<void>
}

export function RegisterShipmentModal({ detail, panelists, onClose, onRegister }: Props) {
  const { t } = useTranslation()
  const [tagId, setTagId] = useState('')
  const [sentAt, setSentAt] = useState('')
  const [sentByPanelistId, setSentByPanelistId] = useState('')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    // Set default values
    const now = new Date()
    const localDateTime = new Date(now.getTime() - now.getTimezoneOffset() * 60000)
      .toISOString()
      .slice(0, 16)
    setSentAt(localDateTime)

    // Find panelist assigned to origin node
    const originPanelist = panelists.find(p => p.node_id === detail.origin_node_id)
    if (originPanelist) {
      setSentByPanelistId(originPanelist.id)
    }
  }, [detail])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!tagId.trim()) {
      alert(t('allocation_plans.please_enter_tag_id'))
      return
    }

    if (!sentAt) {
      alert(t('allocation_plans.please_select_datetime'))
      return
    }

    if (!sentByPanelistId) {
      alert(t('allocation_plans.please_ensure_origin_panelist'))
      return
    }

    try {
      setSaving(true)
      
      // Find the panelist assigned to origin node
      const originPanelist = panelists.find(p => p.node_id === detail.origin_node_id)
      
      await onRegister({
        tag_id: tagId.trim(),
        sent_at: new Date(sentAt).toISOString(),
        origin_panelist_id: originPanelist?.id || null,
        origin_panelist_name: originPanelist?.name || null,
      })
      onClose()
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
        <div className="p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-medium text-gray-900">{t('allocation_plans.register_shipment')}</h3>
            <button
              onClick={onClose}
              className="text-gray-400 hover:text-gray-600"
              disabled={saving}
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Shipment Info */}
            <div className="bg-gray-50 p-3 rounded text-sm">
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <span className="text-gray-600">{t('allocation_plans.origin')}</span>
                  <p className="font-medium">{detail.origin_node?.auto_id || 'N/A'}</p>
                </div>
                <div>
                  <span className="text-gray-600">{t('allocation_plans.destination')}</span>
                  <p className="font-medium">{detail.destination_node?.auto_id || 'N/A'}</p>
                </div>
              </div>
            </div>

            {/* Tag ID */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Tag ID <span className="text-red-500">*</span>
              </label>
              <input
                type="text"
                value={tagId}
                onChange={(e) => setTagId(e.target.value)}
                placeholder="Enter tag ID"
                className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                disabled={saving}
                required
              />
            </div>

            {/* Sent Date/Time */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Sent Date & Time <span className="text-red-500">*</span>
              </label>
              <input
                type="datetime-local"
                value={sentAt}
                onChange={(e) => setSentAt(e.target.value)}
                className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                disabled={saving}
                required
              />
            </div>

            {/* Sent By Panelist */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Registered By <span className="text-red-500">*</span>
              </label>
              <div className="text-sm text-gray-600 mb-2">
                {(() => {
                  const originPanelist = panelists.find(p => p.node_id === detail.origin_node_id)
                  return originPanelist ? (
                    <span>
                      {originPanelist.name} ({originPanelist.panelist_code})
                    </span>
                  ) : (
                    <span className="text-orange-600">No panelist assigned to origin node</span>
                  )
                })()}
              </div>
              <input
                type="text"
                value={sentByPanelistId}
                readOnly
                className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm bg-gray-50"
                disabled
              />
            </div>

            {/* Actions */}
            <div className="flex gap-3 pt-4">
              <button
                type="button"
                onClick={onClose}
                disabled={saving}
                className="flex-1 px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:bg-gray-100"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={saving || !sentByPanelistId}
                className="flex-1 px-4 py-2 bg-blue-600 text-white rounded-md text-sm font-medium hover:bg-blue-700 disabled:bg-gray-300"
              >
                {saving ? 'Registering...' : 'Register Shipment'}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  )
}
