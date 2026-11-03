import { useState } from 'react'
import { X, Package } from 'lucide-react'
import type { MaterialShipmentItem } from '../../hooks/useStockManagement'
import { useTranslation } from '@/hooks/useTranslation'

interface EditShipmentItemModalProps {
  item: MaterialShipmentItem
  onClose: () => void
  onSave: (itemId: string, quantity: number) => Promise<void>
}

export default function EditShipmentItemModal({ item, onClose, onSave }: EditShipmentItemModalProps) {
  const { t } = useTranslation()
  const [quantity, setQuantity] = useState(item.quantity_sent)
  const [saving, setSaving] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    if (quantity <= 0) {
      alert(t('hc.edit_shipment_item_modal.qty_gt_zero'))
      return
    }

    try {
      setSaving(true)
      await onSave(item.id, quantity)
      onClose()
    } catch (error: any) {
      alert(t('hc.edit_shipment_item_modal.error', { message: error.message }))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center p-4 z-50">
      <div className="bg-white rounded-lg shadow-xl max-w-md w-full">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200">
          <div className="flex items-center gap-3">
            <Package className="h-6 w-6 text-blue-600" />
            <h3 className="text-lg font-medium text-gray-900">{t('hc.edit_shipment_item_modal.title')}</h3>
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
        <form onSubmit={handleSubmit}>
          <div className="px-6 py-4 space-y-4">
            {/* Material Info */}
            <div className="bg-gray-50 rounded-lg p-4">
              <div className="text-sm font-medium text-gray-900">
                {item.material?.code || t('hc.edit_shipment_item_modal.unknown_material')}
              </div>
              <div className="text-sm text-gray-500">
                {item.material?.name || t('hc.edit_shipment_item_modal.no_description')}
              </div>
              <div className="text-xs text-gray-500 mt-1">
                {t('hc.edit_shipment_item_modal.current_quantity', { quantity: item.quantity_sent.toLocaleString(), unit: item.material?.unit_measure || t('hc.edit_shipment_item_modal.units') })}
              </div>
            </div>

            {/* Quantity Input */}
            <div>
              <label htmlFor="quantity" className="block text-sm font-medium text-gray-700 mb-1">
                {t('hc.edit_shipment_item_modal.new_quantity')}
              </label>
              <div className="flex items-center gap-2">
                <input
                  type="number"
                  id="quantity"
                  min="1"
                  step="1"
                  value={quantity}
                  onChange={(e) => setQuantity(parseInt(e.target.value) || 0)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  autoFocus
                  disabled={saving}
                />
                <span className="text-sm text-gray-500 whitespace-nowrap">
                  {item.material?.unit_measure || t('hc.edit_shipment_item_modal.units')}
                </span>
              </div>
            </div>

            {/* Info */}
            <div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
              <p className="text-sm text-blue-700">
                {t('hc.edit_shipment_item_modal.info')}
              </p>
            </div>
          </div>

          {/* Footer */}
          <div className="px-6 py-4 bg-gray-50 border-t border-gray-200 flex items-center justify-end gap-3">
            <button
              type="button"
              onClick={onClose}
              disabled={saving}
              className="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:bg-gray-100"
            >
              {t('hc.edit_shipment_item_modal.cancel')}
            </button>
            <button
              type="submit"
              disabled={saving}
              className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:bg-gray-300"
            >
              {saving ? t('hc.edit_shipment_item_modal.saving') : t('hc.edit_shipment_item_modal.save_changes')}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
