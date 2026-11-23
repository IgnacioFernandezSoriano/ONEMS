// Corte de un trozo del fichero en registros y lectura de cada registro (JSON Lines o CSV, sin comprimir).
// Se trabaja sobre bytes: el salto de linea (0x0A) y la comilla (0x22) nunca forman parte de un caracter UTF-8 de
// varios bytes, asi que cortar por bytes es seguro y cada registro se decodifica entero.
// Un trozo siempre empieza en el inicio de un registro (el cursor de la carga apunta ahi), por eso el estado de
// comillas del CSV empieza cerrado en cada trozo.

export type Format = 'jsonl' | 'csv'

export class FileError extends Error {
  // final = el fichero no se puede procesar (rejected); si no, se puede reintentar (failed).
  constructor(public code: string, public final: boolean) { super(code) }
}

export interface Span { start: number; end: number; next: number }   // [start, end) sin fin de linea; next = byte siguiente

// Registros completos del trozo. Sin isLast, el ultimo registro sin salto de linea queda fuera (consumed no lo
// incluye) y se vuelve a leer en el siguiente trozo. Con isLast, lo que quede es el ultimo registro.
export function splitRecords(buf: Uint8Array, format: Format, isLast: boolean): { spans: Span[]; consumed: number } {
  const spans: Span[] = []
  let start = 0
  let inQuote = false
  const csv = format === 'csv'
  for (let i = 0; i < buf.length; i++) {
    const b = buf[i]
    if (csv && b === 0x22) { inQuote = !inQuote; continue }
    if (b === 0x0a && !inQuote) {
      const end = i > start && buf[i - 1] === 0x0d ? i - 1 : i
      spans.push({ start, end, next: i + 1 })
      start = i + 1
    }
  }
  if (isLast && start < buf.length) {
    let end = buf.length
    if (buf[end - 1] === 0x0d) end--
    spans.push({ start, end, next: buf.length })
    start = buf.length
  }
  return { spans, consumed: start }
}

const decoder = new TextDecoder('utf-8', { fatal: true })

export function decode(bytes: Uint8Array): string {
  try {
    return decoder.decode(bytes)
  } catch {
    throw new FileError('CL_BAD_ENCODING', true)
  }
}

const BOM = [0xef, 0xbb, 0xbf]
export function bomLength(buf: Uint8Array, fileOffset: number): number {
  return fileOffset === 0 && buf.length >= 3 && buf[0] === BOM[0] && buf[1] === BOM[1] && buf[2] === BOM[2] ? 3 : 0
}

// Campos de un registro CSV (RFC 4180, separador coma). null si esta mal formado (comilla sin cerrar o texto tras
// la comilla de cierre).
export function parseCsvFields(line: string): string[] | null {
  const out: string[] = []
  let i = 0
  const n = line.length
  while (true) {
    if (i < n && line[i] === '"') {
      let v = ''
      i++
      while (true) {
        if (i >= n) return null
        const c = line[i]
        if (c === '"') {
          if (line[i + 1] === '"') { v += '"'; i += 2; continue }
          i++
          break
        }
        v += c
        i++
      }
      if (i < n && line[i] !== ',') return null
      out.push(v)
    } else {
      const j = line.indexOf(',', i)
      const v = j === -1 ? line.slice(i) : line.slice(i, j)
      if (v.includes('"')) return null
      out.push(v)
      i = j === -1 ? n : j
    }
    if (i >= n) return out
    i++ // coma
    if (i === n) { out.push(''); return out }
  }
}

export function parseCsvHeader(line: string): string[] {
  const f = parseCsvFields(line)
  if (!f || f.length === 0) throw new FileError('CL_BAD_CSV_HEADER', true)
  const names = f.map((x) => x.trim())
  if (names.some((x) => x === '') || new Set(names).size !== names.length) throw new FileError('CL_BAD_CSV_HEADER', true)
  return names
}

// Registro -> objeto con solo los campos permitidos (lista cerrada; la base vuelve a filtrar). null = registro
// ilegible (la base lo guarda como bad_record).
export function toRecord(line: string, format: Format, header: string[] | null, allowed: Set<string>):
  Record<string, unknown> | null {
  if (format === 'jsonl') {
    let v: unknown
    try { v = JSON.parse(line) } catch { return null }
    if (v === null || typeof v !== 'object' || Array.isArray(v)) return null
    const o: Record<string, unknown> = {}
    for (const [k, x] of Object.entries(v as Record<string, unknown>)) if (allowed.has(k)) o[k] = x
    return o
  }
  const f = parseCsvFields(line)
  if (!f || !header || f.length !== header.length) return null
  const o: Record<string, unknown> = {}
  for (let i = 0; i < header.length; i++) {
    if (allowed.has(header[i]) && f[i] !== '') o[header[i]] = f[i]
  }
  return o
}

export function isBlank(line: string): boolean {
  return line.trim() === ''
}
