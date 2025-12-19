import { useState, useMemo } from 'react'
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
  const [selectedYear, setSelectedYear] = useState(new Date().getFullYear())

  const availableProducts = products.filter(
    (p) => !formData.carrier_id || p.carrier_id === formData.carrier_id
  )

  const handleMatrixChange = (key: keyof CityDistributionMatrix, value: string) => {
    setMatrix({ ...matrix, [key]: value === '' ? undefined : parseInt(value, 10) })
  }

  const handleSeasonalChange = (month: keyof SeasonalDistribution, value: string) => {
    setSeasonal({ ...seasonal, [month]: value === '' ? undefined : parseInt(value, 10) })
  }

  const autoFillMatrixHandler = () => {
    const filled = autoFillMatrix(matrix)
    setMatrix(filled)
  }

  const clearMatrixHandler = () => {
    setMatrix({})
  }

  const autoFillSeasonalHandler = () => {
    const filled = autoFillSeasonal(seasonal)
    setSeasonal(filled)
  }

  const clearSeasonalHandler = () => {
    setSeasonal({})
  }

  // Quick period selection helpers
  const months = [
    { name: 'Jan', num: 1 }, { name: 'Feb', num: 2 }, { name: 'Mar', num: 3 },
    { name: 'Apr', num: 4 }, { name: 'May', num: 5 }, { name: 'Jun', num: 6 },
    { name: 'Jul', num: 7 }, { name: 'Aug', num: 8 }, { name: 'Sep', num: 9 },
    { name: 'Oct', num: 10 }, { name: 'Nov', num: 11 }, { name: 'Dec', num: 12 }
  ]

  const yearRange = useMemo(() => {
    const currentYear = new Date().getFullYear()
    const years = []
    for (let i = currentYear; i <= currentYear + 10; i++) {
      years.push(i)
    }
    return years
  }, [])

  const formatDateLocal = (date: Date) => {
    const y = date.getFullYear()
    const m = String(date.getMonth() + 1).padStart(2, '0')
    const d = String(date.getDate()).padStart(2, '0')
    return `${y}-${m}-${d}`
  }

  const handleMonthSelect = (year: number, month: number) => {
    const firstDay = new Date(year, month - 1, 1)
    const lastDay = new Date(year, month, 0)
    setFormData({
      ...formData,
      start_date: formatDateLocal(firstDay),
      end_date: formatDateLocal(lastDay)
    })
  }

  const handleFirstSemesterSelect = () => {
    const firstDay = new Date(selectedYear, 0, 1) // Jan 1
    const lastDay = new Date(selectedYear, 5, 30) // Jun 30
    setFormData({
      ...formData,
      start_date: formatDateLocal(firstDay),
      end_date: formatDateLocal(lastDay)
    })
  }

  const handleSecondSemesterSelect = () => {
    const firstDay = new Date(selectedYear, 6, 1) // Jul 1
    const lastDay = new Date(selectedYear, 11, 31) // Dec 31
    setFormData({
      ...formData,
      start_date: formatDateLocal(firstDay),
      end_date: formatDateLocal(lastDay)
    })
  }

  const handleYearSelect = () => {
    const firstDay = new Date(selectedYear, 0, 1) // Jan 1
    const lastDay = new Date(selectedYear, 11, 31) // Dec 31
    setFormData({
      ...formData,
      start_date: formatDateLocal(firstDay),
      end_date: formatDateLocal(lastDay)
    })
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
          <label className="flex items-center gap-1 text-sm font-medium mb-1">
            Plan Name *
            <span className="group relative">
              <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
              </svg>
              <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                Unique identifier for this allocation plan. Use descriptive names like "Q1_2025_Madrid_Express".
              </div>
            </span>
          </label>
          <input
            type="text"
            required
            value={formData.plan_name}
            onChange={(e) => setFormData({ ...formData, plan_name: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
          />
        </div>

        <div>
          <label className="flex items-center gap-1 text-sm font-medium mb-1">
            Total Samples *
            <span className="group relative">
              <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
              </svg>
              <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                Total number of samples to allocate across the date range. Will be distributed according to city and seasonal patterns.
              </div>
            </span>
          </label>
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
          <label className="flex items-center gap-1 text-sm font-medium mb-1">
            Carrier *
            <span className="group relative">
              <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
              </svg>
              <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                Logistics carrier for this allocation plan (e.g., DHL, FedEx). Determines available products.
              </div>
            </span>
          </label>
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
          <label className="flex items-center gap-1 text-sm font-medium mb-1">
            Product *
            <span className="group relative">
              <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
              </svg>
              <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                Carrier product/service type (e.g., Express, Standard). Filtered by selected carrier.
              </div>
            </span>
          </label>
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
          <label className="flex items-center gap-1 text-sm font-medium mb-1">
            Start Date *
            <span className="group relative">
              <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
              </svg>
              <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                First day of the allocation period. Samples will be scheduled from this date.
              </div>
            </span>
          </label>
          <input
            type="date"
            required
            value={formData.start_date}
            onChange={(e) => setFormData({ ...formData, start_date: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
          />
        </div>

        <div>
          <label className="flex items-center gap-1 text-sm font-medium mb-1">
            End Date *
            <span className="group relative">
              <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
              </svg>
              <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                Last day of the allocation period. Samples will be scheduled until this date.
              </div>
            </span>
          </label>
          <input
            type="date"
            required
            value={formData.end_date}
            onChange={(e) => setFormData({ ...formData, end_date: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
          />
        </div>
      </div>

      {/* Quick Period Selection */}
      <div className="border rounded-lg p-4 bg-gray-50">
        <label className="flex items-center gap-2 text-sm font-medium mb-3">
          Quick Period Selection
          <span className="group relative">
            <svg className="w-3 h-3 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
            </svg>
            <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
              Click any month button to automatically set the start and end dates for that entire month, or use semester/year buttons for longer periods.
            </div>
          </span>
        </label>
        <div className="flex items-center gap-2">
          <select
            value={selectedYear}
            onChange={(e) => setSelectedYear(parseInt(e.target.value))}
            className="border border-gray-300 rounded-md shadow-sm py-1 px-2 text-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
          >
            {yearRange.map(year => (
              <option key={year} value={year}>{year}</option>
            ))}
          </select>
          <div className="flex flex-wrap gap-1">
            {months.map(month => (
              <button
                key={month.num}
                type="button"
                onClick={() => handleMonthSelect(selectedYear, month.num)}
                className="px-3 py-1 text-sm font-medium rounded-md border border-gray-300 hover:bg-blue-50 hover:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                {month.name}
              </button>
            ))}
            <button
              type="button"
              onClick={handleFirstSemesterSelect}
              className="px-3 py-1 text-sm font-medium rounded-md border border-green-300 bg-green-50 hover:bg-green-100 hover:border-green-500 focus:outline-none focus:ring-2 focus:ring-green-500"
            >
              1st Semester
            </button>
            <button
              type="button"
              onClick={handleSecondSemesterSelect}
              className="px-3 py-1 text-sm font-medium rounded-md border border-teal-300 bg-teal-50 hover:bg-teal-100 hover:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500"
            >
              2nd Semester
            </button>
            <button
              type="button"
              onClick={handleYearSelect}
              className="px-3 py-1 text-sm font-medium rounded-md border border-purple-300 bg-purple-50 hover:bg-purple-100 hover:border-purple-500 focus:outline-none focus:ring-2 focus:ring-purple-500"
            >
              Year
            </button>
          </div>
        </div>
      </div>

      {/* City Distribution Matrix */}
      <div className="border rounded-lg p-4">
        <div className="flex justify-between items-center mb-3">
          <div className="flex items-center gap-2">
            <h3 className="font-medium">City Distribution Matrix (A-B-C)</h3>
            <span className="group relative">
              <svg className="w-4 h-4 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
              </svg>
              <div className="invisible group-hover:visible absolute z-10 w-80 p-3 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                <p className="font-semibold mb-1">City Distribution Matrix</p>
                <p className="mb-2">Defines the percentage of samples allocated between city classification pairs (A, B, C).</p>
                <p className="mb-1"><strong>Example:</strong></p>
                <p className="mb-1">• AA = 20% (Class A origin → Class A destination)</p>
                <p className="mb-1">• AB = 15% (Class A origin → Class B destination)</p>
                <p>Fill some cells manually, then click "Auto-fill to 100%" to distribute the remaining percentage equally across empty cells.</p>
              </div>
            </span>
          </div>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={clearMatrixHandler}
              className="px-3 py-1.5 text-sm font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-400 focus:ring-offset-2 transition-colors"
            >
              Clear
            </button>
            <button
              type="button"
              onClick={autoFillMatrixHandler}
              className="px-3 py-1.5 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
            >
              Auto-fill to 100%
            </button>
          </div>
        </div>
        <div className="grid grid-cols-3 gap-3">
          {(['AA', 'AB', 'AC', 'BA', 'BB', 'BC', 'CA', 'CB', 'CC'] as const).map((key) => (
            <div key={key}>
              <label className="block text-xs mb-1">
                {key[0]} → {key[1]} (%)
              </label>
              <input
                type="number"
                step="1"
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
            <div className="flex items-center gap-2">
              <span className="font-medium">Seasonal Distribution</span>
              <span className="group relative">
                <svg className="w-4 h-4 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                </svg>
                <div className="invisible group-hover:visible absolute z-10 w-80 p-3 bg-gray-900 text-white text-xs rounded shadow-lg -top-1 left-5 normal-case font-normal">
                  <p className="font-semibold mb-1">Seasonal Distribution</p>
                  <p className="mb-2">Optional: Distribute samples unevenly across months to reflect seasonal patterns.</p>
                  <p className="mb-1"><strong>Example:</strong></p>
                  <p className="mb-1">• December = 15% (high season)</p>
                  <p className="mb-1">• January = 5% (low season)</p>
                  <p>When disabled, samples are distributed evenly across all months. Fill some months manually, then click "Auto-fill to 100%" to distribute the remaining percentage.</p>
                </div>
              </span>
            </div>
          </label>
          {useSeasonalDist && (
            <div className="flex gap-2">
              <button
                type="button"
                onClick={clearSeasonalHandler}
                className="px-3 py-1.5 text-sm font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-400 focus:ring-offset-2 transition-colors"
              >
                Clear
              </button>
              <button
                type="button"
                onClick={autoFillSeasonalHandler}
                className="px-3 py-1.5 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
              >
                Auto-fill to 100%
              </button>
            </div>
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
                  step="1"
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
