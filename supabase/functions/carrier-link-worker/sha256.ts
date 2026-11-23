// SHA-256 incremental con estado serializable (WebCrypto no permite hashear por partes entre invocaciones).
// Estado = 8 palabras + bytes pendientes (< 64) + longitud total. Se guarda con el cursor de la carga
// (cl_deliveries.progress->'load'->'sha') y la siguiente invocacion continua donde lo dejo la anterior.

export interface ShaState {
  h: number[]      // 8 palabras de 32 bits (sin signo)
  buf: string      // bytes pendientes en base64 (< 64 bytes)
  len: number      // bytes consumidos en total
}

const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
])
const H0 = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]

function toB64(b: Uint8Array): string {
  let s = ''
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i])
  return btoa(s)
}
function fromB64(s: string): Uint8Array {
  const t = atob(s)
  const out = new Uint8Array(t.length)
  for (let i = 0; i < t.length; i++) out[i] = t.charCodeAt(i)
  return out
}

export class Sha256 {
  private h = new Uint32Array(8)
  private w = new Uint32Array(64)
  private pend = new Uint8Array(64)
  private pendLen = 0
  private total = 0

  constructor(state?: ShaState | null) {
    if (!state) { this.h.set(H0); return }
    if (!Array.isArray(state.h) || state.h.length !== 8 || typeof state.len !== 'number' || state.len < 0) {
      throw new Error('CL_BAD_SHA_STATE')
    }
    for (let i = 0; i < 8; i++) this.h[i] = state.h[i] >>> 0
    const p = fromB64(state.buf ?? '')
    if (p.length >= 64 || p.length !== state.len % 64) throw new Error('CL_BAD_SHA_STATE')
    this.pend.set(p)
    this.pendLen = p.length
    this.total = state.len
  }

  get length(): number { return this.total }

  update(data: Uint8Array): this {
    let i = 0
    const n = data.length
    this.total += n
    if (this.pendLen > 0) {
      const take = Math.min(64 - this.pendLen, n)
      this.pend.set(data.subarray(0, take), this.pendLen)
      this.pendLen += take
      i = take
      if (this.pendLen < 64) return this
      this.block(this.pend, 0)
      this.pendLen = 0
    }
    for (; i + 64 <= n; i += 64) this.block(data, i)
    if (i < n) { this.pend.set(data.subarray(i), 0); this.pendLen = n - i }
    return this
  }

  state(): ShaState {
    return { h: Array.from(this.h), buf: toB64(this.pend.subarray(0, this.pendLen)), len: this.total }
  }

  // No destructivo: se puede seguir actualizando despues.
  hex(): string {
    const c = new Sha256(this.state())
    const bits = c.total * 8
    const padLen = (c.pendLen < 56 ? 56 : 120) - c.pendLen
    const pad = new Uint8Array(padLen + 8)
    pad[0] = 0x80
    const hi = Math.floor(bits / 0x100000000)
    const lo = bits >>> 0
    const dv = new DataView(pad.buffer)
    dv.setUint32(padLen, hi)
    dv.setUint32(padLen + 4, lo)
    c.update(pad)
    let out = ''
    for (let k = 0; k < 8; k++) out += c.h[k].toString(16).padStart(8, '0')
    return out
  }

  private block(b: Uint8Array, o: number) {
    const w = this.w
    for (let t = 0; t < 16; t++) {
      const j = o + t * 4
      w[t] = (b[j] << 24) | (b[j + 1] << 16) | (b[j + 2] << 8) | b[j + 3]
    }
    for (let t = 16; t < 64; t++) {
      const x = w[t - 15], y = w[t - 2]
      const s0 = ((x >>> 7) | (x << 25)) ^ ((x >>> 18) | (x << 14)) ^ (x >>> 3)
      const s1 = ((y >>> 17) | (y << 15)) ^ ((y >>> 19) | (y << 13)) ^ (y >>> 10)
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) | 0
    }
    const h = this.h
    let a = h[0] | 0, bb = h[1] | 0, c = h[2] | 0, d = h[3] | 0, e = h[4] | 0, f = h[5] | 0, g = h[6] | 0, hh = h[7] | 0
    for (let t = 0; t < 64; t++) {
      const S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7))
      const ch = (e & f) ^ (~e & g)
      const t1 = (hh + S1 + ch + K[t] + w[t]) | 0
      const S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10))
      const maj = (a & bb) ^ (a & c) ^ (bb & c)
      const t2 = (S0 + maj) | 0
      hh = g; g = f; f = e; e = (d + t1) | 0; d = c; c = bb; bb = a; a = (t1 + t2) | 0
    }
    h[0] = (h[0] + a) | 0; h[1] = (h[1] + bb) | 0; h[2] = (h[2] + c) | 0; h[3] = (h[3] + d) | 0
    h[4] = (h[4] + e) | 0; h[5] = (h[5] + f) | 0; h[6] = (h[6] + g) | 0; h[7] = (h[7] + hh) | 0
  }
}
