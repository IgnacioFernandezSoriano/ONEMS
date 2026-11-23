/**
 * SHA-256 incremental (FIPS 180-4) para la huella de un fichero de entrega en el navegador.
 * WebCrypto (crypto.subtle.digest) solo calcula sobre un buffer entero: con un fichero de 500 MB habria que tenerlo
 * todo en memoria. Aqui se lee el fichero por trozos (Blob.slice) y se va acumulando la huella.
 */

const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01,
  0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08,
  0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
])

export class Sha256 {
  private h = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19])
  private w = new Uint32Array(64)
  private block = new Uint8Array(64)
  private blockLen = 0
  private bytes = 0
  private done = false

  update(data: Uint8Array): this {
    if (this.done) throw new Error('Sha256: digest already taken')
    this.bytes += data.length
    let i = 0
    if (this.blockLen > 0) {
      const take = Math.min(64 - this.blockLen, data.length)
      this.block.set(data.subarray(0, take), this.blockLen)
      this.blockLen += take
      i = take
      if (this.blockLen === 64) {
        this.compress(this.block, 0)
        this.blockLen = 0
      }
    }
    for (; i + 64 <= data.length; i += 64) this.compress(data, i)
    if (i < data.length) {
      this.block.set(data.subarray(i), 0)
      this.blockLen = data.length - i
    }
    return this
  }

  /** Huella en hexadecimal (64 caracteres en minusculas). Solo se puede pedir una vez. */
  digestHex(): string {
    if (this.done) throw new Error('Sha256: digest already taken')
    const bitsHi = Math.floor(this.bytes / 0x20000000)
    const bitsLo = (this.bytes * 8) >>> 0
    const pad = new Uint8Array(this.blockLen < 56 ? 64 - this.blockLen : 128 - this.blockLen)
    pad[0] = 0x80
    const view = new DataView(pad.buffer)
    view.setUint32(pad.length - 8, bitsHi)
    view.setUint32(pad.length - 4, bitsLo)
    const total = this.bytes
    this.update(pad)
    this.bytes = total
    this.done = true
    let out = ''
    for (const x of this.h) out += x.toString(16).padStart(8, '0')
    return out
  }

  private compress(d: Uint8Array, off: number) {
    const w = this.w
    for (let t = 0; t < 16; t++) {
      const j = off + t * 4
      w[t] = (d[j] << 24) | (d[j + 1] << 16) | (d[j + 2] << 8) | d[j + 3]
    }
    for (let t = 16; t < 64; t++) {
      const a = w[t - 15]
      const b = w[t - 2]
      const s0 = ((a >>> 7) | (a << 25)) ^ ((a >>> 18) | (a << 14)) ^ (a >>> 3)
      const s1 = ((b >>> 17) | (b << 15)) ^ ((b >>> 19) | (b << 13)) ^ (b >>> 10)
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) | 0
    }
    const h = this.h
    let a = h[0], b = h[1], c = h[2], e = h[4], f = h[5], g = h[6]
    let dd = h[3], hh = h[7]
    for (let t = 0; t < 64; t++) {
      const S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7))
      const ch = (e & f) ^ (~e & g)
      const t1 = (hh + S1 + ch + K[t] + w[t]) | 0
      const S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10))
      const maj = (a & b) ^ (a & c) ^ (b & c)
      const t2 = (S0 + maj) | 0
      hh = g
      g = f
      f = e
      e = (dd + t1) | 0
      dd = c
      c = b
      b = a
      a = (t1 + t2) | 0
    }
    h[0] = (h[0] + a) | 0
    h[1] = (h[1] + b) | 0
    h[2] = (h[2] + c) | 0
    h[3] = (h[3] + dd) | 0
    h[4] = (h[4] + e) | 0
    h[5] = (h[5] + f) | 0
    h[6] = (h[6] + g) | 0
    h[7] = (h[7] + hh) | 0
  }
}

/** Trozo de lectura por defecto: 4 MiB (no se carga nunca el fichero entero en memoria). */
export const SHA256_CHUNK_BYTES = 4 * 1024 * 1024

/**
 * Huella SHA-256 de un fichero (o Blob) leyendolo por trozos. `onProgress(bytesLeidos, total)` tras cada trozo.
 * Con `signal` abortado se detiene y lanza un Error con name 'AbortError'.
 */
export async function sha256Blob(
  blob: Blob,
  opts: { chunkBytes?: number; onProgress?: (done: number, total: number) => void; signal?: AbortSignal } = {},
): Promise<string> {
  const chunk = Math.max(64, Math.floor(opts.chunkBytes ?? SHA256_CHUNK_BYTES))
  const hash = new Sha256()
  for (let off = 0; off < blob.size; off += chunk) {
    if (opts.signal?.aborted) {
      const e = new Error('aborted')
      e.name = 'AbortError'
      throw e
    }
    const buf = await blob.slice(off, Math.min(off + chunk, blob.size)).arrayBuffer()
    hash.update(new Uint8Array(buf))
    opts.onProgress?.(Math.min(off + chunk, blob.size), blob.size)
  }
  return hash.digestHex()
}
