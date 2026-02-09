import { useState } from 'react'
import { ChevronRight, ChevronDown, MapPin, Radio, Edit, Trash2, Plus } from 'lucide-react'
import { Button } from '@/components/common/Button'
import type { PostalCenterWithReaders, Reader } from '@/lib/types_postal_centers'
import { useTranslation } from '@/hooks/useTranslation'

interface PostalCentersListProps {
  postalCenters: PostalCenterWithReaders[]
  onEditCenter: (center: PostalCenterWithReaders) => void
  onDeleteCenter: (centerId: string) => void
  onAddReader: (centerId: string) => void
  onEditReader: (reader: Reader) => void
  onDeleteReader: (readerId: string) => void
}

export function PostalCentersList({
  postalCenters,
  onEditCenter,
  onDeleteCenter,
  onAddReader,
  onEditReader,
  onDeleteReader
}: PostalCentersListProps) {
  const { t } = useTranslation()
  const [expandedCenters, setExpandedCenters] = useState<Set<string>>(new Set())

  const toggleCenter = (centerId: string) => {
    const newExpanded = new Set(expandedCenters)
    if (newExpanded.has(centerId)) {
      newExpanded.delete(centerId)
    } else {
      newExpanded.add(centerId)
    }
    setExpandedCenters(newExpanded)
  }

  const expandAll = () => {
    setExpandedCenters(new Set(postalCenters.map(c => c.id)))
  }

  const collapseAll = () => {
    setExpandedCenters(new Set())
  }

  const getReaderTypeBadge = (type: string) => {
    const badges = {
      Entry: 'bg-green-100 text-green-800',
      Exit: 'bg-blue-100 text-blue-800',
      Mixed: 'bg-purple-100 text-purple-800'
    }
    return badges[type as keyof typeof badges] || 'bg-gray-100 text-gray-800'
  }

  if (postalCenters.length === 0) {
    return (
      <div className="text-center py-12 text-gray-500">
        <MapPin className="mx-auto h-12 w-12 text-gray-400 mb-4" />
        <p>{t('postal_centers.no_centers_found')}</p>
      </div>
    )
  }

  return (
    <div className="space-y-2">
      <div className="flex justify-end mb-2">
        <Button
          variant="secondary"
          size="sm"
          onClick={expandedCenters.size === postalCenters.length ? collapseAll : expandAll}
        >
          {expandedCenters.size === postalCenters.length ? t('common.collapse_all') : t('common.expand_all')}
        </Button>
      </div>

      {postalCenters.map((center) => {
        const isExpanded = expandedCenters.has(center.id)
        const readersCount = center.readers?.length || 0

        return (
          <div key={center.id} className="border border-gray-200 rounded-lg bg-white">
            {/* Postal Center Header */}
            <div className="p-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3 flex-1">
                  <button
                    onClick={() => toggleCenter(center.id)}
                    className="text-gray-500 hover:text-gray-700"
                  >
                    {isExpanded ? (
                      <ChevronDown className="h-5 w-5" />
                    ) : (
                      <ChevronRight className="h-5 w-5" />
                    )}
                  </button>

                  <MapPin className="h-5 w-5 text-blue-600" />

                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <h3 className="font-semibold text-gray-900">{center.name}</h3>
                      <span className="text-sm text-gray-500">({center.code})</span>
                      {center.is_active && (
                        <span className="px-2 py-0.5 text-xs font-medium bg-green-100 text-green-800 rounded">
                          {t('common.active')}
                        </span>
                      )}
                    </div>
                    
                    <div className="flex items-center gap-4 mt-1 text-sm text-gray-600">
                      {center.opening_hour && center.cutoff_time && (
                        <span>
                          {t('postal_centers.hours')}: {center.opening_hour.substring(0, 5)} - {center.cutoff_time.substring(0, 5)}
                        </span>
                      )}
                      {center.calculation_mode && (
                        <span>
                          {t('postal_centers.mode')}: {t(`postal_centers.${center.calculation_mode}`)}
                        </span>
                      )}
                      <span>
                        {readersCount} {readersCount === 1 ? t('readers.reader') : t('readers.readers')}
                      </span>
                    </div>
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => onAddReader(center.id)}
                    title={t('readers.add_reader')}
                  >
                    <Plus className="h-4 w-4" />
                  </Button>
                  <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => onEditCenter(center)}
                    title={t('common.edit')}
                  >
                    <Edit className="h-4 w-4" />
                  </Button>
                  <Button
                    variant="danger"
                    size="sm"
                    onClick={() => {
                      if (confirm(t('postal_centers.confirm_delete_center'))) {
                        onDeleteCenter(center.id)
                      }
                    }}
                    title={t('common.delete')}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            </div>

            {/* Readers List (Expanded) */}
            {isExpanded && center.readers && center.readers.length > 0 && (
              <div className="border-t border-gray-200 bg-gray-50 px-4 py-3">
                <div className="space-y-2">
                  {center.readers.map((reader) => (
                    <div
                      key={reader.id}
                      className="flex items-center justify-between bg-white p-3 rounded border border-gray-200"
                    >
                      <div className="flex items-center gap-3 flex-1">
                        <Radio className="h-4 w-4 text-gray-400" />
                        
                        <div className="flex-1">
                          <div className="flex items-center gap-2">
                            <span className="font-medium text-gray-900">{reader.name}</span>
                            <span className="text-xs text-gray-500">({reader.reader_id})</span>
                            <span className={`px-2 py-0.5 text-xs font-medium rounded ${getReaderTypeBadge(reader.type)}`}>
                              {t(`readers.type_${reader.type.toLowerCase()}`)}
                            </span>
                            {reader.is_active && (
                              <span className="px-2 py-0.5 text-xs font-medium bg-green-100 text-green-800 rounded">
                                {t('common.active')}
                              </span>
                            )}
                          </div>
                          
                          {reader.description && (
                            <p className="text-sm text-gray-600 mt-1">{reader.description}</p>
                          )}
                          
                          {reader.type === 'Mixed' && reader.mixed_reader_gap_minutes && (
                            <p className="text-xs text-gray-500 mt-1">
                              {t('readers.gap')}: {reader.mixed_reader_gap_minutes} {t('common.minutes')}
                            </p>
                          )}
                        </div>
                      </div>

                      <div className="flex items-center gap-2">
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={() => onEditReader(reader)}
                          title={t('common.edit')}
                        >
                          <Edit className="h-4 w-4" />
                        </Button>
                        <Button
                          variant="danger"
                          size="sm"
                          onClick={() => {
                            if (confirm(t('readers.confirm_delete_reader'))) {
                              onDeleteReader(reader.id)
                            }
                          }}
                          title={t('common.delete')}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* No Readers Message */}
            {isExpanded && (!center.readers || center.readers.length === 0) && (
              <div className="border-t border-gray-200 bg-gray-50 px-4 py-6 text-center text-gray-500">
                <Radio className="mx-auto h-8 w-8 text-gray-400 mb-2" />
                <p className="text-sm">{t('readers.no_readers_found')}</p>
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={() => onAddReader(center.id)}
                  className="mt-2"
                >
                  <Plus className="h-4 w-4 mr-1" />
                  {t('readers.add_first_reader')}
                </Button>
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}
