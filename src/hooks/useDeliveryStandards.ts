import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { DeliveryStandardWithDetails, Carrier, Product, City } from '@/lib/types'

export function useDeliveryStandards() {
  const [standards, setStandards] = useState<DeliveryStandardWithDetails[]>([])
  const [carriers, setCarriers] = useState<Carrier[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [cities, setCities] = useState<City[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAll = async () => {
    try {
      setLoading(true)
      setError(null)

      const [standardsRes, carriersRes, productsRes, citiesRes] = await Promise.all([
        supabase
          .from('delivery_standards')
          .select(`
            *,
            carrier:carriers(*),
            product:products(*),
            origin_city:cities!delivery_standards_origin_city_id_fkey(*),
            destination_city:cities!delivery_standards_destination_city_id_fkey(*)
          `)
          .order('created_at', { ascending: false }),
        supabase.from('carriers').select('*').eq('status', 'active').order('name'),
        supabase.from('products').select('*').eq('status', 'active').order('code'),
        supabase.from('cities').select('*').eq('status', 'active').order('name'),
      ])

      if (standardsRes.error) throw standardsRes.error
      if (carriersRes.error) throw carriersRes.error
      if (productsRes.error) throw productsRes.error
      if (citiesRes.error) throw citiesRes.error

      setStandards(standardsRes.data || [])
      setCarriers(carriersRes.data || [])
      setProducts(productsRes.data || [])
      setCities(citiesRes.data || [])
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAll()
  }, [])

  const createStandard = async (data: {
    carrier_id: string
    product_id: string
    origin_city_id: string
    destination_city_id: string
    standard_time?: number | null
    success_percentage?: number | null
    time_unit: 'hours' | 'days'
  }) => {
    const { error } = await supabase.from('delivery_standards').insert(data)
    if (error) throw error
    await fetchAll()
  }

  const generateCombinations = async (
    carrierIds?: string[],
    productIds?: string[],
    originCityIds?: string[],
    destinationCityIds?: string[]
  ) => {
    const { data, error } = await supabase.rpc('generate_delivery_standards', {
      p_carrier_ids: carrierIds && carrierIds.length > 0 ? carrierIds : null,
      p_product_ids: productIds && productIds.length > 0 ? productIds : null,
      p_origin_city_ids: originCityIds && originCityIds.length > 0 ? originCityIds : null,
      p_destination_city_ids: destinationCityIds && destinationCityIds.length > 0 ? destinationCityIds : null,
    })

    if (error) throw error
    await fetchAll() // Refresh data
    return data[0] // Returns { inserted_count, skipped_count }
  }

  const updateStandard = async (
    id: string,
    data: {
      standard_time?: number | null
      success_percentage?: number | null
      time_unit?: 'hours' | 'days'
    }
  ) => {
    const { error } = await supabase
      .from('delivery_standards')
      .update(data)
      .eq('id', id)

    if (error) throw error
    await fetchAll()
  }

  const updateMultiple = async (
    ids: string[],
    data: {
      standard_time?: number | null
      success_percentage?: number | null
      time_unit?: 'hours' | 'days'
    }
  ) => {
    const { error } = await supabase
      .from('delivery_standards')
      .update(data)
      .in('id', ids)

    if (error) throw error
    await fetchAll()
  }

  const deleteStandard = async (id: string) => {
    const { error } = await supabase.from('delivery_standards').delete().eq('id', id)
    if (error) throw error
    await fetchAll()
  }

  const deleteMultiple = async (ids: string[]) => {
    const { error } = await supabase.from('delivery_standards').delete().in('id', ids)
    if (error) throw error
    await fetchAll()
  }

  return {
    standards,
    carriers,
    products,
    cities,
    loading,
    error,
    createStandard,
    generateCombinations,
    updateStandard,
    updateMultiple,
    deleteStandard,
    deleteMultiple,
    refresh: fetchAll,
  }
}
