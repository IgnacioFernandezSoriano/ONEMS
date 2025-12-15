import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { Panelist, PanelistWithNode, Node, City, Region } from '@/lib/types'

export function usePanelists() {
  const [panelists, setPanelists] = useState<PanelistWithNode[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchPanelists = async () => {
    try {
      setLoading(true)
      setError(null)

      const { data, error: fetchError } = await supabase
        .from('panelists')
        .select(`
          *,
          node:nodes (
            *,
            city:cities (
              *,
              region:regions (*)
            )
          )
        `)
        .order('created_at', { ascending: false })

      if (fetchError) throw fetchError

      // Transform data to flatten relationships
      const transformedData = data?.map((panelist: any) => ({
        ...panelist,
        node: panelist.node,
        city: panelist.node?.city,
        region: panelist.node?.city?.region,
      })) || []

      setPanelists(transformedData)
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching panelists:', err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchPanelists()
  }, [])

  const createPanelist = async (panelistData: Omit<Panelist, 'id' | 'created_at' | 'updated_at' | 'account_id'>) => {
    try {
      // Get current user's account_id
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('User not authenticated')

      const { data: profile } = await supabase
        .from('profiles')
        .select('account_id')
        .eq('id', user.id)
        .single()

      if (!profile?.account_id) throw new Error('User account not found')

      const { data, error: insertError } = await supabase
        .from('panelists')
        .insert({
          ...panelistData,
          account_id: profile.account_id,
          created_by: user.id,
        })
        .select()
        .single()

      if (insertError) throw insertError

      await fetchPanelists()
      return data
    } catch (err: any) {
      setError(err.message)
      console.error('Error creating panelist:', err)
      throw err
    }
  }

  const updatePanelist = async (id: string, updates: Partial<Panelist>) => {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('User not authenticated')

      const { data, error: updateError } = await supabase
        .from('panelists')
        .update({
          ...updates,
          updated_by: user.id,
        })
        .eq('id', id)
        .select()
        .single()

      if (updateError) throw updateError

      await fetchPanelists()
      return data
    } catch (err: any) {
      setError(err.message)
      console.error('Error updating panelist:', err)
      throw err
    }
  }

  const deletePanelist = async (id: string) => {
    try {
      const { error: deleteError } = await supabase
        .from('panelists')
        .delete()
        .eq('id', id)

      if (deleteError) throw deleteError

      await fetchPanelists()
    } catch (err: any) {
      setError(err.message)
      console.error('Error deleting panelist:', err)
      throw err
    }
  }

  const getPanelistsByNode = (nodeId: string): PanelistWithNode[] => {
    return panelists.filter(p => p.node_id === nodeId && p.status === 'active')
  }

  const getActivePanelistForNode = (nodeId: string): PanelistWithNode | undefined => {
    return panelists.find(p => p.node_id === nodeId && p.status === 'active')
  }

  return {
    panelists,
    loading,
    error,
    fetchPanelists,
    createPanelist,
    updatePanelist,
    deletePanelist,
    getPanelistsByNode,
    getActivePanelistForNode,
  }
}
