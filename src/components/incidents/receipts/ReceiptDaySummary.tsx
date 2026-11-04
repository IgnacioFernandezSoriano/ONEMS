import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, Legend, CartesianGrid } from 'recharts'
import { useTranslation } from '@/hooks/useTranslation'
import type { ReceiptDaySummary as Summary, ReceiptTrendPoint } from '@/lib/types'

interface Props { summary: Summary | null; trend: ReceiptTrendPoint[] }

type CardKey = 'attempts' | 'ok_first_time' | 'fixed' | 'compensated' | 'pending' | 'needs_decision' | 'informative'

const CARDS: { key: CardKey; color: string }[] = [
  { key: 'attempts', color: 'text-gray-900' },
  { key: 'ok_first_time', color: 'text-green-600' },
  { key: 'fixed', color: 'text-blue-600' },
  { key: 'compensated', color: 'text-amber-600' },
  { key: 'pending', color: 'text-gray-600' },
  { key: 'needs_decision', color: 'text-red-600' },
  { key: 'informative', color: 'text-gray-500' },
]

export function ReceiptDaySummary({ summary, trend }: Props) {
  const { t } = useTranslation()
  const byReason = Object.entries(summary?.by_reason ?? {}).sort((a, b) => b[1] - a[1])
  return (
    <div className="space-y-4 mb-6">
      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-3">
        {CARDS.map(c => (
          <div key={c.key} className="bg-white rounded-lg shadow p-4">
            <div className="text-xs text-gray-500 uppercase">{t(`receipt_errors.card.${c.key}`)}</div>
            <div className={`text-2xl font-bold ${c.color}`}>{summary?.[c.key] ?? 0}</div>
          </div>
        ))}
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div className="bg-white rounded-lg shadow p-4">
          <h3 className="font-semibold mb-2">{t('receipt_errors.by_reason')}</h3>
          {byReason.length === 0 ? <div className="text-sm text-gray-500">{t('receipt_errors.no_cases')}</div> : (
            <ul className="text-sm divide-y">
              {byReason.map(([reason, n]) => (
                <li key={reason} className="flex justify-between py-1.5">
                  <span>{t(`receipt_errors.reason.${reason}`)}</span><span className="font-medium">{n}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
        <div className="bg-white rounded-lg shadow p-4 lg:col-span-2">
          <h3 className="font-semibold mb-2">{t('receipt_errors.trend_title')}</h3>
          <ResponsiveContainer width="100%" height={240}>
            <BarChart data={trend}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="day" tickFormatter={(d: string) => d.slice(5)} fontSize={11} />
              <YAxis allowDecimals={false} fontSize={11} />
              <Tooltip />
              <Legend />
              <Bar dataKey="ok_first_time" stackId="a" fill="#10b981" name={t('receipt_errors.card.ok_first_time')} />
              <Bar dataKey="fixed" stackId="a" fill="#3b82f6" name={t('receipt_errors.card.fixed')} />
              <Bar dataKey="compensated" stackId="a" fill="#f59e0b" name={t('receipt_errors.card.compensated')} />
              <Bar dataKey="open" stackId="a" fill="#ef4444" name={t('receipt_errors.trend_open')} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  )
}
