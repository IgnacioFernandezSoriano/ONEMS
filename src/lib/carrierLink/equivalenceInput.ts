// Interpreta el texto de un tiempo de equivalencia (primer/último tramo del carrier).
// '' -> 0; acepta punto o coma decimal; negativos y no numéricos -> null.
export function parseEquivalenceInput(v: string): number | null {
  const s = v.trim().replace(',', '.')
  if (s === '') return 0
  if (!/^\d+(\.\d+)?$/.test(s)) return null
  return parseFloat(s)
}
