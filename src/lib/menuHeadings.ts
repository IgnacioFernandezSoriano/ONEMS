/** Entrada de un submenú: un enlace o un subencabezado (etiqueta pequeña que agrupa los enlaces siguientes). */
export interface HeadingEntry {
  heading?: boolean
  /** Subencabezado que solo se muestra si en el mismo submenú se ve otro subencabezado (p. ej. "Panelistas" junto a Carrier Link). */
  onlyWithOtherHeadings?: boolean
}

/**
 * Entradas visibles de un submenú: los enlaces visibles y los subencabezados que tengan al menos un enlace
 * visible hasta el siguiente subencabezado. Un subencabezado sin enlaces visibles no se muestra, y uno marcado
 * onlyWithOtherHeadings tampoco si no se ve ningún otro subencabezado (así el menú sin Carrier Link queda como siempre).
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
  const others = out.some((e) => e.heading && !e.onlyWithOtherHeadings)
  return others ? out : out.filter((e) => !(e.heading && e.onlyWithOtherHeadings))
}
