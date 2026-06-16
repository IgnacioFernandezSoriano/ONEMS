import React, { useState, useMemo } from 'react';
import { Plus, MapPin, History, Edit, Trash2, Navigation } from 'lucide-react';
import { Button } from '@/components/common/Button';
import { ReaderForm } from '@/components/postal-centers/ReaderForm';
import { ReaderLocationTimeline } from '@/components/mobile-readers/ReaderLocationTimeline';
import { AssignReaderModal } from '@/components/mobile-readers/AssignReaderModal';
import { ReadersFilters, ReadersFiltersState } from '@/components/mobile-readers/ReadersFilters';
import { useMobileReaders } from '@/hooks/useMobileReaders';
import { useReaderLocationHistory } from '@/hooks/useReaderLocationHistory';
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId';
import { useTranslation } from '@/hooks/useTranslation';
import type { ReaderFormData } from '@/lib/types_postal_centers';

export default function ReadersManagement() {
  const { t } = useTranslation();
  // Superadmin: usa la cuenta seleccionada en el sidebar (DEMO2, etc.).
  // Usuario normal: su propia cuenta. Antes leía profile.account_id directo,
  // que es null para superadmin -> "No account ID provided" al crear lector.
  const accountId = useEffectiveAccountId() || undefined;

  const { readers, allReaders, createMobileReader, updateReader, deleteReader, refetch } =
    useMobileReaders(accountId);

  const [showCreateForm, setShowCreateForm] = useState(false);
  const [showEditForm, setShowEditForm] = useState(false);
  const [selectedReaderId, setSelectedReaderId] = useState<string | null>(null);
  const [showAssignModal, setShowAssignModal] = useState(false);
  const [showHistory, setShowHistory] = useState<string | null>(null);
  const [filters, setFilters] = useState<ReadersFiltersState>({
    search: '',
    carrier_id: '',
    postal_center_id: '',
    reader_type: '',
    assignment_status: '',
    mobility_status: '',
  });

  const { assignToCenter } = useReaderLocationHistory(selectedReaderId);

  // Apply filters
  const filteredReaders = useMemo(() => {
    return readers.filter((reader) => {
      // Search filter
      if (filters.search) {
        const searchLower = filters.search.toLowerCase();
        const matchesSearch =
          reader.reader_name.toLowerCase().includes(searchLower) ||
          reader.reader_code.toLowerCase().includes(searchLower);
        if (!matchesSearch) return false;
      }

      // Carrier filter (filter by centers belonging to carrier)
      if (filters.carrier_id && reader.carrier_id !== filters.carrier_id) {
        return false;
      }

      // Postal Center filter
      if (filters.postal_center_id) {
        if (filters.postal_center_id === 'unassigned') {
          if (reader.current_center_id !== null) return false;
        } else {
          if (reader.current_center_id !== filters.postal_center_id) return false;
        }
      }

      // Reader Type filter
      if (filters.reader_type && reader.reader_type !== filters.reader_type) {
        return false;
      }

      // Assignment Status filter
      if (filters.assignment_status) {
        if (filters.assignment_status === 'assigned' && !reader.current_center_id) return false;
        if (filters.assignment_status === 'unassigned' && reader.current_center_id) return false;
      }

      // Mobility Status filter
      if (filters.mobility_status) {
        if (filters.mobility_status === 'mobile' && !reader.is_mobile) return false;
        if (filters.mobility_status === 'fixed' && reader.is_mobile) return false;
      }

      return true;
    });
  }, [readers, filters]);

  const selectedReader = readers.find((r) => r.reader_id === selectedReaderId);
  const selectedFullReader = allReaders.find((r) => r.id === selectedReaderId);

  const handleCreateReader = async (data: ReaderFormData) => {
    const result = await createMobileReader(data);
    if (result.success) {
      setShowCreateForm(false);
      refetch();
    } else {
      throw new Error(result.error);
    }
  };

  const handleUpdateReader = async (readerId: string, data: ReaderFormData) => {
    const result = await updateReader(readerId, data);
    if (result.success) {
      setShowEditForm(false);
      setSelectedReaderId(null);
      refetch();
    } else {
      throw new Error(result.error);
    }
  };

  const handleAssignReader = async (
    postalCenterId: string,
    assignedAt: string,
    unassignedAt: string | null,
    notes: string | null
  ) => {
    const result = await assignToCenter(postalCenterId, assignedAt, unassignedAt, notes);
    if (result.success) {
      setShowAssignModal(false);
      refetch();
    }
    return result;
  };

  const handleDeleteReader = async (readerId: string) => {
    if (!confirm(t('readers_management.confirm_delete'))) return;

    const result = await deleteReader(readerId);
    if (result.success) {
      refetch();
    }
  };

  const getReaderTypeColor = (type: string) => {
    switch (type) {
      case 'Entry':
        return 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400';
      case 'Exit':
        return 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400';
      case 'Mixed':
        return 'bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-400';
      default:
        return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300';
    }
  };

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">
          Readers Management
        </h1>
        <p className="text-gray-600 dark:text-gray-400">
          {t('readers_management.description')}
        </p>
      </div>

      {/* Actions */}
      <div className="mb-6 flex justify-between items-center">
        <div className="flex gap-2">
          <Button onClick={() => setShowCreateForm(true)}>
            <Plus className="w-4 h-4 mr-2" />
            {t('readers_management.create_reader')}
          </Button>
        </div>
        <div className="text-sm text-gray-600 dark:text-gray-400">
          {filteredReaders.length} {t('readers_management.showing')}
          {filteredReaders.length !== readers.length && (
            <> / {readers.length} {t('readers_management.total')}</>
          )}
        </div>
      </div>

      {/* Filters */}
      <div className="mb-6">
        <ReadersFilters onFilterChange={setFilters} />
      </div>

      {/* Create Form Modal */}
      {showCreateForm && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto p-6">
            <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">
              {t('readers_management.create_reader')}
            </h2>
            <ReaderForm
              accountId={accountId!}
              onSubmit={handleCreateReader}
              onCancel={() => setShowCreateForm(false)}
            />
          </div>
        </div>
      )}

      {/* Edit Form Modal */}
      {showEditForm && selectedFullReader && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto p-6">
            <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">
              {t('readers_management.edit_reader')}
            </h2>
            <ReaderForm
              accountId={accountId!}
              reader={selectedFullReader}
              onSubmit={(data) => handleUpdateReader(selectedFullReader.id, data)}
              onCancel={() => {
                setShowEditForm(false);
                setSelectedReaderId(null);
              }}
            />
          </div>
        </div>
      )}

      {/* Assign Modal */}
      {showAssignModal && selectedReader && (
        <AssignReaderModal
          readerId={selectedReader.reader_id}
          readerName={selectedReader.reader_name}
          currentCenterId={selectedReader.current_center_id}
          onAssign={handleAssignReader}
          onClose={() => setShowAssignModal(false)}
        />
      )}

      {/* Readers Table */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 overflow-hidden">
        {filteredReaders.length === 0 ? (
          <div className="text-center py-12">
            <MapPin className="w-12 h-12 text-gray-400 mx-auto mb-4" />
            <p className="text-gray-600 dark:text-gray-400">
              {t('readers_management.no_readers_found')}
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50 dark:bg-gray-700/50 border-b border-gray-200 dark:border-gray-700">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    {t('readers_management.reader_name')}
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    {t('readers_management.carrier')}
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    {t('readers_management.code')}
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    {t('readers_management.type')}
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    {t('readers_management.postal_center')}
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    {t('readers_management.status')}
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    {t('readers_management.assignments')}
                  </th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    {t('common.actions')}
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200 dark:divide-gray-700">
                {filteredReaders.map((reader) => (
                  <React.Fragment key={reader.reader_id}>
                  <tr className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    {/* Reader Name */}
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm font-medium text-gray-900 dark:text-white">
                        {reader.reader_name}
                      </div>
                    </td>

                    {/* Carrier */}
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm text-gray-500 dark:text-gray-400">
                        {reader.carrier_name || '-'}
                      </div>
                    </td>

                    {/* Code */}
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm text-gray-500 dark:text-gray-400">
                        {reader.reader_code}
                      </div>
                    </td>

                    {/* Type */}
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span
                        className={`px-2 py-1 text-xs font-medium rounded ${getReaderTypeColor(
                          reader.reader_type
                        )}`}
                      >
                        {reader.reader_type}
                      </span>
                    </td>

                    {/* Postal Center */}
                    <td className="px-6 py-4">
                      {reader.current_center_name ? (
                        <div>
                          <div className="text-sm text-gray-900 dark:text-white">
                            {reader.current_center_name}
                          </div>
                          {reader.assigned_since && (
                            <div className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                              {t('readers_management.since')}{' '}
                              {new Date(reader.assigned_since).toLocaleDateString('es-ES')}
                            </div>
                          )}
                        </div>
                      ) : (
                        <span className="text-sm text-gray-500 dark:text-gray-400 italic">
                          {t('readers_management.unassigned')}
                        </span>
                      )}
                    </td>

                    {/* Status */}
                    <td className="px-6 py-4 whitespace-nowrap">
                      {reader.is_mobile ? (
                        <span className="px-2 py-1 bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400 text-xs font-medium rounded">
                          {t('readers_management.has_history')}
                        </span>
                      ) : (
                        <span className="px-2 py-1 bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-400 text-xs font-medium rounded">
                          {t('readers_management.no_history')}
                        </span>
                      )}
                    </td>

                    {/* Assignments */}
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm text-gray-900 dark:text-white">
                        {reader.total_assignments}
                      </div>
                    </td>

                    {/* Actions */}
                    <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      <div className="flex items-center justify-end gap-2">
                        <button
                          onClick={() => {
                            setSelectedReaderId(reader.reader_id);
                            setShowEditForm(true);
                          }}
                          className="p-2 text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-lg"
                          title={t('common.edit')}
                        >
                          <Edit className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => {
                            setSelectedReaderId(reader.reader_id);
                            setShowAssignModal(true);
                          }}
                          className="p-2 text-green-600 hover:bg-green-50 dark:hover:bg-green-900/20 rounded-lg"
                          title={reader.current_center_name
                            ? t('readers_management.reassign')
                            : t('readers_management.assign')}
                        >
                          <Navigation className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => {
                            setSelectedReaderId(reader.reader_id);
                            setShowHistory(showHistory === reader.reader_id ? null : reader.reader_id);
                          }}
                          className="p-2 text-purple-600 hover:bg-purple-50 dark:hover:bg-purple-900/20 rounded-lg"
                          title={t('readers_management.view_history')}
                        >
                          <History className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => handleDeleteReader(reader.reader_id)}
                          className="p-2 text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg"
                          title={t('common.delete')}
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    </td>
                  </tr>
                  {/* Expandable History Row */}
                  {showHistory === reader.reader_id && (
                    <tr>
                      <td colSpan={8} className="px-6 py-4 bg-gray-50 dark:bg-gray-700/30">
                        <ReaderLocationTimeline readerId={reader.reader_id} />
                      </td>
                    </tr>
                  )}
                  </React.Fragment>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
