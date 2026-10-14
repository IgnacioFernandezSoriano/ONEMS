import { useTranslation } from '@/hooks/useTranslation'

interface TablePaginationProps {
  /** 1-based index of the page being shown */
  currentPage: number
  /** Total number of pages for the current filtered set */
  totalPages: number
  /** Rows rendered per page */
  pageSize: number
  /** Size of the whole filtered set, not of the current page */
  totalItems: number
  onPageChange: (page: number) => void
  onPageSizeChange: (size: number) => void
  pageSizeOptions?: number[]
  /** Disambiguates the <label for> when several tables share a screen */
  idPrefix?: string
}

/**
 * Pagination bar for the big data tables.
 *
 * Rendering every row of a large table freezes the browser, so tables render
 * one page at a time. Selection, bulk actions and CSV export keep working over
 * the whole filtered set, not just the visible page.
 */
export function TablePagination({
  currentPage,
  totalPages,
  pageSize,
  totalItems,
  onPageChange,
  onPageSizeChange,
  pageSizeOptions = [50, 100, 250, 500],
  idPrefix = 'table',
}: TablePaginationProps) {
  const { t } = useTranslation()

  if (totalItems === 0) return null

  const firstRow = (currentPage - 1) * pageSize + 1
  const lastRow = Math.min(currentPage * pageSize, totalItems)

  return (
    <div className="flex flex-wrap items-center justify-between gap-3 px-6 py-3 border-t border-gray-200 text-sm text-gray-600">
      <div className="flex items-center gap-2">
        <label htmlFor={`${idPrefix}-page-size`}>{t('common.rows_per_page')}</label>
        <select
          id={`${idPrefix}-page-size`}
          value={pageSize}
          onChange={(e) => onPageSizeChange(Number(e.target.value))}
          className="border border-gray-300 rounded-md px-2 py-1"
        >
          {pageSizeOptions.map((n) => (
            <option key={n} value={n}>{n}</option>
          ))}
        </select>
      </div>

      <div>
        {t('common.showing')} {firstRow} - {lastRow} {t('common.of')} {totalItems}
      </div>

      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={() => onPageChange(Math.max(1, currentPage - 1))}
          disabled={currentPage === 1}
          className="px-3 py-1 border border-gray-300 rounded-md hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {t('common.previous')}
        </button>
        <span>{currentPage} / {totalPages}</span>
        <button
          type="button"
          onClick={() => onPageChange(Math.min(totalPages, currentPage + 1))}
          disabled={currentPage === totalPages}
          className="px-3 py-1 border border-gray-300 rounded-md hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {t('common.next')}
        </button>
      </div>
    </div>
  )
}
