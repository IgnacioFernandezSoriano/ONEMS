import { describe, it, expect } from 'vitest'
import { webcrypto } from 'node:crypto'
import { Sha256, sha256Blob } from '../carrierLink/sha256'

const subtle = (globalThis.crypto?.subtle ?? webcrypto.subtle) as SubtleCrypto

async function reference(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const d = new Uint8Array(await subtle.digest('SHA-256', bytes))
  return [...d].map((b) => b.toString(16).padStart(2, '0')).join('')
}

function bytesOf(n: number, seed = 7): Uint8Array<ArrayBuffer> {
  const out = new Uint8Array(n)
  let x = seed
  for (let i = 0; i < n; i++) {
    x = (x * 1103515245 + 12345) >>> 0
    out[i] = x >>> 24
  }
  return out
}

describe('Sha256 (incremental)', () => {
  it('vectores conocidos', () => {
    expect(new Sha256().digestHex()).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
    expect(new Sha256().update(new TextEncoder().encode('abc')).digestHex()).toBe(
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    )
  })

  it('igual que WebCrypto en tamaños alrededor de los bordes de bloque', async () => {
    for (const n of [1, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 129, 1000, 4097]) {
      const data = bytesOf(n, n)
      expect(new Sha256().update(data).digestHex(), `n=${n}`).toBe(await reference(data))
    }
  })

  it('el resultado no depende de cómo se trocea la entrada', async () => {
    const data = bytesOf(3001)
    const expected = await reference(data)
    for (const step of [1, 3, 63, 64, 65, 500]) {
      const h = new Sha256()
      for (let i = 0; i < data.length; i += step) h.update(data.subarray(i, i + step))
      expect(h.digestHex(), `step=${step}`).toBe(expected)
    }
  })

  it('la huella solo se pide una vez', () => {
    const h = new Sha256()
    h.digestHex()
    expect(() => h.digestHex()).toThrow()
    expect(() => h.update(new Uint8Array(1))).toThrow()
  })
})

describe('sha256Blob (por trozos)', () => {
  it('igual que WebCrypto leyendo el Blob en trozos pequeños, con progreso', async () => {
    const data = bytesOf(10_000)
    const progress: number[] = []
    const hex = await sha256Blob(new Blob([data]), { chunkBytes: 333, onProgress: (d) => progress.push(d) })
    expect(hex).toBe(await reference(data))
    expect(progress.length).toBe(Math.ceil(10_000 / 333))
    expect(progress[progress.length - 1]).toBe(10_000)
    expect(progress.every((v, i) => i === 0 || v > progress[i - 1])).toBe(true)
  })

  it('fichero vacío', async () => {
    expect(await sha256Blob(new Blob([]))).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
  })

  it('se detiene si se cancela', async () => {
    const c = new AbortController()
    c.abort()
    await expect(sha256Blob(new Blob([bytesOf(100)]), { signal: c.signal })).rejects.toMatchObject({ name: 'AbortError' })
  })
})
