import { useState } from 'react'
import { Button } from '@/components/common/Button'
import type { Carrier, Product, City, Node } from '@/lib/types'
import {
  generateAllocationPlan,
  autoFillMatrix,
  autoFillSeasonal,
  type CityDistributionMatrix,
  type SeasonalDistribution,
} from '@/lib/allocationPlanCalculator'

interface AllocationPlanGeneratorFormProps {
  carriers: Carrier[]
  products: Product[]
  cities: City[]
  nodes: Node[]
  onGenerate: (planData: any, details: any[]) => Promise<void>
}

export function AllocationPlanGeneratorForm({
  carriers,
  products,
  cities,
  nodes,
  onGenerate,
}: AllocationPlanGeneratorFormProps) {
  const [formData, setFormData] = useState({
    plan_name: '',
    carrier_id: '',
    product_id: '',
    total_samples: '',
    start_date: '',
    end_date: '',
  })

  const [matrix, setMatrix] = useState<Partial<CityDistributionMatrix>>({})
  const [useSeasonalDist, setUseSeasonalDist] = useState(false)
  const [seasonal, setSeasonal] = useState<Partial<SeasonalDistribution>>({})
  const [loading, setLoading] = useState(false)

  const availableProducts = products.filter(
    (p) => !formData.carrier_id || p.carrier_id === formData.carrier_id
  )

  const handleMatrixChange = (key: keyof CityDistributionMatrix, value: string) => {
    setMatrix({ ...matrix, [key]: value === '' ? undefined : parseFloat(value) })
  }

  const handleSeasonalChange = (month: keyof SeasonalDistribution, value: string) => {
    setSeasonal({ ...seasonal, [month]: value === '' ? undefined : parseFloat(value) })
  }

  const autoFillMatrixHandler = () => {
    const filled = autoFillMatrix(matrix)
    setMatrix(filled)
  }

  const autoFillSeasonalHandler = () => {
    const filled = autoFillSeasonal(seasonal)
    setSeasonal(filled)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)

    try {
      const filledMatrix = autoFillMatrix(matrix)
      const filledSeasonal = useSeasonalDist ? autoFillSeasonal(seasonal) : undefined

      const entries = generateAllocationPlan({
        totalSamples: parseInt(formData.total_samples),
        startDate: new Date(formData.start_date),
        endDate: new Date(formData.end_date),
        cities,
        nodes,
        cityDistributionMatrix: filledMatrix,
        useSeasonalDistribution: useSeasonalDist,
        seasonalDistribution: filledSeasonal,
        maxSamplesPerWeek: 5, // Default capacity
      })

      const planData = {
        plan_name: formData.plan_name,
        carrier_id: formData.carrier_id,
        product_id: formData.product_id,
        total_samples: parseInt(formData.total_samples),
        start_date: formData.start_date,
        end_date: formData.end_date,
      }

      const details = entries.map((entry) => ({
        origin_node_id: entry.originNodeId,
        destination_node_id: entry.destinationNodeId,
        fecha_programada: entry.fechaProgramada.toISOString().split('T')[0],
        week_number: entry.weekNumber,
        month: entry.month,
        year: entry.year,
        status: 'pending',
      }))

      await onGenerate(planData, details)

      // Reset form
      setFormData({
        plan_name: '',
        carrier_id: '',
        product_id: '',
        total_samples: '',
        start_date: '',
        end_date: '',
      })
      setMatrix({})
      setSeasonal({})
      setUseSeasonalDist(false)

      alert(`Plan generated successfully with ${details.length} samples!`)
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {/* Basic Info */}
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium mb-1">Plan Name *</label>
          <input
            type="text"
            required
            value={formData.plan_name}
            onChange={(e) => setFormData({ ...formData, plan_name: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Total Samples *</label>
          <input
            type="number"
            required
            min="1"
            value={formData.total_samples}
            onChange={(e) => setFormData({ ...formData, total_samples: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
          />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium mb-1">Carrier *</label>
          <select
            required
            value={formData.carrier_id}
            onChange={(e) => setFormData({ ...formData, carrier_id: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
          >
            <option value="">Select carrier</option>
            {carriers.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Product *</label>
          <select
            required
            value={formData.product_id}
            onChange={(e) => setFormData({ ...formData, product_id: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
          >
            <option value="">Select product</option>
            {availableProducts.map((p) => (
              <option key={p.id} value={p.id}>
                {p.description}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium mb-1">Start Date *</label>
          <input
            type="date"
            required
            value={formData.start_date}
            onChange={(e) => setFormData({ ...formData, start_date: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">End Date *</label>
          <input
            type="date"
            required
            value={formData.end_date}
            onChange={(e) => setFormData({ ...formData, end_date: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
          />
        </div>
      </div>

      {/* City Distribution Matrix */}
      <div className="border rounded-lg p-4">
        <div className="flex justify-between items-center mb-3">
          <h3 className="font-medium">City Distribution Matrix (A-B-C)</h3>
          <button type="button" onClick={autoFillMatrixHandler} className="text-sm text-blue-600">
            Auto-fill to 100%
          </button>
        </div>
        <div className="grid grid-cols-3 gap-3">
          {(['AA', 'AB', 'AC', 'BA', 'BB', 'BC', 'CA', 'CB', 'CC'] as const).map((key) => (
            <div key={key}>
              <label className="block text-xs mb-1">
                {key[0]} → {key[1]} (%)
              </label>
              <input
                type="number"
                step="0.01"
                min="0"
                max="100"
                value={matrix[key] ?? ''}
                onChange={(e) => handleMatrixChange(key, e.target.value)}
                className="w-full px-2 py-1 border rounded text-sm"
              />
            </div>
          ))}
        </div>
      </div>

      {/* Seasonal Distribution */}
      <div className="border rounded-lg p-4">
        <div className="flex justify-between items-center mb-3">
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={useSeasonalDist}
              onChange={(e) => setUseSeasonalDist(e.target.checked)}
            />
            <span className="font-medium">Use Seasonal Distribution</span>
          </label>
          {useSeasonalDist && (
            <button
              type="button"
              onClick={autoFillSeasonalHandler}
              className="text-sm text-blue-600"
            >
              Auto-fill to 100%
            </button>
          )}
        </div>

        {useSeasonalDist && (
          <div className="grid grid-cols-4 gap-3">
            {(
              [
                'jan',
                'feb',
                'mar',
                'apr',
                'may',
                'jun',
                'jul',
                'aug',
                'sep',
                'oct',
                'nov',
                'dec',
              ] as const
            ).map((month) => (
              <div key={month}>
                <label className="block text-xs mb-1 capitalize">{month} (%)</label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  max="100"
                  value={seasonal[month] ?? ''}
                  onChange={(e) => handleSeasonalChange(month, e.target.value)}
                  className="w-full px-2 py-1 border rounded text-sm"
                />
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="flex justify-end">
        <Button type="submit" disabled={loading}>
          {loading ? 'Generating...' : 'Generate Allocation Plan'}
        </Button>
      </div>
    </form>
  )
}
