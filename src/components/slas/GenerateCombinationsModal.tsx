import { useState, useMemo } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import type { GenerateCombinationsRequest } from '@/lib/types_slas'
import type { PostalCenter } from '@/lib/types_postal_centers'
import type { SLAWithDetails } from '@/lib/types_slas'
import type { Carrier, Product } from '@/lib/types'

interface GenerateCombinationsModalProps {
  postalCenters: PostalCenter[]
  carriers: Carrier[]
  products: Product[]
  existingSLAs: SLAWithDetails[]
  onGenerate: (request: GenerateCombinationsRequest & { 
    selectedCenters: string[]
    selectedRoutes: Array<{ from: string; to: string }>
    selectedCarriers: string[]
    selectedProducts: string[]
    generateOperational: boolean
    generateDistribution: boolean
  }) => Promise<{ inserted_count: number; skipped_count: number }>
  onClose: () => void
}

export function GenerateCombinationsModal({ 
  postalCenters,
  carriers,
  products,
  existingSLAs,
  onGenerate, 
  onClose 
}: GenerateCombinationsModalProps) {
  const { t } = useTranslation()
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<{ inserted_count: number; skipped_count: number } | null>(null)
  const [timeValue, setTimeValue] = useState<number>(1)
  const [timeUnit, setTimeUnit] = useState<'minutes' | 'hours' | 'days'>('days')
  const [formData, setFormData] = useState({
    on_time_percentage: 95,
    warning_threshold: 90,
    critical_threshold: 80,
  })
  
  const [generateOperational, setGenerateOperational] = useState(true)
  const [generateDistribution, setGenerateDistribution] = useState(true)
  const [selectedCenters, setSelectedCenters] = useState<Set<string>>(new Set())
  const [selectedRoutes, setSelectedRoutes] = useState<Set<string>>(new Set())
  const [selectedCarriers, setSelectedCarriers] = useState<Set<string>>(new Set(carriers.map(c => c.id)))
  const [selectedProducts, setSelectedProducts] = useState<Set<string>>(new Set(products.map(p => p.id)))

  // Calculate pending operational SLAs
  const pendingOperational = useMemo(() => {
    const existingOperationalCenters = new Set(
      existingSLAs
        .filter(sla => sla.sla_type === 'operational' && sla.postal_center_id)
        .map(sla => sla.postal_center_id!)
    )
    return postalCenters.filter(pc => !existingOperationalCenters.has(pc.id))
  }, [postalCenters, existingSLAs])

  // Calculate pending distribution SLAs
  const pendingDistribution = useMemo(() => {
    const existingRoutes = new Set(
      existingSLAs
        .filter(sla => sla.sla_type === 'distribution')
        .map(sla => `${sla.from_postal_center_id}->${sla.to_postal_center_id}`)
    )
    
    const pending: Array<{ from: PostalCenter; to: PostalCenter; key: string }> = []
    for (const fromCenter of postalCenters) {
      for (const toCenter of postalCenters) {
        if (fromCenter.id !== toCenter.id) {
          const key = `${fromCenter.id}->${toCenter.id}`
          if (!existingRoutes.has(key)) {
            pending.push({ from: fromCenter, to: toCenter, key })
          }
        }
      }
    }
    return pending
  }, [postalCenters, existingSLAs])

  const handleToggleCenter = (centerId: string) => {
    const newSelected = new Set(selectedCenters)
    if (newSelected.has(centerId)) {
      newSelected.delete(centerId)
    } else {
      newSelected.add(centerId)
    }
    setSelectedCenters(newSelected)
  }

  const handleToggleRoute = (routeKey: string) => {
    const newSelected = new Set(selectedRoutes)
    if (newSelected.has(routeKey)) {
      newSelected.delete(routeKey)
    } else {
      newSelected.add(routeKey)
    }
    setSelectedRoutes(newSelected)
  }

  const handleSelectAllCenters = () => {
    if (selectedCenters.size === pendingOperational.length) {
      setSelectedCenters(new Set())
    } else {
      setSelectedCenters(new Set(pendingOperational.map(pc => pc.id)))
    }
  }

  const handleSelectAllRoutes = () => {
    if (selectedRoutes.size === pendingDistribution.length) {
      setSelectedRoutes(new Set())
    } else {
      setSelectedRoutes(new Set(pendingDistribution.map(r => r.key)))
    }
  }

  const handleGenerate = async () => {
    setLoading(true)
    try {
      // Convert time to minutes
      let minutes = timeValue
      if (timeUnit === 'hours') {
        minutes = timeValue * 60
      } else if (timeUnit === 'days') {
        minutes = timeValue * 24 * 60
      }
      
      const routes = Array.from(selectedRoutes).map(key => {
        const [from, to] = key.split('->')
        return { from, to }
      })
      
      const res = await onGenerate({
        ...formData,
        expected_time_minutes: minutes,
        time_unit: 'minutes',
        selectedCenters: Array.from(selectedCenters),
        selectedRoutes: routes,
        selectedCarriers: Array.from(selectedCarriers),
        selectedProducts: Array.from(selectedProducts),
        generateOperational,
        generateDistribution,
      })
      // Close modal after successful generation
      onClose()
    } catch (error) {
      console.error('Error generating SLAs:', error)
      alert(error instanceof Error ? error.message : 'Error generating SLAs')
    } finally {
      setLoading(false)
    }
  }

  const totalToGenerate = 
    (generateOperational ? selectedCenters.size : 0) +
    (generateDistribution ? selectedRoutes.size : 0)

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg p-6 max-w-4xl w-full max-h-[90vh] overflow-y-auto">
        <h2 className="text-xl font-semibold mb-4">{t('slas.generate_pending_slas')}</h2>

        {!result ? (
          <>
            {/* Summary */}
            <div className="mb-6 p-4 bg-blue-50 rounded-lg">
              <h3 className="font-medium text-blue-900 mb-2">{t('slas.pending_slas_summary')}</h3>
              <div className="space-y-1 text-sm text-blue-800">
                <p>• {t('slas.pending_operational')}: <strong>{pendingOperational.length}</strong></p>
                <p>• {t('slas.pending_distribution')}: <strong>{pendingDistribution.length}</strong></p>
                <p className="pt-2 border-t border-blue-200">
                  • <strong>{t('slas.selected_to_generate')}: {totalToGenerate}</strong>
                </p>
              </div>
            </div>

            {/* SLA Type Selection */}
            <div className="mb-6 space-y-3">
              <h3 className="font-medium text-gray-900">{t('slas.select_sla_types')}</h3>
              <div className="flex gap-4">
                <label className="flex items-center">
                  <input
                    type="checkbox"
                    checked={generateOperational}
                    onChange={(e) => setGenerateOperational(e.target.checked)}
                    className="mr-2"
                  />
                  <span>{t('slas.operational')}</span>
                </label>
                <label className="flex items-center">
                  <input
                    type="checkbox"
                    checked={generateDistribution}
                    onChange={(e) => setGenerateDistribution(e.target.checked)}
                    className="mr-2"
                  />
                  <span>{t('slas.distribution')}</span>
                </label>
              </div>
            </div>

            {/* Carrier Selection */}
            <div className="mb-6">
              <div className="flex justify-between items-center mb-2">
                <h3 className="font-medium text-gray-900">Select Carriers</h3>
                <button
                  onClick={() => {
                    if (selectedCarriers.size === carriers.length) {
                      setSelectedCarriers(new Set())
                    } else {
                      setSelectedCarriers(new Set(carriers.map(c => c.id)))
                    }
                  }}
                  className="text-sm text-blue-600 hover:text-blue-800"
                >
                  {selectedCarriers.size === carriers.length ? t('common.deselect_all') : t('common.select_all')}
                </button>
              </div>
              <div className="max-h-32 overflow-y-auto border rounded p-2 space-y-1">
                {carriers.map(carrier => (
                  <label key={carrier.id} className="flex items-center hover:bg-gray-50 p-1 rounded">
                    <input
                      type="checkbox"
                      checked={selectedCarriers.has(carrier.id)}
                      onChange={() => {
                        const newSelected = new Set(selectedCarriers)
                        if (newSelected.has(carrier.id)) {
                          newSelected.delete(carrier.id)
                        } else {
                          newSelected.add(carrier.id)
                        }
                        setSelectedCarriers(newSelected)
                      }}
                      className="mr-2"
                    />
                    <span className="text-sm">{carrier.name}</span>
                  </label>
                ))}
              </div>
            </div>

            {/* Product Selection */}
            <div className="mb-6">
              <div className="flex justify-between items-center mb-2">
                <h3 className="font-medium text-gray-900">Select Products</h3>
                <button
                  onClick={() => {
                    if (selectedProducts.size === products.length) {
                      setSelectedProducts(new Set())
                    } else {
                      setSelectedProducts(new Set(products.map(p => p.id)))
                    }
                  }}
                  className="text-sm text-blue-600 hover:text-blue-800"
                >
                  {selectedProducts.size === products.length ? t('common.deselect_all') : t('common.select_all')}
                </button>
              </div>
              <div className="max-h-32 overflow-y-auto border rounded p-2 space-y-1">
                {products.map(product => (
                  <label key={product.id} className="flex items-center hover:bg-gray-50 p-1 rounded">
                    <input
                      type="checkbox"
                      checked={selectedProducts.has(product.id)}
                      onChange={() => {
                        const newSelected = new Set(selectedProducts)
                        if (newSelected.has(product.id)) {
                          newSelected.delete(product.id)
                        } else {
                          newSelected.add(product.id)
                        }
                        setSelectedProducts(newSelected)
                      }}
                      className="mr-2"
                    />
                    <span className="text-sm">{product.code} - {product.description}</span>
                  </label>
                ))}
              </div>
            </div>

            {/* Operational Centers Selection */}
            {generateOperational && pendingOperational.length > 0 && (
              <div className="mb-6">
                <div className="flex justify-between items-center mb-2">
                  <h3 className="font-medium text-gray-900">{t('slas.select_centers_for_operational')}</h3>
                  <button
                    onClick={handleSelectAllCenters}
                    className="text-sm text-blue-600 hover:text-blue-800"
                  >
                    {selectedCenters.size === pendingOperational.length 
                      ? t('common.deselect_all') 
                      : t('common.select_all')}
                  </button>
                </div>
                <div className="max-h-40 overflow-y-auto border rounded p-2 space-y-1">
                  {pendingOperational.map(center => (
                    <label key={center.id} className="flex items-center hover:bg-gray-50 p-1 rounded">
                      <input
                        type="checkbox"
                        checked={selectedCenters.has(center.id)}
                        onChange={() => handleToggleCenter(center.id)}
                        className="mr-2"
                      />
                      <span className="text-sm">{center.name} (Entry → Exit)</span>
                    </label>
                  ))}
                </div>
              </div>
            )}

            {/* Distribution Routes Selection */}
            {generateDistribution && pendingDistribution.length > 0 && (
              <div className="mb-6">
                <div className="flex justify-between items-center mb-2">
                  <h3 className="font-medium text-gray-900">{t('slas.select_routes_for_distribution')}</h3>
                  <button
                    onClick={handleSelectAllRoutes}
                    className="text-sm text-blue-600 hover:text-blue-800"
                  >
                    {selectedRoutes.size === pendingDistribution.length 
                      ? t('common.deselect_all') 
                      : t('common.select_all')}
                  </button>
                </div>
                <div className="max-h-60 overflow-y-auto border rounded p-2 space-y-1">
                  {pendingDistribution.map(route => (
                    <label key={route.key} className="flex items-center hover:bg-gray-50 p-1 rounded">
                      <input
                        type="checkbox"
                        checked={selectedRoutes.has(route.key)}
                        onChange={() => handleToggleRoute(route.key)}
                        className="mr-2"
                      />
                      <span className="text-sm">{route.from.name} → {route.to.name}</span>
                    </label>
                  ))}
                </div>
              </div>
            )}

            {/* Default Values Form */}
            <div className="space-y-4 mb-6">
              <h3 className="font-medium text-gray-900">{t('slas.default_values')}</h3>

              {/* Expected Time */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t('slas.expected_time')} *
                </label>
                <div className="flex gap-2">
                  <input
                    type="number"
                    min="0.001"
                    step="0.001"
                    value={timeValue}
                    onChange={(e) => setTimeValue(parseFloat(e.target.value))}
                    className="flex-1 px-3 py-2 border border-gray-300 rounded-md"
                  />
                  <select
                    value={timeUnit}
                    onChange={(e) => setTimeUnit(e.target.value as 'minutes' | 'hours' | 'days')}
                    className="px-3 py-2 border border-gray-300 rounded-md"
                  >
                    <option value="minutes">{t('common.minutes')}</option>
                    <option value="hours">{t('common.hours')}</option>
                    <option value="days">{t('common.days')}</option>
                  </select>
                </div>
              </div>

              {/* On-Time Percentage */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t('slas.on_time_percentage')} (%)
                </label>
                <input
                  type="number"
                  min="0"
                  max="100"
                  value={formData.on_time_percentage}
                  onChange={(e) => setFormData({ ...formData, on_time_percentage: parseInt(e.target.value) })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md"
                />
              </div>

              {/* Warning Threshold */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t('slas.warning_threshold')} (%)
                </label>
                <input
                  type="number"
                  min="0"
                  max="100"
                  value={formData.warning_threshold}
                  onChange={(e) => setFormData({ ...formData, warning_threshold: parseInt(e.target.value) })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md"
                />
              </div>

              {/* Critical Threshold */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t('slas.critical_threshold')} (%)
                </label>
                <input
                  type="number"
                  min="0"
                  max="100"
                  value={formData.critical_threshold}
                  onChange={(e) => setFormData({ ...formData, critical_threshold: parseInt(e.target.value) })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md"
                />
              </div>
            </div>

            {/* Actions */}
            <div className="flex justify-end gap-2 pt-4 border-t">
              <button
                onClick={onClose}
                className="px-4 py-2 text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
                disabled={loading}
              >
                {t('common.cancel')}
              </button>
              <button
                onClick={handleGenerate}
                className="px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50"
                disabled={loading || totalToGenerate === 0}
              >
                {loading ? t('common.generating') : t('slas.generate_selected_slas')}
              </button>
            </div>
          </>
        ) : (
          <>
            {/* Success Result */}
            <div className="mb-6 p-4 bg-green-50 rounded-lg">
              <h3 className="font-medium text-green-900 mb-2">✅ {t('common.success')}</h3>
              <div className="space-y-1 text-sm text-green-800">
                <p>• {t('slas.slas_created')}: <strong>{result.inserted_count}</strong></p>
                <p>• {t('slas.slas_skipped')}: <strong>{result.skipped_count}</strong> ({t('slas.already_exist')})</p>
              </div>
            </div>

            {/* Close Button */}
            <div className="flex justify-end">
              <button
                onClick={onClose}
                className="px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700"
              >
                {t('common.close')}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
