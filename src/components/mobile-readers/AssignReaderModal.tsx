import { useState } from 'react';
import { X, MapPin, Calendar, FileText } from 'lucide-react';
import { Button } from '@/components/common/Button';
import { usePostalCenters } from '@/hooks/usePostalCenters';
import { useTranslation } from '@/hooks/useTranslation';

interface AssignReaderModalProps {
  readerId: string;
  readerName: string;
  currentCenterId?: string | null;
  onAssign: (
    postalCenterId: string,
    assignedAt: string,
    unassignedAt: string | null,
    notes: string | null
  ) => Promise<{ success: boolean; error?: string }>;
  onClose: () => void;
}

export function AssignReaderModal({
  readerId,
  readerName,
  currentCenterId,
  onAssign,
  onClose,
}: AssignReaderModalProps) {
  const { t } = useTranslation();
  const { postalCenters } = usePostalCenters();
  const [formData, setFormData] = useState({
    postal_center_id: currentCenterId || '',
    assigned_at: new Date().toISOString().slice(0, 16),
    unassigned_at: '',
    notes: '',
  });
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!formData.postal_center_id) {
      setError(t('mobile_readers.select_center_error'));
      return;
    }

    setSubmitting(true);

    try {
      const result = await onAssign(
        formData.postal_center_id,
        formData.assigned_at,
        formData.unassigned_at || null,
        formData.notes || null
      );

      if (result.success) {
        onClose();
      } else {
        setError(result.error || t('common.error'));
      }
    } catch (err: any) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="flex items-center justify-between p-6 border-b border-gray-200 dark:border-gray-700">
          <div>
            <h2 className="text-xl font-semibold text-gray-900 dark:text-white">
              {t('mobile_readers.assign_reader')}
            </h2>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">{readerName}</p>
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="p-6 space-y-6">
          {error && (
            <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 text-red-700 dark:text-red-400 px-4 py-3 rounded-lg">
              {error}
            </div>
          )}

          {/* Postal Center Selection */}
          <div>
            <label className="flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              <MapPin className="w-4 h-4" />
              {t('mobile_readers.postal_center')} *
            </label>
            <select
              value={formData.postal_center_id}
              onChange={(e) =>
                setFormData({ ...formData, postal_center_id: e.target.value })
              }
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:text-white"
              required
            >
              <option value="">{t('mobile_readers.select_center')}</option>
              {postalCenters.map((center) => (
                <option key={center.id} value={center.id}>
                  {center.name} ({center.code})
                </option>
              ))}
            </select>
            <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
              {t('mobile_readers.select_center_help')}
            </p>
          </div>

          {/* Assignment Date */}
          <div>
            <label className="flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              <Calendar className="w-4 h-4" />
              {t('mobile_readers.assigned_at')} *
            </label>
            <input
              type="datetime-local"
              value={formData.assigned_at}
              onChange={(e) => setFormData({ ...formData, assigned_at: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:text-white"
              required
            />
            <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
              {t('mobile_readers.assigned_at_help')}
            </p>
          </div>

          {/* Unassignment Date (Optional) */}
          <div>
            <label className="flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              <Calendar className="w-4 h-4" />
              {t('mobile_readers.unassigned_at')} ({t('common.optional')})
            </label>
            <input
              type="datetime-local"
              value={formData.unassigned_at}
              onChange={(e) => setFormData({ ...formData, unassigned_at: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:text-white"
            />
            <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
              {t('mobile_readers.unassigned_at_help')}
            </p>
          </div>

          {/* Notes */}
          <div>
            <label className="flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              <FileText className="w-4 h-4" />
              {t('mobile_readers.notes')} ({t('common.optional')})
            </label>
            <textarea
              value={formData.notes}
              onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:text-white"
              rows={3}
              placeholder={t('mobile_readers.notes_placeholder')}
            />
            <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
              {t('mobile_readers.notes_help')}
            </p>
          </div>

          {/* Actions */}
          <div className="flex justify-end gap-3 pt-4 border-t border-gray-200 dark:border-gray-700">
            <Button type="button" variant="secondary" onClick={onClose} disabled={submitting}>
              {t('common.cancel')}
            </Button>
            <Button type="submit" disabled={submitting}>
              {submitting ? t('common.saving') : t('mobile_readers.assign')}
            </Button>
          </div>
        </form>
      </div>
    </div>
  );
}
