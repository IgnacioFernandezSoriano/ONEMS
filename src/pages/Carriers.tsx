import { useCarriers } from '@/hooks/useCarriers'
import { CarriersTree } from '@/components/carriers/CarriersTree'

export function Carriers() {
  const {
    carriers,
    products,
    loading,
    error,
    createCarrier,
    updateCarrier,
    deleteCarrier,
    createProduct,
    updateProduct,
    deleteProduct,
  } = useCarriers()

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading carriers...</div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-red-500">Error: {error}</div>
      </div>
    )
  }

  const totalCarriers = carriers.length
  const totalProducts = products.length

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Carriers & Products</h1>
        <p className="text-gray-600 mt-1">Manage shipping carriers and their products</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="bg-white p-6 rounded-lg border">
          <div className="text-3xl font-bold text-blue-600">{totalCarriers}</div>
          <div className="text-sm text-gray-600 mt-1">Carriers</div>
        </div>
        <div className="bg-white p-6 rounded-lg border">
          <div className="text-3xl font-bold text-green-600">{totalProducts}</div>
          <div className="text-sm text-gray-600 mt-1">Products</div>
        </div>
      </div>

      {carriers.length === 0 ? (
        <div className="bg-white rounded-lg border p-12 text-center">
          <div className="text-4xl mb-4">🚚</div>
          <h3 className="text-lg font-medium text-gray-900 mb-2">No carriers defined yet</h3>
          <p className="text-gray-600 mb-6">
            Start by creating your first carrier to manage shipping products
          </p>
        </div>
      ) : null}

      <CarriersTree
        carriers={carriers}
        products={products}
        onCreateCarrier={createCarrier}
        onCreateProduct={createProduct}
        onUpdateCarrier={updateCarrier}
        onUpdateProduct={updateProduct}
        onDeleteCarrier={deleteCarrier}
        onDeleteProduct={deleteProduct}
      />
    </div>
  )
}
