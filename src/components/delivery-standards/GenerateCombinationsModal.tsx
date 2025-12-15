import { useState } from 'react'
import { Modal } from '@/components/common/Modal'
import { Button } from '@/components/common/Button'
import type { Carrier, Product, City } from '@/lib/types'

interface GenerateCombinationsModalProps {
  isOpen: boolean
  onClose: () => void
  carriers: Carrier[]
  products: Product[]
  cities: City[]
  onGenerate: (
    carrierIds?: string[],
    productIds?: string[],
    originCityIds?: string[],
    destinationCityIds?: string[]
  ) => Promise<any>
}

export function GenerateCombinationsModal({
  isOpen,
  onClose,
  carriers,
  products,
  cities,
  onGenerate,
}: GenerateCombinationsModalProps) {
  const [selectedCarriers, setSelectedCarriers] = useState<string[]>([])
  const [selectedProducts, setSelectedProducts] = useState<string[]>([])
  const [selectedOriginCities, setSelectedOriginCities] = useState<string[]>([])
  const [selectedDestinationCities, setSelectedDestinationCities] = useState<string[]>([])
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<{ inserted_count: number; skipped_count: number } | null>(
    null
  )

  // Filter products by selected carriers (or all if none selected)
  const availableProducts = products.filter((p) =>
    selectedCarriers.length === 0 ? true : selectedCarriers.includes(p.carrier_id)
  )

  const handleGenerate = async () => {
    setLoading(true)
    try {
      const res = await onGenerate(
        selectedCarriers.length > 0 ? selectedCarriers : undefined,
        selectedProducts.length > 0 ? selectedProducts : undefined,
        selectedOriginCities.length > 0 ? selectedOriginCities : undefined,
        selectedDestinationCities.length > 0 ? selectedDestinationCities : undefined
      )
      setResult(res)
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    } finally {
      setLoading(false)
    }
  }

  const handleClose = () => {
    setSelectedCarriers([])
    setSelectedProducts([])
    setSelectedOriginCities([])
    setSelectedDestinationCities([])
    setResult(null)
    onClose()
  }

  const toggleCarrier = (id: string) => {
    const newCarriers = selectedCarriers.includes(id)
      ? selectedCarriers.filter((c) => c !== id)
      : [...selectedCarriers, id]
    setSelectedCarriers(newCarriers)

    // Remove products that don't belong to selected carriers
    if (newCarriers.length > 0) {
      setSelectedProducts((prev) =>
        prev.filter((pid) => {
          const product = products.find((p) => p.id === pid)
          return product && newCarriers.includes(product.carrier_id)
        })
      )
    }
  }

  const toggleProduct = (id: string) => {
    setSelectedProducts((prev) =>
      prev.includes(id) ? prev.filter((p) => p !== id) : [...prev, id]
    )
  }

  const toggleOriginCity = (id: string) => {
    setSelectedOriginCities((prev) =>
      prev.includes(id) ? prev.filter((c) => c !== id) : [...prev, id]
    )
  }

  const toggleDestinationCity = (id: string) => {
    setSelectedDestinationCities((prev) =>
      prev.includes(id) ? prev.filter((c) => c !== id) : [...prev, id]
    )
  }

  const selectAllCarriers = () => {
    if (selectedCarriers.length === carriers.length) {
      setSelectedCarriers([])
    } else {
      setSelectedCarriers(carriers.map((c) => c.id))
    }
  }

  const selectAllProducts = () => {
    if (selectedProducts.length === availableProducts.length) {
      setSelectedProducts([])
    } else {
      setSelectedProducts(availableProducts.map((p) => p.id))
    }
  }

  const selectAllOriginCities = () => {
    if (selectedOriginCities.length === cities.length) {
      setSelectedOriginCities([])
    } else {
      setSelectedOriginCities(cities.map((c) => c.id))
    }
  }

  const selectAllDestinationCities = () => {
    if (selectedDestinationCities.length === cities.length) {
      setSelectedDestinationCities([])
    } else {
      setSelectedDestinationCities(cities.map((c) => c.id))
    }
  }

  const clearAll = () => {
    setSelectedCarriers([])
    setSelectedProducts([])
    setSelectedOriginCities([])
    setSelectedDestinationCities([])
  }

  // Calculate estimated combinations
  const estimatedCombinations = (() => {
    const numCarriers = selectedCarriers.length || carriers.length
    const numProducts = selectedProducts.length || availableProducts.length
    const numOrigins = selectedOriginCities.length || cities.length
    const numDestinations = selectedDestinationCities.length || cities.length
    // Subtract same-city combinations (origin = destination)
    const validRoutes = numOrigins * numDestinations - Math.min(numOrigins, numDestinations)
    return numCarriers * numProducts * validRoutes
  })()

  if (result) {
    return (
      <Modal isOpen={isOpen} onClose={handleClose} title="Generation Complete">
        <div className="space-y-4">
          <div className="bg-green-50 border border-green-200 rounded-lg p-4">
            <div className="text-lg font-medium text-green-900 mb-2">✓ Success</div>
            <div className="space-y-1 text-sm text-green-800">
              <div>
                <strong>{result.inserted_count}</strong> new combinations created
              </div>
              <div>
                <strong>{result.skipped_count}</strong> combinations already existed
              </div>
            </div>
          </div>

          <div className="flex justify-end">
            <Button onClick={handleClose}>Close</Button>
          </div>
        </div>
      </Modal>
    )
  }

  return (
    <Modal isOpen={isOpen} onClose={handleClose} title="Generate Delivery Standards">
      <div className="space-y-6">
        {/* Info Banner */}
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-3 text-sm text-blue-800">
          ℹ️ <strong>Smart Generation:</strong> All fields are optional. Leave empty to use all
          available options. The system will generate combinations respecting carrier-product
          relationships.
        </div>

        {/* Estimated Combinations */}
        <div className="bg-gray-50 border border-gray-200 rounded-lg p-3">
          <div className="text-sm text-gray-600">Estimated combinations:</div>
          <div className="text-2xl font-bold text-gray-900">{estimatedCombinations}</div>
          <div className="text-xs text-gray-500 mt-1">
            {selectedCarriers.length || carriers.length} carriers ×{' '}
            {selectedProducts.length || availableProducts.length} products ×{' '}
            {selectedOriginCities.length || cities.length} origins ×{' '}
            {selectedDestinationCities.length || cities.length} destinations
          </div>
        </div>

        {/* Clear All Button */}
        <div className="flex justify-end">
          <button onClick={clearAll} className="text-sm text-gray-600 hover:text-gray-800">
            Clear All Selections
          </button>
        </div>

        {/* Carriers Selection */}
        <div>
          <div className="flex justify-between items-center mb-2">
            <label className="block text-sm font-medium text-gray-700">
              Carriers{' '}
              <span className="text-gray-500 font-normal">
                ({selectedCarriers.length > 0 ? selectedCarriers.length : 'all'} selected)
              </span>
            </label>
            <button
              onClick={selectAllCarriers}
              className="text-sm text-blue-600 hover:text-blue-800"
            >
              {selectedCarriers.length === carriers.length ? 'Deselect All' : 'Select All'}
            </button>
          </div>
          <div className="border rounded-md p-3 max-h-40 overflow-y-auto space-y-2">
            {carriers.map((carrier) => (
              <label key={carrier.id} className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={selectedCarriers.includes(carrier.id)}
                  onChange={() => toggleCarrier(carrier.id)}
                  className="rounded"
                />
                <span className="text-sm">
                  {carrier.name} ({carrier.code})
                </span>
              </label>
            ))}
          </div>
        </div>

        {/* Products Selection */}
        <div>
          <div className="flex justify-between items-center mb-2">
            <label className="block text-sm font-medium text-gray-700">
              Products{' '}
              <span className="text-gray-500 font-normal">
                ({selectedProducts.length > 0 ? selectedProducts.length : 'all'} selected)
              </span>
            </label>
            <button
              onClick={selectAllProducts}
              className="text-sm text-blue-600 hover:text-blue-800"
            >
              {selectedProducts.length === availableProducts.length ? 'Deselect All' : 'Select All'}
            </button>
          </div>
          <div className="border rounded-md p-3 max-h-40 overflow-y-auto space-y-2">
            {availableProducts.length === 0 ? (
              <div className="text-sm text-gray-500 italic">
                {selectedCarriers.length > 0
                  ? 'No products for selected carriers'
                  : 'No products available'}
              </div>
            ) : (
              availableProducts.map((product) => (
                <label key={product.id} className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={selectedProducts.includes(product.id)}
                    onChange={() => toggleProduct(product.id)}
                    className="rounded"
                  />
                  <span className="text-sm">
                    {product.description} ({product.code})
                  </span>
                </label>
              ))
            )}
          </div>
        </div>

        {/* Origin Cities Selection */}
        <div>
          <div className="flex justify-between items-center mb-2">
            <label className="block text-sm font-medium text-gray-700">
              Origin Cities{' '}
              <span className="text-gray-500 font-normal">
                ({selectedOriginCities.length > 0 ? selectedOriginCities.length : 'all'} selected)
              </span>
            </label>
            <button
              onClick={selectAllOriginCities}
              className="text-sm text-blue-600 hover:text-blue-800"
            >
              {selectedOriginCities.length === cities.length ? 'Deselect All' : 'Select All'}
            </button>
          </div>
          <div className="border rounded-md p-3 max-h-40 overflow-y-auto space-y-2">
            {cities.map((city) => (
              <label key={city.id} className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={selectedOriginCities.includes(city.id)}
                  onChange={() => toggleOriginCity(city.id)}
                  className="rounded"
                />
                <span className="text-sm">
                  {city.name} ({city.code})
                  {city.classification && (
                    <span className="ml-2 text-xs text-gray-500">Type {city.classification}</span>
                  )}
                </span>
              </label>
            ))}
          </div>
        </div>

        {/* Destination Cities Selection */}
        <div>
          <div className="flex justify-between items-center mb-2">
            <label className="block text-sm font-medium text-gray-700">
              Destination Cities{' '}
              <span className="text-gray-500 font-normal">
                (
                {selectedDestinationCities.length > 0
                  ? selectedDestinationCities.length
                  : 'all'}{' '}
                selected)
              </span>
            </label>
            <button
              onClick={selectAllDestinationCities}
              className="text-sm text-blue-600 hover:text-blue-800"
            >
              {selectedDestinationCities.length === cities.length ? 'Deselect All' : 'Select All'}
            </button>
          </div>
          <div className="border rounded-md p-3 max-h-40 overflow-y-auto space-y-2">
            {cities.map((city) => (
              <label key={city.id} className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={selectedDestinationCities.includes(city.id)}
                  onChange={() => toggleDestinationCity(city.id)}
                  className="rounded"
                />
                <span className="text-sm">
                  {city.name} ({city.code})
                  {city.classification && (
                    <span className="ml-2 text-xs text-gray-500">Type {city.classification}</span>
                  )}
                </span>
              </label>
            ))}
          </div>
        </div>

        {/* Actions */}
        <div className="flex gap-2 justify-end pt-4 border-t">
          <Button variant="secondary" onClick={handleClose}>
            Cancel
          </Button>
          <Button onClick={handleGenerate} disabled={loading}>
            {loading ? 'Generating...' : `Generate ${estimatedCombinations} Combinations`}
          </Button>
        </div>
      </div>
    </Modal>
  )
}
