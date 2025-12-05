import { useState } from 'react'
import { Button } from '@/components/common/Button'
import type { Node } from '@/lib/types'

interface NodeFormProps {
  node?: Node
  cityId: string
  onSubmit: (data: any) => Promise<void>
  onCancel: () => void
}

export function NodeForm({ node, cityId, onSubmit, onCancel }: NodeFormProps) {
  const [formData, setFormData] = useState({
    city_id: cityId,
    name: node?.name || '',
    node_type: node?.node_type || 'access',
    ip_address: node?.ip_address || '',
  })
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      const data: any = {
        city_id: formData.city_id,
        node_type: formData.node_type,
      }
      if (formData.name) data.name = formData.name
      if (formData.ip_address) data.ip_address = formData.ip_address
      
      await onSubmit(data)
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <label className="block text-sm font-medium mb-1">Node Name</label>
        <input
          type="text"
          value={formData.name}
          onChange={(e) => setFormData({ ...formData, name: e.target.value })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder="Optional descriptive name"
        />
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">Node Type *</label>
        <select
          required
          value={formData.node_type}
          onChange={(e) => setFormData({ ...formData, node_type: e.target.value as any })}
          className="w-full px-3 py-2 border rounded-md"
        >
          <option value="access">Access</option>
          <option value="edge">Edge</option>
          <option value="core">Core</option>
        </select>
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">IP Address</label>
        <input
          type="text"
          value={formData.ip_address}
          onChange={(e) => setFormData({ ...formData, ip_address: e.target.value })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder="192.168.1.1"
        />
      </div>

      <div className="flex gap-2 justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={loading}>
          {loading ? 'Saving...' : node ? 'Update' : 'Create'}
        </Button>
      </div>
    </form>
  )
}
