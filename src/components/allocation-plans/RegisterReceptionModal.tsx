import { useState, useEffect } from 'react'
import type { AllocationPlanDetailWithRelations } from '@/lib/types'

interface Props {
  detail: AllocationPlanDetailWithRelations
  panelists: any[]
  onClose: () => void
  onRegister: (data: {
    received_at: string
    destination_panelist_id: string | null
    destination_panelist_name: string | null
  }) => Promise<void>
}

export function RegisterReceptionModal({ detail, panelists, onClose, onRegister }: Props) {
  const [receivedAt, setReceivedAt] = useState('')
  const [receivedByPanelistId, setReceivedByPanelistId] = useState('')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    // Set default values
    const now = new Date()
    const localDateTime = new Date(now.getTime() - now.getTimezoneOffset() * 60000)
      .toISOString()
      .slice(0, 16)
    setReceivedAt(localDateTime)

    // Find panelist assigned to destination node
    const destinationPanelist = panelists.find(p => p.node_id === detail.destination_node_id)
    if (destinationPanelist) {
      setReceivedByPanelistId(destinationPanelist.id)
    }
  }, [detail])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!receivedAt) {
      alert('Please select a date and time')
      return
    }

    if (!receivedByPanelistId) {
      alert('Please ensure destination panelist is assigned')
      return
    }

    try {
      setSaving(true)
      
      // Find the panelist assigned to destination node
      const destinationPanelist = panelists.find(p => p.node_id === detail.destination_node_id)
      
      await onRegister({
        received_at: new Date(receivedAt).toISOString(),
        destination_panelist_id: destinationPanelist?.id || null,
        destination_panelist_name: destinationPanelist?.name || null,
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
            <h3 className="text-lg font-medium text-gray-900">Register Reception</h3>
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
              <div className="grid grid-cols-2 gap-2 mb-2">
                <div>
                  <span className="text-gray-600">Origin:</span>
                  <p className="font-medium">{detail.origin_node?.auto_id || 'N/A'}</p>
                </div>
                <div>
                  <span className="text-gray-600">Destination:</span>
                  <p className="font-medium">{detail.destination_node?.auto_id || 'N/A'}</p>
                </div>
              </div>
              {detail.tag_id && (
                <div>
                  <span className="text-gray-600">Tag ID:</span>
                  <p className="font-medium">{detail.tag_id}</p>
                </div>
              )}
              {detail.sent_at && (
                <div>
                  <span className="text-gray-600">Sent at:</span>
                  <p className="font-medium">
                    {new Date(detail.sent_at).toLocaleString()}
                  </p>
                </div>
              )}
            </div>

            {/* Received Date/Time */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Received Date & Time <span className="text-red-500">*</span>
              </label>
              <input
                type="datetime-local"
                value={receivedAt}
                onChange={(e) => setReceivedAt(e.target.value)}
                className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                disabled={saving}
                required
              />
            </div>

            {/* Received By Panelist */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Registered By <span className="text-red-500">*</span>
              </label>
              <div className="text-sm text-gray-600 mb-2">
                {(() => {
                  const destinationPanelist = panelists.find(p => p.node_id === detail.destination_node_id)
                  return destinationPanelist ? (
                    <span>
                      {destinationPanelist.name} ({destinationPanelist.panelist_code})
                    </span>
                  ) : (
                    <span className="text-orange-600">No panelist assigned to destination node</span>
                  )
                })()}
              </div>
              <input
                type="text"
                value={receivedByPanelistId}
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
                disabled={saving || !receivedByPanelistId}
                className="flex-1 px-4 py-2 bg-green-600 text-white rounded-md text-sm font-medium hover:bg-green-700 disabled:bg-gray-300"
              >
                {saving ? 'Registering...' : 'Register Reception'}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  )
}
