import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { Panelist, PanelistWithNode, Node, City, Region } from '@/lib/types'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'

export function usePanelists() {
  const effectiveAccountId = useEffectiveAccountId()
  const [panelists, setPanelists] = useState<PanelistWithNode[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchPanelists = async () => {
    try {
      setLoading(true)
      setError(null)

      let query = supabase
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

      // Filter by account if effectiveAccountId is set
      if (effectiveAccountId) {
        query = query.eq('account_id', effectiveAccountId)
      }

      const { data, error: fetchError } = await query.order('created_at', { ascending: false })

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
  }, [effectiveAccountId])

  const createPanelist = async (panelistData: Omit<Panelist, 'id' | 'created_at' | 'updated_at' | 'account_id'>) => {
    try {
      // Get current user
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('User not authenticated')

      // Get account_id: use effectiveAccountId if available (superadmin with selected account),
      // otherwise use profile.account_id (normal user)
      let accountId = effectiveAccountId
      
      if (!accountId) {
        const { data: profile } = await supabase
          .from('profiles')
          .select('account_id')
          .eq('id', user.id)
          .single()
        accountId = profile?.account_id
      }

      if (!accountId) throw new Error('User account not found')

      // Generate panelist_code if empty or null
      let panelistCode = panelistData.panelist_code
      if (!panelistCode || panelistCode.trim() === '') {
        // Validate node_id is provided
        if (!panelistData.node_id) {
          throw new Error('Node must be selected to auto-generate panelist code')
        }

        // Get node information to extract city and node number
        const { data: nodeData, error: nodeError } = await supabase
          .from('nodes')
          .select('node_code, city:cities(name)')
          .eq('id', panelistData.node_id)
          .single()

        if (nodeError || !nodeData) {
          throw new Error('Node not found')
        }

        // Extract node number from node_code (e.g., "CENTRO-MAD-002" -> "002")
        const nodeMatch = nodeData.node_code?.match(/(\d+)$/)
        const nodeNumber = nodeMatch ? nodeMatch[1] : '000'

        // Get city name (first 3 letters, uppercase)
        const cityName = (nodeData.city as any)?.name || 'XXX'
        const cityCode = cityName.substring(0, 3).toUpperCase()

        // Get the highest existing serial for this specific node
        const { data: existingPanelists } = await supabase
          .from('panelists')
          .select('panelist_code')
          .eq('account_id', accountId)
          .eq('node_id', panelistData.node_id)
          .not('panelist_code', 'is', null)
          .order('panelist_code', { ascending: false })
          .limit(1)

        let nextSerial = 1
        if (existingPanelists && existingPanelists.length > 0) {
          const lastCode = existingPanelists[0].panelist_code
          // Extract serial number from code like "PAN-MAD-002-001"
          const serialMatch = lastCode?.match(/(\d+)$/)
          if (serialMatch) {
            nextSerial = parseInt(serialMatch[1], 10) + 1
          }
        }
        
        // Generate new code with format PAN-CITY-NODE-SERIAL
        panelistCode = `PAN-${cityCode}-${nodeNumber}-${String(nextSerial).padStart(3, '0')}`
      }

      const { data, error: insertError } = await supabase
        .from('panelists')
        .insert({
          ...panelistData,
          panelist_code: panelistCode,
          account_id: accountId,
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
