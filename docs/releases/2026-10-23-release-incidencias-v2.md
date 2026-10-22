# Release 2026-10-23 — Incidencias reportadas v2, conversación, materiales y ayuda

**Activación prevista:** jueves 23 de octubre de 2026 (merge de `develop` a `main`; Netlify despliega `main`).
**Estado el 22/10:** backend (BD onems-dev) y bot de Telegram (n8n PROD) ya en producción desde el 22/10. Falta solo el frontend.

## Cómo abrir el PR (no hay `gh` instalado)

1. Abrir <https://github.com/IgnacioFernandezSoriano/ONEMS/compare/main...develop>
2. "Create pull request" con el título y la descripción de abajo.
3. **No hacer merge hasta mañana 23/10.** El merge activa el despliegue de producción.

### Título

`Release 2026-10-23: incidencias reportadas v2, conversación con el panelista, materiales y ayuda en 4 idiomas`

### Descripción

```
## Qué incluye (55 commits de develop, 50 archivos)

### Incidencias reportadas por el panelista (v2)
- Lista con filtros por categoría y estado; detalle con cabecera de contacto y papel (emisor/receptor), texto y foto.
- Bloque de acción por categoría: devuelto (reenviar a otro nodo de la misma ciudad y semana, o anular), automáticas en solo lectura (antes/después de contacto, envío elegido), resto solo soporte.
- Estado auto_resolved; primera acción pasa la incidencia a "en curso".

### Falta de material
- Asistente en tres secciones: stock teórico, necesidad del periodo y suministro (vecinos → central → compra, origen editable), replanificar (baja por materiales).
- Hoja de envíos de material (pantalla, PDF, Excel/CSV), estados pending/sent/partially_received/received/cancelled, "Marcar enviado" para central.
- Stock comprometido descontado, guardas de doble clic, envíos de incidencia protegidos desde Stock.

### Conversación con el panelista (todas las incidencias)
- Panel de conversación en cada incidencia (bot, panelista, manager, fotos); envío al panelista por Telegram.
- Respuestas sin leer: etiqueta "New reply", badge azul en el menú; marcado como leído al abrir.

### Ayuda
- Página "Help: Incidents" en EN/ES/FR/AR (árabe en RTL) con maquetas de todas las pantallas y del bot; el menú abre la del idioma activo.

### Base de datos / n8n
- Migraciones ya aplicadas en onems-dev (20261020170000, 20261021120000, 20261022100000).
- Workflows n8n ya promovidos a PROD el 22/10 (Report incident, Material receipt, Deliver incident messages, Material questions, Notify unread incident replies, main, On new parcel to send).

## Verificación
- npm run lint: 0 errores, 48 avisos (línea base).
- npm run build: OK.
- Pruebas de pantalla en DEMO2: pendientes (docs/integrations/2026-10-22-plan-pruebas-demo2-incidencias-v2.md). Decisión del responsable: pasar a producción y probar en vivo.

## Vuelta atrás
- Frontend: revertir el merge en main (Netlify redespliega). BD y n8n no cambian con este PR.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## Plan de activación del 23/10

| Paso | Quién | Qué |
|---|---|---|
| 1 | Responsable | Merge del PR en GitHub (botón "Merge pull request"). |
| 2 | Netlify | Despliega `main` solo (2–4 min). Comprobar en el panel de Netlify que el deploy termina en "Published". |
| 3 | Responsable / Claude | Prueba mínima en producción: entrar como manager, abrir Incidents › Reported incidents y Panelist availability, abrir Help: Incidents en ES y en AR, enviar un mensaje de prueba a PAN-DEM-003 desde una incidencia de DEMO2 y ver que llega al bot. |
| 4 | Responsable | Enviar la comunicación a usuarios (briefing ya preparado; fecha = 23/10/2026). |
| 5 | Claude | Retirar el workflow antiguo "Deliver incident replies" (zpCm5uOEeDTXUIco) unos días después, cuando se confirme que el nuevo entrega bien. |

## Si algo falla el 23/10
- Pantalla: revertir el merge en GitHub ("Revert") → Netlify vuelve a la versión anterior.
- Bot: restaurar workflows desde `panelist_n8n/workflows/backups/prod-before-promotion/`.
- BD: no hay que tocar nada (las migraciones son compatibles con la pantalla anterior).
