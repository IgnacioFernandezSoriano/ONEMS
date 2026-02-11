import { useState } from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import { useNonWorkingDays } from '@/hooks/useNonWorkingDays';
import { usePostalCenters } from '@/hooks/usePostalCenters';
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

  const { postalCenters } = usePostalCenters();

  const [isEditing, setIsEditing] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [formData, setFormData] = useState({
    date: '',
    reason: '',
    type: 'holiday',
    postal_center_id: null as string | null,
  });

  const resetForm = () => {
    setFormData({
      date: '',
      reason: '',
      type: 'holiday',
      postal_center_id: null,
    });
  };

  const handleSave = async () => {
    try {
      if (editingId) {
        await updateNonWorkingDay(editingId, formData);
      } else {
        await createNonWorkingDay(formData);
      }
      setIsEditing(false);
      setEditingId(null);
      resetForm();
    } catch (err) {
      console.error('Error saving non-working day:', err);
    }
  };

  const handleEdit = (day: any) => {
    setEditingId(day.id);
    setFormData({
      date: day.date,
      reason: day.reason,
      type: day.type,
      postal_center_id: day.postal_center_id,
    });
    setIsEditing(true);
  };

  const handleDelete = async (id: number) => {
    if (confirm(t('non_working_days.confirm_delete'))) {
      await deleteNonWorkingDay(id);
    }
  };

  const handleCancel = () => {
    setIsEditing(false);
    setEditingId(null);
    resetForm();
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">{t('common.loading')}</div>
      </div>
    );
  }

  return (
    <div className="p-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <Calendar className="w-8 h-8 text-purple-600" />
          <div>
            <h1 className="text-2xl font-bold text-gray-900">
              {t('non_working_days.title')}
            </h1>
            <p className="text-sm text-gray-500">
              {t('non_working_days.description')}
            </p>
          </div>
        </div>
        <button
          onClick={() => setIsEditing(true)}
          className="flex items-center gap-2 px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700"
        >
          <Plus className="w-5 h-5" />
          {t('non_working_days.add')}
        </button>
      </div>

      {/* Error */}
      {error && (
        <div className="mb-4 p-4 bg-red-50 border border-red-200 rounded-lg text-red-700">
          {error}
        </div>
      )}

      {/* Form */}
      {isEditing && (
        <div className="mb-6 p-6 bg-white border border-gray-200 rounded-lg">
          <h3 className="text-lg font-semibold mb-4">
            {editingId ? t('non_working_days.edit') : t('non_working_days.add')}
          </h3>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                {t('non_working_days.date')}
              </label>
              <input
                type="date"
                value={formData.date}
                onChange={(e) => setFormData({ ...formData, date: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                {t('non_working_days.type')}
              </label>
              <select
                value={formData.type}
                onChange={(e) => setFormData({ ...formData, type: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg"
              >
                <option value="holiday">{t('non_working_days.type_holiday')}</option>
                <option value="closure">{t('non_working_days.type_closure')}</option>
                <option value="maintenance">{t('non_working_days.type_maintenance')}</option>
              </select>
            </div>
            <div className="col-span-2">
              <label className="block text-sm font-medium text-gray-700 mb-1">
                {t('non_working_days.reason')}
              </label>
              <input
                type="text"
                value={formData.reason}
                onChange={(e) => setFormData({ ...formData, reason: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                placeholder={t('non_working_days.reason_placeholder')}
              />
            </div>
            <div className="col-span-2">
              <label className="block text-sm font-medium text-gray-700 mb-1">
                {t('non_working_days.postal_center')}
              </label>
              <select
                value={formData.postal_center_id || ''}
                onChange={(e) =>
                  setFormData({
                    ...formData,
                    postal_center_id: e.target.value || null,
                  })
                }
                className="w-full px-3 py-2 border border-gray-300 rounded-lg"
              >
                <option value="">{t('non_working_days.all_centers')}</option>
                {postalCenters.map((center) => (
                  <option key={center.id} value={center.id}>
                    {center.code} - {center.name}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <div className="flex gap-2 mt-4">
            <button
              onClick={handleSave}
              className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700"
            >
              <Save className="w-4 h-4" />
              {t('common.save')}
            </button>
            <button
              onClick={handleCancel}
              className="flex items-center gap-2 px-4 py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300"
            >
              <X className="w-4 h-4" />
              {t('common.cancel')}
            </button>
          </div>
        </div>
      )}

      {/* Table */}
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('non_working_days.date')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('non_working_days.reason')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('non_working_days.type')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('non_working_days.postal_center')}
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                {t('common.actions')}
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {nonWorkingDays.length === 0 ? (
              <tr>
                <td colSpan={5} className="px-6 py-8 text-center text-gray-500">
                  {t('non_working_days.no_data')}
                </td>
              </tr>
            ) : (
              nonWorkingDays.map((day) => (
                <tr key={day.id} className="hover:bg-gray-50">
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {new Date(day.date).toLocaleDateString()}
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-900">{day.reason}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm">
                    <span
                      className={`px-2 py-1 rounded-full text-xs ${
                        day.type === 'holiday'
                          ? 'bg-blue-100 text-blue-800'
                          : day.type === 'closure'
                          ? 'bg-red-100 text-red-800'
                          : 'bg-yellow-100 text-yellow-800'
                      }`}
                    >
                      {t(`non_working_days.type_${day.type}`)}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-500">
                    {day.postal_center_id
                      ? postalCenters.find((c) => c.id === day.postal_center_id)?.name ||
                        day.postal_center_id
                      : t('non_working_days.all_centers')}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <button
                      onClick={() => handleEdit(day)}
                      className="text-purple-600 hover:text-purple-900 mr-3"
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
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
