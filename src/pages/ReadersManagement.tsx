import { useState } from 'react';
import { Plus, MapPin, History, Edit, Trash2, Navigation } from 'lucide-react';
import { Button } from '@/components/common/Button';
import { ReaderForm } from '@/components/postal-centers/ReaderForm';
import { ReaderLocationTimeline } from '@/components/mobile-readers/ReaderLocationTimeline';
import { AssignReaderModal } from '@/components/mobile-readers/AssignReaderModal';
import { useMobileReaders } from '@/hooks/useMobileReaders';
import { useReaderLocationHistory } from '@/hooks/useReaderLocationHistory';
import { useAuth } from '@/contexts/AuthContext';
import { useTranslation } from '@/hooks/useTranslation';
import type { ReaderFormData } from '@/lib/types_postal_centers';

export default function ReadersManagement() {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const accountId = profile?.account_id || undefined;

  const { readers, createMobileReader, updateReader, deleteReader, refetch } =
    useMobileReaders(accountId);

  const [showCreateForm, setShowCreateForm] = useState(false);
  const [selectedReaderId, setSelectedReaderId] = useState<string | null>(null);
  const [showAssignModal, setShowAssignModal] = useState(false);
  const [showHistory, setShowHistory] = useState(false);

  const { assignToCenter } = useReaderLocationHistory(selectedReaderId);

  const selectedReader = readers.find((r) => r.reader_id === selectedReaderId);

  const handleCreateReader = async (data: ReaderFormData) => {
    const result = await createMobileReader(data);
    if (result.success) {
      setShowCreateForm(false);
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
    if (!confirm(t('mobile_readers.confirm_delete'))) return;

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
            {t('mobile_readers.create_reader')}
          </Button>
        </div>
        <div className="text-sm text-gray-600 dark:text-gray-400">
          {readers.length} {t('readers_management.total_readers')}
          {readers.filter((r) => r.is_mobile).length > 0 && (
            <> • {readers.filter((r) => r.is_mobile).length} {t('readers_management.with_history')}</>
          )}
        </div>
      </div>

      {/* Create Form Modal */}
      {showCreateForm && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto p-6">
            <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">
              {t('mobile_readers.create_reader')}
            </h2>
            <ReaderForm
              accountId={accountId!}
              onSubmit={handleCreateReader}
              onCancel={() => setShowCreateForm(false)}
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

      {/* Readers Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {readers.map((reader) => (
          <div
            key={reader.reader_id}
            className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6 hover:shadow-md transition-shadow"
          >
            {/* Header */}
            <div className="flex items-start justify-between mb-4">
              <div className="flex-1">
                <div className="flex items-center gap-2 mb-2">
                  <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
                    {reader.reader_name}
                  </h3>
                  <span
                    className={`px-2 py-1 text-xs font-medium rounded ${getReaderTypeColor(
                      reader.reader_type
                    )}`}
                  >
                    {reader.reader_type}
                  </span>
                  {reader.is_mobile && (
                    <span className="px-2 py-1 bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400 text-xs font-medium rounded">
                      {t('mobile_readers.mobile')}
                    </span>
                  )}
                </div>
                <p className="text-sm text-gray-500 dark:text-gray-400">{reader.reader_code}</p>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => handleDeleteReader(reader.reader_id)}
                  className="p-2 text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg"
                  title={t('common.delete')}
                >
                  <Trash2 className="w-4 h-4" />
                </button>
              </div>
            </div>

            {/* Current Location */}
            <div className="mb-4 p-3 bg-gray-50 dark:bg-gray-700/50 rounded-lg">
              <div className="flex items-center gap-2 mb-2">
                <MapPin className="w-4 h-4 text-gray-500 dark:text-gray-400" />
                <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
                  {t('mobile_readers.current_location')}
                </span>
              </div>
              {reader.current_center_name ? (
                <div>
                  <p className="text-gray-900 dark:text-white font-medium">
                    {reader.current_center_name}
                  </p>
                  {reader.assigned_since && (
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                      {t('mobile_readers.since')}{' '}
                      {new Date(reader.assigned_since).toLocaleDateString('es-ES')}
                    </p>
                  )}
                </div>
              ) : (
                <p className="text-gray-500 dark:text-gray-400 italic">
                  {t('mobile_readers.unassigned')}
                </p>
              )}
            </div>

            {/* Stats */}
            <div className="flex items-center gap-4 mb-4 text-sm text-gray-600 dark:text-gray-400">
              <div className="flex items-center gap-1">
                <History className="w-4 h-4" />
                <span>
                  {reader.total_assignments} {t('mobile_readers.assignments')}
                </span>
              </div>
            </div>

            {/* Actions */}
            <div className="flex gap-2">
              <Button
                variant="secondary"
                size="sm"
                onClick={() => {
                  setSelectedReaderId(reader.reader_id);
                  setShowAssignModal(true);
                }}
              >
                <Navigation className="w-4 h-4 mr-2" />
                {reader.current_center_name
                  ? t('mobile_readers.reassign')
                  : t('mobile_readers.assign')}
              </Button>
              <Button
                variant="secondary"
                size="sm"
                onClick={() => {
                  setSelectedReaderId(reader.reader_id);
                  setShowHistory(!showHistory);
                }}
              >
                <History className="w-4 h-4 mr-2" />
                {t('mobile_readers.view_history')}
              </Button>
            </div>

            {/* History Timeline */}
            {showHistory && selectedReaderId === reader.reader_id && (
              <div className="mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
                <ReaderLocationTimeline readerId={reader.reader_id} />
              </div>
            )}
          </div>
        ))}
      </div>

      {/* Empty State */}
      {readers.length === 0 && (
        <div className="text-center py-12">
          <MapPin className="w-16 h-16 mx-auto text-gray-400 mb-4" />
          <h3 className="text-lg font-medium text-gray-900 dark:text-white mb-2">
            {t('mobile_readers.no_readers')}
          </h3>
          <p className="text-gray-600 dark:text-gray-400 mb-4">
            {t('mobile_readers.no_readers_description')}
          </p>
          <Button onClick={() => setShowCreateForm(true)}>
            <Plus className="w-4 h-4 mr-2" />
            {t('mobile_readers.create_first_reader')}
          </Button>
        </div>
      )}
    </div>
  );
}
