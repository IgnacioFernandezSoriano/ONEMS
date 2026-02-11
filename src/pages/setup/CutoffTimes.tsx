import { useState } from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import { useCutoffTimes } from '@/hooks/useCutoffTimes';
import { Clock, Plus, Edit, Trash2, Save, X } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';

export default function CutoffTimes() {
  const { t } = useTranslation();
  const {
    cutoffs,
    loading,
    error,
    createCutoff,
    updateCutoff,
    deleteCutoff,
  } = useCutoffTimes();

  const [isEditing, setIsEditing] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [formData, setFormData] = useState({
    postal_center_id: '',
    cutoff_time: '18:00',
    timezone: 'UTC',
    working_hours_start: '09:00',
    working_hours_end: '18:00',
    working_days: [1, 2, 3, 4, 5],
  });

  const handleSave = async () => {
    if (editingId) {
      await updateCutoff(editingId, formData);
    } else {
      await createCutoff(formData);
    }
    setIsEditing(false);
    setEditingId(null);
    resetForm();
  };

  const handleEdit = (cutoff: any) => {
    setEditingId(cutoff.id);
    setFormData({
      postal_center_id: cutoff.postal_center_id,
      cutoff_time: cutoff.cutoff_time,
      timezone: cutoff.timezone,
      working_hours_start: cutoff.working_hours_start,
      working_hours_end: cutoff.working_hours_end,
      working_days: cutoff.working_days,
    });
    setIsEditing(true);
  };

  const handleDelete = async (id: number) => {
    if (confirm(t('cutoff_times.confirm_delete'))) {
      await deleteCutoff(id);
    }
  };

  const resetForm = () => {
    setFormData({
      postal_center_id: '',
      cutoff_time: '18:00',
      timezone: 'UTC',
      working_hours_start: '09:00',
      working_hours_end: '18:00',
      working_days: [1, 2, 3, 4, 5],
    });
  };

  const toggleWorkingDay = (day: number) => {
    setFormData((prev) => ({
      ...prev,
      working_days: prev.working_days.includes(day)
        ? prev.working_days.filter((d) => d !== day)
        : [...prev.working_days, day].sort(),
    }));
  };

  if (loading) {
    return <div className="flex items-center justify-center h-64">{t('common.loading')}</div>;
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-3 bg-blue-100 rounded-lg">
            <Clock className="w-6 h-6 text-blue-600" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{t('cutoff_times.title')}</h1>
            <p className="text-sm text-gray-600">{t('cutoff_times.description')}</p>
          </div>
        </div>
        <button
          onClick={() => setIsEditing(true)}
          className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 flex items-center gap-2"
        >
          <Plus className="w-4 h-4" />
          {t('cutoff_times.add_cutoff')}
        </button>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">{error}</div>
      )}

      {/* Cutoffs Table */}
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('cutoff_times.table.center')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('cutoff_times.table.cutoff_time')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('cutoff_times.table.working_hours')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('cutoff_times.table.working_days')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('cutoff_times.table.timezone')}
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                {t('common.actions')}
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {cutoffs.map((cutoff) => (
              <tr key={cutoff.id}>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {cutoff.postal_center_code}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {cutoff.cutoff_time}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {cutoff.working_hours_start} - {cutoff.working_hours_end}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {cutoff.working_days.join(', ')}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {cutoff.timezone}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <button
                    onClick={() => handleEdit(cutoff)}
                    className="text-blue-600 hover:text-blue-900 mr-4"
                  >
                    <Edit className="w-4 h-4" />
                  </button>
                  <button
                    onClick={() => handleDelete(cutoff.id)}
                    className="text-red-600 hover:text-red-900"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Edit Modal */}
      {isEditing && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg p-6 w-full max-w-2xl">
            <h2 className="text-xl font-bold mb-4">
              {editingId ? t('cutoff_times.edit_cutoff') : t('cutoff_times.add_cutoff')}
            </h2>

            <div className="space-y-4">
              {/* Postal Center */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  {t('cutoff_times.form.postal_center')}
                </label>
                <input
                  type="text"
                  value={formData.postal_center_id}
                  onChange={(e) => setFormData({ ...formData, postal_center_id: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                />
              </div>

              {/* Cut-off Time */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  {t('cutoff_times.form.cutoff_time')}
                </label>
                <input
                  type="time"
                  value={formData.cutoff_time}
                  onChange={(e) => setFormData({ ...formData, cutoff_time: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                />
              </div>

              {/* Working Hours */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    {t('cutoff_times.form.working_hours_start')}
                  </label>
                  <input
                    type="time"
                    value={formData.working_hours_start}
                    onChange={(e) =>
                      setFormData({ ...formData, working_hours_start: e.target.value })
                    }
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    {t('cutoff_times.form.working_hours_end')}
                  </label>
                  <input
                    type="time"
                    value={formData.working_hours_end}
                    onChange={(e) =>
                      setFormData({ ...formData, working_hours_end: e.target.value })
                    }
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  />
                </div>
              </div>

              {/* Working Days */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t('cutoff_times.form.working_days')}
                </label>
                <div className="flex gap-2">
                  {[1, 2, 3, 4, 5, 6, 7].map((day) => (
                    <button
                      key={day}
                      onClick={() => toggleWorkingDay(day)}
                      className={`px-3 py-2 rounded-lg border ${
                        formData.working_days.includes(day)
                          ? 'bg-blue-600 text-white border-blue-600'
                          : 'bg-white text-gray-700 border-gray-300'
                      }`}
                    >
                      {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day - 1]}
                    </button>
                  ))}
                </div>
              </div>

              {/* Timezone */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  {t('cutoff_times.form.timezone')}
                </label>
                <input
                  type="text"
                  value={formData.timezone}
                  onChange={(e) => setFormData({ ...formData, timezone: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                />
              </div>
            </div>

            <div className="flex justify-end gap-2 mt-6">
              <button
                onClick={() => {
                  setIsEditing(false);
                  setEditingId(null);
                  resetForm();
                }}
                className="px-4 py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 flex items-center gap-2"
              >
                <X className="w-4 h-4" />
                {t('common.cancel')}
              </button>
              <button
                onClick={handleSave}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 flex items-center gap-2"
              >
                <Save className="w-4 h-4" />
                {t('common.save')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
