import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

/**
 * PostgREST (rol authenticator) carga pg-safeupdate: cualquier UPDATE/DELETE sin WHERE falla con
 * 21000 "UPDATE requires a WHERE clause", incluso dentro de funciones plpgsql. El Postgres local de pruebas no
 * lo tiene, asi que los tests SQL no lo detectan (fallo real del 2026-10-27 en rpc_balance_city_v2). Esta
 * comprobacion estatica revisa las migraciones de Load Balancing v2: un WHERE de subconsulta no cuenta.
 */
function statementsWithoutWhere(sql: string): string[] {
  const body = sql.replace(/--[^\n]*/g, '')
  const pat = /\b(UPDATE\s+[\w.]+(?:\s+(?:AS\s+)?\w+)?\s+SET|DELETE\s+FROM\s+[\w.]+)/gi
  const bad: string[] = []
  for (let m = pat.exec(body); m; m = pat.exec(body)) {
    let depth = 0
    let hasWhere = false
    let j = m.index
    for (; j < body.length; j++) {
      const c = body[j]
      if (c === '(') depth++
      else if (c === ')') depth--
      else if (c === ';' && depth <= 0) break
      else if (depth === 0 && /^WHERE$/i.test(body.slice(j, j + 5)) && !/\w/.test(body[j - 1]) && !/\w/.test(body[j + 5] ?? ' ')) {
        hasWhere = true
      }
    }
    if (!hasWhere) bad.push(body.slice(m.index, j).replace(/\s+/g, ' ').slice(0, 120))
  }
  return bad
}

describe('migraciones de Load Balancing v2 compatibles con safeupdate', () => {
  const dir = join(process.cwd(), 'supabase', 'migrations')
  const files = readdirSync(dir).filter((f) => /^202610271\d{5}_.*\.sql$/.test(f) && f !== '20261027120000_load_balancing_v2.sql')

  it('el detector encuentra un UPDATE sin WHERE aunque haya WHERE en una subconsulta', () => {
    const sql = 'UPDATE t SET a = (SELECT b FROM u WHERE u.id = 1);\nUPDATE t SET a = 1 WHERE TRUE;'
    expect(statementsWithoutWhere(sql)).toHaveLength(1)
  })

  it.each(files)('%s no tiene UPDATE/DELETE sin WHERE', (file) => {
    expect(statementsWithoutWhere(readFileSync(join(dir, file), 'utf8'))).toEqual([])
  })

  it('la migracion original aun contiene el fallo (por eso existe la de correccion posterior)', () => {
    const original = readFileSync(join(dir, '20261027120000_load_balancing_v2.sql'), 'utf8')
    expect(statementsWithoutWhere(original).length).toBeGreaterThan(0)
    expect(files.some((f) => f.includes('safeupdate'))).toBe(true)
  })
})
