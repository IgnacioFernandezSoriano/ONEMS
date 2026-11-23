/** Entrada de un submenú: un enlace o un subencabezado (etiqueta pequeña que agrupa los enlaces siguientes). */
export interface HeadingEntry {
  heading?: boolean
}

/**
 * Entradas visibles de un submenú: los enlaces visibles y los subencabezados que tengan al menos un enlace
 * visible hasta el siguiente subencabezado. Un subencabezado sin enlaces visibles no se muestra.
 */
export function visibleEntries<T extends HeadingEntry>(entries: T[], isVisible: (e: T) => boolean): T[] {
  const out: T[] = []
  let pendingHeading: T | null = null
  for (const e of entries) {
    if (e.heading) {
      pendingHeading = e
    } else if (isVisible(e)) {
      if (pendingHeading) {
        out.push(pendingHeading)
        pendingHeading = null
      }
      out.push(e)
    }
  }
  return out
}
