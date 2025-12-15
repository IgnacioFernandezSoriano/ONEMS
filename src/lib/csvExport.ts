import type { GeneratedAllocationPlanDetail } from './types'

export interface CSVExportData {
  plan_name: string
  account_code: string
  carrier_code: string
  product_code: string
  origin_city_code: string
  origin_node_code: string
  destination_city_code: string
  destination_node_code: string
  fecha_programada: string
  week_number: number
  month: number
  year: number
  status: string
}

/**
 * Convert allocation plan details to CSV format
 */
export function convertToCSV(data: CSVExportData[]): string {
  if (data.length === 0) return ''

  const headers = Object.keys(data[0])
  const csvRows = []

  // Add header row
  csvRows.push(headers.join(','))

  // Add data rows
  data.forEach((row) => {
    const values = headers.map((header) => {
      const value = row[header as keyof CSVExportData]
      // Escape commas and quotes
      if (typeof value === 'string' && (value.includes(',') || value.includes('"'))) {
        return `"${value.replace(/"/g, '""')}"`
      }
      return value
    })
    csvRows.push(values.join(','))
  })

  return csvRows.join('\n')
}

/**
 * Download CSV file
 */
export function downloadCSV(filename: string, csvContent: string): void {
  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' })
  const link = document.createElement('a')
  const url = URL.createObjectURL(blob)

  link.setAttribute('href', url)
  link.setAttribute('download', filename)
  link.style.visibility = 'hidden'
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
}

/**
 * Generate CSV template for manual import
 */
export function generateCSVTemplate(): string {
  const headers = [
    'plan_name',
    'account_code',
    'carrier_code',
    'product_code',
    'origin_city_code',
    'origin_node_code',
    'destination_city_code',
    'destination_node_code',
    'fecha_programada',
    'status',
  ]

  const exampleRow = [
    'Plan Example',
    'ACCOUNT01',
    'CARRIER01',
    'PRODUCT01',
    'MAD',
    'MAD-N01',
    'BCN',
    'BCN-N01',
    '2026-01-05',
    'pending',
  ]

  return `${headers.join(',')}\n${exampleRow.join(',')}`
}
