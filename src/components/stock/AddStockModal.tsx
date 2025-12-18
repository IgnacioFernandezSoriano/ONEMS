import React, { useState } from 'react'
import { X, Package } from 'lucide-react'

interface AddStockModalProps {
  requirement: {
    id?: string
    material_id: string
    material_code: string
    material_name: string
    unit_measure: string
    quantity_needed: number
  }
  onConfirm: (materialId: string, quantity: number) => void
  onClose: () => void
}

export default function AddStockModal({ requirement, onConfirm, onClose }: AddStockModalProps) {
  const [quantity, setQuantity] = useState(requirement.quantity_needed)

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (quantity <= 0) {
      alert('Quantity must be greater than 0')
      return
    }
    onConfirm(requirement.material_id, quantity)
  }

  return (
    <div className="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center p-4 z-50">
      <div className="bg-white rounded-lg shadow-xl max-w-md w-full">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200">
          <div className="flex items-center gap-3">
            <Package className="h-6 w-6 text-blue-600" />
            <h3 className="text-lg font-medium text-gray-900">Add to Stock</h3>
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-500"
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
                {requirement.material_code}
              </div>
              <div className="text-sm text-gray-500">
                {requirement.material_name}
              </div>
            </div>

            {/* Quantity Input */}
            <div>
              <label htmlFor="quantity" className="block text-sm font-medium text-gray-700 mb-1">
                Quantity Received
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
                />
                <span className="text-sm text-gray-500 whitespace-nowrap">
                  {requirement.unit_measure}
                </span>
              </div>
              <p className="mt-1 text-xs text-gray-500">
                Suggested: {requirement.quantity_needed.toLocaleString()} {requirement.unit_measure} (from requirements)
              </p>
            </div>

            {/* Info */}
            <div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
              <p className="text-sm text-blue-700">
                This will add the specified quantity to the regulator's stock and create a receipt movement record.
              </p>
            </div>
          </div>

          {/* Footer */}
          <div className="px-6 py-4 bg-gray-50 border-t border-gray-200 flex items-center justify-end gap-3">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
            >
              Add to Stock
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
