import { useState } from 'react'
import { Modal } from '@/components/common/Modal'
import { CarrierForm } from './CarrierForm'
import { ProductForm } from './ProductForm'
import type { Carrier, Product } from '@/lib/types'

interface CarriersTreeProps {
  carriers: Carrier[]
  products: Product[]
  onCreateCarrier: (data: any) => Promise<void>
  onCreateProduct: (data: any) => Promise<void>
  onUpdateCarrier: (id: string, data: any) => Promise<void>
  onUpdateProduct: (id: string, data: any) => Promise<void>
  onDeleteCarrier: (id: string) => Promise<void>
  onDeleteProduct: (id: string) => Promise<void>
}

export function CarriersTree({
  carriers,
  products,
  onCreateCarrier,
  onCreateProduct,
  onUpdateCarrier,
  onUpdateProduct,
  onDeleteCarrier,
  onDeleteProduct,
}: CarriersTreeProps) {
  const [expandedCarriers, setExpandedCarriers] = useState<Set<string>>(new Set())
  const [modal, setModal] = useState<any>(null)

  const toggleCarrier = (id: string) => {
    const newExpanded = new Set(expandedCarriers)
    if (newExpanded.has(id)) {
      newExpanded.delete(id)
    } else {
      newExpanded.add(id)
    }
    setExpandedCarriers(newExpanded)
  }

  const getProductsForCarrier = (carrierId: string) => {
    return products.filter((p) => p.carrier_id === carrierId)
  }

  const handleSubmit = async (data: any) => {
    try {
      await modal.onSubmit(data)
      setModal(null)
    } catch (error) {
      console.error('Error submitting:', error)
      throw error
    }
  }

  return (
    <>
      <div className="space-y-2">
        {carriers.map((carrier) => {
          const isExpanded = expandedCarriers.has(carrier.id)
          const carrierProducts = getProductsForCarrier(carrier.id)

          return (
            <div key={carrier.id} className="bg-white rounded-lg border">
              <div className="flex items-center gap-3 p-4 hover:bg-gray-50">
                <button
                  onClick={() => toggleCarrier(carrier.id)}
                  className="text-gray-500 hover:text-gray-700"
                >
                  {isExpanded ? '▼' : '▶'}
                </button>
                <span className="text-xl">🚚</span>
                <span className="font-medium flex-1">
                  {carrier.name} ({carrier.code})
                  {carrier.type && (
                    <span className="ml-2 text-xs bg-blue-100 text-blue-700 px-2 py-0.5 rounded">
                      {carrier.type}
                    </span>
                  )}
                </span>
                <span
                  className={`text-xs px-2 py-1 rounded ${
                    carrier.status === 'active'
                      ? 'bg-green-100 text-green-700'
                      : 'bg-gray-100 text-gray-700'
                  }`}
                >
                  {carrier.status}
                </span>
                <button
                  onClick={() =>
                    setModal({
                      type: 'carrier',
                      carrier: carrier,
                      onSubmit: (data: any) => onUpdateCarrier(carrier.id, data),
                    })
                  }
                  className="px-3 py-1 text-sm text-blue-600 hover:bg-blue-50 rounded"
                >
                  Edit
                </button>
                <button
                  onClick={() =>
                    setModal({
                      type: 'product',
                      carrierId: carrier.id,
                      onSubmit: onCreateProduct,
                    })
                  }
                  className="px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"
                >
                  + Product
                </button>
                <button
                  onClick={() => {
                    if (confirm('Delete this carrier and all its products?')) {
                      onDeleteCarrier(carrier.id)
                    }
                  }}
                  className="px-3 py-1 text-sm text-red-600 hover:bg-red-50 rounded"
                >
                  Delete
                </button>
              </div>

              {isExpanded && carrierProducts.length > 0 && (
                <div className="pl-12 pr-4 pb-4 space-y-1">
                  {carrierProducts.map((product) => (
                    <div
                      key={product.id}
                      className="flex items-center gap-2 p-2 hover:bg-gray-50 text-sm border-l-2 border-blue-200"
                    >
                      <span className="text-base">📦</span>
                      <div className="flex-1">
                        <div className="font-medium">{product.code}</div>
                        <div className="text-xs text-gray-600">{product.description}</div>
                        <div className="text-xs text-gray-500">
                          ⏱️ {product.standard_delivery_hours}h
                        </div>
                      </div>
                      <span
                        className={`text-xs px-2 py-1 rounded ${
                          product.status === 'active'
                            ? 'bg-green-100 text-green-700'
                            : 'bg-gray-100 text-gray-700'
                        }`}
                      >
                        {product.status}
                      </span>
                      <button
                        onClick={() =>
                          setModal({
                            type: 'product',
                            carrierId: product.carrier_id,
                            product: product,
                            onSubmit: (data: any) => onUpdateProduct(product.id, data),
                          })
                        }
                        className="px-2 py-1 text-xs text-blue-600 hover:bg-blue-50 rounded"
                      >
                        Edit
                      </button>
                      <button
                        onClick={() => {
                          if (confirm('Delete this product?')) {
                            onDeleteProduct(product.id)
                          }
                        }}
                        className="px-2 py-1 text-xs text-red-600 hover:bg-red-50 rounded"
                      >
                        Delete
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )
        })}

        <button
          onClick={() =>
            setModal({
              type: 'carrier',
              onSubmit: onCreateCarrier,
            })
          }
          className="w-full py-3 border-2 border-dashed border-gray-300 rounded-lg text-gray-600 hover:border-blue-500 hover:text-blue-600"
        >
          + Add Carrier
        </button>
      </div>

      {modal && (
        <Modal
          isOpen={true}
          onClose={() => setModal(null)}
          title={
            modal.type === 'carrier'
              ? modal.carrier
                ? 'Edit Carrier'
                : 'Create Carrier'
              : modal.product
              ? 'Edit Product'
              : 'Create Product'
          }
        >
          {modal.type === 'carrier' && (
            <CarrierForm
              carrier={modal.carrier}
              onSubmit={handleSubmit}
              onCancel={() => setModal(null)}
            />
          )}
          {modal.type === 'product' && (
            <ProductForm
              product={modal.product}
              carrierId={modal.carrierId}
              onSubmit={handleSubmit}
              onCancel={() => setModal(null)}
            />
          )}
        </Modal>
      )}
    </>
  )
}
