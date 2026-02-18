import { useState, useEffect } from 'react'
import { useAccount } from '../../contexts/AccountContext'
import { supabase } from '../../lib/supabase'
import { Filter, Map as MapIcon, List, Download } from 'lucide-react'
import RoutePathMapLeaflet from '../../components/diagnosis/RoutePathMapLeaflet'
import RoutePathTable from '../../components/diagnosis/RoutePathTable'

interface JourneySegment {
  id: string
  tag_id: string
  carrier_id: string
  product_id: string
  from_postal_center_id: string
  to_postal_center_id: string
  from_city: string
  to_city: string
  segment_type: 'operational' | 'distribution'
  natural_time_in_center_minutes: number
  working_time_in_center_minutes: number
  natural_transit_time_minutes: number
  working_transit_time_minutes: number
  expected_time_minutes: number
  sla_compliance: number
  from_center_name: string
  to_center_name: string
}

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
  percent_real: number
  segment_details: any[]
  expected_time_minutes: number
}

interface FilterState {
  carrier_id: string
  product_id: string
  origin_city: string
  destination_city: string
}

export default function RoutePathAnalysis() {
  const { effectiveAccountId } = useAccount()
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
  const [postalCenters, setPostalCenters] = useState<any[]>([])

  // Load filter options
  useEffect(() => {
    loadFilterOptions()
  }, [effectiveAccountId])

  // Load route paths when filters change or on mount
  useEffect(() => {
    loadRoutePaths()
  }, [filters, effectiveAccountId])

  const loadFilterOptions = async () => {
    if (!effectiveAccountId) return

    try {
      // Load carriers
      const { data: carriersData } = await supabase
        .from('carriers')
        .select('id, name')
        .eq('account_id', effectiveAccountId)
        .order('name')

      if (carriersData) setCarriers(carriersData)

      // Load products
      const { data: productsData } = await supabase
        .from('products')
        .select('id, code, description')
        .eq('account_id', effectiveAccountId)
        .order('code')

      if (productsData) setProducts(productsData)

      // Load unique cities from journey_segments
      const { data: segmentsData } = await supabase
        .from('journey_segments')
        .select('from_city, to_city')
        .eq('account_id', effectiveAccountId)

      if (segmentsData) {
        const uniqueCities = new Set<string>()
        segmentsData.forEach(row => {
          if (row.from_city) uniqueCities.add(row.from_city)
          if (row.to_city) uniqueCities.add(row.to_city)
        })
        setCities(Array.from(uniqueCities).sort())
      }

      // Load postal centers
      const { data: centersData } = await supabase
        .from('postal_centers')
        .select('id, code, name, city')
        .eq('account_id', effectiveAccountId)

      if (centersData) setPostalCenters(centersData)
    } catch (error) {
      console.error('Error loading filter options:', error)
    }
  }

  const loadRoutePaths = async () => {
    if (!effectiveAccountId) return

    setLoading(true)
    try {
      // Load journey_segments
      let query = supabase
        .from('journey_segments')
        .select('*')
        .eq('account_id', effectiveAccountId)

      // Apply filters
      if (filters.carrier_id) query = query.eq('carrier_id', filters.carrier_id)
      if (filters.product_id) query = query.eq('product_id', filters.product_id)
      if (filters.origin_city) query = query.eq('from_city', filters.origin_city)
      if (filters.destination_city) query = query.eq('to_city', filters.destination_city)

      const { data: segments, error } = await query

      if (error) throw error

      // Load carriers
      const { data: carriersData } = await supabase
        .from('carriers')
        .select('id, name')
        .eq('account_id', effectiveAccountId)

      // Load products
      const { data: productsData } = await supabase
        .from('products')
        .select('id, code, description')
        .eq('account_id', effectiveAccountId)

      // Load postal centers
      const { data: centersData } = await supabase
        .from('postal_centers')
        .select('id, name')
        .eq('account_id', effectiveAccountId)

      // Create lookup maps
      const carrierMap = new Map(carriersData?.map(c => [c.id, c.name]) || [])
      const productMap = new Map(productsData?.map(p => [p.id, { code: p.code, description: p.description }]) || [])
      const centerMap = new Map(centersData?.map(c => [c.id, c.name]) || [])

      // Group segments by route (carrier + product + origin + destination)
      const routeMap = new Map<string, JourneySegment[]>()
      
      segments?.forEach((seg: any) => {
        // Find first and last cities for this tag
        const tagSegments = segments.filter((s: any) => s.tag_id === seg.tag_id)
        tagSegments.sort((a: any, b: any) => a.id.localeCompare(b.id))
        
        const originCity = tagSegments[0]?.from_city || seg.from_city
        const destinationCity = tagSegments[tagSegments.length - 1]?.to_city || seg.to_city
        
        const routeKey = `${seg.carrier_id}|${seg.product_id}|${originCity}|${destinationCity}`
        
        if (!routeMap.has(routeKey)) {
          routeMap.set(routeKey, [])
        }
        
        routeMap.get(routeKey)!.push({
          id: seg.id,
          tag_id: seg.tag_id,
          carrier_id: seg.carrier_id,
          product_id: seg.product_id,
          from_postal_center_id: seg.from_postal_center_id,
          to_postal_center_id: seg.to_postal_center_id,
          from_city: seg.from_city,
          to_city: seg.to_city,
          segment_type: seg.segment_type,
          natural_time_in_center_minutes: seg.natural_time_in_center_minutes || 0,
          working_time_in_center_minutes: seg.working_time_in_center_minutes || 0,
          natural_transit_time_minutes: seg.natural_transit_time_minutes || 0,
          working_transit_time_minutes: seg.working_transit_time_minutes || 0,
          expected_time_minutes: seg.expected_time_minutes || 0,
          sla_compliance: seg.sla_compliance || 0,
          from_center_name: centerMap.get(seg.from_postal_center_id) || '',
          to_center_name: centerMap.get(seg.to_postal_center_id) || ''
        })
      })

      // Calculate aggregated metrics for each route
      const formattedData: RoutePathData[] = Array.from(routeMap.entries()).map(([routeKey, routeSegments]) => {
        const [carrier_id, product_id, origin_city, destination_city] = routeKey.split('|')
        
        // Get unique tags
        const uniqueTags = new Set(routeSegments.map(s => s.tag_id))
        const totalTags = uniqueTags.size
        
        // Get carrier and product info from maps
        const carrierName = carrierMap.get(carrier_id) || ''
        const productInfo = productMap.get(product_id)
        
        // Calculate metrics per tag, then average
        const tagMetrics = Array.from(uniqueTags).map(tagId => {
          const tagSegments = routeSegments.filter(s => s.tag_id === tagId)
          
          return {
            expected_time: tagSegments.reduce((sum, s) => sum + s.expected_time_minutes, 0),
            natural_time: tagSegments.reduce((sum, s) => 
              sum + s.natural_time_in_center_minutes + s.natural_transit_time_minutes, 0),
            working_time: tagSegments.reduce((sum, s) => 
              sum + s.working_time_in_center_minutes + s.working_transit_time_minutes, 0),
            avg_compliance: tagSegments.reduce((sum, s) => sum + s.sla_compliance, 0) / tagSegments.length,
            compliance_excluding_zeros: tagSegments.filter(s => s.sla_compliance > 0).length > 0
              ? tagSegments.filter(s => s.sla_compliance > 0).reduce((sum, s) => sum + s.sla_compliance, 0) / 
                tagSegments.filter(s => s.sla_compliance > 0).length
              : 0
          }
        })
        
        // Average across all tags
        const expected_time_minutes = tagMetrics.reduce((sum, m) => sum + m.expected_time, 0) / totalTags
        const avg_natural_time_minutes = tagMetrics.reduce((sum, m) => sum + m.natural_time, 0) / totalTags
        const avg_working_time_minutes = tagMetrics.reduce((sum, m) => sum + m.working_time, 0) / totalTags
        const compliance_rate = tagMetrics.reduce((sum, m) => sum + m.avg_compliance, 0) / totalTags
        const percent_real = tagMetrics.reduce((sum, m) => sum + m.compliance_excluding_zeros, 0) / totalTags
        
        // Build segment details for display
        const segmentDetailsMap = new Map<string, any>()
        
        routeSegments.forEach(seg => {
          const segKey = `${seg.from_postal_center_id}|${seg.to_postal_center_id}`
          
          if (!segmentDetailsMap.has(segKey)) {
            segmentDetailsMap.set(segKey, {
              from_city: seg.from_city,
              to_city: seg.to_city,
              from_center_name: seg.from_center_name,
              to_center_name: seg.to_center_name,
              from_center_id: seg.from_postal_center_id,
              to_center_id: seg.to_postal_center_id,
              segment_type: seg.segment_type,
              expected_time_minutes: 0,
              natural_time: 0,
              working_time: 0,
              compliance_sum: 0,
              compliance_count: 0,
              compliance_non_zero_sum: 0,
              compliance_non_zero_count: 0,
              tags: new Set()
            })
          }
          
          const detail = segmentDetailsMap.get(segKey)!
          detail.expected_time_minutes += seg.expected_time_minutes
          detail.natural_time += seg.natural_time_in_center_minutes + seg.natural_transit_time_minutes
          detail.working_time += seg.working_time_in_center_minutes + seg.working_transit_time_minutes
          detail.compliance_sum += seg.sla_compliance
          detail.compliance_count += 1
          if (seg.sla_compliance > 0) {
            detail.compliance_non_zero_sum += seg.sla_compliance
            detail.compliance_non_zero_count += 1
          }
          detail.tags.add(seg.tag_id)
        })
        
        const segment_details = Array.from(segmentDetailsMap.values()).map(detail => ({
          from_city: detail.from_city,
          to_city: detail.to_city,
          from_center_name: detail.from_center_name,
          to_center_name: detail.to_center_name,
          from_center_id: detail.from_center_id,
          to_center_id: detail.to_center_id,
          segment_type: detail.segment_type,
          expected_time_minutes: detail.expected_time_minutes / detail.tags.size,
          avg_time_in_center_natural: 0, // Not needed for header calculation
          avg_time_in_center_working: 0,
          avg_transit_time_natural: 0,
          avg_transit_time_working: 0,
          avg_total_time_natural: detail.natural_time / detail.tags.size,
          avg_total_time_working: detail.working_time / detail.tags.size,
          on_time_percentage_std: detail.compliance_sum / detail.compliance_count,
          compliance_rate: detail.compliance_non_zero_count > 0 
            ? detail.compliance_non_zero_sum / detail.compliance_non_zero_count 
            : 0,
          warning_threshold: 90,
          critical_threshold: 80,
          tags_count: detail.tags.size,
          calculation_mode: 'frontend'
        }))
        
        // Build path signature
        const uniqueSegmentKeys = Array.from(new Set(
          routeSegments.map(s => `${s.from_city} → ${s.to_city}`)
        ))
        const path_signature = uniqueSegmentKeys.join(' | ')
        
        return {
          id: routeKey,
          carrier_id,
          carrier_name: carrierName,
          product_id,
          product_name: productInfo 
            ? `${productInfo.code} - ${productInfo.description}`
            : '',
          origin_city_name: origin_city,
          destination_city_name: destination_city,
          path_signature,
          path_segments: [],
          total_tags: totalTags,
          avg_natural_time_minutes,
          avg_working_time_minutes,
          compliance_rate,
          percent_real,
          segment_details,
          expected_time_minutes
        }
      })

      // Sort by total tags descending
      formattedData.sort((a, b) => b.total_tags - a.total_tags)
      
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
    ? routePaths.reduce((sum, path) => sum + (path.percent_real || 0) * path.total_tags, 0) / totalTags
    : 0

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Route Path Analysis</h1>
        <button
          onClick={handleExport}
          className="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 flex items-center gap-2"
        >
          <Download className="w-4 h-4" />
          Export
        </button>
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
        <div className="grid grid-cols-3 gap-4">
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
          <p>No route paths found. Try adjusting your filters.</p>
        </div>
      ) : (
        <>
          {/* Map View */}
          <div className="bg-white rounded-lg shadow mb-6">
            <RoutePathMapLeaflet routePaths={routePaths} />
          </div>
          
          {/* Table View */}
          <div className="bg-white rounded-lg shadow">
            <RoutePathTable routePaths={routePaths} postalCenters={postalCenters} />
          </div>
        </>
      )}
    </div>
  )
}
