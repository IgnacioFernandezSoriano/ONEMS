// deno-lint-ignore-file no-import-prefix
import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { Sha256, type ShaState } from './sha256.ts'

async function webcrypto(b: Uint8Array): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', b.slice() as Uint8Array<ArrayBuffer>))
  return Array.from(d, (x) => x.toString(16).padStart(2, '0')).join('')
}

// PRNG determinista (mulberry32) para que un fallo sea reproducible.
function rng(seed: number) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
function randomBytes(n: number, r: () => number): Uint8Array {
  const b = new Uint8Array(n)
  for (let i = 0; i < n; i++) b[i] = Math.floor(r() * 256)
  return b
}

Deno.test('known vectors', () => {
  assertEquals(new Sha256().hex(), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
  assertEquals(new Sha256().update(new TextEncoder().encode('abc')).hex(),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
  assertEquals(new Sha256().update(new TextEncoder().encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')).hex(),
    '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1')
})

Deno.test('one shot equals WebCrypto on random data (all lengths 0..300 and some large)', async () => {
  const r = rng(1)
  for (const n of [...Array(301).keys(), 1000, 4095, 4096, 4097, 65536, 1_000_003]) {
    const b = randomBytes(n, r)
    assertEquals(new Sha256().update(b).hex(), await webcrypto(b), `length ${n}`)
  }
})

Deno.test('incremental with serialized state at random boundaries equals WebCrypto', async () => {
  const r = rng(2)
  for (let trial = 0; trial < 60; trial++) {
    const n = Math.floor(r() * 20000)
    const b = randomBytes(n, r)
    let state: ShaState | null = null
    let o = 0
    while (o < n) {
      const step = Math.max(1, Math.floor(r() * (r() < 0.3 ? 70 : 3000)))
      const h = new Sha256(state)
      h.update(b.subarray(o, Math.min(n, o + step)))
      state = JSON.parse(JSON.stringify(h.state()))   // como se guarda en la base (jsonb)
      o += step
    }
    assertEquals(new Sha256(state).hex(), await webcrypto(b), `trial ${trial}, length ${n}`)
  }
})

Deno.test('boundaries at 55/56/63/64/65 bytes and hex() is not destructive', async () => {
  const r = rng(3)
  for (const n of [55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 129]) {
    const b = randomBytes(n * 3, r)
    const h = new Sha256()
    h.update(b.subarray(0, n))
    assertEquals(h.hex(), await webcrypto(b.subarray(0, n)))
    h.update(b.subarray(n))
    assertEquals(h.hex(), await webcrypto(b))
    assertEquals(h.length, n * 3)
  }
})

Deno.test('corrupt state is refused', () => {
  const s = new Sha256().update(new Uint8Array(10)).state()
  assertThrows(() => new Sha256({ ...s, len: 11 }))
  assertThrows(() => new Sha256({ ...s, h: [1, 2, 3] }))
})
