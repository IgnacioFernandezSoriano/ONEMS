import { useState } from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import { useCutoffTimes, CutoffTime } from '@/hooks/useCutoffTimes';
import { Clock, Edit, Save, X } from 'lucide-react';

export default function CutoffTimes() {
  const { t } = useTranslation();
  const {
    cutoffs,
    loading,
    error,
    updateCutoff,
  } = useCutoffTimes();

  const [editingId, setEditingId] = useState<string | null>(null);
  const [formData, setFormData] = useState<Partial<CutoffTime>>({});

  const handleEdit = (cutoff: CutoffTime) => {
    setEditingId(cutoff.id);
    setFormData({
      cutoff_time: cutoff.cutoff_time,
      opening_hour: cutoff.opening_hour,
      working_hours_end: cutoff.working_hours_end,
      working_days: cutoff.working_days,
      timezone: cutoff.timezone,
    });
  };

  const handleSave = async () => {
    if (editingId) {
      await updateCutoff(editingId, formData);
      setEditingId(null);
      setFormData({});
    }
  };

  const handleCancel = () => {
    setEditingId(null);
    setFormData({});
  };

  const toggleWorkingDay = (day: string) => {
    setFormData((prev) => {
      const days = prev.working_days || [];
      return {
        ...prev,
        working_days: days.includes(day)
          ? days.filter((d) => d !== day)
          : [...days, day],
      };
    });
  };

  const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const dayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  if (loading) {
    return <div className="flex items-center justify-center h-64">{t('common.loading')}</div>;
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-3">
        <div className="p-3 bg-blue-100 rounded-lg">
          <Clock className="w-6 h-6 text-blue-600" />
        </div>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">{t('cutoff_times.title')}</h1>
          <p className="text-sm text-gray-600">{t('cutoff_times.description')}</p>
        </div>
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
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="text-sm font-medium text-gray-900">{cutoff.postal_center_code}</div>
                  <div className="text-sm text-gray-500">{cutoff.postal_center_name}</div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {cutoff.cutoff_time}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {cutoff.opening_hour} - {cutoff.working_hours_end}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {cutoff.working_days.map(d => d.substring(0, 3)).join(', ')}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {cutoff.timezone}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <button
                    onClick={() => handleEdit(cutoff)}
                    className="text-blue-600 hover:text-blue-900"
                  >
                    <Edit className="w-4 h-4" />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Edit Modal */}
      {editingId && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg p-6 w-full max-w-2xl">
            <h2 className="text-xl font-bold mb-4">{t('cutoff_times.edit_cutoff')}</h2>

            <div className="space-y-4">
              {/* Cut-off Time */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  {t('cutoff_times.form.cutoff_time')}
                </label>
                <input
                  type="time"
                  value={formData.cutoff_time || ''}
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
                    value={formData.opening_hour || ''}
                    onChange={(e) => setFormData({ ...formData, opening_hour: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    {t('cutoff_times.form.working_hours_end')}
                  </label>
                  <input
                    type="time"
                    value={formData.working_hours_end || ''}
                    onChange={(e) => setFormData({ ...formData, working_hours_end: e.target.value })}
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
                  {dayNames.map((day, idx) => (
                    <button
                      key={day}
                      onClick={() => toggleWorkingDay(day)}
                      className={`px-3 py-2 rounded-lg border ${
                        (formData.working_days || []).includes(day)
                          ? 'bg-blue-600 text-white border-blue-600'
                          : 'bg-white text-gray-700 border-gray-300'
                      }`}
                    >
                      {dayAbbr[idx]}
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
                  value={formData.timezone || ''}
                  onChange={(e) => setFormData({ ...formData, timezone: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  placeholder="UTC, Europe/Madrid, etc."
                />
              </div>
            </div>

            <div className="flex justify-end gap-2 mt-6">
              <button
                onClick={handleCancel}
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
