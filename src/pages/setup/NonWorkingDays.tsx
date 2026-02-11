import { useState } from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import { useNonWorkingDays } from '@/hooks/useNonWorkingDays';
import { Calendar, Plus, Edit, Trash2, Save, X } from 'lucide-react';

export default function NonWorkingDays() {
  const { t } = useTranslation();
  const {
    nonWorkingDays,
    loading,
    error,
    createNonWorkingDay,
    updateNonWorkingDay,
    deleteNonWorkingDay,
  } = useNonWorkingDays();

  const [isEditing, setIsEditing] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [formData, setFormData] = useState({
    date: '',
    name: '',
    description: '',
    applies_to_all_centers: true,
    day_type: 'holiday',
    is_recurring: false,
  });

  const handleSave = async () => {
    if (editingId) {
      await updateNonWorkingDay(editingId, formData);
    } else {
      await createNonWorkingDay(formData);
    }
    setIsEditing(false);
    setEditingId(null);
    resetForm();
  };

  const handleEdit = (day: any) => {
    setEditingId(day.id);
    setFormData({
      date: day.date,
      name: day.name,
      description: day.description || '',
      applies_to_all_centers: day.applies_to_all_centers,
      day_type: day.day_type,
      is_recurring: day.is_recurring,
    });
    setIsEditing(true);
  };

  const handleDelete = async (id: number) => {
    if (confirm(t('non_working_days.confirm_delete'))) {
      await deleteNonWorkingDay(id);
    }
  };

  const resetForm = () => {
    setFormData({
      date: '',
      name: '',
      description: '',
      applies_to_all_centers: true,
      day_type: 'holiday',
      is_recurring: false,
    });
  };

  if (loading) {
    return <div className="flex items-center justify-center h-64">{t('common.loading')}</div>;
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-3 bg-green-100 rounded-lg">
            <Calendar className="w-6 h-6 text-green-600" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{t('non_working_days.title')}</h1>
            <p className="text-sm text-gray-600">{t('non_working_days.description')}</p>
          </div>
        </div>
        <button
          onClick={() => setIsEditing(true)}
          className="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 flex items-center gap-2"
        >
          <Plus className="w-4 h-4" />
          {t('non_working_days.add_day')}
        </button>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">{error}</div>
      )}

      {/* Non-Working Days Table */}
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('non_working_days.table.date')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('non_working_days.table.name')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('non_working_days.table.type')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('non_working_days.table.scope')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('non_working_days.table.recurring')}
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                {t('common.actions')}
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {nonWorkingDays.map((day) => (
              <tr key={day.id}>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{day.date}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{day.name}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <span
                    className={`px-2 py-1 rounded-full text-xs ${
                      day.day_type === 'holiday'
                        ? 'bg-green-100 text-green-800'
                        : 'bg-red-100 text-red-800'
                    }`}
                  >
                    {day.day_type}
                  </span>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {day.applies_to_all_centers ? t('non_working_days.all_centers') : t('non_working_days.specific_centers')}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {day.is_recurring ? t('common.yes') : t('common.no')}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <button
                    onClick={() => handleEdit(day)}
                    className="text-blue-600 hover:text-blue-900 mr-4"
                  >
                    <Edit className="w-4 h-4" />
                  </button>
                  <button
                    onClick={() => handleDelete(day.id)}
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
              {editingId ? t('non_working_days.edit_day') : t('non_working_days.add_day')}
            </h2>

            <div className="space-y-4">
              {/* Date */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  {t('non_working_days.form.date')}
                </label>
                <input
                  type="date"
                  value={formData.date}
                  onChange={(e) => setFormData({ ...formData, date: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                />
              </div>

              {/* Name */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  {t('non_working_days.form.name')}
                </label>
                <input
                  type="text"
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  placeholder={t('non_working_days.form.name_placeholder')}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                />
              </div>

              {/* Description */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  {t('non_working_days.form.description')}
                </label>
                <textarea
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  rows={3}
                />
              </div>

              {/* Type */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  {t('non_working_days.form.type')}
                </label>
                <select
                  value={formData.day_type}
                  onChange={(e) => setFormData({ ...formData, day_type: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                >
                  <option value="holiday">Holiday</option>
                  <option value="closure">Closure</option>
                  <option value="maintenance">Maintenance</option>
                </select>
              </div>

              {/* Applies to all centers */}
              <div className="flex items-center">
                <input
                  type="checkbox"
                  checked={formData.applies_to_all_centers}
                  onChange={(e) =>
                    setFormData({ ...formData, applies_to_all_centers: e.target.checked })
                  }
                  className="mr-2"
                />
                <label className="text-sm font-medium text-gray-700">
                  {t('non_working_days.form.applies_to_all')}
                </label>
              </div>

              {/* Recurring */}
              <div className="flex items-center">
                <input
                  type="checkbox"
                  checked={formData.is_recurring}
                  onChange={(e) => setFormData({ ...formData, is_recurring: e.target.checked })}
                  className="mr-2"
                />
                <label className="text-sm font-medium text-gray-700">
                  {t('non_working_days.form.recurring')}
                </label>
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
                className="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 flex items-center gap-2"
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
