import { useState, useEffect } from 'react'
import { Button } from '@/components/common/Button'
import type { Reader, ReaderFormData } from '@/lib/types_postal_centers'
import { useTranslation } from '@/hooks/useTranslation'

interface ReaderFormProps {
  reader?: Reader | null
  onSubmit: (data: ReaderFormData) => Promise<void>
  onCancel: () => void
}

export function ReaderForm({ reader, onSubmit, onCancel }: ReaderFormProps) {
  const { t } = useTranslation()
  const [formData, setFormData] = useState<ReaderFormData>({
    reader_id: '',
    name: '',
    description: '',
    type: 'Entry',
    mixed_reader_gap_minutes: null,
    is_active: true
  })
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (reader) {
      setFormData({
        reader_id: reader.reader_id,
        name: reader.name,
        description: reader.description || '',
        type: reader.type,
        mixed_reader_gap_minutes: reader.mixed_reader_gap_minutes,
        is_active: reader.is_active
      })
    }
  }, [reader])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setSubmitting(true)

    try {
      await onSubmit(formData)
    } catch (err: any) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
          {error}
        </div>
      )}

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('readers.reader_id')} *
        </label>
        <input
          type="text"
          value={formData.reader_id}
          onChange={(e) => setFormData({ ...formData, reader_id: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          required
          disabled={!!reader} // Reader ID cannot be changed after creation
          placeholder="J11DBRA02100000319"
        />
        <p className="text-xs text-gray-500 mt-1">
          {t('readers.reader_id_help')}
        </p>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('readers.name')} *
        </label>
        <input
          type="text"
          value={formData.name}
          onChange={(e) => setFormData({ ...formData, name: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          required
          placeholder="Reader MAD 001"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('readers.description')}
        </label>
        <textarea
          value={formData.description}
          onChange={(e) => setFormData({ ...formData, description: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          rows={2}
          placeholder="Entry gate at loading dock"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('readers.type')} *
        </label>
        <select
          value={formData.type}
          onChange={(e) => setFormData({ ...formData, type: e.target.value as 'Entry' | 'Exit' | 'Mixed' })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
          required
        >
          <option value="Entry">{t('readers.type_entry')}</option>
          <option value="Exit">{t('readers.type_exit')}</option>
          <option value="Mixed">{t('readers.type_mixed')}</option>
        </select>
        <p className="text-xs text-gray-500 mt-1">
          {formData.type === 'Entry' && t('readers.type_entry_help')}
          {formData.type === 'Exit' && t('readers.type_exit_help')}
          {formData.type === 'Mixed' && t('readers.type_mixed_help')}
        </p>
      </div>

      {formData.type === 'Mixed' && (
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('readers.mixed_reader_gap_minutes')}
          </label>
          <input
            type="number"
            value={formData.mixed_reader_gap_minutes || ''}
            onChange={(e) => setFormData({ ...formData, mixed_reader_gap_minutes: e.target.value ? parseInt(e.target.value) : null })}
            className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            min="1"
            placeholder="10"
          />
          <p className="text-xs text-gray-500 mt-1">
            {t('readers.mixed_reader_gap_help')}
          </p>
        </div>
      )}

      <div className="flex items-center">
        <input
          type="checkbox"
          id="is_active"
          checked={formData.is_active}
          onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
          className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
        />
        <label htmlFor="is_active" className="ml-2 block text-sm text-gray-700">
          {t('readers.is_active')}
        </label>
      </div>

      <div className="flex justify-end gap-2 pt-4">
        <Button
          type="button"
          variant="secondary"
          onClick={onCancel}
          disabled={submitting}
        >
          {t('common.cancel')}
        </Button>
        <Button
          type="submit"
          disabled={submitting}
        >
          {submitting ? t('common.saving') : (reader ? t('common.update') : t('common.create'))}
        </Button>
      </div>
    </form>
  )
}
