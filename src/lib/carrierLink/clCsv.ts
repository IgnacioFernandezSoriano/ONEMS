// Descargas CSV de las listas de Carrier Link: todo lo que cumple los filtros (no solo la pagina), con las mismas
// columnas y textos de la pantalla. Excel: BOM UTF-8 (acentos y arabe) y textos que empiezan por = + - @ tab o CR
// protegidos con un apostrofo para que no se ejecuten como formula (los datos vienen en parte del carrier).

/** Tope de filas por descarga; si hay mas, la descarga sale recortada y se avisa. */
export const CSV_MAX_ROWS = 50000

/** Ids por consulta `.in()`: 100 uuids dejan la URL en unos 4 KB (200 rozaban el limite de 8 KB de algunos proxies). */
export const ID_CHUNK = 100

const FORMULA_START = /^[=+\-@\t\r]/

export function csvCell(v: unknown): string {
  if (v === null || v === undefined) return ''
  if (typeof v === 'number' || typeof v === 'boolean') return String(v)
  let s = String(v)
  if (FORMULA_START.test(s)) s = `'${s}`
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

export function toCsv(headers: string[], rows: unknown[][]): string {
  return [headers, ...rows].map((r) => r.map(csvCell).join(',')).join('\r\n')
}

const pad = (n: number) => String(n).padStart(2, '0')

/** Fecha y hora local `YYYY-MM-DD HH:MM` (Excel la ordena bien); una fecha sola (`YYYY-MM-DD`) se deja como esta. */
export function csvDate(iso: string | null | undefined): string {
  if (!iso) return ''
  if (/^\d{4}-\d{2}-\d{2}$/.test(iso)) return iso
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export function csvFileName(base: string, now: Date = new Date()): string {
  return `${base.replace(/[^\w.-]+/g, '_')}_${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}.csv`
}

/** Lee paginas [from, to] (1.000 filas) hasta el final o hasta `max` filas; `truncated` si quedaba mas. */
export async function fetchCapped<T>(
  fetchPage: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown }>,
  max: number = CSV_MAX_ROWS,
  pageSize = 1000,
): Promise<{ rows: T[]; truncated: boolean }> {
  const rows: T[] = []
  for (let from = 0; from <= max; from += pageSize) {
    // Una fila de mas al llegar al tope: asi se sabe si quedaba algo sin leer.
    const to = Math.min(from + pageSize, max + 1) - 1
    const { data, error } = await fetchPage(from, to)
    if (error) throw error
    const page = data ?? []
    rows.push(...page)
    if (page.length < to - from + 1) break
  }
  return rows.length > max ? { rows: rows.slice(0, max), truncated: true } : { rows, truncated: false }
}

export interface CsvTable {
  headers: string[]
  rows: unknown[][]
  truncated: boolean
}

/** Descarga en el navegador (BOM UTF-8 delante). */
export function downloadCsv(filename: string, table: CsvTable): void {
  const blob = new Blob(['﻿' + toCsv(table.headers, table.rows)], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.style.display = 'none'
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
