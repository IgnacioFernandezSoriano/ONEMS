import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { MaterialCatalog, ProductMaterial } from '@/lib/types'

export function useMaterialCatalog() {
  const [catalog, setCatalog] = useState<MaterialCatalog[]>([])
  const [productMaterials, setProductMaterials] = useState<ProductMaterial[]>([])
  const [loading, setLoading] = useState(true)

  const fetchCatalog = async () => {
    const { data, error } = await supabase
      .from('material_catalog')
      .select('*')
      .order('name')
    
    if (error) throw error
    setCatalog(data || [])
  }

  const fetchProductMaterials = async (productId?: string) => {
    let query = supabase
      .from('product_materials')
      .select('*, material_catalog(*)')
      .order('created_at')
    
    if (productId) {
      query = query.eq('product_id', productId)
    }

    const { data, error } = await query
    
    if (error) throw error
    setProductMaterials(data || [])
  }

  const fetchAll = async () => {
    setLoading(true)
    try {
      await Promise.all([fetchCatalog(), fetchProductMaterials()])
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAll()
  }, [])

  const createCatalogItem = async (data: Partial<MaterialCatalog>) => {
    const { data: newItem, error } = await supabase
      .from('material_catalog')
      .insert(data)
      .select()
      .single()
    
    if (error) throw error
    setCatalog(prev => [...prev, newItem])
    return newItem
  }

  const updateCatalogItem = async (id: string, data: Partial<MaterialCatalog>) => {
    const { data: updated, error } = await supabase
      .from('material_catalog')
      .update(data)
      .eq('id', id)
      .select()
      .single()
    
    if (error) throw error
    setCatalog(prev => prev.map(item => item.id === id ? updated : item))
    return updated
  }

  const deleteCatalogItem = async (id: string) => {
    const { error } = await supabase
      .from('material_catalog')
      .delete()
      .eq('id', id)
    
    if (error) throw error
    setCatalog(prev => prev.filter(item => item.id !== id))
  }

  const addMaterialToProduct = async (productId: string, materialCatalogId: string, quantity: number) => {
    const { data: newRelation, error } = await supabase
      .from('product_materials')
      .insert({
        product_id: productId,
        material_id: materialCatalogId,
        quantity
      })
      .select('*, material_catalog(*)')
      .single()
    
    if (error) throw error
    setProductMaterials(prev => [...prev, newRelation])
    return newRelation
  }

  const updateProductMaterialQuantity = async (id: string, quantity: number) => {
    const { data: updated, error } = await supabase
      .from('product_materials')
      .update({ quantity })
      .eq('id', id)
      .select('*, material_catalog(*)')
      .single()
    
    if (error) throw error
    setProductMaterials(prev => prev.map(item => item.id === id ? updated : item))
    return updated
  }

  const removeMaterialFromProduct = async (id: string) => {
    const { error } = await supabase
      .from('product_materials')
      .delete()
      .eq('id', id)
    
    if (error) throw error
    setProductMaterials(prev => prev.filter(item => item.id !== id))
  }

  const getProductMaterials = (productId: string) => {
    return productMaterials.filter(pm => pm.product_id === productId)
  }

  return {
    catalog,
    productMaterials,
    loading,
    fetchCatalog,
    fetchProductMaterials,
    createCatalogItem,
    updateCatalogItem,
    deleteCatalogItem,
    addMaterialToProduct,
    updateProductMaterialQuantity,
    removeMaterialFromProduct,
    getProductMaterials,
  }
}
