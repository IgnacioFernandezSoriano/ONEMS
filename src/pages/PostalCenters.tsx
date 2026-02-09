import { useState, useMemo } from 'react'
import { Plus, Search, Filter } from 'lucide-react'
import { usePostalCenters } from '@/hooks/usePostalCenters'
import { PostalCentersList } from '@/components/postal-centers/PostalCentersList'
import { PostalCenterForm } from '@/components/postal-centers/PostalCenterForm'
import { ReaderForm } from '@/components/postal-centers/ReaderForm'
import { Modal } from '@/components/common/Modal'
import { Button } from '@/components/common/Button'
import type { PostalCenterWithReaders, Reader, PostalCenterFormData, ReaderFormData } from '@/lib/types_postal_centers'
import { useTranslation } from '@/hooks/useTranslation'

export function PostalCenters() {
  const { t } = useTranslation()
  const {
    postalCenters,
    loading,
    error,
    createPostalCenter,
    updatePostalCenter,
    deletePostalCenter,
    createReader,
    updateReader,
    deleteReader
  } = usePostalCenters()

  // Modals state
  const [showCreateCenterModal, setShowCreateCenterModal] = useState(false)
  const [showEditCenterModal, setShowEditCenterModal] = useState(false)
  const [editingCenter, setEditingCenter] = useState<PostalCenterWithReaders | null>(null)
  
  const [showCreateReaderModal, setShowCreateReaderModal] = useState(false)
  const [showEditReaderModal, setShowEditReaderModal] = useState(false)
  const [editingReader, setEditingReader] = useState<Reader | null>(null)
  const [selectedCenterId, setSelectedCenterId] = useState<string | null>(null)

  // Filters state
  const [showFilters, setShowFilters] = useState(false)
  const [searchTerm, setSearchTerm] = useState('')
  const [filters, setFilters] = useState({
    active_only: false,
    reader_type: '',
    calculation_mode: ''
  })

  // Filtered postal centers
  const filteredCenters = useMemo(() => {
    return postalCenters.filter((center) => {
      // Search filter
      if (searchTerm) {
        const search = searchTerm.toLowerCase()
        const matchesCenter = 
          center.name.toLowerCase().includes(search) ||
          center.code.toLowerCase().includes(search) ||
          (center.description && center.description.toLowerCase().includes(search))
        
        const matchesReader = center.readers?.some(reader =>
          reader.name.toLowerCase().includes(search) ||
          reader.reader_id.toLowerCase().includes(search)
        )

        if (!matchesCenter && !matchesReader) return false
      }

      // Active only filter
      if (filters.active_only && !center.is_active) return false

      // Calculation mode filter
      if (filters.calculation_mode && center.calculation_mode !== filters.calculation_mode) return false

      // Reader type filter
      if (filters.reader_type) {
        const hasReaderType = center.readers?.some(reader => reader.type === filters.reader_type)
        if (!hasReaderType) return false
      }

      return true
    })
  }, [postalCenters, searchTerm, filters])

  // Calculate KPIs
  const kpis = useMemo(() => {
    const totalCenters = postalCenters.length
    const activeCenters = postalCenters.filter(c => c.is_active).length
    const totalReaders = postalCenters.reduce((sum, c) => sum + (c.readers?.length || 0), 0)
    const activeReaders = postalCenters.reduce((sum, c) => 
      sum + (c.readers?.filter(r => r.is_active).length || 0), 0
    )
    const readersByType = postalCenters.reduce((acc, c) => {
      c.readers?.forEach(r => {
        acc[r.type] = (acc[r.type] || 0) + 1
      })
      return acc
    }, {} as Record<string, number>)

    return {
      totalCenters,
      activeCenters,
      totalReaders,
      activeReaders,
      entryReaders: readersByType.Entry || 0,
      exitReaders: readersByType.Exit || 0,
      mixedReaders: readersByType.Mixed || 0
    }
  }, [postalCenters])

  // Handlers
  const handleCreateCenter = async (data: PostalCenterFormData) => {
    await createPostalCenter(data)
    setShowCreateCenterModal(false)
  }

  const handleEditCenter = (center: PostalCenterWithReaders) => {
    setEditingCenter(center)
    setShowEditCenterModal(true)
  }

  const handleUpdateCenter = async (data: PostalCenterFormData) => {
    if (!editingCenter) return
    await updatePostalCenter(editingCenter.id, data)
    setShowEditCenterModal(false)
    setEditingCenter(null)
  }

  const handleDeleteCenter = async (centerId: string) => {
    await deletePostalCenter(centerId)
  }

  const handleAddReader = (centerId: string) => {
    setSelectedCenterId(centerId)
    setShowCreateReaderModal(true)
  }

  const handleCreateReader = async (data: ReaderFormData) => {
    if (!selectedCenterId) return
    await createReader(selectedCenterId, data)
    setShowCreateReaderModal(false)
    setSelectedCenterId(null)
  }

  const handleEditReader = (reader: Reader) => {
    setEditingReader(reader)
    setShowEditReaderModal(true)
  }

  const handleUpdateReader = async (data: ReaderFormData) => {
    if (!editingReader) return
    await updateReader(editingReader.id, data)
    setShowEditReaderModal(false)
    setEditingReader(null)
  }

  const handleDeleteReader = async (readerId: string) => {
    await deleteReader(readerId)
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">{t('common.loading')}</div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
        {error}
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">{t('postal_centers.title')}</h1>
          <p className="text-gray-600 mt-1">{t('postal_centers.description')}</p>
        </div>
        <Button onClick={() => setShowCreateCenterModal(true)}>
          <Plus className="h-4 w-4 mr-2" />
          {t('postal_centers.create_center')}
        </Button>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-4">
        <div className="bg-white p-4 rounded-lg border border-gray-200">
          <div className="text-sm text-gray-600">{t('postal_centers.total_centers')}</div>
          <div className="text-2xl font-bold text-gray-900">{kpis.totalCenters}</div>
        </div>
        <div className="bg-white p-4 rounded-lg border border-gray-200">
          <div className="text-sm text-gray-600">{t('postal_centers.active_centers')}</div>
          <div className="text-2xl font-bold text-green-600">{kpis.activeCenters}</div>
        </div>
        <div className="bg-white p-4 rounded-lg border border-gray-200">
          <div className="text-sm text-gray-600">{t('readers.total_readers')}</div>
          <div className="text-2xl font-bold text-gray-900">{kpis.totalReaders}</div>
        </div>
        <div className="bg-white p-4 rounded-lg border border-gray-200">
          <div className="text-sm text-gray-600">{t('readers.active_readers')}</div>
          <div className="text-2xl font-bold text-green-600">{kpis.activeReaders}</div>
        </div>
        <div className="bg-white p-4 rounded-lg border border-gray-200">
          <div className="text-sm text-gray-600">{t('readers.entry_readers')}</div>
          <div className="text-2xl font-bold text-green-600">{kpis.entryReaders}</div>
        </div>
        <div className="bg-white p-4 rounded-lg border border-gray-200">
          <div className="text-sm text-gray-600">{t('readers.exit_readers')}</div>
          <div className="text-2xl font-bold text-blue-600">{kpis.exitReaders}</div>
        </div>
        <div className="bg-white p-4 rounded-lg border border-gray-200">
          <div className="text-sm text-gray-600">{t('readers.mixed_readers')}</div>
          <div className="text-2xl font-bold text-purple-600">{kpis.mixedReaders}</div>
        </div>
      </div>

      {/* Filters */}
      <div className="bg-white p-4 rounded-lg border border-gray-200">
        <div className="flex items-center gap-4">
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-gray-400" />
            <input
              type="text"
              placeholder={t('postal_centers.search_placeholder')}
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <Button
            variant="secondary"
            onClick={() => setShowFilters(!showFilters)}
          >
            <Filter className="h-4 w-4 mr-2" />
            {t('common.filters')}
          </Button>
        </div>

        {showFilters && (
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mt-4 pt-4 border-t border-gray-200">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                {t('postal_centers.status')}
              </label>
              <select
                value={filters.active_only ? 'active' : 'all'}
                onChange={(e) => setFilters({ ...filters, active_only: e.target.value === 'active' })}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="all">{t('common.all')}</option>
                <option value="active">{t('common.active_only')}</option>
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                {t('readers.reader_type')}
              </label>
              <select
                value={filters.reader_type}
                onChange={(e) => setFilters({ ...filters, reader_type: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="">{t('common.all')}</option>
                <option value="Entry">{t('readers.type_entry')}</option>
                <option value="Exit">{t('readers.type_exit')}</option>
                <option value="Mixed">{t('readers.type_mixed')}</option>
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                {t('postal_centers.calculation_mode')}
              </label>
              <select
                value={filters.calculation_mode}
                onChange={(e) => setFilters({ ...filters, calculation_mode: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="">{t('common.all')}</option>
                <option value="natural_days">{t('postal_centers.natural_days')}</option>
                <option value="working_days">{t('postal_centers.working_days')}</option>
              </select>
            </div>
          </div>
        )}
      </div>

      {/* List */}
      <PostalCentersList
        postalCenters={filteredCenters}
        onEditCenter={handleEditCenter}
        onDeleteCenter={handleDeleteCenter}
        onAddReader={handleAddReader}
        onEditReader={handleEditReader}
        onDeleteReader={handleDeleteReader}
      />

      {/* Modals */}
      <Modal
        isOpen={showCreateCenterModal}
        onClose={() => setShowCreateCenterModal(false)}
        title={t('postal_centers.create_center')}
      >
        <PostalCenterForm
          onSubmit={handleCreateCenter}
          onCancel={() => setShowCreateCenterModal(false)}
        />
      </Modal>

      <Modal
        isOpen={showEditCenterModal}
        onClose={() => {
          setShowEditCenterModal(false)
          setEditingCenter(null)
        }}
        title={t('postal_centers.edit_center')}
      >
        <PostalCenterForm
          postalCenter={editingCenter}
          onSubmit={handleUpdateCenter}
          onCancel={() => {
            setShowEditCenterModal(false)
            setEditingCenter(null)
          }}
        />
      </Modal>

      <Modal
        isOpen={showCreateReaderModal}
        onClose={() => {
          setShowCreateReaderModal(false)
          setSelectedCenterId(null)
        }}
        title={t('readers.create_reader')}
      >
        <ReaderForm
          onSubmit={handleCreateReader}
          onCancel={() => {
            setShowCreateReaderModal(false)
            setSelectedCenterId(null)
          }}
        />
      </Modal>

      <Modal
        isOpen={showEditReaderModal}
        onClose={() => {
          setShowEditReaderModal(false)
          setEditingReader(null)
        }}
        title={t('readers.edit_reader')}
      >
        <ReaderForm
          reader={editingReader}
          onSubmit={handleUpdateReader}
          onCancel={() => {
            setShowEditReaderModal(false)
            setEditingReader(null)
          }}
        />
      </Modal>
    </div>
  )
}
