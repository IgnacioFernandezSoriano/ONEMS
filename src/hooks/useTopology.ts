import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { Region, City, Node } from '@/lib/types'

export function useTopology() {
  const [regions, setRegions] = useState<Region[]>([])
  const [cities, setCities] = useState<City[]>([])
  const [nodes, setNodes] = useState<Node[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAll = async () => {
    try {
      setLoading(true)
      setError(null)

      const [regionsRes, citiesRes, nodesRes] = await Promise.all([
        supabase.from('regions').select('*').order('name'),
        supabase.from('cities').select('*').order('name'),
        supabase.from('nodes').select('*').order('auto_id'),
      ])

      if (regionsRes.error) throw regionsRes.error
      if (citiesRes.error) throw citiesRes.error
      if (nodesRes.error) throw nodesRes.error

      setRegions(regionsRes.data || [])
      setCities(citiesRes.data || [])
      setNodes(nodesRes.data || [])
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAll()
  }, [])

  // Region operations
  const createRegion = async (data: { name: string; code: string; description?: string }) => {
    const { error } = await supabase.from('regions').insert(data)
    if (error) throw error
    await fetchAll()
  }

  const updateRegion = async (id: string, data: Partial<Region>) => {
    const { error } = await supabase.from('regions').update(data).eq('id', id)
    if (error) throw error
    await fetchAll()
  }

  const deleteRegion = async (id: string) => {
    const { error } = await supabase.from('regions').delete().eq('id', id)
    if (error) throw error
    await fetchAll()
  }

  // City operations
  const createCity = async (data: {
    region_id: string
    name: string
    code: string
    latitude?: number
    longitude?: number
  }) => {
    const { error } = await supabase.from('cities').insert(data)
    if (error) throw error
    await fetchAll()
  }

  const updateCity = async (id: string, data: Partial<City>) => {
    const { error } = await supabase.from('cities').update(data).eq('id', id)
    if (error) throw error
    await fetchAll()
  }

  const deleteCity = async (id: string) => {
    const { error } = await supabase.from('cities').delete().eq('id', id)
    if (error) throw error
    await fetchAll()
  }

  // Node operations
  const createNode = async (data: {
    city_id: string
    name?: string
    node_type?: 'core' | 'edge' | 'access'
    ip_address?: string
  }) => {
    // Generate auto_id
    const { data: autoIdData, error: autoIdError } = await supabase.rpc(
      'generate_node_auto_id',
      { p_city_id: data.city_id }
    )

    if (autoIdError) throw autoIdError

    const { error } = await supabase.from('nodes').insert({
      ...data,
      auto_id: autoIdData,
    })

    if (error) throw error
    await fetchAll()
  }

  const updateNode = async (id: string, data: Partial<Node>) => {
    const { error } = await supabase.from('nodes').update(data).eq('id', id)
    if (error) throw error
    await fetchAll()
  }

  const deleteNode = async (id: string) => {
    const { error } = await supabase.from('nodes').delete().eq('id', id)
    if (error) throw error
    await fetchAll()
  }

  return {
    regions,
    cities,
    nodes,
    loading,
    error,
    createRegion,
    updateRegion,
    deleteRegion,
    createCity,
    updateCity,
    deleteCity,
    createNode,
    updateNode,
    deleteNode,
    refresh: fetchAll,
  }
}
