import React, { useState } from 'react';
import { Search, Edit2, Trash2, Save, X } from 'lucide-react';
import type { CityClassification } from '@/hooks/useAccountReportingConfig';

import { useTranslation } from '@/hooks/useTranslation';
interface CityClassificationTableProps {
  classifications: CityClassification[];
  onUpdate: (cityId: string, classification: 'capital' | 'major' | 'minor') => Promise<{ success: boolean; error?: Error }>;
  onDelete: (cityId: string) => Promise<{ success: boolean; error?: Error }>;
}

export function CityClassificationTable({
  classifications,
  onUpdate,
  onDelete
}: CityClassificationTableProps) {
  const { t } = useTranslation();
  const [searchTerm, setSearchTerm] = useState('');
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editValue, setEditValue] = useState<'capital' | 'major' | 'minor'>('minor');

  const filteredClassifications = classifications.filter(c =>
    c.cityName.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const handleEdit = (classification: CityClassification) => {
    setEditingId(classification.cityId);
    setEditValue(classification.classification);
  };

  const handleSave = async (cityId: string) => {
    const result = await onUpdate(cityId, editValue);
    if (result.success) {
      setEditingId(null);
    } else {
      alert(`Error: ${result.error?.message}`);
    }
  };

  const handleCancel = () => {
    setEditingId(null);
  };

  const handleDelete = async (cityId: string) => {
    if (confirm('Are you sure you want to delete this classification?')) {
      const result = await onDelete(cityId);
      if (!result.success) {
        alert(`Error: ${result.error?.message}`);
      }
    }
  };

  const getClassificationBadge = (classification: string) => {
    const badges = {
      capital: 'bg-purple-100 text-purple-800',
      major: 'bg-blue-100 text-blue-800',
      minor: 'bg-gray-100 text-gray-800'
    };
    return badges[classification as keyof typeof badges] || badges.minor;
  };

  return (
    <div className="space-y-4">
      <div className="relative">
        <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-5 h-5" />
        <input
          type="text"
          placeholder="Search cities..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
        />
      </div>

      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                City Name
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Classification
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {filteredClassifications.length === 0 ? (
              <tr>
                <td colSpan={3} className="px-6 py-8 text-center text-gray-500">
                  No city classifications found
                </td>
              </tr>
            ) : (
              filteredClassifications.map((classification) => (
                <tr key={classification.cityId} className="hover:bg-gray-50">
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    {classification.cityName}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm">
                    {editingId === classification.cityId ? (
                      <select
                        value={editValue}
                        onChange={(e) => setEditValue(e.target.value as 'capital' | 'major' | 'minor')}
                        className="border border-gray-300 rounded px-2 py-1 text-sm focus:ring-2 focus:ring-blue-500"
                      >
                        <option value="capital">{t('settings.capital')}</option>
                        <option value="major">{t('settings.major')}</option>
                        <option value="minor">{t('settings.minor')}</option>
                      </select>
                    ) : (
                      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium capitalize ${getClassificationBadge(classification.classification)}`}>
                        {classification.classification}
                      </span>
                    )}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    {editingId === classification.cityId ? (
                      <div className="flex items-center justify-end gap-2">
                        <button
                          onClick={() => handleSave(classification.cityId)}
                          className="text-green-600 hover:text-green-900"
                          title={t('common.save')}
                        >
                          <Save className="w-4 h-4" />
                        </button>
                        <button
                          onClick={handleCancel}
                          className="text-gray-600 hover:text-gray-900"
                          title={t('common.cancel')}
                        >
                          <X className="w-4 h-4" />
                        </button>
                      </div>
                    ) : (
                      <div className="flex items-center justify-end gap-2">
                        <button
                          onClick={() => handleEdit(classification)}
                          className="text-blue-600 hover:text-blue-900"
                          title={t('common.edit')}
                        >
                          <Edit2 className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => handleDelete(classification.cityId)}
                          className="text-red-600 hover:text-red-900"
                          title={t('common.delete')}
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <div className="text-sm text-gray-500">
        Showing {filteredClassifications.length} of {classifications.length} classifications
      </div>
    </div>
  );
}
