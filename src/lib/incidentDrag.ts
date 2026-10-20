import type { DragEvent } from 'react'
import type { MoveDragPayload } from '@/lib/types'

// Arrastrar y soltar (HTML5 nativo) de lineas / muestras a las casillas del balance de la ciudad.
// Tipo propio para no aceptar arrastres ajenos (texto, ficheros...).
export const DRAG_MIME = 'application/x-onems-move'

// Inicia el arrastre: carga JSON en un tipo propio + text/plain (Firefox no arranca sin datos).
export function startMoveDrag(e: DragEvent, payload: MoveDragPayload): void {
  e.dataTransfer.effectAllowed = 'move'
  e.dataTransfer.setData(DRAG_MIME, JSON.stringify(payload))
  e.dataTransfer.setData('text/plain', payload.label)
}

// Lee la carga del arrastre al soltar; null si no es nuestra o no es valida.
export function readDragPayload(e: DragEvent): MoveDragPayload | null {
  try {
    const raw = e.dataTransfer.getData(DRAG_MIME)
    if (!raw) return null
    const p = JSON.parse(raw)
    if ((p?.kind === 'line' || p?.kind === 'sample') && typeof p.detailId === 'string'
        && typeof p.fromNodeId === 'string' && (p.kind !== 'line' || typeof p.lineId === 'string')) {
      return p as MoveDragPayload
    }
  } catch { /* carga ajena */ }
  return null
}
