import { useState } from 'react'
import { Modal } from '@/components/common/Modal'
import { CarrierForm } from './CarrierForm'
import { ProductForm } from './ProductForm'
import { MaterialForm } from './MaterialForm'
import type { Carrier, Product, Material } from '@/lib/types'

interface CarriersTreeProps {
  carriers: Carrier[]
  products: Product[]
  materials: Material[]
  onCreateCarrier: (data: any) => Promise<void>
  onCreateProduct: (data: any) => Promise<void>
  onCreateMaterial: (data: any) => Promise<void>
  onUpdateCarrier: (id: string, data: any) => Promise<void>
  onUpdateProduct: (id: string, data: any) => Promise<void>
  onUpdateMaterial: (id: string, data: any) => Promise<void>
  onDeleteCarrier: (id: string) => Promise<void>
  onDeleteProduct: (id: string) => Promise<void>
  onDeleteMaterial: (id: string) => Promise<void>
}

export function CarriersTree({
  carriers,
  products,
  materials,
  onCreateCarrier,
  onCreateProduct,
  onCreateMaterial,
  onUpdateCarrier,
  onUpdateProduct,
  onUpdateMaterial,
  onDeleteCarrier,
  onDeleteProduct,
  onDeleteMaterial,
}: CarriersTreeProps) {
  const [expandedCarriers, setExpandedCarriers] = useState<Set<string>>(new Set())
  const [expandedProducts, setExpandedProducts] = useState<Set<string>>(new Set())
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

  const toggleProduct = (id: string) => {
    const newExpanded = new Set(expandedProducts)
    if (newExpanded.has(id)) {
      newExpanded.delete(id)
    } else {
      newExpanded.add(id)
    }
    setExpandedProducts(newExpanded)
  }

  const getProductsForCarrier = (carrierId: string) => {
    return products.filter((p) => p.carrier_id === carrierId)
  }

  const getMaterialsForProduct = (productId: string) => {
    return materials.filter((m) => m.product_id === productId)
  }

  const handleSubmit = async (data: any) => {
    try {
      await modal.onSubmit(data)
      setModal(null)
    } catch (error) {
      console.error('Error submitting:', error)
    }
  }

  const handleDelete = async (type: 'carrier' | 'product' | 'material', id: string, name: string) => {
    if (!confirm(`Are you sure you want to delete ${name}?`)) return
    
    try {
      if (type === 'carrier') await onDeleteCarrier(id)
      else if (type === 'product') await onDeleteProduct(id)
      else await onDeleteMaterial(id)
    } catch (error) {
      console.error('Error deleting:', error)
    }
  }

  return (
    <div className="bg-white rounded-lg border">
      <div className="p-6 space-y-2">
        {carriers.map((carrier) => {
          const carrierProducts = getProductsForCarrier(carrier.id)
          const isExpanded = expandedCarriers.has(carrier.id)

          return (
            <div key={carrier.id} className="border-l-2 border-red-300 pl-4">
              <div className="flex items-center gap-2 py-2">
                <button
                  onClick={() => toggleCarrier(carrier.id)}
                  className="text-gray-600 hover:text-gray-900"
                >
                  {isExpanded ? '▼' : '▶'}
                </button>
                <span className="text-xl">🚚</span>
                <span className="font-medium">{carrier.name}</span>
                <span className="text-sm text-gray-500">({carrier.code})</span>
                {carrier.type && (
                  <span className="text-xs bg-gray-100 px-2 py-1 rounded">{carrier.type}</span>
                )}
                <span
                  className={`text-xs px-2 py-1 rounded ${
                    carrier.status === 'active'
                      ? 'bg-green-100 text-green-800'
                      : 'bg-gray-100 text-gray-800'
                  }`}
                >
                  {carrier.status}
                </span>
                <div className="ml-auto flex gap-2">
                  <button
                    onClick={() =>
                      setModal({
                        title: 'Edit Carrier',
                        type: 'carrier',
                        data: carrier,
                        onSubmit: (data: any) => onUpdateCarrier(carrier.id, data),
                      })
                    }
                    className="text-sm text-blue-600 hover:text-blue-800"
                  >
                    Edit
                  </button>
                  <button
                    onClick={() =>
                      setModal({
                        title: 'Add Product',
                        type: 'product',
                        carrierId: carrier.id,
                        onSubmit: onCreateProduct,
                      })
                    }
                    className="text-sm bg-blue-600 text-white px-3 py-1 rounded hover:bg-blue-700"
                  >
                    + Product
                  </button>
                  <button
                    onClick={() => handleDelete('carrier', carrier.id, carrier.name)}
                    className="text-sm text-red-600 hover:text-red-800"
                  >
                    Delete
                  </button>
                </div>
              </div>

              {isExpanded && (
                <div className="ml-6 space-y-2 mt-2">
                  {carrierProducts.map((product) => {
                    const productMaterials = getMaterialsForProduct(product.id)
                    const isProductExpanded = expandedProducts.has(product.id)

                    return (
                      <div key={product.id} className="border-l-2 border-blue-300 pl-4">
                        <div className="flex items-center gap-2 py-2">
                          <button
                            onClick={() => toggleProduct(product.id)}
                            className="text-gray-600 hover:text-gray-900"
                          >
                            {isProductExpanded ? '▼' : '▶'}
                          </button>
                          <span className="text-lg">📦</span>
                          <span className="font-medium">{product.description}</span>
                          <span className="text-sm text-gray-500">({product.code})</span>
                          <span className="text-xs bg-blue-50 px-2 py-1 rounded">
                            {product.standard_delivery_hours}h
                          </span>
                          <span
                            className={`text-xs px-2 py-1 rounded ${
                              product.status === 'active'
                                ? 'bg-green-100 text-green-800'
                                : 'bg-gray-100 text-gray-800'
                            }`}
                          >
                            {product.status}
                          </span>
                          <div className="ml-auto flex gap-2">
                            <button
                              onClick={() =>
                                setModal({
                                  title: 'Edit Product',
                                  type: 'product',
                                  data: product,
                                  carrierId: carrier.id,
                                  onSubmit: (data: any) => onUpdateProduct(product.id, data),
                                })
                              }
                              className="text-sm text-blue-600 hover:text-blue-800"
                            >
                              Edit
                            </button>
                            <button
                              onClick={() =>
                                setModal({
                                  title: 'Add Material',
                                  type: 'material',
                                  productId: product.id,
                                  onSubmit: onCreateMaterial,
                                })
                              }
                              className="text-sm bg-green-600 text-white px-3 py-1 rounded hover:bg-green-700"
                            >
                              + Material
                            </button>
                            <button
                              onClick={() => handleDelete('product', product.id, product.description)}
                              className="text-sm text-red-600 hover:text-red-800"
                            >
                              Delete
                            </button>
                          </div>
                        </div>

                        {isProductExpanded && (
                          <div className="ml-6 space-y-1 mt-2">
                            {productMaterials.map((material) => (
                              <div
                                key={material.id}
                                className="flex items-center gap-2 py-1 text-sm border-l-2 border-green-300 pl-4"
                              >
                                <span className="text-base">📋</span>
                                <span className="font-medium">{material.name}</span>
                                <span className="text-gray-500">({material.code})</span>
                                <span className="text-xs bg-blue-50 text-blue-700 px-2 py-1 rounded font-medium">
                                  Qty: {material.quantity}
                                </span>
                                {material.unit_measure && (
                                  <span className="text-xs bg-gray-50 px-2 py-1 rounded">
                                    {material.unit_measure}
                                  </span>
                                )}
                                <span
                                  className={`text-xs px-2 py-1 rounded ${
                                    material.status === 'active'
                                      ? 'bg-green-100 text-green-800'
                                      : 'bg-gray-100 text-gray-800'
                                  }`}
                                >
                                  {material.status}
                                </span>
                                <div className="ml-auto flex gap-2">
                                  <button
                                    onClick={() =>
                                      setModal({
                                        title: 'Edit Material',
                                        type: 'material',
                                        data: material,
                                        productId: product.id,
                                        onSubmit: (data: any) => onUpdateMaterial(material.id, data),
                                      })
                                    }
                                    className="text-blue-600 hover:text-blue-800"
                                  >
                                    Edit
                                  </button>
                                  <button
                                    onClick={() => handleDelete('material', material.id, material.name)}
                                    className="text-red-600 hover:text-red-800"
                                  >
                                    Delete
                                  </button>
                                </div>
                              </div>
                            ))}
                          </div>
                        )}
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          )
        })}

        <button
          onClick={() =>
            setModal({
              title: 'Add Carrier',
              type: 'carrier',
              onSubmit: onCreateCarrier,
            })
          }
          className="w-full mt-4 py-2 border-2 border-dashed border-gray-300 rounded-lg text-gray-600 hover:border-gray-400 hover:text-gray-700"
        >
          + Add Carrier
        </button>
      </div>

      {modal && (
        <Modal
          isOpen={true}
          onClose={() => setModal(null)}
          title={modal.title}
        >
          {modal.type === 'carrier' && (
            <CarrierForm
              carrier={modal.data}
              onSubmit={handleSubmit}
              onCancel={() => setModal(null)}
            />
          )}
          {modal.type === 'product' && (
            <ProductForm
              product={modal.data}
              carrierId={modal.carrierId}
              onSubmit={handleSubmit}
              onCancel={() => setModal(null)}
            />
          )}
          {modal.type === 'material' && (
            <MaterialForm
              material={modal.data}
              productId={modal.productId}
              onSubmit={handleSubmit}
              onCancel={() => setModal(null)}
            />
          )}
        </Modal>
      )}
    </div>
  )
}
