import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { Region, City, Node } from '@/lib/types'
import { useEffectiveAccountId } from './useEffectiveAccountId'

export function useTopology() {
  const effectiveAccountId = useEffectiveAccountId()
  const [regions, setRegions] = useState<Region[]>([])
  const [cities, setCities] = useState<City[]>([])
  const [nodes, setNodes] = useState<Node[]>([])
  const [panelists, setPanelists] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAll = async () => {
    try {
      setLoading(true)
      setError(null)

      // Build queries with account filter if needed
      let regionsQuery = supabase.from('regions').select('*').order('name')
      let citiesQuery = supabase.from('cities').select('*').order('name')
      let nodesQuery = supabase.from('nodes').select('*').order('auto_id')

      if (effectiveAccountId) {
        regionsQuery = regionsQuery.eq('account_id', effectiveAccountId)
        citiesQuery = citiesQuery.eq('account_id', effectiveAccountId)
        nodesQuery = nodesQuery.eq('account_id', effectiveAccountId)
      }

      // Fetch panelists for node status
      let panelistsQuery = supabase.from('panelists').select('id, node_id, name, status')
      if (effectiveAccountId) {
        panelistsQuery = panelistsQuery.eq('account_id', effectiveAccountId)
      }

      const [regionsRes, citiesRes, nodesRes, panelistsRes] = await Promise.all([
        regionsQuery,
        citiesQuery,
        nodesQuery,
        panelistsQuery,
      ])

      if (regionsRes.error) throw regionsRes.error
      if (citiesRes.error) throw citiesRes.error
      if (nodesRes.error) throw nodesRes.error
      if (panelistsRes.error) throw panelistsRes.error

      setRegions(regionsRes.data || [])
      setCities(citiesRes.data || [])
      setNodes(nodesRes.data || [])
      setPanelists(panelistsRes.data || [])
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAll()
  }, [effectiveAccountId])

  // Region operations
  const createRegion = async (data: { name: string; code: string; description?: string }) => {
    const { data: newRegion, error } = await supabase
      .from('regions')
      .insert({ ...data, account_id: effectiveAccountId })
      .select()
      .single()
    if (error) throw error
    setRegions([...regions, newRegion])
  }

  const updateRegion = async (id: string, data: Partial<Region>) => {
    const { data: updated, error } = await supabase.from('regions').update(data).eq('id', id).select().single()
    if (error) throw error
    setRegions(regions.map(r => r.id === id ? updated : r))
  }

  const deleteRegion = async (id: string) => {
    const { error } = await supabase.from('regions').delete().eq('id', id)
    if (error) throw error
    setRegions(regions.filter(r => r.id !== id))
    setCities(cities.filter(c => c.region_id !== id))
    setNodes(nodes.filter(n => !cities.some(c => c.id === n.city_id && c.region_id === id)))
  }

  // City operations
  const createCity = async (data: {
    region_id: string
    name: string
    code: string
    latitude?: number
    longitude?: number
  }) => {
    const { data: newCity, error } = await supabase
      .from('cities')
      .insert({ ...data, account_id: effectiveAccountId })
      .select()
      .single()
    if (error) throw error
    setCities([...cities, newCity])
  }

  const updateCity = async (id: string, data: Partial<City>) => {
    const { data: updated, error } = await supabase.from('cities').update(data).eq('id', id).select().single()
    if (error) throw error
    setCities(cities.map(c => c.id === id ? updated : c))
  }

  const deleteCity = async (id: string) => {
    const { error } = await supabase.from('cities').delete().eq('id', id)
    if (error) throw error
    setCities(cities.filter(c => c.id !== id))
    setNodes(nodes.filter(n => n.city_id !== id))
  }

  // Node operations
  const createNode = async (data: { city_id: string }) => {
    // Generate auto_id
    const { data: autoIdData, error: autoIdError } = await supabase.rpc(
      'generate_node_auto_id',
      { p_city_id: data.city_id }
    )

    if (autoIdError) throw autoIdError

    const { error } = await supabase.from('nodes').insert({
      city_id: data.city_id,
      auto_id: autoIdData,
      status: 'active',
      account_id: effectiveAccountId,
    })

    if (error) throw error
    
    // Fetch the newly created node
    const { data: newNode, error: fetchError } = await supabase
      .from('nodes')
      .select('*')
      .eq('auto_id', autoIdData)
      .single()
    
    if (fetchError) throw fetchError
    setNodes([...nodes, newNode])
  }

  const updateNode = async (id: string, data: Partial<Node>) => {
    const { data: updated, error } = await supabase.from('nodes').update(data).eq('id', id).select().single()
    if (error) throw error
    setNodes(nodes.map(n => n.id === id ? updated : n))
  }

  const deleteNode = async (id: string) => {
    const { error } = await supabase.from('nodes').delete().eq('id', id)
    if (error) throw error
    setNodes(nodes.filter(n => n.id !== id))
  }

  return {
    regions,
    cities,
    nodes,
    panelists,
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
