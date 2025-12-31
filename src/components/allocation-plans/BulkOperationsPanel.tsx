import { useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'

interface Props {
  selectedCount: number
  selectedDetails: any[]
  nodes: any[]
  onBulkUpdateOriginNode: (nodeId: string) => Promise<void>
  onBulkUpdateDestinationNode: (nodeId: string) => Promise<void>
  onBulkUpdateDate: (date: string) => Promise<void>
  onBulkCancel: () => Promise<void>
  onBulkReprocess: () => Promise<void>
  onBulkDelete: () => Promise<void>
  onClearSelection: () => void
}

export function BulkOperationsPanel({
  selectedCount,
  selectedDetails,
  nodes,
  onBulkUpdateOriginNode,
  onBulkUpdateDestinationNode,
  onBulkUpdateDate,
  onBulkCancel,
  onBulkReprocess,
  onBulkDelete,
  onClearSelection,
}: Props) {
  const { t } = useTranslation()
  const [originNodeId, setOriginNodeId] = useState('')
  const [destinationNodeId, setDestinationNodeId] = useState('')
  const [date, setDate] = useState('')
  const [processing, setProcessing] = useState(false)

  if (selectedCount === 0) return null

  const handleBulkUpdateOriginNode = async () => {
    if (!originNodeId) {
      alert(t('bulk.please_select_origin_node'))
      return
    }
    try {
      setProcessing(true)
      await onBulkUpdateOriginNode(originNodeId)
      setOriginNodeId('')
      alert(t('bulk.updated_records').replace('{count}', String(selectedCount)))
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    } finally {
      setProcessing(false)
    }
  }

  const handleBulkUpdateDestinationNode = async () => {
    if (!destinationNodeId) {
      alert(t('bulk.please_select_destination_node'))
      return
    }
    try {
      setProcessing(true)
      await onBulkUpdateDestinationNode(destinationNodeId)
      setDestinationNodeId('')
      alert(t('bulk.updated_records').replace('{count}', String(selectedCount)))
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    } finally {
      setProcessing(false)
    }
  }

  const handleBulkUpdateDate = async () => {
    if (!date) {
      alert(t('bulk.please_select_date'))
      return
    }
    try {
      setProcessing(true)
      await onBulkUpdateDate(date)
      setDate('')
      alert(t('bulk.updated_records').replace('{count}', String(selectedCount)))
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    } finally {
      setProcessing(false)
    }
  }

  const handleBulkCancel = async () => {
    if (!confirm(t('bulk.confirm_cancel').replace('{count}', String(selectedCount)))) return
    try {
      setProcessing(true)
      await onBulkCancel()
      alert(t('bulk.cancelled_records').replace('{count}', String(selectedCount)))
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    } finally {
      setProcessing(false)
    }
  }

  const handleBulkReprocess = async () => {
    const errorCount = selectedDetails.filter(d => d.status === 'transfer_error').length
    if (!confirm(t('bulk.confirm_reprocess').replace('{count}', String(errorCount)))) {
      return
    }
    try {
      setProcessing(true)
      await onBulkReprocess()
      alert(t('bulk.reprocessed_records').replace('{count}', String(errorCount)))
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    } finally {
      setProcessing(false)
    }
  }

  const handleBulkDelete = async () => {
    if (!confirm(t('bulk.confirm_delete').replace('{count}', String(selectedCount)))) {
      return
    }
    try {
      setProcessing(true)
      await onBulkDelete()
      alert(t('bulk.deleted_records').replace('{count}', String(selectedCount)))
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    } finally {
      setProcessing(false)
    }
  }

  return (
    <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <span className="font-medium text-blue-900">{selectedCount} {t('bulk.selected')}</span>
          <button
            onClick={onClearSelection}
            className="text-sm text-blue-600 hover:text-blue-800"
          >
            Clear selection
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Update Origin Node */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Change Origin Node
          </label>
          <div className="flex gap-2">
            <select
              value={originNodeId}
              onChange={(e) => setOriginNodeId(e.target.value)}
              className="flex-1 border border-gray-300 rounded-md px-3 py-2 text-sm"
              disabled={processing}
            >
              <option value="">Select node...</option>
              {nodes.map((node) => (
                <option key={node.id} value={node.id}>
                  {node.auto_id}
                </option>
              ))}
            </select>
            <button
              onClick={handleBulkUpdateOriginNode}
              disabled={processing || !originNodeId}
              className="px-4 py-2 bg-blue-600 text-white rounded-md text-sm hover:bg-blue-700 disabled:bg-gray-300"
            >
              Apply
            </button>
          </div>
        </div>

        {/* Update Destination Node */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Change Destination Node
          </label>
          <div className="flex gap-2">
            <select
              value={destinationNodeId}
              onChange={(e) => setDestinationNodeId(e.target.value)}
              className="flex-1 border border-gray-300 rounded-md px-3 py-2 text-sm"
              disabled={processing}
            >
              <option value="">Select node...</option>
              {nodes.map((node) => (
                <option key={node.id} value={node.id}>
                  {node.auto_id}
                </option>
              ))}
            </select>
            <button
              onClick={handleBulkUpdateDestinationNode}
              disabled={processing || !destinationNodeId}
              className="px-4 py-2 bg-blue-600 text-white rounded-md text-sm hover:bg-blue-700 disabled:bg-gray-300"
            >
              Apply
            </button>
          </div>
        </div>

        {/* Update Date */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Change Scheduled Date
          </label>
          <div className="flex gap-2">
            <input
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              className="flex-1 border border-gray-300 rounded-md px-3 py-2 text-sm"
              disabled={processing}
            />
            <button
              onClick={handleBulkUpdateDate}
              disabled={processing || !date}
              className="px-4 py-2 bg-blue-600 text-white rounded-md text-sm hover:bg-blue-700 disabled:bg-gray-300"
            >
              Apply
            </button>
          </div>
        </div>

        {/* Cancel */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Cancel Selected
          </label>
          <button
            onClick={handleBulkCancel}
            disabled={processing}
            className="w-full px-4 py-2 bg-orange-600 text-white rounded-md text-sm hover:bg-orange-700 disabled:bg-gray-300"
          >
            Cancel {selectedCount} records
          </button>
        </div>

        {/* Reprocess Transfer Errors */}
        {selectedDetails.some(d => d.status === 'transfer_error') && (
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Reprocess Errors
            </label>
            <button
              onClick={handleBulkReprocess}
              disabled={processing}
              className="w-full px-4 py-2 bg-purple-600 text-white rounded-md text-sm hover:bg-purple-700 disabled:bg-gray-300"
            >
              Retry {selectedDetails.filter(d => d.status === 'transfer_error').length} errors
            </button>
          </div>
        )}

        {/* Delete */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Delete Selected
          </label>
          <button
            onClick={handleBulkDelete}
            disabled={processing}
            className="w-full px-4 py-2 bg-red-600 text-white rounded-md text-sm hover:bg-red-700 disabled:bg-gray-300"
          >
            Delete {selectedCount} records
          </button>
        </div>
      </div>
    </div>
  )
}
