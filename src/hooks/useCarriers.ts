import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { Carrier, Product, Material } from '@/lib/types'

export function useCarriers() {
  const [carriers, setCarriers] = useState<Carrier[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [materials, setMaterials] = useState<Material[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAll = async () => {
    try {
      setLoading(true)
      setError(null)

      const [carriersRes, productsRes, materialsRes] = await Promise.all([
        supabase.from('carriers').select('*').order('name'),
        supabase.from('products').select('*').order('code'),
        supabase.from('materials').select('*').order('code'),
      ])

      if (carriersRes.error) throw carriersRes.error
      if (productsRes.error) throw productsRes.error
      if (materialsRes.error) throw materialsRes.error

      setCarriers(carriersRes.data || [])
      setProducts(productsRes.data || [])
      setMaterials(materialsRes.data || [])
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAll()
  }, [])

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
    setMaterials(materials.filter(m => m.product_id !== id))
  }

  // Material operations
  const createMaterial = async (data: {
    product_id: string
    code: string
    name: string
    unit_measure?: string
    description?: string
    status?: string
  }) => {
    const { data: newMaterial, error } = await supabase.from('materials').insert(data).select().single()
    if (error) throw error
    setMaterials([...materials, newMaterial])
  }

  const updateMaterial = async (id: string, data: Partial<Material>) => {
    const { data: updated, error } = await supabase.from('materials').update(data).eq('id', id).select().single()
    if (error) throw error
    setMaterials(materials.map(m => m.id === id ? updated : m))
  }

  const deleteMaterial = async (id: string) => {
    const { error } = await supabase.from('materials').delete().eq('id', id)
    if (error) throw error
    setMaterials(materials.filter(m => m.id !== id))
  }

  return {
    carriers,
    products,
    materials,
    loading,
    error,
    createCarrier,
    updateCarrier,
    deleteCarrier,
    createProduct,
    updateProduct,
    deleteProduct,
    createMaterial,
    updateMaterial,
    deleteMaterial,
    refresh: fetchAll,
  }
}
