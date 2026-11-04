import { useTranslation } from '@/hooks/useTranslation'
import type { ReceiptRepeatPanelist } from '@/lib/types'

interface Props { rows: ReceiptRepeatPanelist[]; onNotice: (p: ReceiptRepeatPanelist) => void }

export function ReceiptRepeatPanelists({ rows, onNotice }: Props) {
  const { t } = useTranslation()
  const th = 'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase'
  return (
    <div className="bg-white rounded-lg shadow overflow-hidden mb-6">
      <h3 className="font-semibold px-6 pt-4">{t('receipt_errors.repeaters_title')}</h3>
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-gray-50 border-b">
            <tr>
              <th className={th}>{t('receipt_errors.col.panelist')}</th>
              <th className={th}>{t('receipt_errors.col.fails_7d')}</th>
              <th className={th}>{t('receipt_errors.col.fails_30d')}</th>
              <th className={th}>{t('receipt_errors.col.top_reason')}</th>
              <th className={th}>{t('receipt_errors.col.last_notice')}</th>
              <th className={th}></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {rows.length > 0 ? rows.map(r => (
              <tr key={r.panelist_id} className="hover:bg-gray-50">
                <td className="px-6 py-3 text-sm"><div className="font-medium">{r.name}</div><div className="text-gray-500 text-xs font-mono">{r.panelist_code}</div></td>
                <td className="px-6 py-3 text-sm">{r.fails_7d}</td>
                <td className="px-6 py-3 text-sm">{r.fails_30d}</td>
                <td className="px-6 py-3 text-sm">{r.top_reason ? t(`receipt_errors.reason.${r.top_reason}`) : '-'}</td>
                <td className="px-6 py-3 text-sm">{r.last_notice_at ? r.last_notice_at.slice(0, 10) : t('receipt_errors.never')}</td>
                <td className="px-6 py-3 text-sm"><button onClick={() => onNotice(r)} className="text-blue-600 hover:text-blue-800">{t('receipt_errors.send_notice')}</button></td>
              </tr>
            )) : (
              <tr><td colSpan={6} className="px-6 py-4 text-center text-gray-500">{t('receipt_errors.no_repeaters')}</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
