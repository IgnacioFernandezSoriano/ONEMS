import { useState, useEffect } from 'react'
import { useAccount } from '../../contexts/AccountContext'
import { supabase } from '../../lib/supabase'
import { Filter, Map as MapIcon, List, Download } from 'lucide-react'
import RouteFlowMap from '../../components/diagnosis/RouteFlowMap'
import RoutePathTable from '../../components/diagnosis/RoutePathTable'

interface RoutePathData {
  id: string
  carrier_id: string
  carrier_name: string
  product_id: string
  product_name: string
  origin_city_name: string
  destination_city_name: string
  path_signature: string
  path_segments: any[]
  total_tags: number
  avg_natural_time_minutes: number
  avg_working_time_minutes: number
  compliance_rate: number
  segment_details: any[]
}

interface FilterState {
  carrier_id: string
  product_id: string
  origin_city: string
  destination_city: string
}

export default function RoutePathAnalysis() {
  const { currentAccount } = useAccount()
  const [viewMode, setViewMode] = useState<'map' | 'table'>('map')
  const [loading, setLoading] = useState(false)
  const [routePaths, setRoutePaths] = useState<RoutePathData[]>([])
  
  const [filters, setFilters] = useState<FilterState>({
    carrier_id: '',
    product_id: '',
    origin_city: '',
    destination_city: ''
  })

  const [carriers, setCarriers] = useState<any[]>([])
  const [products, setProducts] = useState<any[]>([])
  const [cities, setCities] = useState<string[]>([])

  // Load filter options
  useEffect(() => {
    loadFilterOptions()
  }, [currentAccount])

  // Load route paths when filters change
  useEffect(() => {
    if (filters.carrier_id && filters.product_id && filters.origin_city && filters.destination_city) {
      loadRoutePaths()
    }
  }, [filters])

  const loadFilterOptions = async () => {
    if (!currentAccount) return

    try {
      // Load carriers
      const { data: carriersData } = await supabase
        .from('carriers')
        .select('id, name')
        .eq('account_id', currentAccount.id)
        .order('name')

      if (carriersData) setCarriers(carriersData)

      // Load products
      const { data: productsData } = await supabase
        .from('products')
        .select('id, code, description')
        .eq('account_id', currentAccount.id)
        .order('code')

      if (productsData) setProducts(productsData)

      // Load unique cities from journey_paths
      const { data: citiesData } = await supabase
        .from('journey_paths')
        .select('origin_city_name, destination_city_name')
        .eq('account_id', currentAccount.id)

      if (citiesData) {
        const uniqueCities = new Set<string>()
        citiesData.forEach(row => {
          if (row.origin_city_name) uniqueCities.add(row.origin_city_name)
          if (row.destination_city_name) uniqueCities.add(row.destination_city_name)
        })
        setCities(Array.from(uniqueCities).sort())
      }
    } catch (error) {
      console.error('Error loading filter options:', error)
    }
  }

  const loadRoutePaths = async () => {
    if (!currentAccount) return

    setLoading(true)
    try {
      const { data, error } = await supabase
        .from('journey_paths')
        .select(`
          id,
          carrier_id,
          product_id,
          origin_city_name,
          destination_city_name,
          path_signature,
          path_segments,
          total_tags,
          avg_natural_time_minutes,
          avg_working_time_minutes,
          compliance_rate,
          segment_details,
          carriers!inner(name),
          products!inner(code, description)
        `)
        .eq('account_id', currentAccount.id)
        .eq('carrier_id', filters.carrier_id)
        .eq('product_id', filters.product_id)
        .eq('origin_city_name', filters.origin_city)
        .eq('destination_city_name', filters.destination_city)
        .order('total_tags', { ascending: false })

      if (error) throw error

      const formattedData: RoutePathData[] = (data || []).map((row: any) => ({
        id: row.id,
        carrier_id: row.carrier_id,
        carrier_name: row.carriers?.name || '',
        product_id: row.product_id,
        product_name: `${row.products?.code} - ${row.products?.description}`,
        origin_city_name: row.origin_city_name,
        destination_city_name: row.destination_city_name,
        path_signature: row.path_signature,
        path_segments: row.path_segments || [],
        total_tags: row.total_tags,
        avg_natural_time_minutes: row.avg_natural_time_minutes,
        avg_working_time_minutes: row.avg_working_time_minutes,
        compliance_rate: row.compliance_rate,
        segment_details: row.segment_details || []
      }))

      setRoutePaths(formattedData)
    } catch (error) {
      console.error('Error loading route paths:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleExport = () => {
    // TODO: Implement CSV export
    console.log('Export route paths:', routePaths)
  }

  const totalTags = routePaths.reduce((sum, path) => sum + path.total_tags, 0)
  const avgCompliance = routePaths.length > 0
    ? routePaths.reduce((sum, path) => sum + path.compliance_rate * path.total_tags, 0) / totalTags
    : 0

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-bold text-gray-900">Route Path Analysis</h1>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setViewMode('map')}
            className={`px-4 py-2 rounded-lg flex items-center gap-2 ${
              viewMode === 'map'
                ? 'bg-blue-600 text-white'
                : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
            }`}
          >
            <MapIcon className="w-4 h-4" />
            Map View
          </button>
          <button
            onClick={() => setViewMode('table')}
            className={`px-4 py-2 rounded-lg flex items-center gap-2 ${
              viewMode === 'table'
                ? 'bg-blue-600 text-white'
                : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
            }`}
          >
            <List className="w-4 h-4" />
            Table View
          </button>
          <button
            onClick={handleExport}
            className="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 flex items-center gap-2"
          >
            <Download className="w-4 h-4" />
            Export
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center gap-2 mb-4">
          <Filter className="w-5 h-5 text-gray-600" />
          <h2 className="text-lg font-semibold text-gray-900">Filters</h2>
        </div>

        <div className="grid grid-cols-4 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Carrier
            </label>
            <select
              value={filters.carrier_id}
              onChange={(e) => setFilters({ ...filters, carrier_id: e.target.value })}
              className="w-full border border-gray-300 rounded-lg px-3 py-2"
            >
              <option value="">Select carrier...</option>
              {carriers.map(carrier => (
                <option key={carrier.id} value={carrier.id}>
                  {carrier.name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Product
            </label>
            <select
              value={filters.product_id}
              onChange={(e) => setFilters({ ...filters, product_id: e.target.value })}
              className="w-full border border-gray-300 rounded-lg px-3 py-2"
            >
              <option value="">Select product...</option>
              {products.map(product => (
                <option key={product.id} value={product.id}>
                  {product.code} - {product.description}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Origin City
            </label>
            <select
              value={filters.origin_city}
              onChange={(e) => setFilters({ ...filters, origin_city: e.target.value })}
              className="w-full border border-gray-300 rounded-lg px-3 py-2"
            >
              <option value="">Select origin...</option>
              {cities.map(city => (
                <option key={city} value={city}>
                  {city}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Destination City
            </label>
            <select
              value={filters.destination_city}
              onChange={(e) => setFilters({ ...filters, destination_city: e.target.value })}
              className="w-full border border-gray-300 rounded-lg px-3 py-2"
            >
              <option value="">Select destination...</option>
              {cities.map(city => (
                <option key={city} value={city}>
                  {city}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Summary Stats */}
      {routePaths.length > 0 && (
        <div className="grid grid-cols-4 gap-4">
          <div className="bg-white rounded-lg shadow p-4">
            <div className="text-sm text-gray-600 mb-1">Total Routes</div>
            <div className="text-2xl font-bold text-gray-900">{routePaths.length}</div>
          </div>
          <div className="bg-white rounded-lg shadow p-4">
            <div className="text-sm text-gray-600 mb-1">Total Tags</div>
            <div className="text-2xl font-bold text-gray-900">{totalTags.toLocaleString()}</div>
          </div>
          <div className="bg-white rounded-lg shadow p-4">
            <div className="text-sm text-gray-600 mb-1">Avg Compliance</div>
            <div className="text-2xl font-bold text-gray-900">{avgCompliance.toFixed(1)}%</div>
          </div>
          <div className="bg-white rounded-lg shadow p-4">
            <div className="text-sm text-gray-600 mb-1">Most Common Route</div>
            <div className="text-sm font-semibold text-gray-900 truncate">
              {routePaths[0]?.path_signature || '-'}
            </div>
          </div>
        </div>
      )}

      {/* Content */}
      {loading ? (
        <div className="bg-white rounded-lg shadow p-12 text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto mb-4"></div>
          <p className="text-gray-600">Loading route paths...</p>
        </div>
      ) : routePaths.length === 0 ? (
        <div className="bg-white rounded-lg shadow p-12 text-center text-gray-500">
          <MapIcon className="w-16 h-16 mx-auto mb-4 text-gray-300" />
          <p>Select all filters to view route paths</p>
        </div>
      ) : (
        <div className="bg-white rounded-lg shadow">
          {viewMode === 'map' ? (
            <RouteFlowMap routePaths={routePaths} />
          ) : (
            <RoutePathTable routePaths={routePaths} />
          )}
        </div>
      )}
    </div>
  )
}
