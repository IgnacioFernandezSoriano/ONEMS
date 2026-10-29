// Anade campos de horas y hora local a src/data/demo2/one_db.json (zona Europe/Madrid, Lun-Vie, sin festivos).
// Idempotente: sobrescribe siempre los mismos seis campos.
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const file = join(root, 'src/data/demo2/one_db.json')
const holidaysFile = join(root, 'src/data/demo2/non_working_days.json')
const TZ = 'Europe/Madrid'

const holidays = new Set()
if (existsSync(holidaysFile)) {
  for (const h of JSON.parse(readFileSync(holidaysFile, 'utf8'))) {
    const d = typeof h === 'string' ? h : (h.date ?? h.non_working_date)
    if (d) holidays.add(String(d).slice(0, 10))
  }
}

const fmt = new Intl.DateTimeFormat('en-GB', {
  timeZone: TZ, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit',
})
// Reloj de pared local como "fecha UTC" (ms), para aritmetica por dia natural.
function local(iso) {
  const p = Object.fromEntries(fmt.formatToParts(new Date(iso)).map((x) => [x.type, x.value]))
  const ms = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second)
  return { ms, text: `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}:${p.second}` }
}
const DAY = 86400000
const isWorking = (dayMs) => {
  const dow = new Date(dayMs).getUTCDay()
  return dow !== 0 && dow !== 6 && !holidays.has(new Date(dayMs).toISOString().slice(0, 10))
}
const round2 = (n) => Math.round(n * 100) / 100

function compute(sentIso, recvIso) {
  const s = local(sentIso), r = local(recvIso)
  const out = { sent_at_local: s.text, received_at_local: r.text }
  if (r.ms < s.ms) return { total_transit_hours: 0, business_transit_hours: 0, total_transit_days: 0, business_transit_days: 0, ...out }
  const sDay = Math.floor(s.ms / DAY) * DAY, rDay = Math.floor(r.ms / DAY) * DAY
  let bh = 0, bd = 0
  for (let d = sDay; d <= rDay; d += DAY) {
    const overlap = Math.min(r.ms, d + DAY) - Math.max(s.ms, d)
    if (isWorking(d)) {
      bh += overlap / 3600000
      if (d < rDay) bd++
    }
  }
  return {
    total_transit_hours: round2((new Date(recvIso) - new Date(sentIso)) / 3600000),
    business_transit_hours: round2(bh),
    total_transit_days: Math.round((rDay - sDay) / DAY),
    business_transit_days: bd,
    ...out,
  }
}

const rows = JSON.parse(readFileSync(file, 'utf8'))
for (const row of rows) {
  if (row.sent_at && row.received_at) Object.assign(row, compute(row.sent_at, row.received_at))
}
writeFileSync(file, JSON.stringify(rows, null, 2).replace(/\n/g, '\r\n')) // el fichero usa CRLF y no acaba en salto de linea
const f = rows[0]
console.log(rows.length, 'filas;', {
  total_transit_hours: f.total_transit_hours, business_transit_hours: f.business_transit_hours,
  total_transit_days: f.total_transit_days, business_transit_days: f.business_transit_days,
  sent_at_local: f.sent_at_local, received_at_local: f.received_at_local,
})
