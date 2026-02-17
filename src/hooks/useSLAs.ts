import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { SLAWithDetails, SLAFormData, GenerateCombinationsRequest } from '@/lib/types_slas'
import type { PostalCenter } from '@/lib/types_postal_centers'
import type { Carrier, Product } from '@/lib/types'
import { useEffectiveAccountId } from './useEffectiveAccountId'

export function useSLAs() {
  const effectiveAccountId = useEffectiveAccountId()
  const [slas, setSLAs] = useState<SLAWithDetails[]>([])
  const [postalCenters, setPostalCenters] = useState<PostalCenter[]>([])
  const [carriers, setCarriers] = useState<Carrier[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAll = async () => {
    try {
      setLoading(true)
      setError(null)

      // Build queries with account filter
      let slasQuery = supabase
        .from('slas')
        .select(`
          *,
          postal_center:postal_centers!slas_postal_center_id_fkey(*),
          from_postal_center:postal_centers!slas_from_postal_center_id_fkey(*),
          to_postal_center:postal_centers!slas_to_postal_center_id_fkey(*)
        `)

      let postalCentersQuery = supabase
        .from('postal_centers')
        .select('*')
        .eq('is_active', true)
        .is('deleted_at', null)

      let carriersQuery = supabase
        .from('carriers')
        .select('*')

      let productsQuery = supabase
        .from('products')
        .select('*')

      if (effectiveAccountId) {
        slasQuery = slasQuery.eq('account_id', effectiveAccountId)
        postalCentersQuery = postalCentersQuery.eq('account_id', effectiveAccountId)
        carriersQuery = carriersQuery.eq('account_id', effectiveAccountId)
        productsQuery = productsQuery.eq('account_id', effectiveAccountId)
      }

      const [slasRes, postalCentersRes, carriersRes, productsRes] = await Promise.all([
        slasQuery.order('created_at', { ascending: false }),
        postalCentersQuery.order('name'),
        carriersQuery.order('name'),
        productsQuery.order('code'),
      ])

      if (slasRes.error) throw slasRes.error
      if (postalCentersRes.error) throw postalCentersRes.error
      if (carriersRes.error) throw carriersRes.error
      if (productsRes.error) throw productsRes.error

      setSLAs(slasRes.data || [])
      setPostalCenters(postalCentersRes.data || [])
      setCarriers(carriersRes.data || [])
      setProducts(productsRes.data || [])
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAll()
  }, [effectiveAccountId])

  const createSLA = async (data: SLAFormData) => {
    if (!effectiveAccountId) throw new Error('Account ID is required')

    // Check for duplicate based on unique constraint
    let duplicateQuery = supabase
      .from('slas')
      .select('id')
      .eq('account_id', effectiveAccountId)
      .eq('sla_type', data.sla_type)
      .is('deleted_at', null)

    if (data.sla_type === 'operational') {
      duplicateQuery = duplicateQuery
        .eq('postal_center_id', data.postal_center_id!)
        .eq('carrier_id', data.carrier_id || null)
        .eq('product_id', data.product_id || null)
    } else {
      duplicateQuery = duplicateQuery
        .eq('from_postal_center_id', data.from_postal_center_id!)
        .eq('to_postal_center_id', data.to_postal_center_id!)
        .eq('carrier_id', data.carrier_id || null)
        .eq('product_id', data.product_id || null)
    }

    const { data: existing } = await duplicateQuery

    if (existing && existing.length > 0) {
      throw new Error(
        'Ya existe un SLA para esta combinación de ' +
        (data.sla_type === 'operational' 
          ? 'Centro Postal, Carrier y Producto' 
          : 'Origen, Destino, Carrier y Producto') +
        '. Por favor, modifica alguno de estos valores o edita el SLA existente.'
      )
    }

    const { error } = await supabase.from('slas').insert({
      ...data,
      account_id: effectiveAccountId,
    })

    if (error) throw error
    await fetchAll()
  }

  const generateCombinations = async (request: GenerateCombinationsRequest & {
    selectedCenters?: string[]
    selectedRoutes?: Array<{ from: string; to: string }>
    selectedCarriers?: string[]
    selectedProducts?: string[]
    generateOperational?: boolean
    generateDistribution?: boolean
  }) => {
    if (!effectiveAccountId) throw new Error('Account ID is required')

    const combinations: any[] = []

    // 1. Generate OPERATIONAL SLAs for selected centers × carriers × products
    if (request.generateOperational && request.selectedCenters) {
      // Use selected carriers and products
      const carrierIds = request.selectedCarriers || []
      
      // Get product details for selected products
      const productsRes = await supabase
        .from('products')
        .select('id, carrier_id, standard_delivery_hours, time_unit')
        .eq('account_id', effectiveAccountId)
        .in('id', request.selectedProducts || [])
      
      const allProducts = productsRes.data || []
      
      for (const centerId of request.selectedCenters) {
        for (const carrierId of carrierIds) {
          // Get products for this carrier
          const carrierProducts = allProducts.filter(p => p.carrier_id === carrierId)
          
          for (const product of carrierProducts) {
            // Calculate expected time based on product standard delivery
            let expectedMinutes = request.expected_time_minutes
            if (product.standard_delivery_hours && product.time_unit) {
              if (product.time_unit === 'days') {
                expectedMinutes = product.standard_delivery_hours * 24 * 60
              } else if (product.time_unit === 'hours') {
                expectedMinutes = product.standard_delivery_hours * 60
              } else {
                expectedMinutes = product.standard_delivery_hours
              }
            }
            
            combinations.push({
              account_id: effectiveAccountId,
              sla_type: 'operational',
              postal_center_id: centerId,
              from_postal_center_id: null,
              to_postal_center_id: null,
              carrier_id: carrierId,
              product_id: product.id,
              expected_time_minutes: expectedMinutes,
              time_unit: request.time_unit,
              on_time_percentage: request.on_time_percentage,
              warning_threshold: request.warning_threshold,
              critical_threshold: request.critical_threshold,
              is_active: true,
            })
          }
        }
      }
    }

    // 2. Generate DISTRIBUTION SLAs for selected routes × carriers × products
    if (request.generateDistribution && request.selectedRoutes) {
      // Use selected carriers and products
      const carrierIds = request.selectedCarriers || []
      
      // Get product details for selected products
      const productsRes = await supabase
        .from('products')
        .select('id, carrier_id, standard_delivery_hours, time_unit')
        .eq('account_id', effectiveAccountId)
        .in('id', request.selectedProducts || [])
      
      const allProducts = productsRes.data || []
      
      // Generate SLA for each route × carrier × product combination
      for (const route of request.selectedRoutes) {
        for (const carrierId of carrierIds) {
          // Get products for this carrier
          const carrierProducts = allProducts.filter(p => p.carrier_id === carrierId)
          
          for (const product of carrierProducts) {
            // Calculate expected time based on product standard delivery
            let expectedMinutes = request.expected_time_minutes
            if (product.standard_delivery_hours && product.time_unit) {
              if (product.time_unit === 'days') {
                expectedMinutes = product.standard_delivery_hours * 24 * 60
              } else if (product.time_unit === 'hours') {
                expectedMinutes = product.standard_delivery_hours * 60
              } else {
                expectedMinutes = product.standard_delivery_hours
              }
            }
            
            combinations.push({
              account_id: effectiveAccountId,
              sla_type: 'distribution',
              postal_center_id: null,
              from_postal_center_id: route.from,
              to_postal_center_id: route.to,
              carrier_id: carrierId,
              product_id: product.id,
              expected_time_minutes: expectedMinutes,
              time_unit: request.time_unit,
              on_time_percentage: request.on_time_percentage,
              warning_threshold: request.warning_threshold,
              critical_threshold: request.critical_threshold,
              is_active: true,
            })
          }
        }
      }
    }

    if (combinations.length === 0) {
      return { inserted_count: 0, skipped_count: 0 }
    }

    // Batch insert with upsert (skip duplicates)
    const chunkSize = 500
    let insertedCount = 0
    let skippedCount = 0

    for (let i = 0; i < combinations.length; i += chunkSize) {
      const chunk = combinations.slice(i, i + chunkSize)
      
      const { data, error } = await supabase
        .from('slas')
        .upsert(chunk, { 
          onConflict: 'id', // Will use unique indexes to detect conflicts
          ignoreDuplicates: true 
        })
        .select()

      if (error) {
        // If error is due to unique constraint, count as skipped
        if (error.code === '23505') {
          skippedCount += chunk.length
        } else {
          throw error
        }
      } else {
        insertedCount += data?.length || 0
        skippedCount += chunk.length - (data?.length || 0)
      }
    }

    await fetchAll()
    return { inserted_count: insertedCount, skipped_count: skippedCount }
  }

  const updateSLA = async (
    id: string,
    data: Partial<SLAFormData>
  ) => {
    const { error } = await supabase
      .from('slas')
      .update(data)
      .eq('id', id)

    if (error) throw error
    await fetchAll()
  }

  const updateMultiple = async (
    ids: string[],
    data: Partial<SLAFormData>
  ) => {
    const { error } = await supabase
      .from('slas')
      .update(data)
      .in('id', ids)

    if (error) throw error
    await fetchAll()
  }

  const deleteSLA = async (id: string) => {
    // Soft delete: set deleted_at timestamp
    const { error } = await supabase
      .from('slas')
      .update({ deleted_at: new Date().toISOString() })
      .eq('id', id)
    if (error) throw error
    await fetchAll()
  }

  const deleteMultiple = async (ids: string[]) => {
    // Soft delete: set deleted_at timestamp
    const { error } = await supabase
      .from('slas')
      .update({ deleted_at: new Date().toISOString() })
      .in('id', ids)
    if (error) throw error
    await fetchAll()
  }

  return {
    slas,
    postalCenters,
    carriers,
    products,
    loading,
    error,
    createSLA,
    generateCombinations,
    updateSLA,
    updateMultiple,
    deleteSLA,
    deleteMultiple,
    refresh: fetchAll,
  }
}
