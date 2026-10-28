/**
 * Recorre un resultado paginado (p. ej. una RPC de PostgREST, que corta en max_rows = 1000 por defecto)
 * pidiendo rangos [from, to] inclusivos hasta recibir una pagina corta. Acumula las filas en orden.
 * Si alguna pagina devuelve error, lo lanza (el llamador decide si es fatal).
 */
export async function fetchAllPages<T>(
  fetchPage: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown }>,
  pageSize = 1000
): Promise<T[]> {
  const out: T[] = []
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await fetchPage(from, from + pageSize - 1)
    if (error) throw error
    const page = data ?? []
    out.push(...page)
    if (page.length < pageSize) return out
  }
}
