import { useState, useEffect } from 'react'
import { X, Send, Trash2, AlertTriangle, Package } from 'lucide-react'
import type { MaterialShipment } from '../../hooks/useStockManagement'

interface ConfirmShipmentModalProps {
  shipment: MaterialShipment
  regulatorStocks: any[]
  onClose: () => void
  onConfirm: (shipmentId: string, confirmedItems: ConfirmedItem[], sentDate: string) => Promise<void>
}

export interface ConfirmedItem {
  id: string
  material_id: string
  quantity_sent: number
}

interface EditableItem {
  id: string
  material_id: string
  material_code: string
  material_name: string
  unit_measure: string
  quantity_sent: number
  stock_available: number
  removed: boolean
}

export default function ConfirmShipmentModal({
  shipment,
  regulatorStocks,
  onClose,
  onConfirm
}: ConfirmShipmentModalProps) {
  const [sentDate, setSentDate] = useState(
    shipment.expected_date || new Date().toISOString().split('T')[0]
  )
  const [items, setItems] = useState<EditableItem[]>([])
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    // Initialize items with stock info
    const editableItems: EditableItem[] = (shipment.items || []).map(item => {
      const stock = regulatorStocks.find(s => s.material_id === item.material_id)
      return {
        id: item.id,
        material_id: item.material_id,
        material_code: item.material?.code || 'Unknown',
        material_name: item.material?.name || 'Unknown Material',
        unit_measure: item.material?.unit_measure || 'units',
        quantity_sent: item.quantity_sent,
        stock_available: stock?.quantity || 0,
        removed: false
      }
    })
    setItems(editableItems)
  }, [shipment, regulatorStocks])

  const handleQuantityChange = (itemId: string, newQuantity: number) => {
    setItems(items.map(item =>
      item.id === itemId ? { ...item, quantity_sent: newQuantity } : item
    ))
  }

  const handleRemoveItem = (itemId: string) => {
    setItems(items.map(item =>
      item.id === itemId ? { ...item, removed: true } : item
    ))
  }

  const handleRestoreItem = (itemId: string) => {
    setItems(items.map(item =>
      item.id === itemId ? { ...item, removed: false } : item
    ))
  }

  const activeItems = items.filter(item => !item.removed)
  const removedItems = items.filter(item => item.removed)

  const hasStockIssues = activeItems.some(item => item.quantity_sent > item.stock_available)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (activeItems.length === 0) {
      alert('At least one material must remain in the shipment')
      return
    }

    if (activeItems.some(item => item.quantity_sent <= 0)) {
      alert('All quantities must be greater than 0')
      return
    }

    try {
      setSaving(true)
      const confirmedItems: ConfirmedItem[] = activeItems.map(item => ({
        id: item.id,
        material_id: item.material_id,
        quantity_sent: item.quantity_sent
      }))
      await onConfirm(shipment.id, confirmedItems, sentDate)
      onClose()
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center p-4 z-50">
      <div className="bg-white rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200">
          <div className="flex items-center gap-3">
            <Send className="h-6 w-6 text-blue-600" />
            <div>
              <h3 className="text-lg font-medium text-gray-900">Confirm Shipment</h3>
              <p className="text-sm text-gray-500">
                To: {shipment.panelist?.name || 'Unknown Panelist'}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-500"
            disabled={saving}
          >
            <X className="h-6 w-6" />
          </button>
        </div>

        {/* Content */}
        <form onSubmit={handleSubmit} className="flex flex-col flex-1 overflow-hidden">
          <div className="px-6 py-4 space-y-4 overflow-y-auto flex-1">
            {/* Sent Date */}
            <div>
              <label htmlFor="sentDate" className="block text-sm font-medium text-gray-700 mb-1">
                Sent Date
              </label>
              <input
                type="date"
                id="sentDate"
                value={sentDate}
                onChange={(e) => setSentDate(e.target.value)}
                className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                disabled={saving}
              />
            </div>

            {/* Stock Alert */}
            {hasStockIssues && (
              <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 flex items-start gap-3">
                <AlertTriangle className="h-5 w-5 text-yellow-600 flex-shrink-0 mt-0.5" />
                <div className="flex-1">
                  <h4 className="text-sm font-medium text-yellow-800">Stock Alert</h4>
                  <p className="text-sm text-yellow-700 mt-1">
                    Some materials have insufficient stock in the regulator. An inventory check is required.
                    The shipment will be registered with a stock incident note.
                  </p>
                </div>
              </div>
            )}

            {/* Active Items Table */}
            <div>
              <h4 className="text-sm font-medium text-gray-900 mb-2">Materials to Send</h4>
              <div className="border border-gray-200 rounded-lg overflow-hidden">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Material
                      </th>
                      <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Available Stock
                      </th>
                      <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Quantity to Send
                      </th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Actions
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {activeItems.map(item => {
                      const hasIssue = item.quantity_sent > item.stock_available
                      return (
                        <tr key={item.id} className={hasIssue ? 'bg-yellow-50' : ''}>
                          <td className="px-4 py-3">
                            <div className="text-sm font-medium text-gray-900">{item.material_code}</div>
                            <div className="text-sm text-gray-500">{item.material_name}</div>
                          </td>
                          <td className="px-4 py-3">
                            <div className={`text-sm ${hasIssue ? 'text-yellow-700 font-medium' : 'text-gray-900'}`}>
                              {item.stock_available.toLocaleString()} {item.unit_measure}
                              {hasIssue && (
                                <span className="ml-2 text-xs">⚠️ Insufficient</span>
                              )}
                            </div>
                          </td>
                          <td className="px-4 py-3">
                            <input
                              type="number"
                              min="1"
                              step="1"
                              value={item.quantity_sent}
                              onChange={(e) => handleQuantityChange(item.id, parseInt(e.target.value) || 0)}
                              className="block w-32 border border-gray-300 rounded-md shadow-sm py-1 px-2 text-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                              disabled={saving}
                            />
                          </td>
                          <td className="px-4 py-3 text-right">
                            <button
                              type="button"
                              onClick={() => handleRemoveItem(item.id)}
                              className="inline-flex items-center px-2 py-1 text-xs font-medium text-red-700 bg-red-100 hover:bg-red-200 rounded"
                              disabled={saving || activeItems.length === 1}
                              title={activeItems.length === 1 ? 'Cannot remove last item' : 'Remove from shipment'}
                            >
                              <Trash2 className="h-3 w-3 mr-1" />
                              Remove
                            </button>
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Removed Items */}
            {removedItems.length > 0 && (
              <div>
                <h4 className="text-sm font-medium text-gray-900 mb-2">Removed Materials (Will Create New Pending Shipment)</h4>
                <div className="border border-gray-200 rounded-lg overflow-hidden bg-gray-50">
                  <table className="min-w-full divide-y divide-gray-200">
                    <thead className="bg-gray-100">
                      <tr>
                        <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                          Material
                        </th>
                        <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                          Quantity
                        </th>
                        <th className="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                          Actions
                        </th>
                      </tr>
                    </thead>
                    <tbody className="bg-gray-50 divide-y divide-gray-200">
                      {removedItems.map(item => (
                        <tr key={item.id}>
                          <td className="px-4 py-2">
                            <div className="text-sm text-gray-700">{item.material_code}</div>
                            <div className="text-xs text-gray-500">{item.material_name}</div>
                          </td>
                          <td className="px-4 py-2">
                            <div className="text-sm text-gray-700">
                              {item.quantity_sent.toLocaleString()} {item.unit_measure}
                            </div>
                          </td>
                          <td className="px-4 py-2 text-right">
                            <button
                              type="button"
                              onClick={() => handleRestoreItem(item.id)}
                              className="inline-flex items-center px-2 py-1 text-xs font-medium text-blue-700 bg-blue-100 hover:bg-blue-200 rounded"
                              disabled={saving}
                            >
                              <Package className="h-3 w-3 mr-1" />
                              Restore
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="px-6 py-4 bg-gray-50 border-t border-gray-200 flex items-center justify-end gap-3">
            <button
              type="button"
              onClick={onClose}
              disabled={saving}
              className="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:bg-gray-100"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={saving || activeItems.length === 0}
              className="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:bg-gray-300"
            >
              <Send className="h-4 w-4 mr-2" />
              {saving ? 'Sending...' : 'Confirm Send'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
