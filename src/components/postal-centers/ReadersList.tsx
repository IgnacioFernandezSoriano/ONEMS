import React, { useState, useMemo } from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import { Pencil, Trash2, Eye, Power, PowerOff } from 'lucide-react';
import { Reader } from '../../lib/types_postal_centers';
import { usePostalCenters } from '../../hooks/usePostalCenters';
import { ReaderForm } from './ReaderForm';
import { ReaderStatusBadge } from './ReaderStatusBadge';

interface ReadersListProps {
  accountId: string;
}

export function ReadersList({ accountId }: ReadersListProps) {
  const { t } = useTranslation();
  const {
    readers,
    postalCenters,
    loading,
    deleteReader,
    updateReader,
  } = usePostalCenters();

  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCenter, setSelectedCenter] = useState<string>('all');
  const [selectedType, setSelectedType] = useState<string>('all');
  const [selectedStatus, setSelectedStatus] = useState<string>('all');
  const [isFormOpen, setIsFormOpen] = useState(false);
  const [editingReader, setEditingReader] = useState<Reader | undefined>();
  const [selectedReaders, setSelectedReaders] = useState<Set<string>>(new Set());
  const [currentPage, setCurrentPage] = useState(1);
  const itemsPerPage = 25;

  // Filter readers
  const filteredReaders = useMemo(() => {
    return readers.filter((reader) => {
      const matchesSearch =
        reader.reader_id.toLowerCase().includes(searchTerm.toLowerCase()) ||
        reader.name.toLowerCase().includes(searchTerm.toLowerCase());

      const matchesCenter =
        selectedCenter === 'all' ||
        (selectedCenter === 'unassigned' && !reader.postal_center_id) ||
        reader.postal_center_id?.toString() === selectedCenter;

      const matchesType =
        selectedType === 'all' || reader.type === selectedType;

      const matchesStatus =
        selectedStatus === 'all' ||
        (selectedStatus === 'active' && reader.is_active) ||
        (selectedStatus === 'inactive' && !reader.is_active);

      return matchesSearch && matchesCenter && matchesType && matchesStatus;
    });
  }, [readers, searchTerm, selectedCenter, selectedType, selectedStatus]);

  // Pagination
  const totalPages = Math.ceil(filteredReaders.length / itemsPerPage);
  const paginatedReaders = filteredReaders.slice(
    (currentPage - 1) * itemsPerPage,
    currentPage * itemsPerPage
  );

  const handleEdit = (reader: Reader) => {
    setEditingReader(reader);
    setIsFormOpen(true);
  };

  const handleDelete = async (readerId: number) => {
    if (window.confirm(t('readers.confirm_delete'))) {
      await deleteReader(readerId.toString());
    }
  };

  const handleToggleActive = async (reader: Reader) => {
    await updateReader(reader.id, { is_active: !reader.is_active });
  };

  const handleSelectReader = (readerId: string) => {
    const newSelected = new Set(selectedReaders);
    if (newSelected.has(readerId)) {
      newSelected.delete(readerId);
    } else {
      newSelected.add(readerId);
    }
    setSelectedReaders(newSelected);
  };

  const handleSelectAll = () => {
    if (selectedReaders.size === paginatedReaders.length) {
      setSelectedReaders(new Set());
    } else {
      setSelectedReaders(new Set(paginatedReaders.map((r) => r.id)));
    }
  };

  const handleBulkActivate = async () => {
    for (const readerId of selectedReaders) {
      await updateReader(readerId, { is_active: true });
    }
    setSelectedReaders(new Set());
  };

  const handleBulkDeactivate = async () => {
    for (const readerId of selectedReaders) {
      await updateReader(readerId, { is_active: false });
    }
    setSelectedReaders(new Set());
  };

  const handleBulkDelete = async () => {
    if (window.confirm(t('readers.confirm_bulk_delete', { count: selectedReaders.size }))) {
      for (const readerId of selectedReaders) {
        await deleteReader(readerId.toString());
      }
      setSelectedReaders(new Set());
    }
  };

  const getCenterName = (centerId: string | null) => {
    if (!centerId) return t('readers.unassigned');
    const center = postalCenters.find((c) => c.id === centerId);
    return center?.name || '-';
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">{t('common.loading')}</div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">{t('readers.title')}</h2>
          <p className="text-sm text-gray-500 mt-1">
            {t('readers.total_count', { count: filteredReaders.length })}
          </p>
        </div>
        <button
          onClick={() => {
            setEditingReader(undefined);
            setIsFormOpen(true);
          }}
          className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
        >
          {t('readers.add_new')}
        </button>
      </div>

      {/* Filters */}
      <div className="bg-white p-4 rounded-lg shadow space-y-4">
        {/* Search */}
        <div>
          <input
            type="text"
            placeholder={t('readers.search_placeholder')}
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
        </div>

        {/* Filter Row */}
        <div className="flex items-end gap-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 flex-1">
          {/* Postal Center Filter */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              {t('readers.filter_by_center')}
            </label>
            <select
              value={selectedCenter}
              onChange={(e) => setSelectedCenter(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="all">{t('common.all')}</option>
              <option value="unassigned">{t('readers.unassigned')}</option>
              {postalCenters.map((center) => (
                <option key={center.id} value={center.id.toString()}>
                  {center.name}
                </option>
              ))}
            </select>
          </div>

          {/* Type Filter */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              {t('readers.filter_by_type')}
            </label>
            <select
              value={selectedType}
              onChange={(e) => setSelectedType(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="all">{t('common.all')}</option>
              <option value="Entry">{t('readers.type_entry')}</option>
              <option value="Exit">{t('readers.type_exit')}</option>
              <option value="Mixed">{t('readers.type_mixed')}</option>
            </select>
          </div>

          {/* Status Filter */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              {t('readers.filter_by_status')}
            </label>
            <select
              value={selectedStatus}
              onChange={(e) => setSelectedStatus(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="all">{t('common.all')}</option>
              <option value="active">{t('common.active')}</option>
              <option value="inactive">{t('common.inactive')}</option>
            </select>
          </div>
          </div>
          
          {/* Reset Button */}
          <button
            onClick={() => {
              setSearchTerm('');
              setSelectedCenter('all');
              setSelectedType('all');
              setSelectedStatus('all');
            }}
            className="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50 text-sm font-medium text-gray-700 whitespace-nowrap"
          >
            {t('common.reset_filters')}
          </button>
        </div>
      </div>

      {/* Bulk Actions */}
      {selectedReaders.size > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 flex items-center justify-between">
          <span className="text-sm text-blue-900">
            {t('readers.selected_count', { count: selectedReaders.size })}
          </span>
          <div className="flex gap-2">
            <button
              onClick={handleBulkActivate}
              className="px-3 py-1 bg-green-600 text-white text-sm rounded hover:bg-green-700 flex items-center gap-1"
            >
              <Power className="w-4 h-4" />
              {t('readers.activate')}
            </button>
            <button
              onClick={handleBulkDeactivate}
              className="px-3 py-1 bg-yellow-600 text-white text-sm rounded hover:bg-yellow-700 flex items-center gap-1"
            >
              <PowerOff className="w-4 h-4" />
              {t('readers.deactivate')}
            </button>
            <button
              onClick={handleBulkDelete}
              className="px-3 py-1 bg-red-600 text-white text-sm rounded hover:bg-red-700 flex items-center gap-1"
            >
              <Trash2 className="w-4 h-4" />
              {t('common.delete')}
            </button>
          </div>
        </div>
      )}

      {/* Table */}
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left">
                  <input
                    type="checkbox"
                    checked={selectedReaders.size === paginatedReaders.length && paginatedReaders.length > 0}
                    onChange={handleSelectAll}
                    className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                  />
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('readers.reader_id')}
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('readers.name')}
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('readers.type')}
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('readers.postal_center')}
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('readers.gap_threshold')}
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('readers.status')}
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('common.actions')}
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {paginatedReaders.map((reader) => (
                <tr key={reader.id} className="hover:bg-gray-50">
                  <td className="px-6 py-4">
                    <input
                      type="checkbox"
                      checked={selectedReaders.has(reader.id)}
                      onChange={() => handleSelectReader(reader.id)}
                      className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    {reader.reader_id}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {reader.name}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {t(`readers.type_${reader.type.toLowerCase()}`)}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {getCenterName(reader.postal_center_id)}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {reader.type === 'Mixed'
                      ? reader.mixed_reader_gap_minutes
                        ? `${reader.mixed_reader_gap_minutes} min`
                        : t('readers.inherited')
                      : '-'}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <ReaderStatusBadge reader={reader} accountId={accountId} />
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => handleEdit(reader)}
                        className="text-blue-600 hover:text-blue-900"
                        title={t('common.edit')}
                      >
                        <Pencil className="w-4 h-4" />
                      </button>
                      <button
                        onClick={() => handleToggleActive(reader)}
                        className={`${
                          reader.is_active ? 'text-yellow-600 hover:text-yellow-900' : 'text-green-600 hover:text-green-900'
                        }`}
                        title={reader.is_active ? t('readers.deactivate') : t('readers.activate')}
                      >
                        {reader.is_active ? <PowerOff className="w-4 h-4" /> : <Power className="w-4 h-4" />}
                      </button>
                      <button
                        onClick={() => handleDelete(parseInt(reader.id))}
                        className="text-red-600 hover:text-red-900"
                        title={t('common.delete')}
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
        {totalPages > 1 && (
          <div className="bg-gray-50 px-6 py-3 flex items-center justify-between border-t border-gray-200">
            <div className="text-sm text-gray-700">
              {t('common.showing')} {(currentPage - 1) * itemsPerPage + 1} - {Math.min(currentPage * itemsPerPage, filteredReaders.length)} {t('common.of')} {filteredReaders.length}
            </div>
            <div className="flex gap-2">
              <button
                onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
                disabled={currentPage === 1}
                className="px-3 py-1 border border-gray-300 rounded text-sm disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gray-100"
              >
                {t('common.previous')}
              </button>
              <span className="px-3 py-1 text-sm text-gray-700">
                {currentPage} / {totalPages}
              </span>
              <button
                onClick={() => setCurrentPage((p) => Math.min(totalPages, p + 1))}
                disabled={currentPage === totalPages}
                className="px-3 py-1 border border-gray-300 rounded text-sm disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gray-100"
              >
                {t('common.next')}
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Empty State */}
      {filteredReaders.length === 0 && (
        <div className="bg-white rounded-lg shadow p-12 text-center">
          <p className="text-gray-500">{t('readers.no_readers_found')}</p>
        </div>
      )}

      {/* Form Modal */}
      {isFormOpen && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg max-w-2xl w-full max-h-[90vh] overflow-y-auto">
            <ReaderForm
              accountId={accountId}
              reader={editingReader}
              onSubmit={async (data) => {
                if (editingReader) {
                  await updateReader(editingReader.id, data);
                } else {
                  // Create logic would go here
                }
                setIsFormOpen(false);
                setEditingReader(undefined);
              }}
              onCancel={() => {
                setIsFormOpen(false);
                setEditingReader(undefined);
              }}
            />
          </div>
        </div>
      )}
    </div>
  );
}
