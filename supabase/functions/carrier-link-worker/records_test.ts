// deno-lint-ignore-file no-import-prefix
import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { parseCsvFields, parseCsvHeader, splitRecords, toRecord } from './records.ts'

const enc = (s: string) => new TextEncoder().encode(s)
const lines = (s: string, f: 'jsonl' | 'csv', last: boolean) => {
  const b = enc(s)
  const { spans, consumed } = splitRecords(b, f, last)
  return { recs: spans.map((x) => new TextDecoder().decode(b.subarray(x.start, x.end))), consumed }
}

Deno.test('jsonl: LF, CRLF, partial last line kept for the next chunk', () => {
  assertEquals(lines('{"a":1}\n{"a":2}\r\n{"a"', 'jsonl', false), { recs: ['{"a":1}', '{"a":2}'], consumed: 17 })
  assertEquals(lines('{"a":1}\n{"a":2}', 'jsonl', true), { recs: ['{"a":1}', '{"a":2}'], consumed: 15 })
  assertEquals(lines('{"a":1}\r\n', 'jsonl', true), { recs: ['{"a":1}'], consumed: 9 })
  assertEquals(lines('', 'jsonl', true), { recs: [], consumed: 0 })
})

Deno.test('csv: newline inside quotes does not end the record', () => {
  const r = lines('a,b\r\n"x\ny",2\r\n"open\n', 'csv', false)
  assertEquals(r.recs, ['a,b', '"x\ny",2'])
  assertEquals(r.consumed, 14)
})

Deno.test('csv fields: quotes, escaped quotes, commas, empty fields, malformed', () => {
  assertEquals(parseCsvFields('a,"b,c","d ""q""",,e'), ['a', 'b,c', 'd "q"', '', 'e'])
  assertEquals(parseCsvFields('a,'), ['a', ''])
  assertEquals(parseCsvFields('"multi\nline",1'), ['multi\nline', '1'])
  assertEquals(parseCsvFields('"open'), null)
  assertEquals(parseCsvFields('"x"y,1'), null)
  assertEquals(parseCsvFields('a"b,1'), null)
})

Deno.test('csv header: trimmed names, duplicates and blanks refused', () => {
  assertEquals(parseCsvHeader(' trk ,ts'), ['trk', 'ts'])
  assertThrows(() => parseCsvHeader('trk,trk'))
  assertThrows(() => parseCsvHeader('trk,,ts'))
})

Deno.test('records keep only allowed fields; unreadable records are null', () => {
  const allowed = new Set(['trk', 'ts'])
  assertEquals(toRecord('{"trk":"A","ts":"t","name":"Juan"}', 'jsonl', null, allowed), { trk: 'A', ts: 't' })
  assertEquals(toRecord('[1,2]', 'jsonl', null, allowed), null)
  assertEquals(toRecord('not json', 'jsonl', null, allowed), null)
  assertEquals(toRecord('A,,Juan', 'csv', ['trk', 'ts', 'name'], allowed), { trk: 'A' })
  assertEquals(toRecord('A,t', 'csv', ['trk', 'ts', 'name'], allowed), null)
})
