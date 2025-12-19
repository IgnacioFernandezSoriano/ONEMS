import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { Carrier, Product, ProductMaterial } from '@/lib/types'
import { useEffectiveAccountId } from './useEffectiveAccountId'

export function useCarriers() {
  const effectiveAccountId = useEffectiveAccountId()
  const [carriers, setCarriers] = useState<Carrier[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [productMaterials, setProductMaterials] = useState<ProductMaterial[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAll = async () => {
    try {
      setLoading(true)
      setError(null)

      // Build queries with account filter if needed
      let carriersQuery = supabase.from('carriers').select('*')
      let productsQuery = supabase.from('products').select('*')
      let productMaterialsQuery = supabase.from('product_materials').select('*, material_catalog(*)')

      if (effectiveAccountId) {
        carriersQuery = carriersQuery.eq('account_id', effectiveAccountId)
        productsQuery = productsQuery.eq('account_id', effectiveAccountId)
        productMaterialsQuery = productMaterialsQuery.eq('account_id', effectiveAccountId)
      }

      const [carriersRes, productsRes, productMaterialsRes] = await Promise.all([
        carriersQuery.order('name'),
        productsQuery.order('code'),
        productMaterialsQuery.order('created_at'),
      ])

      if (carriersRes.error) throw carriersRes.error
      if (productsRes.error) throw productsRes.error
      if (productMaterialsRes.error) throw productMaterialsRes.error

      setCarriers(carriersRes.data || [])
      setProducts(productsRes.data || [])
      setProductMaterials(productMaterialsRes.data || [])
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAll()
  }, [effectiveAccountId])

  // Carrier operations
  const createCarrier = async (data: { code: string; name: string; type?: string; status?: string }) => {
    const { data: newCarrier, error } = await supabase.from('carriers').insert(data).select().single()
    if (error) throw error
    setCarriers([...carriers, newCarrier])
  }

  const updateCarrier = async (id: string, data: Partial<Carrier>) => {
    const { data: updated, error } = await supabase.from('carriers').update(data).eq('id', id).select().single()
    if (error) throw error
    setCarriers(carriers.map(c => c.id === id ? updated : c))
  }

  const deleteCarrier = async (id: string) => {
    const { error } = await supabase.from('carriers').delete().eq('id', id)
    if (error) throw error
    setCarriers(carriers.filter(c => c.id !== id))
    setProducts(products.filter(p => p.carrier_id !== id))
  }

  // Product operations
  const createProduct = async (data: {
    carrier_id: string
    code: string
    description: string
    standard_delivery_hours: number
    status?: string
  }) => {
    const { data: newProduct, error } = await supabase.from('products').insert(data).select().single()
    if (error) throw error
    setProducts([...products, newProduct])
  }

  const updateProduct = async (id: string, data: Partial<Product>) => {
    const { data: updated, error } = await supabase.from('products').update(data).eq('id', id).select().single()
    if (error) throw error
    setProducts(products.map(p => p.id === id ? updated : p))
  }

  const deleteProduct = async (id: string) => {
    const { error } = await supabase.from('products').delete().eq('id', id)
    if (error) throw error
    setProducts(products.filter(p => p.id !== id))
    setProductMaterials(productMaterials.filter(pm => pm.product_id !== id))
  }

  // Product-Material operations (new catalog system)
  const addMaterialToProduct = async (data: {
    product_id: string
    material_id: string
    quantity: number
  }) => {
    const { data: newPM, error } = await supabase
      .from('product_materials')
      .insert(data)
      .select('*, material_catalog(*)')
      .single()
    
    if (error) throw error
    setProductMaterials([...productMaterials, newPM])
  }

  const updateProductMaterial = async (id: string, data: { quantity: number }) => {
    const { data: updated, error } = await supabase
      .from('product_materials')
      .update(data)
      .eq('id', id)
      .select('*, material_catalog(*)')
      .single()
    
    if (error) throw error
    setProductMaterials(productMaterials.map(pm => pm.id === id ? updated : pm))
  }

  const removeProductMaterial = async (id: string) => {
    const { error } = await supabase.from('product_materials').delete().eq('id', id)
    if (error) throw error
    setProductMaterials(productMaterials.filter(pm => pm.id !== id))
  }

  return {
    carriers,
    products,
    productMaterials,
    loading,
    error,
    createCarrier,
    updateCarrier,
    deleteCarrier,
    createProduct,
    updateProduct,
    deleteProduct,
    addMaterialToProduct,
    updateProductMaterial,
    removeProductMaterial,
    refresh: fetchAll,
  }
}
