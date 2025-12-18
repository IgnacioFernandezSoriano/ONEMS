import { SmartTooltip } from './SmartTooltip'

interface SortableHeaderProps {
  field: string
  label: string
  sortField: string
  sortDirection: 'asc' | 'desc'
  onSort: (field: string) => void
  tooltip: string
}

export function SortableHeader({
  field,
  label,
  sortField,
  sortDirection,
  onSort,
  tooltip,
}: SortableHeaderProps) {
  return (
    <th
      className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase cursor-pointer hover:bg-gray-100 transition-colors"
      onClick={() => onSort(field)}
    >
      <div className="flex items-center gap-1">
        <span>{label}</span>
        {sortField === field && (
          <svg className="w-3.5 h-3.5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            {sortDirection === 'asc' ? (
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M5 15l7-7 7 7" />
            ) : (
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 9l-7 7-7-7" />
            )}
          </svg>
        )}
        <div onClick={(e) => e.stopPropagation()}>
          <SmartTooltip content={tooltip} />
        </div>
      </div>
    </th>
  )
}
